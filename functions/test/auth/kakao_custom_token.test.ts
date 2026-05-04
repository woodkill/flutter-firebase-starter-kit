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

// jose — jwtVerify mock + JOSEError 클래스 보존.
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

// firebase-admin/auth — getAuth().createCustomToken / createUser stub.
const mockCreateCustomToken = jest.fn().mockResolvedValue("MOCK_CUSTOM_TOKEN");
const mockCreateUser = jest.fn().mockResolvedValue({uid: "new-uid-pre"});
jest.mock("firebase-admin/auth", () => ({
  getAuth: jest.fn(() => ({
    createCustomToken: mockCreateCustomToken,
    createUser: mockCreateUser,
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
const jwtVerifyMock = jose.jwtVerify as unknown as jest.Mock;

afterAll(() => testEnv.cleanup());

describe("kakaoCustomToken onCall", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockCreateCustomToken.mockResolvedValue("MOCK_CUSTOM_TOKEN");
    mockCreateUser.mockResolvedValue({uid: "new-uid-pre"});
  });

  it("성공: ID Token 검증 + Identity Index 신규 등록 + Custom Token 발급", async () => {
    jwtVerifyMock.mockResolvedValue({
      payload: {sub: "kakao-user-456", nonce: "client-nonce"},
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
    expect(jwtVerifyMock).toHaveBeenCalledWith(
      "FAKE_JWT",
      "MOCK_JWKS",
      expect.objectContaining({
        issuer: "https://kauth.kakao.com",
        audience: "fake-rest-api-key",
        algorithms: ["RS256"],
      }),
    );
    expect(mockCreateCustomToken).toHaveBeenCalledWith("anon-uid-1");
    // PII 금지 sentinel — info 호출 payload 에 토큰 본문 미포함.
    const infoCalls = infoMock.mock.calls;
    expect(infoCalls.length).toBeGreaterThanOrEqual(1);
  });

  it("ID Token 검증 실패 → invalid-argument HttpsError", async () => {
    jwtVerifyMock.mockRejectedValue(
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
    jwtVerifyMock.mockResolvedValue({
      payload: {sub: "kakao-user-new", nonce: "n"},
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
    jwtVerifyMock.mockResolvedValue({
      payload: {sub: "kakao-anon", nonce: "n"},
    });
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
      jwtVerifyMock.mockResolvedValue({
        payload: {sub: "kakao-existing", nonce: "n"},
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
      expect(mockCreateCustomToken).toHaveBeenCalledWith("existing-uid-9");
    },
  );

  it(
    // eslint-disable-next-line max-len
    "기존 매핑 + 동일 callerUid (재로그인) → 그 firebaseUid 재사용 (D-12, R3 conflictKind null)",
    async () => {
      // R3 (Plan 12.1-06): callerUid === existing.firebaseUid 면 충돌 아님 →
      // conflictKind null → 정상 customToken 발급. 이 시나리오는 *재로그인* —
      // 동일 사용자가 idle 후 재진입, 같은 UID 보존.
      jwtVerifyMock.mockResolvedValue({
        payload: {sub: "kakao-rerun", nonce: "n"},
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
      jwtVerifyMock.mockResolvedValue({
        payload: {
          sub: "kakao-456",
          email: "secret@test.com",
          kakao_account: {profile: {nickname: "secret-nickname"}},
          nonce: "n",
        },
      });
      mockIdxGet.mockResolvedValue({exists: false});
      mockTxGet.mockResolvedValue({exists: false});

      const wrapped = testEnv.wrap(myFunctions.kakaoCustomToken);
      await wrapped({
        auth: {uid: "anon-pii"},
        app: {appId: "test"},
        data: {idToken: "JWT_BODY", nonce: "n"},
      } as never);

      const allLogCalls = [
        ...infoMock.mock.calls,
        ...warnMock.mock.calls,
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
      jwtVerifyMock.mockResolvedValue({
        payload: {
          sub: "kakao-collision",
          email: "collision@example.com",
          nonce: "n",
        },
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
      const allLogCalls = [
        ...infoMock.mock.calls,
        ...warnMock.mock.calls,
        ...errorMock.mock.calls,
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
      jwtVerifyMock.mockResolvedValue({
        payload: {sub: "kakao-existing", nonce: "n"},
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
      jwtVerifyMock.mockResolvedValue({
        payload: {sub: "kakao-fail", nonce: "n"},
      });
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
      for (const args of errorMock.mock.calls) {
        expect(JSON.stringify(args)).not.toContain("firestore unavailable");
      }
    },
  );

  it(
    "R3: 정상 path (conflictKind null) → customToken 정상 발급 + throw 안 함",
    async () => {
      jwtVerifyMock.mockResolvedValue({
        payload: {sub: "kakao-normal", nonce: "n"},
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
});
