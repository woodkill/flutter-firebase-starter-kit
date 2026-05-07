import {getAuth} from "firebase-admin/auth";
import {Firestore, FieldValue} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";

/**
 * Identity Index 컬렉션 키 형식 (Phase 12 D-09 — Phase 13~17 영구 고정).
 *
 * `identity_index/{provider}:{providerUserId}` 단일 문서 ID. Phase 12 가 첫
 * 등록자 (Kakao). Phase 13~16 (Naver/LINE/Yahoo!JP/WeChat) + Phase 17
 * (Account Linking — Native 4 provider 회고적 등록) — see ROADMAP.md, 모두
 * 동일 컬렉션 공유. 키 형식 변경은 데이터 마이그레이션 의무 발생.
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

/**
 * Identity Index 조회 결과.
 *
 * R3 (Phase 12.1-06 / BL-04 + WR-06, D-32) — `conflictKind` 필드 추가.
 * helper 는 충돌을 *detect* 만 한다 (HttpsError throw 책임은 caller).
 *
 * - `null` — 정상 path (충돌 없음).
 * - `'email_in_use'` — `createUser` 가 `auth/email-already-in-use` rejection.
 *   Kakao ID Token 의 email 이 기존 Firebase Auth 사용자 (다른 provider 또는
 *   email/password 로 가입한 사용자) 의 email 과 일치. caller 는 안전한
 *   `already-exists` HttpsError 로 변환 (email enumeration 차단).
 * - `'anonymous_existing_collision'` — 익명 사용자 (`callerUid` 가 anonymous
 *   uid) 가 *기존* identity_index 매핑이 존재하는 provider 사용자로 로그인
 *   시도. helper 는 first-write-wins 로 existing.firebaseUid 를 반환하지만,
 *   caller 가 anonymous Firestore 데이터 손실 / UID hijack 위험을 인지하고
 *   `already-exists` HttpsError throw (Phase 17 Account Linking 이 자동
 *   마이그레이션 처리).
 *
 * D-33 (layering) — helper 가 `firebase-functions/https` import 미추가. caller
 * 가 conflictKind 보고 정책 (throw / migrate / link) 자유롭게 선택. Phase
 * 13~16 의 다른 provider 가 동일 helper 재사용 시 동일 conflictKind 자동 상속.
 */
export type IdentityResolution = {
  uid: string;
  isNewUser: boolean;
  conflictKind: "email_in_use" | "anonymous_existing_collision" | null;
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
 * 중 하나만 채택, 다른 uid 는 orphan 사용자 로 남는다. 본 helper 가 post-tx
 * best-effort cleanup 처리 (Phase 12.1 R2 — see ROADMAP.md). race-loser 가
 * cleanup 실패 시에도 다음 race 호출에서 재시도 가능 (idempotent).
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
     * IdP 가 제공한 사용자 프로필 정보 (옵션).
     *
     * - email: Kakao 일반 앱: undefined (동의항목 disable). 비즈 앱 + 동의:
     *   ID Token email claim. Naver: `/v1/nid/me` response.email (동의 항목).
     * - displayName: 사용자 닉네임 (Kakao OIDC `name`/`nickname` claim, Naver
     *   response.nickname). Firebase Auth user.displayName 에 저장.
     * - photoURL: 프로필 사진 URL (Kakao OIDC `picture` claim, Naver
     *   response.profile_image). Firebase Auth user.photoURL 에 저장.
     *
     * R10 (Phase 13 retroactive — 12-UAT 가 nickname/email/photo UI 표시
     * 검증 누락 → Phase 12 + 13 양쪽 재발현). 모든 OAuth Custom Token
     * provider (Phase 13~16) 에 동일 매개변수 사용.
     */
    userInfo?: {email?: string; displayName?: string; photoURL?: string};
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
  // R10: email + displayName + photoURL 을 createUser 시점에 set —
  // !callerUid path 의 신규 user record 가 nickname/이메일/프로필 사진 모두
  // Firebase Auth 에 저장되도록 한다. Phase 12 가 email 만 처리해서 12-UAT
  // 가 nickname/photo 검증 누락 → 13-UAT 시나리오 2 에서 처음 노출.
  const profileFields: {
    email?: string;
    displayName?: string;
    photoURL?: string;
  } = {};
  if (userInfo?.email) profileFields.email = userInfo.email;
  if (userInfo?.displayName) profileFields.displayName = userInfo.displayName;
  if (userInfo?.photoURL) profileFields.photoURL = userInfo.photoURL;

  let preCreatedUid: string | null = null;
  const idxSnapPre = await idxRef.get();
  if (!idxSnapPre.exists && !callerUid) {
    try {
      const created = await getAuth().createUser({
        emailVerified: true,
        ...profileFields,
      });
      preCreatedUid = created.uid;
    } catch (err: unknown) {
      // R3 (Phase 12.1-06 / BL-04, D-32) — email collision detect.
      // Kakao 비즈 앱 + email 필수 동의 시 ID Token 의 email claim 이
      // 기존 Firebase Auth user.email 과 일치하면 createUser 가
      // `auth/email-already-in-use` throw. helper 는 conflictKind 로 *detect*
      // 만 하고 caller 가 안전한 already-exists HttpsError 로 변환
      // (email enumeration 차단 + 사용자 recovery 가능).
      //
      // **D-33** — `firebase-functions/https` import 미추가 — helper 는
      // 도메인 layer (Firestore / firebase-admin) 만 의존. caller 가
      // HTTP 응답 layer 책임.
      if (
        err instanceof Error &&
        (err as {code?: string}).code === "auth/email-already-in-use"
      ) {
        return {
          // caller 가 사용 안 함 — switch (conflictKind) 가 우선해서 throw.
          uid: "",
          isNewUser: false,
          conflictKind: "email_in_use" as const,
        };
      }
      // 그 외 에러 (e.g., 'auth/internal-error', network) 는 caller 가 catch
      // 하여 internal 매핑.
      throw err;
    }
  }

  // Step 2: race-safe transaction — first-write-wins (D-12, D-13).
  const result = await db.runTransaction(async (tx) => {
    const idxSnap = await tx.get(idxRef);
    const now = FieldValue.serverTimestamp();
    if (idxSnap.exists) {
      const existing = idxSnap.data() as {firebaseUid: string};
      // R3 (Phase 12.1-06 / WR-06, D-32) — anonymous + existing kakao
      // identity 충돌 detect. callerUid (익명 사용자 uid) 가 있고 existing
      // identity 가 *다른* Firebase user 와 매핑 → first-write-wins 로
      // existing.firebaseUid 반환은 유지하지만 conflictKind 로 caller 에
      // 충돌 사실 전달. caller 는 anonymous 데이터 보존 후 already-exists
      // throw — Phase 17 (Account Linking) 가 자동 마이그레이션 처리.
      //
      // R12 (Phase 13 retroactive — 12.1 R3 안전 차단 정밀화):
      // anonymous B 의 Firestore users/<callerUid> 문서가 비어있으면 (sign-out
      // 직후 자동 재생성된 빈 익명 user) collision 차단 불필요 — existing.
      // firebaseUid 재사용으로 sign-in 허용 (시나리오 3 "재로그인 동일 UID").
      // 데이터 있으면 12.1 R3 의 보안 차단 그대로 (Phase 17 Account Linking
      // 이 자동 마이그레이션). check 는 transaction 내부 — consistency 보장.
      //
      // **Firestore transaction "all reads before all writes" 제약**:
      // tx.update / tx.set 의 *write* 가 호출되기 전에 모든 추가 read 를
      // 완료해야 한다. callerUserSnap read 는 tx.update(idxRef, lastSeenAt)
      // 보다 위에 위치해야 violation 회피 (mock test 는 이 제약을 강제하지
      // 않아 R12 첫 구현에서 누락 → 13-UAT 시나리오 3 시 실 단말 통신 시점에
      // 노출됨).
      let callerHasData = false;
      if (callerUid && existing.firebaseUid !== callerUid) {
        const callerUserSnap = await tx.get(userRefFor(callerUid));
        callerHasData = callerUserSnap.exists;
      }
      tx.update(idxRef, {lastSeenAt: now});
      if (callerUid && existing.firebaseUid !== callerUid && callerHasData) {
        return {
          uid: existing.firebaseUid,
          isNewUser: false,
          conflictKind: "anonymous_existing_collision" as const,
        };
      }
      // 정상 path — existing 재사용 (callerUid 없음, callerUid===existing,
      // 또는 R12 우회 path = 빈 anonymous B).
      return {
        uid: existing.firebaseUid,
        isNewUser: false,
        conflictKind: null,
      };
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

    return {uid: newUid, isNewUser: true, conflictKind: null};
  });

  // Step 3 (R2 — D-31): post-tx best-effort orphan cleanup.
  // transaction first-write-wins 결과 result.uid 가 preCreatedUid 와 다르면
  // preCreatedUid 는 race-loser orphan Firebase Auth user. best-effort 로
  // 삭제 — 실패해도 outer caller (kakaoCustomToken) 의 정상 path 차단 안 함.
  // idempotent — 다음 race 호출에서 재시도 가능.
  // **Pitfall 4 보존:** 본 블록은 db.runTransaction(...) 외부 — preCreatedUid
  // scope (line 102) 도 transaction body 외부. cleanup 을 transaction body
  // 안으로 절대 이동 금지 (retry 마다 deleteUser 다중호출 위험).
  if (preCreatedUid && result.uid !== preCreatedUid) {
    try {
      await getAuth().deleteUser(preCreatedUid);
    } catch (cleanupErr: unknown) {
      // **Pitfall 7 보존:** err.message 는 본문이 PII 일 가능성 (e.g.
      // 'user not found for uid abc...') — 절대 로깅 금지. err.code
      // (firebase-admin standard) 또는 err.name 만 short fingerprint 노출.
      const errCode =
        cleanupErr instanceof Error ?
          (cleanupErr as {code?: string}).code ?? cleanupErr.name :
          "unknown";
      logger.warn(
        {
          event: "identity_index_orphan_cleanup_failed",
          uid: preCreatedUid,
          code: errCode,
        },
        "orphan user cleanup failed",
      );
      // 의도적으로 재던지지 않음 — outer call 정상 반환 보장.
    }
  }

  // R9 (Phase 13 retroactive — Pitfall 9 두 번째 path):
  // callerUid (anonymous user) + 신규 identity 등록 시 anonymous user
  // record 의 emailVerified=false 가 그대로 남아 client-side router 의
  // verify-email gate (auth_guard 분기 4) 가 잘못 트리거. transaction
  // 외부 (Pitfall 4 — retry 시 다중 호출 회피) 에서 updateUser 로 갱신.
  // strict — 실패 시 throw → caller 가 createCustomToken 차단 + internal
  // 매핑 (emailVerified=false 인 social user 가 Home 진입하는 보안 회귀
  // 차단). !callerUid path 는 createUser({emailVerified: true}) 로 처리.
  // 12-04 retroactive fix 가 한 path 만 커버 + 12-UAT 가 재로그인 path
  // 만 검증 → buggy "anonymous→소셜 첫 로그인" path 가 가려졌던 회귀.
  // helper 자체에 fix → kakao + naver + Phase 14~16 자동 상속 (D-08).
  //
  // R10 (Phase 13 retroactive): emailVerified 외에 email/displayName/
  // photoURL 도 동시 갱신. anonymous user 는 첫 익명 로그인 시점에 user
  // record 가 비어있어 displayName/email/photoURL 이 없는 채로 남아
  // EnvironmentInfoScreen 의 닉네임/이메일/프로필 사진 카드가 비어 보임.
  // 12-UAT 의 검증 누락 → Phase 13 첫 anonymous→소셜 로그인 시 처음 노출.
  if (result.isNewUser && callerUid) {
    await getAuth().updateUser(callerUid, {
      emailVerified: true,
      ...profileFields,
    });
  }

  return result;
}
