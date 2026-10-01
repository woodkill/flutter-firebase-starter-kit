// Phase 17 — see ROADMAP.md (D-26 · D-13) · native 경로 email mirror ·
// 입력 0 · 서버 검증 토큰만.
//
// 계정 대표 이메일(Auth top-level email · 가입 수단 기준) 1개를 Firestore
// `users/{uid}` 의 서버 전용 필드 `email` · `emailVerified` 로 mirror 한다.
// 클라이언트는 `authUserObserver` 의 정식 세션 시작마다 이 callable 을
// fire-and-forget 으로 1회 부른다 (RESEARCH R-03 (b)).
//
// - 값 원천은 `request.auth.token`(firebase-functions 가 검증한 ID token)
//   뿐이다. callable 요청 본문은 읽지 않는다 — 클라이언트가 이메일을 실어
//   보내도 저장값은 토큰 값이다 (T-17-34).
// - 이메일이 없는 사용자는 `email: null` 을 그대로 쓴다 (빈 문자열 sentinel 0
//   — CONTEXT D-26 2026-09-29 정정).
// - 두 키는 rules 의 클라이언트 화이트리스트 밖이다 (D-13 · plan 02).
// - Custom Token 경로는 `identity_index.ts` 의 서버 트랜잭션이 같은 두 키를
//   add-only 로 쓴다. 이 callable 은 CT 사용자에게도 멱등(같은 값 재기록)이다.
//
// **IN-04**: 아래 `HttpsError` 들의 message 는 ARB 키가 아니라 taxonomy
// 토큰이다. client 는 `code` 로만 분기하며 서버 message 를 렌더하지 않는다.
import {getFirestore} from "firebase-admin/firestore";
import {onCall, HttpsError} from "firebase-functions/https";
import * as logger from "firebase-functions/logger";

import {isAnonymousCaller} from "../shared/caller_auth";
import {ANONYMOUS_CALLER_REASON} from "../shared/custom_token_errors";
import {fingerprintError} from "./identity_index";

type MirrorAccountEmailResponse = {
  ok: true;
};

/**
 * 계정 대표 이메일 Firestore mirror callable (Phase 17 D-26).
 *
 * 흐름:
 *   Step 0: `request.auth` 검증 — 미인증 `unauthenticated`, 익명
 *           `failed-precondition` + `{reason: "anonymous_caller"}`.
 *   Step 1: 토큰 claim `email`(문자열이 아니면 null) ·
 *           `email_verified === true` 를 `users/{uid}` 에 set-merge.
 *
 * **PII 금지 (T-17-35):** logger payload 는 `{event, uid, hasEmail}` /
 * `{event, uid, code}` 뿐이다. 이메일 본문 · err.message 를 싣지 않는다.
 *
 * @param {{auth?: {uid: string, token: Record<string, unknown>}}} request
 *     onCall request — 요청 본문은 읽지 않는다.
 * @return {Promise<MirrorAccountEmailResponse>} `{ok: true}`.
 */
export const mirrorAccountEmail = onCall({enforceAppCheck: true},
  async (request): Promise<MirrorAccountEmailResponse> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "errorUnauthenticated");
    }
    if (isAnonymousCaller(request.auth)) {
      throw new HttpsError(
        "failed-precondition",
        "errorAnonymousCallerNotAllowed",
        {reason: ANONYMOUS_CALLER_REASON},
      );
    }
    const uid = request.auth.uid;
    const tokenEmail: unknown = request.auth.token.email;
    const email = typeof tokenEmail === "string" && tokenEmail.length > 0 ?
      tokenEmail :
      null;
    const emailVerified = request.auth.token.email_verified === true;

    try {
      await getFirestore()
        .collection("users")
        .doc(uid)
        .set({email, emailVerified}, {merge: true});
    } catch (err: unknown) {
      const code = fingerprintError(err);
      logger.error(
        {event: "mirror_account_email_failed", uid, code},
        "mirrorAccountEmail failed",
      );
      throw new HttpsError("internal", "errorUnknown");
    }

    logger.info(
      {event: "mirror_account_email_done", uid, hasEmail: email !== null},
      "mirrorAccountEmail done",
    );
    return {ok: true};
  },
);
