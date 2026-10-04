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
// - 남용 방지: uid 별 10회/60초 (Phase 16 D-10 mirror · `shared/rate_limit.ts`).
// - 토큰 위생: 만료(`expireAt` 경과 — TTL 삭제 지연 ≤ 24h 방어 · D-33) · 미등록 ·
//   무효 토큰 문서는 발송 뒤 지운다.
// - PII: 로그에 토큰 문자열 · 알림 본문을 싣지 않는다 (uid · 수 · 오류 code).
//
// **IN-04**: 아래 `HttpsError` 들의 message 는 ARB 키가 아니라 taxonomy
// 토큰이다. client 는 `code` + `details.reason` 으로만 분기한다.
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import type {
  DocumentReference,
  Firestore,
  QueryDocumentSnapshot,
} from "firebase-admin/firestore";
import {getMessaging} from "firebase-admin/messaging";
import type {MulticastMessage} from "firebase-admin/messaging";
import {onCall, HttpsError} from "firebase-functions/https";
import type {CallableRequest} from "firebase-functions/https";
import * as logger from "firebase-functions/logger";
import {defineBoolean} from "firebase-functions/params";
import type {BooleanParam} from "firebase-functions/params";

import {fingerprintError} from "../auth/identity_index";
import {isAnonymousCaller} from "../shared/caller_auth";
import {ANONYMOUS_CALLER_REASON} from "../shared/custom_token_errors";
import {consumeRateLimit} from "../shared/rate_limit";
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

/** uid 별 rate limit — 창당 허용 횟수 (Phase 16 D-10 과 같은 값). */
const RATE_LIMIT = 10;

/** uid 별 rate limit — 창 길이 (초). */
const RATE_WINDOW_SEC = 60;

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

/** 발송 대상 토큰 1개 — 토큰 문자열 + 정리용 문서 참조. */
type TokenTarget = {
  token: string;
  ref: DocumentReference;
};

/**
 * 토큰 문서의 `expireAt` 이 [nowMillis] 보다 앞인지 판정한다 (D-33).
 *
 * Firestore TTL 은 만료 뒤 최대 24시간 지나서 지우므로(Pitfall 15) 그 사이의
 * 문서를 서버가 직접 거른다. `expireAt` 이 없거나 Timestamp 형태가 아니면
 * 만료로 보지 않는다(발송 대상 유지).
 *
 * @param {unknown} expireAt 토큰 문서 `expireAt` 필드 값.
 * @param {number} nowMillis 현재 시각 (epoch ms).
 * @return {boolean} 만료면 true.
 */
function isExpired(expireAt: unknown, nowMillis: number): boolean {
  if (typeof expireAt !== "object" || expireAt === null) return false;
  const toMillis = (expireAt as {toMillis?: unknown}).toMillis;
  if (typeof toMillis !== "function") return false;
  const millis: unknown = toMillis.call(expireAt);
  return typeof millis === "number" && millis < nowMillis;
}

/**
 * FCM 응답 오류가 「토큰 폐기」 code 인지 판정한다 (RESEARCH R-02 · A14).
 *
 * 미등록(앱 삭제 · 토큰 교체)과 무효 형식 두 가지만 문서를 지운다. code 는
 * 응답 오류 값을 그대로 fingerprint 해 부분 일치로 본다(`messaging/` 접두어
 * 유무와 무관). 그 밖의 실패(일시 오류 등)는 문서를 유지한다.
 *
 * @param {unknown} error `SendResponse.error`.
 * @return {boolean} 문서를 지워야 하면 true.
 */
function isStaleTokenError(error: unknown): boolean {
  const code = fingerprintError(error);
  return code.includes("registration-token-not-registered") ||
    code.includes("invalid-registration-token");
}

/**
 * 토큰 문서를 만료 여부로 나누고, 살아 있는 것을 문구 locale 별로 묶는다
 * (D-31 · D-33).
 *
 * 토큰 문자열은 문서 id 다(rules 가 `data.token == id` 를 강제).
 *
 * @param {Array<QueryDocumentSnapshot>} docs fcmTokens 문서들.
 * @param {number} nowMillis 현재 시각 (epoch ms).
 * @return {{groups: Map<TestPushLocale, Array<TokenTarget>>,
 *     expired: Array<DocumentReference>}} locale 그룹 · 만료 문서 참조.
 */
function partitionTokens(
  docs: QueryDocumentSnapshot[],
  nowMillis: number,
): {
  groups: Map<TestPushLocale, TokenTarget[]>;
  expired: DocumentReference[];
} {
  const groups = new Map<TestPushLocale, TokenTarget[]>();
  const expired: DocumentReference[] = [];
  for (const doc of docs) {
    const data = doc.data();
    if (isExpired(data.expireAt, nowMillis)) {
      expired.push(doc.ref);
      continue;
    }
    const locale = resolveTestPushLocale(data.locale);
    const targets = groups.get(locale) ?? [];
    targets.push({token: doc.id, ref: doc.ref});
    groups.set(locale, targets);
  }
  return {groups, expired};
}

/**
 * 토큰 문서들을 지우고 성공 수를 돌려준다 (best-effort).
 *
 * 하나가 실패해도 나머지는 계속 지운다. 실패는 `{event, uid, code}` 로만
 * 남긴다(토큰 문자열 0). 남은 문서는 다음 발송 · TTL 이 다시 정리한다.
 *
 * @param {Array<DocumentReference>} refs 지울 문서 참조.
 * @param {string} uid 호출자 uid (로그용).
 * @return {Promise<number>} 삭제 성공 수.
 */
async function pruneTokens(
  refs: DocumentReference[],
  uid: string,
): Promise<number> {
  const results = await Promise.allSettled(refs.map((ref) => ref.delete()));
  let pruned = 0;
  for (const result of results) {
    if (result.status === "fulfilled") {
      pruned += 1;
    } else {
      logger.warn(
        {
          event: "send_test_push_prune_failed",
          uid,
          code: fingerprintError(result.reason),
        },
        "token document delete failed",
      );
    }
  }
  return pruned;
}

/**
 * locale 1개 · 토큰 청크 1개의 발송 요청을 만든다 (D-05 payload).
 *
 * notification(title · body) + `data.route` + Android 채널 + iOS 기본 소리.
 * - `data.route` 는 앱 알림 탭 허용 목록(`kNotificationRoutableRoutes` —
 *   `/` · `/settings` · `/settings/account` · `/terms/service` ·
 *   `/terms/privacy`) 안이어야 그 화면으로 이동한다(목록 밖이면 홈).
 *   본문 「설정 화면을 엽니다」 와 짝.
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
 * uid 별 rate limit 을 1회 소비한다 — 초과면 `resource-exhausted`.
 *
 * 초과 응답은 `lookupSignInMethods` 와 같은 `resource-exhausted` /
 * `errorTooManyRequests` 다. counter transaction 자체가 실패하면
 * `internal` / `errorUnknown`.
 *
 * @param {Firestore} db Firestore 인스턴스.
 * @param {string} uid 호출자 uid.
 * @return {Promise<void>} 허용이면 resolve.
 */
async function enforceRateLimit(
  db: Firestore,
  uid: string,
): Promise<void> {
  let allowed: boolean;
  try {
    allowed = await consumeRateLimit(db, `sendTestPush:${uid}`, {
      limit: RATE_LIMIT,
      windowSec: RATE_WINDOW_SEC,
    });
  } catch (err: unknown) {
    logger.warn(
      {
        event: "send_test_push_rate_limit_failed",
        uid,
        code: fingerprintError(err),
      },
      "rate limit transaction threw",
    );
    throw new HttpsError("internal", "errorUnknown");
  }
  if (!allowed) {
    logger.warn(
      {event: "send_test_push_rate_limited", uid},
      "rate limit exceeded",
    );
    throw new HttpsError("resource-exhausted", "errorTooManyRequests");
  }
}

/**
 * sendTestPush 본체 (D-05 · D-33 · D-34 · D-35).
 *
 * 흐름:
 *   Step 0: `request.auth` 검증 → 미인증 `unauthenticated`, 익명
 *           `failed-precondition` + `{reason: "anonymous_caller"}`
 *           (리뷰 WR-02 — 익명은 토큰이 없다(D-02). rate limit 카운터 ·
 *           Firestore 읽기 전에 거부해 익명 uid 로 문서를 만들지 않는다 ·
 *           D-28 · `mirrorAccountEmail` 과 같은 code · reason).
 *   Step 1: 환경 스위치(D-35) — 꺼져 있으면 읽기 · 발송 없이
 *           `failed-precondition` + `{reason: "test_push_disabled"}`.
 *   Step 2: uid 별 rate limit 10회/60초 → 초과 `resource-exhausted`.
 *   Step 3: `users/{uid}/fcmTokens` 전체 읽기 → 만료 제외(D-33) → locale 그룹.
 *   Step 4: 그룹(· 500개 청크)마다 `sendEachForMulticast` → 성공 수 합 ·
 *           미등록 · 무효 토큰 수집.
 *   Step 5: 만료 + 미등록 · 무효 토큰 문서 삭제(best-effort).
 *   Step 6: `{event: "send_test_push_done", uid, sent, failed, pruned}` 로그 →
 *           `{sentCount}`.
 *
 * Firestore 읽기 · FCM 요청 자체가 실패하면 `internal` / `errorUnknown`.
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
  if (isAnonymousCaller(request.auth)) {
    throw new HttpsError(
      "failed-precondition",
      "errorAnonymousCallerNotAllowed",
      {reason: ANONYMOUS_CALLER_REASON},
    );
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
  await enforceRateLimit(db, uid);

  let sent = 0;
  let failed = 0;
  const toPrune: DocumentReference[] = [];
  try {
    const snap = await db
      .collection("users")
      .doc(uid)
      .collection("fcmTokens")
      .get();
    const {groups, expired} = partitionTokens(
      snap.docs,
      Timestamp.now().toMillis(),
    );
    toPrune.push(...expired);
    for (const [locale, targets] of groups) {
      for (let i = 0; i < targets.length; i += MAX_MULTICAST_TOKENS) {
        const batch = targets.slice(i, i + MAX_MULTICAST_TOKENS);
        const response = await getMessaging().sendEachForMulticast(
          buildTestPushMessage(locale, batch.map((t) => t.token)),
        );
        sent += response.successCount;
        failed += response.failureCount;
        response.responses.forEach((r, index) => {
          if (r.success) return;
          logger.info(
            {
              event: "send_test_push_token_rejected",
              uid,
              code: fingerprintError(r.error),
            },
            "token rejected by FCM",
          );
          if (isStaleTokenError(r.error)) toPrune.push(batch[index].ref);
        });
      }
    }
  } catch (err: unknown) {
    logger.error(
      {event: "send_test_push_failed", uid, code: fingerprintError(err)},
      "test push send failed",
    );
    throw new HttpsError("internal", "errorUnknown");
  }

  const pruned = await pruneTokens(toPrune, uid);
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
