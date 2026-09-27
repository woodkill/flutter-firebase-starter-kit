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
// `errorAccountAlreadyLinked` / `errorReauthenticationRequired` 는 ARB 에
// 존재하지 않는다 (나머지는 client 가 같은 어휘를 쓰는 우연의 일치다).
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
// 따라서 **ARB 키를 신설하지 않는다.** 소비처가 없는 키 3개를 3 locale 에
// 추가하는 것은 사용자 가치 0이고, "매핑되어 있다" 는 오인을 오히려 굳힌다.
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
 * 정식 로그인 caller 가 자기 계정에 매핑되지 않은 identity 로 Custom Token
 * 로그인을 요청했을 때의 표준 에러 (debug reauth-login-auto-merge).
 *
 * `permission-denied` 는 `deleteUserAccount` · `linkCustomTokenProvider` 의
 * uid 불일치 throw(`errorUnauthenticated`)와 code 를 공유하므로 client 는
 * `details.reason` 으로 구분한다 (`AuthRepository._mapFunctionsException` →
 * `ReauthUserMismatch`). App Check 차단은 firebase-functions 7.2.5 가
 * `unauthenticated` 로 던지므로 이 code 를 공유하지 않는다. details 에는
 * reason 토큰 하나만 담는다 — uid · sub · email 등 식별자는 넣지 않는다
 * (PII slug-only 정책 D-51 과 같은 원칙).
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
