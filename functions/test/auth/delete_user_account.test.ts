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
 *
 * Phase 15 리뷰 WR-09 회귀 가드 (D9-D11):
 *  - D9: Auth 삭제 실패 시 Firestore 는 손대지 않는다 (data loss 차단)
 *  - D10: Firestore cleanup 실패 → 고아 문서 로그 + ok:true (계정은 삭제됨)
 *  - D11: 호출 순서 sentinel — deleteUser 가 identity_index where 보다 먼저
 *
 * Phase 17 탈퇴 cascade (D-16 · D-40 · D-02 정정) — T-17-DEL 시리즈:
 *  - T-17-DEL-01: Storage prefix 삭제 → Auth → identity_index 순서 (관통)
 *  - T-17-DEL-02: Storage 실패(Error) → unavailable · storage_cleanup_failed
 *  - T-17-DEL-03: Storage 실패(force 의 Error[]) → 같은 결과 + 실패 수
 *  - T-17-DEL-04: fcmTokens 서브컬렉션 recursiveDelete — 트랜잭션 뒤 1회
 *  - T-17-DEL-05: recursiveDelete 실패 → orphan 로그 + ok:true
 *  - T-17-DEL-06: 멱등 재시도(user-not-found) 전 단계 진행 · 로그 경로 0
 *
 * Phase 17 리뷰 WR-01 — 404 는 「지울 것 없음」 (영구 오류로 탈퇴를 막지 않음):
 *  - T-17-DEL-07: 단일 404(기본 버킷 없음) → warn 로그 · Auth · Firestore 진행
 *  - T-17-DEL-08: 전부 404 인 Error[](이미 삭제됨) → warn 로그 · 진행
 *  - T-17-DEL-09: 404 와 다른 code 가 섞인 Error[] → 기존대로 중단
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
    // WR-09: Auth 삭제 시점을 Firestore 호출과 같은 축에 기록한다 (D11).
    deleteUser: (uid: string) => {
      callOrder.push("auth.deleteUser");
      return mockDeleteUser(uid);
    },
  })),
}));

// firebase-admin/firestore — where + runTransaction.
const mockWhereGet = jest.fn();
const mockTxDelete = jest.fn();
const mockRecursiveDelete = jest.fn();
// call order sentinel — D7 / D11 invariant 검증용.
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
          // 서브컬렉션 ref — fcmTokens recursiveDelete 대상 식별용.
          collection: (sub: string) => ({
            label: `${name}/${id ?? "?"}/${sub}`,
          }),
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
      // Phase 17 D-02 정정 — fcmTokens 서브컬렉션 재귀 삭제.
      recursiveDelete: (ref: unknown) => {
        callOrder.push("recursiveDelete");
        return mockRecursiveDelete(ref);
      },
    })),
    FieldValue: {
      serverTimestamp: () => "MOCK_TIMESTAMP",
    },
  };
});

// firebase-admin/storage — bucket().deleteFiles (Phase 17 D-40 Step 1.5).
const mockDeleteFiles = jest.fn();
jest.mock("firebase-admin/storage", () => ({
  getStorage: jest.fn(() => ({
    bucket: () => ({
      // Storage 삭제 시점을 Auth · Firestore 호출과 같은 축에 기록한다.
      deleteFiles: (query: unknown) => {
        callOrder.push("storage.deleteFiles");
        return mockDeleteFiles(query);
      },
    }),
  })),
}));

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

/**
 * 모든 mock 을 초기화하고 Storage 삭제는 기본 성공(빈 prefix 포함)으로 둔다.
 *
 * 기존 D1~D11 은 Storage 단계를 의식하지 않으므로 기본값이 resolve 여야
 * 그대로 통과한다.
 */
function resetAllMocks(): void {
  jest.clearAllMocks();
  mockVerifyIdToken.mockReset();
  mockDeleteUser.mockReset();
  mockWhereGet.mockReset();
  mockTxDelete.mockReset();
  mockDeleteFiles.mockReset();
  mockDeleteFiles.mockResolvedValue(undefined);
  mockRecursiveDelete.mockReset();
  mockRecursiveDelete.mockResolvedValue(undefined);
  callOrder.length = 0;
}

describe("deleteUserAccount onCall — Task 2.1 (D1-D8)", () => {
  beforeEach(resetAllMocks);

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
      details: {reason: "reauthentication_required"},
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
      details: {reason: "reauthentication_required"},
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

  // ---------------------------------------------------------------------------
  // WR-09 (Phase 15 리뷰) 회귀 가드 — 삭제 순서 역전.
  //
  // 이전에는 Firestore 삭제를 먼저 커밋하고 Auth 삭제를 뒤에 했다. Auth 삭제가
  // 실패하면 internal 을 반환하는데 Firestore 삭제는 되돌릴 수 없어, 사용자는
  // "탈퇴 실패" 를 보면서 데이터만 잃고 (로그인은 계속 가능) identity_index
  // 소실로 계정 분열까지 이어질 수 있었다.
  // ---------------------------------------------------------------------------
  it("D9: Auth 삭제 실패 → Firestore 를 손대지 않는다 (data loss 차단)", async () => {
    mockVerifyIdToken.mockResolvedValue({
      uid: "uid-D9",
      auth_time: freshAuthTime(),
    });
    mockWhereGet.mockResolvedValue({docs: [{id: "kakao:999"}]});
    mockDeleteUser.mockRejectedValue(
      Object.assign(new Error("boom"), {code: "auth/internal-error"}),
    );

    const wrapped = testEnv.wrap(myFunctions.deleteUserAccount);
    await expect(
      wrapped({
        auth: {uid: "uid-D9"},
        app: {appId: "test"},
        data: {idToken: "FAKE_FRESH"},
      } as never),
    ).rejects.toMatchObject({code: "internal"});

    // 핵심 — Firestore 는 읽지도 지우지도 않았다. 사용자는 재시도 가능.
    expect(mockTxDelete).not.toHaveBeenCalled();
    expect(callOrder).not.toContain("where:identity_index:get");
  });

  // eslint-disable-next-line max-len
  it("D10: Firestore cleanup 실패 → 고아 문서 로그 + ok:true (계정은 이미 삭제)", async () => {
    mockVerifyIdToken.mockResolvedValue({
      uid: "uid-D10",
      auth_time: freshAuthTime(),
    });
    mockDeleteUser.mockResolvedValue(undefined);
    mockWhereGet.mockRejectedValue(
      Object.assign(new Error("PII_FIRESTORE_SENTINEL"), {
        code: "unavailable",
      }),
    );

    const wrapped = testEnv.wrap(myFunctions.deleteUserAccount);
    const result = (await wrapped({
      auth: {uid: "uid-D10"},
      app: {appId: "test"},
      data: {idToken: "FAKE_FRESH"},
    } as never)) as {ok: true};

    // 계정은 삭제됐고 caller 는 인증 수단을 잃어 재시도할 수 없다 —
    // 실패를 알리는 대신 ops 수거용 전용 event 로 남긴다.
    expect(result.ok).toBe(true);
    expect(errorMock).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "delete_user_firestore_orphan",
        uid: "uid-D10",
        code: "unavailable",
      }),
      expect.any(String),
    );
    // PII 금지 — err.message 본문 미노출.
    for (const args of errorMock.mock.calls) {
      expect(JSON.stringify(args)).not.toContain("PII_FIRESTORE_SENTINEL");
    }
  });

  it("D11: 호출 순서 — Auth 삭제가 Firestore cleanup 보다 먼저", async () => {
    mockVerifyIdToken.mockResolvedValue({
      uid: "uid-D11",
      auth_time: freshAuthTime(),
    });
    mockWhereGet.mockResolvedValue({docs: [{id: "kakao:111"}]});
    mockDeleteUser.mockResolvedValue(undefined);

    const wrapped = testEnv.wrap(myFunctions.deleteUserAccount);
    await wrapped({
      auth: {uid: "uid-D11"},
      app: {appId: "test"},
      data: {idToken: "FAKE_FRESH"},
    } as never);

    const authIdx = callOrder.indexOf("auth.deleteUser");
    const whereIdx = callOrder.indexOf("where:identity_index:get");
    expect(authIdx).toBeGreaterThanOrEqual(0);
    expect(whereIdx).toBeGreaterThan(authIdx);
  });
});

// ---------------------------------------------------------------------------
// Phase 17 (D-16 · D-40) — Storage `users/{uid}/` 를 Auth 보다 먼저 지운다.
//
// Storage 를 Auth 뒤에 두면 Storage 실패 시 계정은 이미 없어 사용자가 재시도할
// 수 없고 개인 사진이 영구 잔존한다. 그래서 Storage 실패는 탈퇴 자체를 멈춘다.
// ---------------------------------------------------------------------------
describe("deleteUserAccount onCall — Phase 17 탈퇴 cascade", () => {
  beforeEach(resetAllMocks);

  /**
   * 신선한 ID Token 으로 [uid] 의 탈퇴를 호출한다.
   *
   * @param {string} uid 호출자 uid (request.auth.uid · decoded.uid 동일).
   * @return {Promise<unknown>} callable 결과 promise.
   */
  function callDelete(uid: string): Promise<unknown> {
    mockVerifyIdToken.mockResolvedValue({uid, auth_time: freshAuthTime()});
    const wrapped = testEnv.wrap(myFunctions.deleteUserAccount);
    return wrapped({
      auth: {uid},
      app: {appId: "test"},
      data: {idToken: "FAKE_FRESH"},
    } as never) as Promise<unknown>;
  }

  it("T-17-DEL-01: Storage prefix 삭제 → Auth → Firestore 순서", async () => {
    mockWhereGet.mockResolvedValue({docs: [{id: "kakao:101"}]});
    mockDeleteUser.mockResolvedValue(undefined);

    const result = (await callDelete("uid-DEL01")) as {ok: true};

    expect(result.ok).toBe(true);
    // 슬래시 종결 prefix — `users/uid-DEL012/…` 오매칭 방지 (Pitfall 10).
    expect(mockDeleteFiles).toHaveBeenCalledTimes(1);
    expect(mockDeleteFiles).toHaveBeenCalledWith({
      prefix: "users/uid-DEL01/",
      force: true,
    });
    const storageIdx = callOrder.indexOf("storage.deleteFiles");
    const authIdx = callOrder.indexOf("auth.deleteUser");
    const whereIdx = callOrder.indexOf("where:identity_index:get");
    expect(storageIdx).toBeGreaterThanOrEqual(0);
    expect(authIdx).toBeGreaterThan(storageIdx);
    expect(whereIdx).toBeGreaterThan(authIdx);
  });

  it("T-17-DEL-02: Storage 실패(Error) → 탈퇴 중단 · 무변경", async () => {
    mockDeleteFiles.mockRejectedValue(
      Object.assign(new Error("PII_STORAGE_SENTINEL"), {code: 503}),
    );

    const promise = callDelete("uid-DEL02");

    await expect(promise).rejects.toBeInstanceOf(HttpsError);
    await expect(promise).rejects.toMatchObject({
      code: "unavailable",
      message: "errorServiceUnavailable",
      details: {reason: "storage_cleanup_failed"},
    });
    // 계정 · 데이터 무변경 — 사용자는 그대로 재시도할 수 있다.
    expect(mockDeleteUser).not.toHaveBeenCalled();
    expect(callOrder).not.toContain("auth.deleteUser");
    expect(callOrder).not.toContain("runTransaction:enter");
    expect(callOrder).not.toContain("where:identity_index:get");
    expect(errorMock).toHaveBeenCalledTimes(1);
    const [payload] = errorMock.mock.calls[0] as [Record<string, unknown>];
    expect(payload).toMatchObject({
      event: "delete_user_storage_failed",
      uid: "uid-DEL02",
      failedCount: 1,
    });
    // payload 키는 event · uid · code (+ 실패 수) 뿐 — 경로 · prefix 없음.
    expect(Object.keys(payload).sort()).toEqual(
      ["code", "event", "failedCount", "uid"],
    );
    expect(JSON.stringify(errorMock.mock.calls)).not.toContain(
      "PII_STORAGE_SENTINEL",
    );
  });

  it("T-17-DEL-03: Storage 실패(Error[]) → 같은 중단 + 실패 수", async () => {
    mockDeleteFiles.mockRejectedValue([new Error("a"), new Error("b")]);

    const promise = callDelete("uid-DEL03");

    await expect(promise).rejects.toMatchObject({
      code: "unavailable",
      message: "errorServiceUnavailable",
      details: {reason: "storage_cleanup_failed"},
    });
    expect(mockDeleteUser).not.toHaveBeenCalled();
    expect(callOrder).not.toContain("runTransaction:enter");
    expect(errorMock).toHaveBeenCalledTimes(1);
    expect(errorMock).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "delete_user_storage_failed",
        uid: "uid-DEL03",
        failedCount: 2,
      }),
      expect.any(String),
    );
  });

  it("T-17-DEL-04: fcmTokens recursiveDelete — 트랜잭션 뒤 1회", async () => {
    mockWhereGet.mockResolvedValue({docs: [{id: "kakao:404"}]});
    mockDeleteUser.mockResolvedValue(undefined);

    const result = (await callDelete("uid-DEL04")) as {ok: true};

    expect(result.ok).toBe(true);
    expect(mockRecursiveDelete).toHaveBeenCalledTimes(1);
    expect(mockRecursiveDelete).toHaveBeenCalledWith(
      expect.objectContaining({label: "users/uid-DEL04/fcmTokens"}),
    );
    // 토큰 삭제 실패가 identity_index · users 문서 삭제를 건너뛰게 하지
    // 않도록 기존 트랜잭션 **뒤** 에 둔다.
    const txExitIdx = callOrder.lastIndexOf("runTransaction:exit");
    const recursiveIdx = callOrder.indexOf("recursiveDelete");
    expect(txExitIdx).toBeGreaterThanOrEqual(0);
    expect(recursiveIdx).toBeGreaterThan(txExitIdx);
  });

  it("T-17-DEL-05: recursiveDelete 실패 → orphan 로그 + ok:true", async () => {
    mockWhereGet.mockResolvedValue({docs: [{id: "kakao:505"}]});
    mockDeleteUser.mockResolvedValue(undefined);
    mockRecursiveDelete.mockRejectedValue(
      Object.assign(new Error("PII_FCM_SENTINEL"), {code: "unavailable"}),
    );

    const result = (await callDelete("uid-DEL05")) as {ok: true};

    // WR-09 orphan 정책 — 계정은 이미 없고 TTL(D-33)이 남은 토큰을 지운다.
    expect(result.ok).toBe(true);
    expect(callOrder).toContain("runTransaction:exit");
    expect(mockTxDelete).toHaveBeenCalled();
    expect(errorMock).toHaveBeenCalledTimes(1);
    const [payload] = errorMock.mock.calls[0] as [Record<string, unknown>];
    expect(payload).toEqual({
      event: "delete_user_fcm_tokens_orphan",
      uid: "uid-DEL05",
      code: "unavailable",
    });
    expect(JSON.stringify(errorMock.mock.calls)).not.toContain(
      "PII_FCM_SENTINEL",
    );
  });

  it("T-17-DEL-06: 멱등 재시도 — 전 단계 진행 · 로그에 경로 0", async () => {
    // 이전 시도가 Auth 삭제 직후 중단된 상태 — Storage 는 빈 prefix resolve.
    mockWhereGet.mockResolvedValue({docs: []});
    mockDeleteUser.mockRejectedValue(
      Object.assign(new Error("user not found"), {
        code: "auth/user-not-found",
      }),
    );

    const result = (await callDelete("uid-DEL06")) as {ok: true};

    expect(result.ok).toBe(true);
    expect(mockDeleteFiles).toHaveBeenCalledTimes(1);
    expect(callOrder).toContain("runTransaction:enter");
    expect(mockRecursiveDelete).toHaveBeenCalledTimes(1);
    expect(infoMock).toHaveBeenCalledWith(
      expect.objectContaining({event: "delete_user_auth_already_done"}),
      expect.any(String),
    );
    // PII — 파일 경로 · prefix · 문서 경로가 어떤 로그에도 실리지 않는다.
    const allLogCalls = [
      ...infoMock.mock.calls,
      ...warnMock.mock.calls,
      ...errorMock.mock.calls,
      ...debugMock.mock.calls,
      ...logMock.mock.calls,
    ];
    expect(allLogCalls.length).toBeGreaterThan(0);
    for (const args of allLogCalls) {
      expect(JSON.stringify(args)).not.toContain("users/");
    }
  });

  /**
   * `@google-cloud/storage` `ApiError` 모양의 오류를 만든다 — `code` 는 HTTP
   * 상태 **숫자** 다 (`nodejs-common/util.js`).
   *
   * @param {number} status HTTP 상태.
   * @return {Error} code 가 붙은 Error.
   */
  function storageError(status: number): Error {
    return Object.assign(new Error("PII_STORAGE_404_SENTINEL"), {code: status});
  }

  it("T-17-DEL-07: 단일 404(버킷 없음) → warn 로그 뒤 Auth · Firestore 진행",
    async () => {
      mockWhereGet.mockResolvedValue({docs: [{id: "kakao:707"}]});
      mockDeleteUser.mockResolvedValue(undefined);
      mockDeleteFiles.mockRejectedValue(storageError(404));

      const result = (await callDelete("uid-DEL07")) as {ok: true};

      expect(result.ok).toBe(true);
      expect(mockDeleteUser).toHaveBeenCalledWith("uid-DEL07");
      expect(callOrder).toContain("runTransaction:enter");
      expect(mockRecursiveDelete).toHaveBeenCalledTimes(1);
      expect(warnMock).toHaveBeenCalledWith(
        {event: "delete_user_storage_bucket_missing", uid: "uid-DEL07"},
        expect.any(String),
      );
      expect(errorMock).not.toHaveBeenCalled();
      expect(JSON.stringify(warnMock.mock.calls)).not.toContain(
        "PII_STORAGE_404_SENTINEL",
      );
    });

  it("T-17-DEL-08: 전부 404 인 Error[](이미 삭제) → warn 로그 뒤 진행",
    async () => {
      mockWhereGet.mockResolvedValue({docs: []});
      mockDeleteUser.mockResolvedValue(undefined);
      mockDeleteFiles.mockRejectedValue([storageError(404), storageError(404)]);

      const result = (await callDelete("uid-DEL08")) as {ok: true};

      expect(result.ok).toBe(true);
      expect(mockDeleteUser).toHaveBeenCalledWith("uid-DEL08");
      expect(callOrder).toContain("runTransaction:enter");
      expect(warnMock).toHaveBeenCalledWith(
        {
          event: "delete_user_storage_already_gone",
          uid: "uid-DEL08",
          failedCount: 2,
        },
        expect.any(String),
      );
      expect(errorMock).not.toHaveBeenCalled();
    });

  it("T-17-DEL-09: 404 와 다른 code 가 섞인 Error[] → 탈퇴 중단", async () => {
    mockDeleteFiles.mockRejectedValue([storageError(404), storageError(503)]);

    const promise = callDelete("uid-DEL09");

    await expect(promise).rejects.toMatchObject({
      code: "unavailable",
      message: "errorServiceUnavailable",
      details: {reason: "storage_cleanup_failed"},
    });
    expect(mockDeleteUser).not.toHaveBeenCalled();
    expect(callOrder).not.toContain("runTransaction:enter");
    expect(warnMock).not.toHaveBeenCalled();
    expect(errorMock).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "delete_user_storage_failed",
        uid: "uid-DEL09",
        failedCount: 2,
      }),
      expect.any(String),
    );
  });
});
