// Phase 16.5 SOCL-14 — Naver authorization code → Firebase Custom Token
// (킷 소유 웹 경로).
//
// NAVER 토큰 API 파라미터 진실원 = NAVER 공식 SDK 2종 소스 (RESEARCH
// 「NAVER OAuth 2.0 엔드포인트 계약」):
// - 교환: naveridlogin-sdk-ios-swift 5.2.1 IssueAccessTokenRequest.swift
//   (POST · form-urlencoded) + com.navercorp.nid:oauth 5.11.2
//   NidOAuthLoginService.requestAccessToken (state 포함).
// - 폐기: DeleteAccessTokenRequest.swift — service_provider 포함 5 파라미터.
// redirect_uri 는 양 SDK 모두 보내지 않는다 → 본 서버도 보내지 않는다.
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

// token 교환 · 폐기 공용 endpoint (별도 revoke URL 없음 — RESEARCH §3).
const NAVER_TOKEN_URL = "https://nid.naver.com/oauth2.0/token" as const;

// Phase 13 Pitfall 3 미러 — NAVER 5xx hang 방어. 함수 30s timeout 이전 abort.
// IN-04 (16.5 review 2회차) — `AbortSignal.timeout` 이라 헤더 수신뿐 아니라
// `resp.json()` 본문 읽기까지 이 5s 안에 끝나야 한다 (revoke 와 같은 방식).
const FETCH_TIMEOUT_MS = 5000;

// WR-01 (16.5 review) — revoke 는 best-effort 이고 응답 반환 전에 await 되므로
// 짧은 예산만 준다. 웹 경로는 NAVER 를 직렬 3회(교환 5s · /v1/nid/me 5s ·
// revoke 2s) 호출하며, 합계 12s + Firestore · cold start 가 클라이언트 웹 경로
// callable timeout(auth_repository.dart `_kNaverWebCustomTokenTimeout` 20s)
// 안에 들어와야 「서버 성공 · 클라 deadline-exceeded」 부분 성공이 생기지 않는다.
// 세 fetch 모두 `AbortSignal.timeout` 이라 각 예산은 본문 읽기까지 포함한
// 상한이다 (IN-04 — 이전에는 교환 · 프로필이 헤더 수신까지만 bounded).
const REVOKE_TIMEOUT_MS = 2000;

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
// 좁힌다. refresh_token · token_type · expires_in 은 형상 문서화용 선언이며
// 읽지 않는다 (D-15 — refresh_token 미저장 · 미로깅).
type NaverTokenResponse = {
  access_token?: unknown;
  refresh_token?: unknown;
  token_type?: unknown;
  expires_in?: unknown;
  error?: unknown;
  error_description?: unknown;
};

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
 * @return {Promise<string>} 교환된 access_token (로그 · 응답 미노출).
 * @throws {HttpsError} 위 매핑 표에 따른 표준 에러.
 */
async function exchangeNaverAuthCode(args: {
  code: string;
  state: string;
}): Promise<string> {
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
  return accessToken;
}

/**
 * 교환된 access_token 을 best-effort 로 폐기한다 (D-15).
 *
 * token 교환과 같은 endpoint 에 grant_type=delete + service_provider=NAVER 를
 * 포함한 5 파라미터를 보낸다 (Pitfall 5 — 누락 시 무응답). 실패는 경고 로그만
 * 남기고 로그인 결과를 바꾸지 않는다.
 *
 * 성공 판정 (WR-02 — 교환과 같은 Pitfall 4 대칭: 같은 endpoint 가 실패를
 * HTTP 200 + 본문 error 로 돌려준다):
 * - fetch reject (`AbortSignal.timeout` 초과 = TimeoutError / network) →
 *   `{code: err.name}`
 * - HTTP non-OK → `{status}`
 * - JSON parse 실패 → `{code: err.name}` · 비객체 본문 → `{code:
 *   "non_object_body"}`
 * - 본문 `result !== "success"` → `{code: "error_body", error}` — error 는
 *   {@link NAVER_ERROR_CODE_PATTERN} 화이트리스트 통과 시 원문, 아니면
 *   "other". 성공 본문도 access_token 을 되돌려 주므로 본문 원문은 절대
 *   로깅하지 않는다 (D-51).
 *
 * 위 어느 것에도 걸리지 않을 때만 성공이다 — `naver_web_revoke_failed` 부재 =
 * NAVER 가 `result: "success"` 를 돌려줬다는 뜻이다.
 *
 * @param {string} accessToken 폐기할 NAVER access_token.
 * @return {Promise<void>} 성공 · 실패와 무관하게 resolve (never throws).
 */
async function revokeNaverToken(accessToken: string): Promise<void> {
  let failure: {status?: number; code?: string; error?: string} | null = null;
  try {
    const resp = await fetch(NAVER_TOKEN_URL, {
      method: "POST",
      headers: {"Content-Type": "application/x-www-form-urlencoded"},
      body: new URLSearchParams({
        grant_type: "delete",
        client_id: NAVER_CLIENT_ID.value(),
        client_secret: NAVER_CLIENT_SECRET.value(),
        access_token: accessToken,
        service_provider: "NAVER",
      }),
      signal: AbortSignal.timeout(REVOKE_TIMEOUT_MS),
    });
    if (!resp.ok) {
      failure = {status: resp.status};
    } else {
      // resp.json() reject 는 아래 catch 가 err.name fingerprint 로 받는다.
      const parsed: unknown = await resp.json();
      if (typeof parsed !== "object" || parsed === null) {
        failure = {code: "non_object_body"};
      } else {
        const revokeBody = parsed as {result?: unknown; error?: unknown};
        if (revokeBody.result !== "success") {
          failure = {
            code: "error_body",
            error:
              typeof revokeBody.error === "string" &&
              NAVER_ERROR_CODE_PATTERN.test(revokeBody.error) ?
                revokeBody.error :
                "other",
          };
        }
      }
    }
  } catch (err: unknown) {
    // PII 금지 (D-51) — err.name 만.
    failure = {code: err instanceof Error ? err.name : "unknown"};
  }
  if (failure) {
    logger.warn(
      {event: "naver_web_revoke_failed", ...failure},
      "Naver token revoke failed",
    );
  }
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
 * 4. finally — helper 성공 · 실패와 무관하게 access_token best-effort 폐기
 *    (D-15). refresh_token 은 읽지도 저장하지도 로깅하지도 않는다.
 *
 * **PII 금지 (D-51):** logger payload 는 {event, uid, isNewUser, status?,
 * code?, error?(화이트리스트 NAVER error 코드 — 교환 · revoke 공통)} 뿐.
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

    // Step 2: authorization code → access_token.
    const accessToken = await exchangeNaverAuthCode({code, state});

    // Step 3~4: helper 위임 + finally revoke (D-15 — 결과 무관 best-effort).
    let result: NaverCustomTokenResult;
    try {
      result = await verifyNaverProfileAndIssueCustomToken({
        accessToken,
        callerUid: request.auth?.uid, // unauthenticated 허용 (D-49).
        callerIsAnonymous: isAnonymousCaller(request.auth),
        termsSnapshot: parseTermsAcceptanceJson(
          request.data?.termsAcceptanceSnapshot,
        ),
        path: "web", // IN-02 — helper 로그 경로 구분 축.
      });
    } finally {
      await revokeNaverToken(accessToken);
    }

    // Step 5: structured log — uid + isNewUser 만 (PII 금지 D-51).
    logger.info(
      {
        event: "naver_web_custom_token_issued",
        uid: result.uid,
        isNewUser: result.isNewUser,
      },
      "Naver web custom token issued",
    );
    return result;
  },
);
