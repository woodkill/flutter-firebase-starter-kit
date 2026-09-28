// Phase 15 code review WR-01 / WR-02 — Custom Token endpoint 공용 에러 매핑.
//
// **WR-01 (4종 매핑 불일치):** 같은 실패 상황에 대해 provider 마다 다른
// HttpsError code 를 던지고 있었다. "IdP 가 자격증명 거부" 를 Naver 는
// `unauthenticated`, OIDC 3종은 `invalid-argument` 로; "IdP 인프라 장애" 를
// Naver 는 `unavailable`, OIDC 3종은 `internal` 로 매핑했다. 그 결과 동일한
// 장애에서 provider 마다 다른 안내가 나가고, Cloud Logging 에서 code 축으로
// 대시보드/알람을 걸 때 provider 마다 다른 축을 봐야 했다.
//
// 통일 축은 gRPC 표준 의미론을 따른다.
// - IdP 가 토큰을 거부 → `unauthenticated`
// - IdP 에 도달 실패 (transient) → `unavailable`
// - 서버 자체 결함 → `internal`
//
// **WR-02 (JWKS 장애 오분류):** jose 6.2.3 은 JWKS HTTP 응답이 200 이 아닐 때
// `JOSEError` 를 던진다 (`jwks/remote.js` — `JWKSTimeout` 및 "Expected 200 OK
// from the JSON Web Key Set HTTP response"). 이전 구현은 `instanceof JOSEError`
// 를 **무조건** 자격증명 무효로 매핑해서, IdP 의 JWKS 서버가 5xx 를 내거나
// 타임아웃이 나면 완전히 정상인 사용자 토큰이 "자격증명 무효" 로 처리됐다.
// 재시도 안내가 필요한 transient 장애가 영구 실패처럼 보이고, ops triage 에서
// `*_jwt_verify_failed` 한 버킷에 정상 실패와 인프라 장애가 섞였다.
//
// ---------------------------------------------------------------------------
// **IN-04 (Phase 15 리뷰) — `HttpsError` 의 message 는 ARB 키가 아니다.**
//
// 본 파일과 다른 callable 이 `HttpsError` 의 두 번째 인자로 넘기는
// `errorInvalidCredentials` / `errorInvalidArgument` / `errorUnknown` 등은
// **taxonomy 토큰** 이지 `lib/l10n/app_en.arb` 의 키가 아니다. 실제로
// `errorInvalidArgument` / `errorAnonymousLinkNotAllowed` /
// `errorAnonymousUnlinkNotAllowed` / `errorAccountAlreadyLinked` /
// `errorProviderAlreadyLinked` / `errorProviderNotLinked` /
// `errorUnlinkLastCredential` / `errorReauthenticationRequired` /
// `errorProviderConfig` / `errorAnonymousDisconnectNotAllowed` 는 ARB 에
// 존재하지 않는다 (나머지는 client 가 같은 어휘를 쓰는 우연의 일치다).
// 목록은 `grep -rhoE '"error[A-Z][A-Za-z]+"' functions/src | sort -u` 결과를
// ARB 3 locale 키와 대조해 확정한다 — 토큰을 추가하면 여기도 갱신하라.
//
// **client 는 서버 message 를 렌더하지 않는다.** `AuthRepository.
// _mapFunctionsException` 은 `FirebaseFunctionsException.code` 로만 분기해
// client 측 `AppException` 을 새로 만들고, 화면 문구는 그 `AppException.
// userMessage` 를 `resolveExceptionMessage` 가 번역한다. 서버 message 는
// 그 경로에 진입하지 않는다 (repo 전역 확인 — 서버 message 소비처 0건).
//
// 같은 모델의 선례가 이미 client 에 문서화되어 있다 —
// `errorReauthenticationRequired` 는 "ARB 키가 아니라 taxonomy 토큰" 이라고
// `app_en.arb` 의 `authReauthRequired` description 이 명시한다.
//
// 따라서 **ARB 키를 신설하지 않는다.** 소비처가 없는 키(Phase 15 리뷰가
// 제안한 3개를 포함해)를 3 locale 에 추가하는 것은 사용자 가치 0이고,
// "매핑되어 있다" 는 오인을 오히려 굳힌다.
// 다만 토큰이 ARB 키 형태를 흉내 내고 있어 후속 작업자가 오인하기 쉬우므로
// 그 계약을 여기 한 곳에 못박는다.
//
// **새 토큰을 추가할 때:** 사용자에게 보일 문구가 필요하면 서버 토큰이 아니라
// client 의 `AppException` 서브타입 + `resolveExceptionMessage` arm + ARB 키
// 를 추가하라. 서버 토큰만 늘리면 화면에는 아무 변화가 없다.
// ---------------------------------------------------------------------------
import {HttpsError} from "firebase-functions/https";
import {errors as joseErrors} from "jose";

/**
 * jose 에러 code 중 **JWKS 도달 실패** (transient) 를 의미하는 값.
 *
 * - `ERR_JWKS_TIMEOUT` — `JWKSTimeout` (jose 기본 5초 타임아웃 초과).
 * - `ERR_JOSE_GENERIC` — base `JOSEError`. jose 는 JWKS HTTP 응답이 200 이
 *   아닐 때 이 코드로 던진다 ("Expected 200 OK from the JSON Web Key Set
 *   HTTP response"). 서명/클레임 실패는 모두 전용 서브클래스 코드를 갖기
 *   때문에, base 코드로 도달하는 경로는 사실상 JWKS fetch 실패다.
 */
const JWKS_TRANSIENT_JOSE_CODES: readonly string[] = [
  "ERR_JWKS_TIMEOUT",
  "ERR_JOSE_GENERIC",
];

/**
 * IdP 가 자격증명을 거부했을 때의 표준 에러 (WR-01).
 *
 * @return {HttpsError} `unauthenticated` / `errorInvalidCredentials`.
 */
export function idpCredentialRejected(): HttpsError {
  return new HttpsError("unauthenticated", "errorInvalidCredentials");
}

/**
 * IdP 에 도달하지 못했을 때의 표준 에러 (WR-01 / WR-02 — transient).
 *
 * @return {HttpsError} `unavailable` / `errorServiceUnavailable`.
 */
export function idpUnavailable(): HttpsError {
  return new HttpsError("unavailable", "errorServiceUnavailable");
}

/**
 * 서버 자체 결함 (Firestore / admin SDK / JSON parse 등) 의 표준 에러.
 *
 * @return {HttpsError} `internal` / `errorUnknown`.
 */
export function serverFailure(): HttpsError {
  return new HttpsError("internal", "errorUnknown");
}

/**
 * 재인증 필요 거부의 `details.reason` 토큰 (Phase 16.9 review WR-01).
 *
 * `unauthenticated` 는 재인증 필요 외에도 IdP 자격증명 거부
 * ([idpCredentialRejected]) · App Check 차단 · auth token 무효
 * (firebase-functions 7.2.5 `common/providers/https.js` — details 없음)가
 * 공유한다. client 는 code 만으로는 셋을 구분할 수 없으므로, 재로그인으로
 * 해소되는 거부에만 이 reason 을 싣고 client 는 그 reason 일 때만 재로그인
 * 으로 보낸다 (fail-closed — reason 이 없으면 일시 오류로 안내).
 */
export const REAUTH_REQUIRED_REASON = "reauthentication_required";

/**
 * 재인증(fresh ID Token)이 필요할 때의 표준 에러 (Phase 16.9 review WR-01).
 *
 * 생성처: `assertFreshAuth`(auth_time 누락 · 미래값 · 300초 초과 —
 * `deleteUserAccount` 만 호출 · 연결 callable 은 quick 260928-cxs 로 제외) 와
 * 세 callable(`deleteUserAccount` · `linkCustomTokenProvider` ·
 * `linkNaverProvider`)의 `verifyIdToken(checkRevoked)` 실패. details 에는
 * reason 토큰 하나만 담는다 — uid · 토큰 등 식별자는 넣지 않는다 (PII
 * slug-only 정책 D-51 · [callerIdentityMismatch] 와 같은 원칙).
 *
 * @return {HttpsError} `unauthenticated` / `errorReauthenticationRequired` /
 *     `{reason: "reauthentication_required"}`.
 */
export function reauthenticationRequired(): HttpsError {
  return new HttpsError("unauthenticated", "errorReauthenticationRequired", {
    reason: REAUTH_REQUIRED_REASON,
  });
}

/**
 * 같은 provider 의 다른 신원이 이미 caller 계정에 연결돼 있을 때의
 * `details.reason` 토큰 (Phase 16.9 review IN-03).
 */
export const PROVIDER_ALREADY_LINKED_REASON = "provider_already_linked";

/**
 * caller 계정에 같은 provider 의 다른 신원이 이미 연결돼 있어 연결을 거부할
 * 때의 표준 에러 (Phase 16.9 review IN-03 — provider 당 신원 1개).
 *
 * Firebase 네이티브 `linkWithCredential` 의 `provider-already-linked` 를
 * mirror 한다. code 는 다른 계정 소유 거부(`errorAccountAlreadyLinked` —
 * details 없음)와 같은 `already-exists` 를 공유하고 client 는
 * `details.reason` 으로 가른다 — 두 거부 모두 「연결 대상이 이미 존재」 라는
 * gRPC 의미가 같고, reason 을 모르는 옛 client 가 받아도 「기존 연결을 해제한
 * 뒤 다시 시도」 안내가 해소 절차(기존 연결 해제)와 맞는다. `failed-precondition`
 * 은 옛 client 에서 「잠시 후 다시 시도」 로 떨어져 재시도 루프가 된다.
 * details 에는 reason 토큰 하나만 담는다 — providerUserId 등 식별자는 넣지
 * 않는다 (PII slug-only 정책 D-51).
 *
 * @return {HttpsError} `already-exists` / `errorProviderAlreadyLinked` /
 *     `{reason: "provider_already_linked"}`.
 */
export function providerAlreadyLinked(): HttpsError {
  return new HttpsError("already-exists", "errorProviderAlreadyLinked", {
    reason: PROVIDER_ALREADY_LINKED_REASON,
  });
}

/**
 * 정식 로그인 caller 가 자기 계정에 매핑되지 않은 identity 로 Custom Token
 * 로그인을 요청했을 때의 표준 에러 (debug reauth-login-auto-merge).
 *
 * `permission-denied` 는 `deleteUserAccount` · `linkCustomTokenProvider` ·
 * `linkNaverProvider` 의 uid 불일치 throw(`errorUnauthenticated`)와 code 를
 * 공유하므로 client 는 `details.reason` 으로 구분한다
 * (`AuthRepository._mapFunctionsException` → `ReauthUserMismatch`). App Check
 * 차단은 firebase-functions 7.2.5 가 `unauthenticated` 로 던지므로 이 code 를
 * 공유하지 않는다. details 에는 reason 토큰 하나만 담는다 — uid · sub · email
 * 등 식별자는 넣지 않는다 (PII slug-only 정책 D-51 과 같은 원칙).
 *
 * @return {HttpsError} `permission-denied` / `errorReauthUserMismatch` /
 *     `{reason: "caller_identity_mismatch"}`.
 */
export function callerIdentityMismatch(): HttpsError {
  return new HttpsError("permission-denied", "errorReauthUserMismatch", {
    reason: "caller_identity_mismatch",
  });
}

/**
 * provider 측 설정 결함 거부의 `details.reason` 토큰 (Phase 16.10 D-12).
 */
export const PROVIDER_CONFIG_REASON = "provider_config";

/**
 * provider 측 자격증명 · 콘솔 설정 결함으로 끊기가 거부됐을 때의 표준 에러
 * (Phase 16.10 D-12 · T-16.10-09).
 *
 * 대상: 어드민 키 무효 · 「사용 가능 API」 미허용 · app token 무효 · client
 * 인증 실패처럼 **운영자 설정** 이 원인인 거부다. 재시도로 해소되지 않으므로
 * 일시 오류([idpUnavailable])와 code 를 나눈다 — client 는 행 실패 → 건너뛰기
 * 안내로, 운영자는 Cloud Logging 의 reason 축으로 설정 결함을 찾는다.
 * details 에는 reason 토큰 하나만 담는다 — 키 · 회원번호 · provider 응답
 * 본문 등 식별자는 넣지 않는다 (PII slug-only 정책 D-51).
 *
 * @return {HttpsError} `failed-precondition` / `errorProviderConfig` /
 *     `{reason: "provider_config"}`.
 */
export function providerConfigError(): HttpsError {
  return new HttpsError("failed-precondition", "errorProviderConfig", {
    reason: PROVIDER_CONFIG_REASON,
  });
}

/**
 * 익명 caller 거부의 `details.reason` 토큰 (Phase 16.10 C-06 — 16.8 해제
 * callable 의 인라인 값과 같다).
 */
export const ANONYMOUS_CALLER_REASON = "anonymous_caller";

/**
 * 익명 caller 가 provider 연결 끊기를 요청했을 때의 표준 에러 (Phase 16.10
 * C-06).
 *
 * 익명 계정에는 끊을 provider 연결이 없다. provider · Firestore 호출 전에
 * 거부한다. code · reason 은 16.8 `unlinkCustomTokenProvider` 의 익명 거부와
 * 같은 값이라 client 는 같은 분기로 처리한다.
 *
 * @return {HttpsError} `failed-precondition` /
 *     `errorAnonymousDisconnectNotAllowed` / `{reason: "anonymous_caller"}`.
 */
export function anonymousDisconnectNotAllowed(): HttpsError {
  return new HttpsError(
    "failed-precondition",
    "errorAnonymousDisconnectNotAllowed",
    {reason: ANONYMOUS_CALLER_REASON},
  );
}

/**
 * 호출자 입력이 계약을 벗어났을 때의 표준 에러.
 *
 * @return {HttpsError} `invalid-argument` / `errorInvalidArgument`.
 */
export function invalidArgument(): HttpsError {
  return new HttpsError("invalid-argument", "errorInvalidArgument");
}

/**
 * jose verify 에러의 PII-safe fingerprint 를 만든다 (Pitfall 1/7).
 *
 * `err.message` / `err.payload` / `err.claim` / `err.reason` 본문은 절대
 * 노출하지 않는다. `err.code` (jose 6.x stable public API) 또는 `err.name`
 * 만 short fingerprint 로 반환한다 — 운영 시 JWKS 네트워크 / kid not found /
 * clock skew / signature mismatch 등 분류가 가능하다.
 *
 * @param {unknown} err catch (err: unknown) 의 err.
 * @return {string} logger `code` 필드용 fingerprint.
 */
export function fingerprintJoseError(err: unknown): string {
  if (err instanceof joseErrors.JOSEError) {
    return err.code ?? err.name;
  }
  if (err instanceof Error) {
    return err.name;
  }
  return "unknown";
}

/**
 * OIDC ID Token 검증 실패를 표준 HttpsError 로 분류한다 (WR-01 / WR-02).
 *
 * 분류 기준:
 * 1. JWKS 도달 실패 계열 (`ERR_JWKS_TIMEOUT` / `ERR_JOSE_GENERIC`) →
 *    [idpUnavailable] — 정상 토큰이 인프라 장애로 거부되는 것이므로 사용자
 *    에게는 재시도 안내가 맞다.
 * 2. 그 외 `JOSEError` (서명 불일치 / 클레임 검증 실패 / kid 부재 / 만료) →
 *    [idpCredentialRejected].
 * 3. 비-`JOSEError` (DNS 실패 / ECONNREFUSED 는 fetch 가 `TypeError` 로
 *    던진다) → [idpUnavailable]. 이전에는 이 경로만 `internal` 로 빠져서
 *    한 가지 장애 계열이 세 갈래로 흩어졌다 (Naver 는 같은 계열을
 *    `unavailable` 하나로 모은다).
 *
 * @param {unknown} err verifier 가 던진 에러.
 * @return {HttpsError} 위 기준으로 분류된 표준 에러.
 */
export function mapOidcVerifyError(err: unknown): HttpsError {
  if (err instanceof joseErrors.JOSEError) {
    const code = err.code;
    if (typeof code === "string" && JWKS_TRANSIENT_JOSE_CODES.includes(code)) {
      return idpUnavailable();
    }
    return idpCredentialRejected();
  }
  // fetch 계열 실패 (DNS / ECONNREFUSED / abort) — transient.
  return idpUnavailable();
}
