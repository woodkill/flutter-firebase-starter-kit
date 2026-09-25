// Phase 15 code review WR-06 — OIDC provider 설정 단일 진실원.
//
// 이전에는 issuer / jwksUrl / algorithms / nonceHashing 4-튜플이 provider
// 당시 3종 × 2 파일 = 6개 리터럴로 존재했다 (각 Custom Token endpoint 1 +
// `link_custom_token_provider.ts` 1). 결과로 두 가지 결함이 있었다.
//
// 1. **drift 위험** — IdP 가 issuer 나 JWKS URL 을 바꾸면 두 곳을 동시에
//    고쳐야 하고, 한 곳만 고치면 "로그인은 되는데 연동은 안 되는" (또는 그
//    반대) 부분 장애가 난다. issuer 의 trailing slash 처럼 한 글자 차이가
//    치명적인 값에서 특히 위험하다.
// 2. **JWKS 캐시 이중화** — `createOidcVerifier` 는 factory 호출마다
//    `createRemoteJWKSet` 을 새로 만들므로 provider 당 JWKS 캐시가 2개
//    생기고 워밍/쿨다운이 각각 돌았다. `oidc_verifier.ts` 의 "JWKS singleton
//    (Pitfall 3 sentinel)" 전제가 깨져 있었다.
//
// 이제 provider 당 verifier 인스턴스는 **정확히 1개** 다. 새 OIDC provider 를
// 추가할 때는 본 파일의 맵에만 항목을 추가한다.
import {defineSecret} from "firebase-functions/params";

import {createOidcVerifier, OidcVerifier} from "./oidc_verifier";

// Phase 11 D-05 — Secret Manager 주입.
// 배포 전 의무: `firebase functions:secrets:set KAKAO_NATIVE_APP_KEY`.
export const KAKAO_NATIVE_APP_KEY = defineSecret("KAKAO_NATIVE_APP_KEY");

// Phase 14 D-LINE-16 — 배포 전 의무:
//   firebase functions:secrets:set LINE_CHANNEL_ID
//
// LINE_CHANNEL_ID 는 OIDC ID Token audience 검증 (aud claim) 의 정답값으로
// runtime 시점에 사용된다.
//
// WR-04 (Phase 14 review): LINE_CHANNEL_SECRET 은 Phase 17+ refresh /
// verify-token / revoke API 진입 시점에 도입한다. 현 시점 사용처 0 인 secret
// 을 declared 하면 운영자가 deploy 전 1회성 더미 주입을 강제받아 starter-kit
// "최소 설정으로 시작" 가치와 충돌 → declaration 제거. Phase 17 진입 시 본
// 위치에 재선언 + onCall secrets 배열에 재포함 의무.
//
// (Naver 는 정반대 정책을 택했다 — `shared/naver_secrets.ts` 의
// `NAVER_CLIENT_SECRET` 주석 참조. 두 provider 의 정책 차이는 의도적이며
// 그 사유가 양쪽 선언부에 명시되어 있다.)
export const LINE_CHANNEL_ID = defineSecret("LINE_CHANNEL_ID");

/** OIDC ID Token 을 발급하는 Custom Token provider (Naver 는 REST 기반). */
export type OidcProviderId = "kakao" | "line";

/**
 * provider 별 OIDC verifier singleton 맵 (WR-06 단일 진실원).
 *
 * **provider 별 인자 근거 (verbatim cross-verify):**
 * - kakao — issuer `https://kauth.kakao.com`, RS256, raw nonce 비교
 *   (Phase 12 D-06 검증된 동작).
 * - line — issuer `https://access.line.me`, **ES256** (Kakao 의
 *   RS256 과 분리), raw nonce 비교. line-sdk-android `LineIdToken.java`
 *   verbatim "the same value as in the authentication request"
 *   (Phase 14.1 D-14.1-02 cross-verified).
 *
 * **audience lazy invoke:** `defineSecret().value()` 는 onCall 진입 시점에만
 * evaluate 가능하다 (모듈 로드 시점은 secret 미주입). 따라서 audience 는
 * 콜백으로 전달한다.
 *
 * **Pitfall 3 sentinel:** jose 의 JWKS remote set 생성 호출처는
 * `oidc_verifier.ts` 단 한 곳이고, 그 factory 를 호출하는 곳은 이제 본 파일
 * 단 한 곳이다.
 */
export const OIDC_VERIFIERS: Record<OidcProviderId, OidcVerifier> = {
  kakao: createOidcVerifier({
    issuer: "https://kauth.kakao.com",
    jwksUrl: "https://kauth.kakao.com/.well-known/jwks.json",
    audience: () => KAKAO_NATIVE_APP_KEY.value(),
    algorithms: ["RS256"],
    nonceHashing: "none",
  }),
  line: createOidcVerifier({
    issuer: "https://access.line.me",
    jwksUrl: "https://api.line.me/oauth2/v2.1/certs",
    audience: () => LINE_CHANNEL_ID.value(),
    algorithms: ["ES256"],
    nonceHashing: "none",
  }),
};
