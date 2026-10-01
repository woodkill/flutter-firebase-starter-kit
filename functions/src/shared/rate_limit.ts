// Phase 17 — see ROADMAP.md (plan 18 · Phase 16 D-10 mirror) — Firestore
// counter 기반 rate limit 공유 helper.
//
// `lookupSignInMethods` 가 쓰던 counter 해석을 그대로 옮겨 `sendTestPush` 와
// 공유한다. counter 문서는 `rate_limits/{docId}` 의 `{count, windowStart}` 다.
// 문서 id 에는 uid · 해시만 쓴다(이메일 · IP 원문 금지).
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import type {Firestore} from "firebase-admin/firestore";

/** rate limit counter 문서의 해석 결과. */
export type RateCounterState = {
  /** 현재 창의 카운트 (창이 만료됐으면 의미 없음). */
  count: number;
  /** 창이 없거나 만료됨 → 새 창으로 리셋해야 한다. */
  expired: boolean;
};

/** counter 문서 스냅샷 중 해석에 필요한 부분 (Firestore 스냅샷이 만족). */
export type RateCounterSnapshot = {
  exists: boolean;
  data(): Record<string, unknown> | undefined;
};

/**
 * rate limit counter 문서를 방어적으로 해석한다 (Phase 15 리뷰 WR-08).
 *
 * 문서에 `windowStart` 가 없거나 형태가 어긋나면 (부분 write / 수동 편집 /
 * 스키마 변경 잔재) 예외 대신 "만료된 창" 으로 본다 — 다음 write 가 정상
 * 문서로 덮어써 자기치유된다. 예외로 처리하면 그 키의 요청이 영구 실패한다.
 *
 * `Timestamp` 를 `instanceof` 로 검사하지 않는다 — 필요한 것은 `seconds`
 * 하나뿐이고, duck typing 이 Firestore Timestamp 와 그 직렬화된 형태를 모두
 * 받아준다.
 *
 * @param {RateCounterSnapshot} snap counter 문서 스냅샷.
 * @param {Timestamp} now 현재 시각.
 * @param {number} windowSec 창 길이 (초).
 * @return {RateCounterState} 카운트 + 창 만료 여부.
 */
export function readRateCounter(
  snap: RateCounterSnapshot,
  now: Timestamp,
  windowSec: number,
): RateCounterState {
  if (!snap.exists) return {count: 0, expired: true};
  const data = snap.data();
  const windowStart = data?.windowStart;
  const rawCount = data?.count;
  const startSeconds = (windowStart as {seconds?: unknown} | undefined)
    ?.seconds;
  if (typeof startSeconds !== "number" || !Number.isFinite(startSeconds)) {
    return {count: 0, expired: true};
  }
  if (now.seconds - startSeconds > windowSec) {
    return {count: 0, expired: true};
  }
  const count = typeof rawCount === "number" && Number.isFinite(rawCount) ?
    rawCount :
    0;
  return {count, expired: false};
}

/**
 * 단일 키 rate limit 을 1회 소비한다 (Phase 16 D-10 패턴 mirror).
 *
 * `rate_limits/{docId}` counter 를 Firestore transaction 안에서
 * 「read 전부 → 한도 판정 → write」 순으로 처리한다 (reads-before-writes —
 * 실 Firestore 는 write 뒤 read 를 거부한다).
 * - 창이 없거나 만료 → `{count: 1, windowStart: now}` 로 새 창.
 * - 창 안 · `count < limit` → `count + 1`.
 * - 창 안 · `count >= limit` → write 없이 `false`.
 *
 * transaction 자체 실패(Firestore 오류)는 그대로 reject 된다 — 호출부가
 * 로그 · HttpsError 로 바꾼다.
 *
 * @param {Firestore} db Firestore 인스턴스.
 * @param {string} docId counter 문서 id (예: `sendTestPush:<uid>`).
 * @param {{limit: number, windowSec: number}} opts 창당 허용 횟수 · 창 길이.
 * @return {Promise<boolean>} 허용이면 true, 한도 초과면 false.
 */
export async function consumeRateLimit(
  db: Firestore,
  docId: string,
  opts: {limit: number; windowSec: number},
): Promise<boolean> {
  const ref = db.collection("rate_limits").doc(docId);
  return db.runTransaction(async (tx) => {
    // --- reads (모두 write 앞) ---
    const snap = await tx.get(ref);
    const now = Timestamp.now();
    const state = readRateCounter(snap, now, opts.windowSec);

    // --- 한도 판정 (write 전) ---
    if (!state.expired && state.count >= opts.limit) return false;

    // --- writes ---
    if (state.expired) {
      tx.set(ref, {count: 1, windowStart: now});
    } else {
      tx.update(ref, {count: FieldValue.increment(1)});
    }
    return true;
  });
}
