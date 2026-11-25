/**
 * rate limit helper 의 같은 창 증가량 회귀 테스트.
 *
 * 기존 fake 는 숫자가 아닌 count payload 를 모두 +1 로 해석해 증가량이 1 인지
 * 볼 수 없다. 여기서는 `FieldValue.increment` 를 `{mockIncrement: n}` 으로
 * 바꿔 update payload 원본을 그대로 단언한다.
 *
 * 시나리오:
 *  - T-32-RATE-04: consumeRateLimit 같은 창 두 번째 호출의 update 는 정확히
 *    `{count: increment(1)}` 한 건이다 (0 · 2 증가, update 꼴 리셋 실패)
 *  - T-32-RATE-05: consumeRateLimitAxes 도 축마다 같은 payload 를 쓴다
 */

import type {Firestore} from "firebase-admin/firestore";

import {
  consumeRateLimit,
  consumeRateLimitAxes,
} from "../../src/shared/rate_limit";
import {createOrderedTx} from "../mocks/ordered_transaction";

jest.mock("firebase-admin/firestore", () => {
  const actual = jest.requireActual("firebase-admin/firestore");
  return {
    ...actual,
    FieldValue: {
      increment: (n: number) => ({mockIncrement: n}),
    },
  };
});

/** ref 경로 → 문서 데이터 저장소. */
type Store = Map<string, Record<string, unknown>>;

/** update 로 들어온 raw 기록. */
type UpdateRecord = {path: string; data: unknown};

/**
 * set 은 저장소에 반영하고 update 는 raw 로 기록하는 Firestore fake 를 만든다.
 *
 * @param {Store} store 문서 저장소.
 * @param {Array<UpdateRecord>} updates update raw 기록 (호출 순).
 * @return {Firestore} fake.
 */
function fakeDb(store: Store, updates: UpdateRecord[]): Firestore {
  const db = {
    collection: (name: string) => ({
      doc: (id: string) => ({path: `${name}/${id}`}),
    }),
    runTransaction: async (fn: (tx: unknown) => Promise<unknown>) => {
      const handle = createOrderedTx((ref) => {
        const data = store.get((ref as {path: string}).path);
        return {exists: data !== undefined, data: () => data};
      });
      const result = await fn(handle.tx);
      for (const {ref, data} of handle.sets) {
        store.set(
          (ref as {path: string}).path,
          data as Record<string, unknown>,
        );
      }
      for (const {ref, data} of handle.updates) {
        updates.push({path: (ref as {path: string}).path, data});
      }
      return result;
    },
  };
  return db as unknown as Firestore;
}

describe("rate limit helper — 같은 창 increment(1) payload", () => {
  it("T-32-RATE-04: consumeRateLimit 같은 창 update 는 {count: increment(1)} 한 건이다",
    async () => {
      const store: Store = new Map();
      const updates: UpdateRecord[] = [];
      const db = fakeDb(store, updates);
      const opts = {limit: 5, windowSec: 60};

      // 1회차는 새 창(set), 2회차가 같은 창 분기.
      await expect(consumeRateLimit(db, "k:a", opts)).resolves.toBe(true);
      expect(updates).toHaveLength(0);
      await expect(consumeRateLimit(db, "k:a", opts)).resolves.toBe(true);

      expect(updates).toEqual([
        {path: "rate_limits/k:a", data: {count: {mockIncrement: 1}}},
      ]);
    });

  it("T-32-RATE-05: consumeRateLimitAxes 같은 창 호출은 축마다 increment(1) 을 쓴다",
    async () => {
      const store: Store = new Map();
      const updates: UpdateRecord[] = [];
      const db = fakeDb(store, updates);
      const axes = [
        {axis: "uid", docId: "m:u", limit: 5, windowSec: 60},
        {axis: "ip", docId: "m:ip", limit: 5, windowSec: 60},
      ];

      await expect(consumeRateLimitAxes(db, axes)).resolves.toEqual([]);
      expect(updates).toHaveLength(0);
      await expect(consumeRateLimitAxes(db, axes)).resolves.toEqual([]);

      expect(updates).toEqual([
        {path: "rate_limits/m:u", data: {count: {mockIncrement: 1}}},
        {path: "rate_limits/m:ip", data: {count: {mockIncrement: 1}}},
      ]);
    });
});
