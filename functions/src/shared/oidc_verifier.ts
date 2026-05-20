import {createHash} from "node:crypto";

import {createRemoteJWKSet, jwtVerify, errors as joseErrors} from "jose";
import type {JWTPayload} from "jose";

/**
 * Provider-agnostic OIDC ID Token JWT 검증 factory (Phase 14 D-LINE-02/05/07,
 * Phase 12 D-08 의무 완전 이행).
 *
 * Phase 12 의 inline `KAKAO_JWKS + jwtVerify + nonce 비교` 코드를 일반화한
 * helper. Phase 14 LINE 이 원신 사용처 + Phase 12 Kakao 가 retroactive
 * 마이그 + Phase 15 Yahoo!JP 가 후속 사용처.
 *
 * **Provider 별 인자 분기:**
 * - Kakao: issuer=https://kauth.kakao.com / algorithms=["RS256"] /
 *   nonceHashing="none" (raw nonce === claim.nonce)
 * - LINE: issuer=https://access.line.me / algorithms=["ES256"] /
 *   nonceHashing="none" (raw nonce === claim.nonce — Phase 14.1 D-14.1-02:
 *   LINE iOS/Android SDK 가 raw nonce 를 그대로 LINE 서버에 transmit + ID
 *   Token nonce claim = raw 동일값. line-sdk-android LineIdToken.java verbatim
 *   "the same value as in the authentication request" cross-verified)
 *
 * **JWKS singleton (Pitfall 3 sentinel 보존, D-LINE-04):**
 * jose JWKS remote set 생성은 factory 호출 시점 1회만 evaluate (closure
 * 외부가 아닌 factory body 내부 — provider 별 별도 singleton). 함수 내부
 * 매 호출 시 jose internal 캐시가 무효화된다. 회귀 방어 sentinel grep
 * (호출 패턴) — 본 파일의 호출 1줄만 hit.
 *
 * **jose 6.x 기본값 (D-LINE-07):**
 * - cacheMaxAge: 600_000 ms (10분)
 * - cooldownDuration: 30_000 ms (30초)
 * - timeoutDuration: 5_000 ms (5초)
 *
 * helper internal default 유지 — caller override 노출 X.
 *
 * **audience lazy invoke:** `defineSecret().value()` 는 onCall 진입 시점에만
 * evaluate 가능 (모듈 로드 시점은 secret 미주입). audience 를 callback 으로
 * 받아 verifier 호출 시점에 invoke.
 *
 * @see .planning/phases/14-line-login/14-RESEARCH.md Pattern 1
 * @see .planning/phases/14-line-login/14-PATTERNS.md Wave 1.A
 */

/** OIDC verifier 함수 시그니쳐 (D-LINE-05 verbatim). */
export type OidcVerifier = (
  idToken: string,
  nonce: string,
) => Promise<JWTPayload>;

/** Provider OIDC 메타데이터 (D-LINE-05 verbatim). */
export type OidcVerifierConfig = {
  /** OIDC issuer (e.g., "https://kauth.kakao.com"). */
  issuer: string;
  /** JWKS endpoint URL (e.g., "https://api.line.me/oauth2/v2.1/certs"). */
  jwksUrl: string;
  /** audience 클레임 — defineSecret().value() lazy invoke (D-LINE-05). */
  audience: () => string;
  /** JWT 서명 alg whitelist (e.g., Kakao=["RS256"], LINE=["ES256"]). */
  algorithms: string[];
  /**
   * nonce 비교 모드.
   * - "none": raw nonce === claim.nonce (Kakao)
   * - "sha256": SHA256(raw) === claim.nonce (LINE — SDK 가 hash 후 embed)
   */
  nonceHashing: "none" | "sha256";
};

/**
 * OIDC verifier factory. JWKS singleton 은 factory 호출 시점 1회 evaluate.
 *
 * @param {OidcVerifierConfig} config provider OIDC 메타데이터.
 * @return {OidcVerifier} idToken + nonce 받아 검증된 JWTPayload 반환.
 */
export function createOidcVerifier(config: OidcVerifierConfig): OidcVerifier {
  // JWKS singleton — factory 호출 시점 1회만 evaluate (Pitfall 3 sentinel
  // 보존). 함수 내부에서 매번 호출 시 jose internal cache 가 무효화된다.
  const jwks = createRemoteJWKSet(new URL(config.jwksUrl));

  return async (idToken: string, rawNonce: string): Promise<JWTPayload> => {
    // issuer / audience / algorithms 검증은 jose 가 흡수. 위반 시
    // joseErrors.* throw — caller 가 instanceof JOSEError 분기.
    const verified = await jwtVerify(idToken, jwks, {
      issuer: config.issuer,
      audience: config.audience(),
      algorithms: config.algorithms,
    });

    // nonce 클레임 직접 비교 — jose 6.x JWTClaimVerificationOptions 에 native
    // nonce 옵션 부재 (Phase 12 D-06 검증). provider 별 hashing 분기.
    const claimNonce = verified.payload.nonce;
    const expectedNonce =
      config.nonceHashing === "sha256" ?
        createHash("sha256").update(rawNonce).digest("hex") :
        rawNonce;
    if (claimNonce !== expectedNonce) {
      throw new joseErrors.JWTClaimValidationFailed(
        "unexpected nonce",
        verified.payload,
        "nonce",
        "check_failed",
      );
    }
    return verified.payload;
  };
}
