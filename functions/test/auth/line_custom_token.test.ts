/**
 * lineCustomToken onCall 회귀 테스트 (Phase 14 Plan 14-04 Task 1).
 *
 * **Mock 한계 명시 (Phase 14.1 D-14.1-03, memory
 * `feedback_oidc_mock_self_referential` §2):** 본 test 는 mock LINE 서버가
 * helper 의 nonceHashing 가정과 일관되게 동작한다는 self-referential 검증이다.
 * 실 LINE OIDC provider 의 nonce claim embed 동작은 Phase 14.1 D-14.1-02
 * cross-verify (line-sdk-android LineIdToken.java verbatim "the same value as
 * in the authentication request" + line-sdk-ios-swift LoginProcess.swift
 * verbatim `parameters["nonce"] = nonce` raw 직접 할당) 로 확인했으며, 본
 * mock 의 `mockServerEmbedNonce` fixture 가 그 정적 사실을 mirror 한다.
 * 그러나 본 mock 은 실 OIDC provider 의 모든 edge case (clock skew / network
 * failure / token rotation 등) 를 reproduce 하지 않는다. 실 단말 backend tier
 * UAT (.planning/phases/14-line-login/14-HUMAN-UAT.md §A1) 가 진짜 contract
 * 검증.
 *
 * Phase 12 kakao_custom_token.test.ts 직접 mirror — 5 deltas:
 *  1. helper mock = createOidcVerifier (Plan 14-01) — 직접 createRemoteJWKSet
 *     호출 0 (Pitfall 3 sentinel 보존).
 *  2. audience = LINE_CHANNEL_ID (mock value "fake-line-channel-id")
 *  3. algorithms = ES256 (Kakao = RS256)
 *  4. nonceHashing = none (Kakao 와 동일 mode, Phase 14.1 D-14.1-01 정정)
 *  5. provider = "line" (resolveIdentity 인자)
 *
 * Task 1 시나리오 (1-9):
 *  - Test 1: 정상 검증 + Identity Index 신규 등록 + Custom Token 발급
 *  - Test 2: iss mismatch → invalid-argument HttpsError
 *  - Test 3: aud mismatch → invalid-argument HttpsError
 *  - Test 4: exp 만료 → invalid-argument HttpsError
 *  - Test 5: nonce raw mismatch → invalid-argument HttpsError
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
const errorMock = logger.error as unknown as jest.Mock;
// WR-02 회귀 가드 — debug/log 도 PII sentinel 검사 배열 (allLogCalls) 에 포함.
// production code 가 현재 logger.debug / logger.log 미사용이지만 향후 디버그
// 목적 추가 시 PII 회귀를 sentinel 이 감지 못 하는 약점 차단.
const debugMock = logger.debug as unknown as jest.Mock;
const logMock = logger.log as unknown as jest.Mock;

afterAll(() => testEnv.cleanup());

/**
 * mockServerEmbedNonce — 실 LINE 서버의 nonce embed 동작에 대한 정적
 * 사실 (raw 그대로 embed) 의 docstring-assertion. 본 fixture 는 Test
 * 1-14 의 mock payload 구성에 functional plug-in 되지 않으며 (verifier
 * helper 자체가 jest.mock 으로 가로채여 payload.nonce 값이 caller code-
 * path 에서 소비되지 않기 때문 — functional 분리의 실효성이 illusory),
 * helper 의 nonceHashing 가정 변경 시 향후 contributor 가 본 sentinel 의
 * describe 블록 (line 218-) RED 로 인해 의도 발견 + 4-source verbatim
 * 재확인을 강제받게 하는 문서적 tripwire 역할이다. 진짜 보호장치 두 가지는
 * (1) 본 docstring + describe 블록 (2) 실 단말 backend tier UAT
 * (.planning/phases/14-line-login/14-HUMAN-UAT.md §A1). functional mock
 * separation 은 Phase 15+ 진입 시 (helper 가 payload.nonce 를 실제로 caller
 * 외부에서 검증하는 형태로 재설계) 별도 PR 로 도입 가능.
 *
 * Phase 14.1 D-14.1-02 cross-verified: line-sdk-android LineIdToken.java
 * verbatim "the same value as in the authentication request" + line-sdk-
 * ios-swift LoginProcess.swift verbatim → raw 그대로 embed.
 *
 * @param {string} rawNonce client 가 SDK 에 전달한 raw nonce.
 * @return {string} LINE 서버가 ID Token nonce claim 에 embed 할 값 (raw 동일).
 */
const mockServerEmbedNonce = (rawNonce: string): string => rawNonce;

describe(
  "mockServerEmbedNonce fixture (Phase 14.1 self-reference 회피 sentinel)",
  () => {
    // eslint-disable-next-line max-len
    it("raw nonce 그대로 반환 — line-sdk-android LineIdToken.java verbatim mirror", () => {
      const raw = "test-raw-nonce-xyz";
      expect(mockServerEmbedNonce(raw)).toBe(raw);
    });
  },
);

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

  // Test 5: helper 가 raw !== claim.nonce 검사 후 JWTClaimValidationFailed
  // throw 시뮬레이션 (Phase 14.1 D-14.1-02 — LINE nonceHashing="none" raw
  // 비교 mode). caller 는 jose error 를 그대로 invalid-argument 매핑.
  // eslint-disable-next-line max-len
  it("Test 5: nonce raw mismatch → invalid-argument HttpsError", async () => {
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

  // WR-01 회귀 가드 (Wave 2 carry-over) — happy-path 에서 logger 가 payload
  // 본문 (name / picture / idToken / raw nonce) 을 누출하지 않음을 명시 검증.
  // 현재 production code (line_custom_token.ts:222-226) 는 {event, uid,
  // isNewUser} 만 logger.info 호출 → 실질 누출 0 이지만, 향후 contributor 가
  // 진단 목적으로 lineDisplayName / linePictureUrl 변수를 logger payload 에
  // 추가하면 happy-path 회귀가 silently merge 될 수 있다 → 본 sentinel 이
  // RED 로 차단.
  // eslint-disable-next-line max-len
  it("Test 9.5: happy-path PII 금지 — logger 에 name/picture/idToken/nonce 본문 미노출", async () => {
    mockVerifyLineIdToken.mockResolvedValue({
      sub: "U_line_pii",
      name: "PII_LINE_DISPLAY_NAME",
      picture: "https://line.example.com/PII_PIC.png",
    });
    mockIdxGet.mockResolvedValue({exists: false});
    mockTxGet.mockResolvedValue({exists: false});

    const wrapped = testEnv.wrap(myFunctions.lineCustomToken);
    await wrapped({
      auth: {uid: "anon-pii-line"},
      app: {appId: "test"},
      data: {idToken: "JWT_LINE_BODY", nonce: "raw-PII-nonce"},
    } as never);

    // WR-02 mirror — debug/log 도 sentinel 배열 포함.
    const allLogCalls = [
      ...infoMock.mock.calls,
      ...warnMock.mock.calls,
      ...errorMock.mock.calls,
      ...debugMock.mock.calls,
      ...logMock.mock.calls,
    ];
    for (const args of allLogCalls) {
      const s = JSON.stringify(args);
      expect(s).not.toContain("PII_LINE_DISPLAY_NAME");
      expect(s).not.toContain("PII_PIC.png");
      expect(s).not.toContain("JWT_LINE_BODY");
      expect(s).not.toContain("raw-PII-nonce");
    }
  });
});

// Task 2 — 잔여 Test 10-14 (conflictKind + PII regression).
// Phase 12 kakao_custom_token.test.ts 의 conflict 시나리오 + PII regression
// 패턴 직접 mirror. D-LINE-21 (email scope 미채택) 이라 자체 trigger 가능성은
// 0 이지만 caller switch 분기는 정책 일관성 보존 — 회귀 가드 의무.
describe("lineCustomToken onCall — Task 2 (Test 10-14)", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockCreateCustomToken.mockResolvedValue("MOCK_LINE_TOKEN");
    mockCreateUser.mockResolvedValue({uid: "new-uid-line-pre"});
    mockGetUserByEmail.mockReset();
    mockGetUserByEmail.mockRejectedValue(
      Object.assign(new Error("not found"), {code: "auth/user-not-found"}),
    );
  });

  // Test 10: conflictKind=email_in_use → already-exists HttpsError.
  // helper level conflictKind injection — !callerUid 분기의 createUser
  // auth/email-already-in-use rejection 으로 trigger 시뮬레이션.
  // eslint-disable-next-line max-len
  it("Test 10: conflictKind=email_in_use → already-exists HttpsError", async () => {
    mockVerifyLineIdToken.mockResolvedValue({
      sub: "U_line_collision",
      name: "Tanaka",
    });
    mockIdxGet.mockResolvedValue({exists: false});
    mockCreateUser.mockRejectedValueOnce(
      Object.assign(new Error("email exists"), {
        code: "auth/email-already-in-use",
      }),
    );

    const wrapped = testEnv.wrap(myFunctions.lineCustomToken);
    const promise = wrapped({
      app: {appId: "test"},
      data: {idToken: "FAKE", nonce: "n"},
    } as never);
    await expect(promise).rejects.toBeInstanceOf(HttpsError);
    await expect(promise).rejects.toMatchObject({
      code: "already-exists",
      message: "errorAccountExistsWithDifferentCredential",
    });
    expect(warnMock).toHaveBeenCalledWith(
      expect.objectContaining({event: "line_email_collision"}),
      expect.any(String),
    );
  });

  // Test 11: conflictKind=anonymous_existing_collision → already-exists.
  // eslint-disable-next-line max-len
  it("Test 11: anonymous + existing LINE identity → already-exists HttpsError", async () => {
    mockVerifyLineIdToken.mockResolvedValue({
      sub: "U_line_existing_b",
      name: "Sato",
    });
    // 익명 사용자 'anon-A' 가 기존 LINE identity 'existing-B' 로 로그인 시도.
    mockIdxGet.mockResolvedValue({exists: true});
    mockTxGet.mockResolvedValue({
      exists: true,
      data: () => ({firebaseUid: "existing-line-B"}),
    });

    const wrapped = testEnv.wrap(myFunctions.lineCustomToken);
    const promise = wrapped({
      auth: {uid: "anon-A-line"},
      app: {appId: "test"},
      data: {idToken: "FAKE", nonce: "n"},
    } as never);
    await expect(promise).rejects.toBeInstanceOf(HttpsError);
    await expect(promise).rejects.toMatchObject({
      code: "already-exists",
      message: "errorAccountExistsWithDifferentCredential",
    });
    expect(warnMock).toHaveBeenCalledWith(
      expect.objectContaining({event: "line_anonymous_conflict"}),
      expect.any(String),
    );
  });

  // Test 12: resolveIdentity throw → internal HttpsError + logger.error.
  // eslint-disable-next-line max-len
  it("Test 12: resolveIdentity throw → internal HttpsError + logger.error", async () => {
    mockVerifyLineIdToken.mockResolvedValue({
      sub: "U_line_fail",
      name: "Ito",
    });
    // helper 의 idxRef.get() 이 firestore 오류 throw — caller 가 catch 하여
    // internal 매핑.
    mockIdxGet.mockRejectedValueOnce(new Error("firestore unavailable"));

    const wrapped = testEnv.wrap(myFunctions.lineCustomToken);
    const promise = wrapped({
      app: {appId: "test"},
      data: {idToken: "FAKE", nonce: "n"},
    } as never);
    await expect(promise).rejects.toBeInstanceOf(HttpsError);
    await expect(promise).rejects.toMatchObject({
      code: "internal",
      message: "errorUnknown",
    });
    expect(errorMock).toHaveBeenCalledWith(
      expect.objectContaining({event: "identity_index_failed"}),
      expect.any(String),
    );
    // PII 회귀 — err.message ('firestore unavailable') 본문 logger 미노출.
    // WR-02 — error 만이 아닌 info/warn/debug/log 전체 sentinel 검사.
    const allLogCalls = [
      ...infoMock.mock.calls,
      ...warnMock.mock.calls,
      ...errorMock.mock.calls,
      ...debugMock.mock.calls,
      ...logMock.mock.calls,
    ];
    for (const args of allLogCalls) {
      expect(JSON.stringify(args)).not.toContain("firestore unavailable");
    }
  });

  // Test 13: createCustomToken throw → internal + err.message PII 미노출.
  // eslint-disable-next-line max-len
  it("Test 13: createCustomToken throw → internal + err.message 미노출", async () => {
    mockVerifyLineIdToken.mockResolvedValue({
      sub: "U_line_token_fail",
      name: "Watanabe",
    });
    mockIdxGet.mockResolvedValue({exists: false});
    mockTxGet.mockResolvedValue({exists: false});
    // admin SDK throw 시뮬레이션 — err.message 에 PII sentinel 삽입.
    const sdkErr = Object.assign(
      new Error("PII_SENTINEL_LINE_TOKEN_FAIL_MSG"),
      {name: "FirebaseAuthError"},
    );
    mockCreateCustomToken.mockRejectedValueOnce(sdkErr);

    const wrapped = testEnv.wrap(myFunctions.lineCustomToken);
    const promise = wrapped({
      app: {appId: "test"},
      data: {idToken: "FAKE", nonce: "n"},
    } as never);
    await expect(promise).rejects.toBeInstanceOf(HttpsError);
    await expect(promise).rejects.toMatchObject({
      code: "internal",
      message: "errorUnknown",
    });
    expect(errorMock).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "line_custom_token_create_failed",
        code: "FirebaseAuthError",
      }),
      expect.any(String),
    );
    // PII 회귀 — err.message 본문 logger 미노출.
    // WR-02 — debug/log 도 sentinel 배열 포함.
    const allLogCalls = [
      ...infoMock.mock.calls,
      ...warnMock.mock.calls,
      ...errorMock.mock.calls,
      ...debugMock.mock.calls,
      ...logMock.mock.calls,
    ];
    for (const args of allLogCalls) {
      expect(JSON.stringify(args)).not.toContain(
        "PII_SENTINEL_LINE_TOKEN_FAIL_MSG",
      );
    }
  });

  // Test 14: PII regression sentinel — logger 어디에도 PII sentinel 미노출.
  // jose error message 에 LINE PII 모형 문자열 삽입 → caller 의 catch 가
  // err.code / err.name 만 fingerprint 노출하므로 sentinel 어디에도 등장 0.
  // eslint-disable-next-line max-len
  it("Test 14: PII regression — JOSEError.message PII sentinel 미노출", async () => {
    const piiSentinel = "PII_SENTINEL_secret_line_account_PII_NICK";
    const ErrCtor = jose.errors.JWTClaimValidationFailed as unknown as new (
      m: string
    ) => Error;
    const err = new ErrCtor(piiSentinel);
    (err as unknown as {code: string}).code =
      "ERR_JWT_CLAIM_VALIDATION_FAILED";
    mockVerifyLineIdToken.mockRejectedValue(err);

    const wrapped = testEnv.wrap(myFunctions.lineCustomToken);
    await expect(
      wrapped({
        app: {appId: "test"},
        data: {idToken: "JWT_BODY_LINE", nonce: "n"},
      } as never),
    ).rejects.toBeInstanceOf(Error);

    // 모든 logger 호출에서 sentinel + 분해 토큰 미포함 검증.
    // WR-02 — debug/log 도 sentinel 배열 포함.
    const allLogCalls = [
      ...infoMock.mock.calls,
      ...warnMock.mock.calls,
      ...errorMock.mock.calls,
      ...debugMock.mock.calls,
      ...logMock.mock.calls,
    ];
    for (const args of allLogCalls) {
      const stringified = JSON.stringify(args);
      expect(stringified).not.toContain(piiSentinel);
      expect(stringified).not.toContain("secret_line_account");
      expect(stringified).not.toContain("PII_NICK");
      expect(stringified).not.toContain("JWT_BODY_LINE");
    }
  });
});
