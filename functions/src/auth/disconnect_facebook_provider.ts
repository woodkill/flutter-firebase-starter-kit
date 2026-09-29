// Phase 16.10 SOCL-13 · SOCL-15 — Facebook 앱 권한 삭제 callable (서버 단독).
//
// 탈퇴 진행 화면의 Facebook 자동 행 · 해제 다이얼로그가 호출한다. 사용자 재로그인
// 없이 서버가 app access token 으로 Facebook 측 앱 권한을 삭제한다.
//
// 결정 (16.10-CONTEXT · RESEARCH):
// - D-03: app access token(`<앱 ID>|<앱 시크릿>`)으로 끊는다 — 재로그인 0.
// - 전제 ①(RESEARCH Q2 · PASS): Admin `getUser(uid).providerData` 의
//   `facebook.com` 항목 `uid` = Graph `{user-id}` 로 쓸 수 있는 app-scoped
//   ID(asid)다. 입력으로 받지 않는다(IDOR 표면 0). asid 는 로그 · 응답 ·
//   HttpsError details 어디에도 싣지 않는다.
// - **iOS Limited Login 주의 (RESEARCH Q2 ② 정정 · Pitfall 3):** Limited
//   Login 토큰은 Graph API 를 쓸 수 없으므로 「재로그인 user token 으로
//   전환」 하는 대체 경로는 없다. 이 callable 이 실패하면 진행 화면 행 실패 →
//   건너뛰기(D-12)로 흡수하고, 실제 동작은 iOS batch UAT(D-17)가 실측한다.
// - **A2 재진입 (Pitfall 7 · plan 10 실측):** 이미 권한을 지운 사용자를 다시
//   지워도 Graph 는 성공 본문(`{success: true}`)을 돌려준다 — plan 10 Android
//   UAT 재진입 관측(`UAT1610_FB_REDELETE: success`)을 Jest F15 로 잠갔다.
//   그래서 「이미 끊긴 사용자」 전용 오류 코드 매핑은 없다. 오류 응답 경로
//   (iOS Limited Login 등)는 미실측이라 후보 코드를 추측해 성공으로 매핑하지
//   않는다 — 성공 · 명시 실패(`190` · rate limit · 네트워크) 외에는 모두
//   `unavailable` 이다.
// - T-16.10-07: app token 을 URL 쿼리 문자열에 싣지 않는다 — URL 은 요청
//   로그 · 프록시 · 에러 보고에 남는다. `Authorization: Bearer` 헤더로만
//   보낸다 (plan 01 Wave 0 `A3_GRAPH_BEARER: accepted` 실측).
// - Graph 경로는 버전 없는 기본 경로를 쓴다 — 버전 문자열 추측 0, 앱 기본
//   버전을 따른다.
//
// provider 제거 = 이 파일 + `index.ts` export 1줄 + 시크릿 선언 파일
// (`shared/facebook_secrets.ts`) + 배포 정리(`functions:delete` · secret
// 삭제). 다른 파일은 편집하지 않는다 (C-08).
//
// **IN-04**: 아래 `HttpsError` 의 message 는 ARB 키가 아니라 taxonomy
// 토큰이다. client 는 `code` + `details.reason` 으로만 분기한다 —
// `shared/custom_token_errors.ts` 헤더 참조.
import {getAuth} from "firebase-admin/auth";
import {onCall, HttpsError} from "firebase-functions/https";
import * as logger from "firebase-functions/logger";

import {isAnonymousCaller} from "../shared/caller_auth";
import {
  anonymousDisconnectNotAllowed,
  idpUnavailable,
  providerConfigError,
  serverFailure,
} from "../shared/custom_token_errors";
import {
  FACEBOOK_APP_ID,
  FACEBOOK_APP_SECRET,
} from "../shared/facebook_secrets";
import {fingerprintError} from "./identity_index";

/** Graph API 기본 경로 (버전 없음 — 앱 기본 버전). */
const GRAPH_BASE_URL = "https://graph.facebook.com";

/** 외부 호출 timeout — 헤더 + 본문 전체 5s (naver_token_exchange 관례). */
const FETCH_TIMEOUT_MS = 5000;

/**
 * app-scoped ID 형식 — 숫자 문자열.
 * [ASSUMED — Android Classic 로그인 기준 · iOS Limited Login 형식은 plan 10 ·
 * iOS batch 실측].
 */
const FACEBOOK_ASID_PATTERN = /^[0-9]{1,32}$/;

/** Graph `OAuthException` — app token 무효 · 운영자 설정 결함. */
const GRAPH_TOKEN_INVALID_CODE = 190;

/** Graph 호출 한도 초과 코드 — `resource-exhausted`. */
const GRAPH_RATE_LIMIT_CODES: readonly number[] = [4, 17, 613];

type DisconnectFacebookProviderResponse = {
  ok: true;
  /** 이번 호출에서 권한을 삭제한 Facebook 신원 수. */
  disconnectedCount: number;
};

/** Graph 오류 본문에서 읽은 정수 코드 (없으면 undefined). */
type GraphErrorCodes = {
  code?: number;
  subcode?: number;
};

/**
 * 값이 안전 정수면 그대로, 아니면 undefined 를 돌려준다.
 *
 * @param {unknown} value 알 수 없는 값.
 * @return {number | undefined} 안전 정수 또는 undefined.
 */
function asSafeInteger(value: unknown): number | undefined {
  return typeof value === "number" && Number.isSafeInteger(value) ?
    value :
    undefined;
}

/**
 * Graph 오류 본문 `{error: {code, error_subcode, message}}` 에서 정수 코드만
 * 읽는다.
 *
 * `message` 는 읽지 않는다 (로그 · 응답 PII 차단). 본문이 JSON 이 아니면
 * 빈 객체다.
 *
 * @param {Response} resp Graph 응답 (`!resp.ok`).
 * @return {Promise<GraphErrorCodes>} `code` · `subcode` (정수만).
 */
async function readGraphError(resp: Response): Promise<GraphErrorCodes> {
  let parsed: unknown;
  try {
    parsed = await resp.json();
  } catch {
    return {};
  }
  if (typeof parsed !== "object" || parsed === null) return {};
  const error = (parsed as Record<string, unknown>).error;
  if (typeof error !== "object" || error === null) return {};
  const fields = error as Record<string, unknown>;
  return {
    code: asSafeInteger(fields.code),
    subcode: asSafeInteger(fields.error_subcode),
  };
}

/**
 * Graph `DELETE /{asid}/permissions` 성공 본문인지 판정한다.
 *
 * 문서 표기가 둘이라(`true` · `{"success": true}`) 둘 다 수용한다.
 *
 * @param {unknown} body `resp.json()` 결과.
 * @return {boolean} 성공 본문이면 true.
 */
function isGraphDeleteSuccess(body: unknown): boolean {
  if (body === true) return true;
  if (typeof body !== "object" || body === null) return false;
  return (body as Record<string, unknown>).success === true;
}

/**
 * Facebook 앱 권한 삭제 callable (Phase 16.10 SOCL-13 · SOCL-15).
 *
 * 호출 조건: App Check 필수 · 로그인 필수 · 익명 caller 거부. 입력은 받지
 * 않는다 — 끊을 대상은 서버가 `request.auth.uid` 의 `providerData` 에서만
 * 찾는다.
 *
 * 흐름:
 *   Step 0: `request.auth` 검증.
 *   Step 1: 익명 caller 거부 (`failed-precondition` · reason
 *           `anonymous_caller`) — Admin · Graph 호출 0.
 *   Step 2: Admin `getUser(uid).providerData` 에서 `facebook.com` asid 수집.
 *   Step 3: asid 마다 `DELETE /{asid}/permissions` (Bearer app token) —
 *           성공 본문이면 성공, `190` 은 `provider_config`, rate limit 은
 *           `resource-exhausted`, 그 밖 · 네트워크 · timeout 은
 *           `unavailable`.
 *   Step 4: 구조화 로그 + `{ok: true, disconnectedCount}` (0 이면 외부 호출 0).
 *
 * **PII 금지 (C-04 · C-06):** logger payload 는
 * `{event, uid, disconnectedCount | status | code | subcode}` 뿐이다. asid ·
 * 앱 시크릿 · Graph 응답 `message` 는 어디에도 싣지 않는다.
 *
 * @param {{auth?: {uid: string}}} request onCall request — auth 는 Step 0
 *     에서 검증.
 * @return {Promise<DisconnectFacebookProviderResponse>}
 *     `{ok: true, disconnectedCount}`.
 */
export const disconnectFacebookProvider = onCall(
  {
    enforceAppCheck: true,
    secrets: [FACEBOOK_APP_ID, FACEBOOK_APP_SECRET],
  },
  async (request): Promise<DisconnectFacebookProviderResponse> => {
    // Step 0: auth.
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "errorUnauthenticated");
    }
    const uid = request.auth.uid;

    // Step 1: 익명 caller 거부 — 익명 계정에는 끊을 연결이 없다.
    if (isAnonymousCaller(request.auth)) {
      throw anonymousDisconnectNotAllowed();
    }

    // Step 2: caller 의 Facebook asid — Admin 원장에서만 도출.
    let asids: string[];
    try {
      const userRecord = await getAuth().getUser(uid);
      asids = userRecord.providerData
        .filter((p) => p.providerId === "facebook.com")
        .map((p) => p.uid);
    } catch (err: unknown) {
      logger.error(
        {
          event: "disconnect_facebook_precheck_failed",
          uid,
          code: fingerprintError(err),
        },
        "getUser threw",
      );
      throw serverFailure();
    }

    // Step 3: asid 마다 앱 권한 삭제. app token 은 지역 상수로만 둔다.
    const appToken =
      `${FACEBOOK_APP_ID.value()}|${FACEBOOK_APP_SECRET.value()}`;
    let disconnectedCount = 0;
    for (const asid of asids) {
      // 원장 데이터 결함 — 값은 로그에 싣지 않는다.
      if (!FACEBOOK_ASID_PATTERN.test(asid)) {
        logger.error(
          {event: "disconnect_facebook_target_invalid", uid},
          "providerData uid is not a Facebook app-scoped id",
        );
        throw serverFailure();
      }

      let resp: Response;
      try {
        resp = await fetch(`${GRAPH_BASE_URL}/${asid}/permissions`, {
          method: "DELETE",
          headers: {Authorization: `Bearer ${appToken}`},
          signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
        });
      } catch (err: unknown) {
        // err.message 미로깅 — err.name 만 fingerprint.
        logger.error(
          {
            event: "disconnect_facebook_delete_failed",
            uid,
            code: err instanceof Error ? err.name : "unknown",
          },
          "Graph permissions delete request failed",
        );
        throw idpUnavailable();
      }

      if (resp.ok) {
        let body: unknown;
        try {
          body = await resp.json();
        } catch {
          body = undefined;
        }
        if (isGraphDeleteSuccess(body)) {
          disconnectedCount += 1;
          continue;
        }
        logger.error(
          {
            event: "disconnect_facebook_delete_failed",
            uid,
            status: resp.status,
            code: "unexpected_body",
          },
          "Graph permissions delete returned unexpected body",
        );
        throw idpUnavailable();
      }

      const {code, subcode} = await readGraphError(resp);
      logger.error(
        {
          event: "disconnect_facebook_delete_failed",
          uid,
          status: resp.status,
          code: code ?? "other",
          subcode: subcode ?? "other",
        },
        "Graph permissions delete rejected",
      );
      if (code === GRAPH_TOKEN_INVALID_CODE) {
        throw providerConfigError();
      }
      if (code !== undefined && GRAPH_RATE_LIMIT_CODES.includes(code)) {
        throw new HttpsError("resource-exhausted", "errorTooManyRequests");
      }
      // A2 — 재삭제는 성공 본문이라(plan 10 실측 · F15) 여기 오지 않는다.
      // 미실측 오류 응답(iOS Limited Login 등)은 보수적으로 unavailable.
      throw idpUnavailable();
    }

    // Step 4: 성공.
    logger.info(
      {event: "disconnect_facebook_succeeded", uid, disconnectedCount},
      "Facebook permissions deleted",
    );
    return {ok: true, disconnectedCount};
  },
);
