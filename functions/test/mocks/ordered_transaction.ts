/**
 * 「all reads before all writes」 를 강제하는 Firestore transaction mock
 * (Phase 16.8 plan 02 · RESEARCH §Code Examples 「순서 강제 tx mock」).
 *
 * 실 Firestore 는 transaction 안에서 write 뒤 read 를 하면 오류를 던지지만,
 * 기존 jest mock 은 그 순서를 강제하지 않아 read-after-write 회귀가 green
 * 으로 통과했다 (memory feedback_mock_transaction_constraint · R12 계열).
 * 본 helper 는 write(`delete` / `update` / `set`) 가 한 번이라도 호출된 뒤
 * `get` 이 오면 `READ_AFTER_WRITE` 를 던져 그 회귀를 테스트 실패로 만든다.
 *
 * 파일명에 `.test.ts` 접미어를 붙이지 않는다 — `jest.config.js` 의
 * `testMatch` 에 잡히지 않게 하는 `test/mocks/` 관례.
 */

/** 순서 강제 transaction 의 테스트용 부분 shape. */
export type OrderedTx = {
  get: (ref: unknown) => Promise<unknown>;
  delete: (ref: unknown) => unknown;
  update: (ref: unknown, data: unknown) => unknown;
  set: (ref: unknown, data: unknown, opts?: unknown) => unknown;
};

/** [createOrderedTx] 의 반환 — tx 와 호출 기록. */
export type OrderedTxHandle = {
  /** runTransaction 콜백에 넘길 transaction. */
  tx: OrderedTx;
  /** 호출 순서 기록 (`"get"` · `"delete"` · `"update"` · `"set"`). */
  calls: string[];
  /** `tx.delete` 에 넘어온 ref 목록 (호출 순). */
  deletes: unknown[];
  /** `tx.update` 에 넘어온 ref · data 목록 (호출 순). */
  updates: Array<{ref: unknown; data: unknown}>;
  /** `tx.set` 에 넘어온 ref · data 목록 (호출 순). */
  sets: Array<{ref: unknown; data: unknown}>;
};

/**
 * 순서 강제 transaction mock 을 만든다.
 *
 * write 가 한 번이라도 호출된 뒤의 `get` 은
 * `Error("READ_AFTER_WRITE: tx.get called after a write")` 로 reject 된다.
 * 그 전의 `get` 은 `calls` 에 `"get"` 을 기록하고 [getImpl] 결과를 돌려준다.
 *
 * @param {function(unknown): unknown} getImpl ref 를 받아 snapshot 모양
 *     객체(`{exists, data}`)를 돌려주는 fixture 함수.
 * @return {OrderedTxHandle} tx 와 호출 · write 기록.
 */
export function createOrderedTx(
  getImpl: (ref: unknown) => unknown,
): OrderedTxHandle {
  let wrote = false;
  const calls: string[] = [];
  const deletes: unknown[] = [];
  const updates: Array<{ref: unknown; data: unknown}> = [];
  const sets: Array<{ref: unknown; data: unknown}> = [];
  const tx: OrderedTx = {
    get: async (ref: unknown): Promise<unknown> => {
      if (wrote) {
        throw new Error("READ_AFTER_WRITE: tx.get called after a write");
      }
      calls.push("get");
      return getImpl(ref);
    },
    delete: (ref: unknown): unknown => {
      wrote = true;
      calls.push("delete");
      deletes.push(ref);
      return tx;
    },
    update: (ref: unknown, data: unknown): unknown => {
      wrote = true;
      calls.push("update");
      updates.push({ref, data});
      return tx;
    },
    set: (ref: unknown, data: unknown): unknown => {
      wrote = true;
      calls.push("set");
      sets.push({ref, data});
      return tx;
    },
  };
  return {tx, calls, deletes, updates, sets};
}
