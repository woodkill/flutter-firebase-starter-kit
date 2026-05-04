import {getAuth} from "firebase-admin/auth";
import {Firestore, FieldValue} from "firebase-admin/firestore";

/**
 * Identity Index 컬렉션 키 형식 (Phase 12 D-09 — Phase 13~17 영구 고정).
 *
 * `identity_index/{provider}:{providerUserId}` 단일 문서 ID. Phase 12 가 첫
 * 등록자 (Kakao). Phase 13~16 (Naver/LINE/Yahoo!JP/WeChat) + Phase 17
 * (Native 4 provider 회고적 등록) 모두 동일 컬렉션 공유. 키 형식 변경은
 * 데이터 마이그레이션 의무 발생.
 *
 * @param {string} provider provider 슬러그 (예: "kakao").
 * @param {string} providerUserId IdP 가 발급한 사용자 식별자
 *     (Kakao = ID Token sub 클레임).
 * @return {string} Firestore 문서 ID 문자열.
 */
export function identityIndexDocId(
  provider: string,
  providerUserId: string,
): string {
  return `${provider}:${providerUserId}`;
}

/** Identity Index 조회 결과. */
export type IdentityResolution = {
  uid: string;
  isNewUser: boolean;
};

/**
 * Identity Index lookup-first + seed UID + Pitfall 4 회피 (D-10, D-13).
 *
 * 흐름:
 * 1. transaction 외부에서 비-tx read 로 미존재 + caller 없음 인지 시
 *    `admin.auth().createUser()` 1회 호출 — transaction body 외부에서.
 *    (Pitfall 4 회피 — Firestore runTransaction 은 default 5회 retry 이고
 *    transaction body 안에서 createUser 호출 시 retry 마다 신규 사용자
 *    생성 위험.)
 * 2. transaction 내부에서 tx.get → existence check → tx.set:
 *    - 존재: existing.firebaseUid 반환 (D-12 first-write-wins)
 *    - 미존재 + callerUid 있음: callerUid 사용
 *    - 미존재 + 미인증 호출: 사전 createUser uid 사용
 *    - tx.set(idxRef, {firebaseUid, provider, providerUserId, linkedAt,
 *      lastSeenAt})
 *    - tx.set(userRef, {linkedProviders: arrayUnion({providerId,
 *      providerUserId})}, {merge: true})  ← Pitfall 12 (Plan 10-12
 *      mirrorToFirestore race 방어)
 *    - tx.set(userRef, {providerLinkedAt: {[providerId]: serverTimestamp()}},
 *      {merge: true})  ← Pitfall 5 회피 (linkedAt 별도 map)
 *
 * Phase 14 LINE 진입 시 본 helper 의 시그니처가 일반화 표본 (D-08).
 *
 * **race window 분석 (preCreatedUid 패턴, Pitfall 4):** 동시 호출자 2명이
 * 같은 providerUserId 로 진입 시 createUser 가 2회 호출될 수 있다 (둘 다
 * 비-tx read 시점에 미존재 관측). transaction first-write-wins 가 두 uid
 * 중 하나만 채택, 다른 uid 는 orphan 사용자 로 남는다. Phase 17 cleanup
 * TODO — periodic sweep 또는 onAuthCreate 트리거 검사.
 *
 * @param {Firestore} db Firestore Admin 인스턴스.
 * @param {{provider: string, providerUserId: string,
 *     callerUid: (string|undefined)}} args lookup 인자.
 * @return {Promise<IdentityResolution>} Firebase UID + 신규 등록 여부.
 */
export async function resolveIdentity(
  db: Firestore,
  args: {
    provider: string;
    providerUserId: string;
    callerUid: string | undefined;
    /**
     * IdP 가 ID Token 으로 제공한 사용자 정보 (옵션).
     *
     * Kakao 일반 앱: email 동의항목 disable 이라 보통 undefined.
     * Kakao 비즈 앱 + email 필수 동의: ID Token 의 email claim 으로부터 채워짐.
     * Phase 13~16 의 다른 provider 도 동일 매개변수 사용.
     */
    userInfo?: {email?: string};
  },
): Promise<IdentityResolution> {
  const {provider, providerUserId, callerUid, userInfo} = args;
  const idxRef = db
    .collection("identity_index")
    .doc(identityIndexDocId(provider, providerUserId));
  const userRefFor = (uid: string) => db.collection("users").doc(uid);

  // Step 1: 비-tx read — Pitfall 4 (transaction retry 시 createUser 다중호출)
  // 회피. 미존재 + 미인증 → createUser 1회 사전 호출.
  //
  // emailVerified: true — OAuth Custom Token 사용자는 외부 IdP (Kakao 등) 가
  // 인증을 책임지므로 verified 상태로 간주. 이게 없으면 Firebase Auth 의
  // default emailVerified=false 가 client-side router 의 verify-email
  // 분기를 트리거 (Phase 12-04 retroactive gap closure). 본 starter kit 의
  // 모든 OAuth Custom Token provider (Phase 13~16) 에 동일 패턴 적용.
  //
  // email 매개변수 — userInfo.email 이 제공되면 Firebase Auth user.email
  // 에 저장. starter kit 의 dev 단계 (일반 앱) 는 카카오 동의항목에 이메일
  // 비활성이라 undefined → email 미저장. 비즈 앱 전환 후 ID Token 에 email
  // claim 포함 시 자동으로 user.email 에 저장됨. 동일 이메일로 기존 user
  // 존재 시 createUser 가 `auth/email-already-in-use` throw — account
  // linking 정책은 별도 phase (백로그).
  let preCreatedUid: string | null = null;
  const idxSnapPre = await idxRef.get();
  if (!idxSnapPre.exists && !callerUid) {
    const created = await getAuth().createUser({
      emailVerified: true,
      ...(userInfo?.email ? {email: userInfo.email} : {}),
    });
    preCreatedUid = created.uid;
  }

  // Step 2: race-safe transaction — first-write-wins (D-12, D-13).
  return db.runTransaction(async (tx) => {
    const idxSnap = await tx.get(idxRef);
    const now = FieldValue.serverTimestamp();
    if (idxSnap.exists) {
      const existing = idxSnap.data() as {firebaseUid: string};
      tx.update(idxRef, {lastSeenAt: now});
      return {uid: existing.firebaseUid, isNewUser: false};
    }

    // 신규 등록 — uid 결정 우선순위: callerUid → preCreatedUid.
    const newUid = callerUid ?? preCreatedUid;
    if (!newUid) {
      // 본 분기는 Pitfall 4 회피 단계가 빠진 경우만 도달 — 방어 throw.
      throw new Error(
        "identity_index: createUser pre-step missed " +
          "(Pitfall 4 mitigation broken)",
      );
    }

    tx.set(idxRef, {
      firebaseUid: newUid,
      provider,
      providerUserId,
      linkedAt: now,
      lastSeenAt: now,
    });

    // Pitfall 12 (Plan 10-12 mirrorToFirestore race): set-merge 의무.
    // Pitfall 5 (arrayUnion deep-eq false-positive): 객체 스키마는
    // {providerId, providerUserId} 만 — linkedAt 은 별도 map.
    tx.set(
      userRefFor(newUid),
      {
        linkedProviders: FieldValue.arrayUnion({
          providerId: provider,
          providerUserId,
        }),
        providerLinkedAt: {[provider]: now},
      },
      {merge: true},
    );

    return {uid: newUid, isNewUser: true};
  });
}
