// Phase 16.10 D-02 · D-03 — Facebook app access token secret 선언 단일 진실원.
//
// 배포 전 의무 (아래 secret 모두):
//   firebase functions:secrets:set FACEBOOK_APP_ID
//   firebase functions:secrets:set FACEBOOK_APP_SECRET
// 값은 Meta App Dashboard → 앱 설정 → 기본 설정의 앱 ID / 앱 시크릿 코드다.
//
// provider 제거 시: 이 파일 + 사용처 callable 파일 + `index.ts` export 1줄을
// 함께 지우고, 배포된 함수 · secret 을 정리한다 (C-08).
import {defineSecret} from "firebase-functions/params";

/**
 * Facebook 앱 ID (Phase 16.10 D-03).
 *
 * **사용처:** `disconnectFacebookProvider`
 * (`auth/disconnect_facebook_provider.ts`)가 app access token
 * (`<앱 ID>|<앱 시크릿>`)을 만들어 `DELETE /{asid}/permissions` 의
 * `Authorization: Bearer` 헤더로 보낸다.
 *
 * 앱 ID 는 client 에도 실리는 **공개 식별자** 지만 `NAVER_CLIENT_ID`
 * (shared/naver_secrets.ts) 와 같은 이유로 Secret Manager 에 둔다.
 * - 별도 `.env` 파일 도입 0 — 서버 설정 공급 경로를 Secret Manager 하나로 유지.
 * - client payload 신뢰 0 — 서버가 쓰는 앱 ID 는 서버가 정한다.
 *
 * 값은 client 의 `config/<flavor>.json` `facebookAppId` 와 같아야 한다 —
 * 다르면 app-scoped ID(asid)의 발급 앱이 달라 끊기 대상이 어긋난다
 * (plan 01 Wave 0 `FB_APP_ID_MATCH_CONFIG` 확인 항목).
 */
export const FACEBOOK_APP_ID = defineSecret("FACEBOOK_APP_ID");

/**
 * Facebook 앱 시크릿 코드 (Phase 16.10 D-03).
 *
 * **사용처:** `disconnectFacebookProvider` — `FACEBOOK_APP_ID` 와 짝으로
 * app access token 을 만든다. 탈퇴 함수(`deleteUserAccount`)는 바인딩하지
 * 않는다 (D-13 · WR-04 「사용처 0 secret 선언 금지」).
 *
 * **서버 전용:** URL 쿼리 문자열에 싣지 않는다 — 헤더로만 보낸다
 * (T-16.10-07). 값은 함수 본문 실행 시점에만 `.value()` 로 읽는다
 * (module scope 금지) · 로그 금지.
 */
export const FACEBOOK_APP_SECRET = defineSecret("FACEBOOK_APP_SECRET");
