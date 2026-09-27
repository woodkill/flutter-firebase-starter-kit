// Phase 16.9 SOCL-12 — Naver 신원을 기존 Firebase 계정에 연결하는 callable.
//
// D-01: Naver 는 OIDC ID token 이 아니라 access token 을 `/v1/nid/me` 로
// 검증하므로 `linkCustomTokenProvider` 에 분기를 넣지 않고 별도 callable 로
// 둔다 — Naver 제거 = 본 파일 삭제 + index export 1줄 + 배포 정리.
// 공유하는 것:
// - 검증 helper `fetchNaverProfile` (`naver_profile_to_custom_token.ts`)
// - 연결 transaction `linkCustomTokenIdentity` (`link_identity_transaction.ts`)
// - 재인증 신선도 `assertFreshAuth` (`shared/reauth.ts`)
// - code 교환 `exchangeNaverAuthCode` (`naver_token_exchange.ts` — 웹 모양)
//
// **Mock 한계:** Jest 는 NAVER 서버 · App Check · 실 Firestore 를 흉내낼
// 뿐이다 — 실 단말 UAT 가 ground truth.
//
// **IN-04**: 아래 `HttpsError` 들의 message 는 ARB 키가 아니라 taxonomy
// 토큰이다. client 는 `code` + `details.reason` 으로만 분기하며 서버 message
// 를 렌더하지 않는다 (재인증 필요 = `reason: reauthentication_required` —
// 16.9 review WR-01).
// 계약 전문은 `shared/custom_token_errors.ts` 헤더 참조.
import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
import {onCall, HttpsError} from "firebase-functions/https";
import * as logger from "firebase-functions/logger";

import {
  invalidArgument,
  reauthenticationRequired,
} from "../shared/custom_token_errors";
import {NAVER_CLIENT_ID, NAVER_CLIENT_SECRET} from "../shared/naver_secrets";
import {assertFreshAuth} from "../shared/reauth";
import {
  MAX_NONCE_ARG_LENGTH,
  requireStringArg,
} from "../shared/require_string_arg";
import {fingerprintError} from "./identity_index";
import {linkCustomTokenIdentity} from "./link_identity_transaction";
import {fetchNaverProfile} from "./naver_profile_to_custom_token";
import type {NaverSignInPath} from "./naver_profile_to_custom_token";
import {
  exchangeNaverAuthCode,
  NAVER_CONTROL_CHARS,
} from "./naver_token_exchange";

/**
 * `linkNaverProvider` 요청 — 필드 존재로 모양을 판별한다.
 *
 * - 1-tap 모양: `{idToken, accessToken}`
 * - 웹 모양: `{idToken, code, state}`
 *
 * 모든 필드는 신뢰할 수 없는 임의 JSON 이라 `unknown` 으로 받고 Step 0 에서
 * 좁힌다.
 */
type LinkNaverProviderRequest = {
  /** 현재 Firebase user 의 fresh ID Token (재인증 검증). */
  idToken?: unknown;
  /** 1-tap 모양 — Naver SDK 가 준 access token. */
  accessToken?: unknown;
  /** 웹 모양 — Naver authorization code (1회용). */
  code?: unknown;
  /** 웹 모양 — authorize 요청에 실은 state. */
  state?: unknown;
};

/**
 * Step 0 이 좁힌 연결 자격증명 — `kind` 로 모양을 구분한다.
 * - `app`: 1-tap access token (그대로 검증)
 * - `web`: authorization code · state (Step 3 에서 교환)
 */
type NaverLinkCredential =
  | {kind: "app"; accessToken: string}
  | {kind: "web"; code: string; state: string};

/** `linkNaverProvider` 응답 — link callable 과 같은 모양. */
type LinkNaverProviderResponse = {
  ok: true;
};

/**
 * Naver 신원을 호출자의 기존 계정에 연결한다 (Phase 16.9 D-01).
 *
 * 흐름:
 *   Step 0: request.auth + 입력 모양 판별 · 위생 검증 (Admin Auth 호출 전).
 *           `accessToken` 있음 = 1-tap 모양, `code`/`state` 있음 = 웹 모양 —
 *           둘 다이거나 둘 다 없으면 `invalid-argument`. CRLF/NUL 은
 *           `NAVER_CONTROL_CHARS`, state 상한은 `MAX_NONCE_ARG_LENGTH`.
 *   Step 1: 재인증 ID Token 검증 (`verifyIdToken(checkRevoked)` + uid 일치 +
 *           `assertFreshAuth` 300s).
 *   Step 2: 익명 caller 거부 (`failed-precondition`).
 *   Step 3: 웹 모양만 — `exchangeNaverAuthCode` 로 code → access token.
 *           Step 1~2 뒤에 둔다 — stale 세션이 1회용 code 를 소비하지 않는다.
 *           access token 은 이 호출의 지역 변수로만 존재한다 (C-03).
 *   Step 4: `fetchNaverProfile` — `/v1/nid/me` 검증 후 `id` 만 소비.
 *   Step 5: `linkCustomTokenIdentity` — identity_index 생성 + linkedProviders
 *           갱신 (공용 transaction). 다른 Naver 신원이 이미 이 계정에 있으면
 *           `already-exists` + reason `provider_already_linked` (16.9 review
 *           IN-03 — provider 당 신원 1개).
 *   Step 6: 성공 로그 + `{ok: true}`.
 *
 * **PII 금지:** logger payload 는 `{event, uid, path, code}` 만. idToken ·
 * access token · code · state · client secret · Naver 응답 본문(email ·
 * nickname 등)은 로그 · 응답에 싣지 않는다. 프로필은 `id` 만 읽고 user record · 프로필 필드는 쓰지 않는다
 * (C-06).
 *
 * @param {{data: LinkNaverProviderRequest, auth?: {uid: string}}} request
 *     onCall request — data 의무, auth optional (Step 0 에서 검증).
 * @return {Promise<LinkNaverProviderResponse>} `{ok: true}` on success.
 */
export const linkNaverProvider = onCall<LinkNaverProviderRequest>(
  {
    enforceAppCheck: true,
    secrets: [NAVER_CLIENT_SECRET, NAVER_CLIENT_ID],
  },
  async (request): Promise<LinkNaverProviderResponse> => {
    // Step 0: auth + input validation.
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "errorUnauthenticated");
    }
    const callerUid = request.auth.uid;
    const idToken = requireStringArg(request.data?.idToken);
    // 모양 판별 — 필드 존재로 정확히 한 모양만 허용한다.
    const hasApp = request.data?.accessToken !== undefined;
    const hasWeb =
      request.data?.code !== undefined || request.data?.state !== undefined;
    if (hasApp === hasWeb) {
      throw invalidArgument();
    }
    let credential: NaverLinkCredential;
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
    // helper 로그의 경로 축 — 로그인(`app` · `web`)과 구분된다 (IN-02).
    const path: NaverSignInPath = hasApp ? "link_app" : "link_web";

    // Step 1: 재인증 ID Token 검증 (link callable verbatim mirror).
    let decoded;
    try {
      decoded = await getAuth().verifyIdToken(idToken, true /* checkRevoked */);
    } catch (err: unknown) {
      // PII 금지 — fingerprintError helper 만 사용 (err.message 본문 노출 0).
      const errCode = fingerprintError(err);
      logger.warn(
        {event: "link_naver_id_token_verify_failed", code: errCode},
        "verifyIdToken threw",
      );
      // details.reason 으로 재로그인 분기를 표시한다 (16.9 review WR-01) —
      // 같은 code 의 IdP 거부 · App Check 차단은 reason 이 없다.
      throw reauthenticationRequired();
    }
    if (decoded.uid !== callerUid) {
      throw new HttpsError("permission-denied", "errorUnauthenticated");
    }
    assertFreshAuth(decoded.auth_time);

    // Step 2: anonymous caller 거부.
    if (decoded.firebase?.sign_in_provider === "anonymous") {
      throw new HttpsError(
        "failed-precondition",
        "errorAnonymousLinkNotAllowed",
      );
    }

    // Step 3: 웹 모양만 code 교환 — caller 검사(Step 1~2) 뒤라 거부된
    // 세션은 1회용 code 를 소비하지 않는다 (D-01 흐름 1).
    // access token 은 이 호출의 지역 변수로만 존재한다 (C-03).
    const accessToken = credential.kind === "web" ?
      (await exchangeNaverAuthCode({
        code: credential.code,
        state: credential.state,
      })).accessToken :
      credential.accessToken;

    // Step 4: Naver 검증 — `id` 만 소비 (email · nickname 미독 · C-06).
    const {id: naverUserId} = await fetchNaverProfile({accessToken, path});

    // Step 5: 공용 연결 transaction.
    await linkCustomTokenIdentity({
      db: getFirestore(),
      callerUid,
      provider: "naver",
      providerUserId: naverUserId,
    });

    // Step 6: structured log + return. PII 금지 — {event, uid, path} 만.
    logger.info(
      {event: "link_naver_provider_succeeded", uid: callerUid, path},
      "linked",
    );
    return {ok: true};
  },
);
