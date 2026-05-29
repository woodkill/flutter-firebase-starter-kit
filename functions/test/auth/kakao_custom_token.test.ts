/**
 * kakaoCustomToken onCall 회귀 테스트 (Phase 12 Task 3).
 *
 * RESEARCH Pattern D 의 6 케이스 (성공 / JWT 실패 / 미인증+미등록 /
 * 익명+미등록 seed / 기존 매핑 / 충돌 first-write-wins) + Pitfall 1/7
 * PII 회귀 1 케이스.
 *
 * 모든 jest.mock 호출은 hoist 되므로 src import 보다 먼저 정의되어야 한다
 * (firebase-functions-test 공식 권장 패턴 — ping.test.ts 와 동일).
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
  defineSecret: () => ({value: () => "fake-rest-api-key"}),
}));

// jose — Phase 14 D-LINE-02 retroactive 마이그 후 caller 가 jose.jwtVerify 를
// 직접 호출하지 않는다. errors 클래스만 보존 (R5 PII regression / Phase 9.2 Gap B
// 등 jose error 생성 시뮬레이션 케이스용). createRemoteJWKSet stub 은 jose
// 모듈 lazy load 시 SyntaxError 차단용 (moduleNameMapper jose stub 와 동등).
jest.mock("jose", () => {
  /** Mock JOSEError — instanceof 분기 동작용. */
  class JOSEError extends Error {}
  /** Mock JWTClaimValidationFailed — JOSEError 서브클래스. */
  class JWTClaimValidationFailed extends JOSEError {}
  return {
    jwtVerify: jest.fn(),
    createRemoteJWKSet: jest.fn(() => "MOCK_JWKS"),
    errors: {JOSEError, JWTClaimValidationFailed},
  };
});

// Phase 14 D-LINE-02 — createOidcVerifier helper mock. caller 는 helper 가
// 반환한 verifier 함수만 호출하므로 (issuer/aud/alg/nonce 검증 전부 흡수),
// 단일 mock 함수가 resolve(payload) / reject(joseError) 로 14 시나리오 모두
// 시뮬레이션 가능. RESEARCH Pitfall 3 — 의도적 nonce mismatch 케이스가 mock
// 가로채기로 silently PASS 되지 않도록 reject path 도 명시.
const mockVerifyKakaoIdToken = jest.fn();
jest.mock("../../src/shared/oidc_verifier", () => ({
  createOidcVerifier: jest.fn(() => mockVerifyKakaoIdToken),
}));

// firebase-admin/auth — getAuth().createCustomToken / createUser
// / deleteUser / updateUser (R9: emailVerified retroactive
// — anonymous→소셜 path 가 helper 에서 updateUser 를 호출) /
// getUserByEmail (Phase 9.2 Gap B — callerUid 분기 email collision detect).
const mockCreateCustomToken = jest.fn().mockResolvedValue("MOCK_CUSTOM_TOKEN");
const mockCreateUser = jest.fn().mockResolvedValue({uid: "new-uid-pre"});
const mockDeleteUser = jest.fn().mockResolvedValue(undefined);
const mockUpdateUser = jest.fn().mockResolvedValue(undefined);
// Phase 9.2 Gap B — default: auth/user-not-found (lookup 시 충돌 없음 의도).
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
// Phase 16 D-13/D-14 (Plan 16-03 Task 3.2) — termsAcceptanceSnapshot mirror
// 의 users/{uid}.set 호출 mock. transaction 외부의 직접 set merge — endpoint
// 본체 마지막 단계 (createCustomToken 성공 후).
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
      }),
      runTransaction: (fn: (t: unknown) => Promise<unknown>) =>
        fn({get: mockTxGet, set: mockTxSet, update: mockTxUpdate}),
    })),
    FieldValue: {
      serverTimestamp: () => "MOCK_TIMESTAMP",
      arrayUnion: (item: unknown) => ({mockArrayUnion: item}),
    },
    // Phase 16 D-13/D-14 — Timestamp.fromDate sentinel — 5 필드 mirror 의
    // acceptedAt 변환 검증용 mock. ISO 문자열 round-trip 검증.
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

const infoMock = logger.info as unknown as jest.Mock;
const warnMock = logger.warn as unknown as jest.Mock;
const errorMock = logger.error as unknown as jest.Mock;
// WR-02 mirror (from LINE Phase 14 review) — debug/log 도 PII sentinel
// 검사 배열 (allLogCalls) 에 포함. mock 선언 (line 17-18) 에 이미 등록되어
// 있으나 sentinel 배열에는 누락되어 있었다 — production code 가 향후
// logger.debug / log 추가 시 PII 회귀 silently merge 차단.
const debugMock = logger.debug as unknown as jest.Mock;
const logMock = logger.log as unknown as jest.Mock;
// Phase 14 D-LINE-02 — caller 는 createOidcVerifier 가 반환한 verifier 함수만
// 호출. `mockVerifyKakaoIdToken.mockResolvedValue(payload)` 로 검증된 payload
// 시뮬레이션 + `.mockRejectedValue(joseError)` 로 JWT 검증 실패 시뮬레이션.

afterAll(() => testEnv.cleanup());

describe("kakaoCustomToken onCall", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockCreateCustomToken.mockResolvedValue("MOCK_CUSTOM_TOKEN");
    mockCreateUser.mockResolvedValue({uid: "new-uid-pre"});
    // Phase 9.2 Gap B default — auth/user-not-found (lookup 시 충돌 없음).
    mockGetUserByEmail.mockReset();
    mockGetUserByEmail.mockRejectedValue(
      Object.assign(new Error("not found"), {code: "auth/user-not-found"}),
    );
  });

  it("성공: ID Token 검증 + Identity Index 신규 등록 + Custom Token 발급", async () => {
    mockVerifyKakaoIdToken.mockResolvedValue({
      sub: "kakao-user-456",
      nonce: "client-nonce",
    });
    mockIdxGet.mockResolvedValue({exists: false});
    mockTxGet.mockResolvedValue({exists: false});

    const wrapped = testEnv.wrap(myFunctions.kakaoCustomToken);
    const result = (await wrapped({
      auth: {uid: "anon-uid-1"},
      app: {appId: "test"},
      data: {idToken: "FAKE_JWT", nonce: "client-nonce"},
    } as never)) as {
      customToken: string;
      uid: string;
      isNewUser: boolean;
    };

    expect(result.customToken).toBe("MOCK_CUSTOM_TOKEN");
    expect(result.uid).toBe("anon-uid-1");
    expect(result.isNewUser).toBe(true);
    // Phase 14 D-LINE-02 — helper 호출 인자 검증 (caller 가 idToken + raw nonce
    // 만 전달, issuer/aud/alg 은 module-level factory 호출에서 lock).
    expect(mockVerifyKakaoIdToken).toHaveBeenCalledWith(
      "FAKE_JWT",
      "client-nonce",
    );
    // Phase 9.2 Gap B 옵션 C — email 부재 시 두 번째 인자 undefined.
    expect(mockCreateCustomToken).toHaveBeenCalledWith("anon-uid-1", undefined);
    // PII 금지 sentinel — info 호출 payload 에 토큰 본문 미포함.
    const infoCalls = infoMock.mock.calls;
    expect(infoCalls.length).toBeGreaterThanOrEqual(1);
  });

  it("ID Token 검증 실패 → invalid-argument HttpsError", async () => {
    mockVerifyKakaoIdToken.mockRejectedValue(
      new (jose.errors.JOSEError as new (m: string) => Error)("bad signature"),
    );
    const wrapped = testEnv.wrap(myFunctions.kakaoCustomToken);
    await expect(
      wrapped({
        app: {appId: "test"},
        data: {idToken: "BAD", nonce: "n"},
      } as never),
    ).rejects.toBeInstanceOf(HttpsError);
    // 분기 진입 검증 — warn mock 으로 catch 블록 도달 확인.
    expect(warnMock).toHaveBeenCalledWith(
      expect.objectContaining({event: "kakao_jwt_verify_failed"}),
      expect.any(String),
    );
  });

  it("미인증 + 미등록 → preCreatedUid 경로로 새 UID 자동 생성", async () => {
    mockVerifyKakaoIdToken.mockResolvedValue({
      sub: "kakao-user-new",
      nonce: "n",
    });
    mockIdxGet.mockResolvedValue({exists: false});
    mockTxGet.mockResolvedValue({exists: false});

    const wrapped = testEnv.wrap(myFunctions.kakaoCustomToken);
    const result = (await wrapped({
      app: {appId: "test"},
      data: {idToken: "FAKE", nonce: "n"},
    } as never)) as {customToken: string; uid: string; isNewUser: boolean};

    expect(result.uid).toBe("new-uid-pre");
    expect(result.isNewUser).toBe(true);
    expect(mockCreateUser).toHaveBeenCalledTimes(1);
  });

  it("익명 호출자 + 미등록 → seed UID = request.auth.uid", async () => {
    mockVerifyKakaoIdToken.mockResolvedValue({sub: "kakao-anon", nonce: "n"});
    mockIdxGet.mockResolvedValue({exists: false});
    mockTxGet.mockResolvedValue({exists: false});

    const wrapped = testEnv.wrap(myFunctions.kakaoCustomToken);
    const result = (await wrapped({
      auth: {uid: "anon-seed-uid"},
      app: {appId: "test"},
      data: {idToken: "FAKE", nonce: "n"},
    } as never)) as {customToken: string; uid: string; isNewUser: boolean};

    expect(result.uid).toBe("anon-seed-uid");
    expect(result.isNewUser).toBe(true);
    // callerUid 가 있으면 createUser 미호출.
    expect(mockCreateUser).not.toHaveBeenCalled();
  });

  it(
    "기존 매핑 + 미인증 호출자 → 그 firebaseUid 재사용 (정상 path, R3 conflictKind null)",
    async () => {
      // R3 (Plan 12.1-06): callerUid 가 없으면 anonymous_existing_collision
      // 분기 미진입 → conflictKind null → 정상 customToken 발급.
      // 이 케이스가 "기존 매핑 정상 재사용" 의 진짜 시나리오 (재로그인 등).
      mockVerifyKakaoIdToken.mockResolvedValue({
        sub: "kakao-existing",
        nonce: "n",
      });
      mockIdxGet.mockResolvedValue({exists: true});
      mockTxGet.mockResolvedValue({
        exists: true,
        data: () => ({firebaseUid: "existing-uid-9"}),
      });

      const wrapped = testEnv.wrap(myFunctions.kakaoCustomToken);
      const result = (await wrapped({
        // auth 없음 — 미인증 (재로그인) 호출.
        app: {appId: "test"},
        data: {idToken: "FAKE", nonce: "n"},
      } as never)) as {customToken: string; uid: string; isNewUser: boolean};

      expect(result.uid).toBe("existing-uid-9");
      expect(result.isNewUser).toBe(false);
      // Phase 9.2 Gap B 옵션 C — email 부재 시 두 번째 인자 undefined.
      expect(mockCreateCustomToken).toHaveBeenCalledWith(
        "existing-uid-9",
        undefined,
      );
    },
  );

  it(
    // eslint-disable-next-line max-len
    "기존 매핑 + 동일 callerUid (재로그인) → 그 firebaseUid 재사용 (D-12, R3 conflictKind null)",
    async () => {
      // R3 (Plan 12.1-06): callerUid === existing.firebaseUid 면 충돌 아님 →
      // conflictKind null → 정상 customToken 발급. 이 시나리오는 *재로그인* —
      // 동일 사용자가 idle 후 재진입, 같은 UID 보존.
      mockVerifyKakaoIdToken.mockResolvedValue({
        sub: "kakao-rerun",
        nonce: "n",
      });
      mockIdxGet.mockResolvedValue({exists: true});
      mockTxGet.mockResolvedValue({
        exists: true,
        data: () => ({firebaseUid: "existing-uid-9"}),
      });

      const wrapped = testEnv.wrap(myFunctions.kakaoCustomToken);
      const result = (await wrapped({
        auth: {uid: "existing-uid-9"}, // 동일 UID (재로그인).
        app: {appId: "test"},
        data: {idToken: "FAKE", nonce: "n"},
      } as never)) as {customToken: string; uid: string; isNewUser: boolean};

      // first-write-wins — identity_index 의 firebaseUid 가 우선.
      expect(result.uid).toBe("existing-uid-9");
      expect(result.isNewUser).toBe(false);
    },
  );

  it(
    // eslint-disable-next-line max-len
    "PII 금지 — logger 에 idToken / payload.email / kakao_account 본문 미노출 (Pitfall 1/7)",
    async () => {
      mockVerifyKakaoIdToken.mockResolvedValue({
        sub: "kakao-456",
        email: "secret@test.com",
        kakao_account: {profile: {nickname: "secret-nickname"}},
        nonce: "n",
      });
      mockIdxGet.mockResolvedValue({exists: false});
      mockTxGet.mockResolvedValue({exists: false});

      const wrapped = testEnv.wrap(myFunctions.kakaoCustomToken);
      await wrapped({
        auth: {uid: "anon-pii"},
        app: {appId: "test"},
        data: {idToken: "JWT_BODY", nonce: "n"},
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
        const stringified = JSON.stringify(args);
        expect(stringified).not.toContain("secret@test.com");
        expect(stringified).not.toContain("secret-nickname");
        expect(stringified).not.toContain("JWT_BODY");
        expect(stringified).not.toContain("kakao_account");
      }
    },
  );

  // R3 (Plan 12.1-06 / BL-04 + WR-06) — D-32 caller throw responsibility.
  // helper 가 conflictKind 로 detect → caller 가 try/catch + switch 로 안전한
  // already-exists HttpsError 변환 (email enumeration 차단 + 사용자 recovery
  // 가능). helper 의 unexpected throw 는 internal 매핑.
  it(
    // eslint-disable-next-line max-len
    "R3: email collision (createUser auth/email-already-in-use) → already-exists HttpsError + logger.warn",
    async () => {
      mockVerifyKakaoIdToken.mockResolvedValue({
        sub: "kakao-collision",
        email: "collision@example.com",
        nonce: "n",
      });
      // helper 의 idxRef.get() 가 미존재 + 미인증 → createUser 호출 → email
      // collision rejection. helper 가 conflictKind: 'email_in_use' 반환,
      // caller 가 already-exists throw.
      mockIdxGet.mockResolvedValue({exists: false});
      mockCreateUser.mockRejectedValueOnce(
        Object.assign(new Error("email exists"), {
          code: "auth/email-already-in-use",
        }),
      );

      const wrapped = testEnv.wrap(myFunctions.kakaoCustomToken);
      // firebase-functions/https HttpsError — code 는 prefix 없는 형식
      // ("already-exists"), message 는 두 번째 인자 그대로 (.message 속성).
      const promise = wrapped({
        app: {appId: "test"},
        data: {idToken: "FAKE", nonce: "n"},
      } as never);
      await expect(promise).rejects.toBeInstanceOf(HttpsError);
      await expect(promise).rejects.toMatchObject({
        code: "already-exists",
      });
      try {
        await promise;
      } catch (err: unknown) {
        expect((err as HttpsError).code).toBe("already-exists");
        expect((err as HttpsError).message).toBe(
          "errorAccountExistsWithDifferentCredential",
        );
      }

      expect(warnMock).toHaveBeenCalledWith(
        expect.objectContaining({event: "kakao_email_collision"}),
        expect.any(String),
      );
      // PII 회귀 — collision email 본문이 logger payload 에 미노출.
      // WR-02 mirror — debug/log 도 sentinel 배열 포함.
      const allLogCalls = [
        ...infoMock.mock.calls,
        ...warnMock.mock.calls,
        ...errorMock.mock.calls,
        ...debugMock.mock.calls,
        ...logMock.mock.calls,
      ];
      for (const args of allLogCalls) {
        const stringified = JSON.stringify(args);
        expect(stringified).not.toContain("collision@example.com");
      }
    },
  );

  it(
    // eslint-disable-next-line max-len
    "R3: anonymous + existing kakao identity 충돌 → already-exists HttpsError + logger.warn",
    async () => {
      mockVerifyKakaoIdToken.mockResolvedValue({
        sub: "kakao-existing",
        nonce: "n",
      });
      // 익명 사용자 'anon-A' 가 *기존* kakao identity 'existing-B' 로 로그인
      // 시도 — helper 가 conflictKind: 'anonymous_existing_collision' 반환,
      // caller 가 anonymous Firestore 데이터 보존 + already-exists throw.
      mockIdxGet.mockResolvedValue({exists: true});
      mockTxGet.mockResolvedValue({
        exists: true,
        data: () => ({firebaseUid: "existing-B"}),
      });

      const wrapped = testEnv.wrap(myFunctions.kakaoCustomToken);
      const promise = wrapped({
        auth: {uid: "anon-A"},
        app: {appId: "test"},
        data: {idToken: "FAKE", nonce: "n"},
      } as never);
      await expect(promise).rejects.toBeInstanceOf(HttpsError);
      await expect(promise).rejects.toMatchObject({
        code: "already-exists",
      });
      try {
        await promise;
      } catch (err: unknown) {
        expect((err as HttpsError).message).toBe(
          "errorAccountExistsWithDifferentCredential",
        );
      }

      expect(warnMock).toHaveBeenCalledWith(
        expect.objectContaining({event: "kakao_anonymous_conflict"}),
        expect.any(String),
      );
    },
  );

  it(
    // eslint-disable-next-line max-len
    "R3: helper unexpected throw → internal HttpsError + logger.error (event: identity_index_failed)",
    async () => {
      mockVerifyKakaoIdToken.mockResolvedValue({sub: "kakao-fail", nonce: "n"});
      // helper 의 idxRef.get() 이 firestore 오류 throw — caller 가 catch 하여
      // internal 로 매핑.
      mockIdxGet.mockRejectedValueOnce(new Error("firestore unavailable"));

      const wrapped = testEnv.wrap(myFunctions.kakaoCustomToken);
      const promise = wrapped({
        app: {appId: "test"},
        data: {idToken: "FAKE", nonce: "n"},
      } as never);
      await expect(promise).rejects.toBeInstanceOf(HttpsError);
      await expect(promise).rejects.toMatchObject({code: "internal"});
      try {
        await promise;
      } catch (err: unknown) {
        expect((err as HttpsError).message).toBe("errorUnknown");
      }

      expect(errorMock).toHaveBeenCalledWith(
        expect.objectContaining({event: "identity_index_failed"}),
        expect.any(String),
      );
      // PII 회귀 — err.message ('firestore unavailable') 본문 미노출.
      // WR-02 mirror — error 만이 아닌 info/warn/debug/log 전체 sentinel 검사.
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
    },
  );

  it(
    "R3: 정상 path (conflictKind null) → customToken 정상 발급 + throw 안 함",
    async () => {
      mockVerifyKakaoIdToken.mockResolvedValue({
        sub: "kakao-normal",
        nonce: "n",
      });
      // 미인증 + 미등록 + createUser 정상 → conflictKind null → caller 가 throw
      // 분기 미진입.
      mockIdxGet.mockResolvedValue({exists: false});
      mockTxGet.mockResolvedValue({exists: false});

      const wrapped = testEnv.wrap(myFunctions.kakaoCustomToken);
      const result = (await wrapped({
        app: {appId: "test"},
        data: {idToken: "FAKE", nonce: "n"},
      } as never)) as {customToken: string; uid: string; isNewUser: boolean};

      expect(result.customToken).toBe("MOCK_CUSTOM_TOKEN");
      expect(result.uid).toBe("new-uid-pre");
      expect(result.isNewUser).toBe(true);
      // R3 throw 분기에 미진입 — kakao_email_collision /
      // kakao_anonymous_conflict warn 호출 0회.
      const r3WarnCalls = warnMock.mock.calls.filter((args) => {
        const ev = (args[0] as {event?: string})?.event;
        return (
          ev === "kakao_email_collision" ||
          ev === "kakao_anonymous_conflict"
        );
      });
      expect(r3WarnCalls.length).toBe(0);
    },
  );

  // R5 (Plan 12.1-07 / WR-03, D-40) — jose 에러 code 비-PII 로깅.
  // catch 블록 (line 91-101) 이 err.code ?? err.name 만 logger.warn 의 code
  // 필드로 노출. err.message / err.payload 본문 절대 미포함 (Pitfall 7).
  // jose 6.x JOSEError.code 는 stable public property
  // ([VERIFIED via Context7] panva/jose).
  it(
    // eslint-disable-next-line max-len
    "R5: JWTClaimValidationFailed → logger.warn 의 code 필드 = ERR_JWT_CLAIM_VALIDATION_FAILED",
    async () => {
      // jose mock 의 JWTClaimValidationFailed 에 code property set —
      // 실제 jose 6.x 의 stable code property 을 시뮬레이션. unknown 경유
      // double cast — 실제 jose 타입은 (message, payload, claim?, reason?)
      // 이지만 mock factory 는 단일 인자 (test line 27-37).
      const ErrCtor = jose.errors.JWTClaimValidationFailed as unknown as new (
        m: string
      ) => Error;
      const err = new ErrCtor("bad nonce");
      (err as unknown as {code: string}).code =
        "ERR_JWT_CLAIM_VALIDATION_FAILED";
      mockVerifyKakaoIdToken.mockRejectedValue(err);

      const wrapped = testEnv.wrap(myFunctions.kakaoCustomToken);
      await expect(
        wrapped({
          app: {appId: "test"},
          data: {idToken: "FAKE", nonce: "n"},
        } as never),
      ).rejects.toMatchObject({
        code: "invalid-argument",
        message: "errorInvalidCredentials",
      });

      expect(warnMock).toHaveBeenCalledWith(
        expect.objectContaining({
          event: "kakao_jwt_verify_failed",
          code: "ERR_JWT_CLAIM_VALIDATION_FAILED",
        }),
        expect.any(String),
      );
    },
  );

  it(
    "R5: PII regression — JOSEError.message PII sentinel 미노출 (Pitfall 7)",
    async () => {
      const sentinel =
        "PII_SENTINEL_secret@example.com_kakao_account_nickname";
      const ErrCtor = jose.errors.JWTClaimValidationFailed as unknown as new (
        m: string
      ) => Error;
      const err = new ErrCtor(sentinel);
      (err as unknown as {code: string}).code =
        "ERR_JWT_CLAIM_VALIDATION_FAILED";
      mockVerifyKakaoIdToken.mockRejectedValue(err);

      const wrapped = testEnv.wrap(myFunctions.kakaoCustomToken);
      await expect(
        wrapped({
          app: {appId: "test"},
          data: {idToken: "FAKE", nonce: "n"},
        } as never),
      ).rejects.toBeInstanceOf(Error);

      // 모든 log call 에서 sentinel + 분해 토큰 미포함 검증.
      // WR-02 mirror — debug/log 도 sentinel 배열 포함.
      const allLogCalls = [
        ...infoMock.mock.calls,
        ...warnMock.mock.calls,
        ...errorMock.mock.calls,
        ...debugMock.mock.calls,
        ...logMock.mock.calls,
      ];
      for (const args of allLogCalls) {
        const stringified = JSON.stringify(args);
        expect(stringified).not.toContain(sentinel);
        expect(stringified).not.toContain("secret@example.com");
        expect(stringified).not.toContain("nickname");
      }
    },
  );

  it(
    "R5: 비-jose Error 도 err.name fallback (errCode = Error.name)",
    async () => {
      // TypeError 같은 일반 Error throw → err instanceof Error 분기 →
      // errCode = err.name = 'TypeError'. JOSEError 가 아니므로 internal 매핑.
      const err = new TypeError("unrelated type error");
      mockVerifyKakaoIdToken.mockRejectedValue(err);

      const wrapped = testEnv.wrap(myFunctions.kakaoCustomToken);
      await expect(
        wrapped({
          app: {appId: "test"},
          data: {idToken: "FAKE", nonce: "n"},
        } as never),
      ).rejects.toMatchObject({
        code: "internal",
        message: "errorUnknown",
      });

      expect(warnMock).toHaveBeenCalledWith(
        expect.objectContaining({
          event: "kakao_jwt_verify_failed",
          code: "TypeError",
        }),
        expect.any(String),
      );
    },
  );

  // Phase 13 — see ROADMAP.md
  // D-54 retroactive — RESEARCH Example C 패턴 verbatim 인용 (line 1442-1461).
  // 기존 R5 PII regression (line 503-537) 가 sentinel
  // "PII_SENTINEL_secret@example.com_kakao_account_nickname" 으로 검증 중인데,
  // 본 케이스는 다른 sentinel 분해 토큰 (email@test.com / PII_NICK) 으로 추가
  // 검증 — Phase 13 fetch + Phase 12 jose retroactive 의 sentinel 통일성 + by-
  // construction 한계 보강 (catch 메시지에 logger 추가 시 RED).
  it(
    // eslint-disable-next-line max-len
    "T-13-PII-KAKAO-RETRO-01: D-54 retroactive — jose error message PII sentinel 강화",
    async () => {
      const sentinel =
        "PII_SENTINEL_email@test.com_kakao_account_PII_NICK";
      const ErrCtor = jose.errors.JWTClaimValidationFailed as unknown as new (
        m: string
      ) => Error;
      const err = new ErrCtor(sentinel);
      (err as unknown as {code: string}).code =
        "ERR_JWT_CLAIM_VALIDATION_FAILED";
      mockVerifyKakaoIdToken.mockRejectedValue(err);

      const wrapped = testEnv.wrap(myFunctions.kakaoCustomToken);
      await expect(
        wrapped({
          app: {appId: "test"},
          data: {idToken: "FAKE", nonce: "n"},
        } as never),
      ).rejects.toBeInstanceOf(Error);

      // Phase 13 신규 sentinel — 모든 logger call (info/warn/error) 에서
      // sentinel + 분해 토큰 미노출 검증.
      // WR-02 mirror — debug/log 도 sentinel 배열 포함.
      const allLogCalls = [
        ...infoMock.mock.calls,
        ...warnMock.mock.calls,
        ...errorMock.mock.calls,
        ...debugMock.mock.calls,
        ...logMock.mock.calls,
      ];
      for (const args of allLogCalls) {
        const stringified = JSON.stringify(args);
        expect(stringified).not.toContain(sentinel);
        expect(stringified).not.toContain("email@test.com");
        expect(stringified).not.toContain("PII_NICK");
      }
    },
  );

  // CR-01 (Phase 13 review carry-forward): createCustomToken throw → internal
  // + errorUnknown 매핑 회귀 가드. err.message 본문은 logger 에 미노출
  // (PII 금지 D-08).
  it(
    // eslint-disable-next-line max-len
    "T-13-PII-KAKAO-RETRO-02: createCustomToken throw → internal + errorUnknown + err.message 미노출",
    async () => {
      // 정상 JWT 검증 통과 → resolveIdentity 통과 시뮬레이션.
      mockVerifyKakaoIdToken.mockResolvedValue({
        sub: "kakao-uid-token-fail",
        nonce: "n",
      });
      mockIdxGet.mockResolvedValue({exists: false});
      mockTxGet.mockResolvedValue({exists: false});
      // admin SDK throw 시뮬레이션 — err.message 에 PII sentinel 삽입.
      const sdkErr = Object.assign(
        new Error("PII_SENTINEL_KAKAO_TOKEN_FAIL_MSG"),
        {name: "FirebaseAuthError"},
      );
      mockCreateCustomToken.mockRejectedValueOnce(sdkErr);

      const wrapped = testEnv.wrap(myFunctions.kakaoCustomToken);
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
          event: "kakao_custom_token_create_failed",
          code: "FirebaseAuthError",
        }),
        expect.any(String),
      );
      // PII 회귀 — err.message 본문 logger 미노출.
      // WR-02 mirror — debug/log 도 sentinel 배열 포함.
      const allLogCalls = [
        ...infoMock.mock.calls,
        ...warnMock.mock.calls,
        ...errorMock.mock.calls,
        ...debugMock.mock.calls,
        ...logMock.mock.calls,
      ];
      for (const args of allLogCalls) {
        expect(JSON.stringify(args)).not.toContain(
          "PII_SENTINEL_KAKAO_TOKEN_FAIL_MSG",
        );
      }
    },
  );

  // Phase 9.2 Gap B (HUMAN-UAT 2026-05-11) — Kakao Custom Token 익명승격 path
  // 의 email collision detect integration. Naver 와 동일 결함 사전 차단 — Custom
  // Token architecture 동일 (resolveIdentity helper 공유). 회귀 가드 의무.
  it(
    // eslint-disable-next-line max-len
    "T-12-KAKAO-CT-COLLISION-A1: 익명승격 + Kakao email + Google 가입자 detect → already-exists + createCustomToken 미호출",
    async () => {
      mockVerifyKakaoIdToken.mockResolvedValue({
        sub: "kakao-user-collision",
        nonce: "kakao-nonce-test",
        email: "PII_COLLISION_email@kakao.com",
      });
      mockIdxGet.mockResolvedValue({exists: false});
      // Gap B 핵심 — admin.auth().getUserByEmail 가 Google 가입자 반환.
      mockGetUserByEmail.mockReset();
      mockGetUserByEmail.mockResolvedValueOnce({
        uid: "google-uid-existing",
        providerData: [
          {providerId: "google.com", uid: "google-platform-id-PII"},
        ],
      });

      const wrapped = testEnv.wrap(myFunctions.kakaoCustomToken);
      const promise = wrapped({
        auth: {uid: "anon-uid-test"}, // 익명승격 시나리오.
        app: {appId: "test"},
        data: {idToken: "kakao-token-test", nonce: "kakao-nonce-test"},
      } as never);
      await expect(promise).rejects.toBeInstanceOf(HttpsError);
      await expect(promise).rejects.toMatchObject({
        code: "already-exists",
        message: "errorAccountExistsWithDifferentCredential",
      });

      // caller switch 분기 logger event 발동 검증.
      expect(warnMock).toHaveBeenCalledWith(
        expect.objectContaining({event: "kakao_email_collision"}),
        expect.any(String),
      );
      // 옵션 C 의 미도달 invariant — early throw → createCustomToken 미발급.
      expect(mockCreateCustomToken).not.toHaveBeenCalled();

      // PII regression sentinel — email / IdP user_id 본문 logger 미노출.
      // WR-02 mirror — debug/log 도 sentinel 배열 포함.
      const allLogCalls = [
        ...infoMock.mock.calls,
        ...warnMock.mock.calls,
        ...errorMock.mock.calls,
        ...debugMock.mock.calls,
        ...logMock.mock.calls,
      ];
      for (const args of allLogCalls) {
        const stringified = JSON.stringify(args);
        expect(stringified).not.toContain("PII_COLLISION_email@kakao.com");
        expect(stringified).not.toContain("google-platform-id-PII");
      }
    },
  );

  it(
    // eslint-disable-next-line max-len
    "T-12-KAKAO-CT-COLLISION-A2: 익명승격 + Kakao email 부재 → getUserByEmail 미호출 + 정상 customToken + developerClaims undefined",
    async () => {
      // 동의 비활성 — payload.email 부재. lookup skip + 정상 customToken 발급.
      mockVerifyKakaoIdToken.mockResolvedValue({
        sub: "kakao-user-no-email",
        nonce: "kakao-nonce-test",
      });
      mockIdxGet.mockResolvedValue({exists: false});
      mockTxGet.mockResolvedValue({exists: false});

      const wrapped = testEnv.wrap(myFunctions.kakaoCustomToken);
      const result = (await wrapped({
        auth: {uid: "anon-uid-test"},
        app: {appId: "test"},
        data: {idToken: "FAKE", nonce: "kakao-nonce-test"},
      } as never)) as {customToken: string; uid: string; isNewUser: boolean};

      // 핵심 — userInfo.email 부재 → getUserByEmail lookup skip.
      expect(mockGetUserByEmail).not.toHaveBeenCalled();
      expect(result.customToken).toBe("MOCK_CUSTOM_TOKEN");
      // 옵션 C — email 부재 시 developerClaims undefined.
      expect(mockCreateCustomToken).toHaveBeenCalledWith(
        "anon-uid-test",
        undefined,
      );

      // PII regression sentinel.
      // WR-02 mirror — debug/log 도 sentinel 배열 포함.
      const allLogCalls = [
        ...infoMock.mock.calls,
        ...warnMock.mock.calls,
        ...errorMock.mock.calls,
        ...debugMock.mock.calls,
        ...logMock.mock.calls,
      ];
      for (const args of allLogCalls) {
        expect(JSON.stringify(args)).not.toContain("kakao-user-no-email");
      }
    },
  );

  it(
    // eslint-disable-next-line max-len
    "T-12-KAKAO-CT-OPTC-K1: 정상 happy-path (충돌 0 + email validated) → createCustomToken developerClaims sentinel",
    async () => {
      // Plan 08 의 Dart-side propagation 단언 부재의 대체 — functions jest
      // sentinel 로 createCustomToken 호출 인자에 developerClaims 포함 검증.
      // IN-04: Kakao OIDC ID Token 의 email_verified claim 도 mock payload 에
      // 포함 — 비즈 앱 + email 필수 동의 + 인증 완료 케이스 시뮬레이션.
      mockVerifyKakaoIdToken.mockResolvedValue({
        sub: "kakao-user-ok",
        nonce: "kakao-nonce-test",
        email: "PII_OPTC_ok@kakao.com",
        email_verified: true,
      });
      mockIdxGet.mockResolvedValue({exists: false});
      mockTxGet.mockResolvedValue({exists: false});
      // 충돌 0 — auth/user-not-found (default beforeEach 가 이미 설정).
      mockGetUserByEmail.mockReset();
      mockGetUserByEmail.mockRejectedValueOnce(
        Object.assign(new Error("not found"), {
          code: "auth/user-not-found",
        }),
      );

      const wrapped = testEnv.wrap(myFunctions.kakaoCustomToken);
      const result = (await wrapped({
        auth: {uid: "anon-uid-optc"},
        app: {appId: "test"},
        data: {idToken: "FAKE", nonce: "kakao-nonce-test"},
      } as never)) as {customToken: string; uid: string; isNewUser: boolean};

      expect(result.customToken).toBe("MOCK_CUSTOM_TOKEN");
      // 옵션 C 핵심 — developerClaims propagate (strict object match).
      expect(mockCreateCustomToken).toHaveBeenCalledWith("anon-uid-optc", {
        email: "PII_OPTC_ok@kakao.com",
        email_verified: true,
      });

      // PII regression sentinel — logger 어디에도 email 본문 미노출.
      for (const args of infoMock.mock.calls) {
        expect(JSON.stringify(args)).not.toContain("PII_OPTC_ok@kakao.com");
      }
      for (const args of warnMock.mock.calls) {
        expect(JSON.stringify(args)).not.toContain("PII_OPTC_ok@kakao.com");
      }
    },
  );

  it(
    // eslint-disable-next-line max-len -- IN-04 testcase 라벨 verbatim
    "T-12-KAKAO-CT-OPTC-K2 (IN-04): email claim 만 있고 email_verified 부재 → email_verified=false 보수 매핑",
    async () => {
      // 일반 앱 / 미동의 / 미래 Kakao 정책 변경 시: ID Token 에 email 은
      // 있지만 email_verified claim 미발급 케이스. starter-kit 은 unverified
      // 가능성을 가정하고 보수적으로 false 매핑 — Firebase Auth 의 verified
      // email 로 잘못 propagate 되는 회귀 차단.
      mockVerifyKakaoIdToken.mockResolvedValue({
        sub: "kakao-user-no-verify-claim",
        nonce: "kakao-nonce-test",
        email: "PII_OPTC_unverified@kakao.com",
        // email_verified intentionally omitted
      });
      mockIdxGet.mockResolvedValue({exists: false});
      mockTxGet.mockResolvedValue({exists: false});
      mockGetUserByEmail.mockReset();
      mockGetUserByEmail.mockRejectedValueOnce(
        Object.assign(new Error("not found"), {
          code: "auth/user-not-found",
        }),
      );

      const wrapped = testEnv.wrap(myFunctions.kakaoCustomToken);
      await wrapped({
        auth: {uid: "anon-uid-optc-k2"},
        app: {appId: "test"},
        data: {idToken: "FAKE", nonce: "kakao-nonce-test"},
      } as never);

      // 핵심 회귀 가드 — email_verified=false 보수 매핑.
      expect(mockCreateCustomToken).toHaveBeenCalledWith("anon-uid-optc-k2", {
        email: "PII_OPTC_unverified@kakao.com",
        email_verified: false,
      });
    },
  );

  // Phase 16 D-13/D-14 (Plan 16-03 Task 3.2) — termsAcceptanceSnapshot arg
  // add-only. snapshot=undefined 시 기존 11 case 회귀 0 보장 (C1) + snapshot
  // present 시 5 필드 atomic mirror (C2). Phase 14.1 A6 termsAccepted flip
  // bug root cause fix 의 Custom Token side.
  it(
    // eslint-disable-next-line max-len
    "C1: termsAcceptanceSnapshot=undefined → 기존 behavior 보존 (users/{uid} 직접 set 호출 0)",
    async () => {
      mockVerifyKakaoIdToken.mockResolvedValue({
        sub: "kakao-C1",
        nonce: "n",
      });
      mockIdxGet.mockResolvedValue({exists: false});
      mockTxGet.mockResolvedValue({exists: false});
      mockUserDocSet.mockClear();

      const wrapped = testEnv.wrap(myFunctions.kakaoCustomToken);
      const result = (await wrapped({
        auth: {uid: "anon-C1"},
        app: {appId: "test"},
        data: {idToken: "FAKE", nonce: "n"},
        // termsAcceptanceSnapshot 미전달 — 기존 11 case 회귀 보존.
      } as never)) as {customToken: string; uid: string; isNewUser: boolean};

      expect(result.customToken).toBe("MOCK_CUSTOM_TOKEN");
      expect(result.uid).toBe("anon-C1");
      // 핵심 — users/{uid} 직접 set 호출 0 (transaction 내부 tx.set 만).
      expect(mockUserDocSet).not.toHaveBeenCalled();
    },
  );

  it(
    // eslint-disable-next-line max-len
    "C2: termsAcceptanceSnapshot present → users/{uid}.termsAccepted 5 필드 atomic mirror (merge:true)",
    async () => {
      mockVerifyKakaoIdToken.mockResolvedValue({
        sub: "kakao-C2",
        nonce: "n",
      });
      mockIdxGet.mockResolvedValue({exists: false});
      mockTxGet.mockResolvedValue({exists: false});
      mockUserDocSet.mockClear();

      const snapshot = {
        version: 1,
        service: true,
        privacy: true,
        marketing: false,
        acceptedAt: "2026-05-29T12:00:00.000Z",
      };

      const wrapped = testEnv.wrap(myFunctions.kakaoCustomToken);
      const result = (await wrapped({
        auth: {uid: "anon-C2"},
        app: {appId: "test"},
        data: {
          idToken: "FAKE",
          nonce: "n",
          termsAcceptanceSnapshot: snapshot,
        },
      } as never)) as {customToken: string; uid: string; isNewUser: boolean};

      expect(result.uid).toBe("anon-C2");
      // 핵심 — users/{uid}.set 1회 호출 (Custom Token issue 이후).
      expect(mockUserDocSet).toHaveBeenCalledTimes(1);
      const [payload, options] = mockUserDocSet.mock.calls[0] as [
        {termsAccepted: Record<string, unknown>},
        {merge: boolean},
      ];
      // 5 필드 verbatim mirror (Pitfall 4 schema sentinel).
      expect(payload.termsAccepted.version).toBe(1);
      expect(typeof payload.termsAccepted.version).toBe("number");
      expect(payload.termsAccepted.service).toBe(true);
      expect(payload.termsAccepted.privacy).toBe(true);
      expect(payload.termsAccepted.marketing).toBe(false);
      // acceptedAt 은 Timestamp.fromDate(new Date(ISO)) — mock 가 _kind sentinel.
      const acceptedAt = payload.termsAccepted.acceptedAt as {
        _kind: string;
        iso: string;
      };
      expect(acceptedAt._kind).toBe("MOCK_TIMESTAMP");
      expect(acceptedAt.iso).toBe("2026-05-29T12:00:00.000Z");
      // merge:true 의무 (기존 users/{uid} 필드 보존).
      expect(options).toEqual({merge: true});
      // info log — terms_mirrored sentinel (version 만 노출, 본체 미노출).
      const termsMirrorInfoCalls = infoMock.mock.calls.filter((args) => {
        const ev = (args[0] as {terms_mirrored?: boolean})?.terms_mirrored;
        return ev === true;
      });
      expect(termsMirrorInfoCalls.length).toBeGreaterThanOrEqual(1);
    },
  );
});
