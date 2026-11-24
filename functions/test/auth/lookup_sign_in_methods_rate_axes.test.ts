/**
 * lookupSignInMethods 호출 횟수 제한 축 특성 시험 (Phase 32 · D-07).
 *
 * 목적: lookup 의 인라인 counter transaction 을 공유 helper
 * (`consumeRateLimitAxes`)로 옮기기 전후에 바깥 동작이 같음을 고정한다.
 * 기존 `lookup_sign_in_methods.test.ts` 는 두 축 동시 초과 · IP 축만 초과 ·
 * transaction reject · IP 없는 축 수 · `get` 순서를 고정하지 않으므로, 그
 * 파일은 바이트 그대로 두고 이 파일이 그 부분을 맡는다. 01 ~ 05 는 옮기기
 * **전** 소스에서 먼저 통과했다(특성 시험).
 *
 * mock: transaction 은 순서 강제 tx(`createOrderedTx` — write 뒤 `get` 이면
 * `READ_AFTER_WRITE`)이고, 콜백을 돌리기 **전에** 호출 기록 참조를 모은다 —
 * 한도를 넘으면 콜백 안에서 throw 할 수 있어, 콜백 뒤에 모으면 「write 0」
 * 단언이 공허해진다. counter 문서는 시험마다 비우는 `Map` 저장소에서 읽는다.
 *
 * 시험 목록:
 *  - T-32-LOOKUP-01: 새 창 + IP — get 두 번(uid → IP) 뒤 set 두 번
 *  - T-32-LOOKUP-02: IP 없음 — uid 축 하나만
 *  - T-32-LOOKUP-03: 두 축 다 넘음 — axis uid · uid 축 count · write 0
 *  - T-32-LOOKUP-04: IP 축만 넘음 — axis ip · write 0
 *  - T-32-LOOKUP-05: transaction reject — internal · lookup_rate_limit_failed
 *  - T-32-LOOKUP-06: 새 창 set 에 만료 시각 = 창 시작 + 60초 (나노초 0)
 */

import type {OrderedTxHandle} from "../mocks/ordered_transaction";

jest.mock("firebase-functions/logger", () => ({
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
  debug: jest.fn(),
  log: jest.fn(),
}));

jest.mock("firebase-functions/params", () => ({
  defineSecret: () => ({value: () => "fake-secret"}),
}));

// firebase-admin/auth — 기본은 계정 없음(`auth/user-not-found`) → null 응답.
const mockGetUserByEmail = jest.fn();
jest.mock("firebase-admin/auth", () => ({
  getAuth: jest.fn(() => ({
    getUserByEmail: mockGetUserByEmail,
  })),
}));

// counter 저장소(경로 → 문서 data) · transaction 기록 · 강제 reject.
const mockStore = new Map<string, Record<string, unknown>>();
const mockTxHandles: OrderedTxHandle[] = [];
let mockTxReject: Error | null = null;

jest.mock("firebase-admin/firestore", () => {
  /** 시험용 Timestamp — `seconds` · `nanoseconds` 만 갖는다. */
  class MockTimestamp {
    /**
     * @param {number} seconds epoch 초.
     * @param {number} nanoseconds 나노초.
     */
    constructor(readonly seconds: number, readonly nanoseconds = 0) {}

    /**
     * 지금 시각 — 나노초를 0 이 아닌 값으로 두어 만료 시각의 「나노초 0」
     * 단언이 공허하지 않게 한다.
     *
     * @return {MockTimestamp} 지금.
     */
    static now(): MockTimestamp {
      return new MockTimestamp(Math.floor(Date.now() / 1000), 123000000);
    }

    /**
     * @param {number} ms epoch 밀리초.
     * @return {MockTimestamp} 그 시각.
     */
    static fromMillis(ms: number): MockTimestamp {
      return new MockTimestamp(Math.floor(ms / 1000), (ms % 1000) * 1e6);
    }

    /**
     * @param {Date} d 시각.
     * @return {MockTimestamp} 그 시각.
     */
    static fromDate(d: Date): MockTimestamp {
      return MockTimestamp.fromMillis(d.getTime());
    }

    /** @return {number} epoch 밀리초. */
    toMillis(): number {
      return this.seconds * 1000 + Math.floor(this.nanoseconds / 1e6);
    }
  }

  return {
    Firestore: class MockFirestore {},
    Timestamp: MockTimestamp,
    FieldValue: {
      serverTimestamp: () => "MOCK_TIMESTAMP",
      increment: (n: number) => ({mockIncrement: n}),
    },
    getFirestore: jest.fn(() => ({
      collection: (name: string) => ({
        doc: (id: string) => ({path: `${name}/${id}`}),
        // identity_index 조회 — 이 시험 경로(계정 없음)에서는 쓰이지 않는다.
        where: () => ({
          where: () => ({
            limit: () => ({
              get: async () => ({empty: true, docs: []}),
            }),
          }),
        }),
      }),
      runTransaction: async (fn: (tx: unknown) => Promise<unknown>) => {
        if (mockTxReject) throw mockTxReject;
        const {createOrderedTx} = jest.requireActual(
          "../mocks/ordered_transaction",
        ) as typeof import("../mocks/ordered_transaction");
        const handle = createOrderedTx((ref: unknown) => {
          const data = mockStore.get((ref as {path: string}).path);
          return {exists: data !== undefined, data: () => data};
        });
        // 콜백 전에 기록 참조를 모은다(콜백 안 throw 에도 기록이 남는다).
        mockTxHandles.push(handle);
        return fn(handle.tx);
      },
    })),
  };
});

// eslint-disable-next-line import/first
import functionsTest from "firebase-functions-test";
// eslint-disable-next-line import/first
import * as logger from "firebase-functions/logger";

const testEnv = functionsTest();

// eslint-disable-next-line import/first
import * as myFunctions from "../../src/index";
// eslint-disable-next-line import/first
import {hashClientIp} from "../../src/shared/client_ip_hash";
// eslint-disable-next-line import/first
import {serializeLogCalls} from "../mocks/log_calls";

const infoMock = logger.info as unknown as jest.Mock;
const warnMock = logger.warn as unknown as jest.Mock;
const errorMock = logger.error as unknown as jest.Mock;
const debugMock = logger.debug as unknown as jest.Mock;
const logMock = logger.log as unknown as jest.Mock;

/** 시험 IP — IP 축 문서 경로는 실제 해시 함수로 만든다. */
const TEST_IP = "203.0.113.9";
const IP_DOC_PATH =
  `rate_limits/lookupSignInMethodsIp:${hashClientIp(TEST_IP)}`;

afterAll(() => testEnv.cleanup());

/**
 * lookupSignInMethods 를 부른다.
 *
 * @param {string} uid 호출자 uid.
 * @param {boolean} withIp true 면 `rawRequest.ip` 를 채운다.
 * @return {Promise<unknown>} callable 응답.
 */
function callLookup(uid: string, withIp: boolean): Promise<unknown> {
  const wrapped = testEnv.wrap(myFunctions.lookupSignInMethods);
  return wrapped({
    auth: {uid},
    app: {appId: "test"},
    data: {email: "a@example.com"},
    rawRequest: withIp ? {ip: TEST_IP} : {},
  } as never) as Promise<unknown>;
}

/**
 * `rate limit exceeded` warn 호출의 둘째 인자(필드)만 모은다.
 *
 * @return {Array<unknown>} 필드 객체 목록.
 */
function exceededWarnFields(): unknown[] {
  return warnMock.mock.calls
    .filter((c) => c[0] === "rate limit exceeded")
    .map((c) => c[1]);
}

/**
 * 하나뿐인 transaction 기록을 돌려준다.
 *
 * @return {OrderedTxHandle} transaction 호출 기록.
 */
function onlyTx(): OrderedTxHandle {
  expect(mockTxHandles).toHaveLength(1);
  return mockTxHandles[0];
}

/**
 * set ref 의 경로를 돌려준다.
 *
 * @param {unknown} ref `tx.set` 에 넘어온 ref.
 * @return {string} 문서 경로.
 */
function refPath(ref: unknown): string {
  return (ref as {path: string}).path;
}

/**
 * set data 의 만료 시각과 창 시작의 초 차이 · 만료 시각 나노초를 읽는다.
 *
 * 둘 중 하나라도 `seconds` 가 숫자가 아니면 null 값을 돌려줘, 만료 시각이
 * 없을 때 TypeError 가 아니라 값 비교 실패로 나게 한다.
 *
 * @param {unknown} data `tx.set` 에 넘어온 data.
 * @return {{gap: (number|null), nanos: (number|null)}} 초 차이 · 나노초.
 */
function readExpireGap(data: unknown): {
  gap: number | null;
  nanos: number | null;
} {
  const d = data as {
    windowStart?: {seconds?: unknown};
    expireAt?: {seconds?: unknown; nanoseconds?: unknown};
  };
  const start = d.windowStart?.seconds;
  const expire = d.expireAt?.seconds;
  if (typeof start !== "number" || typeof expire !== "number") {
    return {gap: null, nanos: null};
  }
  const nanos = d.expireAt?.nanoseconds;
  return {gap: expire - start, nanos: typeof nanos === "number" ? nanos : null};
}

describe("lookupSignInMethods 호출 횟수 제한 축 — 특성 시험", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockStore.clear();
    mockTxHandles.length = 0;
    mockTxReject = null;
    mockGetUserByEmail.mockReset();
    mockGetUserByEmail.mockRejectedValue(
      Object.assign(new Error("no user"), {code: "auth/user-not-found"}),
    );
  });

  it("T-32-LOOKUP-01: 새 창 + IP — get 두 번(uid → IP) 뒤 set 두 번",
    async () => {
      const result = await callLookup("u-lk1", true);

      expect(result).toEqual({existingProvider: null});
      const tx = onlyTx();
      expect(tx.calls).toEqual(["get", "get", "set", "set"]);
      expect(refPath(tx.sets[0].ref)).toBe(
        "rate_limits/lookupSignInMethods:u-lk1",
      );
      expect(
        refPath(tx.sets[1].ref).startsWith(
          "rate_limits/lookupSignInMethodsIp:",
        ),
      ).toBe(true);
      for (const {data} of tx.sets) {
        expect(data).toEqual(expect.objectContaining({count: 1}));
        expect((data as {windowStart?: unknown}).windowStart).toBeDefined();
      }
    });

  it("T-32-LOOKUP-02: IP 없음 — uid 축 하나만", async () => {
    await callLookup("u-lk2", false);

    const tx = onlyTx();
    expect(tx.calls).toEqual(["get", "set"]);
    expect(tx.sets.map((s) => refPath(s.ref))).toEqual([
      "rate_limits/lookupSignInMethods:u-lk2",
    ]);
  });

  it("T-32-LOOKUP-03: 두 축 다 넘음 — axis uid · uid 축 count", async () => {
    const nowSec = Math.floor(Date.now() / 1000);
    mockStore.set("rate_limits/lookupSignInMethods:u-lk3", {
      count: 11,
      windowStart: {seconds: nowSec},
    });
    mockStore.set(IP_DOC_PATH, {count: 61, windowStart: {seconds: nowSec}});

    await expect(callLookup("u-lk3", true)).rejects.toMatchObject({
      code: "resource-exhausted",
      message: "errorTooManyRequests",
    });
    expect(exceededWarnFields()).toEqual([
      {
        event: "email_enumeration_suspected",
        uid: "u-lk3",
        count: 11,
        axis: "uid",
      },
    ]);
    // write 0 — read 둘만 있고 set · update 는 없다.
    expect(onlyTx().calls).toEqual(["get", "get"]);
  });

  it("T-32-LOOKUP-04: IP 축만 넘음 — axis ip", async () => {
    const nowSec = Math.floor(Date.now() / 1000);
    mockStore.set("rate_limits/lookupSignInMethods:u-lk4", {
      count: 3,
      windowStart: {seconds: nowSec},
    });
    mockStore.set(IP_DOC_PATH, {count: 61, windowStart: {seconds: nowSec}});

    await expect(callLookup("u-lk4", true)).rejects.toMatchObject({
      code: "resource-exhausted",
      message: "errorTooManyRequests",
    });
    expect(exceededWarnFields()).toEqual([
      {
        event: "email_enumeration_suspected",
        uid: "u-lk4",
        count: 61,
        axis: "ip",
      },
    ]);
    expect(onlyTx().calls).toEqual(["get", "get"]);
  });

  it("T-32-LOOKUP-05: transaction reject — internal · lookup_rate_limit_failed",
    async () => {
      mockTxReject = Object.assign(new Error("PII_LOOKUP_SENTINEL"), {
        code: "aborted",
      });

      await expect(callLookup("u-lk5", true)).rejects.toMatchObject({
        code: "internal",
        message: "errorUnknown",
      });
      const failed = warnMock.mock.calls.filter(
        (c) => c[0] === "rate limit transaction threw",
      );
      expect(failed).toHaveLength(1);
      expect(failed[0][1]).toEqual({
        event: "lookup_rate_limit_failed",
        uid: "u-lk5",
        code: "aborted",
      });
      const allLogs = serializeLogCalls([
        ...infoMock.mock.calls,
        ...warnMock.mock.calls,
        ...errorMock.mock.calls,
        ...debugMock.mock.calls,
        ...logMock.mock.calls,
      ]);
      expect(allLogs).not.toContain("PII_LOOKUP_SENTINEL");
    });

  it("T-32-LOOKUP-06: 새 창 set 에 만료 시각 = 창 시작 + 60초", async () => {
    await callLookup("u-lk6", true);

    const tx = onlyTx();
    expect(tx.sets).toHaveLength(2);
    expect(tx.sets.map((s) => readExpireGap(s.data))).toEqual([
      {gap: 60, nanos: 0},
      {gap: 60, nanos: 0},
    ]);
  });

  it("T-32-LOOKUP-07: IP 축 한도는 60 — 59 는 통과하고 count 60 으로 쓴다",
    async () => {
      const nowSec = Math.floor(Date.now() / 1000);
      mockStore.set("rate_limits/lookupSignInMethods:u-lk7", {
        count: 3,
        windowStart: {seconds: nowSec},
      });
      mockStore.set(IP_DOC_PATH, {count: 59, windowStart: {seconds: nowSec}});

      // uid 한도(10)를 IP 축에 잘못 쓰면 59 에서 막힌다.
      await expect(callLookup("u-lk7", true)).resolves.toEqual({
        existingProvider: null,
      });
      expect(exceededWarnFields()).toEqual([]);
      const tx = onlyTx();
      expect(tx.calls).toEqual(["get", "get", "update", "update"]);
      const ipUpdate = tx.updates.find((u) => refPath(u.ref) === IP_DOC_PATH);
      expect(ipUpdate?.data).toEqual({count: {mockIncrement: 1}});
    });

  it("T-32-LOOKUP-08: uid 축 한도는 10 — 9 는 통과하고 count 10 으로 쓴다",
    async () => {
      const nowSec = Math.floor(Date.now() / 1000);
      const uidPath = "rate_limits/lookupSignInMethods:u-lk8";
      mockStore.set(uidPath, {count: 9, windowStart: {seconds: nowSec}});

      // 한도가 10 보다 작아지면 9 에서 막힌다(위쪽 11 은 K4 가 잡는다).
      await expect(callLookup("u-lk8", false)).resolves.toEqual({
        existingProvider: null,
      });
      expect(exceededWarnFields()).toEqual([]);
      const tx = onlyTx();
      expect(tx.calls).toEqual(["get", "update"]);
      const uidUpdate = tx.updates.find((u) => refPath(u.ref) === uidPath);
      expect(uidUpdate?.data).toEqual({count: {mockIncrement: 1}});
    });
});
