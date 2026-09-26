/**
 * linkCustomTokenProvider onCall 회귀 테스트 (Phase 16 Plan 16-02 Task 2.1).
 *
 * **Mock 한계 — 실 단말 backend tier UAT (Plan 16-07 A6/A7) 가 ground truth.**
 * 본 test 는 (1) Firebase Admin SDK verifyIdToken / Firestore runTransaction
 * 의 jest stub + (2) createOidcVerifier helper mock (자체 verifier 가정 0,
 * memory feedback_oidc_mock_self_referential mirror) 로 시나리오 시뮬레이션.
 * 실 단말 Firestore "all reads before all writes" invariant + admin SDK
 * verifyIdToken 의 auth_time / checkRevoked / firebase.sign_in_provider 동작은
 * Firebase Emulator integration test 또는 backend tier UAT 가 진짜 contract
 * 검증 (memory feedback_mock_transaction_constraint mirror).
 *
 * Task 2.1 시나리오 (L1-L7):
 *  - L1: happy native→Custom Token — identity_index 신규 + linkedProviders update
 *  - L2: already linked — already-exists HttpsError
 *  - L3: stale idToken (auth_time > 5분) — unauthenticated
 *  - L4: revoked idToken — verifyIdToken throws → unauthenticated
 *  - L5: uid mismatch — permission-denied
 *  - L6: target ID Token invalid — unauthenticated + fingerprint
 *  - L7: anonymous caller — failed-precondition (Open Question #2)
 *
 * Phase 15 리뷰 WR-10 회귀 가드:
 *  - L8: 같은 uid 재연동 — 멱등 성공 (이전에는 already-exists 오분류)
 *  - L9: transaction read 1건 — 결과를 버리는 죽은 read 제거
 */

// firebase-functions/logger mock — read-only export 라 jest.spyOn 미동작.
jest.mock("firebase-functions/logger", () => ({
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
  debug: jest.fn(),
  log: jest.fn(),
}));

// secret 주입 — 배포 환경 의존 제거.
jest.mock("firebase-functions/params", () => ({
  defineSecret: () => ({value: () => "fake-secret"}),
}));

// jose — caller 가 errors 만 사용 (instanceof 분기), createRemoteJWKSet stub.
jest.mock("jose", () => {
  /** Mock JOSEError — instanceof 분기 동작용. */
  class JOSEError extends Error {
    code?: string;
    /** @param {string} [message] error message. */
    constructor(message?: string) {
      super(message);
      this.name = "JOSEError";
    }
  }
  /** Mock JWTClaimValidationFailed — JOSEError 서브클래스. */
  class JWTClaimValidationFailed extends JOSEError {
    /** @param {string} [message] error message. */
    constructor(message?: string) {
      super(message);
      this.name = "JWTClaimValidationFailed";
      this.code = "ERR_JWT_CLAIM_VALIDATION_FAILED";
    }
  }
  return {
    jwtVerify: jest.fn(),
    createRemoteJWKSet: jest.fn(() => "MOCK_JWKS"),
    errors: {JOSEError, JWTClaimValidationFailed},
  };
});

// createOidcVerifier helper mock — 자체 verifier 매개변수 가정 0
// (memory feedback_oidc_mock_self_referential mirror).
// 본 mock 은 admin SDK verifyIdToken 와 별 — target provider OIDC ID Token 의
// 검증을 시뮬레이션. mock 은 helper 의 dispatch 결과만 stub.
const mockVerifyTargetIdToken = jest.fn();
jest.mock("../../src/shared/oidc_verifier", () => ({
  createOidcVerifier: jest.fn(() => mockVerifyTargetIdToken),
}));

// firebase-admin/auth — verifyIdToken 자체 stub (자체 JWT decode 0).
const mockVerifyIdToken = jest.fn();
jest.mock("firebase-admin/auth", () => ({
  getAuth: jest.fn(() => ({
    verifyIdToken: mockVerifyIdToken,
  })),
}));

// firebase-admin/firestore — runTransaction mock state-machine.
const mockTxGet = jest.fn();
const mockTxSet = jest.fn();
const mockTxUpdate = jest.fn();
jest.mock("firebase-admin/firestore", () => {
  const idxRef = {label: "idxRef"};
  const userRef = {label: "userRef"};
  return {
    Firestore: class MockFirestore {},
    getFirestore: jest.fn(() => ({
      collection: (name: string) => ({
        doc: () => (name === "identity_index" ? idxRef : userRef),
      }),
      runTransaction: (fn: (t: unknown) => Promise<unknown>) =>
        fn({get: mockTxGet, set: mockTxSet, update: mockTxUpdate}),
    })),
    FieldValue: {
      serverTimestamp: () => "MOCK_TIMESTAMP",
      arrayUnion: (item: unknown) => ({mockArrayUnion: item}),
    },
  };
});

// eslint-disable-next-line import/first
import functionsTest from "firebase-functions-test";
// eslint-disable-next-line import/first
import * as logger from "firebase-functions/logger";
// eslint-disable-next-line import/first
import {HttpsError} from "firebase-functions/https";
// eslint-disable-next-line import/first
import * as jose from "jose";

const testEnv = functionsTest();

// eslint-disable-next-line import/first
import * as myFunctions from "../../src/index";

const infoMock = logger.info as unknown as jest.Mock;
const warnMock = logger.warn as unknown as jest.Mock;
const errorMock = logger.error as unknown as jest.Mock;
const debugMock = logger.debug as unknown as jest.Mock;
const logMock = logger.log as unknown as jest.Mock;

afterAll(() => testEnv.cleanup());

/**
 * auth_time 신선 (now - 60s) — fresh ID Token fixture.
 * @return {number} auth_time epoch seconds.
 */
function freshAuthTime(): number {
  return Math.floor(Date.now() / 1000) - 60;
}

/**
 * auth_time 만료 (now - 600s = 10분) — stale ID Token fixture.
 * @return {number} auth_time epoch seconds.
 */
function staleAuthTime(): number {
  return Math.floor(Date.now() / 1000) - 600;
}

describe("linkCustomTokenProvider onCall — Task 2.1 (L1-L7)", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockTxGet.mockReset();
    mockTxSet.mockReset();
    mockTxUpdate.mockReset();
    mockVerifyIdToken.mockReset();
    mockVerifyTargetIdToken.mockReset();
  });

  // eslint-disable-next-line max-len
  it("L1: happy native→Custom Token — identity_index 신규 + linkedProviders update", async () => {
    mockVerifyIdToken.mockResolvedValue({
      uid: "caller-uid-L1",
      auth_time: freshAuthTime(),
      firebase: {sign_in_provider: "google.com"},
    });
    mockVerifyTargetIdToken.mockResolvedValue({sub: "kakao-sub-L1"});
    // tx.get 호출 2회 (idxRef + userRef) — Promise.all 순서 보존.
    mockTxGet.mockResolvedValueOnce({exists: false});
    mockTxGet.mockResolvedValueOnce({exists: true});

    const wrapped = testEnv.wrap(myFunctions.linkCustomTokenProvider);
    const result = (await wrapped({
      auth: {uid: "caller-uid-L1"},
      app: {appId: "test"},
      data: {
        idToken: "FAKE_FRESH_ID_TOKEN",
        targetProvider: "kakao",
        targetProviderToken: "FAKE_KAKAO_TOKEN",
        nonce: "client-raw-nonce",
      },
    } as never)) as {ok: true};

    expect(result.ok).toBe(true);
    // verifyIdToken 의 checkRevoked=true 의무 검증.
    expect(mockVerifyIdToken).toHaveBeenCalledWith(
      "FAKE_FRESH_ID_TOKEN",
      true,
    );
    // target verifier 호출 인자 검증 (createOidcVerifier helper 재사용 증거).
    expect(mockVerifyTargetIdToken).toHaveBeenCalledWith(
      "FAKE_KAKAO_TOKEN",
      "client-raw-nonce",
    );
    // tx.set 2회 (idxRef + userRef) — RESEARCH Pattern 2 verbatim.
    expect(mockTxSet).toHaveBeenCalledTimes(2);
    // Phase 16.7 D-14 · D-18 — 연결 경로는 가입 이벤트가 아니므로 users
    // payload 에 가입 수단 필드가 없다 (코드 미변경 + 본 단언으로 보장).
    const usersSetCalls = mockTxSet.mock.calls.filter(
      (c: unknown[]) =>
        typeof c[1] === "object" &&
        c[1] !== null &&
        "linkedProviders" in (c[1] as Record<string, unknown>),
    );
    expect(usersSetCalls).toHaveLength(1);
    const usersPayload = usersSetCalls[0][1];
    expect(usersPayload).not.toHaveProperty("signUpProviderId");
    // happy path info log.
    expect(infoMock).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "link_custom_token_provider_succeeded",
        uid: "caller-uid-L1",
        targetProvider: "kakao",
        isNewUser: false,
      }),
      expect.any(String),
    );
    // PII 금지 sentinel — logger payload 에 idToken / targetProviderToken /
    // 본문 미노출.
    expect(infoMock).not.toHaveBeenCalledWith(
      expect.objectContaining({idToken: expect.anything()}),
      expect.any(String),
    );
  });

  it("L2: already linked — already-exists HttpsError", async () => {
    mockVerifyIdToken.mockResolvedValue({
      uid: "caller-uid-L2",
      auth_time: freshAuthTime(),
      firebase: {sign_in_provider: "google.com"},
    });
    mockVerifyTargetIdToken.mockResolvedValue({sub: "kakao-sub-L2"});
    // idxRef 가 **다른 계정** 소유로 이미 존재 → already-exists.
    // WR-10 (Phase 15 리뷰): 소유자 판정이 생겼으므로 firebaseUid 를 함께
    // 준다. 같은 uid 면 멱등 성공이어야 한다 (아래 L8).
    mockTxGet.mockResolvedValueOnce({
      exists: true,
      data: () => ({firebaseUid: "other-owner-uid"}),
    });

    const wrapped = testEnv.wrap(myFunctions.linkCustomTokenProvider);
    const promise = wrapped({
      auth: {uid: "caller-uid-L2"},
      app: {appId: "test"},
      data: {
        idToken: "FAKE_FRESH",
        targetProvider: "kakao",
        targetProviderToken: "FAKE_TARGET",
        nonce: "n",
      },
    } as never);
    await expect(promise).rejects.toBeInstanceOf(HttpsError);
    await expect(promise).rejects.toMatchObject({
      code: "already-exists",
      message: "errorAccountAlreadyLinked",
    });
    expect(mockTxSet).not.toHaveBeenCalled();
  });

  // ---------------------------------------------------------------------------
  // WR-10 (Phase 15 리뷰) 회귀 가드 — 같은 uid 재연동 멱등성.
  //
  // 이전 구현은 idxSnap.exists 만 보고 무조건 already-exists 를 던져서,
  // 이미 연동된 provider 를 다시 누르거나 (client 10초 타임아웃 뒤) 재시도
  // 하면 자기 계정에 대해 "이미 다른 계정에 연동됨" 안내를 받았다.
  // ---------------------------------------------------------------------------
  it("L8: 같은 uid 재연동 → 멱등 성공 + idx 재작성 안 함", async () => {
    mockVerifyIdToken.mockResolvedValue({
      uid: "caller-uid-L8",
      auth_time: freshAuthTime(),
      firebase: {sign_in_provider: "google.com"},
    });
    mockVerifyTargetIdToken.mockResolvedValue({sub: "kakao-sub-L8"});
    // 이미 **내 계정** 에 연동된 상태.
    mockTxGet.mockResolvedValueOnce({
      exists: true,
      data: () => ({firebaseUid: "caller-uid-L8"}),
    });

    const wrapped = testEnv.wrap(myFunctions.linkCustomTokenProvider);
    const result = (await wrapped({
      auth: {uid: "caller-uid-L8"},
      app: {appId: "test"},
      data: {
        idToken: "FAKE_FRESH",
        targetProvider: "kakao",
        targetProviderToken: "FAKE_TARGET",
        nonce: "n",
      },
    } as never)) as {ok: true};

    expect(result.ok).toBe(true);
    // idx 문서는 다시 쓰지 않는다 (최초 linkedAt 보존) — users/{uid} 의
    // linkedProviders self-heal 만 1회.
    expect(mockTxSet).toHaveBeenCalledTimes(1);
  });

  it("L9: transaction read 는 idxRef 1건만 수행한다 (죽은 read 제거)", async () => {
    mockVerifyIdToken.mockResolvedValue({
      uid: "caller-uid-L9",
      auth_time: freshAuthTime(),
      firebase: {sign_in_provider: "google.com"},
    });
    mockVerifyTargetIdToken.mockResolvedValue({sub: "kakao-sub-L9"});
    mockTxGet.mockResolvedValueOnce({exists: false});

    const wrapped = testEnv.wrap(myFunctions.linkCustomTokenProvider);
    await wrapped({
      auth: {uid: "caller-uid-L9"},
      app: {appId: "test"},
      data: {
        idToken: "FAKE_FRESH",
        targetProvider: "kakao",
        targetProviderToken: "FAKE_TARGET",
        nonce: "n",
      },
    } as never);

    // 이전에는 결과를 버리는 tx.get(userRef) 가 함께 돌아 2회였다.
    expect(mockTxGet).toHaveBeenCalledTimes(1);
  });

  it("L3: stale idToken (auth_time > 5분) → unauthenticated", async () => {
    mockVerifyIdToken.mockResolvedValue({
      uid: "caller-uid-L3",
      auth_time: staleAuthTime(),
      firebase: {sign_in_provider: "google.com"},
    });

    const wrapped = testEnv.wrap(myFunctions.linkCustomTokenProvider);
    const promise = wrapped({
      auth: {uid: "caller-uid-L3"},
      app: {appId: "test"},
      data: {
        idToken: "STALE_TOKEN",
        targetProvider: "kakao",
        targetProviderToken: "FAKE_TARGET",
        nonce: "n",
      },
    } as never);
    await expect(promise).rejects.toMatchObject({
      code: "unauthenticated",
      message: "errorReauthenticationRequired",
    });
    // target verifier 호출 안 됨 (Step 2 까지만 도달).
    expect(mockVerifyTargetIdToken).not.toHaveBeenCalled();
  });

  // eslint-disable-next-line max-len
  it("L4: revoked idToken → verifyIdToken throws → unauthenticated", async () => {
    mockVerifyIdToken.mockRejectedValue(
      Object.assign(new Error("id token revoked"), {
        code: "auth/id-token-revoked",
      }),
    );

    const wrapped = testEnv.wrap(myFunctions.linkCustomTokenProvider);
    const promise = wrapped({
      auth: {uid: "caller-uid-L4"},
      app: {appId: "test"},
      data: {
        idToken: "REVOKED_TOKEN",
        targetProvider: "kakao",
        targetProviderToken: "FAKE_TARGET",
        nonce: "n",
      },
    } as never);
    await expect(promise).rejects.toMatchObject({
      code: "unauthenticated",
      message: "errorReauthenticationRequired",
    });
    expect(warnMock).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "link_id_token_verify_failed",
        code: "auth/id-token-revoked",
      }),
      expect.any(String),
    );
  });

  it("L5: uid mismatch → permission-denied", async () => {
    mockVerifyIdToken.mockResolvedValue({
      uid: "DIFFERENT-UID",
      auth_time: freshAuthTime(),
      firebase: {sign_in_provider: "google.com"},
    });

    const wrapped = testEnv.wrap(myFunctions.linkCustomTokenProvider);
    const promise = wrapped({
      auth: {uid: "caller-uid-L5"},
      app: {appId: "test"},
      data: {
        idToken: "FAKE",
        targetProvider: "kakao",
        targetProviderToken: "FAKE_TARGET",
        nonce: "n",
      },
    } as never);
    await expect(promise).rejects.toMatchObject({
      code: "permission-denied",
      message: "errorUnauthenticated",
    });
  });

  // eslint-disable-next-line max-len
  it("L6: target ID Token invalid → unauthenticated + fingerprint log", async () => {
    mockVerifyIdToken.mockResolvedValue({
      uid: "caller-uid-L6",
      auth_time: freshAuthTime(),
      firebase: {sign_in_provider: "google.com"},
    });
    // jose 가 JWTClaimValidationFailed throw.
    const ErrCtor = jose.errors.JWTClaimValidationFailed as unknown as new (
      m: string
    ) => Error;
    const err = new ErrCtor("PII_TARGET_BODY");
    mockVerifyTargetIdToken.mockRejectedValue(err);

    const wrapped = testEnv.wrap(myFunctions.linkCustomTokenProvider);
    const promise = wrapped({
      auth: {uid: "caller-uid-L6"},
      app: {appId: "test"},
      data: {
        idToken: "FAKE",
        targetProvider: "kakao",
        targetProviderToken: "BAD_TARGET",
        nonce: "n",
      },
    } as never);
    // WR-01 / WR-02 (Phase 15 리뷰): link callable 도 4 Custom Token
    // endpoint 와 동일한 공용 매핑 표를 쓴다 — IdP 자격증명 거부는
    // `unauthenticated`, JWKS 도달 실패는 `unavailable`. 이전에는 둘 다
    // `invalid-argument` 로 뭉개져 "잘못된 입력" 으로 오분류됐다.
    await expect(promise).rejects.toMatchObject({
      code: "unauthenticated",
      message: "errorInvalidCredentials",
    });
    expect(warnMock).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "link_target_token_verify_failed",
        code: "ERR_JWT_CLAIM_VALIDATION_FAILED",
      }),
      expect.any(String),
    );
    // PII 금지 — err.message 본문 미노출.
    const allLogCalls = [
      ...infoMock.mock.calls,
      ...warnMock.mock.calls,
      ...errorMock.mock.calls,
      ...debugMock.mock.calls,
      ...logMock.mock.calls,
    ];
    for (const args of allLogCalls) {
      expect(JSON.stringify(args)).not.toContain("PII_TARGET_BODY");
    }
  });

  // eslint-disable-next-line max-len
  it("L7: anonymous caller → failed-precondition (Open Question #2)", async () => {
    mockVerifyIdToken.mockResolvedValue({
      uid: "caller-uid-L7",
      auth_time: freshAuthTime(),
      firebase: {sign_in_provider: "anonymous"},
    });

    const wrapped = testEnv.wrap(myFunctions.linkCustomTokenProvider);
    const promise = wrapped({
      auth: {uid: "caller-uid-L7"},
      app: {appId: "test"},
      data: {
        idToken: "FAKE",
        targetProvider: "kakao",
        targetProviderToken: "FAKE_TARGET",
        nonce: "n",
      },
    } as never);
    await expect(promise).rejects.toMatchObject({
      code: "failed-precondition",
      message: "errorAnonymousLinkNotAllowed",
    });
    // target verifier 호출 안 됨 (Step 2 reject 후 Step 3 미진입).
    expect(mockVerifyTargetIdToken).not.toHaveBeenCalled();
  });
});
