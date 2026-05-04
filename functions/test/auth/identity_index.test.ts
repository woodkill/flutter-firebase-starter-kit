/**
 * Identity Index helper 회귀 테스트 (Phase 12 Task 2 + Phase 12.1 R2).
 *
 * - lookup-first transaction 동작 (D-13)
 * - first-write-wins (D-12)
 * - Pitfall 4 회피 (createUser transaction 외부 1회만)
 * - Pitfall 5 회피 (linkedProviders 객체에 linkedAt 미포함)
 * - Pitfall 12 회피 (users/{uid} set-merge)
 * - R2 (BL-03 / D-31) — race-loser preCreatedUid post-tx best-effort cleanup +
 *   logger.warn (Pitfall 7 PII 미포함) + idempotent (cleanup 실패 시 outer 정상 반환)
 *
 * Phase 13~16 의 Custom Token provider 가 같은 helper 를 재사용하므로
 * 본 테스트가 helper 시그니처 회귀 가드 역할 (D-08).
 */

const mockCreateUser = jest.fn();
const mockDeleteUser = jest.fn(); // R2 추가 — orphan cleanup 검증용.

jest.mock("firebase-admin/auth", () => ({
  getAuth: jest.fn(() => ({
    createUser: mockCreateUser,
    deleteUser: mockDeleteUser, // R2 추가.
  })),
}));

jest.mock("firebase-admin/firestore", () => ({
  Firestore: class MockFirestore {},
  FieldValue: {
    serverTimestamp: () => "MOCK_TIMESTAMP",
    arrayUnion: (item: unknown) => ({mockArrayUnion: item}),
  },
}));

// R2 추가 — best-effort cleanup 의 logger.warn 호출 검증용.
jest.mock("firebase-functions/logger", () => ({
  warn: jest.fn(),
  info: jest.fn(),
  error: jest.fn(),
}));

// helper import 는 mock 셋업 이후.
// eslint-disable-next-line import/first
import {
  identityIndexDocId,
  resolveIdentity,
} from "../../src/auth/identity_index";
// eslint-disable-next-line import/first
import * as logger from "firebase-functions/logger";

const warnMock = logger.warn as jest.MockedFunction<typeof logger.warn>;

type MockDoc = {
  exists: boolean;
  data?: () => Record<string, unknown>;
};

type MockTx = {
  get: jest.Mock<Promise<MockDoc>, [unknown]>;
  set: jest.Mock;
  update: jest.Mock;
};

type MockDb = {
  db: never;
  tx: MockTx;
  idxRef: {label: string};
  userRef: {label: string};
};

/**
 * 4 가지 분기 (preExists / txExists 조합) 에 대한 mock Firestore + tx 빌더.
 *
 * @param {{preExists: boolean, preData: (Record<string, unknown>|undefined),
 *     txExists: boolean, txData: (Record<string, unknown>|undefined)}} opts
 *     비-tx read / tx.get 분기 설정.
 * @return {MockDb} mock db + tx + ref.
 */
function makeDb(opts: {
  preExists: boolean;
  preData?: Record<string, unknown>;
  txExists: boolean;
  txData?: Record<string, unknown>;
}): MockDb {
  const idxRef = {
    get: jest.fn().mockResolvedValue({
      exists: opts.preExists,
      data: opts.preData ? () => opts.preData : undefined,
    }),
    label: "idxRef",
  };
  const userRef = {label: "userRef"};

  const tx: MockTx = {
    get: jest.fn().mockResolvedValue({
      exists: opts.txExists,
      data: opts.txData ? () => opts.txData : undefined,
    }),
    set: jest.fn(),
    update: jest.fn(),
  };

  const db = {
    collection: jest.fn((name: string) => ({
      doc: jest.fn(() => (name === "identity_index" ? idxRef : userRef)),
    })),
    runTransaction: jest.fn(
      (fn: (t: MockTx) => Promise<unknown>) => fn(tx),
    ),
  };

  return {db: db as never, tx, idxRef, userRef};
}

describe("identityIndexDocId", () => {
  it("provider:providerUserId 형식으로 키 생성 (D-09)", () => {
    expect(identityIndexDocId("kakao", "abc123")).toBe("kakao:abc123");
    expect(identityIndexDocId("naver", "456")).toBe("naver:456");
  });
});

describe("resolveIdentity (Phase 12 lookup-first)", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockCreateUser.mockReset();
    mockDeleteUser.mockReset();
    warnMock.mockReset();
  });

  it("기존 매핑 존재 → first-write-wins (D-12)", async () => {
    const {db, tx, idxRef} = makeDb({
      preExists: true,
      txExists: true,
      txData: {firebaseUid: "existing-uid-9"},
    });

    const res = await resolveIdentity(db, {
      provider: "kakao",
      providerUserId: "kakao-456",
      callerUid: "different-uid",
    });

    expect(res).toMatchObject({uid: "existing-uid-9", isNewUser: false});
    // 기존 매핑은 lastSeenAt 만 update — set 호출 0회.
    expect(tx.update).toHaveBeenCalledWith(
      idxRef,
      expect.objectContaining({lastSeenAt: expect.anything()}),
    );
    expect(tx.set).not.toHaveBeenCalled();
    // Pitfall 4 회피 — 기존 매핑이면 createUser 미호출.
    expect(mockCreateUser).not.toHaveBeenCalled();
  });

  it("미존재 + 익명 호출자 → callerUid 를 seed UID 로 사용", async () => {
    const {db, tx, userRef} = makeDb({
      preExists: false,
      txExists: false,
    });

    const res = await resolveIdentity(db, {
      provider: "kakao",
      providerUserId: "kakao-789",
      callerUid: "anon-uid-1",
    });

    expect(res).toMatchObject({uid: "anon-uid-1", isNewUser: true});
    // Pitfall 4 — callerUid 가 있으므로 createUser 미호출.
    expect(mockCreateUser).not.toHaveBeenCalled();
    // Pitfall 12 회귀 — userRef set 시 {merge: true} 의무.
    const userSetCall = tx.set.mock.calls.find((c) => c[0] === userRef);
    expect(userSetCall).toBeDefined();
    if (userSetCall) {
      expect(userSetCall[2]).toEqual({merge: true});
    }
  });

  it(
    "미존재 + 미인증 호출자 → Pitfall 4 회피 (createUser 외부 1회 + tx 내부 0회)",
    async () => {
      mockCreateUser.mockResolvedValueOnce({uid: "new-uid-pre"});
      const {db} = makeDb({
        preExists: false,
        txExists: false,
      });

      const res = await resolveIdentity(db, {
        provider: "kakao",
        providerUserId: "kakao-999",
        callerUid: undefined,
      });

      expect(res.uid).toBe("new-uid-pre");
      expect(res.isNewUser).toBe(true);
      // 핵심 — createUser 는 transaction 외부에서 단 1회만 호출.
      expect(mockCreateUser).toHaveBeenCalledTimes(1);
    },
  );

  it("Pitfall 5 회피 — linkedProviders 객체에 linkedAt 미포함", async () => {
    const {db, tx, userRef} = makeDb({
      preExists: false,
      txExists: false,
    });

    await resolveIdentity(db, {
      provider: "kakao",
      providerUserId: "kakao-555",
      callerUid: "anon-1",
    });

    const userSetCall = tx.set.mock.calls.find((c) => c[0] === userRef);
    expect(userSetCall).toBeDefined();
    if (!userSetCall) return;
    const data = userSetCall[1] as Record<string, unknown>;

    // arrayUnion 객체 스키마 = {providerId, providerUserId} 만.
    // mock 환경에서는 FieldValue.arrayUnion 가 단순 객체 — JSON 직렬화로 검증.
    const stringified = JSON.stringify(data.linkedProviders);
    expect(stringified).not.toContain("linkedAt");
    expect(stringified).toContain("providerId");
    expect(stringified).toContain("providerUserId");

    // linkedAt 은 별도 providerLinkedAt map 에 저장.
    expect(data.providerLinkedAt).toBeDefined();
  });

  it(
    "R2: race-loser orphan 시 deleteUser cleanup 호출 (uid mismatch)",
    async () => {
      // race window 시뮬레이션:
      // - 비-tx read 시점: idx 미존재 (preExists: false) → createUser
      //   1회 호출 → 'B' 받음.
      // - transaction 내부 tx.get 시점: 다른 호출자가 먼저 commit 해서
      //   idx 존재 (txExists: true) → 기존 매핑 'A' 가 first-write-winner.
      //   우리가 만든 'B' 는 race-loser orphan.
      mockCreateUser.mockResolvedValueOnce({uid: "B"});
      const {db} = makeDb({
        preExists: false,
        txExists: true,
        txData: {firebaseUid: "A"},
      });

      const res = await resolveIdentity(db, {
        provider: "kakao",
        providerUserId: "kakao-456",
        callerUid: undefined,
        userInfo: undefined,
      });

      expect(mockDeleteUser).toHaveBeenCalledTimes(1);
      expect(mockDeleteUser).toHaveBeenCalledWith("B");
      expect(res).toMatchObject({uid: "A", isNewUser: false});
    },
  );

  it(
    "R2: cleanup 실패 시 outer call 정상 반환 + logger.warn 호출 (idempotent)",
    async () => {
      mockCreateUser.mockResolvedValueOnce({uid: "B"});
      mockDeleteUser.mockRejectedValueOnce(
        Object.assign(new Error("user not found"), {
          code: "auth/user-not-found",
        }),
      );
      const {db} = makeDb({
        preExists: false,
        txExists: true,
        txData: {firebaseUid: "A"},
      });

      const res = await resolveIdentity(db, {
        provider: "kakao",
        providerUserId: "kakao-456",
        callerUid: undefined,
        userInfo: undefined,
      });

      // outer call 정상 반환 — cleanup 실패가 outer path 를 차단하지 않음.
      expect(res).toMatchObject({uid: "A", isNewUser: false});

      // logger.warn 1회 호출, payload 에 event/uid/code 포함.
      expect(warnMock).toHaveBeenCalledTimes(1);
      expect(warnMock).toHaveBeenCalledWith(
        expect.objectContaining({
          event: "identity_index_orphan_cleanup_failed",
          uid: "B",
          code: "auth/user-not-found",
        }),
        expect.any(String),
      );

      // PII 회귀 (Pitfall 7) — err.message 본문 ('user not found') 미노출 검증.
      for (const args of warnMock.mock.calls) {
        expect(JSON.stringify(args)).not.toContain("user not found");
      }
    },
  );
});
