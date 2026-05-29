/**
 * deleteUserAccount onCall 회귀 테스트 (Phase 16 Plan 16-02 Task 2.1).
 *
 * **Mock 한계 — 실 단말 backend tier UAT (Plan 16-07 A2/A5/A8) 가 ground
 * truth.** 본 test 는 (1) admin.auth().verifyIdToken / deleteUser 의 jest stub
 * + (2) Firestore where + runTransaction mock 으로 시나리오 시뮬레이션.
 * 실 Firestore 의 "all reads before all writes" invariant 는 jest mock 이
 * 강제하지 않으므로 (memory feedback_mock_transaction_constraint) D7 case
 * 는 read/write 호출 순서를 explicit 으로 sentinel 검증한다. 실 단말 backend
 * tier UAT (Plan 16-07 A2/A5/A8) 와 Firebase Emulator integration test 가
 * 진짜 contract.
 *
 * Task 2.1 시나리오 (D1-D8):
 *  - D1: happy native — Firestore atomic delete + Auth delete
 *  - D2: happy Custom Token — identity_index 2건 + users delete + Auth delete
 *  - D3: idempotent retry (auth/user-not-found) — Pitfall 1 회피
 *  - D4: stale auth_time → unauthenticated
 *  - D5: uid mismatch → permission-denied
 *  - D6: revoked idToken → unauthenticated
 *  - D7: Pitfall 2 회귀 가드 — identity_index where 가 runTransaction 전 호출
 *  - D8: deleteUser other error → internal + logger.error
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

// firebase-admin/auth — verifyIdToken + deleteUser.
const mockVerifyIdToken = jest.fn();
const mockDeleteUser = jest.fn();
jest.mock("firebase-admin/auth", () => ({
  getAuth: jest.fn(() => ({
    verifyIdToken: mockVerifyIdToken,
    deleteUser: mockDeleteUser,
  })),
}));

// firebase-admin/firestore — where + runTransaction.
const mockWhereGet = jest.fn();
const mockTxDelete = jest.fn();
// call order sentinel — D7 invariant 검증용.
const callOrder: string[] = [];
jest.mock("firebase-admin/firestore", () => {
  return {
    Firestore: class MockFirestore {},
    getFirestore: jest.fn(() => ({
      collection: (name: string) => ({
        doc: (id?: string) => ({
          collectionName: name,
          docId: id,
          label: `${name}/${id ?? "?"}`,
        }),
        where: () => ({
          // chained where (firebaseUid + provider in [...])
          get: () => {
            callOrder.push(`where:${name}:get`);
            return mockWhereGet();
          },
        }),
      }),
      runTransaction: async (fn: (t: unknown) => Promise<unknown>) => {
        callOrder.push("runTransaction:enter");
        const result = await fn({
          delete: (ref: unknown) => {
            callOrder.push("tx.delete");
            return mockTxDelete(ref);
          },
        });
        callOrder.push("runTransaction:exit");
        return result;
      },
    })),
    FieldValue: {
      serverTimestamp: () => "MOCK_TIMESTAMP",
    },
  };
});

// eslint-disable-next-line import/first
import functionsTest from "firebase-functions-test";
// eslint-disable-next-line import/first
import * as logger from "firebase-functions/logger";
// eslint-disable-next-line import/first
import {HttpsError} from "firebase-functions/https";

const testEnv = functionsTest();

// eslint-disable-next-line import/first
import * as myFunctions from "../../src/index";

const infoMock = logger.info as unknown as jest.Mock;
const warnMock = logger.warn as unknown as jest.Mock;
const errorMock = logger.error as unknown as jest.Mock;
const debugMock = logger.debug as unknown as jest.Mock;
const logMock = logger.log as unknown as jest.Mock;

afterAll(() => testEnv.cleanup());

const freshAuthTime = (): number => Math.floor(Date.now() / 1000) - 60;
const staleAuthTime = (): number => Math.floor(Date.now() / 1000) - 600;

describe("deleteUserAccount onCall — Task 2.1 (D1-D8)", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockVerifyIdToken.mockReset();
    mockDeleteUser.mockReset();
    mockWhereGet.mockReset();
    mockTxDelete.mockReset();
    callOrder.length = 0;
  });

  it("D1: happy native — Firestore atomic delete + Auth delete", async () => {
    mockVerifyIdToken.mockResolvedValue({
      uid: "uid-D1",
      auth_time: freshAuthTime(),
    });
    // identity_index where 결과 (native — 1건만 가정).
    mockWhereGet.mockResolvedValue({docs: [{id: "google:abc"}]});
    mockDeleteUser.mockResolvedValue(undefined);

    const wrapped = testEnv.wrap(myFunctions.deleteUserAccount);
    const result = (await wrapped({
      auth: {uid: "uid-D1"},
      app: {appId: "test"},
      data: {idToken: "FAKE_FRESH"},
    } as never)) as {ok: true};

    expect(result.ok).toBe(true);
    expect(mockDeleteUser).toHaveBeenCalledWith("uid-D1");
    expect(infoMock).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "delete_user_firestore_done",
        uid: "uid-D1",
        identityCount: 1,
      }),
      expect.any(String),
    );
    expect(infoMock).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "delete_user_auth_done",
        uid: "uid-D1",
      }),
      expect.any(String),
    );
  });

  // eslint-disable-next-line max-len
  it("D2: happy Custom Token — identity_index 2건 + users delete + Auth delete", async () => {
    mockVerifyIdToken.mockResolvedValue({
      uid: "uid-D2",
      auth_time: freshAuthTime(),
    });
    mockWhereGet.mockResolvedValue({
      docs: [{id: "kakao:111"}, {id: "naver:222"}],
    });
    mockDeleteUser.mockResolvedValue(undefined);

    const wrapped = testEnv.wrap(myFunctions.deleteUserAccount);
    const result = (await wrapped({
      auth: {uid: "uid-D2"},
      app: {appId: "test"},
      data: {idToken: "FAKE_FRESH"},
    } as never)) as {ok: true};

    expect(result.ok).toBe(true);
    // tx.delete 3회 (2 identity_index + 1 users).
    expect(mockTxDelete).toHaveBeenCalledTimes(3);
    expect(mockDeleteUser).toHaveBeenCalledWith("uid-D2");
    expect(infoMock).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "delete_user_firestore_done",
        identityCount: 2,
      }),
      expect.any(String),
    );
  });

  // eslint-disable-next-line max-len
  it("D3: idempotent retry (auth/user-not-found) → success (Pitfall 1 회피)", async () => {
    mockVerifyIdToken.mockResolvedValue({
      uid: "uid-D3",
      auth_time: freshAuthTime(),
    });
    mockWhereGet.mockResolvedValue({docs: []});
    // admin.auth().deleteUser 가 auth/user-not-found throw — 이미 삭제된 user.
    mockDeleteUser.mockRejectedValue(
      Object.assign(new Error("user not found"), {
        code: "auth/user-not-found",
      }),
    );

    const wrapped = testEnv.wrap(myFunctions.deleteUserAccount);
    const result = (await wrapped({
      auth: {uid: "uid-D3"},
      app: {appId: "test"},
      data: {idToken: "FAKE_FRESH"},
    } as never)) as {ok: true};

    expect(result.ok).toBe(true);
    // Pitfall 1 회피 evidence — already_done 분기 info log.
    expect(infoMock).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "delete_user_auth_already_done",
        uid: "uid-D3",
      }),
      expect.any(String),
    );
  });

  it("D4: stale auth_time (> 5분) → unauthenticated", async () => {
    mockVerifyIdToken.mockResolvedValue({
      uid: "uid-D4",
      auth_time: staleAuthTime(),
    });

    const wrapped = testEnv.wrap(myFunctions.deleteUserAccount);
    const promise = wrapped({
      auth: {uid: "uid-D4"},
      app: {appId: "test"},
      data: {idToken: "STALE_TOKEN"},
    } as never);
    await expect(promise).rejects.toBeInstanceOf(HttpsError);
    await expect(promise).rejects.toMatchObject({
      code: "unauthenticated",
      message: "errorReauthenticationRequired",
    });
    expect(mockDeleteUser).not.toHaveBeenCalled();
  });

  it("D5: uid mismatch → permission-denied", async () => {
    mockVerifyIdToken.mockResolvedValue({
      uid: "DIFFERENT-UID",
      auth_time: freshAuthTime(),
    });

    const wrapped = testEnv.wrap(myFunctions.deleteUserAccount);
    const promise = wrapped({
      auth: {uid: "uid-D5"},
      app: {appId: "test"},
      data: {idToken: "FAKE"},
    } as never);
    await expect(promise).rejects.toMatchObject({
      code: "permission-denied",
      message: "errorUnauthenticated",
    });
    expect(mockDeleteUser).not.toHaveBeenCalled();
  });

  // eslint-disable-next-line max-len
  it("D6: revoked idToken → verifyIdToken throws → unauthenticated", async () => {
    mockVerifyIdToken.mockRejectedValue(
      Object.assign(new Error("revoked"), {code: "auth/id-token-revoked"}),
    );

    const wrapped = testEnv.wrap(myFunctions.deleteUserAccount);
    const promise = wrapped({
      auth: {uid: "uid-D6"},
      app: {appId: "test"},
      data: {idToken: "REVOKED"},
    } as never);
    await expect(promise).rejects.toMatchObject({
      code: "unauthenticated",
      message: "errorReauthenticationRequired",
    });
    expect(warnMock).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "delete_user_id_token_verify_failed",
        code: "auth/id-token-revoked",
      }),
      expect.any(String),
    );
  });

  // eslint-disable-next-line max-len
  it("D7: Pitfall 2 invariant — identity_index where 가 runTransaction 전 호출", async () => {
    mockVerifyIdToken.mockResolvedValue({
      uid: "uid-D7",
      auth_time: freshAuthTime(),
    });
    mockWhereGet.mockResolvedValue({
      docs: [{id: "kakao:777"}, {id: "line:888"}],
    });
    mockDeleteUser.mockResolvedValue(undefined);

    const wrapped = testEnv.wrap(myFunctions.deleteUserAccount);
    await wrapped({
      auth: {uid: "uid-D7"},
      app: {appId: "test"},
      data: {idToken: "FAKE_FRESH"},
    } as never);

    // Pitfall 2 회귀 가드 — where 호출은 runTransaction 호출보다 앞.
    const whereIdx = callOrder.indexOf("where:identity_index:get");
    const txEnterIdx = callOrder.indexOf("runTransaction:enter");
    expect(whereIdx).toBeGreaterThanOrEqual(0);
    expect(txEnterIdx).toBeGreaterThan(whereIdx);
    // transaction body 안에는 write only — 추가 get 호출 없음.
    const txExitIdx = callOrder.indexOf("runTransaction:exit");
    const insideTx = callOrder.slice(txEnterIdx + 1, txExitIdx);
    expect(insideTx.every((c) => c === "tx.delete")).toBe(true);
    expect(insideTx).toContain("tx.delete");
  });

  // eslint-disable-next-line max-len
  it("D8: deleteUser other error → internal + logger.error + PII redaction", async () => {
    mockVerifyIdToken.mockResolvedValue({
      uid: "uid-D8",
      auth_time: freshAuthTime(),
    });
    mockWhereGet.mockResolvedValue({docs: []});
    mockDeleteUser.mockRejectedValue(
      Object.assign(new Error("PII_DELETE_BODY_SENTINEL"), {
        code: "auth/internal-error",
      }),
    );

    const wrapped = testEnv.wrap(myFunctions.deleteUserAccount);
    const promise = wrapped({
      auth: {uid: "uid-D8"},
      app: {appId: "test"},
      data: {idToken: "FAKE_FRESH"},
    } as never);
    await expect(promise).rejects.toMatchObject({
      code: "internal",
      message: "errorUnknown",
    });
    expect(errorMock).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "delete_user_auth_failed",
        uid: "uid-D8",
        code: "auth/internal-error",
      }),
      expect.any(String),
    );
    // PII redaction sentinel — err.message 본문 절대 미노출.
    const allLogCalls = [
      ...infoMock.mock.calls,
      ...warnMock.mock.calls,
      ...errorMock.mock.calls,
      ...debugMock.mock.calls,
      ...logMock.mock.calls,
    ];
    for (const args of allLogCalls) {
      expect(JSON.stringify(args)).not.toContain("PII_DELETE_BODY_SENTINEL");
    }
  });
});
