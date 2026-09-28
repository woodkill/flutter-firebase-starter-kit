// Phase 16.10 SOCL-13 · SOCL-15 — Naver 앱 연결 끊기 callable (재로그인 + 서버).
//
// 탈퇴 진행 화면의 Naver 행 · 해제 다이얼로그가 호출한다. client 가 Naver 로
// 다시 로그인해 얻은 access token(1-tap) 또는 authorization code(웹)를 받아,
// 서버가 신원을 대조한 뒤 NAVER Token Revocation 으로 앱 연결을 끊는다.
//
// 결정 (16.10-CONTEXT · RESEARCH):
// - D-02: Naver 는 revoke 에 client_secret 이 필요해 서버를 거친다.
// - D-08: 재로그인한 Naver 신원(`/v1/nid/me` id)이 `identity_index` 에서
//   caller 소유인지 먼저 대조한다. 대조가 revoke 보다 앞이다 — 다른 사람의
//   Naver 로 로그인한 경우 그 사람의 앱 연결을 끊지 않는다.
// - D-07: 끊기 성공 뒤 caller uid 로 custom token 을 만들어 돌려준다. client
//   는 탈퇴 진행 화면에서만 그 토큰으로 로그인해 `auth_time` 을 갱신한다
//   (탈퇴 5분 신선도를 이 로그인이 겸한다).
// - D-09: 해제에서도 같은 callable 을 쓴다 — 신선도 검사(caller ID token
//   재검증 · auth_time)는 두지 않는다. 탈퇴 신선도는 응답 토큰 소비로 만든다.
// - RESEARCH Pitfall 5: 웹 code 는 1회용이라 「재로그인 callable + 별도 끊기
//   callable」 두 번 호출은 성립하지 않는다 → 끊기 · 대조 · 토큰을 한 번에
//   묶는다.
// - quick 260924-lw2 대비: 로그인 경로(`naverCustomToken` ·
//   `naverWebCustomToken` · `linkNaverProvider`)는 revoke 를 보내지 않는다 —
//   NAVER 에서 revoke 는 연동 해제라 다음 로그인에 동의 화면이 다시 뜬다.
//   여기서는 그 재노출이 의도된 결과다.
// - D-14: 재로그인마다 새 access token 이 발급되므로 revoke 대상은 항상 있다.
//   이미 끊긴 계정의 재호출도 새 토큰 폐기로 끝난다 (멱등).
//
// provider 제거 = 이 파일 + `index.ts` export 1줄 + 배포 정리
// (`functions:delete`). 기존 Naver 로그인 · 연결 callable · 교환 모듈은
// 편집하지 않고 helper 를 호출만 한다 (C-08).
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
} from "../shared/custom_token_errors";
import {NAVER_CLIENT_ID, NAVER_CLIENT_SECRET} from "../shared/naver_secrets";
import {mintReloginToken} from "../shared/relogin_token";
import {
  MAX_NONCE_ARG_LENGTH,
  requireStringArg,
} from "../shared/require_string_arg";
import {assertIdentityOwnedByCaller} from "./identity_ownership";
import {fetchNaverProfile} from "./naver_profile_to_custom_token";
import type {NaverSignInPath} from "./naver_profile_to_custom_token";
import {
  exchangeNaverAuthCode,
  NAVER_CONTROL_CHARS,
} from "./naver_token_exchange";

/** NAVER Token Revocation 엔드포인트 (Naver 로그인 API 문서 3.3). */
const NAVER_REVOKE_URL = "https://nid.naver.com/oauth2.0/revoke";

/** 외부 호출 timeout — 헤더 + 본문 전체 5s (naver_token_exchange 관례). */
const FETCH_TIMEOUT_MS = 5000;

/**
 * revoke 응답 `error` 코드 화이트리스트 — 이 형식일 때만 로그에 원문,
 * 아니면 `"other"` (토큰 · 임의 문자열 반사 차단).
 *
 * `naver_token_exchange.ts` 의 private `NAVER_ERROR_CODE_PATTERN` 과 같은
 * 규칙이다. 그 파일을 byte 불변으로 두기 위해 export 대신 사본을 둔다
 * (C-08 · 재배포 표면 최소화).
 */
const REVOKE_ERROR_CODE_PATTERN = /^[a-z_]{1,32}$/;

/**
 * 운영자 설정 결함 — client 인증 실패(Client ID · Secret 불일치 등).
 * 재시도로 해소되지 않으므로 `provider_config` 로 분류한다 (D-12).
 */
const REVOKE_CONFIG_ERROR_CODES: readonly string[] = [
  "unauthorized_client",
  "invalid_client",
];

/**
 * `disconnectNaverProvider` 요청 — 필드 존재로 모양을 판별한다.
 *
 * - 1-tap 모양: `{accessToken}`
 * - 웹 모양: `{code, state}`
 *
 * 모든 필드는 신뢰할 수 없는 임의 JSON 이라 `unknown` 으로 받고 Step 2 에서
 * 좁힌다.
 */
type DisconnectNaverProviderRequest = {
  /** 1-tap 모양 — Naver SDK 가 준 access token. */
  accessToken?: unknown;
  /** 웹 모양 — Naver authorization code (1회용). */
  code?: unknown;
  /** 웹 모양 — authorize 요청에 실은 state. */
  state?: unknown;
};

/**
 * Step 2 가 좁힌 끊기 자격증명 — `kind` 로 모양을 구분한다.
 * - `app`: 1-tap access token (그대로 사용)
 * - `web`: authorization code · state (Step 3 에서 교환)
 */
type NaverDisconnectCredential =
  | {kind: "app"; accessToken: string}
  | {kind: "web"; code: string; state: string};

/** `disconnectNaverProvider` 응답 — 재로그인 custom token 과 발급 uid. */
type DisconnectNaverProviderResponse = {
  ok: true;
  /** caller uid 로 발급한 custom token — 탈퇴 진행 화면만 소비한다. */
  customToken: string;
  /** 발급 대상 uid (= `request.auth.uid`) — client 재대조용. */
  uid: string;
};

/**
 * revoke 응답 본문에서 `error` 필드를 읽는다.
 *
 * 성공은 「본문 없이 HTTP 200」 이다 (Naver 문서 6.2.4). 본문이 비어 있거나
 * JSON 이 아니거나 `error` 필드가 없으면 undefined 다. `error` 가 있으면
 * 화이트리스트 형식일 때만 원문, 아니면 `"other"`. 본문 읽기 자체가 실패하면
 * (본문 수신 중 timeout 등) `"body_unreadable"` — 성공으로 오판하지 않는다.
 * `error_description` 은 읽지 않는다.
 *
 * @param {Response} resp NAVER revoke 응답.
 * @return {Promise<string | undefined>} 로그 가능한 error 코드 또는 undefined.
 */
async function readRevokeErrorCode(
  resp: Response,
): Promise<string | undefined> {
  let text: string;
  try {
    text = await resp.text();
  } catch {
    return "body_unreadable";
  }
  if (text.length === 0) return undefined;
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    return undefined;
  }
  if (typeof parsed !== "object" || parsed === null) return undefined;
  const error = (parsed as Record<string, unknown>).error;
  if (error === undefined) return undefined;
  return typeof error === "string" && REVOKE_ERROR_CODE_PATTERN.test(error) ?
    error :
    "other";
}

/**
 * NAVER Token Revocation 으로 access token 을 폐기한다 — NAVER 측 앱 연결
 * 끊기 (Phase 16.10 D-02).
 *
 * form body 4 필드(`client_id` · `client_secret` · `token` ·
 * `token_type_hint=access_token`)를 POST 한다. 매핑 (D-12):
 * - fetch reject (TimeoutError · network) → `unavailable`
 * - HTTP 2xx + 본문 `error` 없음 → 성공
 * - 본문 `error` 가 `unauthorized_client` · `invalid_client` →
 *   `failed-precondition` (reason `provider_config`)
 * - HTTP 401/403 → `unauthenticated` (`errorInvalidCredentials`)
 * - 그 밖 (200 + 다른 `error` 포함) → `unavailable` — 200 성공 오판 방지
 *
 * **PII 금지:** 로그 payload 는 `{event, uid, path, status?, code}` 뿐 —
 * access token · client secret · 응답 `error_description` 은 싣지 않는다.
 *
 * @param {{accessToken: string, uid: string, path: NaverSignInPath}} args
 *     폐기할 access token · 로그 축 uid · 경로.
 * @return {Promise<void>} 폐기 성공 시 resolve.
 * @throws {HttpsError} 위 매핑 표에 따른 표준 에러.
 */
async function revokeNaverAccessToken(args: {
  accessToken: string;
  uid: string;
  path: NaverSignInPath;
}): Promise<void> {
  const {accessToken, uid, path} = args;
  let resp: Response;
  try {
    resp = await fetch(NAVER_REVOKE_URL, {
      method: "POST",
      headers: {"Content-Type": "application/x-www-form-urlencoded"},
      body: new URLSearchParams({
        client_id: NAVER_CLIENT_ID.value(),
        client_secret: NAVER_CLIENT_SECRET.value(),
        token: accessToken,
        token_type_hint: "access_token",
      }),
      signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
    });
  } catch (err: unknown) {
    // err.message 미로깅 — err.name 만 fingerprint.
    logger.error(
      {
        event: "disconnect_naver_revoke_failed",
        uid,
        path,
        code: err instanceof Error ? err.name : "unknown",
      },
      "Naver token revoke request failed",
    );
    throw idpUnavailable();
  }

  const errorCode = await readRevokeErrorCode(resp);
  if (resp.ok && errorCode === undefined) return;

  logger.error(
    {
      event: "disconnect_naver_revoke_failed",
      uid,
      path,
      status: resp.status,
      code: errorCode ?? "none",
    },
    "Naver token revoke rejected",
  );
  if (
    errorCode !== undefined &&
    REVOKE_CONFIG_ERROR_CODES.includes(errorCode)
  ) {
    throw providerConfigError();
  }
  if (resp.status === 401 || resp.status === 403) {
    throw idpCredentialRejected();
  }
  throw idpUnavailable();
}

/**
 * Naver 앱 연결 끊기 callable (Phase 16.10 SOCL-13 · SOCL-15).
 *
 * 호출 조건: App Check 필수 · 로그인 필수 · 익명 caller 거부.
 *
 * 흐름:
 *   Step 0: `request.auth` 검증.
 *   Step 1: 익명 caller 거부 (`failed-precondition` · reason
 *           `anonymous_caller`).
 *   Step 2: 입력 모양 판별 · 위생 — `accessToken` 있음 = 1-tap, `code`/
 *           `state` 있음 = 웹. 둘 다이거나 둘 다 없으면 `invalid-argument`.
 *           CRLF/NUL 은 `NAVER_CONTROL_CHARS`, state 상한은
 *           `MAX_NONCE_ARG_LENGTH`. Step 0~2 는 모든 외부 호출 앞이다 —
 *           거부되는 caller 가 1회용 code 를 소비하지 않는다.
 *   Step 3: 웹 모양만 — `exchangeNaverAuthCode` 로 code → access token.
 *   Step 4: `fetchNaverProfile` — `/v1/nid/me` 검증 후 `id` 만 소비.
 *   Step 5: `identity_index/naver:{id}` 가 caller 소유인지 대조 — 아니면
 *           `permission-denied` · reason `caller_identity_mismatch` (revoke ·
 *           토큰 발급 0 · D-08).
 *   Step 6: NAVER Token Revocation.
 *   Step 7: caller uid 로 재로그인 custom token 발급 → 성공 로그 →
 *           `{ok: true, customToken, uid}`.
 *
 * **PII 금지 (C-03 · C-06):** logger payload 는 `{event, uid, path}` 와
 * 실패 시 `status | code` 뿐이다. access token · code · state · client
 * secret · Naver id · 프로필 · custom token 은 로그 · HttpsError details 에
 * 싣지 않는다. access token 은 이 호출의 지역 변수로만 존재하고, custom
 * token 은 응답에만 싣는다.
 *
 * @param {{data: DisconnectNaverProviderRequest, auth?: {uid: string}}}
 *     request onCall request — auth 는 Step 0 에서 검증.
 * @return {Promise<DisconnectNaverProviderResponse>}
 *     `{ok: true, customToken, uid}`.
 */
export const disconnectNaverProvider = onCall<DisconnectNaverProviderRequest>(
  {
    enforceAppCheck: true,
    secrets: [NAVER_CLIENT_SECRET, NAVER_CLIENT_ID],
  },
  async (request): Promise<DisconnectNaverProviderResponse> => {
    // Step 0: auth.
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "errorUnauthenticated");
    }
    const uid = request.auth.uid;

    // Step 1: 익명 caller 거부 — 익명 계정에는 끊을 연결이 없다.
    if (isAnonymousCaller(request.auth)) {
      throw anonymousDisconnectNotAllowed();
    }

    // Step 2: 모양 판별 — 필드 존재로 정확히 한 모양만 허용한다.
    const hasApp = request.data?.accessToken !== undefined;
    const hasWeb =
      request.data?.code !== undefined || request.data?.state !== undefined;
    if (hasApp === hasWeb) {
      throw invalidArgument();
    }
    let credential: NaverDisconnectCredential;
    if (hasApp) {
      const accessToken = requireStringArg(request.data?.accessToken);
      // Authorization 헤더 injection 방어 — CRLF / NUL 거부.
      if (NAVER_CONTROL_CHARS.test(accessToken)) {
        throw invalidArgument();
      }
      credential = {kind: "app", accessToken};
    } else {
      const code = requireStringArg(request.data?.code);
      const state = requireStringArg(request.data?.state, MAX_NONCE_ARG_LENGTH);
      if (NAVER_CONTROL_CHARS.test(code) || NAVER_CONTROL_CHARS.test(state)) {
        throw invalidArgument();
      }
      credential = {kind: "web", code, state};
    }
    // helper 로그의 경로 축 — 로그인 · 연결 경로와 구분된다.
    const path: NaverSignInPath = hasApp ? "disconnect_app" : "disconnect_web";

    // Step 3: 웹 모양만 code 교환 — access token 은 지역 변수로만 (C-03).
    const accessToken = credential.kind === "web" ?
      (await exchangeNaverAuthCode({
        code: credential.code,
        state: credential.state,
      })).accessToken :
      credential.accessToken;

    // Step 4: Naver 검증 — `id` 만 소비 (email · nickname 미독 · C-06).
    const {id: naverUserId} = await fetchNaverProfile({accessToken, path});

    // Step 5: 소유 대조 — revoke 보다 앞 (D-08).
    await assertIdentityOwnedByCaller({
      db: getFirestore(),
      provider: "naver",
      providerUserId: naverUserId,
      callerUid: uid,
    });

    // Step 6: NAVER 측 앱 연결 끊기.
    await revokeNaverAccessToken({accessToken, uid, path});

    // Step 7: 재로그인 custom token — 응답에만 싣는다 (D-07).
    const customToken = await mintReloginToken({uid, provider: "naver"});
    logger.info(
      {event: "disconnect_naver_succeeded", uid, path},
      "Naver disconnected",
    );
    return {ok: true, customToken, uid};
  },
);
