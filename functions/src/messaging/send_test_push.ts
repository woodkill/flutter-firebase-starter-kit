// Phase 17 — see ROADMAP.md (D-05 · D-31 · D-34 · D-35)
//
// 「나에게 테스트 알림 보내기」 callable — Dev Tools 버튼(kDebugMode)이
// 부른다. 킷 사용자에게는 서버 발송 샘플(Admin Messaging · locale 그룹 ·
// 환경 스위치)이다.
//
// - 대상은 호출자 `request.auth.uid` 의 `users/{uid}/fcmTokens` 전체뿐이다
//   (D-34). callable 입력은 받지 않는다 — 다른 사용자 · 토픽 · 임의 토큰으로
//   보낼 경로가 없다.
// - 문구는 토큰 문서 `locale` 로 고른 서버 상수다 (D-31 · `test_push_copy.ts`).
// - 환경 스위치 `SEND_TEST_PUSH_ENABLED`(기본 false)가 켜진 환경에서만
//   발송한다 (D-35).
// - PII: 로그에 토큰 문자열 · 알림 본문을 싣지 않는다 (uid · 수 · 오류 code).
//
// **IN-04**: 아래 `HttpsError` 들의 message 는 ARB 키가 아니라 taxonomy
// 토큰이다. client 는 `code` + `details.reason` 으로만 분기한다.
import {getFirestore} from "firebase-admin/firestore";
import type {QueryDocumentSnapshot} from "firebase-admin/firestore";
import {getMessaging} from "firebase-admin/messaging";
import type {MulticastMessage} from "firebase-admin/messaging";
import {onCall, HttpsError} from "firebase-functions/https";
import type {CallableRequest} from "firebase-functions/https";
import * as logger from "firebase-functions/logger";
import {defineBoolean} from "firebase-functions/params";
import type {BooleanParam} from "firebase-functions/params";

import {fingerprintError} from "../auth/identity_index";
import {
  TEST_PUSH_COPY,
  TestPushLocale,
  resolveTestPushLocale,
} from "./test_push_copy";

type SendTestPushResponse = {
  /** FCM 이 수락한 기기 수 (`BatchResponse.successCount` 합). */
  sentCount: number;
};

/**
 * 운영 거부 시 `HttpsError.details.reason` 값 (D-35).
 *
 * 클라이언트 `TestPushClient` 가 이 reason 으로 「이 환경에서는 테스트 알림을
 * 보낼 수 없어요」 를 고른다. code 는 `failed-precondition` 이라
 * `unauthenticated` 기반 App Check 판정(D-43)과 겹치지 않는다.
 */
export const TEST_PUSH_DISABLED_REASON = "test_push_disabled";

/** `sendEachForMulticast` 1회의 토큰 상한 (Admin SDK 제약). */
const MAX_MULTICAST_TOKENS = 500;

/**
 * 환경 스위치 param 을 선언한다 (D-35 · 기본값 false).
 *
 * @return {BooleanParam} `SEND_TEST_PUSH_ENABLED` param.
 */
function declareSendTestPushEnabled(): BooleanParam {
  return defineBoolean("SEND_TEST_PUSH_ENABLED", {default: false});
}

let sendTestPushEnabledParam: BooleanParam | undefined;

/**
 * 테스트 발송 환경 스위치 `SEND_TEST_PUSH_ENABLED` 를 돌려준다 (D-35).
 *
 * 값은 handler 안에서만 `.value()` 로 읽는다(배포 시점 평가 금지). 켜는 법 =
 * `functions/.env.<projectId>` 에 `SEND_TEST_PUSH_ENABLED=true` 1줄 + 재배포
 * (`.env.*` 는 root `.gitignore` 대상 — 커밋하지 않는다). 그 줄이 없는
 * 환경(stg · prod)은 기본값 false 라 발송 없이 거부된다.
 *
 * **선언 시점 (plan 18 deviation):** 공식 예제처럼 모듈 스코프 상수로 두지
 * 않고 첫 호출 때 한 번 선언한다. `src/index.ts` 전체를 import 하는 기존 jest
 * suite 14개가 `firebase-functions/params` 를 `defineSecret` 만 있는 mock 으로
 * 바꿔 두어, 모듈 로드 시점 `defineBoolean` 호출이 그 suite 들을 import 단계에서
 * 깨뜨린다. 런타임 값 해석(`process.env` · `"true"` 일 때만 켜짐)은 같다.
 *
 * @return {BooleanParam} 선언된 param (같은 인스턴스를 재사용한다).
 */
export function sendTestPushEnabled(): BooleanParam {
  if (sendTestPushEnabledParam === undefined) {
    sendTestPushEnabledParam = declareSendTestPushEnabled();
  }
  return sendTestPushEnabledParam;
}

/**
 * 배열을 [size] 이하 청크로 나눈다.
 *
 * @param {Array<string>} items 나눌 항목.
 * @param {number} size 청크 최대 크기 (1 이상).
 * @return {Array<Array<string>>} 청크 목록 (입력이 비면 빈 배열).
 */
function chunk(items: string[], size: number): string[][] {
  const chunks: string[][] = [];
  for (let i = 0; i < items.length; i += size) {
    chunks.push(items.slice(i, i + size));
  }
  return chunks;
}

/**
 * 토큰 문서를 문구 locale 별 토큰 목록으로 묶는다 (D-31).
 *
 * 토큰 문자열은 문서 id 다(rules 가 `data.token == id` 를 강제).
 *
 * @param {Array<QueryDocumentSnapshot>} docs fcmTokens 문서들.
 * @return {Map<TestPushLocale, Array<string>>} locale → 토큰 목록.
 */
function groupTokensByLocale(
  docs: QueryDocumentSnapshot[],
): Map<TestPushLocale, string[]> {
  const groups = new Map<TestPushLocale, string[]>();
  for (const doc of docs) {
    const locale = resolveTestPushLocale(doc.data().locale);
    const tokens = groups.get(locale) ?? [];
    tokens.push(doc.id);
    groups.set(locale, tokens);
  }
  return groups;
}

/**
 * locale 1개 · 토큰 청크 1개의 발송 요청을 만든다 (D-05 payload).
 *
 * notification(title · body) + `data.route` + Android 채널 + iOS 기본 소리.
 * - `data.route` 는 앱 알림 탭 허용 목록(`kNotificationRoutableRoutes` —
 *   `/` · `/settings` · `/terms/service` · `/terms/privacy`) 안이어야 그
 *   화면으로 이동한다(목록 밖이면 홈). 본문 「설정 화면을 엽니다」 와 짝.
 * - Android 채널 id 는 앱이 bootstrap 에서 만드는 채널(plan 16)과 같다.
 *
 * @param {TestPushLocale} locale 문구 locale.
 * @param {Array<string>} tokens 대상 토큰 (최대 500).
 * @return {MulticastMessage} 발송 요청.
 */
function buildTestPushMessage(
  locale: TestPushLocale,
  tokens: string[],
): MulticastMessage {
  return {
    tokens,
    notification: {...TEST_PUSH_COPY[locale]},
    data: {route: "/settings"},
    android: {notification: {channelId: "general"}},
    apns: {payload: {aps: {sound: "default"}}},
  };
}

/**
 * sendTestPush 본체 (D-05 · D-34 · D-35).
 *
 * 흐름:
 *   Step 0: `request.auth` 검증 → 미인증 `unauthenticated`.
 *   Step 1: 환경 스위치(D-35) — 꺼져 있으면 읽기 · 발송 없이
 *           `failed-precondition` + `{reason: "test_push_disabled"}`.
 *   Step 2: `users/{uid}/fcmTokens` 전체 읽기 → locale 그룹.
 *   Step 3: 그룹(· 500개 청크)마다 `sendEachForMulticast` → 성공 수 합.
 *   Step 4: `{event: "send_test_push_done", uid, sent, failed, pruned}` 로그 →
 *           `{sentCount}`.
 *
 * Firestore · FCM 요청 자체가 실패하면 `internal` / `errorUnknown`.
 *
 * @param {CallableRequest<unknown>} request onCall request — 본문은 읽지
 *     않는다 (입력 0).
 * @return {Promise<SendTestPushResponse>} 성공 기기 수.
 */
async function runSendTestPush(
  request: CallableRequest<unknown>,
): Promise<SendTestPushResponse> {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "errorUnauthenticated");
  }
  const uid = request.auth.uid;

  if (!sendTestPushEnabled().value()) {
    logger.info(
      {event: "send_test_push_disabled", uid},
      "test push disabled in this environment",
    );
    throw new HttpsError("failed-precondition", "errorTestPushDisabled", {
      reason: TEST_PUSH_DISABLED_REASON,
    });
  }

  const db = getFirestore();
  let sent = 0;
  let failed = 0;
  const pruned = 0;
  try {
    const snap = await db
      .collection("users")
      .doc(uid)
      .collection("fcmTokens")
      .get();
    const groups = groupTokensByLocale(snap.docs);
    for (const [locale, tokens] of groups) {
      for (const batch of chunk(tokens, MAX_MULTICAST_TOKENS)) {
        const response = await getMessaging().sendEachForMulticast(
          buildTestPushMessage(locale, batch),
        );
        sent += response.successCount;
        failed += response.failureCount;
      }
    }
  } catch (err: unknown) {
    logger.error(
      {event: "send_test_push_failed", uid, code: fingerprintError(err)},
      "test push send failed",
    );
    throw new HttpsError("internal", "errorUnknown");
  }

  logger.info(
    {event: "send_test_push_done", uid, sent, failed, pruned},
    "test push sent",
  );
  return {sentCount: sent};
}

/**
 * 호출자 본인의 모든 기기로 테스트 알림을 보내는 callable (D-05).
 *
 * App Check 강제 · 인증 필수 · 입력 0. 동작은 [runSendTestPush] 참조.
 */
export const sendTestPush = onCall({enforceAppCheck: true}, runSendTestPush);
