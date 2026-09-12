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
 *  - Test 2: iss mismatch (trailing slash trap 의도 노출) → unauthenticated
 *  - Test 3: aud mismatch → unauthenticated HttpsError
 *  - Test 4: exp 만료 → unauthenticated HttpsError
 *  - Test 5: nonce raw mismatch → unauthenticated HttpsError
 *  - Test 6: JWKS fetch 실패 (JWKSNoMatchingKey) → unauthenticated
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
    createCustomToken: mockCreateCustomToken,
    createUser: mockCreateUser,
    deleteUser: mockDeleteUser,
    updateUser: mockUpdateUser,
    getUserByEmail: mockGetUserByEmail,
    getUser: mockGetUser, // CR-02 post-commit 보상 판정.
  })),
}));

// firebase-admin/firestore — 단일 mock transaction.
const mockTxGet = jest.fn();
const mockTxSet = jest.fn();
const mockTxUpdate = jest.fn();
const mockIdxGet = jest.fn();
// Plan 16-17 — identity_index 역조회 (where('firebaseUid','==',uid).get()).
// 기본값 빈 결과 = Custom Token 후보 0 → 기존 케이스 회귀 0.
const mockIdxWhere = jest.fn();
const mockIdxWhereGet = jest.fn().mockResolvedValue({docs: []});
// Phase 16 D-13/D-14 (Plan 16-03 Task 3.2) — termsAcceptanceSnapshot mirror.
const mockUserDocSet = jest.fn().mockResolvedValue(undefined);
jest.mock("firebase-admin/firestore", () => {
  const idxRef = {
    get: (...args: unknown[]) => mockIdxGet(...args),
    label: "idxRef",
  };
  const userRef = {
    label: "userRef",
    set: (...args: unknown[]) => mockUserDocSet(...args),
  };
  return {
    Firestore: class MockFirestore {},
    getFirestore: jest.fn(() => ({
      collection: (name: string) => ({
        doc: () => (name === "identity_index" ? idxRef : userRef),
        where: (...args: unknown[]) => {
          mockIdxWhere(...args);
          return {get: (...a: unknown[]) => mockIdxWhereGet(...a)};
        },
      }),
      runTransaction: (fn: (t: unknown) => Promise<unknown>) =>
        fn({get: mockTxGet, set: mockTxSet, update: mockTxUpdate}),
    })),
    FieldValue: {
      serverTimestamp: () => "MOCK_TIMESTAMP",
      arrayUnion: (item: unknown) => ({mockArrayUnion: item}),
    },
    // Phase 16 D-13/D-14 — Timestamp.fromDate sentinel.
    Timestamp: {
      fromDate: (d: Date) => ({_kind: "MOCK_TIMESTAMP", iso: d.toISOString()}),
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
// Plan 16-17 — resolveIdentity spy 용 namespace import. 본 endpoint 는
// scope 상 email claim 을 받지 않아(D-LINE-21 / D-YJP-09) CT-existing
// 충돌을 자체 trigger 할 수 없다 — endpoint 의 slug 전달 배선만 검증한다.
// eslint-disable-next-line import/first
import * as identityIndex from "../../src/auth/identity_index";

const infoMock = logger.info as unknown as jest.Mock;
const warnMock = logger.warn as unknown as jest.Mock;
const errorMock = logger.error as unknown as jest.Mock;
// WR-02 회귀 가드 (Phase 14) — debug/log 도 PII sentinel 검사 배열
// (allLogCalls) 에 포함. production code 가 현재 logger.debug / logger.log
// 미사용이지만 향후 디버그 목적 추가 시 PII 회귀를 sentinel 이 감지 못 하는
// 약점 차단. Test 10 (PII regression sentinel) 에서 5 채널 stringify.
const debugMock = logger.debug as unknown as jest.Mock;
const logMock = logger.log as unknown as jest.Mock;

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
    // Plan 16-17 default — 역조회 후보 0 (Custom Token 기존 계정 없음).
    mockIdxWhere.mockReset();
    mockIdxWhereGet.mockReset();
    mockIdxWhereGet.mockResolvedValue({docs: []});
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
  // 검증이 fail → JWTClaimValidationFailed throw → caller 가 unauthenticated
  // 매핑. Plan 15-06 UAT A1 의 실 단말 token decode 결과로 final LOCK 검증.
  // eslint-disable-next-line max-len
  it("Test 2: iss mismatch (trailing slash trap) → unauthenticated HttpsError", async () => {
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
    // WR-01 (Phase 15 리뷰): IdP 가 토큰을 거부한 상황은 4 endpoint 공용
    // 매핑 표에서 `unauthenticated` 로 통일됐다 (gRPC 표준 의미론).
    await expect(promise).rejects.toMatchObject({
      code: "unauthenticated",
      message: "errorInvalidCredentials",
    });
    expect(warnMock).toHaveBeenCalledWith(
      expect.objectContaining({event: "yahoojp_jwt_verify_failed"}),
      expect.any(String),
    );
  });

  it("Test 3: aud mismatch → unauthenticated HttpsError", async () => {
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
    // WR-01 (Phase 15 리뷰): IdP 가 토큰을 거부한 상황은 4 endpoint 공용
    // 매핑 표에서 `unauthenticated` 로 통일됐다 (gRPC 표준 의미론).
    await expect(promise).rejects.toMatchObject({
      code: "unauthenticated",
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

  it("Test 4: exp 만료 → unauthenticated HttpsError", async () => {
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
    // WR-01 (Phase 15 리뷰): IdP 가 토큰을 거부한 상황은 4 endpoint 공용
    // 매핑 표에서 `unauthenticated` 로 통일됐다 (gRPC 표준 의미론).
    await expect(promise).rejects.toMatchObject({
      code: "unauthenticated",
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
  it("Test 5: nonce raw mismatch → unauthenticated HttpsError", async () => {
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
    // WR-01 (Phase 15 리뷰): IdP 가 토큰을 거부한 상황은 4 endpoint 공용
    // 매핑 표에서 `unauthenticated` 로 통일됐다 (gRPC 표준 의미론).
    await expect(promise).rejects.toMatchObject({
      code: "unauthenticated",
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

  // Test 6: JWKSNoMatchingKey (kid 부재) 는 JWKS 도달 자체는 성공한
  // 상황이므로 transient 가 아니라 자격증명 축이다 → unauthenticated.
  // (JWKS *도달* 실패 = JWKSTimeout / non-200 은 WR-02 케이스에서
  //  별도로 unavailable 로 분류된다.)
  // eslint-disable-next-line max-len
  it("Test 6: JWKS fetch 실패 (JWKSNoMatchingKey) → unauthenticated", async () => {
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
    // WR-01 (Phase 15 리뷰): IdP 가 토큰을 거부한 상황은 4 endpoint 공용
    // 매핑 표에서 `unauthenticated` 로 통일됐다 (gRPC 표준 의미론).
    await expect(promise).rejects.toMatchObject({
      code: "unauthenticated",
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

  // --------------------------------------------------------------------------
  // WR-03 (Phase 15 리뷰) 회귀 가드 — 비-string 인자.
  //
  // 이전 구현의 `!idToken || !nonce` falsy 가드는 `{idToken: 12345,
  // nonce: {}}` 를 통과시켜 verifier 까지 내려보냈다. 그 결과 (1) 오류가
  // "입력 타입 오류" 가 아니라 "자격증명 무효" 로 로깅되고, (2) nonce 가
  // 객체일 때 `claimNonce !== expectedNonce` 참조 비교가 항상 참이 되어
  // 정상 토큰까지 거부됐다. **verifier 미호출** 이 회귀 판정의 핵심 단언이다.
  // --------------------------------------------------------------------------
  const nonStringArgCases: Array<[string, unknown, unknown]> = [
    ["idToken=number", 12345, "n"],
    ["nonce=object", "FAKE", {}],
    ["idToken=null", null, "n"],
    ["nonce 누락", "FAKE", undefined],
  ];
  it.each(nonStringArgCases)(
    "WR-03: %s → invalid-argument + verifier 미호출",
    async (_label, idToken, nonce) => {
      const wrapped = testEnv.wrap(myFunctions.yahoojpCustomToken);
      const promise = wrapped({
        app: {appId: "test"},
        data: {idToken, nonce},
      } as never);
      await expect(promise).rejects.toMatchObject({
        code: "invalid-argument",
        message: "errorInvalidArgument",
      });
      expect(mockVerifyYahoojpIdToken).not.toHaveBeenCalled();
    },
  );
});

// Task 2 — Test 10 (PII regression sentinel). Phase 14 WR-01 fix 패턴
// 직접 mirror — 5 logger 채널 (info/warn/error/debug/log) 전체 stringify 후
// idToken / payload claims (sub/name/picture) / raw nonce 5 sentinel 값
// 0 hit 검증. T-15-09 mitigation closed.
describe("yahoojpCustomToken onCall — Task 2 (Test 10 PII regression)", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockCreateCustomToken.mockResolvedValue("MOCK_YAHOOJP_TOKEN");
    mockCreateUser.mockResolvedValue({uid: "new-uid-yj-pre"});
    mockGetUserByEmail.mockReset();
    mockGetUserByEmail.mockRejectedValue(
      Object.assign(new Error("not found"), {code: "auth/user-not-found"}),
    );
    // Plan 16-17 default — 역조회 후보 0 (Custom Token 기존 계정 없음).
    mockIdxWhere.mockReset();
    mockIdxWhereGet.mockReset();
    mockIdxWhereGet.mockResolvedValue({docs: []});
  });

  // eslint-disable-next-line max-len
  it("Test 10: PII regression — 5 logger 채널 (info/warn/error/debug/log) 0 hit", async () => {
    const sensitiveIdToken = "eyJSENSITIVE.YJ.IDTOKEN.PAYLOAD.SIG";
    const sensitiveSub = "yj-sub-sensitive-123";
    const sensitiveName = "Sensitive Yahoo Name";
    const sensitivePicture = "https://sensitive.yahoojp.example.com/pic.jpg";
    const sensitiveNonce = "raw-nonce-sensitive-yj-abc";

    mockVerifyYahoojpIdToken.mockResolvedValue({
      sub: sensitiveSub,
      name: sensitiveName,
      picture: sensitivePicture,
    });
    mockIdxGet.mockResolvedValue({exists: false});
    mockTxGet.mockResolvedValue({exists: false});

    const wrapped = testEnv.wrap(myFunctions.yahoojpCustomToken);
    await wrapped({
      auth: {uid: "caller-uid-yj"},
      app: {appId: "test"},
      data: {idToken: sensitiveIdToken, nonce: sensitiveNonce},
    } as never);

    // 5 logger 채널 전체 stringify — debug/log 도 sentinel 배열 포함
    // (WR-02 회귀 가드 patch mirror).
    const allLogs = [
      ...infoMock.mock.calls.flat(),
      ...warnMock.mock.calls.flat(),
      ...errorMock.mock.calls.flat(),
      ...debugMock.mock.calls.flat(),
      ...logMock.mock.calls.flat(),
    ].map((arg) => JSON.stringify(arg)).join("\n");

    // (a) idToken raw value 0 hit
    expect(allLogs).not.toContain(sensitiveIdToken);
    // (b) payload.sub raw value 0 hit
    expect(allLogs).not.toContain(sensitiveSub);
    // (c) payload.name 0 hit
    expect(allLogs).not.toContain(sensitiveName);
    // (d) payload.picture 0 hit
    expect(allLogs).not.toContain(sensitivePicture);
    // (e) raw nonce value 0 hit
    expect(allLogs).not.toContain(sensitiveNonce);

    // 추가 sentinel — 정상 검증 시 logger.info 호출에 event/uid/isNewUser
    // 만 포함, sensitive 값 미포함.
    expect(infoMock).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "yahoojp_custom_token_issued",
        uid: "caller-uid-yj",
        isNewUser: true,
      }),
      expect.any(String),
    );
  });

  // Phase 16 D-13/D-14 (Plan 16-03 Task 3.2) — termsAcceptanceSnapshot arg
  // add-only. snapshot=undefined 시 기존 11 case 회귀 0 보장 (C1) + snapshot
  // present 시 5 필드 atomic mirror (C2).
  it(
    // eslint-disable-next-line max-len
    "C1: termsAcceptanceSnapshot=undefined → 기존 behavior 보존 (users/{uid} 직접 set 호출 0)",
    async () => {
      mockVerifyYahoojpIdToken.mockResolvedValue({
        sub: "yj-C1",
        nonce: "n",
      });
      mockIdxGet.mockResolvedValue({exists: false});
      mockTxGet.mockResolvedValue({exists: false});
      mockUserDocSet.mockClear();

      const wrapped = testEnv.wrap(myFunctions.yahoojpCustomToken);
      const result = (await wrapped({
        auth: {uid: "anon-yj-C1"},
        app: {appId: "test"},
        data: {idToken: "FAKE", nonce: "n"},
      } as never)) as {customToken: string; uid: string; isNewUser: boolean};

      expect(result.uid).toBe("anon-yj-C1");
      expect(mockUserDocSet).not.toHaveBeenCalled();
    },
  );

  it(
    // eslint-disable-next-line max-len
    "C2: termsAcceptanceSnapshot present → users/{uid}.termsAccepted 5 필드 atomic mirror (merge:true)",
    async () => {
      mockVerifyYahoojpIdToken.mockResolvedValue({
        sub: "yj-C2",
        nonce: "n",
      });
      mockIdxGet.mockResolvedValue({exists: false});
      mockTxGet.mockResolvedValue({exists: false});
      mockUserDocSet.mockClear();

      const snapshot = {
        // WR-02: version 은 SERVER_TERMS_CURRENT_VERSION 상한으로 clamp 되므로
        // 정상 client 가 보낼 수 있는 값은 1 뿐이다 (미래 버전 위조 차단).
        // endpoint 별 fixture 구분은 acceptedAt / marketing 이 담당한다.
        version: 1,
        service: true,
        privacy: true,
        marketing: true,
        acceptedAt: "2026-05-29T15:00:00.000Z",
      };

      const wrapped = testEnv.wrap(myFunctions.yahoojpCustomToken);
      await wrapped({
        auth: {uid: "anon-yj-C2"},
        app: {appId: "test"},
        data: {
          idToken: "FAKE",
          nonce: "n",
          termsAcceptanceSnapshot: snapshot,
        },
      } as never);

      expect(mockUserDocSet).toHaveBeenCalledTimes(1);
      const [payload, options] = mockUserDocSet.mock.calls[0] as [
        {termsAccepted: Record<string, unknown>},
        {merge: boolean},
      ];
      expect(payload.termsAccepted.version).toBe(1);
      expect(typeof payload.termsAccepted.version).toBe("number");
      expect(payload.termsAccepted.service).toBe(true);
      expect(payload.termsAccepted.privacy).toBe(true);
      expect(payload.termsAccepted.marketing).toBe(true);
      const acceptedAt = payload.termsAccepted.acceptedAt as {
        _kind: string;
        iso: string;
      };
      expect(acceptedAt._kind).toBe("MOCK_TIMESTAMP");
      expect(acceptedAt.iso).toBe("2026-05-29T15:00:00.000Z");
      expect(options).toEqual({merge: true});
      const termsMirrorInfoCalls = infoMock.mock.calls.filter((args) => {
        const ev = (args[0] as {terms_mirrored?: boolean})?.terms_mirrored;
        return ev === true;
      });
      expect(termsMirrorInfoCalls.length).toBeGreaterThanOrEqual(1);
    },
  );
});

// 16-13 (A4 gap closure) — yahoojp collision throw 의 details.existingProvider
// 회귀 가드. 기존 yahoojp test 가 collision case 부재 (Test 1-9 + Task 2 +
// C1/C2) — LINE Test 10/11 패턴 mirror 로 두 collision arm 신규 등재.
describe("yahoojpCustomToken onCall — 16-13 collision details", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockCreateCustomToken.mockResolvedValue("MOCK_YAHOOJP_TOKEN");
    mockCreateUser.mockResolvedValue({uid: "new-uid-yj-pre"});
    mockGetUserByEmail.mockReset();
    mockGetUserByEmail.mockRejectedValue(
      Object.assign(new Error("not found"), {code: "auth/user-not-found"}),
    );
    // Plan 16-17 default — 역조회 후보 0 (Custom Token 기존 계정 없음).
    mockIdxWhere.mockReset();
    mockIdxWhereGet.mockReset();
    mockIdxWhereGet.mockResolvedValue({docs: []});
  });

  it(
    // eslint-disable-next-line max-len
    "16-13 YJP-CT-COLLISION-1: conflictKind=email_in_use → already-exists + details.existingProvider='unknown'",
    async () => {
      mockVerifyYahoojpIdToken.mockResolvedValue({
        sub: "yj-collision",
        name: "Hanako",
      });
      // !callerUid 분기 createUser auth/email-already-in-use rejection 으로
      // helper 가 conflictKind: 'email_in_use' 반환. Yahoo!JP 은 email scope
      // 미채택 → userInfo.email 부재 → provider 추론 skip → 'unknown'.
      mockIdxGet.mockResolvedValue({exists: false});
      mockCreateUser.mockRejectedValueOnce(
        Object.assign(new Error("email exists"), {
          code: "auth/email-already-in-use",
        }),
      );

      const wrapped = testEnv.wrap(myFunctions.yahoojpCustomToken);
      const promise = wrapped({
        app: {appId: "test"},
        data: {idToken: "FAKE", nonce: "n"},
      } as never);
      await expect(promise).rejects.toBeInstanceOf(HttpsError);
      await expect(promise).rejects.toMatchObject({
        code: "already-exists",
        message: "errorAccountExistsWithDifferentCredential",
        details: {existingProvider: "unknown"},
      });
      expect(warnMock).toHaveBeenCalledWith(
        expect.objectContaining({event: "yahoojp_email_collision"}),
        expect.any(String),
      );
    },
  );

  // Plan 16-17 (A4 매트릭스) — Yahoo!JP caller. D-YJP-09 로 email claim 을
  // 받지 않으므로 endpoint 자체 trigger 불가 → resolveIdentity spy 로
  // "helper 가 naver slug 를 산출하면 endpoint 가 details 로 전달" 배선만
  // 잠근다. 산출 능력은 identity_index.test.ts 의 T-16-17-* 가 담당.
  it(
    // eslint-disable-next-line max-len
    "T-16-17-YJP-CT-EXISTING-01: existingProvider='naver' → details 로 그대로 전달",
    async () => {
      mockVerifyYahoojpIdToken.mockResolvedValue({
        sub: "yj-ct-existing",
        name: "Hanako",
      });
      mockIdxGet.mockResolvedValue({exists: false});
      const spy = jest
        .spyOn(identityIndex, "resolveIdentity")
        .mockResolvedValueOnce({
          uid: "",
          isNewUser: false,
          conflictKind: "email_in_use",
          existingProvider: "naver",
        });

      try {
        const wrapped = testEnv.wrap(myFunctions.yahoojpCustomToken);
        const promise = wrapped({
          auth: {uid: "anon-uid-yj-ct"},
          app: {appId: "test"},
          data: {idToken: "FAKE", nonce: "n"},
        } as never);
        await expect(promise).rejects.toBeInstanceOf(HttpsError);
        await expect(promise).rejects.toMatchObject({
          code: "already-exists",
          message: "errorAccountExistsWithDifferentCredential",
          details: {existingProvider: "naver"},
        });
        expect(warnMock).toHaveBeenCalledWith(
          expect.objectContaining({event: "yahoojp_email_collision"}),
          expect.any(String),
        );
        expect(mockCreateCustomToken).not.toHaveBeenCalled();
      } finally {
        spy.mockRestore();
      }
    },
  );

  it(
    // eslint-disable-next-line max-len
    "16-13 YJP-CT-COLLISION-2: anonymous + existing yahoojp identity → already-exists + details.existingProvider='yahoojp'",
    async () => {
      mockVerifyYahoojpIdToken.mockResolvedValue({
        sub: "yj-existing-b",
        name: "Jiro",
      });
      // 익명 사용자 'anon-A' 가 기존 yahoojp identity 'existing-B' 로 로그인
      // 시도 → conflictKind: 'anonymous_existing_collision', existingProvider
      // = 호출 endpoint slug ('yahoojp').
      mockIdxGet.mockResolvedValue({exists: true});
      mockTxGet.mockResolvedValue({
        exists: true,
        data: () => ({firebaseUid: "existing-yj-B"}),
      });

      const wrapped = testEnv.wrap(myFunctions.yahoojpCustomToken);
      const promise = wrapped({
        auth: {uid: "anon-A-yj"},
        app: {appId: "test"},
        data: {idToken: "FAKE", nonce: "n"},
      } as never);
      await expect(promise).rejects.toBeInstanceOf(HttpsError);
      await expect(promise).rejects.toMatchObject({
        code: "already-exists",
        message: "errorAccountExistsWithDifferentCredential",
        details: {existingProvider: "yahoojp"},
      });
      expect(warnMock).toHaveBeenCalledWith(
        expect.objectContaining({event: "yahoojp_anonymous_conflict"}),
        expect.any(String),
      );
    },
  );

  // WR-01 (2차 리뷰): isNewUser 게이트 회귀 가드 — kakao C3 mirror.
  //
  // 게이트가 없으면 device-local 동의가 남은 기기의 재로그인이 서버의
  // 권위 있는 termsAccepted (marketing opt-in / version 포함) 를 덮어쓴다.
  it(
    // eslint-disable-next-line max-len
    "C3 (WR-01): 기존 사용자 재로그인 (isNewUser=false) + snapshot present → mirror skip (users/{uid} set 0)",
    async () => {
      mockVerifyYahoojpIdToken.mockResolvedValue({
        sub: "yj-C3",
        nonce: "n",
      });
      // 기존 identity_index 매핑 존재 + 미인증 호출 → conflictKind null,
      // isNewUser=false (재로그인).
      mockIdxGet.mockResolvedValue({exists: true});
      mockTxGet.mockResolvedValue({
        exists: true,
        data: () => ({firebaseUid: "existing-uid-C3"}),
      });
      mockUserDocSet.mockClear();

      const wrapped = testEnv.wrap(myFunctions.yahoojpCustomToken);
      const result = (await wrapped({
        app: {appId: "test"},
        data: {
          idToken: "FAKE",
          nonce: "n",
          termsAcceptanceSnapshot: {
            version: 1,
            service: true,
            privacy: true,
            marketing: false,
            acceptedAt: "2026-05-29T12:00:00.000Z",
          },
        },
      } as never)) as {customToken: string; uid: string; isNewUser: boolean};

      expect(result.isNewUser).toBe(false);
      // 핵심 — 기존 사용자 문서는 건드리지 않는다.
      expect(mockUserDocSet).not.toHaveBeenCalled();
    },
  );
});
