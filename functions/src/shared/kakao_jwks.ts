import {createRemoteJWKSet} from "jose";

/**
 * Kakao OIDC issuer (Phase 12 D-06).
 *
 * `jwtVerify(idToken, JWKS, {issuer: KAKAO_ISSUER, ...})` 의 issuer 인자.
 * Kakao Developers `/.well-known/openid-configuration` 의 `issuer` 클레임과
 * 일치 (RESEARCH 2026-05-03 직접 probe 검증).
 */
export const KAKAO_ISSUER = "https://kauth.kakao.com" as const;

/**
 * Kakao OIDC JWKS singleton — 모듈 레벨 1회만 생성 (Pitfall 3 / D-08).
 *
 * jose 6.x defaults:
 * - cacheMaxAge: 600_000 ms (10분) — 두 번째 호출부터 캐시 hit
 * - cooldownDuration: 30_000 ms (30초) — kid 회전 시 fetch 쿨다운
 * - timeoutDuration: 5_000 ms (5초)
 *
 * Kakao 가이드 ("일정 기간 캐싱") 와 정합. Phase 14 LINE 진입 시
 * `createOidcVerifier(issuer, jwksUrl, audSecret)` 헬퍼로 일반화 (D-08).
 *
 * **함수 내부에서 매번 생성 시 캐시 무효화** — Pitfall 3 회귀 방어 sentinel
 * (PATTERNS.md): `grep -r createRemoteJWKSet functions/src/` 결과는 본 파일의
 * 1줄만이어야 한다.
 */
export const KAKAO_JWKS = createRemoteJWKSet(
  new URL("https://kauth.kakao.com/.well-known/jwks.json"),
);
