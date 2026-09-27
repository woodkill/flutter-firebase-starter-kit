// Phase 16.5 D-13 — Naver access_token 검증 → Firebase Custom Token 발급 공용
// helper.
//
// Phase 13 `naverCustomToken` 의 Step 2~6 (Naver REST 검증 → identity index →
// Custom Token → terms mirror → issued log) 을 동작 · 로그 event 이름 불변으로
// 옮겨 왔다. 두 진입점이 공유한다.
// - `naverCustomToken` (1-tap SDK 경로) — client 가 access_token 을 직접 넘긴다.
// - `naverWebCustomToken` (킷 소유 웹 경로) — 서버가 authorization code 를
//   access_token 으로 교환한 뒤 넘긴다.
//
// 본 helper 는 onCall `request` 를 모른다 (PC-11) — caller 정보 · terms
// snapshot 은 호출자가 파싱해서 넘긴다. logger event 이름은 Cloud Logging
// 대시보드 축이므로 한 글자도 바꾸지 말 것
// (`functions/test/auth/naver_custom_token.test.ts` 가 잠근다). 두 경로의
// 구분은 이벤트 이름이 아니라 payload 의 `path` 필드("app" | "web")로 한다
// (16.5 review IN-02).
import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";

import {
  callerIdentityMismatch,
  idpCredentialRejected,
  idpUnavailable,
  serverFailure,
} from "../shared/custom_token_errors";
import type {TermsAcceptanceJson} from "../shared/terms_acceptance_json";
import {buildAccountExistsError} from "./account_exists_error";
import {resolveIdentity} from "./identity_index";
import {mirrorTermsAccepted} from "./mirror_terms";

// Phase 13 D-46 / D-47 — Naver REST 검증 endpoint.
const NAVER_PROFILE_URL = "https://openapi.naver.com/v1/nid/me" as const;

// Phase 13 Pitfall 3 — Naver REST 5xx 무한 hang 방어.
// Cloud Function 30s timeout 까지 도달하기 전 5s 에서 abort.
// IN-04 (16.5 review 2회차) — `AbortSignal.timeout` 이라 헤더 수신뿐 아니라
// `resp.json()` 본문 읽기까지 이 5s 안에 끝나야 한다.
const FETCH_TIMEOUT_MS = 5000;

// Naver `/v1/nid/me` 응답 본문 shape (D-47).
// resultcode='00' + response.id 가 정상 path. 본 Phase 13 단계에서는 email
// claim 만 (옵션) 사용 — name / nickname / profile_image / age / gender /
// birthday 등 추가 PII 는 의도적으로 미사용 (D-51 PII 최소 수집).
type NaverProfileResponse = {
  resultcode?: string;
  message?: string;
  response?: {
    id?: string;
    email?: string;
    // R10: 동의 항목 활성화 + 사용자 동의 시 포함 — Firebase Auth user.
    // displayName / photoURL 로 propagate.
    nickname?: string;
    profile_image?: string;
  };
};

/**
 * Naver 로그인 진입 경로 — helper 로그 payload 의 `path` 필드 (16.5 review
 * IN-02). event 이름은 두 경로 공용으로 불변 (대시보드 축 유지) 이고, 경로
 * 구분은 이 필드로 한다.
 * - `"app"` — `naverCustomToken` (1-tap SDK 경로)
 * - `"web"` — `naverWebCustomToken` (킷 소유 웹 경로)
 * - `"link_app"` — `linkNaverProvider` 1-tap 모양 (Phase 16.9 계정 연결)
 * - `"link_web"` — `linkNaverProvider` 웹 모양 (Phase 16.9 계정 연결)
 */
export type NaverSignInPath = "app" | "web" | "link_app" | "link_web";

/**
 * [fetchNaverProfile] 결과 — `/v1/nid/me` 가 검증한 Naver 신원.
 *
 * `id` 만 필수다. 나머지는 동의 항목 활성화 + 사용자 동의 시에만 채워지며,
 * 로그인 발급 경로만 읽는다 (계정 연결은 `id` 만 소비 — Phase 16.9 C-06).
 */
export type NaverVerifiedProfile = {
  id: string;
  email?: string;
  nickname?: string;
  profileImage?: string;
};

/**
 * [verifyNaverProfileAndIssueCustomToken] 입력.
 *
 * 호출자가 onCall `request` 에서 미리 계산해 넘긴다 — helper 는 `request`
 * shape 에 의존하지 않는다 (PC-11).
 */
export type NaverProfileToCustomTokenInput = {
  /** 검증할 Naver access_token (호출자가 타입 · 길이 · CRLF 검증 완료). */
  accessToken: string;
  /** onCall `request.auth?.uid` — 미인증 호출이면 undefined (D-49). */
  callerUid: string | undefined;
  /** `isAnonymousCaller(request.auth)` 결과 — 비익명 caller 가드 입력. */
  callerIsAnonymous: boolean;
  /**
   * `parseTermsAcceptanceJson(request.data?.termsAcceptanceSnapshot)` 결과.
   * 부재 · 검증 실패면 null (mirror skip, 로그인은 계속).
   */
  termsSnapshot: TermsAcceptanceJson | null;
  /** 진입 경로 — 모든 helper 로그 payload 에 `path` 로 싣는다 (IN-02). */
  path: NaverSignInPath;
};

/** Naver Custom Token callable 공용 응답 — 토큰 · uid · 신규 여부만. */
export type NaverCustomTokenResult = {
  customToken: string;
  uid: string;
  isNewUser: boolean;
};

/**
 * Naver access_token 을 `/v1/nid/me` 로 검증하고 신원을 돌려준다 (검증 전용).
 *
 * Phase 16.9 D-01 — [verifyNaverProfileAndIssueCustomToken] 의 앞부분
 * (fetch → status → 본문 → resultcode → id)을 동작 · event 이름 불변으로
 * 옮겨 왔다. 로그인 발급 경로와 계정 연결(`linkNaverProvider`)이 공유한다.
 * 전역 `fetch` 는 정확히 1회 — 재시도 · 사전 probe 없음.
 *
 * 매핑 (WR-01 공용 표 — shared/custom_token_errors.ts):
 * - fetch reject (TimeoutError / network) → unavailable + `naver_fetch_failed`
 * - HTTP 401/403 → unauthenticated + `naver_verify_unauthenticated`
 * - HTTP 5xx → unavailable + `naver_verify_unavailable`
 * - HTTP 기타 non-OK → unavailable + `naver_verify_failed`
 * - 본문 읽기 TimeoutError → unavailable + `naver_fetch_failed` (IN-04)
 * - 그 외 JSON parse 실패 → internal + `naver_parse_failed`
 * - resultcode != '00' → unauthenticated + `naver_resultcode_non_success`
 * - response.id 부재 → unauthenticated + `naver_response_id_missing`
 *
 * **PII 금지 (D-51):** logger payload 는 {event, path, status?, resultcode?,
 * code?} 만. access_token · 응답 본문(id / email / nickname 등)은 절대 logger
 * 인자에 싣지 않는다. err.message 미노출 — err.name 만 fingerprint.
 *
 * @param {{accessToken: string, path: NaverSignInPath}} input 검증할
 *     access_token (호출자가 타입 · 길이 · CRLF 검증 완료) 과 로그 경로 축.
 * @return {Promise<NaverVerifiedProfile>} 검증된 Naver 신원 (`id` 필수).
 * @throws {HttpsError} 위 매핑 표에 따른 표준 에러.
 */
export async function fetchNaverProfile(input: {
  accessToken: string;
  path: NaverSignInPath;
}): Promise<NaverVerifiedProfile> {
  const {accessToken, path} = input;

  let resp: Response;
  try {
    resp = await fetch(NAVER_PROFILE_URL, {
      method: "GET",
      headers: {Authorization: `Bearer ${accessToken}`},
      // IN-04 — 헤더 + 본문(resp.json) 전체 5s. 초과 시 TimeoutError.
      signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
    });
  } catch (err: unknown) {
    // PII 금지 (D-51) — err.message 본문 미로깅. err.name 만 fingerprint
    // (TimeoutError / TypeError / DNS 실패 등 분류 가능).
    const errCode = err instanceof Error ? err.name : "unknown";
    logger.warn(
      {event: "naver_fetch_failed", path, code: errCode},
      "Naver REST fetch failed",
    );
    // TimeoutError / TypeError(network) / DNS 실패 모두 unavailable.
    // WR-01: 4 endpoint 공용 매핑 표 (IdP 도달 실패 = transient).
    throw idpUnavailable();
  }

  if (resp.status === 401 || resp.status === 403) {
    logger.warn(
      {event: "naver_verify_unauthenticated", path, status: resp.status},
      "Naver access token rejected",
    );
    throw idpCredentialRejected();
  }
  if (resp.status >= 500) {
    logger.warn(
      {event: "naver_verify_unavailable", path, status: resp.status},
      "Naver REST 5xx",
    );
    throw idpUnavailable();
  }
  if (!resp.ok) {
    // 4xx 외 (예: 429 rate limit) — unavailable 로 일반화 + status fingerprint.
    logger.warn(
      {event: "naver_verify_failed", path, status: resp.status},
      "Naver REST non-OK",
    );
    throw idpUnavailable();
  }

  let responseBody: NaverProfileResponse;
  try {
    responseBody = (await resp.json()) as NaverProfileResponse;
  } catch (err: unknown) {
    const errCode = err instanceof Error ? err.name : "unknown";
    if (errCode === "TimeoutError") {
      // IN-04 — 본문 읽기 도중 5s 초과는 헤더 전 timeout 과 같은 IdP 도달
      // 실패다. event · 매핑 모두 fetch reject 분기와 같게 둔다 (event 이름
      // 신설 없음 — 대시보드 축 불변).
      logger.warn(
        {event: "naver_fetch_failed", path, code: errCode},
        "Naver REST fetch failed",
      );
      throw idpUnavailable();
    }
    logger.warn(
      {event: "naver_parse_failed", path, code: errCode},
      "Naver REST JSON parse failed",
    );
    throw serverFailure();
  }

  if (responseBody.resultcode !== "00") {
    // resultcode 는 Naver 공식 코드 ('00' / '024' / '028' 등) — non-PII.
    logger.warn(
      {
        event: "naver_resultcode_non_success",
        path,
        resultcode: responseBody.resultcode,
      },
      "Naver resultcode not 00",
    );
    throw idpCredentialRejected();
  }

  const naverUserId = responseBody.response?.id;
  if (
    !naverUserId ||
    typeof naverUserId !== "string" ||
    naverUserId.length === 0
  ) {
    // Pitfall 4 — resultcode='00' but response.id missing →
    // undefined createCustomToken 방어. resultcode 도 함께 기록 (WR-06)
    // — Naver API 가 success code 를 반환했는데 id 가 누락된 케이스 vs.
    // 다른 unexpected status 로 분기 (어차피 본 분기는 resultcode='00'
    // 만 도달하지만 ops triage 시 fingerprint 일관성 + 회귀 가드).
    logger.error(
      {
        event: "naver_response_id_missing",
        path,
        resultcode: responseBody.resultcode,
      },
      "Naver response.id missing",
    );
    // WR-01: IdP 가 id 없는 응답을 준 경우도 "자격증명 사용 불가" 축으로
    // 통일한다 (4 endpoint 공용 매핑 표).
    throw idpCredentialRejected();
  }
  return {
    id: naverUserId,
    email: responseBody.response?.email,
    nickname: responseBody.response?.nickname,
    profileImage: responseBody.response?.profile_image,
  };
}

/**
 * Naver access_token 을 `/v1/nid/me` 로 검증하고 Firebase Custom Token 을 발급한다.
 *
 * 흐름 (Phase 13 D-46~D-51 · Phase 16 D-13/D-14):
 * 1. Node fetch + `AbortSignal.timeout`(5s · 헤더 + 본문 읽기 전체, IN-04) →
 *    Authorization: Bearer (D-46/D-48).
 *    WR-01: 아래 매핑은 4 endpoint 공용 표
 *    (shared/custom_token_errors.ts) 를 따른다.
 *    - HTTP 401/403 → unauthenticated (errorInvalidCredentials)
 *    - HTTP 5xx → unavailable (errorServiceUnavailable)
 *    - HTTP 기타 4xx (예: 429) → unavailable (errorServiceUnavailable)
 *    - TimeoutError(5s 초과) / network → unavailable (errorServiceUnavailable)
 * 2. JSON parse → resultcode='00' + response.id 검증 (D-47).
 *    - 본문 읽기 중 5s 초과(TimeoutError) → unavailable + `naver_fetch_failed`
 *      (1 의 timeout 과 같은 결과 · 같은 event — IN-04)
 *    - 그 외 JSON parse 실패 → internal (errorUnknown)
 *    - resultcode != '00' → unauthenticated (errorInvalidCredentials)
 *    - response.id 부재 → unauthenticated (errorInvalidCredentials)
 * 3. resolveIdentity helper (Phase 12.1 D-31~D-34 자동 상속).
 *    - resolveIdentity throw → internal (errorUnknown)
 * 4. caller switch on conflictKind (D-32 carry-forward).
 *    - 'email_in_use' → already-exists
 *      (errorAccountExistsWithDifferentCredential)
 *    - 'anonymous_existing_collision' → 동일
 *    - 'caller_identity_mismatch' → permission-denied (errorReauthUserMismatch)
 * 5. createCustomToken — 1h 만료. throw → internal (errorUnknown).
 * 6. termsSnapshot 이 있고 isNewUser 일 때만 termsAccepted mirror
 *    (Phase 16 D-13/D-14 · WR-01 게이트). 실패 → internal (errorUnknown).
 * 7. issued structured log 후 결과 반환.
 *
 * **PII 금지 (D-51, Phase 11 D-08):** logger payload 는 {event, path, uid?,
 * isNewUser?, status?, resultcode?, code?} 만. `path` 는 진입 경로 (IN-02 —
 * 같은 event 이름을 1-tap · 웹이 공유하므로 경로 구분 축). Naver
 * `/v1/nid/me` response 본문 (id / email / name / nickname / profile_image /
 * age / gender /
 * birthday) 은 절대 logger 인자에 포함 금지. err.message 미노출 — err.name
 * 만 fingerprint 로 노출 (Pitfall 1/7).
 *
 * @param {NaverProfileToCustomTokenInput} input 검증 대상 access_token 과
 *     호출자가 계산한 caller 정보 · terms snapshot.
 * @return {Promise<NaverCustomTokenResult>} customToken + uid + isNewUser.
 * @throws {HttpsError} 위 흐름의 매핑 표에 따른 표준 에러
 *     (shared/custom_token_errors.ts · account_exists_error.ts).
 */
export async function verifyNaverProfileAndIssueCustomToken(
  input: NaverProfileToCustomTokenInput,
): Promise<NaverCustomTokenResult> {
  const {accessToken, callerUid, callerIsAnonymous, termsSnapshot, path} =
    input;

  // Step 2: Naver REST 검증 (D-46/D-47/D-48) — 검증 전용 helper 로 분리
  // (Phase 16.9 D-01). fetch 1회 · event 이름 · 매핑은 helper 안에서 불변.
  const profile = await fetchNaverProfile({accessToken, path});
  const naverUserId = profile.id;
  const naverEmail = profile.email;
  // R10: response.nickname + response.profile_image 추출 → Firebase Auth
  // user record 의 displayName / photoURL 에 propagate. 동의 항목 활성화 +
  // 사용자 동의 시에만 응답에 포함 — 부재 시 undefined (silent).
  const naverNickname = profile.nickname;
  const naverProfileImage = profile.profileImage;

  // Step 3: Identity Index resolve (Phase 12.1 D-31~D-34 자동 상속).
  // helper 가 conflictKind 로 detect → caller 가 try/catch + switch 로 안전한
  // already-exists HttpsError 변환 (email enumeration 차단). helper 의
  // unexpected throw 는 internal 매핑 (D-32 fallback).
  // callerUid — unauthenticated 허용 (D-49).
  // callerIsAnonymous — debug reauth-login-auto-merge: 정식 로그인 caller 는
  // 자기 계정에 매핑된 identity 로만 통과한다 (resolveIdentity 비익명 caller
  // 가드, fail-closed). 두 값 모두 호출자가 onCall request 에서 계산해 넘긴다.
  const userInfo: {
    email?: string;
    emailVerified?: boolean;
    displayName?: string;
    photoURL?: string;
  } = {};
  if (naverEmail) userInfo.email = naverEmail;
  // WR-04: Naver `/v1/nid/me` 는 REST API 라 email_verified 표준 claim 이
  // 없다. 아래 developerClaims 주석과 **같은 가정** ("응답에 email 이 있으면
  // verified") 을 user record 에도 명시적으로 적용한다 — 두 곳이 서로 다른
  // 값을 쓰던 모순을 제거한다. 가정을 뒤집으려면 두 곳을 함께 바꿀 것.
  if (naverEmail) userInfo.emailVerified = true;
  if (naverNickname) userInfo.displayName = naverNickname;
  if (naverProfileImage) userInfo.photoURL = naverProfileImage;
  let resolution;
  try {
    resolution = await resolveIdentity(getFirestore(), {
      provider: "naver",
      providerUserId: naverUserId,
      callerUid,
      callerIsAnonymous,
      userInfo: Object.keys(userInfo).length > 0 ? userInfo : undefined,
    });
  } catch {
    // PII 보존 — catch parameter 생략 (D-40 / D-51, Phase 12 동일 패턴).
    // err 객체 접근 안 함 → 누구도 실수로 PII 로깅 못 함 (compile-time 보장).
    logger.error(
      {event: "identity_index_failed", path},
      "resolveIdentity threw unexpected error",
    );
    throw serverFailure();
  }

  // Step 4: caller switch on conflictKind (Phase 12.1 D-32 carry-forward).
  // exhaustive switch — TypeScript 가 conflictKind union 의 모든 case 강제.
  switch (resolution.conflictKind) {
  case "email_in_use":
    logger.warn(
      {event: "naver_email_collision", path},
      "Naver email collides with existing account",
    );
    // 16-13: existingProvider slug 를 details 로 전달 (client sheet 분기 wiring).
    throw buildAccountExistsError(resolution.existingProvider);
  case "anonymous_existing_collision":
    logger.warn(
      {event: "naver_anonymous_conflict", path},
      "Anonymous user attempted to login with existing Naver identity",
    );
    // 16-13: anonymous collision 도 resolution.existingProvider (= 호출
    // provider slug) 를 details 로 전달.
    throw buildAccountExistsError(resolution.existingProvider);
  case "caller_identity_mismatch":
    // debug reauth-login-auto-merge — 정식 로그인 caller 가 자기 계정에
    // 매핑되지 않은 Naver identity 로 호출 (재인증 화면에서 다른 계정 ·
    // 미연결 계정 선택). identity 등록 · 프로필 변경 없이 거부한다.
    // already-exists 로 보내면 client 가 계정 연결 시트를 열어 다시 같은
    // callable 로 돌아오므로 전용 reason 으로 구분한다.
    logger.warn(
      {event: "naver_caller_identity_mismatch", path},
      "Signed-in caller used a Naver identity not mapped to it",
    );
    throw callerIdentityMismatch();
  case null:
    break; // 정상 flow.
  }

  const {uid, isNewUser} = resolution;

  // Step 5: Custom Token 발급 (admin SDK — 1h 만료).
  // CR-01 (Phase 13 review): admin SDK throw (auth/internal-error,
  // auth/insufficient-permission 등) 도 internal + errorUnknown 으로 매핑.
  // 미적용 시 raw err.message 가 Cloud Functions runtime 의 INTERNAL 응답에
  // 그대로 노출 — D-08 PII 정책 위반.
  //
  // (Phase 9.2 Gap B 옵션 C — HUMAN-UAT 2026-05-11):
  //
  // 비-충돌 정상 path 에서 createCustomToken 의 developerClaims 인자로
  // userInfo.email 명시 — Firebase Admin SDK 가 client 의
  // getIdTokenResult().claims.email 로 propagate. 사용자 user.email=null
  // 회귀 차단 (Gap B 의 비-충돌 신규 가입 path 보조).
  //
  // **scope 제약**: userInfo.email 가 validated 상태 (Naver REST response.email
  // 정상 반환) 에서만 추가. 부재 시 undefined (Firebase Admin SDK 기본 동작).
  // 충돌 path (conflictKind!==null) 는 switch 가 throw 우선해서 createCustomToken
  // 자체 미도달 → developerClaims 발급 0 (의도된 동작).
  //
  // **PII 정책**: developerClaims 는 Firebase Auth user record 의 idToken
  // claim 으로만 propagate — logger 어디에도 email 본문 미노출 (D-51).
  //
  // Phase 17 (Account Linking) — see ROADMAP.md
  //
  // IN-04: Naver `/v1/nid/me` 는 OIDC 가 아니라 REST API 이며
  // email_verified 표준 claim 미제공. Naver 정책상 `email` 필드는 사용자
  // 동의 시 항상 반환되며 verification 상태 구분이 응답에 없다 — 따라서
  // 본 starter-kit 은 **"Naver 응답에 email 이 포함되어 있다면 verified"**
  // 라는 가정을 채택하고 email_verified=true 를 명시 발급. Naver 가
  // unverified email 도 응답에 포함하는 정책 변경 시 본 가정 재검토 필요
  // (Naver 개발자 공지 / Changelog 추적). Kakao 와 달리 IdP 측 grounding
  // claim 이 없으므로 starter-kit 측 정책 결정 영역 — 사용자 fork 시
  // 본 단락 한 줄 (`email_verified: true` → `false`) 변경 가능.
  const developerClaims = userInfo.email ?
    {email: userInfo.email, email_verified: true} :
    undefined;
  let customToken: string;
  try {
    customToken = await getAuth().createCustomToken(uid, developerClaims);
  } catch (err: unknown) {
    // PII 금지 (D-51) — err.message 본문 미로깅. err.name 만 fingerprint.
    const errCode = err instanceof Error ? err.name : "unknown";
    logger.error(
      {event: "naver_custom_token_create_failed", path, code: errCode},
      "createCustomToken threw",
    );
    throw serverFailure();
  }

  // Step 5.5 (Phase 16 D-13/D-14 — Plan 16-03 Task 3.2):
  // termsAcceptanceSnapshot atomic mirror — Phase 14.1 A6 root cause fix
  // 의 Custom Token branch. {merge:true} 의무. snapshot=null 시 skip.
  // PII 정책 보존 — snapshot 본체 미노출, version 만 logger payload 노출.
  // WR-02: callable arg 는 신뢰할 수 없는 임의 JSON 이다 — 호출자가
  // parseTermsAcceptanceJson 으로 5 필드 타입을 런타임 검증해 좁혀 넘긴다.
  // 실패 시 null (필드 무시, 로그인은 계속).
  //
  // WR-01: isNewUser 게이트 — mirror 는 users/{uid} 문서가 새로
  // 만들어지는 시점에만 수행한다. 게이트 없이 매 Custom Token 로그인마다
  // set 하면, 기기에 device-local 동의가 남은 상태로 기존 계정에 재로그인할
  // 때 서버의 권위 있는 termsAccepted 가 device-local 값으로 덮어씌워진다
  // (acceptedAt 뿐 아니라 marketing opt-in 과 version 까지). client 측
  // TermsNotifier.mirrorToFirestore 의 pre-read + skip (Plan 10-12
  // multi-user invariant) 과 대칭인 서버측 가드다.
  if (termsSnapshot && isNewUser) {
    try {
      // WR-07: write + 로깅은 공용 helper 단일 진실원 (5회 verbatim 복제
      // 제거). 검증은 호출자의 parseTermsAcceptanceJson 이 이미 수행했다.
      await mirrorTermsAccepted({
        uid,
        snapshot: termsSnapshot,
        successEvent: "naver_terms_acceptance_mirrored",
        failureEvent: "naver_terms_acceptance_mirror_failed",
      });
    } catch {
      // helper 가 이미 PII-safe fingerprint 로 logger.error 를 남겼다.
      throw serverFailure();
    }
  }

  // Step 6: structured log — uid + isNewUser 만 (PII 금지 D-51).
  logger.info(
    {event: "naver_custom_token_issued", path, uid, isNewUser},
    "Naver custom token issued",
  );

  return {customToken, uid, isNewUser};
}
