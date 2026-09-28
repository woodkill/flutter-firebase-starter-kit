import {getAuth} from "firebase-admin/auth";
import {Firestore, FieldValue} from "firebase-admin/firestore";
import type {DocumentSnapshot} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";

/**
 * IdP 측 프로필 변경의 starter-kit 측 동기화 정책 (R10-FOLLOWUP, 2026-05-08).
 *
 * 재로그인 시 (resolveIdentity 의 isNewUser=false path) IdP 응답의
 * displayName/photoURL 을 Firebase Auth user record 에 어떻게 반영할지 결정.
 *
 * - **"truth-of-source"** (default): IdP 응답을 진실로. 응답에 필드가 있으면
 *   해당 값으로 update, 없으면 명시 `null` 로 clear (Slack/Discord 등
 *   production app 의 일반 default + GDPR Art. 17 친화).
 *   사용자가 IdP 측에서 프로필 이미지/닉네임을 *삭제* → 다음 로그인에
 *   starter-kit 측에서도 즉시 clear.
 * - **"preserve"**: 응답에 필드가 있으면 update, 없으면 기존 값 보존. 동의
 *   항목 일시 OFF/ON 빈번한 도메인 (일부 B2B 툴 등) 에서 데이터 안정성
 *   우선. 단점: 사용자가 IdP 에서 프로필 *삭제* 의도 reflect 안 됨.
 *
 * **email 은 정책 무관 — 비우지 않는다**: IdP 가 email 을 주면 그 값으로
 * 갱신하고, 주지 않으면 기존 값을 그대로 둔다 (clear 하지 않음 — sign-in
 * 식별자라 clear 시 user lockout 위험, 다음 로그인에 email 매칭 안 되면 새
 * user record 충돌 가능). 이 갱신도 가입 수단 로그인 때만 일어난다 (아래
 * 적용 조건). 정책은 displayName / photoURL 에만 적용.
 *
 * **적용 조건 (quick 260928-jwe)**: 재로그인 갱신은 가입 수단
 * (`users/{uid}.signUpProviderId`) 으로 로그인할 때만 적용한다. 연결 수단
 * (가입 수단이 아닌 provider) 으로 로그인하면 email 포함 갱신 0. 가입 수단
 * 기록이 없거나 읽기에 실패하면 보존한다 (fail-closed). 원칙 — Auth
 * top-level email · 이름 · 사진은 가입 수단 기준의 계정당 1개 대표값이며
 * 로그인 수단과 무관하다.
 *
 * 첫 등록 path (createUser, isNewUser=true) 는 정책과 무관 — falsy 필드는
 * 단순 미설정 (R10 패턴 유지).
 *
 * **starter-kit 사용자 customization 영역**: 자기 앱 도메인에 맞춰 본 상수
 * 한 줄 변경. manual.md "## IdP 프로필 동기화 정책" 절 참고.
 */
export type ProfileRefreshPolicy = "truth-of-source" | "preserve";
export const PROFILE_REFRESH_POLICY: ProfileRefreshPolicy = "truth-of-source";

/**
 * 재로그인 시 Firebase Auth `updateUser` 에 전달할 프로필 필드 객체 생성
 * (R10-FOLLOWUP pure helper).
 *
 * 정책 분기 결과를 객체로 반환 — `Object.keys(...).length === 0` 이면 caller
 * 가 `updateUser` 호출 자체를 skip 한다 (preserve + 모든 필드 부재 케이스).
 * 호출 조건 (가입 수단 로그인 — quick 260928-jwe) 은 caller `resolveIdentity`
 * 가 판정한다 — 이 helper 는 정책 분기만 한다.
 *
 * @param {ProfileRefreshPolicy} policy 정책 — "truth-of-source" | "preserve".
 * @param {{email: (string|undefined), displayName: (string|undefined),
 *     photoURL: (string|undefined)}} userInfo IdP 응답에서 추출한 프로필
 *     필드. 모든 필드 optional.
 * @return {{email: (string|undefined),
 *     displayName: (string|null|undefined),
 *     photoURL: (string|null|undefined)}} updateUser 에 그대로 전달 가능한
 *     객체. `null` 명시 = Firebase Auth user record 에서 해당 필드 clear.
 *     필드 부재 = 보존.
 */
export function profileFieldsForRefresh(
  policy: ProfileRefreshPolicy,
  userInfo: {email?: string; displayName?: string; photoURL?: string},
): {
  email?: string;
  displayName?: string | null;
  photoURL?: string | null;
} {
  const update: {
    email?: string;
    displayName?: string | null;
    photoURL?: string | null;
  } = {};
  // email — sign-in 식별자, 정책 무관 · 비우지 않는다 (있으면 update,
  // 없으면 미포함 = 기존 값 유지). clear 시 user lockout 위험.
  if (userInfo.email) update.email = userInfo.email;
  if (policy === "truth-of-source") {
    // 응답 부재 시 명시 null clear (Firebase Auth updateUser spec — null 은
    // 해당 필드 unset).
    update.displayName = userInfo.displayName ?? null;
    update.photoURL = userInfo.photoURL ?? null;
  } else {
    // preserve — 응답 있으면 update, 없으면 미포함 (Firebase Auth updateUser
    // 가 미명시 필드 보존).
    if (userInfo.displayName) update.displayName = userInfo.displayName;
    if (userInfo.photoURL) update.photoURL = userInfo.photoURL;
  }
  return update;
}

/**
 * Identity Index 컬렉션 키 형식 (Phase 12 D-09 — Phase 13~17 영구 고정).
 *
 * `identity_index/{provider}:{providerUserId}` 단일 문서 ID. Phase 12 가 첫
 * 등록자 (Kakao). Phase 13~14 (Naver/LINE) + Phase 16
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
 * unknown 에러를 logger.code 필드용 fingerprint 문자열로 변환 (WR-07).
 *
 * 비-Error throw (Symbol / null / undefined / primitive) 도 명시 fingerprint
 * 부여하여 firebase-admin 비정상 throw 경로를 ops triage 에서 분간 가능하게
 * 한다. `err as {code?: string}` 식 unchecked assertion 패턴을 본 helper 로
 * 일원화 — cloud-functions-typescript.md "as 타입 단언 최소화" / "any 사용
 * 금지" 규칙 정합.
 *
 * **PII 정책 (D-51 / Pitfall 7)**: 본 함수는 fingerprint *문자열* 만 반환
 * 하며 err.message / payload / claim 등 본문은 절대 노출하지 않는다.
 *
 * @param {unknown} err catch (err: unknown) 의 err.
 * @return {string} logger.code 필드용 short fingerprint
 *     ('auth/user-not-found' / 'TypeError' / 'string-thrown' / 'null-thrown'
 *      / 'non-error-thrown' / 'unknown' 등).
 */
export function fingerprintError(err: unknown): string {
  if (err instanceof Error) {
    // firebase-admin / firebase-functions Error 는 code 프로퍼티가 stable
    // public API. instanceof Error 가드 통과 후 code 안전 접근.
    const code = (err as Error & {code?: unknown}).code;
    if (typeof code === "string" && code.length > 0) return code;
    return err.name;
  }
  if (typeof err === "string") return "string-thrown";
  if (err === null) return "null-thrown";
  if (err === undefined) return "undefined-thrown";
  return "non-error-thrown";
}

/**
 * 재로그인 계정의 가입 수단 read 결과 (quick 260928-jwe).
 *
 * - `found`: `users/{uid}.signUpProviderId` 가 비어 있지 않은 문자열.
 * - `missing`: 문서 없음 · 필드 없음 · 문자열 아님 · 빈 문자열.
 * - `read_failed`: Firestore read 실패 — `code` 는 fingerprintError 결과만.
 */
type SignUpProviderRead =
  | {kind: "found"; providerId: string}
  | {kind: "missing"}
  | {kind: "read_failed"; code: string};

/**
 * 재로그인 계정의 가입 수단(`users/{uid}.signUpProviderId`)을 읽는다
 * (quick 260928-jwe — 가입 수단 로그인 때만 프로필 갱신).
 *
 * **transaction 밖 전용 (Pitfall 4)**: caller 는 `db.runTransaction(...)` 이
 * 끝난 뒤 best-effort 프로필 refresh 블록에서만 부른다. transaction body 안에
 * 두면 retry 마다 중복 read 가 생기고 "all reads before all writes" 제약
 * (WR-05) 과도 충돌한다 — 갱신 자체가 tx 밖 best-effort 이므로 tx 에 넣을
 * 이유가 없다.
 *
 * **fail-closed (절대 throw 하지 않음)**: read 실패 · 기록 없음은 호출자가
 * 「갱신하지 않음(보존)」 으로 처리하도록 판정값으로 돌려준다. 로그인 자체는
 * 이 read 의 성패와 무관하게 계속된다. 실패 시 err.message 는 담지 않는다
 * (Pitfall 7 — fingerprint 만).
 *
 * @param {Firestore} db Firestore Admin 인스턴스.
 * @param {string} uid 재로그인 대상 Firebase UID.
 * @return {Promise<SignUpProviderRead>} `found` = 기록된 가입 수단 문자열,
 *     `missing` = 기록 없음(보존 대상), `read_failed` = read 실패(보존 대상 ·
 *     code 만).
 */
async function readSignUpProviderId(
  db: Firestore,
  uid: string,
): Promise<SignUpProviderRead> {
  try {
    const snap = await db.collection("users").doc(uid).get();
    if (!snap.exists) return {kind: "missing"};
    const value = snap.data()?.signUpProviderId;
    if (typeof value !== "string" || value.length === 0) {
      return {kind: "missing"};
    }
    return {kind: "found", providerId: value};
  } catch (err: unknown) {
    return {kind: "read_failed", code: fingerprintError(err)};
  }
}

/**
 * Identity Index 조회 결과.
 *
 * R3 (Phase 12.1-06 / BL-04 + WR-06, D-32) — `conflictKind` 필드 추가.
 * helper 는 충돌을 *detect* 만 한다 (HttpsError throw 책임은 caller).
 *
 * - `null` — 정상 path (충돌 없음).
 * - `'email_in_use'` — Two detect paths: (1) [기존, !callerUid 분기]
 *   `createUser` 가 `auth/email-already-in-use` rejection (Kakao biz / Naver
 *   email consent). (2) [Phase 9.2 Gap B — HUMAN-UAT 2026-05-11] callerUid
 *   분기 + userInfo.email 제공 + `getUserByEmail` 결과 providerData[] 가
 *   conflictingProviders 포함. caller (naverCustomToken/kakaoCustomToken)
 *   switch case 'email_in_use' 분기가 둘 다 동일하게 already-exists HttpsError
 *   throw. Phase 17 (Account Linking) — see ROADMAP.md.
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
/**
 * Phase 16 D-09 (Plan 16-03 Task 3.1) — ProviderId union (7값).
 *
 * native 4 provider (`google` / `apple` / `facebook` / `email`) + Custom Token
 * 3 provider (`kakao` / `naver` / `line`) 의 closed enum. identity_
 * index 의 `existingProvider` 필드 type + Plan 16-04 의 Flutter ProviderId
 * Freezed enum 의 server-side 진실원 (server 가 issue, Flutter 가 mirror).
 *
 * Phase 16 add-only — Plan 16-03 이전에는 conflictKind 만 있고 provider 라벨
 * 부재 → caller (client) 가 추가 lookupSignInMethods callable 호출 의무.
 * Phase 16 부터는 conflictKind + existingProvider 즉시 전달 → caller catch 시
 * server 추가 조회 0 (D-09 핵심 가치).
 */
export type ProviderId =
  | "google"
  | "apple"
  | "facebook"
  | "email"
  | "kakao"
  | "naver"
  | "line";

/**
 * Firebase Auth providerData[].providerId → ProviderId enum 매핑 (D-09).
 *
 * native 4 provider 의 Firebase 표기 (`google.com` / `apple.com` /
 * `facebook.com` / `password`) 를 ProviderId slug 로 변환. 미정의 provider
 * (예: `twitter.com`) 는 `"unknown"` fallback.
 */
const NATIVE_PROVIDER_DATA_MAP: Record<string, ProviderId> = {
  "google.com": "google",
  "apple.com": "apple",
  "facebook.com": "facebook",
  "password": "email",
};

/**
 * providerData[] 의 첫 known native provider 를 ProviderId 로 매핑 (D-09).
 *
 * `firebase` slug 와 본 helper 의 caller 가 호출한 `currentProvider` 자체는
 * skip (self-identity). 매칭 0 시 'unknown' fallback.
 *
 * @param {object[]} providerData Firebase Auth user 의 providerData array
 *     (admin SDK 반환) — 각 원소 `{providerId?: string}`.
 * @param {ProviderId} currentProvider caller 가 호출한 provider slug — 자기
 *     자신 매칭 제외 (false-positive 회피).
 * @return {string} 첫 known native provider slug 또는 'unknown'.
 */
export function mapProviderDataToProviderId(
  providerData: Array<{providerId?: string}> | undefined,
  currentProvider: ProviderId,
): ProviderId | "unknown" {
  if (!providerData || providerData.length === 0) return "unknown";
  for (const p of providerData) {
    const pid = p.providerId;
    if (!pid) continue;
    if (pid === "firebase") continue;
    const mapped = NATIVE_PROVIDER_DATA_MAP[pid];
    if (mapped && mapped !== currentProvider) {
      return mapped;
    }
  }
  return "unknown";
}

/**
 * Custom Token provider 화이트리스트 겸 결정적 tie-break 순서 (Plan 16-17).
 *
 * 두 가지 책임을 겸한다.
 * 1. **화이트리스트** — `identity_index` 역조회 결과의 `provider` 필드 값이
 *    본 배열에 없으면 후보에서 탈락한다 (T-16-17-04 Spoofing 방어 — 임의
 *    문자열이 사용자 노출 라벨로 주입되는 경로 차단).
 * 2. **결정적 tie-break 순서** — 기존 계정이 2개 이상의 Custom Token
 *    identity 를 보유할 때 앞선 값이 선택된다.
 *
 * **순서 변경은 사용자에게 노출되는 라벨을 바꾸는 동작 변경이다.** 단순
 * 정렬 취향 문제가 아니라 "어느 provider 로 가입되어 있습니다" 문구가
 * 달라지므로, 순서를 바꿀 때는 Plan 16-17 의 결정성 테스트도 함께 갱신할 것.
 */
export const CUSTOM_TOKEN_PROVIDER_PRIORITY: readonly ProviderId[] = [
  "kakao",
  "naver",
  "line",
] as const;

/**
 * `identity_index` 역조회로 Custom Token 기존 계정의 provider 를 해석한다
 * (Plan 16-17 / A4 finding 2026-06-11 권장안).
 *
 * **왜 providerData 가 아닌 identity_index 인가**: Custom Token 으로 생성된
 * Firebase Auth user 는 `customAuth: true` 이고 `providerData[]` 가 항상
 * 비어 있다 (라이브 확인 — Kakao/Naver/LINE 계정 모두 `providerUserInfo`
 * 부재). 따라서 `NATIVE_PROVIDER_DATA_MAP` 기반의
 * `mapProviderDataToProviderId` 는 Custom Token 계정에 대해 구조적으로
 * `'unknown'` 만 반환한다. Custom Token 계정의 진실원은 `identity_index`
 * 컬렉션 (`{provider}:{providerUserId}` 문서의 `firebaseUid` / `provider`
 * 필드) 뿐이다. native 계정은 반대로 identity_index 문서가 존재하지 않으므로
 * 두 소스는 상호배타이며, 본 helper 는 native 매핑 실패 시의 2차 소스다.
 *
 * **읽기 순서 계약**: 본 helper 는 `db.runTransaction` **밖**에서만 호출되어야
 * 한다. transaction 내부에서 호출하면 Firestore 의 "all reads before all
 * writes" 제약을 위반할 수 있다 (WR-05 / R12 회귀 계열).
 *
 * **PII 정책 (D-51 / Pitfall 7)**: 반환 타입은
 * `CUSTOM_TOKEN_PROVIDER_PRIORITY` 화이트리스트 값 (kakao / naver / line) 또는
 * `null` 뿐이며, logger payload 에는 `event` 와 `code` 만 담는다 — email /
 * firebaseUid / providerUserId 는 절대 로깅하지 않는다.
 *
 * **best-effort 정책**: 쿼리 실패는 `null` 로 graceful 처리한다
 * (`identity_index_existing_provider_lookup_failed` 분기와 동일 정책) —
 * 역조회 실패가 정당한 로그인을 차단하지 않는다 (T-16-17-02).
 *
 * **multi-identity 계정 계약 (CR-01 / 2026-09-09)**: 기존 계정이 caller 자신의
 * provider identity 를 **이미 보유** 하면 그것은 cross-provider 충돌이 아니라
 * "자기 계정 재로그인" 이다. proactive linking
 * (`link_custom_token_provider.ts`) 이 동일 `firebaseUid` 로 2번째·3번째
 * `identity_index` 문서를 만들기 때문에 이 상태는 Phase 16 의 정상 상태다.
 * 이때 형제 slug 를 라벨로 내보내면 사용자에게 쓰지도 않는 provider 로
 * 로그인하라고 안내하게 되므로 (`AccountLinkingSheet` step 1 CTA), `null` 을
 * 돌려 기존 transaction 경로 (`anonymous_existing_collision` — caller 자신의
 * slug 라벨) 에 위임한다 (T-16-17-10).
 *
 * **self 판정의 기준은 `providerUserId` 다 (WR-03 / 4차 리뷰)**: `identity_index`
 * 문서 ID 가 `{provider}:{providerUserId}` 이므로 **동일 provider 라도 sub 가
 * 다르면 다른 계정**이다 (IdP 계정 탈퇴 후 동일 이메일로 재가입 → sub 변경).
 * provider slug 일치만으로 self 판정하면 그 조합이 "충돌 아님" 으로 통과해
 * 익명 uid 를 가리키는 `identity_index` 문서가 커밋된 뒤
 * `getAuth().updateUser` 가 `auth/email-already-exists` 로 throw 한다 —
 * 사용자에게는 원인 불명 `internal`, Firestore 에는 영구 잔존하는 잘못된
 * 문서가 남는다. 따라서 sub 가 다르면 정당한 충돌로 보고 후보에 남긴다
 * (T-16-17-12).
 *
 * @param {Firestore} db Firestore Admin 인스턴스.
 * @param {string} firebaseUid 기존 계정의 Firebase UID (역조회 대상).
 * @param {ProviderId} currentProvider caller 가 호출한 provider slug.
 * @param {string} currentProviderUserId caller 의 IdP sub — self 판정의 진짜
 *     기준이다. `{currentProvider, currentProviderUserId}` 가 **둘 다** 일치
 *     하는 문서만 자기 자신으로 보아 후보에서 제외하고, 그 매칭이 존재하면
 *     전체 결과를 `null` 로 만든다 (자기 계정 재로그인).
 * @return {Promise<ProviderId|null>} `CUSTOM_TOKEN_PROVIDER_PRIORITY` 순서상
 *     첫 후보 slug. 후보 0개, caller 자신 identity 보유, 또는 쿼리 실패 시
 *     `null`.
 */
export async function resolveCustomTokenExistingProvider(
  db: Firestore,
  firebaseUid: string,
  currentProvider: ProviderId,
  currentProviderUserId: string,
): Promise<ProviderId | null> {
  try {
    // 단일 필드 equality 쿼리 — Firestore 자동 단일 필드 인덱스로 충족되므로
    // 복합 인덱스(firestore.indexes.json) 신설/배포가 불필요하다.
    const snap = await db
      .collection("identity_index")
      .where("firebaseUid", "==", firebaseUid)
      .get();

    const candidates = new Set<ProviderId>();
    // 기존 계정이 caller 자신의 identity 를 이미 보유하는지 (CR-01).
    let selfMatched = false;
    for (const doc of snap.docs) {
      const data = doc.data() as {provider?: unknown; providerUserId?: unknown};
      const raw = data?.provider;
      if (typeof raw !== "string") continue;
      // 화이트리스트 필터 — 미래에 native provider 가 identity_index 에
      // 회고적 등록되어도 Custom Token 라벨로 오분류되지 않는다.
      const matched = CUSTOM_TOKEN_PROVIDER_PRIORITY.find((p) => p === raw);
      if (!matched) continue;
      // self-identity 제외 — caller 자신의 **문서** 만 충돌이 아니다 (WR-03).
      // 같은 provider 라도 sub 가 다르면 다른 계정이므로 후보로 남긴다.
      if (
        matched === currentProvider &&
        data.providerUserId === currentProviderUserId
      ) {
        selfMatched = true;
        continue;
      }
      candidates.add(matched);
    }

    // CR-01: 기존 계정이 caller provider 를 이미 보유 → cross-provider 충돌이
    // 아니라 자기 계정 재로그인이다. 형제 slug 를 라벨로 내보내면 사용자에게
    // 쓰지도 않는 provider 를 안내하게 되므로 (proactive linking 이 만든
    // multi-identity 계정에서 발생), null 로 기존 transaction 경로
    // (anonymous_existing_collision) 에 위임한다.
    if (selfMatched) return null;

    // 입력 문서 순서와 무관하게 고정 우선순위로 결정 (결정성 보장).
    for (const p of CUSTOM_TOKEN_PROVIDER_PRIORITY) {
      if (candidates.has(p)) return p;
    }
    return null;
  } catch (err: unknown) {
    const code = fingerprintError(err);
    logger.warn(
      {event: "identity_index_reverse_lookup_failed", code},
      "identity_index reverse lookup failed",
    );
    return null;
  }
}

/**
 * identity_index 비-transaction 스냅샷에서 매핑된 Firebase UID 를 읽는다
 * (naver-self-email-collision, 2026-09-17).
 *
 * 문서 ID 가 `{provider}:{providerUserId}` 이므로 이 값은 "이 IdP 사용자가
 * 이미 소유한 계정" 의 진실원이다 (D-12 first-write-wins).
 *
 * @param {DocumentSnapshot} snap `identity_index/{provider}:{sub}` 비-tx
 *     스냅샷.
 * @return {string|undefined} 문서가 있고 `firebaseUid` 가 비어 있지 않은
 *     문자열이면 그 값, 아니면 `undefined`.
 */
function readIndexedFirebaseUid(snap: DocumentSnapshot): string | undefined {
  if (!snap.exists) return undefined;
  const uid = snap.data()?.firebaseUid;
  return typeof uid === "string" && uid.length > 0 ? uid : undefined;
}

/**
 * 비익명 caller 가드 거부 결과를 만든다 (debug reauth-login-auto-merge).
 *
 * 거부 사실은 provider slug 와 identity 문서 존재 여부만 기록한다 — caller
 * uid · IdP sub · email 은 로그에 싣지 않는다 (Pitfall 7).
 *
 * @param {ProviderId} provider 호출 provider slug.
 * @param {boolean} indexed identity_index 문서가 있었는지 (다른 계정 매핑).
 * @return {IdentityResolution} `caller_identity_mismatch` 결과 (uid 빈 문자열).
 */
function callerIdentityMismatchResult(
  provider: ProviderId,
  indexed: boolean,
): IdentityResolution {
  logger.warn(
    {event: "identity_index_caller_identity_mismatch", provider, indexed},
    "signed-in caller used an identity not mapped to its account",
  );
  return {
    uid: "",
    isNewUser: false,
    conflictKind: "caller_identity_mismatch",
  };
}

export type IdentityResolution = {
  uid: string;
  isNewUser: boolean;
  /**
   * - `email_in_use` / `anonymous_existing_collision` — 기존 충돌 (Phase 12.1).
   * - `caller_identity_mismatch` — 비익명 caller 가 자기 계정에 매핑되지 않은
   *   identity 로 호출 (debug reauth-login-auto-merge). `uid` 는 `""` 이며
   *   identity 등록 · 사용자 기록 변경은 일어나지 않는다.
   */
  conflictKind:
    | "email_in_use"
    | "anonymous_existing_collision"
    | "caller_identity_mismatch"
    | null;
  /**
   * Phase 16 D-09 (Plan 16-03 Task 3.1) — add-only.
   *
   * conflictKind != null 일 때 정확한 충돌 provider 라벨 (Plan 16-04 의 client
   * catch 시 server 추가 조회 0). null path 에서는 미설정 (undefined). 기존
   * caller switch case 의 schema 보존 — caller 가 본 필드를 참조하지 않아도
   * 회귀 0 (optional add-only).
   *
   * - `email_in_use` path: getUserByEmail 의 providerData[] 첫 known native
   *   provider 매핑 (mapProviderDataToProviderId helper). 매핑 실패 시
   *   'unknown'.
   * - `anonymous_existing_collision` path: identity_index 의 doc ID 가
   *   `provider:providerUserId` 이므로 caller 가 호출한 provider slug 자체.
   */
  existingProvider?: ProviderId | "unknown";
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
 *      providerUserId}), providerLinkedAt: {[providerId]: serverTimestamp()},
 *      signUpProviderId: providerId}, {merge: true}) — users write 는 이
 *      set-merge 1회에 3 필드가 원자적으로 동승한다.
 *      · linkedProviders ← Pitfall 12 (Plan 10-12 mirrorToFirestore race 방어)
 *      · providerLinkedAt ← Pitfall 5 회피 (linkedAt 은 arrayUnion 객체 밖
 *        별도 map)
 *      · signUpProviderId ← Phase 16.7 D-16 (가입 수단 — 신규 등록 분기에서만.
 *        기존 identity 재사용(재로그인 · R12 빈 익명 재사용) · 비익명 caller
 *        가드 · race-loser 는 users write 자체가 없다, D-18)
 * 3. transaction 이후 (tx 밖 · best-effort): 재로그인 (isNewUser=false +
 *    userInfo) 이면 로그인 계정 `users/{uid}` 를 1회 read 해
 *    `signUpProviderId === provider` (가입 수단 로그인) 일 때만 IdP 프로필로
 *    Auth user record 를 갱신한다 (quick 260928-jwe · R10-FOLLOWUP).
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
    /**
     * provider 슬러그. IN-07 (Phase 15 리뷰): 이전에는 `string` 이라서 본문
     * 5곳에서 `ProviderId` 로 단언해야 했고, 오타 슬러그가 `existingProvider`
     * → `HttpsError.details` → client 까지 흘러가 타입 시스템이 아니라
     * client 의 `AccountProvider.tryParse` 가 처음으로 걸러냈다 (→ null →
     * 일반 배너). 호출자 4곳 모두 리터럴을 넘기므로 시그니처를 좁히면 단언이
     * 전부 사라진다.
     */
    provider: ProviderId;
    providerUserId: string;
    callerUid: string | undefined;
    /**
     * caller 세션이 익명 로그인인지 (debug reauth-login-auto-merge).
     *
     * callable 이 `request.auth.token.firebase.sign_in_provider ===
     * "anonymous"` 로 판정해 넘긴다. `callerUid` 가 있고 본 값이 `true` 가
     * 아니면 (미지정 포함 — fail-closed) 비익명 caller 가드를 적용한다.
     */
    callerIsAnonymous?: boolean;
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
     *
     * 재로그인 때는 가입 수단 로그인일 때만 Auth 에 반영한다
     * (quick 260928-jwe — 연결 수단 로그인은 보존).
     */
    userInfo?: {
      email?: string;
      /**
       * IdP 가 보고한 이메일 인증 상태 (WR-04).
       *
       * `email` 이 함께 제공될 때만 의미가 있다. 생략하면 보수적으로
       * `false` 로 간주한다 — "이메일은 받았는데 인증 여부는 모른다" 를
       * verified 로 승격하지 않기 위해서다. `email` 자체가 없는 provider
       * (LINE) 는 본 필드와 무관하게 `true` 를 유지한다.
       */
      emailVerified?: boolean;
      displayName?: string;
      photoURL?: string;
    };
  },
): Promise<IdentityResolution> {
  const {provider, providerUserId, callerUid, callerIsAnonymous, userInfo} =
    args;
  const idxRef = db
    .collection("identity_index")
    .doc(identityIndexDocId(provider, providerUserId));
  const userRefFor = (uid: string) => db.collection("users").doc(uid);

  // Step 1: 비-tx read — Pitfall 4 (transaction retry 시 createUser 다중호출)
  // 회피. 미존재 + 미인증 → createUser 1회 사전 호출.
  //
  // emailVerified — **email 을 받지 않는 provider 는 `true`**. OAuth Custom
  // Token 사용자는 외부 IdP 가 인증을 책임지고, 이게 없으면 Firebase Auth 의
  // default emailVerified=false 가 client-side router 의 verify-email 분기를
  // 오트리거한다 (Phase 12-04 retroactive gap closure).
  //
  // WR-04 (Phase 15 리뷰): 이전에는 **무조건** `true` 라서, Kakao endpoint 가
  // IN-04 대응으로 `developerClaims.email_verified` 를 IdP claim 그대로 보수
  // 전파하도록 고친 것이 무력화됐다 — custom claim 만 false 이고 Firebase Auth
  // **user record 는 true** 였으므로, 이메일 기반 계정 병합 / 비밀번호 재설정 /
  // auth_guard 의 verify-email 분기 등 record 를 신뢰하는 모든 경로에서 방어가
  // 사라졌다. 이제 email 을 받은 경우에만 IdP 의 검증 상태를 반영한다.
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

  // WR-04: email 이 없으면 verify-email gate 오트리거 방지를 위해 true 를
  // 유지하고 (email 권한 없는 LINE 채널 등), email 이 있으면 IdP 가 보고한
  // 상태를 따른다.
  // 미보고 시 보수적으로 false.
  const resolvedEmailVerified = userInfo?.email ?
    (userInfo.emailVerified ?? false) :
    true;

  // Step 0.5 (Phase 9.2 Gap B close — HUMAN-UAT 2026-05-11):
  //
  // 익명승격 path (callerUid 가 익명 user uid + userInfo.email 제공) + 동일
  // 이메일이 이미 *다른* provider 로 가입된 시나리오 에서 createUser pre-step
  // 이 skip 되어 email_in_use detect 미발동 회귀를 차단.
  //
  // 기존 detect path (line 229~250 의 createUser try/catch) 는 !callerUid
  // 분기에서만 활성 — 익명승격 path (callerUid 존재) 는 createUser 호출 0.
  // 동일 이메일의 기존 user (예: Facebook 가입자) 와의 충돌은 transaction
  // 으로 진입되어 신규 identity_index 등록 + Firebase Auth user 미창출
  // (anonymous user record 재활용) 경로로 silent. 사용자는 verifyEmailScreen
  // 의 'email 미설정' 상태에 stuck.
  //
  // **R2 Path A-narrow boundary 보존**: helper 는 detect 만 책임 (D-33 layering)
  // — caller (naverCustomToken / kakaoCustomToken) 의 기존 switch case
  // 'email_in_use' 분기가 'already-exists' HttpsError throw → client 측
  // _mapFunctionsException Phase 12.1 D-34 분기 → unknown fallback ARB 메시지.
  //
  // **false-positive 차단 정책 (Plan 16-17 — 2단 해석으로 갱신)**:
  // 1단 — native 해석. 기존 계정 providerData 에 다른 native provider
  //   (google.com / apple.com / facebook.com / password) 가 포함되면
  //   email_in_use 발동 (mapProviderDataToProviderId 로 slug 산출).
  // 2단 — Custom Token 해석. providerData 매핑이 실패(비어 있음 = Custom
  //   Token 계정의 normal case, 또는 firebase 단일 식별자)하면
  //   `identity_index` 역조회(resolveCustomTokenExistingProvider)로 Custom
  //   Token provider 를 해석한다.
  // 그마저도 비면 **충돌 아님** — 어떤 provider 도 식별되지 않은 상태에서
  // 정당한 로그인을 차단하지 않는다(T-16-17-02). 즉 "email 만 같고 provider
  // 미식별" 은 통과가 정책이다.
  //
  // **PII 정책 (D-51 / Pitfall 7)**: getUserByEmail throw 시 logger payload 에
  // userInfo.email 본문 미노출, err.code/err.name 만 fingerprint.
  //
  // Custom Token ↔ Custom Token 충돌 감지는 Plan 16-17 이 닫았다
  // (그 이전에는 Phase 17 이월 표기 — A4 finding 2026-06-11 참고).
  // Account Linking actuation 자체는 Plan 16-18/16-19 책임.
  //
  // Step 1 의 비-tx read 를 Step 0.5 앞으로 올린다 (naver-self-email-collision,
  // 2026-09-17). Step 0.5 의 self 판정이 "이 identity 가 이미 가리키는 계정"
  // 을 알아야 하기 때문이다. transaction 밖 read 라 Firestore "all reads
  // before all writes" 제약과 무관하고, 정상 경로의 read 횟수도 그대로다
  // (충돌 조기 return 경로에서만 1회 늘어난다).
  const idxSnapPre = await idxRef.get();

  // debug reauth-login-auto-merge (2026-09-17) — 비익명 caller 가드.
  //
  // 정식 로그인 caller 는 **자기 계정에 이미 매핑된 identity** 로만 통과한다.
  // 이 가드가 없을 때 재인증 로그인 화면에서 정식 사용자 U 가 연결 안 된
  // provider 를 누르면 아래 경로가 (a) 새 identity 를 U 에 등록하고
  // (b) R9/R10 블록이 U 의 email · displayName · photoURL 을 IdP 값으로
  // 덮어썼다 — 사용자 동의 없는 연결이며, `linkCustomTokenProvider` 의
  // auth_time · 익명 거부 게이트(T-16-10-01)도 우회한다. 다른 계정에 매핑된
  // identity 는 "다른 계정으로 전환" 을 뜻하므로 역시 거부한다.
  //
  // 익명 caller (익명 → 소셜 승격) 와 미인증 caller 는 기존 경로 그대로다.
  // `callerIsAnonymous` 미지정은 비익명으로 다룬다 (fail-closed).
  //
  // 비-tx 스냅샷으로 명백한 불일치를 부작용(Step 0.5 email lookup 포함)
  // **이전**에 거른다. 스냅샷이 자기 매핑이어도 transaction 이 다시 확인한다
  // (경합 — 그 사이 문서 삭제 · 재매핑).
  const guardsCaller = callerUid !== undefined && callerIsAnonymous !== true;
  if (guardsCaller) {
    const indexedUidPre = readIndexedFirebaseUid(idxSnapPre);
    const isOtherOrUnregistered =
      !idxSnapPre.exists ||
      (indexedUidPre !== undefined && indexedUidPre !== callerUid);
    if (isOtherOrUnregistered) {
      return callerIdentityMismatchResult(provider, idxSnapPre.exists);
    }
  }

  if (callerUid && userInfo?.email) {
    try {
      const existingByEmail = await getAuth().getUserByEmail(userInfo.email);
      // WR-05 (Phase 15 리뷰): **자기 자신은 충돌이 아니다.** 2단(Custom
      // Token) 분기는 `existingByEmail.uid !== callerUid` 로 자기 자신을
      // 명시 제외하는데 1단(native) 분기에는 같은 가드가 없었다. 그래서
      // 이미 Google 로 로그인한 정식 사용자가 같은 이메일로 Kakao Custom
      // Token 로그인을 호출하면 `getUserByEmail` 이 **자기 자신** 을
      // 돌려주고 providerData 에 `google.com` 이 있으므로
      // `already-exists` 가 던져졌다 — 사용자는 자기 계정에 대해 "이미 다른
      // 방법으로 가입된 이메일" 이라는 안내를 받았다.
      //
      // naver-self-email-collision (2026-09-17 — iOS batch UAT G6): self 는
      // caller uid 만이 아니다. **이 identity 가 이미 매핑된 계정** 도 자기
      // 계정이다. 로그아웃 뒤 caller 는 새 익명 uid 라 위 비교만으로는
      // 재로그인이 self 로 인정되지 않았고, 그 계정에 native provider
      // (apple.com 등) 가 붙어 있으면 자기 계정을 가리키는 email_in_use
      // (409) 가 던져졌다. 매핑 uid 와 email 소유 uid 가 **같을 때만** self 다
      // — 다르면 (다른 계정이 그 email 을 소유) 기존 충돌 판정을 유지한다.
      // self 판정 뒤에는 transaction 이 R12 정책 (빈 익명 → 재사용 / 데이터
      // 있는 익명 → anonymous_existing_collision) 을 그대로 적용한다.
      const isSelf =
        existingByEmail.uid === callerUid ||
        existingByEmail.uid === readIndexedFirebaseUid(idxSnapPre);
      const conflictingProviders = isSelf ?
        [] :
        (existingByEmail.providerData ?? [])
          .map((p) => p.providerId)
          // WR-05: 기존 `id !== provider` 비교는 **항상 참** 이었다 — 좌변은
          // Firebase 표기(`google.com` / `password`) 이고 우변은 Custom Token
          // 슬러그(`kakao` / `naver` / ...) 라 교집합이 없다. self-identity 를
          // 걸러내려는 원래 의도대로 역매핑으로 비교한다 (Phase 16 이 native
          // provider 를 identity_index 에 회고 등록하면 실제로 필요해진다).
          .filter(
            (id) =>
              id !== "firebase" &&
              NATIVE_PROVIDER_DATA_MAP[id] !== provider,
          );
      if (conflictingProviders.length > 0) {
        // Phase 16 D-09 (Plan 16-03) — existingProvider 매핑. providerData[]
        // 의 첫 known native provider → ProviderId. 매핑 실패 시 'unknown'.
        // PII 정책 보존 — existingProvider 는 slug ('google'/'apple'/등) 만,
        // platform uid / email 본문 미노출.
        const existingProvider = mapProviderDataToProviderId(
          existingByEmail.providerData,
          provider,
        );
        logger.warn(
          {
            event: "identity_index_email_collision_caller_path",
            provider,
            conflictingProviderCount: conflictingProviders.length,
            existingProvider,
          },
          "email collision detected in callerUid path",
        );
        return {
          uid: "",
          isNewUser: false,
          conflictKind: "email_in_use" as const,
          existingProvider,
        };
      }
      // Plan 16-17 — Custom Token 기존 계정 해석 (2단). providerData 매핑이
      // 실패한 경우에만 진입한다. 본 read 는 db.runTransaction 진입 **이전**의
      // 비-transaction 구간이므로 Firestore "all reads before all writes"
      // 제약과 무관하다 (T-16-17-03).
      // self (caller 자신 또는 이 identity 의 매핑 계정) 이면 역조회도
      // selfMatched 로 null 을 돌리므로 read 를 생략한다.
      if (!isSelf) {
        const ctExistingProvider = await resolveCustomTokenExistingProvider(
          db,
          existingByEmail.uid,
          provider,
          providerUserId,
        );
        if (ctExistingProvider) {
          logger.warn(
            {
              event: "identity_index_email_collision_custom_token_path",
              provider,
              existingProvider: ctExistingProvider,
            },
            "email collision detected via identity_index reverse lookup",
          );
          return {
            uid: "",
            isNewUser: false,
            conflictKind: "email_in_use" as const,
            existingProvider: ctExistingProvider,
          };
        }
        // null → 충돌 아님. 정상 path 진행 (false-positive 차단 정책 보존).
      }
    } catch (err: unknown) {
      // WR-07: as-assertion 제거, fingerprintError type-guard helper 일원화.
      const errCode = fingerprintError(err);
      if (errCode !== "auth/user-not-found") {
        logger.warn(
          {event: "identity_index_email_lookup_failed", code: errCode},
          "getUserByEmail failed in callerUid path",
        );
      }
      // graceful — 정상 path 진행 (lookup 실패가 user-facing throw 로 escalate
      // 되지 않음). auth/user-not-found 는 expected normal case (이메일이
      // 기존에 가입 안 되어 있음) — silent.
    }
  }

  let preCreatedUid: string | null = null;
  if (!idxSnapPre.exists && !callerUid) {
    try {
      const created = await getAuth().createUser({
        emailVerified: resolvedEmailVerified,
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
      // WR-07: fingerprintError 로 as-assertion 일원화. helper 가 'auth/...' /
      // err.name / non-Error throw 까지 안전 추출.
      if (fingerprintError(err) === "auth/email-already-in-use") {
        // Phase 16 D-09 (Plan 16-03) — !callerUid + createUser email-already-
        // in-use path 의 existingProvider 추론. helper 는 caller email 만
        // 알고 있으므로 추가 getUserByEmail lookup 으로 providerData inspect.
        // lookup 실패 시 'unknown' fallback (best-effort, caller-path 와
        // 정책 일관). PII 정책 보존 — existingProvider slug 만 노출.
        let existingProvider: ProviderId | "unknown" = "unknown";
        if (userInfo?.email) {
          try {
            const existingByEmail = await getAuth().getUserByEmail(
              userInfo.email,
            );
            existingProvider = mapProviderDataToProviderId(
              existingByEmail.providerData,
              provider,
            );
            // Plan 16-17 — native 매핑 실패('unknown') 시에만 Custom Token
            // 해석으로 fallback. 기존 계정이 Custom Token 이면 providerData 가
            // 비어 있어 여기까지 오는 것이 normal case 다. 역조회가 null 이면
            // 'unknown' 유지 (R2 일반 배너 fallback 보존).
            // 본 read 도 db.runTransaction 진입 이전 구간이다 (T-16-17-03).
            if (existingProvider === "unknown") {
              const ctExistingProvider =
                await resolveCustomTokenExistingProvider(
                  db,
                  existingByEmail.uid,
                  provider,
                  providerUserId,
                );
              if (ctExistingProvider) existingProvider = ctExistingProvider;
            }
          } catch (lookupErr: unknown) {
            // best-effort — lookup 실패가 conflictKind 매핑을 차단하지 않음.
            // err.code 만 fingerprint, email 본문 미노출.
            const lookupCode = fingerprintError(lookupErr);
            if (lookupCode !== "auth/user-not-found") {
              logger.warn(
                {
                  event: "identity_index_existing_provider_lookup_failed",
                  code: lookupCode,
                },
                "existingProvider inference failed in createUser path",
              );
            }
            // existingProvider 는 'unknown' 으로 유지.
          }
        }
        return {
          // caller 가 사용 안 함 — switch (conflictKind) 가 우선해서 throw.
          uid: "",
          isNewUser: false,
          conflictKind: "email_in_use" as const,
          existingProvider,
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
      // reauth-login-auto-merge 가드의 transaction 재확인 — 쓰기 전에 반환한다.
      if (guardsCaller && existing.firebaseUid !== callerUid) {
        return callerIdentityMismatchResult(provider, true);
      }
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
        // Phase 16 D-09 (Plan 16-03) — existingProvider = caller 가 호출한
        // provider slug 자체. identity_index doc ID 가 `provider:providerUserId`
        // 이므로 existing 매핑은 동일 provider 의 기존 user (정의상 다른
        // provider 일 수 없음). provider 는 본 helper 의 arg → 7값 ProviderId.
        return {
          uid: existing.firebaseUid,
          isNewUser: false,
          conflictKind: "anonymous_existing_collision" as const,
          existingProvider: provider,
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

    // reauth-login-auto-merge 가드 — 비익명 caller 는 신규 등록 대상이 아니다
    // (비-tx 스냅샷 이후 문서가 사라진 경합 포함). 쓰기 0 으로 반환한다.
    if (guardsCaller) {
      return callerIdentityMismatchResult(provider, false);
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
        // Phase 16.7 D-16 — 가입 수단. 값 형식 = linkedProviders[].providerId
        // (closed union ProviderId). 신규 등록 분기에서만 쓰이므로 재로그인
        // (isNewUser: false) · 비익명 caller 가드는 구조적으로 기록 0 (D-18).
        signUpProviderId: provider,
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
      // 'user not found for uid abc...') — 절대 로깅 금지. fingerprintError
      // helper 가 err.code (firebase-admin standard) / err.name / non-Error
      // throw fingerprint 만 안전 추출 (WR-07).
      const errCode = fingerprintError(cleanupErr);
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
  // CR-02 (Phase 15 리뷰) — post-commit 실패의 보상.
  //
  // **문제:** 위 `db.runTransaction(...)` 은 이미 커밋됐다. 따라서 이전
  // 구현 (`if (result.isNewUser && callerUid)`) 에서 `updateUser` 가 throw
  // 하면 (`auth/internal-error` / 네트워크 / `auth/invalid-photo-url` —
  // IdP 가 준 picture 가 Firebase URL 검증을 통과 못 하는 경우 등),
  // `identity_index/{provider}:{sub}.firebaseUid = callerUid` 는 **영구
  // 커밋된 채** 로 남고 caller 는 `internal` 을 받았다. 사용자가 재시도하면
  // 이제 `idxSnap.exists === true` + `existing.firebaseUid === callerUid`
  // 이므로 `isNewUser: false` 가 되어 **본 블록이 통째로 skip** 되고
  // `createCustomToken` 이 발급된다. 즉 "첫 시도 실패 → 재시도 성공" 이라는
  // 가장 흔한 사용자 행동이 `emailVerified=false` 인 social user 를 그대로
  // 통과시켜, 이 코드가 막으려던 회귀가 retry path 로 재현됐다.
  //
  // **수정:** 판단 기준을 "신규 등록" 이 아니라 "미확정" 으로 바꾼다.
  // caller 가 그 uid 의 소유자이고 `emailVerified` 가 아직 false 면 재시도
  // 에서 반드시 다시 시도된다 (멱등).
  if (callerUid && result.uid === callerUid) {
    let shouldSetEmailVerified = result.isNewUser;
    if (!shouldSetEmailVerified) {
      // 재시도 path — 직전 시도가 post-commit 에서 실패했을 수 있다.
      const current = await getAuth().getUser(callerUid);
      // **native provider 계정은 건드리지 않는다.** google / apple /
      // facebook / password 가 연결된 계정에서 `emailVerified` 는 그쪽
      // 인증 게이트 (이메일 인증 / 비밀번호 재설정) 의 근거다. 여기서
      // 강제로 true 를 쓰면 그 게이트를 우회시키는 보안 강등이 된다.
      // Custom Token 및 익명 계정은 `providerData` 가 항상 비어 있다
      // (`resolveCustomTokenExistingProvider` docstring 의 라이브 확인
      // 근거 참조) — 그 population 만 보상 대상이다.
      const hasNativeProvider = (current.providerData ?? []).length > 0;
      // WR-04: 목표값이 false 인 경우 (IdP 가 unverified email 을 보고) 는
      // 보상할 것이 없다 — verify-email gate 가 **정상적으로** 트리거되는
      // 상태이기 때문이다. 보상은 "true 로 올려야 하는데 못 올린" 경우만.
      shouldSetEmailVerified =
        resolvedEmailVerified && !current.emailVerified && !hasNativeProvider;
    }
    if (shouldSetEmailVerified) {
      // strict — 실패 시 throw. 보안 게이트이므로 caller 가
      // createCustomToken 을 차단해야 한다.
      await getAuth().updateUser(callerUid, {
        emailVerified: resolvedEmailVerified,
      });
    }

    // CR-02 두 번째 갈래 — 프로필 필드를 보안 게이트와 **분리**한다.
    // 이전에는 `{emailVerified: true, ...profileFields}` 한 번의 호출이라
    // `auth/invalid-photo-url` 같은 프로필 필드 문제 하나가 보안 게이트까지
    // 도미노로 실패시켰다 (그리고 그 실패가 위의 미보상 상태를 만들었다).
    // 프로필은 UI freshness 수준이므로 best-effort 로 격하한다
    // (R10-FOLLOWUP 재로그인 refresh 와 동일 정책).
    if (result.isNewUser && Object.keys(profileFields).length > 0) {
      try {
        await getAuth().updateUser(callerUid, profileFields);
      } catch (profileErr: unknown) {
        // Pitfall 7 — err.message 본문 미로깅 (PII 가능성).
        logger.warn(
          {
            event: "identity_index_profile_set_failed",
            uid: callerUid,
            code: fingerprintError(profileErr),
          },
          "profile field update failed on new identity",
        );
        // 의도적으로 재던지지 않음 — 로그인은 계속 (best-effort).
      }
    }
  }

  // R10-FOLLOWUP (2026-05-08 — T-13-UAT-NAVER-A1 발견):
  // 재로그인 시 (isNewUser=false path) IdP 측 프로필 변경 (displayName/
  // photoURL) 을 Firebase Auth user record 에 propagate. R10 retroactive
  // 가 신규 등록 path (createUser/updateUser+emailVerified) 만 cover →
  // 재로그인 path 는 tx.update(idxRef, lastSeenAt) 만 호출, user record 의
  // 프로필 필드 stale. 사용자가 IdP 측 프로필 변경/삭제 시 starter-kit 에
  // 반영 안 되는 회귀.
  //
  // **best-effort 정책 (R9 strict 와 차이):** R9 (anonymous→소셜 신규 등록의
  // emailVerified 갱신) 는 보안 회귀 차단 의무 → strict throw. 본 R10-FOLLOWUP
  // 의 재로그인 프로필 refresh 는 UI freshness 정도 → best-effort + logger.warn
  // (R2 orphan cleanup 패턴과 동일). updateUser 실패가 caller 정상 path 차단
  // 하지 않음.
  //
  // **Pitfall 4 보존**: 본 블록은 db.runTransaction(...) 외부 — transaction
  // body 안으로 절대 이동 금지 (retry 마다 updateUser 다중 호출 위험).
  //
  // **PROFILE_REFRESH_POLICY 정책 분기**: profileFieldsForRefresh helper 가
  // 정책에 따라 분기 (truth-of-source = null clear, preserve = skip).
  // helper 가 빈 객체 반환 시 updateUser 호출 자체 skip (preserve + 모든
  // 필드 부재 케이스).
  //
  // helper 자체에 fix → kakao + naver + Phase 14~16 자동 상속 (D-08).
  //
  // **가입 수단 게이트 (quick 260928-jwe)**: 연결 기능 (Phase 16 · 16.7~16.9)
  // 뒤로 계정당 로그인 수단이 여럿이 되었다. 로그인 provider 기준으로 갱신하면
  // 연결 수단으로 한 번 로그인하기만 해도 계정 email 이 그 수단의 email 로
  // 바뀌고, `email_in_use` (getUserByEmail) 판정 기준이 옮겨 간다 (16.9-04
  // R1). 그래서 로그인 계정 `users/{uid}.signUpProviderId` 를 tx 밖에서 1회
  // 읽어 (readSignUpProviderId) 결과별로 처리한다:
  //   - found + 같은 provider (가입 수단 로그인) → 아래 기존 refresh 그대로.
  //   - found + 다른 값 (연결 수단 · native 가입 기록값) → 갱신 0 +
  //     logger.info `identity_index_profile_refresh_skipped_linked`.
  //   - missing (문서 · 필드 없음, 문자열 아님) → 갱신 0 (fail-closed) +
  //     logger.warn `identity_index_profile_refresh_signup_missing`.
  //   - read_failed → 갱신 0 (fail-closed) + logger.warn
  //     `identity_index_profile_refresh_signup_read_failed` (code 만).
  // 세 skip 분기 모두 throw 하지 않는다 — 로그인은 정상 완료. 로그 payload 는
  // event · uid · provider slug · code 뿐이다 (저장된 signUpProviderId 값 ·
  // userInfo · err.message 미포함, Pitfall 7).
  //
  // 형식 일치 근거: 신규 등록 tx 가 쓰는 값 (`signUpProviderId: provider`) 과
  // 여기 비교 키가 같은 `args.provider` (closed union ProviderId) 다. native
  // 가입은 클라이언트 recorder 가 Firebase providerId 형식 (`google.com` 등)
  // 으로만 기록하므로 CT slug 와 겹치지 않는다 → 정규화 불필요. 본인이
  // signUpProviderId 를 바꿀 수 있으나 (WR-12) 영향은 자기 계정 프로필 갱신
  // 여부뿐이다 (manual 「가입 수단 기록」 절 「위조 한계」).
  if (!result.isNewUser && result.uid && userInfo) {
    const signUp = await readSignUpProviderId(db, result.uid);
    if (signUp.kind === "read_failed") {
      logger.warn(
        {
          event: "identity_index_profile_refresh_signup_read_failed",
          uid: result.uid,
          provider,
          code: signUp.code,
        },
        "sign-up provider read failed; profile refresh skipped",
      );
    } else if (signUp.kind === "missing") {
      logger.warn(
        {
          event: "identity_index_profile_refresh_signup_missing",
          uid: result.uid,
          provider,
        },
        "sign-up provider missing; profile refresh skipped",
      );
    } else if (signUp.providerId !== provider) {
      logger.info(
        {
          event: "identity_index_profile_refresh_skipped_linked",
          uid: result.uid,
          provider,
        },
        "linked provider sign-in; profile refresh skipped",
      );
    } else {
      // 가입 수단 로그인 — 기존 R10-FOLLOWUP refresh 그대로.
      const refreshUpdate = profileFieldsForRefresh(
        PROFILE_REFRESH_POLICY,
        userInfo,
      );
      if (Object.keys(refreshUpdate).length > 0) {
        try {
          await getAuth().updateUser(result.uid, refreshUpdate);
        } catch (refreshErr: unknown) {
          // **Pitfall 7 보존**: err.message 본문 미로깅 (PII 가능성).
          // fingerprintError helper 가 err.code / err.name / non-Error throw
          // fingerprint 만 안전 추출 (WR-07).
          const errCode = fingerprintError(refreshErr);
          logger.warn(
            {
              event: "identity_index_profile_refresh_failed",
              uid: result.uid,
              code: errCode,
            },
            "profile refresh failed",
          );
          // 의도적으로 재던지지 않음 — outer call 정상 반환 (best-effort).
        }
      }
    }
  }

  return result;
}
