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
 * - Phase 16.7 D-16 — 신규 등록 2 분기(익명 caller · preCreatedUid) users
 *   set-merge payload 에 가입 수단 동승 + line pass-through (closed union)
 * - Phase 16.7 D-18 — 재로그인(isNewUser: false) · 비익명 caller 가드는
 *   users 문서 write 0 (가입 수단 덮어쓰기 0)
 *
 * Phase 13~16 의 Custom Token provider 가 같은 helper 를 재사용하므로
 * 본 테스트가 helper 시그니처 회귀 가드 역할 (D-08).
 */

const mockCreateUser = jest.fn();
const mockDeleteUser = jest.fn(); // R2 추가 — orphan cleanup 검증용.
const mockUpdateUser = jest.fn(); // R9 추가 — emailVerified retroactive 검증용.
// Phase 9.2 Gap B (HUMAN-UAT 2026-05-11) — callerUid 분기 email collision detect.
const mockGetUserByEmail = jest.fn();

// CR-02 (Phase 15 리뷰) — post-commit 보상 경로가 재시도 판정을 위해
// getAuth().getUser(uid) 로 현재 emailVerified / providerData 를 읽는다.
// 기본값은 "Custom Token 계정 + 이미 verified" (= 보상 불필요) 로 두어
// 기존 케이스 회귀 0.
const mockGetUser = jest.fn().mockResolvedValue({
  emailVerified: true,
  providerData: [],
});
jest.mock("firebase-admin/auth", () => ({
  getAuth: jest.fn(() => ({
    createUser: mockCreateUser,
    deleteUser: mockDeleteUser, // R2 추가.
    updateUser: mockUpdateUser, // R9 추가.
    getUserByEmail: mockGetUserByEmail, // Phase 9.2 Gap B.
    getUser: mockGetUser, // CR-02 post-commit 보상 판정.
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
  profileFieldsForRefresh,
  resolveIdentity,
  type ProviderId,
} from "../../src/auth/identity_index";
// eslint-disable-next-line import/first
import * as logger from "firebase-functions/logger";

const warnMock = logger.warn as jest.MockedFunction<typeof logger.warn>;
// quick 260928-jwe — 연결 수단 재로그인 skip 로그(info) 검증용.
const infoMock = logger.info as jest.MockedFunction<typeof logger.info>;

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
  // Plan 16-17: identity_index 역조회 stub.
  where: jest.Mock;
  whereGet: jest.Mock;
  // Plan 16-17: 호출 순서 태그 배열 ("reverse-lookup" / "runTransaction").
  // quick 260928-jwe: tx 밖 로그인 계정 users read 는 "login-user-read".
  callOrder: string[];
  // quick 260928-jwe: 로그인 계정 users/{uid} 비-tx read stub.
  userGet: jest.Mock;
};

/**
 * 역조회 stub 이 돌려줄 identity_index 문서 shape.
 *
 * WR-03 (4차 리뷰): `providerUserId` 를 담을 수 있다. identity_index 문서 ID 가
 * `{provider}:{providerUserId}` 이므로 self 판정의 진짜 기준은 sub 이며,
 * provider slug 만 담는 fixture 는 "같은 provider 의 다른 sub" 상태를 표현할 수
 * 없었다 (T-16-17-12 가 그 상태를 잠근다).
 */
type ReverseDoc = {provider: unknown; providerUserId?: unknown};

/**
 * 4 가지 분기 (preExists / txExists 조합) 에 대한 mock Firestore + tx 빌더.
 *
 * @param {{preExists: boolean, preData: (Record<string, unknown>|undefined),
 *     txExists: boolean, txData: (Record<string, unknown>|undefined),
 *     callerUserExists: (boolean|undefined),
 *     reverseDocs: (Array<ReverseDoc>|undefined),
 *     reverseRejects: (boolean|undefined),
 *     loginUserDoc: ({exists: boolean,
 *       data: (Record<string, unknown>|undefined)}|undefined),
 *     loginUserReadRejects: (boolean|undefined)}} opts
 *     비-tx read / tx.get / identity_index 역조회 분기 설정.
 *     loginUserDoc = 재로그인 계정 users/{uid} 비-tx read 결과(기본 문서 없음).
 *     loginUserReadRejects = 그 read 실패 시뮬레이션(quick 260928-jwe).
 * @return {MockDb} mock db + tx + ref + 역조회 stub.
 */
function makeDb(opts: {
  preExists: boolean;
  preData?: Record<string, unknown>;
  txExists: boolean;
  txData?: Record<string, unknown>;
  // R12: callerUid 의 users/<uid> 문서 존재 여부. helper 가 collision detect
  // 시 추가로 tx.get(userRef) 호출 → 데이터 없으면 collision 우회.
  // 기본값 true — 12.1 R3 의 보안 차단 동작이 default (기존 R3 test 보존).
  callerUserExists?: boolean;
  // Plan 16-17: identity_index where('firebaseUid','==',uid).get() 결과 주입.
  // 기본값 빈 배열 — 기존 케이스 회귀 0 (역조회 후보 0 = 충돌 아님).
  // WR-03 (4차 리뷰): 문서 shape 는 ReverseDoc (sub 포함) 이다.
  reverseDocs?: Array<ReverseDoc>;
  // Plan 16-17: 역조회 쿼리 실패 시뮬레이션 (best-effort graceful 검증용).
  reverseRejects?: boolean;
  // quick 260928-jwe: 재로그인 계정 users/{uid} 의 tx 밖 read 결과
  // (signUpProviderId 판정용). 기본값 = 문서 없음.
  loginUserDoc?: {exists: boolean; data?: Record<string, unknown>};
  // quick 260928-jwe: 그 read 의 실패 시뮬레이션 (fail-closed 검증용).
  loginUserReadRejects?: boolean;
}): MockDb {
  const idxRef = {
    get: jest.fn().mockResolvedValue({
      exists: opts.preExists,
      data: opts.preData ? () => opts.preData : undefined,
    }),
    label: "idxRef",
  };
  // Plan 16-17: 호출 순서 태그 배열. quick 260928-jwe 에서 userRef.get 도
  // 태그를 남기므로 userRef 생성보다 앞에 선언한다.
  const callOrder: string[] = [];
  // quick 260928-jwe: 로그인 계정 users/{uid} 비-tx read stub. userRef 는
  // 같은 객체 인스턴스를 유지한다 (tx.get 의 ref === userRef 판정 불변).
  const loginUserExists = opts.loginUserDoc?.exists ?? false;
  const loginUserData = opts.loginUserDoc?.data;
  const userGet = jest.fn(async (): Promise<MockDoc> => {
    callOrder.push("login-user-read");
    if (opts.loginUserReadRejects) {
      throw Object.assign(new Error("PII_JWE_READ_ERR"), {
        code: "unavailable",
      });
    }
    return {
      exists: loginUserExists,
      data: loginUserData ? () => loginUserData : undefined,
    };
  });
  const userRef = {label: "userRef", get: userGet};

  // WR-05 (Phase 13 review): "all reads before all writes" Firestore
  // transaction 제약 회귀 가드. firestore production 은 첫 write (set/update)
  // 발화 후 read (get) 시 FAILED_PRECONDITION 으로 reject 하지만, 본 jest mock
  // 은 phase 추적 없이 모두 받아주므로 R12 같은 회귀가 unit test 에서 GREEN
  // 통과해 버림 (13-UAT 시나리오 3 시 실 단말 노출). MockTx state machine 으로
  // first-write 이후 read 시 명시적 throw — 회귀 발생 시 RED.
  let txPhase: "read" | "write" = "read";
  const tx: MockTx = {
    // R12: tx.get(idxRef) → idxSnap, tx.get(userRef) → callerUserSnap 분기.
    // ref reference 비교로 idxRef vs userRef 식별 (mock object 동일 인스턴스).
    get: jest.fn(async (ref: unknown): Promise<MockDoc> => {
      if (txPhase === "write") {
        throw new Error(
          "Firestore transaction violation: tx.get() called after " +
            "tx.set/update. All reads must precede all writes (WR-05 mock " +
            "state-machine guard).",
        );
      }
      if (ref === userRef) {
        return {
          exists: opts.callerUserExists ?? true,
          data: undefined,
        };
      }
      const txData = opts.txData;
      return {
        exists: opts.txExists,
        data: txData ? () => txData : undefined,
      };
    }),
    set: jest.fn(() => {
      txPhase = "write";
    }),
    update: jest.fn(() => {
      txPhase = "write";
    }),
  };

  // Plan 16-17: identity_index 역조회 stub. callOrder 태그로 runTransaction
  // 대비 호출 순서를 관측 가능하게 한다 (transaction 밖 선행 read 회귀 잠금).
  const whereGet = jest.fn(async () => {
    callOrder.push("reverse-lookup");
    if (opts.reverseRejects) {
      throw Object.assign(new Error("query failed"), {
        code: "unavailable",
      });
    }
    return {
      docs: (opts.reverseDocs ?? []).map((d) => ({data: () => d})),
    };
  });
  const where = jest.fn(() => ({get: whereGet}));

  const db = {
    collection: jest.fn((name: string) => ({
      doc: jest.fn(() => (name === "identity_index" ? idxRef : userRef)),
      where,
    })),
    runTransaction: jest.fn(
      (fn: (t: MockTx) => Promise<unknown>) => {
        callOrder.push("runTransaction");
        return fn(tx);
      },
    ),
  };

  return {
    db: db as never,
    tx,
    idxRef,
    userRef,
    where,
    whereGet,
    callOrder,
    userGet,
  };
}

describe("identityIndexDocId", () => {
  it("provider:providerUserId 형식으로 키 생성 (D-09)", () => {
    expect(identityIndexDocId("kakao", "abc123")).toBe("kakao:abc123");
    expect(identityIndexDocId("naver", "456")).toBe("naver:456");
  });
});

// WR-05 (Phase 13 review): MockTx state-machine sanity — mock 가드 자체가
// "all reads before all writes" 위반을 detect 하는지 self-test. 회귀 가드의
// 가드 (meta-test) — 향후 makeDb 가 변경돼서 phase tracker 가 무력화되면
// 본 case 가 RED 로 회귀를 알린다.
describe("MockTx phase tracker (WR-05 meta-test)", () => {
  it("first-write 후 read → 명시 throw (R12 회귀 시뮬레이션)", async () => {
    const {tx, idxRef, userRef} = makeDb({
      preExists: true,
      txExists: true,
      txData: {firebaseUid: "x"},
    });

    // 정상 read.
    await tx.get(idxRef);
    // 명시적 write — phase 전환.
    tx.update(idxRef, {lastSeenAt: "T"});
    // write 후 read 시도 → 명시 throw (Firestore production 동작 미러).
    await expect(tx.get(userRef)).rejects.toThrow(
      /Firestore transaction violation/,
    );
  });
});

describe("resolveIdentity (Phase 12 lookup-first)", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockCreateUser.mockReset();
    mockDeleteUser.mockReset();
    mockUpdateUser.mockReset();
    mockUpdateUser.mockResolvedValue(undefined); // R9 — default success.
    mockGetUserByEmail.mockReset();
    // Phase 9.2 Gap B default — auth/user-not-found (lookup 시 충돌 없음 의도).
    mockGetUserByEmail.mockRejectedValue(
      Object.assign(new Error("not found"), {code: "auth/user-not-found"}),
    );
    // CR-02 default — 보상 불필요 상태 (Custom Token 계정 + 이미 verified).
    mockGetUser.mockReset();
    mockGetUser.mockResolvedValue({emailVerified: true, providerData: []});
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
      callerIsAnonymous: true,
    });

    expect(res).toMatchObject({uid: "existing-uid-9", isNewUser: false});
    // 기존 매핑은 lastSeenAt 만 update — set 호출 0회.
    expect(tx.update).toHaveBeenCalledWith(
      idxRef,
      expect.objectContaining({lastSeenAt: expect.anything()}),
    );
    // Phase 16.7 D-18 — 재로그인(isNewUser: false) 은 users 문서 write 0 이라
    // 가입 수단(signUpProviderId) 을 구조적으로 덮어쓰지 않는다.
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
      callerIsAnonymous: true,
    });

    expect(res).toMatchObject({uid: "anon-uid-1", isNewUser: true});
    // Pitfall 4 — callerUid 가 있으므로 createUser 미호출.
    expect(mockCreateUser).not.toHaveBeenCalled();
    // Pitfall 12 회귀 — userRef set 시 {merge: true} 의무.
    const userSetCall = tx.set.mock.calls.find((c) => c[0] === userRef);
    expect(userSetCall).toBeDefined();
    if (userSetCall) {
      expect(userSetCall[2]).toEqual({merge: true});
      // Phase 16.7 D-16 — 익명 caller 제자리 승격도 가입 수단을 같은 write 에 싣는다.
      expect(userSetCall[1]).toMatchObject({signUpProviderId: "kakao"});
    }
  });

  it(
    "미존재 + 미인증 호출자 → Pitfall 4 회피 (createUser 외부 1회 + tx 내부 0회)",
    async () => {
      mockCreateUser.mockResolvedValueOnce({uid: "new-uid-pre"});
      const {db, tx, userRef} = makeDb({
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
      // Phase 16.7 D-16 — preCreatedUid 신규 등록도 가입 수단을 같은 write 에 싣는다.
      const userSetCall = tx.set.mock.calls.find((c) => c[0] === userRef);
      expect(userSetCall?.[1]).toMatchObject({signUpProviderId: "kakao"});
      expect(userSetCall?.[2]).toEqual({merge: true});
    },
  );

  it(
    // eslint-disable-next-line max-len
    "D-16: line pass-through — provider line 신규 등록 → users payload signUpProviderId === \"line\"",
    async () => {
      const {db, tx, userRef} = makeDb({
        preExists: false,
        txExists: false,
      });

      const res = await resolveIdentity(db, {
        provider: "line",
        providerUserId: "line-new-1",
        callerUid: "anon-uid-2",
        callerIsAnonymous: true,
      });

      expect(res).toMatchObject({uid: "anon-uid-2", isNewUser: true});
      // closed union ProviderId 를 그대로 따라간다
      // (값 형식 = linkedProviders[].providerId).
      const userSetCall = tx.set.mock.calls.find((c) => c[0] === userRef);
      expect(userSetCall?.[1]).toMatchObject({signUpProviderId: "line"});
      expect(userSetCall?.[2]).toEqual({merge: true});
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
      callerIsAnonymous: true,
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
        callerIsAnonymous: true,
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
        callerIsAnonymous: true,
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
        callerIsAnonymous: true,
        userInfo: {
          email: "user@example.com",
          // WR-04: email 이 있으면 IdP 의 검증 상태를 명시해야 한다.
          // 생략 시 보수적으로 false 로 간주된다 (아래 WR-04 케이스 참조).
          emailVerified: true,
          displayName: "홍길동",
          photoURL: "https://example.com/pic.jpg",
        },
      });

      // CR-02 (Phase 15 리뷰): 보안 게이트 (emailVerified) 와 프로필 필드를
      // **분리된 두 호출** 로 나눴다. 한 호출로 묶여 있던 이전 구현은
      // `auth/invalid-photo-url` 같은 프로필 문제 하나가 보안 게이트까지
      // 도미노로 실패시켰다.
      expect(mockUpdateUser).toHaveBeenCalledWith("anon-r10", {
        emailVerified: true,
      });
      expect(mockUpdateUser).toHaveBeenCalledWith("anon-r10", {
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
          // WR-04: IdP 가 verified 를 보고한 경우.
          emailVerified: true,
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

  // R12 (Phase 13 retroactive — 12.1 R3 안전 차단 정밀화):
  // anonymous B 의 Firestore users/<callerUid> 문서가 비어있으면 (sign-out
  // 직후 자동 재생성된 빈 익명 user) collision 차단 우회 → existing.firebaseUid
  // 재사용 (시나리오 3 "재로그인 동일 UID"). 데이터 있으면 12.1 R3 보안 차단 보존.
  it(
    "R12: anonymous + existing identity + users/<B> 부재 → collision 우회",
    async () => {
      const {db} = makeDb({
        preExists: true,
        txExists: true,
        txData: {firebaseUid: "existing-A"},
        callerUserExists: false, // anonymous B 데이터 없음
      });

      const res = await resolveIdentity(db, {
        provider: "naver",
        providerUserId: "naver-r12-empty",
        callerUid: "anon-B",
        callerIsAnonymous: true,
        userInfo: undefined,
      });

      expect(res).toMatchObject({
        uid: "existing-A",
        isNewUser: false,
        conflictKind: null, // collision 우회 — 정상 sign-in path
      });
    },
  );

  it(
    "R12: anonymous + existing identity + users/<B> 존재 → 12.1 R3 보안 차단 보존",
    async () => {
      const {db} = makeDb({
        preExists: true,
        txExists: true,
        txData: {firebaseUid: "existing-A"},
        callerUserExists: true, // anonymous B 가 onboarding/social 데이터 보유
      });

      const res = await resolveIdentity(db, {
        provider: "naver",
        providerUserId: "naver-r12-block",
        callerUid: "anon-B",
        callerIsAnonymous: true,
        userInfo: undefined,
      });

      expect(res).toMatchObject({
        uid: "existing-A",
        isNewUser: false,
        conflictKind: "anonymous_existing_collision", // 차단 보존
      });
    },
  );

  // ---------------------------------------------------------------------------
  // WR-04 (Phase 15 리뷰) 회귀 가드 — emailVerified 하드코딩 제거.
  //
  // Kakao endpoint 는 IN-04 대응으로 developerClaims.email_verified 를 IdP
  // claim 그대로 보수 전파하도록 고쳤지만, 같은 요청의 Firebase Auth **user
  // record** 는 resolveIdentity 가 무조건 true 로 만들고 있었다. custom claim
  // 만 false 이고 record 는 true 이므로, record 를 신뢰하는 모든 경로 (이메일
  // 기반 병합 / 비밀번호 재설정 / auth_guard verify-email 분기) 에서 방어가
  // 사라졌다.
  // ---------------------------------------------------------------------------
  it(
    // eslint-disable-next-line max-len
    "WR-04: email + emailVerified=false → createUser 가 unverified 로 기록",
    async () => {
      mockCreateUser.mockResolvedValueOnce({uid: "new-wr04"});
      const {db} = makeDb({preExists: false, txExists: false});

      await resolveIdentity(db, {
        provider: "kakao",
        providerUserId: "kakao-wr04",
        callerUid: undefined,
        userInfo: {email: "unverified@example.com", emailVerified: false},
      });

      expect(mockCreateUser).toHaveBeenCalledWith({
        emailVerified: false,
        email: "unverified@example.com",
      });
    },
  );

  it(
    // eslint-disable-next-line max-len
    "WR-04: email 은 있고 emailVerified 미보고 → 보수적으로 unverified",
    async () => {
      mockCreateUser.mockResolvedValueOnce({uid: "new-wr04b"});
      const {db} = makeDb({preExists: false, txExists: false});

      await resolveIdentity(db, {
        provider: "kakao",
        providerUserId: "kakao-wr04b",
        callerUid: undefined,
        userInfo: {email: "unknown-state@example.com"},
      });

      expect(mockCreateUser).toHaveBeenCalledWith({
        emailVerified: false,
        email: "unknown-state@example.com",
      });
    },
  );

  it(
    // eslint-disable-next-line max-len
    "WR-04: email 미제공 provider (LINE) 는 true 유지 (gate 오트리거 방지)",
    async () => {
      mockCreateUser.mockResolvedValueOnce({uid: "new-wr04c"});
      const {db} = makeDb({preExists: false, txExists: false});

      await resolveIdentity(db, {
        provider: "line",
        providerUserId: "line-wr04c",
        callerUid: undefined,
        userInfo: {displayName: "Hanako"},
      });

      expect(mockCreateUser).toHaveBeenCalledWith({
        emailVerified: true,
        displayName: "Hanako",
      });
    },
  );

  it(
    // eslint-disable-next-line max-len
    "WR-04: unverified email 은 재시도 보상 대상이 아니다 (gate 정상 동작 보존)",
    async () => {
      // 목표값이 false 인데 current 도 false → 올릴 것이 없다.
      mockGetUser.mockResolvedValue({emailVerified: false, providerData: []});
      const {db} = makeDb({
        preExists: true,
        txExists: true,
        txData: {firebaseUid: "anon-wr04d"},
      });

      await resolveIdentity(db, {
        provider: "kakao",
        providerUserId: "kakao-wr04d",
        callerUid: "anon-wr04d",
        callerIsAnonymous: true,
        userInfo: {email: "unverified@example.com", emailVerified: false},
      });

      expect(mockUpdateUser).not.toHaveBeenCalledWith("anon-wr04d", {
        emailVerified: true,
      });
    },
  );

  // ---------------------------------------------------------------------------
  // CR-02 (Phase 15 리뷰) 회귀 가드 — post-commit 실패 보상.
  //
  // transaction 이 커밋된 뒤 updateUser 가 throw 하면 identity_index 문서는
  // 영구 커밋된 채 남는다. 재시도 시 idxSnap.exists === true 이고
  // existing.firebaseUid === callerUid 이므로 isNewUser=false 로 돌아오는데,
  // 이전 구현은 `result.isNewUser && callerUid` 조건이라 R9 블록을 통째로
  // skip 했다 → emailVerified=false 인 social user 가 그대로 통과했다.
  // ---------------------------------------------------------------------------
  it(
    // eslint-disable-next-line max-len
    "CR-02: 재시도 (isNewUser=false, 소유자 일치) + emailVerified=false → 보상 updateUser",
    async () => {
      // 첫 시도가 post-commit 에서 실패해 idx 문서만 남은 상태의 재현.
      mockGetUser.mockResolvedValue({
        emailVerified: false,
        providerData: [], // Custom Token / 익명 계정 — providerData 비어 있음.
      });
      const {db} = makeDb({
        preExists: true,
        txExists: true,
        txData: {firebaseUid: "anon-cr02"},
      });

      const res = await resolveIdentity(db, {
        provider: "kakao",
        providerUserId: "kakao-cr02",
        callerUid: "anon-cr02",
        callerIsAnonymous: true,
        userInfo: undefined,
      });

      expect(res).toMatchObject({uid: "anon-cr02", isNewUser: false});
      // 핵심 — 재시도에서도 보안 게이트가 반드시 다시 적용된다.
      expect(mockGetUser).toHaveBeenCalledWith("anon-cr02");
      expect(mockUpdateUser).toHaveBeenCalledWith("anon-cr02", {
        emailVerified: true,
      });
    },
  );

  it(
    // eslint-disable-next-line max-len
    "CR-02: 재시도 + 이미 emailVerified=true → updateUser 미호출 (멱등)",
    async () => {
      const {db} = makeDb({
        preExists: true,
        txExists: true,
        txData: {firebaseUid: "anon-cr02b"},
      });

      await resolveIdentity(db, {
        provider: "kakao",
        providerUserId: "kakao-cr02b",
        callerUid: "anon-cr02b",
        callerIsAnonymous: true,
        userInfo: undefined,
      });

      expect(mockUpdateUser).not.toHaveBeenCalled();
    },
  );

  it(
    // eslint-disable-next-line max-len
    "CR-02: native provider 연결 계정은 emailVerified 를 강제하지 않는다 (보안 강등 차단)",
    async () => {
      // password / google 등이 연결된 계정에서 emailVerified 는 그쪽 인증
      // 게이트의 근거다. 여기서 true 를 쓰면 이메일 인증을 우회시킨다.
      mockGetUser.mockResolvedValue({
        emailVerified: false,
        providerData: [{providerId: "password"}],
      });
      // reauth-login-auto-merge: 비익명 caller 가드가 비-tx 스냅샷의
      // firebaseUid 를 읽으므로 실제 문서 shape (data 포함) 로 둔다.
      const {db} = makeDb({
        preExists: true,
        preData: {firebaseUid: "native-cr02"},
        txExists: true,
        txData: {firebaseUid: "native-cr02"},
      });

      await resolveIdentity(db, {
        provider: "kakao",
        providerUserId: "kakao-cr02c",
        callerUid: "native-cr02",
        callerIsAnonymous: false,
        userInfo: undefined,
      });

      expect(mockUpdateUser).not.toHaveBeenCalled();
    },
  );

  it(
    // eslint-disable-next-line max-len
    "CR-02: 소유자가 다르면 (uid !== callerUid) 보상 판정 자체를 하지 않는다",
    async () => {
      const {db} = makeDb({
        preExists: true,
        txExists: true,
        txData: {firebaseUid: "other-owner"},
        callerUserExists: false, // R12 우회 — collision 차단 없이 통과.
      });

      const res = await resolveIdentity(db, {
        provider: "kakao",
        providerUserId: "kakao-cr02d",
        callerUid: "anon-cr02d",
        callerIsAnonymous: true,
        userInfo: undefined,
      });

      expect(res).toMatchObject({uid: "other-owner", isNewUser: false});
      expect(mockGetUser).not.toHaveBeenCalled();
      expect(mockUpdateUser).not.toHaveBeenCalled();
    },
  );

  it(
    // eslint-disable-next-line max-len
    "CR-02: 프로필 필드 실패 (invalid-photo-url) 가 보안 게이트를 도미노로 실패시키지 않는다",
    async () => {
      // 1번째 호출 = emailVerified (성공), 2번째 = profileFields (실패).
      mockUpdateUser.mockReset();
      mockUpdateUser.mockResolvedValueOnce(undefined);
      mockUpdateUser.mockRejectedValueOnce(
        Object.assign(new Error("bad photo"), {
          code: "auth/invalid-photo-url",
        }),
      );
      const {db} = makeDb({preExists: false, txExists: false});

      const res = await resolveIdentity(db, {
        provider: "kakao",
        providerUserId: "kakao-cr02e",
        callerUid: "anon-cr02e",
        callerIsAnonymous: true,
        userInfo: {photoURL: "not-a-valid-url"},
      });

      // 로그인은 계속된다 (프로필은 best-effort).
      expect(res).toMatchObject({uid: "anon-cr02e", isNewUser: true});
      expect(mockUpdateUser).toHaveBeenNthCalledWith(1, "anon-cr02e", {
        emailVerified: true,
      });
      expect(warnMock).toHaveBeenCalledWith(
        expect.objectContaining({
          event: "identity_index_profile_set_failed",
          code: "auth/invalid-photo-url",
        }),
        expect.any(String),
      );
      // PII 금지 — err.message 본문 미노출.
      for (const args of warnMock.mock.calls) {
        expect(JSON.stringify(args)).not.toContain("bad photo");
      }
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
          callerIsAnonymous: true,
          userInfo: undefined,
        }),
      ).rejects.toMatchObject({code: "auth/internal-error"});
    },
  );
});

// Phase 9.2 Gap B (HUMAN-UAT 2026-05-11) — callerUid 분기에서 admin.auth().
// getUserByEmail() lookup 으로 email collision detect. 익명승격 path (callerUid
// 익명 + userInfo.email 제공) + 동일 이메일이 이미 *다른* provider 로 가입된
// 시나리오 close. caller (naver/kakaoCustomToken) 의 switch 분기 unchanged —
// 기존 'errorAccountExistsWithDifferentCredential' HttpsError throw path 재사용.
// eslint-disable-next-line max-len
describe("resolveIdentity Gap B email collision (Phase 9.2, HUMAN-UAT 2026-05-11)", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockCreateUser.mockReset();
    mockDeleteUser.mockReset();
    mockUpdateUser.mockReset();
    mockUpdateUser.mockResolvedValue(undefined);
    mockGetUserByEmail.mockReset();
    warnMock.mockReset();
  });

  // ---------------------------------------------------------------------------
  // WR-05 (Phase 15 리뷰) 회귀 가드 — 1단(native) 분기의 self-check 부재.
  //
  // 2단(Custom Token) 분기는 `existingByEmail.uid !== callerUid` 로 자기
  // 자신을 명시 제외하는데 1단에는 같은 가드가 없었다. 이미 Google 로
  // 로그인한 정식 사용자가 같은 이메일로 Kakao Custom Token 로그인을
  // 호출하면 getUserByEmail 이 자기 자신을 돌려주고 providerData 에
  // google.com 이 있으므로 already-exists 가 던져졌다 — 사용자는 **자기
  // 계정에 대해** "이미 다른 방법으로 가입된 이메일" 안내를 받았다.
  // ---------------------------------------------------------------------------
  it(
    // eslint-disable-next-line max-len
    "WR-05: 자기 계정 재로그인 (existingByEmail.uid === callerUid) 은 충돌이 아니다",
    async () => {
      mockGetUserByEmail.mockResolvedValueOnce({
        // 핵심 — caller 자신이다.
        uid: "self-uid-wr05",
        providerData: [{providerId: "google.com", uid: "g-platform-id"}],
      });
      // debug reauth-login-auto-merge (2026-09-17): 비익명 caller 는 **자기
      // 계정에 이미 매핑된 identity** 로만 통과한다 (caller 가드). 이전 fixture
      // 는 미등록 identity 였고 그 결과 `{uid: self, isNewUser: true}` = 무동의
      // 연결 + 프로필 덮어쓰기를 계약으로 고정하고 있었다. WR-05 가 지키려던
      // "자기 email 은 충돌이 아니다" 는 도달 가능한 상태(매핑 = self)로 옮겨
      // 계속 잠근다. 미등록 identity 거부는 아래 caller 가드 describe 가 잠근다.
      const selfDoc = {firebaseUid: "self-uid-wr05"};
      const {db} = makeDb({
        preExists: true,
        preData: selfDoc,
        txExists: true,
        txData: selfDoc,
      });

      const res = await resolveIdentity(db, {
        provider: "kakao",
        providerUserId: "kakao-wr05",
        callerUid: "self-uid-wr05",
        callerIsAnonymous: false,
        userInfo: {email: "me@example.com", emailVerified: true},
      });

      // 충돌이 아니라 자기 계정 재로그인으로 진행된다.
      expect(res).toMatchObject({
        uid: "self-uid-wr05",
        isNewUser: false,
        conflictKind: null,
      });
      expect(warnMock).not.toHaveBeenCalledWith(
        expect.objectContaining({
          event: "identity_index_email_collision_caller_path",
        }),
        expect.any(String),
      );
    },
  );

  it(
    // eslint-disable-next-line max-len
    "WR-05: 다른 uid 이면 기존 native 충돌 detect 는 그대로 보존된다 (회귀 0)",
    async () => {
      mockGetUserByEmail.mockResolvedValueOnce({
        uid: "other-uid-wr05",
        providerData: [{providerId: "google.com", uid: "g-platform-id"}],
      });
      const {db} = makeDb({preExists: false, txExists: false});

      const res = await resolveIdentity(db, {
        provider: "kakao",
        providerUserId: "kakao-wr05b",
        callerUid: "anon-uid-wr05b",
        callerIsAnonymous: true,
        userInfo: {email: "someone@example.com", emailVerified: true},
      });

      expect(res).toMatchObject({
        conflictKind: "email_in_use",
        existingProvider: "google",
      });
    },
  );

  it(
    // eslint-disable-next-line max-len
    "WR-05: native provider 를 caller 로 호출하면 self-identity 가 실제로 제외된다",
    async () => {
      // 기존 `id !== provider` 비교는 좌변이 Firebase 표기, 우변이 Custom
      // Token 슬러그라 **항상 참** 이었다. 역매핑 비교로 고친 뒤에는
      // provider="google" + providerData=[google.com] 이 self 로 걸러진다
      // (Phase 16 의 native 회고 등록이 들어오면 실제로 필요한 동작).
      mockGetUserByEmail.mockResolvedValueOnce({
        uid: "other-uid-wr05c",
        providerData: [{providerId: "google.com", uid: "g-platform-id"}],
      });
      const {db} = makeDb({preExists: false, txExists: false});

      const res = await resolveIdentity(db, {
        provider: "google",
        providerUserId: "google-wr05c",
        callerUid: "anon-uid-wr05c",
        callerIsAnonymous: true,
        userInfo: {email: "same-provider@example.com", emailVerified: true},
      });

      expect(res.conflictKind).not.toBe("email_in_use");
    },
  );

  it(
    // eslint-disable-next-line max-len
    "T-IDX-COLLISION-01: callerUid + email + 다른 provider 가입자 → conflictKind email_in_use + transaction 미진입",
    async () => {
      // Gap B 핵심 — 익명승격 path 에서 동일 이메일의 Facebook 가입자 detect.
      mockGetUserByEmail.mockResolvedValueOnce({
        uid: "fb-uid-99",
        providerData: [{providerId: "facebook.com", uid: "fb-platform-id"}],
      });
      const {db, tx} = makeDb({preExists: false, txExists: false});
      // db.runTransaction spy — transaction 미진입 검증.
      const runTransactionSpy = jest.spyOn(
        db as unknown as {runTransaction: jest.Mock},
        "runTransaction",
      );

      const res = await resolveIdentity(db, {
        provider: "naver",
        providerUserId: "naver-user-1",
        callerUid: "anon-uid-1",
        callerIsAnonymous: true,
        userInfo: {email: "foo@naver.com"},
      });

      expect(res).toMatchObject({
        uid: "",
        isNewUser: false,
        conflictKind: "email_in_use",
      });
      // transaction 미진입 — tx.get / tx.set 호출 0.
      expect(runTransactionSpy).not.toHaveBeenCalled();
      expect(tx.get).not.toHaveBeenCalled();
      expect(tx.set).not.toHaveBeenCalled();

      // logger.warn payload 검증 (event + count 만, email 본문 / IdP uid 미노출).
      expect(warnMock).toHaveBeenCalledWith(
        expect.objectContaining({
          event: "identity_index_email_collision_caller_path",
          provider: "naver",
          conflictingProviderCount: 1,
        }),
        expect.any(String),
      );
      // PII regression sentinel — email / IdP uid 본문 미노출.
      const allLogCalls = warnMock.mock.calls;
      for (const args of allLogCalls) {
        const stringified = JSON.stringify(args);
        expect(stringified).not.toContain("foo@naver.com");
        expect(stringified).not.toContain("fb-platform-id");
        expect(stringified).not.toContain("fb-uid-99");
      }
    },
  );

  it(
    // eslint-disable-next-line max-len
    "T-IDX-COLLISION-02: callerUid + email + providerData 비어있음 → conflictKind null + transaction 진입",
    async () => {
      // false-positive 차단 — 자기 자신 또는 Custom Token mirror 미지원으로
      // providerData 비어있는 normal case (Phase 12.1 D-34 carry-forward).
      mockGetUserByEmail.mockResolvedValueOnce({
        uid: "naver-uid-self",
        providerData: [],
      });
      const {db, tx} = makeDb({preExists: false, txExists: false});
      const runTransactionSpy = jest.spyOn(
        db as unknown as {runTransaction: jest.Mock},
        "runTransaction",
      );

      const res = await resolveIdentity(db, {
        provider: "naver",
        providerUserId: "naver-user-2",
        callerUid: "anon-uid-2",
        callerIsAnonymous: true,
        userInfo: {email: "self@naver.com"},
      });

      expect(res.conflictKind).toBeNull();
      // 정상 path 진입 — transaction 1회 호출 (callerUid path → updateUser 도).
      expect(runTransactionSpy).toHaveBeenCalledTimes(1);
      expect(tx.get).toHaveBeenCalled();

      // PII regression sentinel.
      const allLogCalls = warnMock.mock.calls;
      for (const args of allLogCalls) {
        expect(JSON.stringify(args)).not.toContain("self@naver.com");
      }
    },
  );

  it(
    // eslint-disable-next-line max-len
    "T-IDX-COLLISION-03: callerUid + email + getUserByEmail throws user-not-found → silent + 정상 path",
    async () => {
      // expected normal case — 이메일이 기존에 가입 안 되어 있음. logger.warn
      // 미호출 (silent).
      mockGetUserByEmail.mockRejectedValueOnce(
        Object.assign(new Error("not found"), {
          code: "auth/user-not-found",
        }),
      );
      const {db, tx} = makeDb({preExists: false, txExists: false});
      const runTransactionSpy = jest.spyOn(
        db as unknown as {runTransaction: jest.Mock},
        "runTransaction",
      );

      const res = await resolveIdentity(db, {
        provider: "naver",
        providerUserId: "naver-user-3",
        callerUid: "anon-uid-3",
        callerIsAnonymous: true,
        userInfo: {email: "same@naver.com"},
      });

      expect(res.conflictKind).toBeNull();
      expect(runTransactionSpy).toHaveBeenCalledTimes(1);
      expect(tx.get).toHaveBeenCalled();

      // lookup_failed event 미호출 (user-not-found 는 silent expected case).
      const lookupFailedCalls = warnMock.mock.calls.filter((args) => {
        const ev = (args[0] as {event?: string})?.event;
        return ev === "identity_index_email_lookup_failed";
      });
      expect(lookupFailedCalls.length).toBe(0);

      // PII regression sentinel.
      const allLogCalls = warnMock.mock.calls;
      for (const args of allLogCalls) {
        expect(JSON.stringify(args)).not.toContain("same@naver.com");
      }
    },
  );

  it(
    // eslint-disable-next-line max-len
    "T-IDX-COLLISION-04: callerUid + email + getUserByEmail throws internal-error → graceful + 정상 path + logger.warn",
    async () => {
      // graceful skip — lookup 실패가 user-facing throw 로 escalate 안 됨.
      // logger.warn 1회 호출 (event=identity_index_email_lookup_failed).
      mockGetUserByEmail.mockRejectedValueOnce(
        Object.assign(new Error("internal"), {
          code: "auth/internal-error",
        }),
      );
      const {db, tx} = makeDb({preExists: false, txExists: false});
      const runTransactionSpy = jest.spyOn(
        db as unknown as {runTransaction: jest.Mock},
        "runTransaction",
      );

      const res = await resolveIdentity(db, {
        provider: "naver",
        providerUserId: "naver-user-4",
        callerUid: "anon-uid-4",
        callerIsAnonymous: true,
        userInfo: {email: "transient@naver.com"},
      });

      expect(res.conflictKind).toBeNull();
      expect(runTransactionSpy).toHaveBeenCalledTimes(1);
      expect(tx.get).toHaveBeenCalled();

      // logger.warn 1회 — event + code (PII 미포함).
      expect(warnMock).toHaveBeenCalledWith(
        expect.objectContaining({
          event: "identity_index_email_lookup_failed",
          code: "auth/internal-error",
        }),
        expect.any(String),
      );

      // PII regression sentinel — email 본문 미노출.
      // (err.code = 'auth/internal-error' 는 의도된 fingerprint, PII 아님.)
      const allLogCalls = warnMock.mock.calls;
      for (const args of allLogCalls) {
        const stringified = JSON.stringify(args);
        expect(stringified).not.toContain("transient@naver.com");
      }
    },
  );

  it(
    // eslint-disable-next-line max-len
    "T-IDX-COLLISION-05: callerUid=undefined + email → getUserByEmail 미호출 (기존 !callerUid 분기 unchanged)",
    async () => {
      // !callerUid path 는 기존 createUser try/catch 분기에서 email collision
      // detect — 신규 lookup skip (중복 lookup 회피). 정상 createUser 성공
      // 시뮬레이션.
      mockCreateUser.mockResolvedValueOnce({uid: "new-uid-no-caller"});
      const {db} = makeDb({preExists: false, txExists: false});

      await resolveIdentity(db, {
        provider: "naver",
        providerUserId: "naver-user-5",
        callerUid: undefined,
        userInfo: {email: "foo@naver.com"},
      });

      // 핵심 — !callerUid 분기에서 신규 getUserByEmail lookup skip.
      expect(mockGetUserByEmail).not.toHaveBeenCalled();
      // 기존 path 진입 — createUser 1회 호출.
      expect(mockCreateUser).toHaveBeenCalledTimes(1);

      // PII regression sentinel.
      const allLogCalls = warnMock.mock.calls;
      for (const args of allLogCalls) {
        expect(JSON.stringify(args)).not.toContain("foo@naver.com");
      }
    },
  );
});

// R10-FOLLOWUP (2026-05-08 — T-13-UAT-NAVER-A1 발견):
// 재로그인 시 (isNewUser=false path) IdP 측 프로필 변경 (displayName/photoURL)
// 을 Firebase Auth user record 에 propagate. PROFILE_REFRESH_POLICY 정책 분기.
// email 은 sign-in 식별자라 정책 무관 항상 preserve.
describe("profileFieldsForRefresh (R10-FOLLOWUP — pure helper)", () => {
  it("truth-of-source: 모든 필드 제공 → 모든 필드 update 객체", () => {
    const r = profileFieldsForRefresh("truth-of-source", {
      email: "u@example.com",
      displayName: "닉네임",
      photoURL: "https://x/p.jpg",
    });
    expect(r).toEqual({
      email: "u@example.com",
      displayName: "닉네임",
      photoURL: "https://x/p.jpg",
    });
  });

  it(
    "truth-of-source: photoURL 부재 → photoURL=null clear (displayName 동일)",
    () => {
      const r = profileFieldsForRefresh("truth-of-source", {
        email: "u@example.com",
        displayName: "닉네임",
      });
      expect(r).toEqual({
        email: "u@example.com",
        displayName: "닉네임",
        photoURL: null,
      });
    },
  );

  it(
    "truth-of-source: 모든 필드 부재 → email 미포함 + displayName/photoURL=null",
    () => {
      const r = profileFieldsForRefresh("truth-of-source", {});
      expect(r).toEqual({
        displayName: null,
        photoURL: null,
      });
    },
  );

  it("preserve: 응답에 있는 것만 update (photoURL 부재 → 미포함 = 보존)", () => {
    const r = profileFieldsForRefresh("preserve", {
      email: "u@example.com",
      displayName: "닉네임",
    });
    expect(r).toEqual({
      email: "u@example.com",
      displayName: "닉네임",
    });
    expect(r).not.toHaveProperty("photoURL");
  });

  it(
    "preserve: 모든 필드 부재 → 빈 객체 (caller 가 updateUser 호출 skip 시그널)",
    () => {
      const r = profileFieldsForRefresh("preserve", {});
      expect(r).toEqual({});
    },
  );

  it(
    "email 은 정책 무관 항상 preserve — clear 시 sign-in 식별자 손실 위험",
    () => {
      // truth-of-source 모드에서도 email 부재 시 미포함 (null 미clear).
      const ts = profileFieldsForRefresh("truth-of-source", {
        displayName: "x",
      });
      expect(ts).not.toHaveProperty("email");
      // preserve 모드에서도 email 부재 시 미포함 (동일 동작).
      const pr = profileFieldsForRefresh("preserve", {displayName: "x"});
      expect(pr).not.toHaveProperty("email");
    },
  );
});

describe("resolveIdentity R10-FOLLOWUP — 재로그인 IdP 프로필 propagate", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockCreateUser.mockReset();
    mockDeleteUser.mockReset();
    mockUpdateUser.mockReset();
    mockUpdateUser.mockResolvedValue(undefined);
    mockGetUserByEmail.mockReset();
    mockGetUserByEmail.mockRejectedValue(
      Object.assign(new Error("not found"), {code: "auth/user-not-found"}),
    );
    warnMock.mockReset();
  });

  it(
    "재로그인 + userInfo 제공 → updateUser 호출 (truth-of-source default)",
    async () => {
      const {db} = makeDb({
        preExists: true,
        txExists: true,
        txData: {firebaseUid: "existing-fol1"},
        loginUserDoc: {exists: true, data: {signUpProviderId: "naver"}},
      });

      await resolveIdentity(db, {
        provider: "naver",
        providerUserId: "naver-fol1",
        callerUid: undefined,
        userInfo: {
          email: "u@example.com",
          displayName: "신규닉",
          photoURL: "https://x/new.jpg",
        },
      });

      expect(mockUpdateUser).toHaveBeenCalledTimes(1);
      expect(mockUpdateUser).toHaveBeenCalledWith("existing-fol1", {
        email: "u@example.com",
        displayName: "신규닉",
        photoURL: "https://x/new.jpg",
      });
    },
  );

  it("재로그인 + userInfo 미제공 → updateUser 미호출", async () => {
    const {db} = makeDb({
      preExists: true,
      txExists: true,
      txData: {firebaseUid: "existing-fol2"},
    });

    await resolveIdentity(db, {
      provider: "naver",
      providerUserId: "naver-fol2",
      callerUid: undefined,
      userInfo: undefined,
    });

    expect(mockUpdateUser).not.toHaveBeenCalled();
  });

  it(
    "재로그인 + truth-of-source + photoURL 부재 → photoURL=null clear",
    async () => {
      const {db} = makeDb({
        preExists: true,
        txExists: true,
        txData: {firebaseUid: "existing-fol3"},
        loginUserDoc: {exists: true, data: {signUpProviderId: "naver"}},
      });

      await resolveIdentity(db, {
        provider: "naver",
        providerUserId: "naver-fol3",
        callerUid: undefined,
        userInfo: {
          email: "u@example.com",
          displayName: "닉네임",
          // photoURL 부재 — 사용자가 IdP 측에서 프로필 이미지 삭제한 시나리오.
        },
      });

      expect(mockUpdateUser).toHaveBeenCalledWith("existing-fol3", {
        email: "u@example.com",
        displayName: "닉네임",
        photoURL: null,
      });
    },
  );

  it(
    "재로그인 + updateUser 실패 → best-effort (logger.warn + 정상 반환)",
    async () => {
      mockUpdateUser.mockRejectedValueOnce(
        Object.assign(new Error("transient"), {
          code: "auth/internal-error",
        }),
      );
      const {db} = makeDb({
        preExists: true,
        txExists: true,
        txData: {firebaseUid: "existing-fol4"},
        loginUserDoc: {exists: true, data: {signUpProviderId: "naver"}},
      });

      const res = await resolveIdentity(db, {
        provider: "naver",
        providerUserId: "naver-fol4",
        callerUid: undefined,
        userInfo: {displayName: "x"},
      });

      // 정상 반환 — best-effort (R9 strict throw 와 차이).
      expect(res).toMatchObject({uid: "existing-fol4", isNewUser: false});

      // logger.warn 1회 + payload 에 event/uid/code 포함.
      expect(warnMock).toHaveBeenCalledTimes(1);
      expect(warnMock).toHaveBeenCalledWith(
        expect.objectContaining({
          event: "identity_index_profile_refresh_failed",
          uid: "existing-fol4",
          code: "auth/internal-error",
        }),
        expect.any(String),
      );

      // PII 회귀 (Pitfall 7) — err.message 본문 ('transient') 미노출.
      for (const args of warnMock.mock.calls) {
        expect(JSON.stringify(args)).not.toContain("transient");
      }
    },
  );
});

// quick 260928-jwe — 가입 수단 로그인 때만 프로필 갱신.
// 연결 수단(가입 수단이 아닌 Custom Token provider)으로 재로그인하면 Auth
// top-level email · displayName · photoURL 을 덮어쓰지 않는다 (16.9-04 R1).
// 판정 기준 = users/{uid}.signUpProviderId — tx 밖 best-effort read 1회.
// 기록 없음 · 읽기 실패는 보존(fail-closed) + logger.warn.
describe(
  // eslint-disable-next-line max-len
  "resolveIdentity quick-260928-jwe — 가입 수단 로그인 때만 프로필 갱신 (연결 수단 재로그인 보존)",
  () => {
    beforeEach(() => {
      jest.clearAllMocks();
      mockCreateUser.mockReset();
      mockDeleteUser.mockReset();
      mockUpdateUser.mockReset();
      mockUpdateUser.mockResolvedValue(undefined);
      mockGetUserByEmail.mockReset();
      mockGetUserByEmail.mockRejectedValue(
        Object.assign(new Error("not found"), {code: "auth/user-not-found"}),
      );
      mockGetUser.mockReset();
      mockGetUser.mockResolvedValue({emailVerified: true, providerData: []});
      warnMock.mockReset();
      infoMock.mockReset();
    });

    // PII sentinel — 로그 payload 에 새면 즉시 RED.
    const jweUserInfo = {
      email: "PII_JWE_EMAIL@example.com",
      displayName: "PII JWE Name",
      photoURL: "https://idp.example.com/PII_jwe.jpg",
    };

    /**
     * warn · info 호출 전체를 직렬화 — PII · 저장값 비노출 단언용.
     *
     * @return {string} 두 logger mock 의 호출 인자 JSON.
     */
    function serializeLogCalls(): string {
      return JSON.stringify([warnMock.mock.calls, infoMock.mock.calls]);
    }

    it(
      // eslint-disable-next-line max-len
      "JWE-1: 가입 수단 재로그인(저장값 naver · 로그인 naver) → updateUser 1회 · users read 는 runTransaction 뒤 tx 밖 1회",
      async () => {
        const {db, tx, userGet, callOrder} = makeDb({
          preExists: true,
          preData: {firebaseUid: "U-jwe-1"},
          txExists: true,
          txData: {firebaseUid: "U-jwe-1"},
          loginUserDoc: {exists: true, data: {signUpProviderId: "naver"}},
        });

        const res = await resolveIdentity(db, {
          provider: "naver",
          providerUserId: "naver-jwe-1",
          callerUid: undefined,
          userInfo: jweUserInfo,
        });

        expect(res).toEqual({
          uid: "U-jwe-1",
          isNewUser: false,
          conflictKind: null,
        });
        expect(mockUpdateUser).toHaveBeenCalledTimes(1);
        expect(mockUpdateUser).toHaveBeenCalledWith("U-jwe-1", {
          email: "PII_JWE_EMAIL@example.com",
          displayName: "PII JWE Name",
          photoURL: "https://idp.example.com/PII_jwe.jpg",
        });
        // D-03 · Pitfall 4 — read 는 transaction 밖 · 그 뒤.
        expect(callOrder.indexOf("runTransaction")).toBeGreaterThanOrEqual(0);
        expect(callOrder.indexOf("login-user-read")).toBeGreaterThan(
          callOrder.indexOf("runTransaction"),
        );
        expect(tx.get).toHaveBeenCalledTimes(1);
        expect(userGet).toHaveBeenCalledTimes(1);
        expect(warnMock).not.toHaveBeenCalled();
      },
    );

    it(
      // eslint-disable-next-line max-len
      "JWE-2: 연결 수단 재로그인(저장값 kakao · 로그인 naver) → updateUser 0 · info skipped_linked 1회 · 로그 PII · 저장값 0",
      async () => {
        const {db} = makeDb({
          preExists: true,
          preData: {firebaseUid: "U-jwe-2"},
          txExists: true,
          txData: {firebaseUid: "U-jwe-2"},
          loginUserDoc: {exists: true, data: {signUpProviderId: "kakao"}},
        });

        const res = await resolveIdentity(db, {
          provider: "naver",
          providerUserId: "naver-jwe-2",
          callerUid: undefined,
          userInfo: jweUserInfo,
        });

        expect(res).toEqual({
          uid: "U-jwe-2",
          isNewUser: false,
          conflictKind: null,
        });
        expect(mockUpdateUser).not.toHaveBeenCalled();
        expect(warnMock).not.toHaveBeenCalled();
        expect(infoMock).toHaveBeenCalledTimes(1);
        expect(infoMock).toHaveBeenCalledWith(
          expect.objectContaining({
            event: "identity_index_profile_refresh_skipped_linked",
            uid: "U-jwe-2",
            provider: "naver",
          }),
          expect.any(String),
        );
        const logged = serializeLogCalls();
        expect(logged).not.toContain("PII_JWE");
        expect(logged).not.toContain("PII JWE");
        expect(logged).not.toContain("kakao");
      },
    );

    it(
      // eslint-disable-next-line max-len
      "JWE-3: native 가입 기록값(저장값 google.com · 로그인 kakao) → updateUser 0 (역방향 시나리오)",
      async () => {
        const {db} = makeDb({
          preExists: true,
          preData: {firebaseUid: "U-jwe-3"},
          txExists: true,
          txData: {firebaseUid: "U-jwe-3"},
          loginUserDoc: {exists: true, data: {signUpProviderId: "google.com"}},
        });

        const res = await resolveIdentity(db, {
          provider: "kakao",
          providerUserId: "kakao-jwe-3",
          callerUid: undefined,
          userInfo: jweUserInfo,
        });

        expect(res).toMatchObject({uid: "U-jwe-3", isNewUser: false});
        expect(mockUpdateUser).not.toHaveBeenCalled();
      },
    );

    it.each([
      ["문서 없음", undefined],
      ["필드 없음", {exists: true, data: {}}],
      ["문자열 아님", {exists: true, data: {signUpProviderId: 123}}],
    ] as const)(
      // eslint-disable-next-line max-len
      "JWE-4: 가입 수단 기록 %s → updateUser 0 + warn signup_missing 1회 (fail-closed 보존)",
      async (_label, loginUserDoc) => {
        const {db} = makeDb({
          preExists: true,
          preData: {firebaseUid: "U-jwe-4"},
          txExists: true,
          txData: {firebaseUid: "U-jwe-4"},
          loginUserDoc,
        });

        const res = await resolveIdentity(db, {
          provider: "naver",
          providerUserId: "naver-jwe-4",
          callerUid: undefined,
          userInfo: jweUserInfo,
        });

        expect(res).toMatchObject({uid: "U-jwe-4", isNewUser: false});
        expect(mockUpdateUser).not.toHaveBeenCalled();
        expect(warnMock).toHaveBeenCalledTimes(1);
        expect(warnMock).toHaveBeenCalledWith(
          expect.objectContaining({
            event: "identity_index_profile_refresh_signup_missing",
            uid: "U-jwe-4",
            provider: "naver",
          }),
          expect.any(String),
        );
        const logged = serializeLogCalls();
        expect(logged).not.toContain("PII_JWE");
        expect(logged).not.toContain("PII JWE");
      },
    );

    it(
      // eslint-disable-next-line max-len
      "JWE-5: users read 실패 → updateUser 0 + warn signup_read_failed(code 만) · 로그인 결과 정상",
      async () => {
        const {db} = makeDb({
          preExists: true,
          preData: {firebaseUid: "U-jwe-5"},
          txExists: true,
          txData: {firebaseUid: "U-jwe-5"},
          loginUserReadRejects: true,
        });

        const res = await resolveIdentity(db, {
          provider: "line",
          providerUserId: "line-jwe-5",
          callerUid: undefined,
          userInfo: jweUserInfo,
        });

        expect(res).toEqual({
          uid: "U-jwe-5",
          isNewUser: false,
          conflictKind: null,
        });
        expect(mockUpdateUser).not.toHaveBeenCalled();
        expect(warnMock).toHaveBeenCalledTimes(1);
        expect(warnMock).toHaveBeenCalledWith(
          expect.objectContaining({
            event: "identity_index_profile_refresh_signup_read_failed",
            uid: "U-jwe-5",
            provider: "line",
            code: "unavailable",
          }),
          expect.any(String),
        );
        // Pitfall 7 — err.message 본문 미노출.
        const logged = serializeLogCalls();
        expect(logged).not.toContain("PII_JWE_READ_ERR");
        expect(logged).not.toContain("PII JWE");
      },
    );

    it(
      "JWE-6: 재로그인 + userInfo 없음 → users read 0 · updateUser 0",
      async () => {
        const {db, userGet} = makeDb({
          preExists: true,
          preData: {firebaseUid: "U-jwe-6"},
          txExists: true,
          txData: {firebaseUid: "U-jwe-6"},
          loginUserDoc: {exists: true, data: {signUpProviderId: "naver"}},
        });

        await resolveIdentity(db, {
          provider: "naver",
          providerUserId: "naver-jwe-6",
          callerUid: undefined,
          userInfo: undefined,
        });

        expect(userGet).not.toHaveBeenCalled();
        expect(mockUpdateUser).not.toHaveBeenCalled();
      },
    );

    it.each(["kakao", "naver", "line"] as const)(
      // eslint-disable-next-line max-len
      "JWE-7: %s 신규 등록이 쓴 signUpProviderId → 같은 provider 재로그인 → updateUser 1회 (형식 일치 왕복)",
      async (p) => {
        // 1단계 — 신규 등록이 users 에 쓰는 가입 수단 값을 캡처.
        const first = makeDb({preExists: false, txExists: false});
        await resolveIdentity(first.db, {
          provider: p,
          providerUserId: `${p}-jwe-7`,
          callerUid: `anon-jwe-${p}`,
          callerIsAnonymous: true,
        });
        const userSetCall = first.tx.set.mock.calls.find(
          (c) => c[0] === first.userRef,
        );
        const written = (userSetCall?.[1] as {signUpProviderId?: unknown})
          ?.signUpProviderId;
        expect(written).toBe(p);
        mockUpdateUser.mockClear();

        // 2단계 — 그 값을 그대로 저장값으로 두고 같은 provider 로 재로그인.
        const second = makeDb({
          preExists: true,
          preData: {firebaseUid: `U-jwe-${p}`},
          txExists: true,
          txData: {firebaseUid: `U-jwe-${p}`},
          loginUserDoc: {exists: true, data: {signUpProviderId: written}},
        });
        await resolveIdentity(second.db, {
          provider: p,
          providerUserId: `${p}-jwe-7`,
          callerUid: undefined,
          userInfo: {displayName: "n"},
        });

        expect(mockUpdateUser).toHaveBeenCalledTimes(1);
        expect(mockUpdateUser).toHaveBeenCalledWith("U-jwe-" + p, {
          displayName: "n",
          photoURL: null,
        });
      },
    );
  },
);

// Phase 16 D-09 (Plan 16-03 Task 3.1) — IdentityResolution 에 add-only
// `existingProvider: ProviderId | "unknown"` 필드 추가. 기존 conflictKind union
// switch case 의 schema 보존 (회귀 0) + 신규 add-only 필드만 추가.
// Plan 16-04 의 client catch 시 conflictKind + existingProvider 로 정확한
// provider 라벨 즉시 전달 (server 추가 조회 0).
describe("resolveIdentity Phase 16 D-09 — existingProvider add-only", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockCreateUser.mockReset();
    mockDeleteUser.mockReset();
    mockUpdateUser.mockReset();
    mockUpdateUser.mockResolvedValue(undefined);
    mockGetUserByEmail.mockReset();
    mockGetUserByEmail.mockRejectedValue(
      Object.assign(new Error("not found"), {code: "auth/user-not-found"}),
    );
    warnMock.mockReset();
  });

  it(
    // eslint-disable-next-line max-len
    "I1: 기존 conflictKind=null 회귀 — existingProvider 미설정 (기존 caller switch 보존)",
    async () => {
      const {db} = makeDb({
        preExists: true,
        txExists: true,
        txData: {firebaseUid: "user-I1"},
      });

      const res = await resolveIdentity(db, {
        provider: "kakao",
        providerUserId: "kakao-I1",
        callerUid: undefined,
        userInfo: undefined,
      });

      expect(res).toMatchObject({
        uid: "user-I1",
        isNewUser: false,
        conflictKind: null,
      });
      // 정상 path 에는 existingProvider 필드가 노출되지 않음 (캐리어 default).
      expect(res.existingProvider).toBeUndefined();
    },
  );

  it(
    // eslint-disable-next-line max-len
    "I2: email_in_use (caller-path) + providerData=[google.com] → existingProvider='google'",
    async () => {
      // Gap B (callerUid + email) path 의 collision detect → existingProvider
      // 가 conflicting provider 의 첫 known IdP 매핑.
      mockGetUserByEmail.mockResolvedValueOnce({
        uid: "google-uid-99",
        providerData: [{providerId: "google.com", uid: "google-platform-id"}],
      });
      const {db} = makeDb({preExists: false, txExists: false});

      const res = await resolveIdentity(db, {
        provider: "kakao",
        providerUserId: "kakao-I2",
        callerUid: "anon-I2",
        callerIsAnonymous: true,
        userInfo: {email: "i2@example.com"},
      });

      expect(res).toMatchObject({
        uid: "",
        isNewUser: false,
        conflictKind: "email_in_use",
        existingProvider: "google",
      });

      // PII regression sentinel — email / IdP uid 본문 미노출.
      for (const args of warnMock.mock.calls) {
        const s = JSON.stringify(args);
        expect(s).not.toContain("i2@example.com");
        expect(s).not.toContain("google-platform-id");
        expect(s).not.toContain("google-uid-99");
      }
    },
  );

  it(
    // eslint-disable-next-line max-len
    "I3: anonymous_existing_collision → existingProvider = 충돌 trigger provider (kakao)",
    async () => {
      // identity_index 의 기존 매핑은 `provider:providerUserId` 의 provider 자체
      // 가 trigger. anonymous user 가 동일 provider 의 기존 user 와 collision —
      // existingProvider 는 caller 가 호출한 provider slug 자체 (kakao).
      const {db} = makeDb({
        preExists: true,
        txExists: true,
        txData: {firebaseUid: "existing-B"},
      });

      const res = await resolveIdentity(db, {
        provider: "kakao",
        providerUserId: "kakao-I3",
        callerUid: "anon-I3",
        callerIsAnonymous: true,
        userInfo: undefined,
      });

      expect(res).toMatchObject({
        uid: "existing-B",
        isNewUser: false,
        conflictKind: "anonymous_existing_collision",
        existingProvider: "kakao",
      });
    },
  );

  it(
    // eslint-disable-next-line max-len
    "I4: email_in_use (caller-path) + providerData=[twitter.com] (미정의 provider) → existingProvider='unknown'",
    async () => {
      // providerData 매핑 실패 (twitter.com — NATIVE_PROVIDER_MAP 미정의) →
      // 'unknown' fallback. client 가 generic 라벨 표시 가능.
      mockGetUserByEmail.mockResolvedValueOnce({
        uid: "x-uid-99",
        providerData: [{providerId: "twitter.com", uid: "x-platform-id"}],
      });
      const {db} = makeDb({preExists: false, txExists: false});

      const res = await resolveIdentity(db, {
        provider: "kakao",
        providerUserId: "kakao-I4",
        callerUid: "anon-I4",
        callerIsAnonymous: true,
        userInfo: {email: "i4@example.com"},
      });

      expect(res).toMatchObject({
        uid: "",
        isNewUser: false,
        conflictKind: "email_in_use",
        existingProvider: "unknown",
      });
    },
  );

  it(
    // eslint-disable-next-line max-len
    "I5: ProviderId type export — 7값 enum 보존 (Plan 16-04 Flutter mirror baseline)",
    async () => {
      // 컴파일 타임 sentinel — 본 case 는 type-level 검증. import 시점에
      // ProviderId 가 7값 literal union 인지 확인 (TS 가 강제). 본 runtime
      // 검증은 const literal 로 캐스팅 가능 여부만 sanity check.
      const providers: Array<ProviderId> = [
        "google", "apple", "facebook", "email",
        "kakao", "naver", "line",
      ];
      expect(providers.length).toBe(7);
    },
  );
});

// Plan 16-17 (A4 finding 2026-06-11 / SC3b gap closure) — Custom Token 으로
// 생성된 기존 계정은 Firebase Auth providerData 가 비어 있어
// mapProviderDataToProviderId 가 구조적으로 'unknown' 만 반환한다. identity_
// index 역조회(where firebaseUid == uid → provider)로 Custom Token
// existingProvider 를 해석하는 2단 정책의 회귀 잠금.
// eslint-disable-next-line max-len
describe("resolveIdentity Phase 16 Plan 16-17 — Custom Token existingProvider 역조회", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockCreateUser.mockReset();
    mockDeleteUser.mockReset();
    mockUpdateUser.mockReset();
    mockUpdateUser.mockResolvedValue(undefined);
    mockGetUserByEmail.mockReset();
    mockGetUserByEmail.mockRejectedValue(
      Object.assign(new Error("not found"), {code: "auth/user-not-found"}),
    );
    warnMock.mockReset();
  });

  it(
    // eslint-disable-next-line max-len
    "T-16-17-01 (A4 tracer): Kakao Custom Token 기존 계정 + Naver caller → existingProvider='kakao'",
    async () => {
      // A4 시나리오 — Kakao 로 가입된 custom-token user (providerData 비어
      // 있음) 와 동일 email 로 Naver 로그인 시도.
      mockGetUserByEmail.mockResolvedValueOnce({
        uid: "PII_KAKAO_UID_A",
        providerData: [],
      });
      const {db, where, whereGet} = makeDb({
        preExists: false,
        txExists: false,
        reverseDocs: [{provider: "kakao"}],
      });

      const res = await resolveIdentity(db, {
        provider: "naver",
        providerUserId: "naver-16-17-tracer",
        callerUid: "anon-16-17-tracer",
        callerIsAnonymous: true,
        userInfo: {email: "PII_TRACER_EMAIL@example.com"},
      });

      expect(res).toMatchObject({
        uid: "",
        isNewUser: false,
        conflictKind: "email_in_use",
        existingProvider: "kakao",
      });
      // 역조회 쿼리 인자 검증 — 단일 필드 equality (자동 인덱스 충족).
      expect(where).toHaveBeenCalledWith(
        "firebaseUid",
        "==",
        "PII_KAKAO_UID_A",
      );
      expect(whereGet).toHaveBeenCalledTimes(1);

      // 신규 event 발동 — provider + existingProvider slug 만.
      expect(warnMock).toHaveBeenCalledWith(
        expect.objectContaining({
          event: "identity_index_email_collision_custom_token_path",
          provider: "naver",
          existingProvider: "kakao",
        }),
        expect.any(String),
      );

      // PII regression sentinel — email / 기존 uid 본문 미노출 (D-51).
      for (const args of warnMock.mock.calls) {
        const s = JSON.stringify(args);
        expect(s).not.toContain("PII_TRACER_EMAIL@example.com");
        expect(s).not.toContain("PII_KAKAO_UID_A");
      }
    },
  );

  it(
    // eslint-disable-next-line max-len
    "T-16-17-02 (경계 0건): 역조회 후보 0 → 충돌 아님 + 정상 sign-in path 진행",
    async () => {
      // false-positive 차단 정책의 회귀 잠금 (T-16-17-02) — email 만 같고
      // 어떤 provider 도 식별되지 않으면 정당한 로그인을 막지 않는다.
      mockGetUserByEmail.mockResolvedValueOnce({
        uid: "unknown-source-uid",
        providerData: [],
      });
      const {db, whereGet} = makeDb({
        preExists: false,
        txExists: false,
        reverseDocs: [],
      });

      const res = await resolveIdentity(db, {
        provider: "naver",
        providerUserId: "naver-16-17-empty",
        callerUid: "anon-16-17-empty",
        callerIsAnonymous: true,
        userInfo: {email: "empty@example.com"},
      });

      expect(res.conflictKind).toBeNull();
      expect(res.isNewUser).toBe(true);
      expect(whereGet).toHaveBeenCalledTimes(1);
    },
  );

  it(
    // eslint-disable-next-line max-len
    "T-16-17-03 (경계 자기자신): 역조회 결과가 caller 와 동일 provider 1건뿐 → 충돌 아님",
    async () => {
      // 동일 provider **동일 sub** 재로그인 — self-identity 는 충돌이 아니다.
      // WR-03 (4차 리뷰) 이후 self 판정 기준이 providerUserId 이므로 fixture 도
      // caller 와 같은 sub 를 담아야 이 테스트의 의도(자기 계정 재로그인)가
      // 성립한다. sub 가 다른 경우는 T-16-17-12 가 반대 방향으로 잠근다.
      mockGetUserByEmail.mockResolvedValueOnce({
        uid: "self-source-uid",
        providerData: [],
      });
      const {db} = makeDb({
        preExists: false,
        txExists: false,
        reverseDocs: [
          {provider: "naver", providerUserId: "naver-16-17-self"},
        ],
      });

      const res = await resolveIdentity(db, {
        provider: "naver",
        providerUserId: "naver-16-17-self",
        callerUid: "anon-16-17-self",
        callerIsAnonymous: true,
        userInfo: {email: "self@example.com"},
      });

      expect(res.conflictKind).toBeNull();
      expect(res.existingProvider).toBeUndefined();
    },
  );

  it(
    // eslint-disable-next-line max-len
    "T-16-17-04 (경계 2건 이상/결정성): 문서 입력 순서를 뒤집어도 우선순위 첫 후보가 선택된다",
    async () => {
      // CUSTOM_TOKEN_PROVIDER_PRIORITY = kakao > naver > line.
      // caller=naver, 기존 계정이 line + kakao 보유 → 항상 'kakao'.
      const runOnce = async (
        docs: Array<{provider: unknown}>,
        suffix: string,
      ) => {
        mockGetUserByEmail.mockResolvedValueOnce({
          uid: `multi-source-uid-${suffix}`,
          providerData: [],
        });
        const {db} = makeDb({
          preExists: false,
          txExists: false,
          reverseDocs: docs,
        });
        return resolveIdentity(db, {
          provider: "naver",
          providerUserId: `naver-16-17-multi-${suffix}`,
          callerUid: `anon-16-17-multi-${suffix}`,
          callerIsAnonymous: true,
          userInfo: {email: `multi-${suffix}@example.com`},
        });
      };

      const forward = await runOnce(
        [{provider: "line"}, {provider: "kakao"}],
        "fwd",
      );
      const reversed = await runOnce(
        [{provider: "kakao"}, {provider: "line"}],
        "rev",
      );

      expect(forward).toMatchObject({
        conflictKind: "email_in_use",
        existingProvider: "kakao",
      });
      // 입력 순서 무관 동일 결과 (결정성).
      expect(reversed.existingProvider).toBe(forward.existingProvider);
    },
  );

  it(
    // eslint-disable-next-line max-len
    "T-16-17-05 (쿼리 실패): 역조회 reject → graceful null + 충돌 미보고 + PII 미노출",
    async () => {
      mockGetUserByEmail.mockResolvedValueOnce({
        uid: "PII_REJECT_UID",
        providerData: [],
      });
      const {db} = makeDb({
        preExists: false,
        txExists: false,
        reverseRejects: true,
      });

      const res = await resolveIdentity(db, {
        provider: "naver",
        providerUserId: "naver-16-17-reject",
        callerUid: "anon-16-17-reject",
        callerIsAnonymous: true,
        userInfo: {email: "PII_REJECT_EMAIL@example.com"},
      });

      // best-effort — 쿼리 실패가 정당한 로그인을 차단하지 않는다.
      expect(res.conflictKind).toBeNull();
      expect(warnMock).toHaveBeenCalledWith(
        expect.objectContaining({
          event: "identity_index_reverse_lookup_failed",
          code: "unavailable",
        }),
        expect.any(String),
      );
      for (const args of warnMock.mock.calls) {
        const s = JSON.stringify(args);
        expect(s).not.toContain("PII_REJECT_EMAIL@example.com");
        expect(s).not.toContain("PII_REJECT_UID");
      }
    },
  );

  it(
    // eslint-disable-next-line max-len
    "T-16-17-06 (native 회귀): providerData=[google.com] → 역조회 미호출 + existingProvider='google'",
    async () => {
      // 1단(native) 해석이 성공하면 2단(Custom Token)은 진입하지 않는다 —
      // I2/I4 기대값 불변 + 불필요한 Firestore read 0.
      mockGetUserByEmail.mockResolvedValueOnce({
        uid: "google-uid-16-17",
        providerData: [{providerId: "google.com", uid: "google-platform-id"}],
      });
      const {db, where, whereGet} = makeDb({
        preExists: false,
        txExists: false,
        reverseDocs: [{provider: "kakao"}],
      });

      const res = await resolveIdentity(db, {
        provider: "naver",
        providerUserId: "naver-16-17-native",
        callerUid: "anon-16-17-native",
        callerIsAnonymous: true,
        userInfo: {email: "native@example.com"},
      });

      expect(res).toMatchObject({
        conflictKind: "email_in_use",
        existingProvider: "google",
      });
      expect(where).not.toHaveBeenCalled();
      expect(whereGet).not.toHaveBeenCalled();
    },
  );

  it(
    // eslint-disable-next-line max-len
    "T-16-17-07 (미인증 caller): createUser email-already-in-use + 역조회 kakao → existingProvider='kakao'",
    async () => {
      // !callerUid path — 충돌 자체는 기존에도 감지됐으나 라벨이 'unknown'
      // 으로 떨어지던 경로. 역조회 fallback 으로 정확한 slug 산출.
      mockCreateUser.mockRejectedValueOnce(
        Object.assign(new Error("email exists"), {
          code: "auth/email-already-in-use",
        }),
      );
      mockGetUserByEmail.mockResolvedValueOnce({
        uid: "PII_CREATEUSER_UID",
        providerData: [],
      });
      const {db, where} = makeDb({
        preExists: false,
        txExists: false,
        reverseDocs: [{provider: "kakao"}],
      });

      const res = await resolveIdentity(db, {
        provider: "naver",
        providerUserId: "naver-16-17-createuser",
        callerUid: undefined,
        userInfo: {email: "PII_CREATEUSER_EMAIL@example.com"},
      });

      expect(res).toMatchObject({
        uid: "",
        isNewUser: false,
        conflictKind: "email_in_use",
        existingProvider: "kakao",
      });
      expect(where).toHaveBeenCalledWith(
        "firebaseUid",
        "==",
        "PII_CREATEUSER_UID",
      );
      for (const args of warnMock.mock.calls) {
        const s = JSON.stringify(args);
        expect(s).not.toContain("PII_CREATEUSER_EMAIL@example.com");
        expect(s).not.toContain("PII_CREATEUSER_UID");
      }
    },
  );

  it(
    // eslint-disable-next-line max-len
    "T-16-17-08 (읽기 순서): 역조회 get 이 db.runTransaction 보다 먼저 호출된다",
    async () => {
      // T-16-17-03 회귀 잠금 — 역조회는 transaction *밖* 선행 read 다.
      // (WR-05 MockTx phase tracker 는 transaction *안* 순서를 담당하고,
      //  본 케이스는 transaction 밖 순서를 담당한다.)
      mockGetUserByEmail.mockResolvedValueOnce({
        uid: "order-source-uid",
        providerData: [],
      });
      const {db, callOrder} = makeDb({
        preExists: false,
        txExists: false,
        reverseDocs: [],
      });

      await resolveIdentity(db, {
        provider: "naver",
        providerUserId: "naver-16-17-order",
        callerUid: "anon-16-17-order",
        callerIsAnonymous: true,
        userInfo: {email: "order@example.com"},
      });

      expect(callOrder).toContain("reverse-lookup");
      expect(callOrder).toContain("runTransaction");
      expect(callOrder.indexOf("reverse-lookup")).toBeLessThan(
        callOrder.indexOf("runTransaction"),
      );
    },
  );

  // Plan 16-17 — 3 caller × CT-existing 양방향 매트릭스 (helper 레벨).
  // LINE endpoint 의 실제 발화는 line_custom_token.test.ts 의 CT-existing
  // 교체본이 잠근다 (quick 260928-luw) — 여기서는 caller 종류와 무관한
  // helper 규칙 (동일 규칙으로 동작) 을 잠근다.
  // IN-07 (Phase 15 리뷰): resolveIdentity 의 provider 가 ProviderId 로
  // 좁혀졌으므로 매트릭스 fixture 도 같은 union 으로 선언한다 — 오타 슬러그가
  // 컴파일 단계에서 걸린다.
  const matrix: Array<[ProviderId, ProviderId]> = [
    ["kakao", "naver"],
    ["naver", "kakao"],
    ["line", "kakao"],
    ["line", "naver"],
  ];
  it.each(matrix)(
    // eslint-disable-next-line max-len
    "T-16-17-09 (매트릭스): caller=%s + 기존 %s Custom Token 계정 → 그 slug 산출",
    async (caller: ProviderId, existing: ProviderId) => {
      mockGetUserByEmail.mockResolvedValueOnce({
        uid: `matrix-uid-${caller}`,
        providerData: [],
      });
      const {db} = makeDb({
        preExists: false,
        txExists: false,
        reverseDocs: [{provider: existing}],
      });

      const res = await resolveIdentity(db, {
        provider: caller,
        providerUserId: `${caller}-16-17-matrix`,
        callerUid: `anon-16-17-matrix-${caller}`,
        callerIsAnonymous: true,
        userInfo: {email: `matrix-${caller}@example.com`},
      });

      expect(res).toMatchObject({
        conflictKind: "email_in_use",
        existingProvider: existing,
      });
    },
  );

  // CR-01 / WR-06 (2차 리뷰 2026-09-09) — proactive linking
  // (link_custom_token_provider) 성공 시마다 동일 firebaseUid 로 2번째
  // identity_index 문서가 생기는 multi-identity 계정 상태. 16-17 최초 테스트
  // 9건은 전부 reverseDocs 0~1건 단일 identity 라 이 상태를 잠그지 못했다.
  it(
    // eslint-disable-next-line max-len
    "T-16-17-10 (multi-identity): 기존 계정이 caller provider 를 이미 보유 → 충돌 아님 (형제 slug 미노출)",
    async () => {
      // Kakao 가입 후 설정 > 계정 연결로 LINE 을 연결한 계정 U 가, 새 단말의
      // 익명 caller 로 Kakao 재로그인 하는 경로. 형제 slug 'line' 을 라벨로
      // 내보내면 사용자에게 쓰지도 않는 provider 로 로그인하라고 안내하게
      // 된다 (AccountLinkingSheet step 1 CTA = signInWithLine).
      mockGetUserByEmail.mockResolvedValueOnce({
        uid: "U-multi-identity",
        providerData: [],
      });
      // naver-self-email-collision (2026-09-17): 비-tx 스냅샷도 실측 문서
      // shape 를 담는다. 이전 fixture 는 `data` 없는 `{exists: true}` 라 Step
      // 0.5 가 매핑 uid 를 읽을 때 TypeError → lookup_failed 로 삼켜진 채
      // 통과했다. 이제 매핑 uid === email 소유 uid 라 self 로 판정되어 역조회
      // 전에 transaction 으로 위임된다 (역조회 selfMatched 단위는 T-16-17-03
      // 이 계속 잠근다).
      const multiIdentityDoc = {
        firebaseUid: "U-multi-identity",
        provider: "kakao",
        providerUserId: "kakao-16-17-multi-identity",
        linkedAt: "MOCK_TIMESTAMP",
        lastSeenAt: "MOCK_TIMESTAMP",
      };
      const {db} = makeDb({
        preExists: true,
        preData: multiIdentityDoc,
        txExists: true,
        txData: multiIdentityDoc,
        // WR-03: caller 자신의 문서는 provider + sub 가 **둘 다** 일치한다.
        reverseDocs: [
          {provider: "kakao", providerUserId: "kakao-16-17-multi-identity"},
          {provider: "line", providerUserId: "line-sub-16-17"},
        ],
      });

      const res = await resolveIdentity(db, {
        provider: "kakao",
        providerUserId: "kakao-16-17-multi-identity",
        callerUid: "anon-16-17-multi-identity",
        callerIsAnonymous: true,
        userInfo: {email: "multi-identity@example.com"},
      });

      // 형제 slug('line')를 라벨로 내보내면 안 된다 (CR-01 회귀 잠금).
      expect(res.existingProvider).not.toBe("line");
      // 역조회가 null 을 돌려 기존 transaction 경로에 위임 → caller 자신의
      // slug 라벨 (anonymous_existing_collision) 로 착지한다.
      expect(res).toMatchObject({
        uid: "U-multi-identity",
        isNewUser: false,
        conflictKind: "anonymous_existing_collision",
        existingProvider: "kakao",
      });
      // custom-token 역조회 경로의 email_in_use 조기 return 미발동.
      expect(warnMock).not.toHaveBeenCalledWith(
        expect.objectContaining({
          event: "identity_index_email_collision_custom_token_path",
        }),
        expect.any(String),
      );
    },
  );

  it(
    // eslint-disable-next-line max-len
    "T-16-17-11 (multi-identity, 진짜 충돌): caller 자신 identity 부재 → 우선순위 첫 slug",
    async () => {
      // 기존 계정이 LINE + Naver 를 보유하고 caller 는 Kakao — caller 자신의
      // identity 가 없으므로 정당한 cross-provider 충돌이다. selfMatched
      // 단축이 이 경로까지 삼키지 않음을 잠근다 (CR-01 fix 의 과잉 차단 방지).
      mockGetUserByEmail.mockResolvedValueOnce({
        uid: "U-multi-conflict",
        providerData: [],
      });
      const {db} = makeDb({
        preExists: false,
        txExists: false,
        reverseDocs: [{provider: "line"}, {provider: "naver"}],
      });

      const res = await resolveIdentity(db, {
        provider: "kakao",
        providerUserId: "kakao-16-17-multi-conflict",
        callerUid: "anon-16-17-multi-conflict",
        callerIsAnonymous: true,
        userInfo: {email: "multi-conflict@example.com"},
      });

      // CUSTOM_TOKEN_PROVIDER_PRIORITY = kakao > naver > line.
      expect(res).toMatchObject({
        uid: "",
        isNewUser: false,
        conflictKind: "email_in_use",
        existingProvider: "naver",
      });
    },
  );

  // WR-03 (4차 리뷰) — CR-01 fix 가 연 좁은 신규 경로. selfMatched 가 provider
  // slug 만 보면 "같은 provider 의 다른 sub" 를 자기 계정으로 오인해 충돌을
  // 통과시킨다. 그러면 tx 가 익명 uid 를 가리키는 identity_index 문서를
  // 커밋한 뒤 getAuth().updateUser 가 auth/email-already-exists 로 throw 하고
  // (try/catch 밖 — caller 에게 internal), 잘못된 문서는 영구 잔존한다.
  it(
    // eslint-disable-next-line max-len
    "T-16-17-12 (동일 provider·다른 sub): self 오인 없이 정당한 충돌로 차단 (WR-03)",
    async () => {
      // IdP 계정 탈퇴 후 동일 이메일로 재가입 → sub 변경 시나리오. 기존 계정
      // U 는 kakao:subA + line:subB 를 보유하고, caller 는 같은 kakao 이지만
      // sub 가 subC 다 — 즉 **다른 계정**이므로 통과시키면 안 된다.
      mockGetUserByEmail.mockResolvedValueOnce({
        uid: "U-same-provider-other-sub",
        providerData: [],
      });
      const {db} = makeDb({
        preExists: false,
        txExists: false,
        reverseDocs: [
          {provider: "kakao", providerUserId: "subA"},
          {provider: "line", providerUserId: "subB"},
        ],
      });

      const res = await resolveIdentity(db, {
        provider: "kakao",
        providerUserId: "subC",
        callerUid: "anon-16-17-other-sub",
        callerIsAnonymous: true,
        userInfo: {email: "other-sub@example.com"},
      });

      // sub 불일치 = 정당한 충돌. 라벨은 caller 와 같은 'kakao' 가 정확하다
      // (사용자가 실제로 그 계정에 도달할 때 쓰는 수단이다).
      expect(res).toMatchObject({
        uid: "",
        isNewUser: false,
        conflictKind: "email_in_use",
        existingProvider: "kakao",
      });
      // 신규 identity_index 문서가 커밋되면 안 된다 (영구 잔존 오염 차단).
      expect(res.isNewUser).toBe(false);
    },
  );
});

// ---------------------------------------------------------------------------
// naver-self-email-collision (2026-09-17 debug) — 기존 identity 재로그인의
// 자기 계정 email 충돌 오판 회귀 가드.
//
// iOS batch UAT (quick 260914-wbr G6) 실측: identity_index naver 문서가 계정 U
// 를 가리키고, U 는 Custom Token 계정(customAuth) 에 apple.com 이 붙은 상태였다.
// 로그아웃 뒤 새 익명 caller 로 Naver 로그인하면 getUserByEmail 이 **U 자신**
// 을 돌려주지만, 1단 isSelf 가 callerUid(익명) 와만 비교해 apple.com 을 충돌로
// 잡았다 → HTTP 409 `identity_index_email_collision_caller_path`
// {conflictingProviderCount 1, existingProvider apple}.
//
// fixture 는 dev 원장 실측 shape 를 따른다 (email · platform uid 본문은 가짜 값).
// - identity_index 문서: {firebaseUid, provider, providerUserId, linkedAt,
//   lastSeenAt} (g5-firestore-identity-index.json 필드 5개)
// - 기존 계정: customAuth + email + providerData 1건 (ledger-g6-before-auth
//   .json 의 uBZ6 — providerUserInfo [apple.com])
// - 익명 caller 의 users 문서 404 (g5-firestore-users-cOn5-M44t.json)
// ---------------------------------------------------------------------------
// eslint-disable-next-line max-len
describe("resolveIdentity — 기존 identity 재로그인은 자기 계정 email 충돌이 아니다 (naver-self-email-collision)", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockCreateUser.mockReset();
    mockDeleteUser.mockReset();
    mockUpdateUser.mockReset();
    mockUpdateUser.mockResolvedValue(undefined);
    mockGetUserByEmail.mockReset();
    mockGetUserByEmail.mockRejectedValue(
      Object.assign(new Error("not found"), {code: "auth/user-not-found"}),
    );
    mockGetUser.mockReset();
    mockGetUser.mockResolvedValue({emailVerified: true, providerData: []});
    warnMock.mockReset();
  });

  /**
   * identity_index 문서 실측 shape (필드 5개) 를 만든다.
   *
   * @param {ProviderId} provider provider slug.
   * @param {string} providerUserId IdP sub (문서 ID 뒤쪽과 동일).
   * @param {string} firebaseUid 매핑된 Firebase UID.
   * @return {Record<string, unknown>} identity_index 문서 data.
   */
  function indexDoc(
    provider: ProviderId,
    providerUserId: string,
    firebaseUid: string,
  ): Record<string, unknown> {
    return {
      firebaseUid,
      provider,
      providerUserId,
      linkedAt: "MOCK_TIMESTAMP",
      lastSeenAt: "MOCK_TIMESTAMP",
    };
  }

  /**
   * getUserByEmail 이 돌려주는 기존 계정 UserRecord shape — Custom Token
   * 계정에 native provider 1건이 붙은 상태.
   *
   * @param {string} uid 기존 계정 UID.
   * @param {string} nativeProviderId Firebase 표기 native providerId.
   * @return {object} admin SDK UserRecord 부분 shape.
   */
  function customTokenUserWithNative(uid: string, nativeProviderId: string) {
    return {
      uid,
      email: "PII_SELF_EMAIL@example.com",
      emailVerified: true,
      customClaims: undefined,
      providerData: [
        {
          providerId: nativeProviderId,
          uid: "PII_NATIVE_PLATFORM_UID",
          email: "PII_SELF_EMAIL@example.com",
        },
      ],
    };
  }

  const selfMatrix: Array<[ProviderId, string, string]> = [
    // [caller provider, 기존 계정에 붙은 native providerId, 기대하지 않는 라벨]
    ["naver", "apple.com", "apple"], // G6 실측 조합.
    ["naver", "google.com", "google"],
    ["naver", "facebook.com", "facebook"],
    ["naver", "password", "email"],
    ["kakao", "apple.com", "apple"], // 비즈 앱 email 전달 시 같은 경로.
  ];
  it.each(selfMatrix)(
    // eslint-disable-next-line max-len
    "SELF-IDX-01: caller=%s · 기존 계정(=identity 매핑 uid) 에 %s 부착 · 익명 caller → 매핑 uid 로 로그인 (충돌 아님)",
    async (provider, nativeProviderId, notLabel) => {
      const sub = `${provider}-self-sub`;
      const doc = indexDoc(provider, sub, "U-self-indexed");
      mockGetUserByEmail.mockResolvedValueOnce(
        customTokenUserWithNative("U-self-indexed", nativeProviderId),
      );
      const {db, tx, whereGet} = makeDb({
        preExists: true,
        preData: doc,
        txExists: true,
        txData: doc,
        // 로그아웃 뒤 새 익명 caller — users 문서 404 (G5 실측).
        callerUserExists: false,
      });

      const res = await resolveIdentity(db, {
        provider,
        providerUserId: sub,
        callerUid: "anon-after-signout",
        callerIsAnonymous: true,
        userInfo: {
          email: "PII_SELF_EMAIL@example.com",
          emailVerified: true,
          displayName: "nick",
        },
      });

      expect(res).toMatchObject({
        uid: "U-self-indexed",
        isNewUser: false,
        conflictKind: null,
      });
      expect(res.existingProvider).toBeUndefined();
      expect(res.existingProvider).not.toBe(notLabel);
      // 1단 · 2단 충돌 이벤트 모두 미발동.
      for (const event of [
        "identity_index_email_collision_caller_path",
        "identity_index_email_collision_custom_token_path",
      ]) {
        expect(warnMock).not.toHaveBeenCalledWith(
          expect.objectContaining({event}),
          expect.any(String),
        );
      }
      // identity 가 이미 자기 계정 매핑임을 알았으므로 역조회 read 추가 0.
      expect(whereGet).not.toHaveBeenCalled();
      // transaction 안 read 는 idx + caller users 2건뿐 (새 tx read 없음).
      expect(tx.get).toHaveBeenCalledTimes(2);
      // 신규 identity 문서 커밋 0.
      expect(tx.set).not.toHaveBeenCalled();
      // PII sentinel — email · platform uid 본문 미노출.
      for (const args of warnMock.mock.calls) {
        const s = JSON.stringify(args);
        expect(s).not.toContain("PII_SELF_EMAIL@example.com");
        expect(s).not.toContain("PII_NATIVE_PLATFORM_UID");
      }
    },
  );

  it(
    // eslint-disable-next-line max-len
    "SELF-IDX-02 (경계 — 다른 계정): identity 매핑 uid ≠ email 소유 uid → native 충돌 그대로 보고",
    async () => {
      // self 판정은 "email 소유 계정 == 이 identity 가 가리키는 계정" 일 때만
      // 성립한다. 매핑이 존재한다는 사실만으로 충돌 검사를 건너뛰면 안 된다.
      const doc = indexDoc("naver", "naver-other-owner", "X-indexed");
      mockGetUserByEmail.mockResolvedValueOnce(
        customTokenUserWithNative("Y-email-owner", "apple.com"),
      );
      const {db} = makeDb({
        preExists: true,
        preData: doc,
        txExists: true,
        txData: doc,
        callerUserExists: false,
      });

      const res = await resolveIdentity(db, {
        provider: "naver",
        providerUserId: "naver-other-owner",
        callerUid: "anon-other-owner",
        callerIsAnonymous: true,
        userInfo: {email: "PII_SELF_EMAIL@example.com", emailVerified: true},
      });

      expect(res).toMatchObject({
        uid: "",
        isNewUser: false,
        conflictKind: "email_in_use",
        existingProvider: "apple",
      });
    },
  );

  it(
    // eslint-disable-next-line max-len
    "SELF-IDX-03 (경계 — 데이터 있는 익명): 자기 계정 매핑이어도 R12 anonymous_existing_collision 차단은 유지 (라벨 = caller provider)",
    async () => {
      // 수정 전에는 1단이 먼저 email_in_use(apple) 로 조기 return 해 R12 의
      // 익명 데이터 보호 분기에 도달하지 못했다. 수정 후에는 transaction 이
      // caller users 문서 존재를 보고 차단한다 — 라벨은 사용자가 실제로 쓴
      // provider(naver) 여야 한다.
      const doc = indexDoc("naver", "naver-anon-data", "U-anon-data");
      mockGetUserByEmail.mockResolvedValueOnce(
        customTokenUserWithNative("U-anon-data", "apple.com"),
      );
      const {db, tx} = makeDb({
        preExists: true,
        preData: doc,
        txExists: true,
        txData: doc,
        callerUserExists: true,
      });

      const res = await resolveIdentity(db, {
        provider: "naver",
        providerUserId: "naver-anon-data",
        callerUid: "anon-with-data",
        callerIsAnonymous: true,
        userInfo: {email: "PII_SELF_EMAIL@example.com", emailVerified: true},
      });

      expect(res).toMatchObject({
        uid: "U-anon-data",
        isNewUser: false,
        conflictKind: "anonymous_existing_collision",
        existingProvider: "naver",
      });
      expect(tx.set).not.toHaveBeenCalled();
    },
  );

  it(
    // eslint-disable-next-line max-len
    "SELF-IDX-04 (경계 — 미등록 sub): identity 문서 부재 + email 소유 계정 native 부착 → 충돌 그대로 보고 (신규 문서 커밋 0)",
    async () => {
      // 같은 provider 라도 sub 가 다르면 문서 ID 가 달라 매핑이 없다 —
      // Gap B 가 막으려던 "새 identity 를 익명 uid 로 등록" 경로다.
      mockGetUserByEmail.mockResolvedValueOnce(
        customTokenUserWithNative("U-existing", "apple.com"),
      );
      const {db, tx} = makeDb({
        preExists: false,
        txExists: false,
        callerUserExists: false,
      });

      const res = await resolveIdentity(db, {
        provider: "naver",
        providerUserId: "naver-new-sub",
        callerUid: "anon-new-sub",
        callerIsAnonymous: true,
        userInfo: {email: "PII_SELF_EMAIL@example.com", emailVerified: true},
      });

      expect(res).toMatchObject({
        uid: "",
        isNewUser: false,
        conflictKind: "email_in_use",
        existingProvider: "apple",
      });
      expect(tx.set).not.toHaveBeenCalled();
    },
  );
});

// ---------------------------------------------------------------------------
// debug reauth-login-auto-merge (2026-09-17) — 비익명 caller 가드.
//
// 재인증 로그인 화면이 정식 사용자로 Custom Token callable 을 부르면, 가드
// 이전에는 caller 에 매핑 안 된 identity 가 (a) caller uid 에 조용히 등록되고
// (b) email · displayName · photoURL 이 IdP 값으로 덮어써졌다 (WR-05 · R10
// 계약이 그 결과를 고정). linkCustomTokenProvider 의 auth_time · 익명 거부
// 게이트도 우회된다. 가드는 "비익명 caller 는 자기 계정에 이미 매핑된
// identity 로만 통과" 이며 부작용(등록 · updateUser · email lookup) 전에
// 거부한다. 익명 · 미인증 caller 는 불변이다.
// ---------------------------------------------------------------------------
describe("resolveIdentity — 비익명 caller 가드 (reauth-login-auto-merge)", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockCreateUser.mockReset();
    mockDeleteUser.mockReset();
    mockUpdateUser.mockReset();
    mockUpdateUser.mockResolvedValue(undefined);
    mockGetUserByEmail.mockReset();
    mockGetUserByEmail.mockRejectedValue(
      Object.assign(new Error("not found"), {code: "auth/user-not-found"}),
    );
    mockGetUser.mockReset();
    mockGetUser.mockResolvedValue({emailVerified: true, providerData: []});
    warnMock.mockReset();
  });

  const fullUserInfo = {
    email: "PII_IDP_EMAIL@example.com",
    emailVerified: true,
    displayName: "PII IdP Name",
    photoURL: "https://idp.example.com/PII_photo.jpg",
  };

  /**
   * 부작용 0 단언 — identity 등록 · 사용자 기록 변경 · email lookup 없음.
   *
   * @param {MockTx} tx mock transaction.
   */
  function expectNoSideEffects(tx: MockTx): void {
    expect(tx.set).not.toHaveBeenCalled();
    expect(tx.update).not.toHaveBeenCalled();
    expect(mockCreateUser).not.toHaveBeenCalled();
    expect(mockUpdateUser).not.toHaveBeenCalled();
    expect(mockGetUserByEmail).not.toHaveBeenCalled();
  }

  it(
    // eslint-disable-next-line max-len
    "GUARD-01: 비익명 caller + 미등록 identity → caller_identity_mismatch, 등록 · updateUser 0 (WR-05 · R10 계약 반전)",
    async () => {
      const {db, tx} = makeDb({preExists: false, txExists: false});

      const res = await resolveIdentity(db, {
        provider: "kakao",
        providerUserId: "kakao-unlinked",
        callerUid: "signed-in-U",
        callerIsAnonymous: false,
        userInfo: fullUserInfo,
      });

      expect(res).toEqual({
        uid: "",
        isNewUser: false,
        conflictKind: "caller_identity_mismatch",
      });
      expectNoSideEffects(tx);
    },
  );

  it(
    // eslint-disable-next-line max-len
    "GUARD-02: 비익명 caller + 다른 계정에 매핑된 identity → caller_identity_mismatch, lastSeenAt 갱신 0",
    async () => {
      const otherDoc = {firebaseUid: "other-V"};
      const {db, tx} = makeDb({
        preExists: true,
        preData: otherDoc,
        txExists: true,
        txData: otherDoc,
      });

      const res = await resolveIdentity(db, {
        provider: "line",
        providerUserId: "line-of-V",
        callerUid: "signed-in-U",
        callerIsAnonymous: false,
        userInfo: fullUserInfo,
      });

      expect(res.conflictKind).toBe("caller_identity_mismatch");
      expect(res.uid).toBe("");
      expectNoSideEffects(tx);
    },
  );

  it(
    // eslint-disable-next-line max-len
    "GUARD-03: 비익명 caller + 자기 계정에 매핑된 identity → 기존 재로그인 경로 그대로 (truth-of-source refresh 포함)",
    async () => {
      const selfDoc = {firebaseUid: "signed-in-U"};
      const {db, tx} = makeDb({
        preExists: true,
        preData: selfDoc,
        txExists: true,
        txData: selfDoc,
        loginUserDoc: {exists: true, data: {signUpProviderId: "naver"}},
      });

      const res = await resolveIdentity(db, {
        provider: "naver",
        providerUserId: "naver-of-U",
        callerUid: "signed-in-U",
        callerIsAnonymous: false,
        userInfo: {displayName: "IdP Name"},
      });

      expect(res).toEqual({
        uid: "signed-in-U",
        isNewUser: false,
        conflictKind: null,
      });
      expect(tx.update).toHaveBeenCalledTimes(1);
      expect(tx.set).not.toHaveBeenCalled();
      // 일반 재로그인과 같은 R10-FOLLOWUP refresh (가드가 바꾸지 않는다).
      expect(mockUpdateUser).toHaveBeenCalledWith("signed-in-U", {
        displayName: "IdP Name",
        photoURL: null,
      });
    },
  );

  it(
    // eslint-disable-next-line max-len
    "GUARD-04: callerIsAnonymous 미지정 + callerUid → fail-closed (비익명으로 간주해 거부)",
    async () => {
      const {db, tx} = makeDb({preExists: false, txExists: false});

      const res = await resolveIdentity(db, {
        provider: "line",
        providerUserId: "line-unlinked",
        callerUid: "unknown-kind-U",
        userInfo: fullUserInfo,
      });

      expect(res.conflictKind).toBe("caller_identity_mismatch");
      expectNoSideEffects(tx);
    },
  );

  it(
    // eslint-disable-next-line max-len
    "GUARD-05 (경합): 비-tx read 는 자기 매핑이었지만 tx 시점에 다른 계정 매핑 → 거부 + 쓰기 0",
    async () => {
      const {db, tx} = makeDb({
        preExists: true,
        preData: {firebaseUid: "signed-in-U"},
        txExists: true,
        txData: {firebaseUid: "other-V"},
      });

      const res = await resolveIdentity(db, {
        provider: "kakao",
        providerUserId: "kakao-race",
        callerUid: "signed-in-U",
        callerIsAnonymous: false,
      });

      expect(res.conflictKind).toBe("caller_identity_mismatch");
      expect(tx.set).not.toHaveBeenCalled();
      expect(tx.update).not.toHaveBeenCalled();
      expect(mockUpdateUser).not.toHaveBeenCalled();
    },
  );

  it(
    // eslint-disable-next-line max-len
    "GUARD-06 (경합): 비-tx read 는 자기 매핑이었지만 tx 시점에 문서 부재 → 신규 등록 대신 거부",
    async () => {
      const {db, tx} = makeDb({
        preExists: true,
        preData: {firebaseUid: "signed-in-U"},
        txExists: false,
      });

      const res = await resolveIdentity(db, {
        provider: "kakao",
        providerUserId: "kakao-race-deleted",
        callerUid: "signed-in-U",
        callerIsAnonymous: false,
        userInfo: fullUserInfo,
      });

      expect(res.conflictKind).toBe("caller_identity_mismatch");
      expect(tx.set).not.toHaveBeenCalled();
      expect(mockUpdateUser).not.toHaveBeenCalled();
    },
  );

  it(
    // eslint-disable-next-line max-len
    "GUARD-07 (대조군): 익명 caller + 미등록 identity 는 기존대로 caller uid 로 등록된다",
    async () => {
      const {db, tx} = makeDb({preExists: false, txExists: false});

      const res = await resolveIdentity(db, {
        provider: "kakao",
        providerUserId: "kakao-anon-new",
        callerUid: "anon-guard-07",
        callerIsAnonymous: true,
      });

      expect(res).toEqual({
        uid: "anon-guard-07",
        isNewUser: true,
        conflictKind: null,
      });
      expect(tx.set).toHaveBeenCalled();
    },
  );

  it(
    // eslint-disable-next-line max-len
    "GUARD-08 (PII): 거부 로그는 provider · 문서 존재 여부만 싣는다 (uid · sub · email 미포함)",
    async () => {
      const {db} = makeDb({preExists: false, txExists: false});

      await resolveIdentity(db, {
        provider: "kakao",
        providerUserId: "PII_SUB_123",
        callerUid: "PII_CALLER_UID",
        callerIsAnonymous: false,
        userInfo: fullUserInfo,
      });

      expect(warnMock).toHaveBeenCalledWith(
        expect.objectContaining({
          event: "identity_index_caller_identity_mismatch",
          provider: "kakao",
        }),
        expect.any(String),
      );
      const logged = JSON.stringify(warnMock.mock.calls);
      expect(logged).not.toContain("PII_");
    },
  );

  it(
    // eslint-disable-next-line max-len
    "D-18: 비익명 caller + 매핑 미존재 → guardsCaller → tx.set 0 (가입 수단 덮어쓰기 0 · GUARD-01 과 같은 경로의 D-18 관점 재단언)",
    async () => {
      const {db, tx} = makeDb({preExists: false, txExists: false});

      const res = await resolveIdentity(db, {
        provider: "kakao",
        providerUserId: "kakao-formal-new",
        callerUid: "formal-uid",
        callerIsAnonymous: false,
      });

      // 거부는 throw 가 아니라 결과 반환 (GUARD-01 과 같은 계약).
      expect(res).toEqual({
        uid: "",
        isNewUser: false,
        conflictKind: "caller_identity_mismatch",
      });
      // 신규 등록 분기에 도달하지 않으므로 users 문서 write 0 — 기존 가입 수단 보존.
      expect(tx.set).not.toHaveBeenCalled();
      expect(mockCreateUser).not.toHaveBeenCalled();
    },
  );
});

// ---------------------------------------------------------------------------
// Phase 16.8 D-21 — 연결 해제 뒤 같은 provider 로 다시 로그인하는 경우의 서버
// 계약. 해제로 `identity_index/{provider}:{sub}` 문서가 사라졌으므로 lookup
// 은 "미존재" 이고 caller 는 로그아웃 뒤의 익명 uid 다. 규칙(provider 공통):
// 같은 이메일 → 기존 계정 안내 시트(email_in_use + existingProvider) /
// 다른 이메일 · 이메일 없음 → 새 계정(익명 uid 승격).
//
// 이메일이 있는 Custom Token 행은 dev 실기기로 도달할 수 없다(Kakao 비즈 앱
// 미전환 · LINE email 권한 미신청) → 본 Jest 가 서버 계약을 보장한다.
// ---------------------------------------------------------------------------
// eslint-disable-next-line max-len
describe("resolveIdentity Phase 16.8 D-21 — 해제 후 재로그인 매트릭스 (이메일 있는 CT)", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockCreateUser.mockReset();
    mockDeleteUser.mockReset();
    mockUpdateUser.mockReset();
    mockUpdateUser.mockResolvedValue(undefined);
    mockGetUserByEmail.mockReset();
    mockGetUser.mockReset();
    mockGetUser.mockResolvedValue({emailVerified: true, providerData: []});
    warnMock.mockReset();
  });

  it(
    // eslint-disable-next-line max-len
    "M1: 같은 이메일 + 남은 계정 native → email_in_use + existingProvider native slug (시트 경로 A/C)",
    async () => {
      // D-21: 같은 이메일 → 기존 계정 안내 시트. 해제한 kakao 로 다시
      // 로그인해도 원 계정(google 이 남음)으로 자동 재연결되지 않는다.
      // dev 실기기 도달 불가(비즈 앱 · LINE email 권한 미신청) → Jest 가 보장.
      mockGetUserByEmail.mockResolvedValueOnce({
        uid: "orig-uid",
        providerData: [{providerId: "google.com", uid: "g"}],
      });
      const {db, tx} = makeDb({preExists: false, txExists: false});

      const res = await resolveIdentity(db, {
        provider: "kakao",
        providerUserId: "kakao-relogin-m1",
        callerUid: "anon-relogin",
        callerIsAnonymous: true,
        userInfo: {email: "same@example.com", emailVerified: true},
      });

      expect(res).toMatchObject({
        uid: "",
        isNewUser: false,
        conflictKind: "email_in_use",
        existingProvider: "google",
      });
      // tx 미진입 — 익명 uid 로 새 identity 를 등록하지 않는다.
      expect(tx.get).not.toHaveBeenCalled();
      expect(tx.set).not.toHaveBeenCalled();
      expect(mockCreateUser).not.toHaveBeenCalled();
    },
  );

  it(
    // eslint-disable-next-line max-len
    "M2: 다른 이메일 → 신규 등록 (익명 uid 승격 · signUpProviderId: provider)",
    async () => {
      // D-21: 다른 이메일 → 새 계정. 원 계정과 무관한 새 가입이며 CT 새
      // 계정은 원 계정 재연결을 막으므로 새 계정 탈퇴가 필요하다(manual).
      // dev 실기기 도달 불가(비즈 앱 · LINE email 권한 미신청) → Jest 가 보장.
      mockGetUserByEmail.mockRejectedValueOnce(
        Object.assign(new Error("nf"), {code: "auth/user-not-found"}),
      );
      const {db, tx, userRef} = makeDb({preExists: false, txExists: false});

      const res = await resolveIdentity(db, {
        provider: "kakao",
        providerUserId: "kakao-relogin-m2",
        callerUid: "anon-relogin",
        callerIsAnonymous: true,
        userInfo: {email: "different@example.com", emailVerified: true},
      });

      expect(res).toMatchObject({uid: "anon-relogin", isNewUser: true});
      expect(mockGetUserByEmail).toHaveBeenCalledTimes(1);
      expect(mockCreateUser).not.toHaveBeenCalled();
      const userSetCall = tx.set.mock.calls.find((c) => c[0] === userRef);
      expect(userSetCall?.[1]).toMatchObject({signUpProviderId: "kakao"});
      expect(userSetCall?.[2]).toEqual({merge: true});
    },
  );

  it(
    // eslint-disable-next-line max-len
    "M3: 이메일 없음 → getUserByEmail 미호출 + 신규 등록 (익명 uid 승격 · signUpProviderId: provider)",
    async () => {
      // D-21: 이메일 없음 → 새 계정 (충돌 판정 근거가 없다). dev 의 Kakao ·
      // LINE 은 이메일이 오지 않아 이 행만 실기기로 관측된다.
      const {db, tx, userRef} = makeDb({preExists: false, txExists: false});

      const res = await resolveIdentity(db, {
        provider: "kakao",
        providerUserId: "kakao-relogin-m3",
        callerUid: "anon-relogin",
        callerIsAnonymous: true,
      });

      expect(mockGetUserByEmail).not.toHaveBeenCalled();
      expect(res).toMatchObject({uid: "anon-relogin", isNewUser: true});
      expect(mockCreateUser).not.toHaveBeenCalled();
      const userSetCall = tx.set.mock.calls.find((c) => c[0] === userRef);
      expect(userSetCall?.[1]).toMatchObject({signUpProviderId: "kakao"});
      expect(userSetCall?.[2]).toEqual({merge: true});
    },
  );

  it(
    // eslint-disable-next-line max-len
    "M4: 같은 이메일 + 남은 계정 CT 전용 → 역조회 existingProvider CT slug (시트 경로 B)",
    async () => {
      // D-21: 같은 이메일 → 기존 계정 안내 시트. 남은 계정이 CT 전용이라
      // providerData 가 비어 있어도 identity_index 역조회가 남은 provider
      // (line) 를 찾는다. dev 실기기 도달 불가(비즈 앱 · LINE email 권한 미신청)
      // → Jest 가 보장.
      mockGetUserByEmail.mockResolvedValueOnce({
        uid: "orig-uid",
        providerData: [],
      });
      const {db, tx, where} = makeDb({
        preExists: false,
        txExists: false,
        reverseDocs: [{provider: "line", providerUserId: "l1"}],
      });

      const res = await resolveIdentity(db, {
        provider: "kakao",
        providerUserId: "kakao-relogin-m4",
        callerUid: "anon-relogin",
        callerIsAnonymous: true,
        userInfo: {email: "same@example.com", emailVerified: true},
      });

      expect(res).toMatchObject({
        uid: "",
        isNewUser: false,
        conflictKind: "email_in_use",
        existingProvider: "line",
      });
      expect(where).toHaveBeenCalledWith("firebaseUid", "==", "orig-uid");
      expect(tx.set).not.toHaveBeenCalled();
    },
  );
});
