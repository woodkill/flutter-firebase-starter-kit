/**
 * Identity Index helper 회귀 테스트 (Phase 12 Task 2).
 *
 * - lookup-first transaction 동작 (D-13)
 * - first-write-wins (D-12)
 * - Pitfall 4 회피 (createUser transaction 외부 1회만)
 * - Pitfall 5 회피 (linkedProviders 객체에 linkedAt 미포함)
 * - Pitfall 12 회피 (users/{uid} set-merge)
 *
 * Phase 13~16 의 Custom Token provider 가 같은 helper 를 재사용하므로
 * 본 테스트가 helper 시그니처 회귀 가드 역할 (D-08).
 */

const mockCreateUser = jest.fn();

jest.mock("firebase-admin/auth", () => ({
  getAuth: jest.fn(() => ({
    createUser: mockCreateUser,
  })),
}));

jest.mock("firebase-admin/firestore", () => ({
  Firestore: class MockFirestore {},
  FieldValue: {
    serverTimestamp: () => "MOCK_TIMESTAMP",
    arrayUnion: (item: unknown) => ({mockArrayUnion: item}),
  },
}));

// helper import 는 mock 셋업 이후.
// eslint-disable-next-line import/first
import {
  identityIndexDocId,
  resolveIdentity,
} from "../../src/auth/identity_index";

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

    expect(res).toEqual({uid: "existing-uid-9", isNewUser: false});
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

    expect(res).toEqual({uid: "anon-uid-1", isNewUser: true});
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
});
