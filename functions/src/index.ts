import {initializeApp} from "firebase-admin/app";
import {setGlobalOptions} from "firebase-functions";
import {onCall, HttpsError} from "firebase-functions/https";
import * as logger from "firebase-functions/logger";

import {REGION} from "./shared/region";

// Firebase Admin SDK 초기화 (Phase 12 D-06 retroactive gap closure -- Firestore /
// Auth 접근 전제). 모듈 로드 시점 1회 호출. kakaoCustomToken 이 getFirestore() /
// admin.auth().createCustomToken() 호출 전 default app 인스턴스 보장. Phase 11
// ping 은 admin 미사용이라 누락이 드러나지 않았던 gap 의 retroactive 보완.
initializeApp();

// 전역 region + 비용 가드 (D-04, Pitfall 3 — region 변경 불가).
setGlobalOptions({
  region: REGION,
  maxInstances: 10,
  memory: "256MiB",
  timeoutSeconds: 30,
});

/**
 * Phase 11 ping stub (D-01).
 *
 * Phase 12~16 Custom Token 함수가 복제할 패턴:
 * - App Check enforcement (D-11, Pitfall 6)
 * - request.auth null check (T-11-FN-02, V4 Access Control)
 * - HttpsError 표준 코드 매핑 (D-07, V7 Error Handling)
 * - structured logger + uid 만 (D-08, T-11-FN-01 PII 금지)
 *
 * IN-05 (Phase 15 리뷰): 배포되는 9개 callable 중 본 함수만
 * `enforceAppCheck: true` 없이 export 되고 있었다. ping 자체의 위험은 낮지만
 * (인증만 요구하고 region/서버시각만 반환), 위 주석이 스스로를 "복제할 패턴"
 * 이라고 선언하는 레퍼런스이므로 빠진 옵션이 그대로 잘못된 템플릿이 된다.
 */
export const ping = onCall({enforceAppCheck: true}, (request) => {
  if (!request.auth) {
    logger.warn({event: "ping_unauthenticated"}, "ping called without auth");
    throw new HttpsError("unauthenticated", "errorUnauthenticated");
  }
  const uid = request.auth.uid;
  logger.info({event: "ping_invoked", uid}, "ping invoked");
  return {
    ok: true,
    region: REGION,
    serverTime: new Date().toISOString(),
  };
});

// Phase 12 D-06 — Kakao OIDC ID Token → Firebase Custom Token.
export {kakaoCustomToken} from "./auth/kakao_custom_token";
// Phase 13 — see ROADMAP.md — Naver access_token → Firebase Custom Token.
export {naverCustomToken} from "./auth/naver_custom_token";
// Phase 16.5 SOCL-14 — Naver authorization code → Custom Token (킷 소유 웹 경로).
export {naverWebCustomToken} from "./auth/naver_web_custom_token";
// Phase 14 D-LINE-06 — LINE OIDC ID Token → Firebase Custom Token.
export {lineCustomToken} from "./auth/line_custom_token";
// Phase 16 Wave 0 sentinel — Plan 16-02 가 본체 채움 (D-04/06/07/08/09/10/14).
export {linkCustomTokenProvider} from "./auth/link_custom_token_provider";
// Phase 16.8 SOCL-15 — Custom Token 신원 해제 (D-01/03/06/08 · link 의 역연산).
export {unlinkCustomTokenProvider} from "./auth/unlink_custom_token_provider";
// Phase 16.9 SOCL-12 — Naver 계정 연결
// (access token · code → /v1/nid/me → identity_index).
export {linkNaverProvider} from "./auth/link_naver_provider";
// Phase 16.10 SOCL-13 · SOCL-15 — Kakao 앱 연결 끊기 (어드민 키 · identity_index 회원번호).
export {disconnectKakaoProvider} from "./auth/disconnect_kakao_provider";
// Phase 16.10 SOCL-13 · SOCL-15 — Facebook 앱 권한 삭제 (app token · asid).
export {disconnectFacebookProvider} from "./auth/disconnect_facebook_provider";
// Phase 16.10 SOCL-13 · SOCL-15 — Naver 앱 연결 끊기
// (Token Revocation · 재로그인 custom token).
export {disconnectNaverProvider} from "./auth/disconnect_naver_provider";
// Phase 16.10 SOCL-13 · SOCL-15 — LINE 앱 권한 해제
// (stateless channel token · deauthorize · 재로그인 custom token).
export {disconnectLineProvider} from "./auth/disconnect_line_provider";
export {deleteUserAccount} from "./auth/delete_user_account";
export {lookupSignInMethods} from "./auth/lookup_sign_in_methods";
export {mirrorTermsAcceptanceSnapshot} from "./auth/mirror_terms_acceptance";
// Phase 17 — see ROADMAP.md (D-26)
export {mirrorAccountEmail} from "./auth/mirror_account_email";
// Phase 17 — see ROADMAP.md (D-05)
export {sendTestPush} from "./messaging/send_test_push";
