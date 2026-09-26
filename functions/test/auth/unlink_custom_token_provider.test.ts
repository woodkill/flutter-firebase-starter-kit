/**
 * unlinkCustomTokenProvider onCall 회귀 테스트 (Phase 16.8 plan 02 · SOCL-15).
 *
 * **Mock 한계:** 실 Firestore 의 「all reads before all writes」 invariant 는
 * 일반 jest mock 이 강제하지 않는다 (memory feedback_mock_transaction_constraint).
 * 본 파일은 `test/mocks/ordered_transaction.ts` 의 순서 강제 tx 를
 * runTransaction 콜백에 넘겨, write 뒤 `tx.get` 이 오면 `READ_AFTER_WRITE`
 * 로 실패하게 만든다 — happy path 통과 자체가 순서 증거다 (U5).
 *
 * 시나리오 (U1~U11):
 *  - U1: happy — idx 삭제 + linkedProviders 필터 재기록 + providerLinkedAt dot 삭제
 *  - U2: last credential — 남은 자격증명 0 → failed-precondition(last_credential)
 *  - U3: anonymous caller → failed-precondition(anonymous_caller)
 *  - U4: not-found — idx 0 + 배열 항목 0
 *  - U5: read-before-write — ordered tx 호출 순서 + 메타 케이스
 *  - U6: signUpProviderId 부재 — 어느 write 인자에도 없음
 *  - U7: slug — 목록 밖 · 누락 → invalid-argument / 목록 안(naver) → 검증 통과
 *  - U8: tx throw → internal + fingerprint 로그
 *  - U9: other uid — tx 재읽기 소유자가 다르면 삭제 0 (IDOR)
 *  - U10: unauthenticated
 *  - U11: self-heal — idx 0 + 배열 항목만 남은 부분 상태 → 정리 + ok
 *
 * 모든 케이스 뒤 PII sentinel — 5 logger mock 의 모든 호출 인자에
 * provider sub · email fixture 값(`PII_UNLINK_SENTINEL`) 이 없어야 한다.
 */

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

// firebase-admin/auth — getUser 만 (해제는 verifyIdToken 을 쓰지 않는다 · D-06).
const mockGetUser = jest.fn();
jest.mock("firebase-admin/auth", () => ({
  getAuth: jest.fn(() => ({getUser: mockGetUser})),
}));

// firebase-admin/firestore — collection.doc · where · runTransaction.
// jest hoisting: factory 가 참조하는 바깥 변수는 이름이 `mock` 으로 시작해야
// 한다. 모두 호출 시점에 지연 참조한다.
const mockWhere = jest.fn();
const mockWhereGet = jest.fn();
let mockOrdered: OrderedTxHandle;
jest.mock("firebase-admin/firestore", () => ({
  Firestore: class MockFirestore {},
  getFirestore: jest.fn(() => ({
    collection: (name: string) => ({
      doc: (id?: string) => ({label: `${name}/${id ?? "?"}`}),
      where: (...args: unknown[]) => {
        mockWhere(name, ...args);
        return {get: () => mockWhereGet()};
      },
    }),
    runTransaction: async (fn: (t: unknown) => Promise<unknown>) =>
      fn(mockOrdered.tx),
  })),
  FieldValue: {
    serverTimestamp: () => "MOCK_TIMESTAMP",
    delete: () => "MOCK_DELETE",
  },
}));

// eslint-disable-next-line import/first
import functionsTest from "firebase-functions-test";
// eslint-disable-next-line import/first
import * as logger from "firebase-functions/logger";
// eslint-disable-next-line import/first
import {HttpsError} from "firebase-functions/https";
// eslint-disable-next-line import/first
import {createOrderedTx} from "../mocks/ordered_transaction";
// eslint-disable-next-line import/first
import type {OrderedTxHandle} from "../mocks/ordered_transaction";

const testEnv = functionsTest();

// eslint-disable-next-line import/first
import * as myFunctions from "../../src/index";

const infoMock = logger.info as unknown as jest.Mock;
const warnMock = logger.warn as unknown as jest.Mock;
const errorMock = logger.error as unknown as jest.Mock;
const debugMock = logger.debug as unknown as jest.Mock;
const logMock = logger.log as unknown as jest.Mock;

afterAll(() => testEnv.cleanup());

/** provider sub · email fixture 값 — 어느 로그 · 오류 본문에도 나오면 안 된다. */
const SENTINEL = "PII_UNLINK_SENTINEL";

/** `identity_index` 문서 fixture (where 결과 · tx 재읽기 공통). */
type IdxFixture = {
  provider: string;
  firebaseUid: string;
};

/** 한 케이스의 서버 상태 fixture. */
type Arrangement = {
  uid: string;
  /** Admin `getUser(uid).providerData` 의 providerId 목록. */
  nativeProviderIds: string[];
  /** tx 밖 `where firebaseUid == uid` 결과. */
  idx: IdxFixture[];
  /** tx 안 재읽기 결과 덮어쓰기 (문서 id → 값 · null = 문서 사라짐). */
  txIdxOverride?: Record<string, IdxFixture | null>;
  /** `users/{uid}` 문서 (undefined = 부재). */
  user?: Record<string, unknown>;
};

/**
 * idx 문서 id 를 만든다 (`{provider}:{sub}` — sub 는 sentinel).
 *
 * @param {string} provider provider slug.
 * @return {string} 문서 id.
 */
function idxDocId(provider: string): string {
  return `${provider}:${SENTINEL}-${provider}`;
}

/**
 * getUser · where · ordered tx fixture 를 한 번에 구성한다.
 *
 * @param {Arrangement} a 서버 상태 fixture.
 */
function arrange(a: Arrangement): void {
  mockGetUser.mockResolvedValue({
    uid: a.uid,
    email: `${SENTINEL}@example.com`,
    providerData: a.nativeProviderIds.map((providerId) => ({
      providerId,
      uid: `${SENTINEL}-${providerId}`,
      email: `${SENTINEL}@example.com`,
    })),
  });
  mockWhereGet.mockResolvedValue({
    docs: a.idx.map((d) => ({
      id: idxDocId(d.provider),
      ref: {label: `identity_index/${idxDocId(d.provider)}`},
      data: () => ({
        firebaseUid: d.firebaseUid,
        provider: d.provider,
        providerUserId: `${SENTINEL}-${d.provider}`,
      }),
    })),
  });
  const docs = new Map<string, Record<string, unknown>>();
  for (const d of a.idx) {
    const id = idxDocId(d.provider);
    const override = a.txIdxOverride?.[id];
    if (override === null) continue;
    const value = override ?? d;
    docs.set(`identity_index/${id}`, {
      firebaseUid: value.firebaseUid,
      provider: value.provider,
      providerUserId: `${SENTINEL}-${value.provider}`,
    });
  }
  if (a.user !== undefined) docs.set(`users/${a.uid}`, a.user);
  mockOrdered = createOrderedTx((ref: unknown) => {
    const label = (ref as {label: string}).label;
    const data = docs.get(label);
    // 실 DocumentSnapshot 처럼 ref 를 싣는다 (tx.delete(snap.ref) 경로).
    return {exists: data !== undefined, ref, data: () => data};
  });
}

/**
 * 정식 로그인(Custom Token 세션) caller 로 callable 을 호출한다.
 *
 * @param {string} uid caller uid.
 * @param {unknown} data callable data.
 * @return {Promise<unknown>} callable 결과.
 */
function callAsSignedIn(uid: string, data: unknown): Promise<unknown> {
  const wrapped = testEnv.wrap(myFunctions.unlinkCustomTokenProvider);
  return wrapped({
    auth: {uid, token: {firebase: {sign_in_provider: "custom"}}},
    app: {appId: "test"},
    data,
  } as never) as Promise<unknown>;
}

/**
 * 거부된 callable 의 HttpsError 를 꺼내고 message · details 에 PII 가
 * 없음을 단언한다.
 *
 * @param {Promise<unknown>} promise callable 호출.
 * @return {Promise<HttpsError>} 던져진 HttpsError.
 */
async function captureHttpsError(
  promise: Promise<unknown>,
): Promise<HttpsError> {
  const err = await promise.then(
    () => undefined,
    (e: unknown) => e,
  );
  expect(err).toBeInstanceOf(HttpsError);
  const httpsErr = err as HttpsError;
  expect(
    JSON.stringify({message: httpsErr.message, details: httpsErr.details}),
  ).not.toContain(SENTINEL);
  return httpsErr;
}

/**
 * 성공 로그 payload 를 꺼낸다.
 *
 * @return {Record<string, unknown> | undefined} 성공 이벤트 payload.
 */
function successLogPayload(): Record<string, unknown> | undefined {
  const call = infoMock.mock.calls.find(
    (c: unknown[]) =>
      (c[0] as {event?: unknown})?.event ===
      "unlink_custom_token_provider_succeeded",
  );
  return call?.[0] as Record<string, unknown> | undefined;
}

/**
 * U1 fixture — google native + kakao CT(대상) + line 항목.
 *
 * @param {string} uid caller uid.
 * @return {Arrangement} 서버 상태 fixture.
 */
const u1Arrangement = (uid: string): Arrangement => ({
  uid,
  nativeProviderIds: ["google.com"],
  idx: [{provider: "kakao", firebaseUid: uid}],
  user: {
    signUpProviderId: "kakao",
    linkedProviders: [
      {providerId: "kakao", providerUserId: `${SENTINEL}-kakao`},
      {providerId: "line", providerUserId: `${SENTINEL}-line`},
    ],
    providerLinkedAt: {kakao: "T1", line: "T2"},
  },
});

describe("unlinkCustomTokenProvider onCall — Phase 16.8 (U1~U11)", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockGetUser.mockReset();
    mockWhere.mockReset();
    mockWhereGet.mockReset();
    mockOrdered = createOrderedTx(() => ({
      exists: false,
      data: () => undefined,
    }));
  });

  afterEach(() => {
    // PII sentinel — provider sub · email 은 어느 로그에도 없다 (D-51).
    const allLogCalls = [
      ...infoMock.mock.calls,
      ...warnMock.mock.calls,
      ...errorMock.mock.calls,
      ...debugMock.mock.calls,
      ...logMock.mock.calls,
    ];
    for (const args of allLogCalls) {
      expect(JSON.stringify(args)).not.toContain("PII_UNLINK_SENTINEL");
    }
  });

  // eslint-disable-next-line max-len
  it("U1: happy — idx 삭제 + linkedProviders 필터 재기록 + providerLinkedAt dot 삭제", async () => {
    arrange(u1Arrangement("uid-U1"));

    const result = await callAsSignedIn("uid-U1", {provider: "kakao"});

    expect(result).toEqual({ok: true});
    expect(mockOrdered.deletes).toEqual([
      {label: `identity_index/${idxDocId("kakao")}`},
    ]);
    expect(mockOrdered.updates).toHaveLength(1);
    expect(mockOrdered.sets).toHaveLength(0);
    const update = mockOrdered.updates[0];
    expect(update.ref).toEqual({label: "users/uid-U1"});
    const payload = update.data as Record<string, unknown>;
    expect(payload.linkedProviders).toEqual([
      {providerId: "line", providerUserId: `${SENTINEL}-line`},
    ]);
    // dot 키 1개만 FieldValue.delete() — 맵 통째 덮어쓰기 금지 (T-16.8-12).
    expect(Object.keys(payload)).toContain("providerLinkedAt.kakao");
    expect(Object.keys(payload)).not.toContain("providerLinkedAt");
    expect(payload["providerLinkedAt.kakao"]).toBe("MOCK_DELETE");
    expect(payload).not.toHaveProperty("signUpProviderId");
    // 성공 로그 — {event, uid, provider, 계수} 뿐.
    expect(infoMock).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "unlink_custom_token_provider_succeeded",
        uid: "uid-U1",
        provider: "kakao",
        removedIdentityCount: 1,
        removedLinkedEntryCount: 1,
      }),
      expect.any(String),
    );
    expect(Object.keys(successLogPayload() ?? {}).sort()).toEqual([
      "event",
      "provider",
      "removedIdentityCount",
      "removedLinkedEntryCount",
      "uid",
    ]);
    // 소유 후보는 request.auth.uid 로만 조회한다 (IDOR — 입력 uid 0).
    expect(mockWhere).toHaveBeenCalledWith(
      "identity_index",
      "firebaseUid",
      "==",
      "uid-U1",
    );
    expect(mockGetUser).toHaveBeenCalledWith("uid-U1");
  });

  // eslint-disable-next-line max-len
  it("U2: last credential — providerData 0 + 대상 idx 만 → code=failed-precondition", async () => {
    arrange({
      uid: "uid-U2",
      nativeProviderIds: [],
      idx: [{provider: "kakao", firebaseUid: "uid-U2"}],
      user: {
        linkedProviders: [
          {providerId: "kakao", providerUserId: `${SENTINEL}-kakao`},
        ],
      },
    });

    const err = await captureHttpsError(
      callAsSignedIn("uid-U2", {provider: "kakao"}),
    );

    expect(err).toMatchObject({
      code: "failed-precondition",
      message: "errorUnlinkLastCredential",
      details: {reason: "last_credential"},
    });
    expect(mockOrdered.deletes).toHaveLength(0);
    expect(mockOrdered.updates).toHaveLength(0);
    expect(successLogPayload()).toBeUndefined();
  });

  // eslint-disable-next-line max-len
  it("U3: anonymous caller → code=failed-precondition · anonymous_caller", async () => {
    const wrapped = testEnv.wrap(myFunctions.unlinkCustomTokenProvider);
    const err = await captureHttpsError(
      wrapped({
        auth: {
          uid: "anon-U3",
          token: {firebase: {sign_in_provider: "anonymous"}},
        },
        app: {appId: "test"},
        data: {provider: "kakao"},
      } as never) as Promise<unknown>,
    );

    expect(err).toMatchObject({
      code: "failed-precondition",
      message: "errorAnonymousUnlinkNotAllowed",
      details: {reason: "anonymous_caller"},
    });
    expect(mockGetUser).not.toHaveBeenCalled();
    expect(mockWhereGet).not.toHaveBeenCalled();
    expect(mockOrdered.calls).toHaveLength(0);
  });

  it("U4: not-found — idx 0 + 배열 항목 0 → not-found · write 0", async () => {
    arrange({
      uid: "uid-U4",
      nativeProviderIds: ["google.com"],
      idx: [],
      user: {
        linkedProviders: [
          {providerId: "line", providerUserId: `${SENTINEL}-line`},
        ],
        providerLinkedAt: {line: "T2"},
      },
    });

    const err = await captureHttpsError(
      callAsSignedIn("uid-U4", {provider: "kakao"}),
    );

    expect(err).toMatchObject({
      code: "not-found",
      message: "errorProviderNotLinked",
    });
    expect(mockOrdered.deletes).toHaveLength(0);
    expect(mockOrdered.updates).toHaveLength(0);
  });

  // eslint-disable-next-line max-len
  it("U5: read-before-write — 모든 tx.get 이 첫 write 보다 앞 · READ_AFTER_WRITE 0", async () => {
    arrange({
      ...u1Arrangement("uid-U5"),
      idx: [
        {provider: "kakao", firebaseUid: "uid-U5"},
        {provider: "line", firebaseUid: "uid-U5"},
      ],
    });

    const result = await callAsSignedIn("uid-U5", {provider: "kakao"});

    expect(result).toEqual({ok: true});
    const calls = mockOrdered.calls;
    const firstWrite = calls.findIndex((c) => c !== "get");
    const lastGet = calls.lastIndexOf("get");
    expect(firstWrite).toBeGreaterThan(-1);
    expect(lastGet).toBeLessThan(firstWrite);
    // 대상 + 다른 provider idx 2건 + users 1건 = get 3회 (tx 안 재계수).
    expect(calls.filter((c) => c === "get")).toHaveLength(3);
    expect(errorMock).not.toHaveBeenCalled();
  });

  // eslint-disable-next-line max-len
  it("U5: meta — createOrderedTx 는 write 뒤 get 을 READ_AFTER_WRITE 로 거부한다", async () => {
    const handle = createOrderedTx(() => ({exists: false}));
    await handle.tx.get({label: "a"});
    handle.tx.delete({label: "a"});
    await expect(handle.tx.get({label: "b"})).rejects.toThrow(
      "READ_AFTER_WRITE",
    );
    expect(handle.calls).toEqual(["get", "delete"]);
  });

  // eslint-disable-next-line max-len
  it("U6: signUpProviderId 부재 — delete · update 어느 인자에도 가입 수단 필드 0", async () => {
    arrange(u1Arrangement("uid-U6"));

    await callAsSignedIn("uid-U6", {provider: "kakao"});

    expect(mockOrdered.updates).toHaveLength(1);
    for (const u of mockOrdered.updates) {
      expect(u.data).not.toHaveProperty("signUpProviderId");
      expect(JSON.stringify(u)).not.toContain("signUpProviderId");
    }
    for (const d of mockOrdered.deletes) {
      expect(JSON.stringify(d)).not.toContain("signUpProviderId");
    }
  });

  it("U7: slug — 목록 밖(google) → invalid-argument", async () => {
    const err = await captureHttpsError(
      callAsSignedIn("uid-U7", {provider: "google"}),
    );
    expect(err).toMatchObject({code: "invalid-argument"});
    expect(mockGetUser).not.toHaveBeenCalled();
  });

  it("U7: slug — provider 누락 → invalid-argument", async () => {
    const err = await captureHttpsError(callAsSignedIn("uid-U7", {}));
    expect(err).toMatchObject({code: "invalid-argument"});
    expect(mockGetUser).not.toHaveBeenCalled();
  });

  // eslint-disable-next-line max-len
  it("U7: slug — naver 는 목록 안이라 검증 통과 → idx 0 · 배열 0 이면 not-found (D-04)", async () => {
    arrange({
      uid: "uid-U7",
      nativeProviderIds: ["google.com"],
      idx: [],
      user: {linkedProviders: []},
    });
    const err = await captureHttpsError(
      callAsSignedIn("uid-U7", {provider: "naver"}),
    );
    expect(err).toMatchObject({code: "not-found"});
    expect(mockGetUser).toHaveBeenCalledWith("uid-U7");
  });

  // eslint-disable-next-line max-len
  it("U8: tx throw → internal + unlink_transaction_failed fingerprint 로그", async () => {
    arrange(u1Arrangement("uid-U8"));
    mockOrdered = createOrderedTx(() => {
      throw Object.assign(new Error(`${SENTINEL} boom`), {code: "aborted"});
    });

    const err = await captureHttpsError(
      callAsSignedIn("uid-U8", {provider: "kakao"}),
    );

    expect(err).toMatchObject({code: "internal", message: "errorUnknown"});
    expect(errorMock).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "unlink_transaction_failed",
        uid: "uid-U8",
        code: "aborted",
      }),
      expect.any(String),
    );
    expect(mockOrdered.deletes).toHaveLength(0);
    expect(mockOrdered.updates).toHaveLength(0);
  });

  // eslint-disable-next-line max-len
  it("U8: precheck throw → internal + unlink_precheck_failed fingerprint 로그", async () => {
    arrange(u1Arrangement("uid-U8b"));
    mockGetUser.mockReset();
    mockGetUser.mockRejectedValue(
      Object.assign(new Error(`${SENTINEL} admin`), {
        code: "auth/internal-error",
      }),
    );

    const err = await captureHttpsError(
      callAsSignedIn("uid-U8b", {provider: "kakao"}),
    );

    expect(err).toMatchObject({code: "internal", message: "errorUnknown"});
    expect(errorMock).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "unlink_precheck_failed",
        uid: "uid-U8b",
        code: "auth/internal-error",
      }),
      expect.any(String),
    );
    expect(mockOrdered.calls).toHaveLength(0);
  });

  // eslint-disable-next-line max-len
  it("U9: other uid — tx 재읽기 소유자가 다르면 삭제 0 · 항목 없으면 not-found", async () => {
    arrange({
      uid: "uid-U9",
      nativeProviderIds: ["google.com"],
      idx: [{provider: "kakao", firebaseUid: "uid-U9"}],
      txIdxOverride: {
        [idxDocId("kakao")]: {provider: "kakao", firebaseUid: "other-uid"},
      },
      user: {linkedProviders: []},
    });

    const err = await captureHttpsError(
      callAsSignedIn("uid-U9", {provider: "kakao"}),
    );

    expect(err).toMatchObject({code: "not-found"});
    expect(mockOrdered.deletes).toHaveLength(0);
    expect(mockOrdered.updates).toHaveLength(0);
  });

  it("U10: unauthenticated — auth 없음 → unauthenticated", async () => {
    const wrapped = testEnv.wrap(myFunctions.unlinkCustomTokenProvider);
    const err = await captureHttpsError(
      wrapped({
        app: {appId: "test"},
        data: {provider: "kakao"},
      } as never) as Promise<unknown>,
    );
    expect(err).toMatchObject({
      code: "unauthenticated",
      message: "errorUnauthenticated",
    });
    expect(mockGetUser).not.toHaveBeenCalled();
  });

  // eslint-disable-next-line max-len
  it("U11: self-heal — idx 0 + 배열 항목만 남은 부분 상태 → 정리 + {ok: true}", async () => {
    arrange({
      uid: "uid-U11",
      nativeProviderIds: ["google.com"],
      idx: [],
      user: {
        linkedProviders: [
          {providerId: "kakao", providerUserId: `${SENTINEL}-kakao`},
        ],
        providerLinkedAt: {kakao: "T1"},
      },
    });

    const result = await callAsSignedIn("uid-U11", {provider: "kakao"});

    expect(result).toEqual({ok: true});
    expect(mockOrdered.deletes).toHaveLength(0);
    expect(mockOrdered.updates).toHaveLength(1);
    const payload = mockOrdered.updates[0].data as Record<string, unknown>;
    expect(payload.linkedProviders).toEqual([]);
    expect(payload["providerLinkedAt.kakao"]).toBe("MOCK_DELETE");
    expect(infoMock).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "unlink_custom_token_provider_succeeded",
        removedIdentityCount: 0,
        removedLinkedEntryCount: 1,
      }),
      expect.any(String),
    );
  });
});
