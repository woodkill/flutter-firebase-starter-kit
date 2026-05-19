/**
 * lineCustomToken onCall 회귀 테스트 (Phase 14 Plan 14-04 Task 1).
 *
 * Phase 12 kakao_custom_token.test.ts 직접 mirror — 5 deltas:
 *  1. helper mock = createOidcVerifier (Plan 14-01) — 직접 createRemoteJWKSet
 *     호출 0 (Pitfall 3 sentinel 보존).
 *  2. audience = LINE_CHANNEL_ID (mock value "fake-line-channel-id")
 *  3. algorithms = ES256 (Kakao = RS256)
 *  4. nonceHashing = sha256 (Kakao = none)
 *  5. provider = "line" (resolveIdentity 인자)
 *
 * Task 1 시나리오 (1-9):
 *  - Test 1: 정상 검증 + Identity Index 신규 등록 + Custom Token 발급
 *  - Test 2: iss mismatch → invalid-argument HttpsError
 *  - Test 3: aud mismatch → invalid-argument HttpsError
 *  - Test 4: exp 만료 → invalid-argument HttpsError
 *  - Test 5: nonce SHA256 mismatch → invalid-argument HttpsError
 *  - Test 6: JWKS fetch 실패 (JWKSNoMatchingKey) → invalid-argument
 *  - Test 7: 익명 호출자 + identity_index 미등록 → seed UID = request.auth.uid
 *  - Test 8: 미인증 호출자 + identity_index 미등록 → 새 UID 자동 생성
 *  - Test 9: identity_index 기존 매핑 → 그 firebaseUid 재사용
 *
 * Task 2 (별도 commit) — Test 10-14 (conflictKind + PII regression) 추가.
 *
 * jest.mock 호출은 hoist 되므로 src import 보다 먼저 정의되어야 한다.
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
  defineSecret: () => ({value: () => "fake-line-channel-id"}),
}));

// jose — Phase 14 D-LINE-02 retroactive 후 caller 가 jose.jwtVerify 를 직접
// 호출하지 않는다. errors 클래스만 보존 (PII regression / JWKS fetch error
// 등 jose error 생성 시뮬레이션 케이스용). createRemoteJWKSet stub 은 jose
// 모듈 lazy load 시 SyntaxError 차단용 (moduleNameMapper jose stub 와 동등).
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
  /** Mock JWTExpired — JOSEError 서브클래스. */
  class JWTExpired extends JOSEError {
    /** @param {string} [message] error message. */
    constructor(message?: string) {
      super(message);
      this.name = "JWTExpired";
      this.code = "ERR_JWT_EXPIRED";
    }
  }
  /** Mock JWKSNoMatchingKey — JOSEError 서브클래스. */
  class JWKSNoMatchingKey extends JOSEError {
    /** @param {string} [message] error message. */
    constructor(message?: string) {
      super(message);
      this.name = "JWKSNoMatchingKey";
      this.code = "ERR_JWKS_NO_MATCHING_KEY";
    }
  }
  return {
    jwtVerify: jest.fn(),
    createRemoteJWKSet: jest.fn(() => "MOCK_JWKS"),
    errors: {
      JOSEError,
      JWTClaimValidationFailed,
      JWTExpired,
      JWKSNoMatchingKey,
    },
  };
});

// Phase 14 D-LINE-02 — createOidcVerifier helper mock. caller 는 helper 가
// 반환한 verifier 함수만 호출하므로 (issuer/aud/alg/nonce 검증 전부 흡수),
// 단일 mock 함수가 resolve(payload) / reject(joseError) 로 시나리오 모두
// 시뮬레이션 가능. Pitfall 3 — 의도적 nonce mismatch 케이스가 mock 가로채기로
// silently PASS 되지 않도록 reject path 도 명시.
const mockVerifyLineIdToken = jest.fn();
jest.mock("../../src/shared/oidc_verifier", () => ({
  createOidcVerifier: jest.fn(() => mockVerifyLineIdToken),
}));

// firebase-admin/auth — getAuth().createCustomToken / createUser / deleteUser /
// updateUser / getUserByEmail (Phase 9.2 Gap B default — auth/user-not-found).
const mockCreateCustomToken = jest.fn().mockResolvedValue("MOCK_LINE_TOKEN");
const mockCreateUser = jest.fn().mockResolvedValue({uid: "new-uid-line-pre"});
const mockDeleteUser = jest.fn().mockResolvedValue(undefined);
const mockUpdateUser = jest.fn().mockResolvedValue(undefined);
const mockGetUserByEmail = jest.fn().mockRejectedValue(
  Object.assign(new Error("not found"), {code: "auth/user-not-found"}),
);
jest.mock("firebase-admin/auth", () => ({
  getAuth: jest.fn(() => ({
    createCustomToken: mockCreateCustomToken,
    createUser: mockCreateUser,
    deleteUser: mockDeleteUser,
    updateUser: mockUpdateUser,
    getUserByEmail: mockGetUserByEmail,
  })),
}));

// firebase-admin/firestore — 단일 mock transaction.
const mockTxGet = jest.fn();
const mockTxSet = jest.fn();
const mockTxUpdate = jest.fn();
const mockIdxGet = jest.fn();
jest.mock("firebase-admin/firestore", () => {
  const idxRef = {
    get: (...args: unknown[]) => mockIdxGet(...args),
    label: "idxRef",
  };
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

// 위 mock 셋업 이후에 testEnv + src import.
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

afterAll(() => testEnv.cleanup());

describe("lineCustomToken onCall — Task 1 (Test 1-9)", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockCreateCustomToken.mockResolvedValue("MOCK_LINE_TOKEN");
    mockCreateUser.mockResolvedValue({uid: "new-uid-line-pre"});
    mockGetUserByEmail.mockReset();
    mockGetUserByEmail.mockRejectedValue(
      Object.assign(new Error("not found"), {code: "auth/user-not-found"}),
    );
  });

  it("Test 1: 정상 검증 → Identity Index 신규 등록 + Custom Token 발급", async () => {
    mockVerifyLineIdToken.mockResolvedValue({
      sub: "U_line_user_1",
      name: "Taro",
      picture: "https://line.example.com/p.png",
    });
    mockIdxGet.mockResolvedValue({exists: false});
    mockTxGet.mockResolvedValue({exists: false});

    const wrapped = testEnv.wrap(myFunctions.lineCustomToken);
    const result = (await wrapped({
      auth: {uid: "anon-uid-line-1"},
      app: {appId: "test"},
      data: {idToken: "FAKE_LINE_JWT", nonce: "client-raw-nonce"},
    } as never)) as {
      customToken: string;
      uid: string;
      isNewUser: boolean;
    };

    expect(result.customToken).toBe("MOCK_LINE_TOKEN");
    expect(result.uid).toBe("anon-uid-line-1");
    expect(result.isNewUser).toBe(true);
    // helper 호출 인자 검증 — caller 가 idToken + raw nonce 만 전달.
    expect(mockVerifyLineIdToken).toHaveBeenCalledWith(
      "FAKE_LINE_JWT",
      "client-raw-nonce",
    );
    // D-LINE-21: email 미발급 → developerClaims 인자 없이 호출.
    expect(mockCreateCustomToken).toHaveBeenCalledWith("anon-uid-line-1");
    // PII 금지 sentinel — info 호출 1회 이상.
    expect(infoMock.mock.calls.length).toBeGreaterThanOrEqual(1);
  });

  it("Test 2: iss mismatch → invalid-argument HttpsError", async () => {
    const ErrCtor = jose.errors.JOSEError as unknown as new (
      m: string
    ) => Error;
    const err = new ErrCtor("unexpected iss");
    (err as unknown as {code: string}).code =
      "ERR_JWT_CLAIM_VALIDATION_FAILED";
    mockVerifyLineIdToken.mockRejectedValue(err);

    const wrapped = testEnv.wrap(myFunctions.lineCustomToken);
    const promise = wrapped({
      app: {appId: "test"},
      data: {idToken: "BAD_ISS_JWT", nonce: "n"},
    } as never);
    await expect(promise).rejects.toBeInstanceOf(HttpsError);
    await expect(promise).rejects.toMatchObject({
      code: "invalid-argument",
      message: "errorInvalidCredentials",
    });
    expect(warnMock).toHaveBeenCalledWith(
      expect.objectContaining({event: "line_jwt_verify_failed"}),
      expect.any(String),
    );
  });

  it("Test 3: aud mismatch → invalid-argument HttpsError", async () => {
    const ErrCtor = jose.errors.JWTClaimValidationFailed as unknown as new (
      m: string
    ) => Error;
    const err = new ErrCtor("unexpected aud");
    mockVerifyLineIdToken.mockRejectedValue(err);

    const wrapped = testEnv.wrap(myFunctions.lineCustomToken);
    const promise = wrapped({
      app: {appId: "test"},
      data: {idToken: "BAD_AUD_JWT", nonce: "n"},
    } as never);
    await expect(promise).rejects.toBeInstanceOf(HttpsError);
    await expect(promise).rejects.toMatchObject({
      code: "invalid-argument",
      message: "errorInvalidCredentials",
    });
    expect(warnMock).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "line_jwt_verify_failed",
        code: "ERR_JWT_CLAIM_VALIDATION_FAILED",
      }),
      expect.any(String),
    );
  });

  it("Test 4: exp 만료 → invalid-argument HttpsError", async () => {
    const ErrCtor = jose.errors.JWTExpired as unknown as new (
      m: string
    ) => Error;
    const err = new ErrCtor("token has expired");
    mockVerifyLineIdToken.mockRejectedValue(err);

    const wrapped = testEnv.wrap(myFunctions.lineCustomToken);
    const promise = wrapped({
      app: {appId: "test"},
      data: {idToken: "EXPIRED_JWT", nonce: "n"},
    } as never);
    await expect(promise).rejects.toBeInstanceOf(HttpsError);
    await expect(promise).rejects.toMatchObject({
      code: "invalid-argument",
      message: "errorInvalidCredentials",
    });
    expect(warnMock).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "line_jwt_verify_failed",
        code: "ERR_JWT_EXPIRED",
      }),
      expect.any(String),
    );
  });

  // Test 5: helper 가 SHA256(raw) !== claim.nonce 검사 후 JWTClaimValidationFailed
  // throw 시뮬레이션. caller 는 jose error 를 그대로 invalid-argument 매핑.
  // eslint-disable-next-line max-len
  it("Test 5: nonce SHA256 mismatch → invalid-argument HttpsError", async () => {
    const ErrCtor = jose.errors.JWTClaimValidationFailed as unknown as new (
      m: string
    ) => Error;
    const err = new ErrCtor("unexpected nonce");
    (err as unknown as {claim: string; reason: string}).claim = "nonce";
    (err as unknown as {claim: string; reason: string}).reason = "check_failed";
    mockVerifyLineIdToken.mockRejectedValue(err);

    const wrapped = testEnv.wrap(myFunctions.lineCustomToken);
    const promise = wrapped({
      app: {appId: "test"},
      data: {idToken: "FAKE_JWT", nonce: "raw-nonce-mismatch"},
    } as never);
    await expect(promise).rejects.toBeInstanceOf(HttpsError);
    await expect(promise).rejects.toMatchObject({
      code: "invalid-argument",
      message: "errorInvalidCredentials",
    });
    expect(warnMock).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "line_jwt_verify_failed",
        code: "ERR_JWT_CLAIM_VALIDATION_FAILED",
      }),
      expect.any(String),
    );
  });

  // Test 6: JWKSNoMatchingKey 는 JOSEError 서브클래스 → invalid-argument 매핑.
  // eslint-disable-next-line max-len
  it("Test 6: JWKS fetch 실패 (JWKSNoMatchingKey) → invalid-argument", async () => {
    const ErrCtor = jose.errors.JWKSNoMatchingKey as unknown as new (
      m: string
    ) => Error;
    const err = new ErrCtor("no matching key");
    mockVerifyLineIdToken.mockRejectedValue(err);

    const wrapped = testEnv.wrap(myFunctions.lineCustomToken);
    const promise = wrapped({
      app: {appId: "test"},
      data: {idToken: "FAKE_JWT", nonce: "n"},
    } as never);
    await expect(promise).rejects.toBeInstanceOf(HttpsError);
    await expect(promise).rejects.toMatchObject({
      code: "invalid-argument",
      message: "errorInvalidCredentials",
    });
    expect(warnMock).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "line_jwt_verify_failed",
        code: "ERR_JWKS_NO_MATCHING_KEY",
      }),
      expect.any(String),
    );
  });

  // eslint-disable-next-line max-len
  it("Test 7: 익명 호출자 + identity_index 미등록 → seed UID = request.auth.uid", async () => {
    mockVerifyLineIdToken.mockResolvedValue({
      sub: "U_line_anon",
      name: "Hanako",
    });
    mockIdxGet.mockResolvedValue({exists: false});
    mockTxGet.mockResolvedValue({exists: false});

    const wrapped = testEnv.wrap(myFunctions.lineCustomToken);
    const result = (await wrapped({
      auth: {uid: "anon-seed-uid-line"},
      app: {appId: "test"},
      data: {idToken: "FAKE", nonce: "n"},
    } as never)) as {customToken: string; uid: string; isNewUser: boolean};

    expect(result.uid).toBe("anon-seed-uid-line");
    expect(result.isNewUser).toBe(true);
    // callerUid 가 있으면 createUser 미호출 (resolveIdentity 내부 비-tx read 분기).
    expect(mockCreateUser).not.toHaveBeenCalled();
  });

  it("Test 8: 미인증 호출자 + 미등록 → preCreatedUid 경로로 새 UID 자동 생성", async () => {
    mockVerifyLineIdToken.mockResolvedValue({
      sub: "U_line_new",
      name: "Yamada",
    });
    mockIdxGet.mockResolvedValue({exists: false});
    mockTxGet.mockResolvedValue({exists: false});

    const wrapped = testEnv.wrap(myFunctions.lineCustomToken);
    const result = (await wrapped({
      app: {appId: "test"},
      data: {idToken: "FAKE", nonce: "n"},
    } as never)) as {customToken: string; uid: string; isNewUser: boolean};

    expect(result.uid).toBe("new-uid-line-pre");
    expect(result.isNewUser).toBe(true);
    expect(mockCreateUser).toHaveBeenCalledTimes(1);
  });

  it("Test 9: identity_index 기존 매핑 → 그 firebaseUid 재사용 (정상 path)", async () => {
    mockVerifyLineIdToken.mockResolvedValue({
      sub: "U_line_existing",
      name: "Suzuki",
    });
    mockIdxGet.mockResolvedValue({exists: true});
    mockTxGet.mockResolvedValue({
      exists: true,
      data: () => ({firebaseUid: "existing-line-uid-9"}),
    });

    const wrapped = testEnv.wrap(myFunctions.lineCustomToken);
    const result = (await wrapped({
      // auth 없음 — 미인증 (재로그인) 호출.
      app: {appId: "test"},
      data: {idToken: "FAKE", nonce: "n"},
    } as never)) as {customToken: string; uid: string; isNewUser: boolean};

    expect(result.uid).toBe("existing-line-uid-9");
    expect(result.isNewUser).toBe(false);
    // D-LINE-21: developerClaims 미발급 → 두 번째 인자 없음.
    expect(mockCreateCustomToken).toHaveBeenCalledWith("existing-line-uid-9");
  });
});
