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
const mockUpdateUser = jest.fn(); // R9 추가 — emailVerified retroactive 검증용.

jest.mock("firebase-admin/auth", () => ({
  getAuth: jest.fn(() => ({
    createUser: mockCreateUser,
    deleteUser: mockDeleteUser, // R2 추가.
    updateUser: mockUpdateUser, // R9 추가.
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
    mockUpdateUser.mockReset();
    mockUpdateUser.mockResolvedValue(undefined); // R9 — default success.
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

  // R3 (Plan 12.1-06 / BL-04 + WR-06) — D-32 helper detect, caller throw.
  // helper 는 conflictKind 를 detect 만 하고, HttpsError 변환 책임은 caller.
  it(
    // eslint-disable-next-line max-len
    "R3: anonymous + existing kakao identity 충돌 → conflictKind 'anonymous_existing_collision'",
    async () => {
      // 시나리오: 익명 사용자 'anon-A' 가 *기존* kakao identity 'existing-B' 로
      // 로그인 시도. helper 는 first-write-wins 로 'existing-B' 반환하지만
      // conflictKind 로 충돌 사실을 caller 에 전달 → caller 가 anonymous
      // 데이터 보존 후 already-exists throw (Phase 17 가 자동 마이그레이션).
      const {db} = makeDb({
        preExists: true,
        txExists: true,
        txData: {firebaseUid: "existing-B"},
      });

      const res = await resolveIdentity(db, {
        provider: "kakao",
        providerUserId: "kakao-456",
        callerUid: "anon-A",
        userInfo: undefined,
      });

      expect(res).toMatchObject({
        uid: "existing-B",
        isNewUser: false,
        conflictKind: "anonymous_existing_collision",
      });
    },
  );

  it(
    // eslint-disable-next-line max-len
    "R3: createUser email collision detect → conflictKind 'email_in_use' (caller throw)",
    async () => {
      // 비-tx read 시점에 idx 미존재 + 미인증 → createUser 호출.
      // createUser 가 'auth/email-already-in-use' throw → helper 가 detect.
      mockCreateUser.mockRejectedValueOnce(
        Object.assign(new Error("email exists"), {
          code: "auth/email-already-in-use",
        }),
      );
      const {db} = makeDb({preExists: false, txExists: false});

      const res = await resolveIdentity(db, {
        provider: "kakao",
        providerUserId: "kakao-789",
        callerUid: undefined,
        userInfo: {email: "test@example.com"},
      });

      // helper 는 throw 하지 않음 — caller 가 conflictKind 로 already-exists 매핑.
      expect(res).toMatchObject({
        uid: "",
        isNewUser: false,
        conflictKind: "email_in_use",
      });
    },
  );

  it(
    "R3: 정상 매핑 (충돌 없음) → conflictKind null",
    async () => {
      const {db} = makeDb({
        preExists: true,
        txExists: true,
        txData: {firebaseUid: "user-A"},
      });

      const res = await resolveIdentity(db, {
        provider: "kakao",
        providerUserId: "kakao-456",
        callerUid: undefined,
        userInfo: undefined,
      });

      expect(res).toMatchObject({
        uid: "user-A",
        isNewUser: false,
        conflictKind: null,
      });
    },
  );

  it(
    "R3: createUser 가 email-already-in-use 외 에러 throw 시 그대로 rethrow",
    async () => {
      // helper 는 'auth/email-already-in-use' 만 detect — 다른 에러는 caller
      // 가 catch 하여 internal 매핑.
      mockCreateUser.mockRejectedValueOnce(
        Object.assign(new Error("internal"), {code: "auth/internal-error"}),
      );
      const {db} = makeDb({preExists: false, txExists: false});

      await expect(
        resolveIdentity(db, {
          provider: "kakao",
          providerUserId: "kakao-rethrow",
          callerUid: undefined,
          userInfo: {email: "rethrow@example.com"},
        }),
      ).rejects.toMatchObject({code: "auth/internal-error"});
    },
  );

  it(
    "R3: 미인증 + 미등록 + 정상 createUser 시 conflictKind null + isNewUser true",
    async () => {
      // 기존 Pitfall 4 회귀 케이스의 R3 변형 — conflictKind 필드 명시 검증.
      mockCreateUser.mockResolvedValueOnce({uid: "new-uid-pre-r3"});
      const {db} = makeDb({preExists: false, txExists: false});

      const res = await resolveIdentity(db, {
        provider: "kakao",
        providerUserId: "kakao-fresh",
        callerUid: undefined,
        userInfo: undefined,
      });

      expect(res).toMatchObject({
        uid: "new-uid-pre-r3",
        isNewUser: true,
        conflictKind: null,
      });
    },
  );

  // R9 (Phase 13 retroactive — Pitfall 9 두 번째 path):
  // anonymous callerUid + 신규 identity 등록 시 anonymous user record 의
  // emailVerified=false 가 그대로 남아 client-side router 의 verify-email
  // gate (auth_guard 분기 4) 가 잘못 트리거되는 회귀. fix: transaction 후
  // updateUser({emailVerified: true}) 호출. Phase 12 UAT 가 "재로그인" path
  // 만 검증해서 buggy "anonymous→소셜 첫 로그인" path 가 가려졌던 회귀.
  // helper 자체에 fix → kakao + naver + Phase 14~16 자동 상속 (D-08).
  it(
    "R9: 익명 callerUid + 신규 identity → updateUser({emailVerified: true})",
    async () => {
      const {db} = makeDb({preExists: false, txExists: false});

      const res = await resolveIdentity(db, {
        provider: "naver",
        providerUserId: "naver-anon-r9",
        callerUid: "anon-uid-r9",
        userInfo: undefined,
      });

      expect(res).toMatchObject({uid: "anon-uid-r9", isNewUser: true});
      // R9 핵심 — updateUser 1회 호출 + emailVerified: true.
      expect(mockUpdateUser).toHaveBeenCalledTimes(1);
      expect(mockUpdateUser).toHaveBeenCalledWith("anon-uid-r9", {
        emailVerified: true,
      });
      // Pitfall 4 회피 보존 — createUser 미호출 (callerUid path).
      expect(mockCreateUser).not.toHaveBeenCalled();
    },
  );

  it(
    "R9: 기존 identity (isNewUser=false) → updateUser 미호출 (멱등성)",
    async () => {
      // 재로그인 path — 이미 emailVerified=true 인 user 재사용.
      const {db} = makeDb({
        preExists: true,
        txExists: true,
        txData: {firebaseUid: "existing-r9"},
      });

      const res = await resolveIdentity(db, {
        provider: "naver",
        providerUserId: "naver-456",
        callerUid: undefined,
        userInfo: undefined,
      });

      expect(res).toMatchObject({uid: "existing-r9", isNewUser: false});
      expect(mockUpdateUser).not.toHaveBeenCalled();
    },
  );

  it(
    "R9: 미인증 호출 (createUser path) → updateUser 미호출 (이미 set)",
    async () => {
      // !callerUid path — createUser({emailVerified: true}) 가 처음부터 set.
      // updateUser 추가 호출 불필요 (멱등성 + 비용 절감).
      mockCreateUser.mockResolvedValueOnce({uid: "new-uid-r9"});
      const {db} = makeDb({preExists: false, txExists: false});

      const res = await resolveIdentity(db, {
        provider: "naver",
        providerUserId: "naver-789",
        callerUid: undefined,
        userInfo: undefined,
      });

      expect(res).toMatchObject({uid: "new-uid-r9", isNewUser: true});
      expect(mockCreateUser).toHaveBeenCalledTimes(1);
      expect(mockUpdateUser).not.toHaveBeenCalled();
    },
  );

  // R10 (Phase 13 retroactive): IdP 가 제공한 nickname/email/profile_image
  // 를 Firebase Auth user record (displayName/email/photoURL) 에 propagate.
  // !callerUid path 의 createUser + callerUid path 의 updateUser 양쪽 모두.
  // 12-UAT 가 nickname/email/photo UI 표시 명시 검증 누락 → Phase 13 시나리오 2
  // 에서 첫 노출. helper 자체에 fix → kakao + naver + Phase 14~16 자동 상속.
  it(
    "R10: callerUid + 신규 + userInfo → updateUser 가 모든 필드 set",
    async () => {
      const {db} = makeDb({preExists: false, txExists: false});

      await resolveIdentity(db, {
        provider: "naver",
        providerUserId: "naver-r10",
        callerUid: "anon-r10",
        userInfo: {
          email: "user@example.com",
          displayName: "홍길동",
          photoURL: "https://example.com/pic.jpg",
        },
      });

      expect(mockUpdateUser).toHaveBeenCalledWith("anon-r10", {
        emailVerified: true,
        email: "user@example.com",
        displayName: "홍길동",
        photoURL: "https://example.com/pic.jpg",
      });
    },
  );

  it(
    "R10: !callerUid + 신규 + userInfo → createUser 가 모든 필드 set",
    async () => {
      mockCreateUser.mockResolvedValueOnce({uid: "new-r10"});
      const {db} = makeDb({preExists: false, txExists: false});

      await resolveIdentity(db, {
        provider: "kakao",
        providerUserId: "kakao-r10",
        callerUid: undefined,
        userInfo: {
          email: "user@example.com",
          displayName: "홍길동",
          photoURL: "https://example.com/pic.jpg",
        },
      });

      expect(mockCreateUser).toHaveBeenCalledWith({
        emailVerified: true,
        email: "user@example.com",
        displayName: "홍길동",
        photoURL: "https://example.com/pic.jpg",
      });
    },
  );

  it(
    "R9: updateUser 실패 시 throw (strict — caller 가 internal 매핑)",
    async () => {
      // updateUser 실패 시 emailVerified=false 가 그대로 남아 verify-email
      // gate 가 잘못 트리거됨 → strict 정책으로 throw → caller 가
      // createCustomToken 차단 + internal 에러 매핑.
      mockUpdateUser.mockReset();
      mockUpdateUser.mockRejectedValueOnce(
        Object.assign(new Error("update failed"), {
          code: "auth/internal-error",
        }),
      );
      const {db} = makeDb({preExists: false, txExists: false});

      await expect(
        resolveIdentity(db, {
          provider: "naver",
          providerUserId: "naver-fail",
          callerUid: "anon-fail",
          userInfo: undefined,
        }),
      ).rejects.toMatchObject({code: "auth/internal-error"});
    },
  );
});
