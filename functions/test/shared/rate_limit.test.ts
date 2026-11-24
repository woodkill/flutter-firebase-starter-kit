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
 *  - T-32-RATE-01 ~ 03: 만료 시각 · increment · uid 축 삭제(Phase 32)
 */

// eslint-disable-next-line import/first
import {Timestamp} from "firebase-admin/firestore";
import type {Firestore} from "firebase-admin/firestore";

// eslint-disable-next-line import/first
import {
  consumeRateLimit,
  consumeRateLimitAxes,
  deleteUidRateLimitDocs,
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

describe("rate limit helper — Phase 32", () => {
  it("T-32-RATE-03: deleteUidRateLimitDocs 는 uid 축 4건을 " +
    "batch 하나로 지운다 (precondition 없음)",
  async () => {
    // fake commit 은 늘 성공 — 실제 Firestore 의 없는 문서 delete 성공은
    // UAT 가 본다(A6). 여기서는 delete 4건 · commit 1회 · precondition
    // 인자 없음만 고정한다.
    const deleted: string[] = [];
    const deleteArgCounts: number[] = [];
    let commits = 0;
    const db = {
      collection: (name: string) => ({
        doc: (id: string) => ({path: `${name}/${id}`}),
      }),
      batch: () => ({
        delete: (...args: unknown[]) => {
          deleteArgCounts.push(args.length);
          deleted.push((args[0] as {path: string}).path);
        },
        commit: async () => {
          commits += 1;
          return [];
        },
      }),
    } as unknown as Firestore;

    // 같은 uid 를 두 번 지워도(문서가 이미 없어도) 같은 batch 를 만든다.
    await deleteUidRateLimitDocs(db, "u9");
    await deleteUidRateLimitDocs(db, "u9");

    expect(deleted.slice(0, 4)).toEqual([
      "rate_limits/lookupSignInMethods:u9",
      "rate_limits/sendTestPush:u9",
      "rate_limits/sendVerificationMail:u9",
      "rate_limits/sendPasswordResetMail:u9",
    ]);
    expect(deleted.slice(4)).toEqual(deleted.slice(0, 4));
    expect(deleted).toHaveLength(8);
    expect(commits).toBe(2);
    expect(deleteArgCounts.every((n) => n === 1)).toBe(true);
  });

  /**
   * 저장소의 counter 문서에서 만료 시각을 읽어 창 시작과의 차이를 돌려준다.
   *
   * 만료 시각이나 창 시작이 Timestamp 가 아니면 `gap` · `nanos` 는 null 이다
   * (단언이 TypeError 대신 값 비교로 실패하게).
   *
   * @param {Store} store 문서 저장소.
   * @param {string} path 문서 경로 (`rate_limits/<docId>`).
   * @return {{gap: (number|null), isTimestamp: boolean, nanos: (number|null)}}
   *     만료 시각 − 창 시작(초) · Timestamp 여부 · 만료 시각 나노초.
   */
  function readExpireGap(store: Store, path: string): {
    gap: number | null;
    isTimestamp: boolean;
    nanos: number | null;
  } {
    const doc = store.get(path);
    const expireAt = doc?.expireAt;
    const windowStart = doc?.windowStart;
    const isTimestamp = expireAt instanceof Timestamp;
    if (!(expireAt instanceof Timestamp) ||
      !(windowStart instanceof Timestamp)) {
      return {gap: null, isTimestamp, nanos: null};
    }
    return {
      gap: expireAt.seconds - windowStart.seconds,
      isTimestamp,
      nanos: expireAt.nanoseconds,
    };
  }

  /**
   * [db] 의 runTransaction 을 감싸 tx 의 `update` data 를 [updates] 에 남긴다.
   *
   * 기존 `fakeDb` 는 고치지 않고, 넘겨받은 tx 의 다른 메서드는 그대로 쓴다.
   *
   * @param {Firestore} db 감쌀 fake (`fakeDb` 결과).
   * @param {Array<unknown>} updates `tx.update` data 기록 (호출 순).
   * @return {Firestore} update 를 기록하는 fake.
   */
  function wrapUpdateRecorder(db: Firestore, updates: unknown[]): Firestore {
    type TxLike = {update: (ref: unknown, data: unknown) => unknown};
    const inner = db as unknown as {
      collection: unknown;
      runTransaction: (
        fn: (tx: unknown) => Promise<unknown>,
      ) => Promise<unknown>;
    };
    const wrapped = {
      collection: inner.collection,
      runTransaction: (fn: (tx: unknown) => Promise<unknown>) =>
        inner.runTransaction((tx) => {
          const base = tx as TxLike;
          return fn({
            ...(tx as Record<string, unknown>),
            update: (ref: unknown, data: unknown) => {
              updates.push(data);
              return base.update(ref, data);
            },
          });
        }),
    };
    return wrapped as unknown as Firestore;
  }

  it("T-32-RATE-01: 새 창 set 은 창 끝 만료 시각(초 단위)을 쓴다",
    async () => {
      const store: Store = new Map();
      const db = fakeDb(store, []);

      await expect(consumeRateLimit(db, "sendTestPush:u1", {
        limit: 5,
        windowSec: 60,
      })).resolves.toBe(true);
      await expect(consumeRateLimitAxes(db, [
        {axis: "uid", docId: "sendVerificationMail:u1", limit: 5,
          windowSec: 600},
        {axis: "ip", docId: "sendPasswordResetMailIp:h1", limit: 5,
          windowSec: 60},
      ])).resolves.toEqual([]);

      // 만료 시각 = 창 시작 + 창 길이(초 단위 · 나노초 0).
      expect(readExpireGap(store, "rate_limits/sendTestPush:u1")).toEqual(
        {gap: 60, isTimestamp: true, nanos: 0},
      );
      expect(readExpireGap(store, "rate_limits/sendVerificationMail:u1"))
        .toEqual({gap: 600, isTimestamp: true, nanos: 0});
      expect(readExpireGap(store, "rate_limits/sendPasswordResetMailIp:h1"))
        .toEqual({gap: 60, isTimestamp: true, nanos: 0});
    });

  it("T-32-RATE-02: 같은 창 increment 는 count 만 바꾸고 만료 시각을 두고 간다",
    async () => {
      const store: Store = new Map();
      const txCalls: string[][] = [];
      const updates: unknown[] = [];
      const db = wrapUpdateRecorder(fakeDb(store, txCalls), updates);
      const pushPath = "rate_limits/sendTestPush:u2";
      const mailPath = "rate_limits/sendVerificationMail:u2";

      // consumeRateLimit — 새 창 → 같은 창 increment.
      const opts = {limit: 5, windowSec: 60};
      await expect(consumeRateLimit(db, "sendTestPush:u2", opts))
        .resolves.toBe(true);
      const pushExpire = store.get(pushPath)?.expireAt;
      await expect(consumeRateLimit(db, "sendTestPush:u2", opts))
        .resolves.toBe(true);

      // consumeRateLimitAxes — 축 하나로 같은 흐름.
      const axes = [
        {axis: "uid", docId: "sendVerificationMail:u2", limit: 5,
          windowSec: 600},
      ];
      await expect(consumeRateLimitAxes(db, axes)).resolves.toEqual([]);
      const mailExpire = store.get(mailPath)?.expireAt;
      await expect(consumeRateLimitAxes(db, axes)).resolves.toEqual([]);

      expect(txCalls).toEqual([
        ["get", "set"],
        ["get", "update"],
        ["get", "set"],
        ["get", "update"],
      ]);
      // increment payload 는 count 하나뿐이다 — 만료 시각이 미끄러지지 않는다.
      expect(updates.map((d) => Object.keys(d as object))).toEqual([
        ["count"],
        ["count"],
      ]);
      expect(store.get(pushPath)?.expireAt).toEqual(pushExpire);
      expect(store.get(mailPath)?.expireAt).toEqual(mailExpire);
      expect(store.get(pushPath)?.count).toBe(2);
      expect(store.get(mailPath)?.count).toBe(2);
    });
});
