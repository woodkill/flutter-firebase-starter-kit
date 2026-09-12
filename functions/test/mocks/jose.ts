/**
 * jose 6.x ESM-only 빌드를 jest CommonJS 환경에서 import 가능하게 하는 stub
 * (Phase 12 Task 3 — moduleNameMapper 로 치환).
 *
 * - 실제 검증은 `functions/test/auth/kakao_custom_token.test.ts` 등이
 *   `jest.mock("jose", ...)` 로 인라인 mock 을 별도 등록한다.
 * - 다른 테스트 (예: ping.test.ts) 는 jose 를 직접 사용하지 않지만 src
 *   import chain 으로 간접 평가되므로 본 stub 이 SyntaxError 를 차단한다.
 *
 * **error code 충실도 (Phase 15 리뷰 WR-02):** `custom_token_errors.ts` 의
 * 매핑이 `err.code` 문자열로 분기하므로, 본 stub 의 클래스들은 실제 jose
 * 6.2.3 (`dist/webapi/util/errors.js`) 의 `code` 값을 **verbatim mirror**
 * 한다. code 를 비워두면 mock 이 실제 동작과 어긋나 self-referential 검증이
 * 되어버린다 (memory `feedback_oidc_mock_self_referential` 의 교훈).
 */

/**
 * Stub JOSEError — instanceof 분기 호환용.
 *
 * 실제 jose 의 base `JOSEError.code` 는 `'ERR_JOSE_GENERIC'` 이며, jose 는
 * JWKS HTTP 응답이 200 이 아닐 때 이 base 클래스로 던진다
 * ("Expected 200 OK from the JSON Web Key Set HTTP response").
 */
export class JOSEError extends Error {
  code = "ERR_JOSE_GENERIC";
}
/** Stub JWTClaimValidationFailed — JOSEError 서브클래스. */
export class JWTClaimValidationFailed extends JOSEError {
  code = "ERR_JWT_CLAIM_VALIDATION_FAILED";
}
/** Stub JWTExpired — JOSEError 서브클래스. */
export class JWTExpired extends JOSEError {
  code = "ERR_JWT_EXPIRED";
}
/** Stub JWKSNoMatchingKey — JOSEError 서브클래스 (kid 부재). */
export class JWKSNoMatchingKey extends JOSEError {
  code = "ERR_JWKS_NO_MATCHING_KEY";
}
/** Stub JWKSTimeout — JOSEError 서브클래스 (JWKS fetch 타임아웃). */
export class JWKSTimeout extends JOSEError {
  code = "ERR_JWKS_TIMEOUT";
}

export const errors = {
  JOSEError,
  JWTClaimValidationFailed,
  JWTExpired,
  JWKSNoMatchingKey,
  JWKSTimeout,
};

/**
 * Stub jwtVerify — 실제 호출은 kakao_custom_token.test.ts 의 jest.mock 이
 * 가로챈다. 다른 테스트가 우연히 호출하면 명시적 throw 로 잘못된 사용
 * 차단.
 */
export function jwtVerify(): Promise<never> {
  throw new Error("jose stub: jwtVerify not mocked in this test");
}

/**
 * Stub createRemoteJWKSet — 모듈 레벨 JWKS 초기화가 fail 하지 않도록
 * 임의 sentinel 반환.
 *
 * @return {unknown} sentinel string.
 */
export function createRemoteJWKSet(): unknown {
  return "STUB_JWKS";
}
