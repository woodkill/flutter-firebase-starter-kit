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
import {
  idpCredentialRejected,
  idpUnavailable,
  invalidArgument,
  serverFailure,
} from "../shared/custom_token_errors";
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

// token 교환 endpoint (RESEARCH §3).
const NAVER_TOKEN_URL = "https://nid.naver.com/oauth2.0/token" as const;

// Phase 13 Pitfall 3 미러 — NAVER 5xx hang 방어. 함수 30s timeout 이전 abort.
// IN-04 (16.5 review 2회차) — `AbortSignal.timeout` 이라 헤더 수신뿐 아니라
// `resp.json()` 본문 읽기까지 이 5s 안에 끝나야 한다.
const FETCH_TIMEOUT_MS = 5000;

// NAVER 응답 expires_in 을 관측 필드로 좁히는 형식 — 1~7자리 숫자 문자열.
// 형식 밖(토큰 반사 · 임의 문자열)은 null 로 버려 로그에 원문이 실리지 않는다.
const EXPIRES_IN_PATTERN = /^[0-9]{1,7}$/;

// expires_in 정수 상한 (7자리 = 9999999초). 문자열 형식 상한과 같다.
const MAX_EXPIRES_IN_SEC = 9999999;

// 제어 문자 (CR / LF / NUL). code · state 는 form body 로만 나가므로 HTTP 헤더
// injection 표면은 없다 — 1-tap 경로와 같은 입력 위생 가드로 유지한다.
// access_token 은 helper 가 Authorization 헤더에 실으므로 같은 필터를 적용한다.
// eslint-disable-next-line no-control-regex -- 의도된 CRLF/NUL 필터 (WR-01)
const CONTROL_CHARS = /[\r\n\x00]/;

// NAVER 본문 error 코드 화이트리스트 — 로그 필드는 이 형식일 때만 원문,
// 아니면 "other" (토큰 · 임의 문자열 반사 차단, T-16.5-03).
const NAVER_ERROR_CODE_PATTERN = /^[a-z_]{1,32}$/;

type NaverWebCustomTokenRequest = {
  /** NAVER authorize 콜백의 authorization code. */
  code: string;
  /** client 가 authorize 요청에 실은 state — 서버는 비교하지 않고 전달만. */
  state: string;
  /** Phase 16 D-13/D-14 — 신규 UID 일 때만 termsAccepted mirror. */
  termsAcceptanceSnapshot?: TermsAcceptanceJson;
};

// NAVER token 응답 본문 shape (RESEARCH §2 — Android NidOAuthResponse DTO ·
// iOS CodingKeys 실측). 비신뢰 JSON 이므로 전 필드 unknown 으로 받아 런타임에
// 좁힌다. expires_in 은 parseExpiresInSec 로만 좁혀 로그에 싣고
// refresh_token · token_type 은 읽지 않는다 (refresh_token 미저장 · 미로깅 —
// D-15 중 유지되는 부분).
type NaverTokenResponse = {
  access_token?: unknown;
  refresh_token?: unknown;
  token_type?: unknown;
  expires_in?: unknown;
  error?: unknown;
  error_description?: unknown;
};

// token 교환 결과 — accessToken 은 helper 인자로만, expiresInSec 는 로그로만.
type NaverTokenExchange = {
  accessToken: string;
  expiresInSec: number | null;
};

/**
 * NAVER token 응답의 expires_in 을 정수 초로 좁힌다 (quick 260924-lw2).
 *
 * 폐기 없이 남는 access_token 의 잔존 노출 상한을 서버 로그로 관측하기 위한
 * 값이다. 1~7자리 숫자 문자열 또는 0~{@link MAX_EXPIRES_IN_SEC} 안전 정수만
 * 통과시키고 그 외(부재 · 음수 · 소수 · 8자리 이상 · 임의 문자열)는 null —
 * 원문 값은 어떤 경우에도 로그에 싣지 않는다. 절대 throw 하지 않는다.
 *
 * @param {unknown} value 비신뢰 응답의 expires_in 필드.
 * @return {(number|null)} 정수 초 또는 null.
 */
function parseExpiresInSec(value: unknown): number | null {
  if (typeof value === "string") {
    return EXPIRES_IN_PATTERN.test(value) ? Number(value) : null;
  }
  if (
    typeof value === "number" &&
    Number.isSafeInteger(value) &&
    value >= 0 &&
    value <= MAX_EXPIRES_IN_SEC
  ) {
    return value;
  }
  return null;
}

/**
 * token 교환 실패의 PII-safe fingerprint 를 남긴다.
 *
 * payload 는 `{event, status?, code?}` 뿐 — 응답 본문 · code · state ·
 * client_secret 은 절대 싣지 않는다 (D-51).
 *
 * @param {{status: (number|undefined), code: (string|undefined)}} fingerprint
 *     HTTP status 또는 `err.name` (둘 중 하나).
 */
function logTokenExchangeFailure(fingerprint: {
  status?: number;
  code?: string;
}): void {
  logger.warn(
    {event: "naver_web_token_exchange_failed", ...fingerprint},
    "Naver token exchange failed",
  );
}

/**
 * authorization code 를 NAVER access_token 으로 교환한다 (D-13).
 *
 * 3단 검사 (RESEARCH Pitfall 4 — 실패가 HTTP 200 + 본문 error 로 올 수 있다):
 * 1. fetch reject (`AbortSignal.timeout` 초과 = TimeoutError / network) →
 *    unavailable. HTTP 401/403 → unauthenticated. 5xx · 기타 non-OK →
 *    unavailable.
 * 2. 본문 읽기 중 5s 초과(TimeoutError) → unavailable (1 의 timeout 과 같은
 *    결과 — IN-04). 그 외 JSON parse 실패 · 비객체 본문 → internal.
 * 3. 본문 error 존재 또는 access_token 부재 · 비문자열 · 제어문자 →
 *    unauthenticated.
 *
 * @param {{code: string, state: string}} args 검증된 code · state.
 * @return {Promise<NaverTokenExchange>} 교환된 access_token (로그 · 응답
 *     미노출) + 관측용 expiresInSec.
 * @throws {HttpsError} 위 매핑 표에 따른 표준 에러.
 */
async function exchangeNaverAuthCode(args: {
  code: string;
  state: string;
}): Promise<NaverTokenExchange> {
  // 5 파라미터 — state 는 Android SDK 처럼 보낸다 (iOS SDK 는 생략, 선택적).
  // 서버는 authorize 단계의 콜백 주소 파라미터를 싣지 않는다 (양 SDK 미전송).
  const body = new URLSearchParams({
    grant_type: "authorization_code",
    client_id: NAVER_CLIENT_ID.value(),
    client_secret: NAVER_CLIENT_SECRET.value(),
    code: args.code,
    state: args.state,
  });

  let resp: Response;
  try {
    resp = await fetch(NAVER_TOKEN_URL, {
      method: "POST",
      headers: {"Content-Type": "application/x-www-form-urlencoded"},
      body,
      // IN-04 — 헤더 + 본문(resp.json) 전체 5s. 초과 시 TimeoutError.
      signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
    });
  } catch (err: unknown) {
    // PII 금지 (D-51) — err.message 미로깅, err.name 만 fingerprint.
    logTokenExchangeFailure({
      code: err instanceof Error ? err.name : "unknown",
    });
    throw idpUnavailable();
  }

  if (!resp.ok) {
    logTokenExchangeFailure({status: resp.status});
    // WR-01 공용 매핑 표 — 401/403 = 자격증명 거부, 그 외 (5xx · 429 등) =
    // IdP 도달 실패 (transient).
    if (resp.status === 401 || resp.status === 403) {
      throw idpCredentialRejected();
    }
    throw idpUnavailable();
  }

  let parsed: unknown;
  try {
    parsed = await resp.json();
  } catch (err: unknown) {
    const errName = err instanceof Error ? err.name : "unknown";
    logTokenExchangeFailure({code: errName});
    // IN-04 — 본문 읽기 도중 5s 초과는 헤더 전 timeout 과 같은 IdP 도달 실패
    // (transient) 다. 파싱 실패(internal)와 구분한다.
    if (errName === "TimeoutError") {
      throw idpUnavailable();
    }
    throw serverFailure();
  }
  if (typeof parsed !== "object" || parsed === null) {
    logTokenExchangeFailure({code: "non_object_body"});
    throw serverFailure();
  }
  const tokenBody = parsed as NaverTokenResponse;

  // Pitfall 4 — HTTP 200 이어도 본문 error 가 올 수 있다. error 존재 또는
  // access_token 부재 · 비문자열을 모두 자격증명 거부로 본다.
  const accessToken = tokenBody.access_token;
  if (
    tokenBody.error !== undefined ||
    typeof accessToken !== "string" ||
    accessToken.length === 0 ||
    CONTROL_CHARS.test(accessToken)
  ) {
    const errorCode =
      typeof tokenBody.error === "string" &&
      NAVER_ERROR_CODE_PATTERN.test(tokenBody.error) ?
        tokenBody.error :
        "other";
    logger.warn(
      {event: "naver_web_token_error_response", error: errorCode},
      "Naver token endpoint returned error body",
    );
    throw idpCredentialRejected();
  }
  return {
    accessToken,
    expiresInSec: parseExpiresInSec(tokenBody.expires_in),
  };
}

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
