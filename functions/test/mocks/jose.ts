/**
 * jose 6.x ESM-only 빌드를 jest CommonJS 환경에서 import 가능하게 하는 stub
 * (Phase 12 Task 3 — moduleNameMapper 로 치환).
 *
 * - 실제 검증은 `functions/test/auth/kakao_custom_token.test.ts` 가
 *   `jest.mock("jose", ...)` 로 인라인 mock 을 별도 등록한다.
 * - 다른 테스트 (예: ping.test.ts) 는 jose 를 직접 사용하지 않지만 src
 *   import chain 으로 간접 평가되므로 본 stub 이 SyntaxError 를 차단한다.
 */

/** Stub JOSEError — instanceof 분기 호환용. */
export class JOSEError extends Error {}
/** Stub JWTClaimValidationFailed — JOSEError 서브클래스. */
export class JWTClaimValidationFailed extends JOSEError {}

export const errors = {JOSEError, JWTClaimValidationFailed};

/**
 * Stub jwtVerify — 실제 호출은 kakao_custom_token.test.ts 의 jest.mock 이
 * 가로챈다. 다른 테스트가 우연히 호출하면 명시적 throw 로 잘못된 사용
 * 차단.
 */
export function jwtVerify(): Promise<never> {
  throw new Error("jose stub: jwtVerify not mocked in this test");
}

/**
 * Stub createRemoteJWKSet — 모듈 레벨 KAKAO_JWKS 초기화가 fail 하지 않도록
 * 임의 sentinel 반환.
 *
 * @return {unknown} sentinel string.
 */
export function createRemoteJWKSet(): unknown {
  return "STUB_JWKS";
}
