/**
 * Custom Token 공용 에러 매핑 회귀 테스트 (Phase 15 리뷰 WR-01 / WR-02).
 *
 * **WR-01:** 같은 실패 상황에 4 endpoint 가 서로 다른 HttpsError code 를 써서
 * (Naver `unauthenticated`/`unavailable` vs OIDC 3종
 * `invalid-argument`/`internal`) 동일 장애에서 사용자 안내가 달라지고 ops
 * 대시보드도 provider 마다 다른 축을 봐야 했다.
 *
 * **WR-02:** jose 6.2.3 은 JWKS HTTP 응답이 200 이 아닐 때 `JOSEError` 를
 * 던진다 (`JWKSTimeout` / base `JOSEError`). 이전 구현은
 * `instanceof JOSEError` 를 **무조건** 자격증명 무효로 매핑해서, IdP 의 JWKS
 * 서버가 5xx 를 내거나 타임아웃이 나면 완전히 정상인 사용자 토큰이
 * "자격증명 무효" 로 처리됐다 — 재시도 안내가 필요한 transient 장애가 영구
 * 실패처럼 보이는 회귀다.
 *
 * jose 는 `jest.config.js` 의 moduleNameMapper 로 `test/mocks/jose.ts` 에
 * 매핑되며, 그 stub 의 `code` 값은 실제 jose 6.2.3 을 verbatim mirror 한다.
 */

// eslint-disable-next-line import/first
import {errors as joseErrors} from "jose";

// eslint-disable-next-line import/first
import {
  ANONYMOUS_CALLER_REASON,
  anonymousDisconnectNotAllowed,
  fingerprintJoseError,
  idpCredentialRejected,
  idpUnavailable,
  invalidArgument,
  mapOidcVerifyError,
  PROVIDER_ALREADY_LINKED_REASON,
  PROVIDER_CONFIG_REASON,
  providerAlreadyLinked,
  providerConfigError,
  reauthenticationRequired,
  REAUTH_REQUIRED_REASON,
  serverFailure,
} from "../../src/shared/custom_token_errors";

describe("표준 에러 팩토리 — WR-01 공용 매핑 표", () => {
  it("IdP 자격증명 거부 = unauthenticated / errorInvalidCredentials", () => {
    expect(idpCredentialRejected()).toMatchObject({
      code: "unauthenticated",
      message: "errorInvalidCredentials",
    });
  });

  // 16.9 review WR-01: 같은 `unauthenticated` 를 쓰는 재인증 필요와 IdP
  // 거부를 client 가 details.reason 으로만 가른다 — 재인증만 reason 을
  // 싣고 IdP 거부는 싣지 않는다.
  it("재인증 필요 = unauthenticated + details.reason 토큰", () => {
    expect(REAUTH_REQUIRED_REASON).toBe("reauthentication_required");
    expect(reauthenticationRequired()).toMatchObject({
      code: "unauthenticated",
      message: "errorReauthenticationRequired",
      details: {reason: "reauthentication_required"},
    });
  });

  // 16.9 review IN-03: 다른 계정 소유 거부(details 없음)와 같은 code 를
  // 공유하므로 client 는 reason 으로만 「이 계정에 이미 연결」 을 가른다.
  it("provider 당 신원 1개 = already-exists + details.reason 토큰", () => {
    expect(PROVIDER_ALREADY_LINKED_REASON).toBe("provider_already_linked");
    expect(providerAlreadyLinked()).toMatchObject({
      code: "already-exists",
      message: "errorProviderAlreadyLinked",
      details: {reason: "provider_already_linked"},
    });
  });

  // 16.10 D-12: provider 측 설정 결함은 재시도로 해소되지 않으므로
  // 일시 오류(unavailable)와 code 를 나누고 reason 으로 운영 신호를 준다.
  it("provider 설정 결함 = failed-precondition + provider_config reason", () => {
    expect(PROVIDER_CONFIG_REASON).toBe("provider_config");
    expect(providerConfigError()).toMatchObject({
      code: "failed-precondition",
      message: "errorProviderConfig",
      details: {reason: "provider_config"},
    });
  });

  // 16.10 C-06: 익명 끊기 거부는 16.8 익명 해제 거부와 같은 reason 이다.
  it("익명 끊기 거부 = failed-precondition + anonymous_caller reason", () => {
    expect(ANONYMOUS_CALLER_REASON).toBe("anonymous_caller");
    expect(anonymousDisconnectNotAllowed()).toMatchObject({
      code: "failed-precondition",
      message: "errorAnonymousDisconnectNotAllowed",
      details: {reason: "anonymous_caller"},
    });
  });

  it("IdP 자격증명 거부는 재인증 reason 을 싣지 않는다", () => {
    expect(idpCredentialRejected().details).toBeUndefined();
  });

  it("IdP 도달 실패 = unavailable / errorServiceUnavailable", () => {
    expect(idpUnavailable()).toMatchObject({
      code: "unavailable",
      message: "errorServiceUnavailable",
    });
  });

  it("서버 결함 = internal / errorUnknown", () => {
    expect(serverFailure()).toMatchObject({
      code: "internal",
      message: "errorUnknown",
    });
  });

  it("입력 계약 위반 = invalid-argument / errorInvalidArgument", () => {
    expect(invalidArgument()).toMatchObject({
      code: "invalid-argument",
      message: "errorInvalidArgument",
    });
  });
});

describe("mapOidcVerifyError — WR-02 JWKS 장애 분류", () => {
  it("JWKSTimeout 은 transient (unavailable) 로 분류한다", () => {
    // jose 는 JWKS fetch 가 5초 기본 타임아웃을 넘기면 JWKSTimeout 을
    // 던진다. 사용자 토큰은 멀쩡하므로 자격증명 무효가 아니다.
    const err = new joseErrors.JWKSTimeout("timeout");
    expect(mapOidcVerifyError(err)).toMatchObject({
      code: "unavailable",
      message: "errorServiceUnavailable",
    });
  });

  it("JWKS non-200 (base JOSEError) 도 transient 로 분류한다", () => {
    // jose: "Expected 200 OK from the JSON Web Key Set HTTP response"
    // → base JOSEError (code = ERR_JOSE_GENERIC).
    const err = new joseErrors.JOSEError("Expected 200 OK from the JWKS");
    expect(mapOidcVerifyError(err)).toMatchObject({
      code: "unavailable",
      message: "errorServiceUnavailable",
    });
  });

  it("클레임 검증 실패는 자격증명 거부로 분류한다", () => {
    const err = new joseErrors.JWTClaimValidationFailed(
      "unexpected nonce",
      {},
      "nonce",
    );
    expect(mapOidcVerifyError(err)).toMatchObject({
      code: "unauthenticated",
      message: "errorInvalidCredentials",
    });
  });

  it("토큰 만료는 자격증명 거부로 분류한다", () => {
    const err = new joseErrors.JWTExpired("expired", {});
    expect(mapOidcVerifyError(err)).toMatchObject({
      code: "unauthenticated",
      message: "errorInvalidCredentials",
    });
  });

  it("kid 부재 (JWKS 도달 성공) 는 자격증명 거부로 분류한다", () => {
    // JWKS 자체는 받아왔고 매칭 키만 없는 상황 — 도달 실패가 아니다.
    const err = new joseErrors.JWKSNoMatchingKey("no matching key");
    expect(mapOidcVerifyError(err)).toMatchObject({
      code: "unauthenticated",
      message: "errorInvalidCredentials",
    });
  });

  it("비-JOSEError (fetch TypeError) 는 transient 로 분류한다", () => {
    // DNS 실패 / ECONNREFUSED 는 fetch 가 TypeError 로 던진다. 이전에는 이
    // 경로만 `internal` 로 빠져 한 가지 장애 계열이 세 갈래로 흩어졌다.
    expect(mapOidcVerifyError(new TypeError("fetch failed"))).toMatchObject({
      code: "unavailable",
      message: "errorServiceUnavailable",
    });
  });
});

describe("fingerprintJoseError — PII 금지 (Pitfall 1/7)", () => {
  it("JOSEError 는 code 를 fingerprint 로 쓴다", () => {
    const err = new joseErrors.JWTExpired(
      "PII_SENTINEL_secret@example.com",
      {},
    );
    expect(fingerprintJoseError(err)).toBe("ERR_JWT_EXPIRED");
  });

  it("비-jose Error 는 name 으로 fallback 한다", () => {
    expect(fingerprintJoseError(new TypeError("boom"))).toBe("TypeError");
  });

  it("비-Error throw 는 'unknown' 이다", () => {
    expect(fingerprintJoseError("string-thrown")).toBe("unknown");
  });

  it("fingerprint 에 err.message 본문이 새지 않는다", () => {
    const sentinel = "PII_SENTINEL_secret@example.com_nickname";
    const err = new joseErrors.JWTClaimValidationFailed(sentinel, {}, "nonce");
    expect(fingerprintJoseError(err)).not.toContain(sentinel);
    expect(fingerprintJoseError(err)).not.toContain("secret@example.com");
  });
});
