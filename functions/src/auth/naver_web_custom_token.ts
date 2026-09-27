// Phase 16.5 SOCL-14 — Naver authorization code → Firebase Custom Token
// (킷 소유 웹 경로).
//
// NAVER 토큰 API 파라미터 진실원 = NAVER 공식 SDK 2종 소스 (RESEARCH
// 「NAVER OAuth 2.0 엔드포인트 계약」):
// - 교환: naveridlogin-sdk-ios-swift 5.2.1 IssueAccessTokenRequest.swift
//   (POST · form-urlencoded) + com.navercorp.nid:oauth 5.11.2
//   NidOAuthLoginService.requestAccessToken (state 포함).
// redirect_uri 는 양 SDK 모두 보내지 않는다 → 본 서버도 보내지 않는다.
//
// 서버는 토큰 폐기 grant 를 호출하지 않는다 — iOS SDK 5.2.1 에서 그 grant 는
// `NidOAuth.disconnect()`(연동 해제) 전용이라 부르면 매 로그인 동의 화면이
// 다시 뜬다 (quick 260924-lw2 · 16.5 D-15 번복).
//
// 서버 교환의 가치는 secret 은닉이 아니라 RFC 8252 정합 + 미설치 단말 착지다
// (D-19 정직한 프레이밍).
import {onCall} from "firebase-functions/https";
import * as logger from "firebase-functions/logger";

import {isAnonymousCaller} from "../shared/caller_auth";
import {invalidArgument} from "../shared/custom_token_errors";
import {NAVER_CLIENT_ID, NAVER_CLIENT_SECRET} from "../shared/naver_secrets";
import {
  // state 는 nonce 계열 짧은 인자 상한(512)을 쓴다 (D-14).
  MAX_NONCE_ARG_LENGTH as MAX_STATE_ARG_LENGTH,
  requireStringArg,
} from "../shared/require_string_arg";
import {
  TermsAcceptanceJson,
  parseTermsAcceptanceJson,
} from "../shared/terms_acceptance_json";
import {
  NaverCustomTokenResult,
  verifyNaverProfileAndIssueCustomToken,
} from "./naver_profile_to_custom_token";
import {
  exchangeNaverAuthCode,
  NAVER_CONTROL_CHARS as CONTROL_CHARS,
} from "./naver_token_exchange";

type NaverWebCustomTokenRequest = {
  /** NAVER authorize 콜백의 authorization code. */
  code: string;
  /** client 가 authorize 요청에 실은 state — 서버는 비교하지 않고 전달만. */
  state: string;
  /** Phase 16 D-13/D-14 — 신규 UID 일 때만 termsAccepted mirror. */
  termsAcceptanceSnapshot?: TermsAcceptanceJson;
};

/**
 * Naver authorization code → Firebase Custom Token 발급 (Phase 16.5 D-13).
 *
 * 호출 조건: App Check 토큰 필수 (enforceAppCheck). Firebase Auth 는 선택 —
 * 미인증 · 익명 · 정식 로그인 caller 모두 허용하며 caller 가드는 helper 의
 * resolveIdentity 가 수행한다 (D-49 · 12.1 D-31~34).
 *
 * 흐름:
 * 1. 입력 검증 (D-14) — code (≤8192) · state (≤512) 타입 · 길이 + CRLF/NUL →
 *    invalid-argument. state 는 검증 대상이 아니라 NAVER 로 전달만 한다 —
 *    비교 주체는 authorize 요청을 만든 client 다 (T-16.5-01).
 * 2. NAVER token 교환 (`exchangeNaverAuthCode`) — 3단 검사.
 *    교환 모듈 = `naver_token_exchange.ts` (Phase 16.9 D-01 이동).
 * 3. 공용 helper `verifyNaverProfileAndIssueCustomToken` 위임 — 1-tap 경로와
 *    같은 /v1/nid/me 검증 · identity · Custom Token · terms mirror.
 * 4. access_token 은 이 호출 안에만 존재 — 저장 · 로깅 · 응답 · 폐기 호출 0.
 *    NAVER 폐기 요청은 연동 해제라 매 로그인 동의 화면이 다시 뜬다
 *    (quick 260924-lw2 · 16.5 D-15 번복). refresh_token 은 읽지도
 *    저장하지도 로깅하지도 않는다.
 *
 * **PII 금지 (D-51):** logger payload 는 {event, uid, isNewUser,
 * expiresInSec, status?, code?, error?(화이트리스트 NAVER error 코드 —
 * 교환)} 뿐.
 * 토큰 응답 본문 · access/refresh token · client_secret · code · state 는
 * logger · HttpsError · 응답 어디에도 싣지 않는다. 응답은 {customToken, uid, isNewUser} 뿐이다.
 *
 * @param {{data: NaverWebCustomTokenRequest, auth?: {uid: string}}} request
 *     onCall request — data.code · data.state 의무, auth optional.
 * @return {Promise<NaverCustomTokenResult>} customToken + uid + isNewUser.
 */
export const naverWebCustomToken = onCall<NaverWebCustomTokenRequest>(
  {
    enforceAppCheck: true,
    secrets: [NAVER_CLIENT_SECRET, NAVER_CLIENT_ID],
  },
  async (request): Promise<NaverCustomTokenResult> => {
    // Step 1: 입력 검증 (D-14). typeof + 길이는 공용 helper.
    const code = requireStringArg(request.data?.code);
    const state = requireStringArg(request.data?.state, MAX_STATE_ARG_LENGTH);
    if (CONTROL_CHARS.test(code) || CONTROL_CHARS.test(state)) {
      throw invalidArgument();
    }

    // Step 2: authorization code → access_token (+ 관측용 expiresInSec).
    const {accessToken, expiresInSec} = await exchangeNaverAuthCode({
      code,
      state,
    });

    // Step 3: helper 위임 — 폐기 없음(quick 260924-lw2 · 16.5 D-15 번복).
    // access_token 은 이 호출 안 지역 변수로만 존재한다.
    const result = await verifyNaverProfileAndIssueCustomToken({
      accessToken,
      callerUid: request.auth?.uid, // unauthenticated 허용 (D-49).
      callerIsAnonymous: isAnonymousCaller(request.auth),
      termsSnapshot: parseTermsAcceptanceJson(
        request.data?.termsAcceptanceSnapshot,
      ),
      path: "web", // IN-02 — helper 로그 경로 구분 축.
    });

    // Step 4: structured log — uid · isNewUser · expiresInSec 만 (D-51).
    logger.info(
      {
        event: "naver_web_custom_token_issued",
        uid: result.uid,
        isNewUser: result.isNewUser,
        expiresInSec,
      },
      "Naver web custom token issued",
    );
    return result;
  },
);
