// Phase 16.10 SOCL-13 · SOCL-15 — Kakao 앱 연결 끊기 callable (서버 단독).
//
// 탈퇴 진행 화면의 Kakao 자동 행 · 해제 다이얼로그가 호출한다. 사용자 재로그인
// 없이 서버가 어드민 키로 Kakao 측 앱 연결을 끊는다.
//
// 결정 (16.10-CONTEXT):
// - D-02: Kakao 는 서버가 어드민 키 + `identity_index` 회원번호로 끊는다.
// - D-13: 탈퇴 함수(`deleteUserAccount`)에는 provider 호출 · 시크릿을 넣지
//   않는다. 진행 화면 행이 이 callable 을 따로 부르고, 계정 삭제는 모든 행이
//   끝난 뒤 한 번만 한다. 해제 callable(`unlinkCustomTokenProvider`)에도 끊기를
//   넣지 않는다 — client 가 「끊기 성공 → 기존 해제」 순서로 조합한다.
// - C-04: `target_id` = `identity_index` 에 이미 저장된 회원번호다. 입력으로
//   받지 않는다(IDOR 표면 0). 회원번호는 파기 대상 개인정보라 로그 · 응답 ·
//   HttpsError details 어디에도 싣지 않는다. Long 정밀도 손실을 막기 위해
//   숫자 형식만 검증하고 **문자열 그대로** form 값으로 보낸다.
// - D-14: 이미 끊긴 사용자(`-101`)와 끊을 신원 없음(0 건)은 성공이다 — 재진입
//   재호출이 멱등하게 끝난다.
//
// provider 제거 = 이 파일 + `index.ts` export 1줄 + 시크릿 선언 파일
// (`shared/kakao_admin_secret.ts`) + 배포 정리(`functions:delete` · secret
// 삭제). 다른 파일은 편집하지 않는다 (C-08).
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
  idpUnavailable,
  providerConfigError,
  serverFailure,
} from "../shared/custom_token_errors";
import {KAKAO_ADMIN_KEY} from "../shared/kakao_admin_secret";
import {fingerprintError} from "./identity_index";
import {readStringField} from "./identity_ownership";

/** Kakao 연결 끊기 REST 엔드포인트 (어드민 키 방식). */
const KAKAO_UNLINK_URL = "https://kapi.kakao.com/v1/user/unlink";

/** 외부 호출 timeout — 헤더 + 본문 전체 5s (naver_token_exchange 관례). */
const FETCH_TIMEOUT_MS = 5000;

/** Kakao 회원번호 형식 — 숫자 문자열 (Long 범위 · 문자열 그대로 전송). */
const KAKAO_USER_ID_PATTERN = /^[0-9]{1,20}$/;

/** 「해당 앱에 연결되지 않은 사용자」 — 이미 끊김 · 멱등 성공 (D-14). */
const KAKAO_ALREADY_UNLINKED_CODE = -101;

/** 사용량 제한 초과 — `resource-exhausted`. */
const KAKAO_RATE_LIMIT_CODE = -10;

/**
 * 운영자 설정 결함 — 어드민 키 무효(`-401`) · 앱 설정 미허용(`-3`).
 * 재시도로 해소되지 않으므로 `provider_config` 로 분류한다.
 */
const KAKAO_CONFIG_ERROR_CODES: readonly number[] = [-401, -3];

type DisconnectKakaoProviderResponse = {
  ok: true;
  /** 이번 호출에서 끊었거나 이미 끊겨 있던 Kakao 신원 수. */
  disconnectedCount: number;
};

/**
 * Kakao 오류 응답 본문 `{code, msg}` 에서 정수 `code` 만 읽는다.
 *
 * `msg` 는 읽지 않는다 (로그 · 응답 PII 차단). 본문이 JSON 이 아니거나
 * `code` 가 안전 정수가 아니면 undefined 다.
 *
 * @param {Response} resp Kakao 응답 (`!resp.ok`).
 * @return {Promise<number | undefined>} Kakao 오류 코드 또는 undefined.
 */
async function readKakaoErrorCode(resp: Response): Promise<number | undefined> {
  let parsed: unknown;
  try {
    parsed = await resp.json();
  } catch {
    return undefined;
  }
  if (typeof parsed !== "object" || parsed === null) return undefined;
  const code = (parsed as Record<string, unknown>).code;
  return typeof code === "number" && Number.isSafeInteger(code) ?
    code :
    undefined;
}

/**
 * Kakao 앱 연결 끊기 callable (Phase 16.10 SOCL-13 · SOCL-15).
 *
 * 호출 조건: App Check 필수 · 로그인 필수 · 익명 caller 거부. 입력은 받지
 * 않는다 — 끊을 대상은 서버가 `request.auth.uid` 로 원장에서만 찾는다.
 *
 * 흐름:
 *   Step 0: `request.auth` 검증.
 *   Step 1: 익명 caller 거부 (`failed-precondition` · reason
 *           `anonymous_caller`) — provider · Firestore 호출 0.
 *   Step 2: (tx 밖 read-only) `identity_index` 에서 caller 의 Kakao 신원을
 *           찾는다.
 *   Step 3: 신원마다 `POST /v1/user/unlink` — 200 · `-101` 은 성공,
 *           `-10` 은 `resource-exhausted`, `-401` · `-3` 은 `provider_config`,
 *           그 밖 · 네트워크 · timeout 은 `unavailable`.
 *   Step 4: 구조화 로그 + `{ok: true, disconnectedCount}` (0 이면 외부 호출 0).
 *
 * **PII 금지 (C-04 · C-06):** logger payload 는
 * `{event, uid, disconnectedCount | status | code}` 뿐이다. 회원번호 · 어드민
 * 키 · Kakao 응답 `msg` 는 어디에도 싣지 않는다.
 *
 * @param {{auth?: {uid: string}}} request onCall request — auth 는 Step 0
 *     에서 검증.
 * @return {Promise<DisconnectKakaoProviderResponse>}
 *     `{ok: true, disconnectedCount}`.
 */
export const disconnectKakaoProvider = onCall(
  {enforceAppCheck: true, secrets: [KAKAO_ADMIN_KEY]},
  async (request): Promise<DisconnectKakaoProviderResponse> => {
    // Step 0: auth.
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "errorUnauthenticated");
    }
    const uid = request.auth.uid;

    // Step 1: 익명 caller 거부 — 익명 계정에는 끊을 연결이 없다.
    if (isAnonymousCaller(request.auth)) {
      throw anonymousDisconnectNotAllowed();
    }

    // Step 2: (tx 밖 read-only) caller 의 Kakao 신원 — write 0.
    let providerUserIds: Array<string | undefined>;
    try {
      const snaps = await getFirestore()
        .collection("identity_index")
        .where("firebaseUid", "==", uid)
        .where("provider", "==", "kakao")
        .get();
      providerUserIds = snaps.docs.map((doc) =>
        readStringField(doc.data(), "providerUserId"),
      );
    } catch (err: unknown) {
      logger.error(
        {
          event: "disconnect_kakao_precheck_failed",
          uid,
          code: fingerprintError(err),
        },
        "identity_index query threw",
      );
      throw serverFailure();
    }

    // Step 3: 신원마다 연결 끊기.
    let disconnectedCount = 0;
    for (const targetId of providerUserIds) {
      // 원장 데이터 결함 — 값은 로그에 싣지 않는다.
      if (targetId === undefined || !KAKAO_USER_ID_PATTERN.test(targetId)) {
        logger.error(
          {event: "disconnect_kakao_target_invalid", uid},
          "identity_index providerUserId is not a Kakao user id",
        );
        throw serverFailure();
      }

      let resp: Response;
      try {
        resp = await fetch(KAKAO_UNLINK_URL, {
          method: "POST",
          headers: {
            "Authorization": `KakaoAK ${KAKAO_ADMIN_KEY.value()}`,
            "Content-Type": "application/x-www-form-urlencoded",
          },
          body: new URLSearchParams({
            target_id_type: "user_id",
            target_id: targetId,
          }),
          signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
        });
      } catch (err: unknown) {
        // err.message 미로깅 — err.name 만 fingerprint.
        logger.error(
          {
            event: "disconnect_kakao_unlink_failed",
            uid,
            code: err instanceof Error ? err.name : "unknown",
          },
          "Kakao unlink request failed",
        );
        throw idpUnavailable();
      }

      if (resp.ok) {
        disconnectedCount += 1;
        continue;
      }

      const code = await readKakaoErrorCode(resp);
      if (code === KAKAO_ALREADY_UNLINKED_CODE) {
        logger.info(
          {event: "disconnect_kakao_already_unlinked", uid},
          "Kakao user already unlinked",
        );
        disconnectedCount += 1;
        continue;
      }
      logger.error(
        {
          event: "disconnect_kakao_unlink_failed",
          uid,
          status: resp.status,
          code: code ?? "other",
        },
        "Kakao unlink rejected",
      );
      if (code === KAKAO_RATE_LIMIT_CODE) {
        throw new HttpsError("resource-exhausted", "errorTooManyRequests");
      }
      if (code !== undefined && KAKAO_CONFIG_ERROR_CODES.includes(code)) {
        throw providerConfigError();
      }
      throw idpUnavailable();
    }

    // Step 4: 성공.
    // 16.10 review IN-05: client 는 `linkedProviders` 에 kakao 가 있을 때만
    // 이 행을 부르므로 신원 0 건은 원장 불일치(`identity_index` 누락)다.
    // 결과는 그대로 성공(행 「해제됨」)이지만 운영자가 찾을 수 있게 warn 을
    // 남긴다 — payload 는 성공 event 와 같은 `{event, uid}` 형태.
    if (disconnectedCount === 0) {
      logger.warn(
        {event: "disconnect_kakao_no_identity", uid},
        "No Kakao identity in identity_index for caller",
      );
    }
    logger.info(
      {event: "disconnect_kakao_succeeded", uid, disconnectedCount},
      "Kakao disconnected",
    );
    return {ok: true, disconnectedCount};
  },
);
