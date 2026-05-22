/**
 * yahoojpCustomToken onCall 회귀 테스트 (Phase 15 Plan 15-02).
 *
 * **Mock 한계 명시 (Phase 14.1 D-14.1-03, memory
 * `feedback_oidc_mock_self_referential` §2, 5층 안전망 §7-C baseline 첫 적용):**
 * 본 test 는 mock Yahoo!JP 서버가 helper 의 nonceHashing 가정과 동일하게
 * 동작한다는 self-referential 검증이다. 실 Yahoo!JP OIDC provider 의 nonce
 * embed 동작은 Phase 14.1 D-14.1-02 mirror 의 5-source cross-verify (Yahoo!JP
 * id_token.html "Payloadのnonce値が ... 一致していることを検証します" verbatim
 * + AppAuth-iOS OIDAuthorizationRequest.m `[query addParameter:kNonceKey
 * value:_nonce]` + AppAuth-Android AuthorizationRequest.java:863-872 "passed
 * through unmodified" + Yahoo!JP authorization.html + flutter_appauth pub.dev
 * example.dart) 로 확인했으며, 본 mock 의 `mockServerEmbedNonce` fixture 가
 * 그 정적 사실을 mirror 한다. 그러나 본 mock 은 실 OIDC provider 의 모든 edge
 * case (clock skew / network failure / token rotation 등) 를 reproduce 하지
 * 않는다. 실 단말 backend tier UAT
 * (.planning/phases/15-yahoo-japan-login/15-HUMAN-UAT.md §A1) 가 진짜 contract
 * 검증.
 *
 * Phase 14 line_custom_token.test.ts 직접 mirror — 5 deltas:
 *  1. issuer = "https://auth.login.yahoo.co.jp/yconnect/v2/" (trailing slash
 *     포함 — configuration.html verbatim, D-YJP-05)
 *  2. audience = YAHOOJP_CLIENT_ID (mock value "fake-yahoojp-client-id")
 *  3. algorithms = ["RS256"] (LINE = ES256, Yahoo!JP id_token.html "RSA-
 *     SHA256のみのサポート" verbatim)
 *  4. nonceHashing = "none" (LINE 과 동일 mode, 5-source cross-verified)
 *  5. provider = "yahoojp" (resolveIdentity 인자)
 *
 * Task 1 시나리오 (1-9):
 *  - Test 1: 정상 검증 + Identity Index 신규 등록 + Custom Token 발급
 *  - Test 2: iss mismatch (trailing slash trap 의도 노출) → invalid-argument
 *  - Test 3: aud mismatch → invalid-argument HttpsError
 *  - Test 4: exp 만료 → invalid-argument HttpsError
 *  - Test 5: nonce raw mismatch → invalid-argument HttpsError
 *  - Test 6: JWKS fetch 실패 (JWKSNoMatchingKey) → invalid-argument
 *  - Test 7: 익명 호출자 + identity_index 미등록 → seed UID = request.auth.uid
 *  - Test 8: 미인증 호출자 + identity_index 미등록 → 새 UID 자동 생성
 *  - Test 9: identity_index 기존 매핑 → 그 firebaseUid 재사용
 *
 * Task 2 (별도 commit) — Test 10 PII regression sentinel + index.ts export.
 *
 * @see .planning/phases/14.1-line-oidc-nonce-hotfix/14.1-RESEARCH.md
 *     §"## LINE OIDC nonce 동작 (verbatim cross-verify)"
 * @see .planning/phases/15-yahoo-japan-login/15-RESEARCH.md
 *     §"Cross-Verify Evidence Matrix" §D-YJP-04
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
  defineSecret: () => ({value: () => "fake-yahoojp-client-id"}),
}));

// jose — Phase 14 D-LINE-02 retroactive 후 caller 가 jose.jwtVerify 를 직접
// 호출하지 않는다. errors 클래스만 보존 (PII regression / JWKS fetch error
// 등 jose error 생성 시뮬레이션 케이스용).
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
const mockVerifyYahoojpIdToken = jest.fn();
jest.mock("../../src/shared/oidc_verifier", () => ({
  createOidcVerifier: jest.fn(() => mockVerifyYahoojpIdToken),
}));

// firebase-admin/auth — getAuth().createCustomToken / createUser / deleteUser /
// updateUser / getUserByEmail (Phase 9.2 Gap B default — auth/user-not-found).
const mockCreateCustomToken = jest.fn().mockResolvedValue("MOCK_YAHOOJP_TOKEN");
const mockCreateUser = jest.fn().mockResolvedValue({uid: "new-uid-yj-pre"});
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
// Task 2 (Test 10 PII regression sentinel) 에서 errorMock / debugMock /
// logMock 5 logger 채널 stringify 검사에 사용 — Task 2 commit 시 추가.

afterAll(() => testEnv.cleanup());

/**
 * mockServerEmbedNonce — 실 Yahoo!JP 서버의 nonce embed 동작에 대한 정적
 * 사실 (raw 그대로 embed) 의 docstring-assertion. 본 fixture 는 Test 1-10 의
 * mock payload 구성에 functional plug-in 되지 않으며 (verifier helper 자체가
 * jest.mock 으로 가로채여 payload.nonce 값이 caller code-path 에서 소비되지
 * 않기 때문 — functional 분리의 실효성이 illusory), helper 의 nonceHashing
 * 가정 변경 시 향후 contributor 가 본 sentinel 의 describe 블록 RED 로 인해
 * 의도 발견 + 5-source verbatim 재확인을 강제받게 하는 문서적 tripwire
 * 역할이다. 진짜 보호장치 두 가지는 (1) 본 docstring + describe 블록
 * (2) 실 단말 backend tier UAT (15-HUMAN-UAT.md §A1).
 *
 * D-YJP-04 cross-verified (5-source): Yahoo!JP id_token.html "Payloadのnonce
 * 値が ... 一致していることを検証します" verbatim + Yahoo!JP authorization.html
 * + flutter_appauth pub.dev example.dart + AppAuth-iOS
 * OIDAuthorizationRequest.m + AppAuth-Android
 * AuthorizationRequest.java:863-872 → raw 그대로 embed.
 *
 * @param {string} rawNonce client 가 SDK 에 전달한 raw nonce.
 * @return {string} Yahoo!JP 서버가 ID Token nonce claim 에 embed 할 값
 *     (raw 동일).
 */
const mockServerEmbedNonce = (rawNonce: string): string => rawNonce;

describe(
  "mockServerEmbedNonce fixture (Phase 14.1 self-reference 회피 sentinel)",
  () => {
    // eslint-disable-next-line max-len
    it("raw nonce 그대로 반환 — Yahoo!JP id_token.html verbatim mirror (D-YJP-04)", () => {
      const raw = "test-raw-nonce-yj-xyz";
      expect(mockServerEmbedNonce(raw)).toBe(raw);
    });
  },
);

describe("yahoojpCustomToken onCall — Task 1 (Test 1-9)", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockCreateCustomToken.mockResolvedValue("MOCK_YAHOOJP_TOKEN");
    mockCreateUser.mockResolvedValue({uid: "new-uid-yj-pre"});
    mockGetUserByEmail.mockReset();
    mockGetUserByEmail.mockRejectedValue(
      Object.assign(new Error("not found"), {code: "auth/user-not-found"}),
    );
  });

  // eslint-disable-next-line max-len
  it("Test 1: 정상 검증 → Identity Index 신규 등록 + Custom Token 발급", async () => {
    mockVerifyYahoojpIdToken.mockResolvedValue({
      sub: "yj-sub-123",
      name: "Taro",
      picture: "https://yahoojp.example.com/p.png",
    });
    mockIdxGet.mockResolvedValue({exists: false});
    mockTxGet.mockResolvedValue({exists: false});

    const wrapped = testEnv.wrap(myFunctions.yahoojpCustomToken);
    const result = (await wrapped({
      auth: {uid: "anon-uid-yj-1"},
      app: {appId: "test"},
      data: {idToken: "FAKE_YJ_JWT", nonce: "client-raw-nonce-yj"},
    } as never)) as {
      customToken: string;
      uid: string;
      isNewUser: boolean;
    };

    expect(result.customToken).toBe("MOCK_YAHOOJP_TOKEN");
    expect(result.uid).toBe("anon-uid-yj-1");
    expect(result.isNewUser).toBe(true);
    // helper 호출 인자 검증 — caller 가 idToken + raw nonce 만 전달.
    expect(mockVerifyYahoojpIdToken).toHaveBeenCalledWith(
      "FAKE_YJ_JWT",
      "client-raw-nonce-yj",
    );
    // D-YJP-09: email 미발급 → developerClaims 인자 없이 호출.
    expect(mockCreateCustomToken).toHaveBeenCalledWith("anon-uid-yj-1");
    // PII 금지 sentinel — info 호출 1회 이상.
    expect(infoMock.mock.calls.length).toBeGreaterThanOrEqual(1);
  });

  // Test 2: iss mismatch — trailing slash trap 의도 노출 (D-YJP-05). 실 단말
  // 에서 issuer 가 trailing slash 없는 형태로 옴직이면 jose strict equality
  // 검증이 fail → JWTClaimValidationFailed throw → caller 가 invalid-argument
  // 매핑. Plan 15-06 UAT A1 의 실 단말 token decode 결과로 final LOCK 검증.
  // eslint-disable-next-line max-len
  it("Test 2: iss mismatch (trailing slash trap) → invalid-argument HttpsError", async () => {
    const ErrCtor = jose.errors.JOSEError as unknown as new (
      m: string
    ) => Error;
    const err = new ErrCtor("unexpected iss");
    (err as unknown as {code: string}).code =
      "ERR_JWT_CLAIM_VALIDATION_FAILED";
    mockVerifyYahoojpIdToken.mockRejectedValue(err);

    const wrapped = testEnv.wrap(myFunctions.yahoojpCustomToken);
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
      expect.objectContaining({event: "yahoojp_jwt_verify_failed"}),
      expect.any(String),
    );
  });

  it("Test 3: aud mismatch → invalid-argument HttpsError", async () => {
    const ErrCtor = jose.errors.JWTClaimValidationFailed as unknown as new (
      m: string
    ) => Error;
    const err = new ErrCtor("unexpected aud");
    mockVerifyYahoojpIdToken.mockRejectedValue(err);

    const wrapped = testEnv.wrap(myFunctions.yahoojpCustomToken);
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
        event: "yahoojp_jwt_verify_failed",
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
    mockVerifyYahoojpIdToken.mockRejectedValue(err);

    const wrapped = testEnv.wrap(myFunctions.yahoojpCustomToken);
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
        event: "yahoojp_jwt_verify_failed",
        code: "ERR_JWT_EXPIRED",
      }),
      expect.any(String),
    );
  });

  // Test 5: helper 가 raw !== claim.nonce 검사 후 JWTClaimValidationFailed
  // throw 시뮬레이션 (D-YJP-04 — Yahoo!JP nonceHashing="none" raw 비교 mode,
  // 5-source cross-verified). caller 는 jose error 를 그대로 invalid-argument
  // 매핑. mockServerEmbedNonce fixture (=raw nonce 그대로 embed) 가 LOCK 한
  // 정적 사실의 mirror.
  // eslint-disable-next-line max-len
  it("Test 5: nonce raw mismatch → invalid-argument HttpsError", async () => {
    const ErrCtor = jose.errors.JWTClaimValidationFailed as unknown as new (
      m: string
    ) => Error;
    const err = new ErrCtor("unexpected nonce");
    (err as unknown as {claim: string; reason: string}).claim = "nonce";
    (err as unknown as {claim: string; reason: string}).reason = "check_failed";
    mockVerifyYahoojpIdToken.mockRejectedValue(err);

    const wrapped = testEnv.wrap(myFunctions.yahoojpCustomToken);
    const promise = wrapped({
      app: {appId: "test"},
      data: {idToken: "FAKE_JWT", nonce: "raw-nonce-mismatch-yj"},
    } as never);
    await expect(promise).rejects.toBeInstanceOf(HttpsError);
    await expect(promise).rejects.toMatchObject({
      code: "invalid-argument",
      message: "errorInvalidCredentials",
    });
    expect(warnMock).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "yahoojp_jwt_verify_failed",
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
    mockVerifyYahoojpIdToken.mockRejectedValue(err);

    const wrapped = testEnv.wrap(myFunctions.yahoojpCustomToken);
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
        event: "yahoojp_jwt_verify_failed",
        code: "ERR_JWKS_NO_MATCHING_KEY",
      }),
      expect.any(String),
    );
  });

  // eslint-disable-next-line max-len
  it("Test 7: 익명 호출자 + identity_index 미등록 → seed UID = request.auth.uid", async () => {
    mockVerifyYahoojpIdToken.mockResolvedValue({
      sub: "yj-sub-anon",
      name: "Hanako",
    });
    mockIdxGet.mockResolvedValue({exists: false});
    mockTxGet.mockResolvedValue({exists: false});

    const wrapped = testEnv.wrap(myFunctions.yahoojpCustomToken);
    const result = (await wrapped({
      auth: {uid: "anon-seed-uid-yj"},
      app: {appId: "test"},
      data: {idToken: "FAKE", nonce: "n"},
    } as never)) as {customToken: string; uid: string; isNewUser: boolean};

    expect(result.uid).toBe("anon-seed-uid-yj");
    expect(result.isNewUser).toBe(true);
    // callerUid 가 있으면 createUser 미호출 (resolveIdentity 내부 비-tx read 분기).
    expect(mockCreateUser).not.toHaveBeenCalled();
  });

  // eslint-disable-next-line max-len
  it("Test 8: 미인증 호출자 + 미등록 → preCreatedUid 경로로 새 UID 자동 생성", async () => {
    mockVerifyYahoojpIdToken.mockResolvedValue({
      sub: "yj-sub-new",
      name: "Yamada",
    });
    mockIdxGet.mockResolvedValue({exists: false});
    mockTxGet.mockResolvedValue({exists: false});

    const wrapped = testEnv.wrap(myFunctions.yahoojpCustomToken);
    const result = (await wrapped({
      app: {appId: "test"},
      data: {idToken: "FAKE", nonce: "n"},
    } as never)) as {customToken: string; uid: string; isNewUser: boolean};

    expect(result.uid).toBe("new-uid-yj-pre");
    expect(result.isNewUser).toBe(true);
    expect(mockCreateUser).toHaveBeenCalledTimes(1);
  });

  // eslint-disable-next-line max-len
  it("Test 9: identity_index 기존 매핑 → 그 firebaseUid 재사용 (정상 path)", async () => {
    mockVerifyYahoojpIdToken.mockResolvedValue({
      sub: "yj-sub-existing",
      name: "Suzuki",
    });
    mockIdxGet.mockResolvedValue({exists: true});
    mockTxGet.mockResolvedValue({
      exists: true,
      data: () => ({firebaseUid: "existing-yj-uid-9"}),
    });

    const wrapped = testEnv.wrap(myFunctions.yahoojpCustomToken);
    const result = (await wrapped({
      // auth 없음 — 미인증 (재로그인) 호출.
      app: {appId: "test"},
      data: {idToken: "FAKE", nonce: "n"},
    } as never)) as {customToken: string; uid: string; isNewUser: boolean};

    expect(result.uid).toBe("existing-yj-uid-9");
    expect(result.isNewUser).toBe(false);
    // D-YJP-09: developerClaims 미발급 → 두 번째 인자 없음.
    expect(mockCreateCustomToken).toHaveBeenCalledWith("existing-yj-uid-9");
  });
});
