// Phase 13 D-60 · Phase 16.5 D-13 — Naver OAuth secret 선언 단일 진실원.
//
// 두 Naver callable 이 같은 secret 을 바인딩하므로 선언을 한 곳에 둔다
// (`naver_custom_token.ts` · `naver_web_custom_token.ts` 가 import).
//
// 배포 전 의무 (2종 모두):
//   firebase functions:secrets:set NAVER_CLIENT_SECRET
//   firebase functions:secrets:set NAVER_CLIENT_ID
// 값은 Naver Developers 콘솔 → 애플리케이션 → 개요의 Client Secret / Client ID.
import {defineSecret} from "firebase-functions/params";

/**
 * Naver Client Secret (Phase 13 D-60 · Phase 16.5 D-13/D-15).
 *
 * **사용처 1 (Phase 16.5 부터):** `naverWebCustomToken` 이 authorization code
 * 교환(`grant_type=authorization_code`)과 best-effort 토큰 폐기
 * (`grant_type=delete`)에서 form body 로 보낸다. Phase 13 단계에서는 사용처가
 * 없었지만 secret 정책 일관성 / 시스템 보안 권장으로 미리 등록했다 (D-60).
 *
 * `naverCustomToken` (1-tap SDK 경로) 은 여전히 값을 읽지 않지만
 * `secrets:` 바인딩을 유지한다 — D-60 정책 일관용. 바인딩을 "미사용" 으로 보고
 * 제거하지 말 것 (D-60 결정을 되돌리는 것이다).
 *
 * **IN-02 (Phase 15 리뷰) — LINE 과 정반대 정책인 이유 (의도된 비대칭):**
 * 같은 "사용처 0건 secret" 상황에서 LINE 은 `LINE_CHANNEL_SECRET` 선언을
 * **제거** 했다 (shared/oidc_providers.ts 의 해당 선언부 주석 참조). 두
 * provider 의 결정이 갈린 이유는 운영자 부담의 비대칭이다.
 * - Naver: `docs/manual.md` 단계 8 이 이미 등록 절차를 안내하고 있고, Naver
 *   Developers 콘솔은 client secret 을 앱 생성과 동시에 발급하므로 운영자가
 *   추가로 얻어야 할 값이 없다 → forward-prep 유지 (D-60). Phase 16.5 에서
 *   실사용처(웹 경로 token 교환 · revoke)를 확보했다.
 * - LINE: 별도 채널 설정 화면에서 값을 찾아 1회성 더미 주입을 강제받는
 *   부담이 있어 "최소 설정으로 시작" 가치와 충돌 → 선언 제거.
 *
 * Phase 17+ 에서 deauth / refresh flow 를 도입할 때 **두 provider 를 함께**
 * 정렬한다 (그 시점에 LINE 은 재선언).
 */
export const NAVER_CLIENT_SECRET = defineSecret("NAVER_CLIENT_SECRET");

/**
 * Naver Client ID (Phase 16.5 D-13 — `naverWebCustomToken` 전용).
 *
 * Client ID 는 authorize URL 에 실리는 **공개 식별자** 지만 LINE 의
 * `LINE_CHANNEL_ID` (shared/oidc_providers.ts) 와 같은 이유로 Secret Manager
 * 에 둔다.
 * - 별도 `.env` 파일 도입 0 — 서버 설정 공급 경로를 Secret Manager 하나로 유지.
 * - client payload 신뢰 0 — caller 가 보낸 client_id 가 서버 secret 과 짝이
 *   되게 두지 않는다 (서버가 교환 · 폐기에 쓰는 값은 서버가 정한다).
 *
 * 값은 client 의 `config/<flavor>.json` `naverClientId` 와 같아야 한다 —
 * 다르면 NAVER token 엔드포인트가 authorization code 교환을 거부한다.
 */
export const NAVER_CLIENT_ID = defineSecret("NAVER_CLIENT_ID");
