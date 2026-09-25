import {timingSafeEqual} from "node:crypto";

import {createRemoteJWKSet, jwtVerify, errors as joseErrors} from "jose";
import type {JWTPayload} from "jose";

/**
 * Provider-agnostic OIDC ID Token JWT 검증 factory (Phase 14 D-LINE-02/05/07,
 * Phase 12 D-08 의무 완전 이행).
 *
 * Phase 12 의 inline `KAKAO_JWKS + jwtVerify + nonce 비교` 코드를 일반화한
 * helper. Phase 14 LINE 이 원신 사용처 + Phase 12 Kakao 가 retroactive
 * 마이그된 후속 사용처.
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
   * nonce 비교 모드. 현재 Kakao + LINE 두 provider 모두 raw 비교 mode 만
   * 사용 (Phase 14.1 D-14.1-02 cross-verified — LINE SDK 가 raw nonce 를
   * 변환 없이 LINE 서버에 transmit + ID Token nonce claim = raw 동일값).
   *
   * - "none": raw nonce === claim.nonce.
   *
   * **Phase 15+ baseline:** SHA256(raw) === claim.nonce 등 hashing mode 가
   * 필요한 provider 진입 시 D-14.1-02 와 동등한 4-source verbatim cross-
   * verify 후 union 재확장 (e.g., `"none" | "sha256"`) + runtime 분기
   * 재도입 + oidc_verifier.test.ts 에 hashing path coverage 추가 의무.
   * Phase 14.1 hotfix 의 minimal-change 정신 + dead-code 제거 + type
   * 안전성 우선으로 "sha256" 분기 잠정 제거.
   */
  nonceHashing: "none";
};

/**
 * nonce 클레임과 기대값을 **상수 시간** 으로 비교한다 (IN-01).
 *
 * `crypto.timingSafeEqual` 은 길이가 다르면 throw 하므로 길이를 먼저 비교해
 * 조기 반환한다. 길이 정보는 애초에 공개값 (client 가 만든 nonce 길이) 이라
 * 누설 가치가 없다.
 *
 * **한계 명시:** nonce 검증 자체는 서버 replay 방어로는 불완전하다 — 공격자가
 * 토큰과 nonce 를 **함께** 재전송할 수 있기 때문이다. 실효 방어는 `iat`
 * 신선도 창 또는 서버측 nonce 저장소이며, 그것은 별도 hardening 작업이다.
 * 본 함수는 "같은 값인지" 만 안전하게 판정한다.
 *
 * @param {unknown} claimNonce ID Token 의 `nonce` 클레임 (임의 JSON 값).
 * @param {string} expectedNonce caller 가 전달한 raw nonce.
 * @return {boolean} 두 값이 같은 문자열이면 true.
 */
function isNonceMatch(claimNonce: unknown, expectedNonce: string): boolean {
  if (typeof claimNonce !== "string") return false;
  const a = Buffer.from(claimNonce, "utf8");
  const b = Buffer.from(expectedNonce, "utf8");
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}

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
    // nonce 옵션 부재 (Phase 12 D-06 검증). 현재 raw 비교 mode 만 지원
    // (config.nonceHashing === "none"). hashing mode 진입은 Phase 15+
    // baseline (위 OidcVerifierConfig docstring 참조).
    //
    // IN-01 (Phase 14.1 IN-02 carry-forward, Phase 15 리뷰에서 범위 확대
    // 확인): JS `!==` 는 첫 불일치 바이트에서 조기 반환하므로 비교 시간이
    // 입력에 의존한다. nonce 는 client-issued one-time 값이라 실효 위협은
    // 낮지만, 본 helper 는 이제 3 provider 가 공유하는 단일 진실원이므로
    // (blast radius 확대) 상수 시간 비교로 바꾼다.
    const claimNonce = verified.payload.nonce;
    const expectedNonce = rawNonce;
    if (!isNonceMatch(claimNonce, expectedNonce)) {
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
