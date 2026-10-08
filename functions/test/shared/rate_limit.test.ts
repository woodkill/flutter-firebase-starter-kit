/**
 * rate limit 공유 helper 회귀 테스트 (Phase 17 plan 18 · Phase 16 D-10 mirror).
 *
 * `lookupSignInMethods` 의 counter 해석(`readCounter`)을 `readRateCounter` 로
 * 옮기고 단일 키 판정 `consumeRateLimit` 을 더했다. 기존 동작 회귀 기준은
 * `test/auth/lookup_sign_in_methods.test.ts`(무수정) 이고, 여기서는 helper
 * 자체의 경계 · reads-before-writes 를 잠근다.
 *
 * 시나리오:
 *  - T-17-SEND-08: readRateCounter 4경계 + consumeRateLimit 한도 · 문서 id ·
 *    트랜잭션 순서
 *  - T-175-RATE-01: consumeRateLimitAxes 다축 — 한 transaction · 초과 축
 *    목록 · 초과 시 write 0 (Phase 17.5 kit 메일 callable)
 */

// eslint-disable-next-line import/first
import {Timestamp} from "firebase-admin/firestore";
import type {Firestore} from "firebase-admin/firestore";

// eslint-disable-next-line import/first
import {
  consumeRateLimit,
  consumeRateLimitAxes,
  readRateCounter,
} from "../../src/shared/rate_limit";
// eslint-disable-next-line import/first
import {createOrderedTx} from "../mocks/ordered_transaction";

/**
 * counter 문서 스냅샷 fixture 를 만든다.
 *
 * @param {object|undefined} data 문서 데이터 (undefined = 문서 없음).
 * @return {{exists: boolean, data: function(): (object|undefined)}} 스냅샷.
 */
function snapOf(data: Record<string, unknown> | undefined): {
  exists: boolean;
  data(): Record<string, unknown> | undefined;
} {
  return {exists: data !== undefined, data: () => data};
}

/** ref 경로 → 문서 데이터 (트랜잭션 commit 시뮬레이션 저장소). */
type Store = Map<string, Record<string, unknown>>;

/**
 * `rate_limits` 컬렉션만 다루는 Firestore fake 를 만든다.
 *
 * runTransaction 은 순서 강제 tx(`createOrderedTx`)로 콜백을 돌린 뒤 write 를
 * 저장소에 반영한다 — `count` 가 숫자가 아니면 increment(1) 로 본다.
 *
 * @param {Store} store 문서 저장소.
 * @param {Array<Array<string>>} txCalls 트랜잭션마다의 호출 순서 기록.
 * @return {Firestore} fake.
 */
function fakeDb(store: Store, txCalls: string[][]): Firestore {
  const db = {
    collection: (name: string) => ({
      doc: (id: string) => ({path: `${name}/${id}`}),
    }),
    runTransaction: async (fn: (tx: unknown) => Promise<unknown>) => {
      const handle = createOrderedTx((ref) => {
        const path = (ref as {path: string}).path;
        return snapOf(store.get(path));
      });
      const result = await fn(handle.tx);
      txCalls.push(handle.calls);
      for (const {ref, data} of handle.sets) {
        const path = (ref as {path: string}).path;
        store.set(path, data as Record<string, unknown>);
      }
      for (const {ref, data} of handle.updates) {
        const path = (ref as {path: string}).path;
        const prev = store.get(path) ?? {};
        const next = (data as {count?: unknown}).count;
        const count = typeof next === "number" ?
          next :
          (typeof prev.count === "number" ? prev.count : 0) + 1;
        store.set(path, {...prev, count});
      }
      return result;
    },
  };
  return db as unknown as Firestore;
}

describe("rate limit helper — Phase 17 plan 18 (Phase 16 D-10 mirror)", () => {
  it("T-17-SEND-08: readRateCounter 경계 · consumeRateLimit 한도와 순서",
    async () => {
      const now = Timestamp.fromMillis(1_000_000 * 1000);

      // 문서 없음 → 만료(새 창).
      expect(readRateCounter(snapOf(undefined), now, 60)).toEqual(
        {count: 0, expired: true},
      );
      // 창 안 → 저장된 count.
      expect(readRateCounter(
        snapOf({count: 7, windowStart: {seconds: now.seconds - 30}}), now, 60,
      )).toEqual({count: 7, expired: false});
      // 창 밖 → 만료.
      expect(readRateCounter(
        snapOf({count: 7, windowStart: {seconds: now.seconds - 61}}), now, 60,
      )).toEqual({count: 0, expired: true});
      // seconds 가 숫자가 아님 → 만료(자기치유).
      expect(readRateCounter(
        snapOf({count: 7, windowStart: {seconds: "x"}}), now, 60,
      )).toEqual({count: 0, expired: true});

      // consumeRateLimit — limit 2: 2회 허용 · 3번째 거부.
      const store: Store = new Map();
      const txCalls: string[][] = [];
      const db = fakeDb(store, txCalls);
      const opts = {limit: 2, windowSec: 60};
      await expect(consumeRateLimit(db, "sendTestPush:u8", opts))
        .resolves.toBe(true);
      await expect(consumeRateLimit(db, "sendTestPush:u8", opts))
        .resolves.toBe(true);
      await expect(consumeRateLimit(db, "sendTestPush:u8", opts))
        .resolves.toBe(false);

      expect([...store.keys()]).toEqual(["rate_limits/sendTestPush:u8"]);
      expect(store.get("rate_limits/sendTestPush:u8")?.count).toBe(2);
      // 매 트랜잭션은 read 1회로 시작하고, 거부된 3번째는 write 가 없다.
      expect(txCalls).toEqual([["get", "set"], ["get", "update"], ["get"]]);
    });

  it("T-175-RATE-01: consumeRateLimitAxes 는 한 transaction 에서 모든 축을 판정한다",
    async () => {
      const store: Store = new Map();
      const txCalls: string[][] = [];
      const db = fakeDb(store, txCalls);
      const axes = [
        {axis: "uid", docId: "mail:u1", limit: 3, windowSec: 60},
        {axis: "email", docId: "mailEmail:h1", limit: 1, windowSec: 60},
      ];

      // 1회차 — 두 축 모두 새 창.
      await expect(consumeRateLimitAxes(db, axes)).resolves.toEqual([]);
      // 2회차 — email 축(limit 1)만 초과 → write 0.
      await expect(consumeRateLimitAxes(db, axes)).resolves.toEqual([
        {axis: "email", count: 1},
      ]);

      expect(store.get("rate_limits/mail:u1")?.count).toBe(1);
      expect(store.get("rate_limits/mailEmail:h1")?.count).toBe(1);
      // read 전부가 write 앞 · 거부된 2회차는 write 가 없다.
      expect(txCalls).toEqual([["get", "get", "set", "set"], ["get", "get"]]);

      // 두 축 동시 초과 → 축 순서대로 둘 다 돌려준다.
      const tight = axes.map((a) => ({...a, limit: 1}));
      await expect(consumeRateLimitAxes(db, tight)).resolves.toEqual([
        {axis: "uid", count: 1},
        {axis: "email", count: 1},
      ]);
    });
});
