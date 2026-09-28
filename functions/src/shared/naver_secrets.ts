// Phase 13 D-60 · Phase 16.5 D-13 — Naver OAuth secret 선언 단일 진실원.
//
// Naver 를 쓰는 callable (`naver_custom_token.ts` · `naver_web_custom_token.ts` ·
// `link_naver_provider.ts` — 교환 helper `naver_token_exchange.ts` 경유 ·
// `disconnect_naver_provider.ts` — 교환 + Token Revocation) 이 같은 secret 을
// 바인딩하므로 선언을 한 곳에 둔다.
//
// 배포 전 의무 (아래 secret 모두):
//   firebase functions:secrets:set NAVER_CLIENT_SECRET
//   firebase functions:secrets:set NAVER_CLIENT_ID
// 값은 Naver Developers 콘솔 → 애플리케이션 → 개요의 Client Secret / Client ID.
import {defineSecret} from "firebase-functions/params";

/**
 * Naver Client Secret (Phase 13 D-60 · Phase 16.5 D-13).
 *
 * **사용처 (Phase 16.5 부터 · Phase 16.9 · 16.10 확장):**
 * `exchangeNaverAuthCode` (`auth/naver_token_exchange.ts`)가 authorization
 * code 교환(`grant_type=authorization_code`)의 form body 로 보낸다 —
 * 호출자는 `naverWebCustomToken`(웹 로그인) · `linkNaverProvider`(웹 모양
 * 연결) · `disconnectNaverProvider`(웹 모양 끊기). 로그인 · 연결 경로는 토큰
 * 폐기 요청을 보내지 않는다 — NAVER 에서 폐기는 연동 해제라 다음 로그인에
 * 동의 화면이 다시 뜨는 부작용이 있어서다 (quick 260924-lw2). 탈퇴 · 해제의
 * `disconnectNaverProvider` (`auth/disconnect_naver_provider.ts`)는 Token
 * Revocation(`/oauth2.0/revoke`) form body 로 보낸다 — 여기서는 동의 화면
 * 재노출이 의도된 결과다 (Phase 16.10 D-09).
 * Phase 13 단계에서는 사용처가 없었지만 secret 정책 일관성 / 시스템 보안
 * 권장으로 미리 등록했다 (D-60).
 *
 * `naverCustomToken` (1-tap SDK 경로) 은 여전히 값을 읽지 않지만
 * `secrets:` 바인딩을 유지한다 — D-60 정책 일관용. 바인딩을 "미사용" 으로 보고
 * 제거하지 말 것 (D-60 결정을 되돌리는 것이다).
 *
 * **IN-02 (Phase 15 리뷰) — LINE 과의 선언 시점 비대칭 (Phase 16.10 해소):**
 * Phase 15 당시 같은 "사용처 0건 secret" 상황에서 Naver 는 선언을 유지했고
 * LINE 은 `LINE_CHANNEL_SECRET` 선언을 제거했다. 결정이 갈린 이유는 운영자
 * 부담의 비대칭이었다.
 * - Naver: `docs/manual.md` 단계 8 이 이미 등록 절차를 안내하고 있고, Naver
 *   Developers 콘솔은 client secret 을 앱 생성과 동시에 발급하므로 운영자가
 *   추가로 얻어야 할 값이 없다 → forward-prep 유지 (D-60). Phase 16.5 에서
 *   실사용처(웹 경로 token 교환)를 확보했다.
 * - LINE: 사용처가 생길 때 선언한다 (WR-04 — shared/oidc_providers.ts 의
 *   해당 선언부 주석 참조).
 *
 * Phase 16.10 에서 두 provider 모두 끊기 경로가 secret 을 쓴다 — Naver
 * `disconnectNaverProvider`(Token Revocation form body) · LINE
 * `disconnectLineProvider`(stateless channel token 발급 — 이때
 * `LINE_CHANNEL_SECRET` 을 사용처와 함께 재선언했다). 비대칭은 해소됐다.
 */
export const NAVER_CLIENT_SECRET = defineSecret("NAVER_CLIENT_SECRET");

/**
 * Naver Client ID (Phase 16.5 D-13 · Phase 16.9 D-01 — `exchangeNaverAuthCode`
 * 경유로 `naverWebCustomToken` · `linkNaverProvider` 가 읽는다. Phase 16.10
 * 부터 `disconnectNaverProvider` 가 웹 교환과 Token Revocation form body 에
 * 싣는다).
 *
 * Client ID 는 authorize URL 에 실리는 **공개 식별자** 지만 LINE 의
 * `LINE_CHANNEL_ID` (shared/oidc_providers.ts) 와 같은 이유로 Secret Manager
 * 에 둔다.
 * - 별도 `.env` 파일 도입 0 — 서버 설정 공급 경로를 Secret Manager 하나로 유지.
 * - client payload 신뢰 0 — caller 가 보낸 client_id 가 서버 secret 과 짝이
 *   되게 두지 않는다 (서버가 교환에 쓰는 값은 서버가 정한다).
 *
 * 값은 client 의 `config/<flavor>.json` `naverClientId` 와 같아야 한다 —
 * 다르면 NAVER token 엔드포인트가 authorization code 교환을 거부한다.
 */
export const NAVER_CLIENT_ID = defineSecret("NAVER_CLIENT_ID");
