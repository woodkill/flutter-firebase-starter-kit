/**
 * Phase 13 — see ROADMAP.md
 *
 * naverCustomToken onCall 회귀 테스트 (Phase 13 Task 2).
 *
 * Phase 12 `kakao_custom_token.test.ts` 의 14 케이스 패턴을 verbatim 미러,
 * jose JWT 검증 단락만 Node 20 fetch + AbortController + REST 검증 단락으로
 * 치환. 13~15 케이스 (T-13-NAVER-CT-{n}) + D-54 PII regression sentinel.
 *
 * 모든 jest.mock 호출은 hoist 되므로 src import 보다 먼저 정의되어야 한다
 * (firebase-functions-test 공식 권장 패턴 — kakao_custom_token.test.ts 와
 * 동일).
 */

// fetch mock — Phase 12 의 jose mock 위치에 fetch mock (D-46/D-48).
const fetchMock = jest.fn();
global.fetch = fetchMock as unknown as typeof fetch;

// firebase-functions/logger mock — read-only export 라 jest.spyOn 미동작.
jest.mock("firebase-functions/logger", () => ({
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
  debug: jest.fn(),
  log: jest.fn(),
}));

// secret 주입 — 배포 환경 의존 제거 (NAVER_CLIENT_SECRET 사용처 0건이지만
// defineSecret() 평가 시점 stub 필요).
jest.mock("firebase-functions/params", () => ({
  defineSecret: () => ({value: () => "fake-naver-secret"}),
}));

// firebase-admin/auth — getAuth().createCustomToken / createUser / deleteUser
// / updateUser (R9: emailVerified retroactive — anonymous→소셜 path).
const mockCreateCustomToken = jest.fn().mockResolvedValue("MOCK_NAVER_TOKEN");
const mockCreateUser = jest.fn().mockResolvedValue({uid: "new-uid-naver"});
const mockDeleteUser = jest.fn().mockResolvedValue(undefined);
const mockUpdateUser = jest.fn().mockResolvedValue(undefined);
jest.mock("firebase-admin/auth", () => ({
  getAuth: jest.fn(() => ({
    createCustomToken: mockCreateCustomToken,
    createUser: mockCreateUser,
    deleteUser: mockDeleteUser,
    updateUser: mockUpdateUser,
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

const testEnv = functionsTest();

// eslint-disable-next-line import/first
import * as myFunctions from "../../src/index";

const infoMock = logger.info as unknown as jest.Mock;
const warnMock = logger.warn as unknown as jest.Mock;
const errorMock = logger.error as unknown as jest.Mock;

afterAll(() => testEnv.cleanup());

/**
 * fetch mock — 정상 200 응답.
 *
 * @param {object} body Naver `/v1/nid/me` 응답 본문 stub.
 */
function mockFetchOk(body: object) {
  fetchMock.mockResolvedValueOnce({
    ok: true,
    status: 200,
    json: async () => body,
  });
}

/**
 * fetch mock — 임의 status (4xx/5xx).
 *
 * @param {number} status HTTP status 코드.
 * @param {object} body 응답 본문 (default 빈 객체).
 */
function mockFetchStatus(status: number, body: object = {}) {
  fetchMock.mockResolvedValueOnce({
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  });
}

/** fetch mock — AbortError (5s timeout). */
function mockFetchAbort() {
  const err = new Error("aborted");
  (err as Error & {name: string}).name = "AbortError";
  fetchMock.mockRejectedValueOnce(err);
}

describe("naverCustomToken onCall (T-13-NAVER-CT)", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    fetchMock.mockReset();
    mockCreateCustomToken.mockResolvedValue("MOCK_NAVER_TOKEN");
    mockCreateUser.mockResolvedValue({uid: "new-uid-naver"});
    mockDeleteUser.mockResolvedValue(undefined);
  });

  it(
    "T-13-NAVER-CT-01: 정상 path → identity_index 신규 등록 + Custom Token 발급",
    async () => {
      mockFetchOk({
        resultcode: "00",
        message: "success",
        response: {id: "naver-user-456"},
      });
      mockIdxGet.mockResolvedValue({exists: false});
      mockTxGet.mockResolvedValue({exists: false});

      const wrapped = testEnv.wrap(myFunctions.naverCustomToken);
      const result = (await wrapped({
        auth: {uid: "anon-uid-1"},
        app: {appId: "test"},
        data: {accessToken: "FAKE_NAVER_TOKEN"},
      } as never)) as {
        customToken: string;
        uid: string;
        isNewUser: boolean;
      };

      expect(result.customToken).toBe("MOCK_NAVER_TOKEN");
      expect(result.uid).toBe("anon-uid-1");
      expect(result.isNewUser).toBe(true);
      expect(fetchMock).toHaveBeenCalledWith(
        "https://openapi.naver.com/v1/nid/me",
        expect.objectContaining({
          method: "GET",
          headers: expect.objectContaining({
            Authorization: "Bearer FAKE_NAVER_TOKEN",
          }),
          signal: expect.anything(),
        }),
      );
      expect(mockCreateCustomToken).toHaveBeenCalledWith("anon-uid-1");
      expect(infoMock).toHaveBeenCalledWith(
        expect.objectContaining({event: "naver_custom_token_issued"}),
        expect.any(String),
      );
    },
  );

  it(
    "T-13-NAVER-CT-02: HTTP 401 → unauthenticated + errorInvalidCredentials",
    async () => {
      mockFetchStatus(401);
      const wrapped = testEnv.wrap(myFunctions.naverCustomToken);
      await expect(
        wrapped({app: {appId: "test"}, data: {accessToken: "BAD"}} as never),
      ).rejects.toMatchObject({
        code: "unauthenticated",
        message: "errorInvalidCredentials",
      });
      expect(warnMock).toHaveBeenCalledWith(
        expect.objectContaining({
          event: "naver_verify_unauthenticated",
          status: 401,
        }),
        expect.any(String),
      );
    },
  );

  it(
    "T-13-NAVER-CT-03: HTTP 503 → unavailable + errorServiceUnavailable",
    async () => {
      mockFetchStatus(503);
      const wrapped = testEnv.wrap(myFunctions.naverCustomToken);
      await expect(
        wrapped({app: {appId: "test"}, data: {accessToken: "T"}} as never),
      ).rejects.toMatchObject({
        code: "unavailable",
        message: "errorServiceUnavailable",
      });
      expect(warnMock).toHaveBeenCalledWith(
        expect.objectContaining({
          event: "naver_verify_unavailable",
          status: 503,
        }),
        expect.any(String),
      );
    },
  );

  it(
    "T-13-NAVER-CT-04: AbortError (timeout) → unavailable + warn fingerprint",
    async () => {
      mockFetchAbort();
      const wrapped = testEnv.wrap(myFunctions.naverCustomToken);
      await expect(
        wrapped({app: {appId: "test"}, data: {accessToken: "T"}} as never),
      ).rejects.toMatchObject({
        code: "unavailable",
        message: "errorServiceUnavailable",
      });
      expect(warnMock).toHaveBeenCalledWith(
        expect.objectContaining({
          event: "naver_fetch_failed",
          code: "AbortError",
        }),
        expect.any(String),
      );
    },
  );

  it(
    "T-13-NAVER-CT-05: resultcode != '00' → unauthenticated",
    async () => {
      mockFetchOk({
        resultcode: "024",
        message: "Authentication failed",
        response: {id: "x"},
      });
      const wrapped = testEnv.wrap(myFunctions.naverCustomToken);
      await expect(
        wrapped({app: {appId: "test"}, data: {accessToken: "T"}} as never),
      ).rejects.toMatchObject({
        code: "unauthenticated",
        message: "errorInvalidCredentials",
      });
      expect(warnMock).toHaveBeenCalledWith(
        expect.objectContaining({
          event: "naver_resultcode_non_success",
          resultcode: "024",
        }),
        expect.any(String),
      );
    },
  );

  it(
    "T-13-NAVER-CT-06: response.id 부재 → invalid-argument",
    async () => {
      mockFetchOk({
        resultcode: "00",
        message: "success",
        response: {},
      });
      const wrapped = testEnv.wrap(myFunctions.naverCustomToken);
      await expect(
        wrapped({app: {appId: "test"}, data: {accessToken: "T"}} as never),
      ).rejects.toMatchObject({
        code: "invalid-argument",
        message: "errorInvalidCredentials",
      });
      expect(errorMock).toHaveBeenCalledWith(
        expect.objectContaining({event: "naver_response_id_missing"}),
        expect.any(String),
      );
    },
  );

  it(
    "T-13-NAVER-CT-07: 익명 호출자 + 미등록 → seed UID = request.auth.uid",
    async () => {
      mockFetchOk({
        resultcode: "00",
        response: {id: "naver-anon-seed"},
      });
      mockIdxGet.mockResolvedValue({exists: false});
      mockTxGet.mockResolvedValue({exists: false});

      const wrapped = testEnv.wrap(myFunctions.naverCustomToken);
      const result = (await wrapped({
        auth: {uid: "anon-seed-uid"},
        app: {appId: "test"},
        data: {accessToken: "T"},
      } as never)) as {
        customToken: string;
        uid: string;
        isNewUser: boolean;
      };

      expect(result.uid).toBe("anon-seed-uid");
      expect(result.isNewUser).toBe(true);
      // callerUid 가 있으면 createUser 미호출 (Pitfall 4 회피).
      expect(mockCreateUser).not.toHaveBeenCalled();
    },
  );

  it(
    "T-13-NAVER-CT-08: 미인증 호출자 + 미등록 → preCreatedUid 자동 생성",
    async () => {
      mockFetchOk({
        resultcode: "00",
        response: {id: "naver-user-new"},
      });
      mockIdxGet.mockResolvedValue({exists: false});
      mockTxGet.mockResolvedValue({exists: false});

      const wrapped = testEnv.wrap(myFunctions.naverCustomToken);
      const result = (await wrapped({
        // auth 없음 — 미인증.
        app: {appId: "test"},
        data: {accessToken: "T"},
      } as never)) as {
        customToken: string;
        uid: string;
        isNewUser: boolean;
      };

      expect(result.uid).toBe("new-uid-naver");
      expect(result.isNewUser).toBe(true);
      expect(mockCreateUser).toHaveBeenCalledTimes(1);
    },
  );

  it(
    "T-13-NAVER-CT-09: identity_index 기존 매핑 → 그 firebaseUid 재사용",
    async () => {
      mockFetchOk({
        resultcode: "00",
        response: {id: "naver-existing"},
      });
      mockIdxGet.mockResolvedValue({exists: true});
      mockTxGet.mockResolvedValue({
        exists: true,
        data: () => ({firebaseUid: "existing-uid-9"}),
      });

      const wrapped = testEnv.wrap(myFunctions.naverCustomToken);
      const result = (await wrapped({
        // 미인증 호출 (재로그인) — conflictKind null 보장.
        app: {appId: "test"},
        data: {accessToken: "T"},
      } as never)) as {
        customToken: string;
        uid: string;
        isNewUser: boolean;
      };

      expect(result.uid).toBe("existing-uid-9");
      expect(result.isNewUser).toBe(false);
      expect(mockCreateCustomToken).toHaveBeenCalledWith("existing-uid-9");
    },
  );

  it(
    // eslint-disable-next-line max-len
    "T-13-NAVER-CT-10: conflictKind 'email_in_use' → already-exists + warn",
    async () => {
      mockFetchOk({
        resultcode: "00",
        response: {
          id: "naver-collision",
          email: "collision@example.com",
        },
      });
      mockIdxGet.mockResolvedValue({exists: false});
      mockCreateUser.mockRejectedValueOnce(
        Object.assign(new Error("email exists"), {
          code: "auth/email-already-in-use",
        }),
      );

      const wrapped = testEnv.wrap(myFunctions.naverCustomToken);
      const promise = wrapped({
        // 미인증 호출 → preCreatedUid 단계 진입 → email collision detect.
        app: {appId: "test"},
        data: {accessToken: "T"},
      } as never);
      await expect(promise).rejects.toBeInstanceOf(HttpsError);
      await expect(promise).rejects.toMatchObject({
        code: "already-exists",
        message: "errorAccountExistsWithDifferentCredential",
      });

      expect(warnMock).toHaveBeenCalledWith(
        expect.objectContaining({event: "naver_email_collision"}),
        expect.any(String),
      );
      // PII 회귀 — collision email 본문 logger 미노출.
      const allLogCalls = [
        ...infoMock.mock.calls,
        ...warnMock.mock.calls,
        ...errorMock.mock.calls,
      ];
      for (const args of allLogCalls) {
        expect(JSON.stringify(args)).not.toContain("collision@example.com");
      }
    },
  );

  it(
    // eslint-disable-next-line max-len
    "T-13-NAVER-CT-11: conflictKind 'anonymous_existing_collision' → already-exists",
    async () => {
      mockFetchOk({
        resultcode: "00",
        response: {id: "naver-existing"},
      });
      // 익명 사용자 'anon-A' 가 *기존* naver identity 'existing-B' 로 로그인.
      mockIdxGet.mockResolvedValue({exists: true});
      mockTxGet.mockResolvedValue({
        exists: true,
        data: () => ({firebaseUid: "existing-B"}),
      });

      const wrapped = testEnv.wrap(myFunctions.naverCustomToken);
      const promise = wrapped({
        auth: {uid: "anon-A"},
        app: {appId: "test"},
        data: {accessToken: "T"},
      } as never);
      await expect(promise).rejects.toBeInstanceOf(HttpsError);
      await expect(promise).rejects.toMatchObject({
        code: "already-exists",
        message: "errorAccountExistsWithDifferentCredential",
      });
      expect(warnMock).toHaveBeenCalledWith(
        expect.objectContaining({event: "naver_anonymous_conflict"}),
        expect.any(String),
      );
    },
  );

  it(
    // eslint-disable-next-line max-len
    "T-13-NAVER-CT-12: resolveIdentity unexpected throw → internal + errorUnknown",
    async () => {
      mockFetchOk({
        resultcode: "00",
        response: {id: "naver-fail"},
      });
      // helper 의 idxRef.get() 이 firestore 오류 throw — caller 가 catch
      // 하여 internal 로 매핑.
      mockIdxGet.mockRejectedValueOnce(new Error("firestore unavailable"));

      const wrapped = testEnv.wrap(myFunctions.naverCustomToken);
      const promise = wrapped({
        app: {appId: "test"},
        data: {accessToken: "T"},
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
      // PII 회귀 — err.message ('firestore unavailable') 미노출.
      for (const args of errorMock.mock.calls) {
        expect(JSON.stringify(args)).not.toContain("firestore unavailable");
      }
    },
  );

  // D-54 PII regression — Naver `/v1/nid/me` response 본문 + accessToken 본문
  // sentinel 검증. resultcode != '00' 분기 진입으로 logger.warn 호출 유도하되,
  // PII sentinel 5종 (email + name + nickname + profile_image + accessToken)
  // 이 모든 logger call 의 JSON.stringify 결과에 부재함을 검증 — catch 메시지에
  // logger 추가 시 test 가 RED.
  it(
    // eslint-disable-next-line max-len
    "T-13-NAVER-CT-13: D-54 PII regression — response 본문 + accessToken sentinel logger 미노출",
    async () => {
      mockFetchOk({
        resultcode: "024",
        message: "AUTH_FAILED",
        response: {
          id: "naver-pii",
          email: "PII_SENTINEL_email@test.com",
          name: "PII_SENTINEL_NAME",
          nickname: "PII_SENTINEL_NICK",
          profile_image: "PII_SENTINEL_IMG_URL",
        },
      });
      const wrapped = testEnv.wrap(myFunctions.naverCustomToken);
      await expect(
        wrapped({
          app: {appId: "test"},
          data: {accessToken: "FAKE_PII_SENTINEL_TOKEN"},
        } as never),
      ).rejects.toBeInstanceOf(HttpsError);

      const allLogCalls = [
        ...infoMock.mock.calls,
        ...warnMock.mock.calls,
        ...errorMock.mock.calls,
      ];
      for (const args of allLogCalls) {
        const stringified = JSON.stringify(args);
        expect(stringified).not.toContain("PII_SENTINEL_email@test.com");
        expect(stringified).not.toContain("PII_SENTINEL_NAME");
        expect(stringified).not.toContain("PII_SENTINEL_NICK");
        expect(stringified).not.toContain("PII_SENTINEL_IMG_URL");
        expect(stringified).not.toContain("FAKE_PII_SENTINEL_TOKEN");
      }
    },
  );

  it(
    // eslint-disable-next-line max-len
    "T-13-NAVER-CT-14: accessToken 빈 문자열 → invalid-argument + errorInvalidArgument",
    async () => {
      const wrapped = testEnv.wrap(myFunctions.naverCustomToken);
      await expect(
        wrapped({app: {appId: "test"}, data: {accessToken: ""}} as never),
      ).rejects.toMatchObject({
        code: "invalid-argument",
        message: "errorInvalidArgument",
      });
      // 단순 분기 가드가 fetch 호출 차단.
      expect(fetchMock).not.toHaveBeenCalled();
    },
  );

  it(
    // eslint-disable-next-line max-len
    "T-13-NAVER-CT-15: HTTP 429 (기타 4xx) → unavailable + naver_verify_failed",
    async () => {
      mockFetchStatus(429);
      const wrapped = testEnv.wrap(myFunctions.naverCustomToken);
      await expect(
        wrapped({app: {appId: "test"}, data: {accessToken: "T"}} as never),
      ).rejects.toMatchObject({
        code: "unavailable",
        message: "errorServiceUnavailable",
      });
      expect(warnMock).toHaveBeenCalledWith(
        expect.objectContaining({
          event: "naver_verify_failed",
          status: 429,
        }),
        expect.any(String),
      );
    },
  );
});
