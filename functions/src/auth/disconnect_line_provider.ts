// Phase 16.10 SOCL-13 · SOCL-15 — LINE 앱 권한 해제 callable (재로그인 + 서버).
//
// 탈퇴 진행 화면의 LINE 행 · 해제 다이얼로그가 호출한다. client 가 LINE 으로
// 다시 로그인해 얻은 사용자 access token 을 받아, 서버가 신원을 대조한 뒤
// LINE Login API deauthorize 로 사용자가 앱에 준 권한을 해제한다.
//
// 공식 요건 (C-09 · LINE 원문): "When a user unregisters from your app … or
// when a user terminates the link between your app and the LINE app, you must
// do the following: The permissions that the user has granted to the
// authorized app must be deauthorized …" — 탈퇴와 연동 해제 모두 deauthorize
// 가 필수다.
//
// 결정 (16.10-CONTEXT · RESEARCH OQ6):
// - D-02: deauthorize 는 사용자 access token(재로그인)과 channel access
//   token(서버 · channel secret 필요)이 둘 다 필요해 서버를 거친다.
// - D-08: 재로그인한 LINE 신원(`/v2/profile` userId — ID token `sub` 와 같은
//   값)이 `identity_index` 에서 caller 소유인지 먼저 대조한다. 대조가
//   channel token 발급 · deauthorize 보다 앞이다 — 다른 사람의 LINE 으로
//   로그인한 경우 그 사람의 앱 권한을 해제하지 않는다.
// - D-07: 해제 성공 뒤 caller uid 로 custom token 을 만들어 돌려준다. client
//   는 탈퇴 진행 화면에서만 그 토큰으로 로그인해 `auth_time` 을 갱신한다.
// - channel token = stateless(유효 15분 · 발급 상한 없음 · 폐기 불가). 호출
//   마다 새로 발급해 지역 변수로만 쓴다 — 저장 · 캐시 · 로그 0 (C-03).
//   v2.1 JWT 방식은 콘솔 공개키 등록 · 서명 코드가 필요해 채택하지 않았다.
// - deauthorize 본문 = JSON `{"userAccessToken": …}` +
//   `Content-Type: application/json`. 채택 근거는 plan 01 A11 dry-run 이다 —
//   JSON 빈 객체는 「[userAccessToken] must not be null」 로 본문을 파싱했고,
//   form 본문은 415 로 거부됐다.
// - 채널 귀속 검증 (16.10 review WR-02): `/v2/profile` 200 은 토큰이 **이
//   채널(`LINE_CHANNEL_ID`)에서 발급됐는지** 보여 주지 않는다 — 같은 LINE
//   provider 의 다른 채널 토큰도 같은 userId 를 준다. 그래서 LINE 공식
//   `GET https://api.line.me/oauth2/v2.1/verify?access_token=…` 로
//   `client_id`("Channel ID for which the access token is issued" · String)
//   === `LINE_CHANNEL_ID` 와 `expires_in`(Number) > 0 을 먼저 확인한다.
//   불일치 · 만료 · 400(형식 오류 · 만료 · 폐기)은 `idpCredentialRejected`
//   로 끝나고 소유 대조 · 발급 · 해제 · custom token 은 0 이다. 계약 출처 =
//   developers.line.biz/en/reference/line-login/ 「Verify access token
//   validity」 SSR 원문(2026-09-29 확인). 토큰을 쿼리에 싣는 것은 공식
//   계약이며 URL 은 로그에 남기지 않는다.
// - D-14 멱등: deauthorize 400 은 성공으로 본다. LINE reference 원문 —
//   "Invalid access token for the target user … The user has already
//   deauthorized your app. / You have already deauthorized your app on behalf
//   of the user via the API." 이 매핑은 위 채널 귀속 검증과 프로필 200 을
//   **모두 통과한 뒤에만** 도달한다 — 이 채널의 유효한 토큰이 거부되는
//   경우만 「이미 해제」 로 본다. 400 본문의 `error` 코드는 대조하지 않는다:
//   실측 본문(wave0 A11 — `message` 만 · `invalid token` /
//   `[userAccessToken] must not be null`)에 「이미 해제」 를 구분하는 코드가
//   관측된 적이 없어 값을 지어낼 근거가 없다.
//
// 순서 함정 (RESEARCH Pitfall 1 · plan 06): LINE SDK `logout()` 은 access
// token 을 서버에서 폐기한다. client 는 이 callable 응답을 받은 뒤에만
// `logout()` 해야 한다 — 먼저 폐기되면 deauthorize 가 400 으로 끝나 권한이
// 실제로는 남는다.
//
// provider 제거 = 이 파일 + `index.ts` export 1줄 + `LINE_CHANNEL_SECRET`
// 선언(`shared/oidc_providers.ts`) + 배포 정리(`functions:delete`). 기존 LINE
// 로그인 · 연결 callable 은 편집하지 않는다. 다른 provider 모듈은 import 하지
// 않는다 — 제어문자 검사도 지역 함수로 둔다 (C-08).
//
// **IN-04**: 아래 `HttpsError` 의 message 는 ARB 키가 아니라 taxonomy
// 토큰이다. client 는 `code` + `details.reason` 으로만 분기한다 —
// `shared/custom_token_errors.ts` 헤더 참조.
import {getFirestore} from "firebase-admin/firestore";
import {onCall, HttpsError} from "firebase-functions/https";
import * as logger from "firebase-functions/logger";

import {isAnonymousCaller} from "../shared/caller_auth";
import {
  anonymousDisconnectNotAllowed,
  idpCredentialRejected,
  idpUnavailable,
  invalidArgument,
  providerConfigError,
  serverFailure,
} from "../shared/custom_token_errors";
import {LINE_CHANNEL_ID, LINE_CHANNEL_SECRET} from "../shared/oidc_providers";
import {mintReloginToken} from "../shared/relogin_token";
import {requireStringArg} from "../shared/require_string_arg";
import {assertIdentityOwnedByCaller} from "./identity_ownership";

/** LINE access token 검증 엔드포인트 — 쿼리 `access_token` (공식 계약). */
const LINE_VERIFY_URL = "https://api.line.me/oauth2/v2.1/verify";

/** LINE 사용자 프로필 엔드포인트 — Bearer 사용자 access token. */
const LINE_PROFILE_URL = "https://api.line.me/v2/profile";

/** stateless channel access token 발급 엔드포인트. */
const LINE_STATELESS_TOKEN_URL = "https://api.line.me/oauth2/v3/token";

/** 사용자 앱 권한 해제 엔드포인트 — Bearer channel access token. */
const LINE_DEAUTHORIZE_URL = "https://api.line.me/user/v1/deauthorize";

/** 외부 호출 timeout — 헤더 + 본문 전체 5s (기존 서버 관례). */
const FETCH_TIMEOUT_MS = 5000;

/** 「이미 해제됨」 으로 보는 deauthorize 응답 status (D-14 멱등). */
const LINE_ALREADY_DEAUTHORIZED_STATUS = 400;

/**
 * `disconnectLineProvider` 요청.
 *
 * 필드는 신뢰할 수 없는 임의 JSON 이라 `unknown` 으로 받고 Step 2 에서
 * 좁힌다.
 */
type DisconnectLineProviderRequest = {
  /** LINE SDK 재로그인으로 얻은 사용자 access token. */
  accessToken?: unknown;
};

/** `disconnectLineProvider` 응답 — 재로그인 custom token 과 발급 uid. */
type DisconnectLineProviderResponse = {
  ok: true;
  /** caller uid 로 발급한 custom token — 탈퇴 진행 화면만 소비한다. */
  customToken: string;
  /** 발급 대상 uid (= `request.auth.uid`) — client 재대조용. */
  uid: string;
};

/**
 * HTTP 헤더 injection 에 쓰일 수 있는 제어문자(CR · LF · NUL)가 있는지 본다.
 *
 * 다른 provider 모듈의 상수를 import 하지 않고 이 파일에 둔다 — 그 provider
 * 를 제거해도 LINE 끊기가 깨지지 않게 한다 (C-08).
 *
 * @param {string} value 검사할 문자열.
 * @return {boolean} CR · LF · NUL 중 하나라도 있으면 true.
 */
function hasHeaderControlChars(value: string): boolean {
  return /[\r\n]/.test(value) || value.includes("\u0000");
}

/**
 * 응답 본문을 JSON 으로 읽어 문자열 필드 하나를 꺼낸다.
 *
 * 본문 읽기 실패 · JSON 아님 · 객체 아님 · 필드가 비어 있지 않은 문자열이
 * 아님 · 제어문자 포함이면 undefined 다. 다른 필드는 읽지 않는다.
 *
 * @param {Response} resp fetch 응답.
 * @param {string} key 꺼낼 필드 이름.
 * @return {Promise<string | undefined>} 필드 값 또는 undefined.
 */
async function readStringFieldFromBody(
  resp: Response,
  key: string,
): Promise<string | undefined> {
  let parsed: unknown;
  try {
    parsed = await resp.json();
  } catch {
    return undefined;
  }
  if (typeof parsed !== "object" || parsed === null) return undefined;
  const value = (parsed as Record<string, unknown>)[key];
  if (typeof value !== "string" || value.length === 0) return undefined;
  return hasHeaderControlChars(value) ? undefined : value;
}

/**
 * 사용자 access token 이 이 채널에서 발급된 유효 토큰인지 LINE verify 로
 * 확인한다 (16.10 review WR-02).
 *
 * 계약 (LINE Login v2.1 reference 「Verify access token validity」 원문):
 * `GET /oauth2/v2.1/verify?access_token=…` → 200 JSON `{scope, client_id
 * (String), expires_in (Number)}` · 400 = 형식 오류 · 만료 · 폐기.
 *
 * 매핑:
 * - fetch reject (TimeoutError · network) → `unavailable`
 * - HTTP 400 → `unauthenticated` (`errorInvalidCredentials`)
 * - 그 밖 비-2xx → `unavailable`
 * - 2xx 인데 `client_id` 가 문자열이 아님 · `expires_in` 이 숫자가 아님 →
 *   `internal` (IdP 계약 위반)
 * - `client_id` ≠ `LINE_CHANNEL_ID` · `expires_in` ≤ 0 → `unauthenticated`
 *
 * 로그 payload 는 `{event, uid}` + `status | code | reason` 뿐이다 — 토큰 ·
 * URL · `client_id` 값 · `scope` 는 싣지 않는다.
 *
 * @param {{accessToken: string, uid: string}} args 사용자 access token ·
 *     로그 축 uid.
 * @return {Promise<void>} 이 채널의 유효 토큰이면 resolve.
 * @throws {HttpsError} 위 매핑 표에 따른 표준 에러.
 */
async function verifyLineAccessTokenChannel(args: {
  accessToken: string;
  uid: string;
}): Promise<void> {
  const {accessToken, uid} = args;
  let resp: Response;
  try {
    resp = await fetch(
      `${LINE_VERIFY_URL}?access_token=${encodeURIComponent(accessToken)}`,
      {method: "GET", signal: AbortSignal.timeout(FETCH_TIMEOUT_MS)},
    );
  } catch (err: unknown) {
    // err.message 미로깅 — URL(토큰 포함)이 실릴 수 있다. err.name 만.
    logger.error(
      {
        event: "disconnect_line_verify_failed",
        uid,
        code: err instanceof Error ? err.name : "unknown",
      },
      "LINE verify request failed",
    );
    throw idpUnavailable();
  }

  if (!resp.ok) {
    logger.error(
      {event: "disconnect_line_verify_failed", uid, status: resp.status},
      "LINE verify rejected",
    );
    if (resp.status === 400) throw idpCredentialRejected();
    throw idpUnavailable();
  }

  let parsed: unknown;
  try {
    parsed = await resp.json();
  } catch {
    parsed = undefined;
  }
  const body =
    typeof parsed === "object" && parsed !== null ?
      (parsed as Record<string, unknown>) :
      {};
  const clientId = body["client_id"];
  const expiresIn = body["expires_in"];
  if (typeof clientId !== "string" || typeof expiresIn !== "number") {
    logger.error(
      {event: "disconnect_line_verify_invalid", uid},
      "LINE verify body invalid",
    );
    throw serverFailure();
  }
  if (clientId !== LINE_CHANNEL_ID.value()) {
    logger.warn(
      {event: "disconnect_line_verify_rejected", uid, reason: "channel"},
      "LINE access token issued for another channel",
    );
    throw idpCredentialRejected();
  }
  if (!(expiresIn > 0)) {
    logger.warn(
      {event: "disconnect_line_verify_rejected", uid, reason: "expired"},
      "LINE access token expired",
    );
    throw idpCredentialRejected();
  }
}

/**
 * 사용자 access token 으로 LINE 프로필을 조회해 `userId` 만 꺼낸다.
 *
 * 매핑 (D-12):
 * - fetch reject (TimeoutError · network) → `unavailable`
 * - HTTP 401 → `unauthenticated` (`errorInvalidCredentials`)
 * - 그 밖 비-2xx → `unavailable`
 * - 2xx 인데 `userId` 가 없거나 형식이 틀림 → `internal`
 *
 * `displayName` 등 다른 프로필 필드는 읽지 않는다 (C-06).
 *
 * @param {{accessToken: string, uid: string}} args 사용자 access token ·
 *     로그 축 uid.
 * @return {Promise<string>} LINE userId (로그 금지).
 * @throws {HttpsError} 위 매핑 표에 따른 표준 에러.
 */
async function fetchLineUserId(args: {
  accessToken: string;
  uid: string;
}): Promise<string> {
  const {accessToken, uid} = args;
  let resp: Response;
  try {
    resp = await fetch(LINE_PROFILE_URL, {
      method: "GET",
      headers: {Authorization: `Bearer ${accessToken}`},
      signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
    });
  } catch (err: unknown) {
    // err.message 미로깅 — err.name 만 fingerprint.
    logger.error(
      {
        event: "disconnect_line_profile_failed",
        uid,
        code: err instanceof Error ? err.name : "unknown",
      },
      "LINE profile request failed",
    );
    throw idpUnavailable();
  }

  if (!resp.ok) {
    logger.error(
      {event: "disconnect_line_profile_failed", uid, status: resp.status},
      "LINE profile rejected",
    );
    if (resp.status === 401) throw idpCredentialRejected();
    throw idpUnavailable();
  }

  const userId = await readStringFieldFromBody(resp, "userId");
  if (userId === undefined) {
    logger.error(
      {event: "disconnect_line_profile_invalid", uid},
      "LINE profile body invalid",
    );
    throw serverFailure();
  }
  return userId;
}

/**
 * deauthorize 에 쓸 stateless channel access token 을 발급한다.
 *
 * form body 3 필드(`grant_type=client_credentials` · `client_id` ·
 * `client_secret`)를 POST 한다 (plan 01 A1 dry-run 확정). 토큰은 호출자의
 * 지역 변수로만 쓰고 저장 · 캐시 · 로그하지 않는다 (C-03).
 *
 * 매핑 (D-12):
 * - fetch reject → `unavailable`
 * - HTTP 400 · 401 → `failed-precondition` (reason `provider_config` —
 *   채널 ID · secret 불일치 등 운영자 설정 결함)
 * - 그 밖 비-2xx → `unavailable`
 * - 2xx 인데 `access_token` 이 없거나 형식이 틀림 → `internal`
 *
 * @param {string} uid 로그 축 uid.
 * @return {Promise<string>} channel access token (로그 금지).
 * @throws {HttpsError} 위 매핑 표에 따른 표준 에러.
 */
async function issueStatelessChannelToken(uid: string): Promise<string> {
  let resp: Response;
  try {
    resp = await fetch(LINE_STATELESS_TOKEN_URL, {
      method: "POST",
      headers: {"Content-Type": "application/x-www-form-urlencoded"},
      body: new URLSearchParams({
        grant_type: "client_credentials",
        client_id: LINE_CHANNEL_ID.value(),
        client_secret: LINE_CHANNEL_SECRET.value(),
      }),
      signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
    });
  } catch (err: unknown) {
    logger.error(
      {
        event: "disconnect_line_channel_token_failed",
        uid,
        code: err instanceof Error ? err.name : "unknown",
      },
      "LINE channel token request failed",
    );
    throw idpUnavailable();
  }

  if (!resp.ok) {
    logger.error(
      {event: "disconnect_line_channel_token_failed", uid, status: resp.status},
      "LINE channel token rejected",
    );
    if (resp.status === 400 || resp.status === 401) {
      throw providerConfigError();
    }
    throw idpUnavailable();
  }

  const channelToken = await readStringFieldFromBody(resp, "access_token");
  if (channelToken === undefined) {
    logger.error(
      {
        event: "disconnect_line_channel_token_failed",
        uid,
        code: "invalid_body",
      },
      "LINE channel token body invalid",
    );
    throw serverFailure();
  }
  return channelToken;
}

/**
 * LINE deauthorize 로 사용자가 앱에 준 권한을 해제한다 (C-09 · D-02).
 *
 * `Authorization: Bearer <channel token>` + JSON 본문 `{userAccessToken}` 을
 * POST 한다. 매핑 (D-12 · D-14):
 * - HTTP 2xx (문서상 204) → 성공
 * - HTTP 400 → 「이미 해제됨」 으로 성공 (D-14 멱등 · reference 원문). 호출부가
 *   verify(채널 귀속 · 만료) · 프로필 200 을 통과한 뒤에만 이 함수에 온다
 *   (WR-02) — 이 전제 없이 이 함수를 재사용하지 않는다.
 * - HTTP 401 → `failed-precondition` (reason `provider_config` — channel
 *   token 거부)
 * - fetch reject · 그 밖 → `unavailable`
 *
 * 응답 본문은 읽지 않는다 — 로그 payload 는 `{event, uid, status | code}`.
 *
 * @param {{channelToken: string, userAccessToken: string, uid: string}} args
 *     channel token · 해제 대상 사용자 access token · 로그 축 uid.
 * @return {Promise<void>} 해제(또는 이미 해제) 시 resolve.
 * @throws {HttpsError} 위 매핑 표에 따른 표준 에러.
 */
async function deauthorizeLineUser(args: {
  channelToken: string;
  userAccessToken: string;
  uid: string;
}): Promise<void> {
  const {channelToken, userAccessToken, uid} = args;
  let resp: Response;
  try {
    resp = await fetch(LINE_DEAUTHORIZE_URL, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${channelToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({userAccessToken}),
      signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
    });
  } catch (err: unknown) {
    logger.error(
      {
        event: "disconnect_line_deauthorize_failed",
        uid,
        code: err instanceof Error ? err.name : "unknown",
      },
      "LINE deauthorize request failed",
    );
    throw idpUnavailable();
  }

  if (resp.ok) return;
  if (resp.status === LINE_ALREADY_DEAUTHORIZED_STATUS) {
    logger.info(
      {event: "disconnect_line_already_deauthorized", uid},
      "LINE already deauthorized",
    );
    return;
  }

  logger.error(
    {event: "disconnect_line_deauthorize_failed", uid, status: resp.status},
    "LINE deauthorize rejected",
  );
  if (resp.status === 401) throw providerConfigError();
  throw idpUnavailable();
}

/**
 * LINE 앱 권한 해제 callable (Phase 16.10 SOCL-13 · SOCL-15).
 *
 * 호출 조건: App Check 필수 · 로그인 필수 · 익명 caller 거부.
 *
 * 흐름:
 *   Step 0: `request.auth` 검증.
 *   Step 1: 익명 caller 거부 (`failed-precondition` · reason
 *           `anonymous_caller`).
 *   Step 2: 입력 위생 — `accessToken` 은 비어 있지 않은 문자열 · 길이 상한 ·
 *           CR/LF/NUL 없음. 아니면 `invalid-argument`.
 *   Step 3: `/oauth2/v2.1/verify` 채널 귀속 · 만료 검증과 `/v2/profile`
 *           userId 획득을 병렬로 한다 — 둘 다 사용자 토큰 읽기뿐이라 부작용이
 *           없다. 결과는 verify 먼저 판정한다(verify 실패면 프로필 결과와
 *           무관하게 그 거부 · WR-02). 직렬 5s+5s 대신 5s (WR-03).
 *   Step 4: `identity_index/line:{userId}` 가 caller 소유인지 대조 — 아니면
 *           `permission-denied` · reason `caller_identity_mismatch` (channel
 *           token 발급 · deauthorize · custom token 0 · D-08).
 *   Step 5: stateless channel access token 발급.
 *   Step 6: deauthorize (400 = 이미 해제 · 성공).
 *   Step 7: caller uid 로 재로그인 custom token 발급 → 성공 로그 →
 *           `{ok: true, customToken, uid}`.
 *
 * **PII 금지 (C-03 · C-06):** logger payload 는 `{event, uid}` 와 실패 시
 * `status | code | reason` 뿐이다. 사용자 access token · LINE userId · channel
 * secret · channel token · 프로필 이름 · custom token 은 로그 · HttpsError
 * details 에 싣지 않는다. 토큰은 이 호출의 지역 변수로만 존재하고, custom
 * token 은 응답에만 싣는다.
 *
 * @param {{data: DisconnectLineProviderRequest, auth?: {uid: string}}}
 *     request onCall request — auth 는 Step 0 에서 검증.
 * @return {Promise<DisconnectLineProviderResponse>}
 *     `{ok: true, customToken, uid}`.
 */
export const disconnectLineProvider = onCall<DisconnectLineProviderRequest>(
  {
    enforceAppCheck: true,
    secrets: [LINE_CHANNEL_ID, LINE_CHANNEL_SECRET],
  },
  async (request): Promise<DisconnectLineProviderResponse> => {
    // Step 0: auth.
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "errorUnauthenticated");
    }
    const uid = request.auth.uid;

    // Step 1: 익명 caller 거부 — 익명 계정에는 해제할 권한이 없다.
    if (isAnonymousCaller(request.auth)) {
      throw anonymousDisconnectNotAllowed();
    }

    // Step 2: 입력 위생 — Authorization 헤더 injection 방어 (CR/LF/NUL).
    const accessToken = requireStringArg(request.data?.accessToken);
    if (hasHeaderControlChars(accessToken)) {
      throw invalidArgument();
    }

    // Step 3: LINE 검증 — 채널 귀속(verify) ∥ userId(profile). 둘 다 읽기
    // 전용이라 병렬로 부르고(WR-03), 판정은 verify 먼저다(WR-02). allSettled
    // 로 두 결과를 모두 기다려 어느 거부가 이기는지를 결정적으로 만든다.
    // userId 만 소비한다 (displayName 미독 · C-06).
    const [verified, profile] = await Promise.allSettled([
      verifyLineAccessTokenChannel({accessToken, uid}),
      fetchLineUserId({accessToken, uid}),
    ]);
    if (verified.status === "rejected") throw verified.reason;
    if (profile.status === "rejected") throw profile.reason;
    const userId = profile.value;

    // Step 4: 소유 대조 — channel token 발급 · deauthorize 보다 앞 (D-08).
    await assertIdentityOwnedByCaller({
      db: getFirestore(),
      provider: "line",
      providerUserId: userId,
      callerUid: uid,
    });

    // Step 5: stateless channel token — 지역 변수로만 (C-03).
    const channelToken = await issueStatelessChannelToken(uid);

    // Step 6: LINE 측 앱 권한 해제.
    await deauthorizeLineUser({
      channelToken,
      userAccessToken: accessToken,
      uid,
    });

    // Step 7: 재로그인 custom token — 응답에만 싣는다 (D-07).
    const customToken = await mintReloginToken({uid, provider: "line"});
    logger.info({event: "disconnect_line_succeeded", uid}, "LINE disconnected");
    return {ok: true, customToken, uid};
  },
);
