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
// / updateUser (R9: emailVerified retroactive — anonymous→소셜 path) /
// getUserByEmail (Phase 9.2 Gap B — callerUid 분기 email collision detect).
const mockCreateCustomToken = jest.fn().mockResolvedValue("MOCK_NAVER_TOKEN");
const mockCreateUser = jest.fn().mockResolvedValue({uid: "new-uid-naver"});
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
    // Phase 9.2 Gap B default — auth/user-not-found (lookup 시 충돌 없음).
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
      // Phase 9.2 Gap B 옵션 C — email 부재 시 두 번째 인자 undefined.
      expect(mockCreateCustomToken).toHaveBeenCalledWith(
        "anon-uid-1",
        undefined,
      );
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
        // WR-06 회귀 가드: resultcode='00' fingerprint 도 함께 기록
        // 되는지 검증 (Naver API 가 success code 반환했는데 id 누락
        // 케이스를 ops triage 에서 분간 가능해야 한다).
        expect.objectContaining({
          event: "naver_response_id_missing",
          resultcode: "00",
        }),
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
      // Phase 9.2 Gap B 옵션 C — email 부재 시 두 번째 인자 undefined.
      expect(mockCreateCustomToken).toHaveBeenCalledWith(
        "existing-uid-9",
        undefined,
      );
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
      // 16-13: details.existingProvider 전달 검증. 본 case 는 createUser path
      // (getUserByEmail default = auth/user-not-found) 라 provider 추론 실패
      // → 'unknown' fallback (R2 일반 배너로 graceful).
      await expect(promise).rejects.toMatchObject({
        details: {existingProvider: "unknown"},
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
      // 16-13: throw 된 HttpsError 의 details 직렬화에 email/platform-uid 본문
      // 미포함 (slug-only invariant, T-16-13-01).
      const thrownDetails = await promise.catch(
        (e: HttpsError) => e.details,
      );
      const detailsStr = JSON.stringify(thrownDetails);
      expect(detailsStr).not.toContain("collision@example.com");
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
      // 16-13: anonymous collision 의 details.existingProvider = 호출 endpoint
      // provider slug 자체 (doc ID = provider:sub → 호출 provider).
      await expect(promise).rejects.toMatchObject({
        details: {existingProvider: "naver"},
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

  // CR-01 (Phase 13 review): createCustomToken throw → internal + errorUnknown
  // 매핑 회귀 가드. err.message 본문은 logger 에 미노출 (PII 금지 D-51).
  it(
    // eslint-disable-next-line max-len
    "T-13-NAVER-CT-16: createCustomToken throw → internal + errorUnknown + err.message 미노출",
    async () => {
      mockFetchOk({
        resultcode: "00",
        response: {id: "naver-ok-token-fail"},
      });
      mockIdxGet.mockResolvedValue({exists: false});
      mockTxGet.mockResolvedValue({exists: false});
      // admin SDK throw 시뮬레이션 — err.message 에 PII sentinel 삽입.
      const sdkErr = Object.assign(
        new Error("PII_SENTINEL_TOKEN_FAIL_MSG"),
        {name: "FirebaseAuthError"},
      );
      mockCreateCustomToken.mockRejectedValueOnce(sdkErr);

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
        expect.objectContaining({
          event: "naver_custom_token_create_failed",
          code: "FirebaseAuthError",
        }),
        expect.any(String),
      );
      // PII 회귀 — err.message 본문 logger 미노출.
      const allLogCalls = [
        ...infoMock.mock.calls,
        ...warnMock.mock.calls,
        ...errorMock.mock.calls,
      ];
      for (const args of allLogCalls) {
        expect(JSON.stringify(args)).not.toContain(
          "PII_SENTINEL_TOKEN_FAIL_MSG",
        );
      }
    },
  );

  // Phase 9.2 Gap B (HUMAN-UAT 2026-05-11) — Naver Custom Token 익명승격 path
  // 의 email collision detect integration. resolveIdentity 의 신규 callerUid
  // 분기 + admin.auth().getUserByEmail() lookup 으로 다른 provider 가입자 detect
  // → switch case 'email_in_use' → 'already-exists' HttpsError throw.
  it(
    // eslint-disable-next-line max-len
    "T-13-NAVER-CT-COLLISION-A1: 익명승격 + Naver email + Facebook 가입자 detect → already-exists + createCustomToken 미호출",
    async () => {
      mockFetchOk({
        resultcode: "00",
        response: {
          id: "naver-user-collision",
          email: "PII_COLLISION_email@naver.com",
        },
      });
      mockIdxGet.mockResolvedValue({exists: false});
      // Gap B 핵심 — admin.auth().getUserByEmail 가 Facebook 가입자 반환.
      mockGetUserByEmail.mockReset();
      mockGetUserByEmail.mockResolvedValueOnce({
        uid: "fb-uid-existing",
        providerData: [
          {providerId: "facebook.com", uid: "fb-platform-id-PII"},
        ],
      });

      const wrapped = testEnv.wrap(myFunctions.naverCustomToken);
      const promise = wrapped({
        auth: {uid: "anon-uid-test"}, // 익명승격 시나리오.
        app: {appId: "test"},
        data: {accessToken: "naver-token-test"},
      } as never);
      await expect(promise).rejects.toBeInstanceOf(HttpsError);
      await expect(promise).rejects.toMatchObject({
        code: "already-exists",
        message: "errorAccountExistsWithDifferentCredential",
      });
      // 16-13: caller path (getUserByEmail providerData facebook) → details.
      // existingProvider = 'facebook' (mapProviderDataToProviderId 매핑).
      await expect(promise).rejects.toMatchObject({
        details: {existingProvider: "facebook"},
      });

      // caller switch 분기 logger event 발동 검증.
      expect(warnMock).toHaveBeenCalledWith(
        expect.objectContaining({event: "naver_email_collision"}),
        expect.any(String),
      );
      // 옵션 C 의 미도달 invariant — early throw → createCustomToken 미발급.
      expect(mockCreateCustomToken).not.toHaveBeenCalled();

      // PII regression sentinel — email / IdP user_id 본문 logger 미노출.
      const allLogCalls = [
        ...infoMock.mock.calls,
        ...warnMock.mock.calls,
        ...errorMock.mock.calls,
      ];
      for (const args of allLogCalls) {
        const stringified = JSON.stringify(args);
        expect(stringified).not.toContain("PII_COLLISION_email@naver.com");
        expect(stringified).not.toContain("fb-platform-id-PII");
      }
      // 16-13: throw details 직렬화에 email/platform-uid 본문 미포함
      // (slug-only invariant). 'facebook' slug 만 노출.
      const thrownDetails = await promise.catch((e: HttpsError) => e.details);
      const detailsStr = JSON.stringify(thrownDetails);
      expect(detailsStr).not.toContain("PII_COLLISION_email@naver.com");
      expect(detailsStr).not.toContain("fb-platform-id-PII");
    },
  );

  // Plan 16-17 (A4 finding 2026-06-11) — CT↔CT collision. 기존 계정이 Kakao
  // Custom Token 으로 생성되어 providerData 가 비어 있어도 identity_index
  // 역조회로 'kakao' slug 가 산출되어 details 로 전달된다.
  it(
    // eslint-disable-next-line max-len
    "T-16-17-NAVER-CT-EXISTING-01 (A4): Kakao Custom Token 기존 계정 → details.existingProvider='kakao'",
    async () => {
      mockFetchOk({
        resultcode: "00",
        response: {
          id: "naver-user-ct-collision",
          email: "PII_CT_COLLISION_email@naver.com",
        },
      });
      mockIdxGet.mockResolvedValue({exists: false});
      // Custom Token 계정 — providerData 비어 있음 (라이브 관측 사실).
      mockGetUserByEmail.mockReset();
      mockGetUserByEmail.mockResolvedValueOnce({
        uid: "PII_KAKAO_UID_EXISTING",
        providerData: [],
      });
      // identity_index 역조회 → kakao 1건.
      mockIdxWhereGet.mockResolvedValueOnce({
        docs: [{data: () => ({provider: "kakao"})}],
      });

      const wrapped = testEnv.wrap(myFunctions.naverCustomToken);
      const promise = wrapped({
        auth: {uid: "anon-uid-ct"},
        app: {appId: "test"},
        data: {accessToken: "naver-token-ct"},
      } as never);
      await expect(promise).rejects.toBeInstanceOf(HttpsError);
      await expect(promise).rejects.toMatchObject({
        code: "already-exists",
        message: "errorAccountExistsWithDifferentCredential",
      });
      await expect(promise).rejects.toMatchObject({
        details: {existingProvider: "kakao"},
      });
      // 단일 필드 equality 역조회 (자동 인덱스 충족).
      expect(mockIdxWhere).toHaveBeenCalledWith(
        "firebaseUid",
        "==",
        "PII_KAKAO_UID_EXISTING",
      );
      // early throw invariant — Custom Token 미발급.
      expect(mockCreateCustomToken).not.toHaveBeenCalled();

      // PII regression sentinel — email / 기존 uid 본문 미노출.
      const allLogCalls = [
        ...infoMock.mock.calls,
        ...warnMock.mock.calls,
        ...errorMock.mock.calls,
      ];
      for (const args of allLogCalls) {
        const stringified = JSON.stringify(args);
        expect(stringified).not.toContain("PII_CT_COLLISION_email@naver.com");
        expect(stringified).not.toContain("PII_KAKAO_UID_EXISTING");
      }
      const thrownDetails2 = await promise.catch(
        (e: HttpsError) => e.details,
      );
      const detailsStr2 = JSON.stringify(thrownDetails2);
      expect(detailsStr2).not.toContain("PII_CT_COLLISION_email@naver.com");
      expect(detailsStr2).not.toContain("PII_KAKAO_UID_EXISTING");
    },
  );

  // Plan 16-17 — 매트릭스 보강. Naver caller ↔ Yahoo!JP 기존 계정.
  it(
    // eslint-disable-next-line max-len
    "T-16-17-NAVER-CT-EXISTING-02: Yahoo!JP Custom Token 기존 계정 → details.existingProvider='yahoojp'",
    async () => {
      mockFetchOk({
        resultcode: "00",
        response: {
          id: "naver-user-ct-yj",
          email: "PII_CT_YJ_email@naver.com",
        },
      });
      mockIdxGet.mockResolvedValue({exists: false});
      mockGetUserByEmail.mockReset();
      mockGetUserByEmail.mockResolvedValueOnce({
        uid: "PII_YJ_UID_EXISTING",
        providerData: [],
      });
      mockIdxWhereGet.mockResolvedValueOnce({
        docs: [{data: () => ({provider: "yahoojp"})}],
      });

      const wrapped = testEnv.wrap(myFunctions.naverCustomToken);
      const promise = wrapped({
        auth: {uid: "anon-uid-ct-yj"},
        app: {appId: "test"},
        data: {accessToken: "naver-token-ct-yj"},
      } as never);
      await expect(promise).rejects.toMatchObject({
        code: "already-exists",
        message: "errorAccountExistsWithDifferentCredential",
        details: {existingProvider: "yahoojp"},
      });
      expect(mockCreateCustomToken).not.toHaveBeenCalled();

      const allLogCalls = [
        ...infoMock.mock.calls,
        ...warnMock.mock.calls,
        ...errorMock.mock.calls,
      ];
      for (const args of allLogCalls) {
        const stringified = JSON.stringify(args);
        expect(stringified).not.toContain("PII_CT_YJ_email@naver.com");
        expect(stringified).not.toContain("PII_YJ_UID_EXISTING");
      }
    },
  );

  it(
    // eslint-disable-next-line max-len
    "T-13-NAVER-CT-COLLISION-A2: 익명승격 + Naver email 부재 → getUserByEmail 미호출 + 정상 customToken + developerClaims undefined",
    async () => {
      // 동의 비활성 — response.email 부재. lookup skip + 정상 customToken 발급.
      mockFetchOk({
        resultcode: "00",
        response: {id: "naver-user-no-email"},
      });
      mockIdxGet.mockResolvedValue({exists: false});
      mockTxGet.mockResolvedValue({exists: false});

      const wrapped = testEnv.wrap(myFunctions.naverCustomToken);
      const result = (await wrapped({
        auth: {uid: "anon-uid-test"},
        app: {appId: "test"},
        data: {accessToken: "T"},
      } as never)) as {customToken: string; uid: string; isNewUser: boolean};

      // 핵심 — userInfo.email 부재 → getUserByEmail lookup skip.
      expect(mockGetUserByEmail).not.toHaveBeenCalled();
      expect(result.customToken).toBe("MOCK_NAVER_TOKEN");
      // 옵션 C — email 부재 시 developerClaims undefined.
      expect(mockCreateCustomToken).toHaveBeenCalledWith(
        "anon-uid-test",
        undefined,
      );

      // PII regression sentinel.
      const allLogCalls = [
        ...infoMock.mock.calls,
        ...warnMock.mock.calls,
        ...errorMock.mock.calls,
      ];
      for (const args of allLogCalls) {
        expect(JSON.stringify(args)).not.toContain("naver-user-no-email");
      }
    },
  );

  it(
    // eslint-disable-next-line max-len
    "T-13-NAVER-CT-OPTC-N1: 정상 happy-path (충돌 0 + email validated) → createCustomToken developerClaims sentinel",
    async () => {
      // Plan 08 의 Dart-side propagation 단언 부재의 대체 — functions jest
      // sentinel 로 createCustomToken 호출 인자에 developerClaims 포함 검증.
      mockFetchOk({
        resultcode: "00",
        response: {
          id: "naver-user-ok",
          email: "PII_OPTC_ok@naver.com",
        },
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

      const wrapped = testEnv.wrap(myFunctions.naverCustomToken);
      const result = (await wrapped({
        auth: {uid: "anon-uid-optc"},
        app: {appId: "test"},
        data: {accessToken: "T"},
      } as never)) as {customToken: string; uid: string; isNewUser: boolean};

      expect(result.customToken).toBe("MOCK_NAVER_TOKEN");
      // 옵션 C 핵심 — developerClaims propagate (strict object match).
      expect(mockCreateCustomToken).toHaveBeenCalledWith("anon-uid-optc", {
        email: "PII_OPTC_ok@naver.com",
        email_verified: true,
      });

      // PII regression sentinel — logger 어디에도 email 본문 미노출.
      // (developerClaims 자체는 Firebase Auth idToken claim 으로만 propagate.)
      for (const args of infoMock.mock.calls) {
        expect(JSON.stringify(args)).not.toContain("PII_OPTC_ok@naver.com");
      }
      for (const args of warnMock.mock.calls) {
        expect(JSON.stringify(args)).not.toContain("PII_OPTC_ok@naver.com");
      }
    },
  );

  // Phase 16 D-13/D-14 (Plan 16-03 Task 3.2) — termsAcceptanceSnapshot arg
  // add-only. snapshot=undefined 시 기존 11 case 회귀 0 보장 (C1) + snapshot
  // present 시 5 필드 atomic mirror (C2).
  it(
    // eslint-disable-next-line max-len
    "C1: termsAcceptanceSnapshot=undefined → 기존 behavior 보존 (users/{uid} 직접 set 호출 0)",
    async () => {
      mockFetchOk({
        resultcode: "00",
        message: "success",
        response: {id: "naver-C1"},
      });
      mockIdxGet.mockResolvedValue({exists: false});
      mockTxGet.mockResolvedValue({exists: false});
      mockUserDocSet.mockClear();

      const wrapped = testEnv.wrap(myFunctions.naverCustomToken);
      const result = (await wrapped({
        auth: {uid: "anon-naver-C1"},
        app: {appId: "test"},
        data: {accessToken: "FAKE_NAVER_TOKEN_C1"},
      } as never)) as {customToken: string; uid: string; isNewUser: boolean};

      expect(result.customToken).toBe("MOCK_NAVER_TOKEN");
      expect(mockUserDocSet).not.toHaveBeenCalled();
    },
  );

  it(
    // eslint-disable-next-line max-len
    "C2: termsAcceptanceSnapshot present → users/{uid}.termsAccepted 5 필드 atomic mirror (merge:true)",
    async () => {
      mockFetchOk({
        resultcode: "00",
        message: "success",
        response: {id: "naver-C2"},
      });
      mockIdxGet.mockResolvedValue({exists: false});
      mockTxGet.mockResolvedValue({exists: false});
      mockUserDocSet.mockClear();

      const snapshot = {
        version: 2,
        service: true,
        privacy: true,
        marketing: true,
        acceptedAt: "2026-05-29T13:00:00.000Z",
      };

      const wrapped = testEnv.wrap(myFunctions.naverCustomToken);
      await wrapped({
        auth: {uid: "anon-naver-C2"},
        app: {appId: "test"},
        data: {
          accessToken: "FAKE_NAVER_TOKEN_C2",
          termsAcceptanceSnapshot: snapshot,
        },
      } as never);

      expect(mockUserDocSet).toHaveBeenCalledTimes(1);
      const [payload, options] = mockUserDocSet.mock.calls[0] as [
        {termsAccepted: Record<string, unknown>},
        {merge: boolean},
      ];
      expect(payload.termsAccepted.version).toBe(2);
      expect(typeof payload.termsAccepted.version).toBe("number");
      expect(payload.termsAccepted.service).toBe(true);
      expect(payload.termsAccepted.privacy).toBe(true);
      expect(payload.termsAccepted.marketing).toBe(true);
      const acceptedAt = payload.termsAccepted.acceptedAt as {
        _kind: string;
        iso: string;
      };
      expect(acceptedAt._kind).toBe("MOCK_TIMESTAMP");
      expect(acceptedAt.iso).toBe("2026-05-29T13:00:00.000Z");
      expect(options).toEqual({merge: true});
      // info log — terms_mirrored sentinel.
      const termsMirrorInfoCalls = infoMock.mock.calls.filter((args) => {
        const ev = (args[0] as {terms_mirrored?: boolean})?.terms_mirrored;
        return ev === true;
      });
      expect(termsMirrorInfoCalls.length).toBeGreaterThanOrEqual(1);
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
      mockFetchOk({
        resultcode: "00",
        message: "success",
        response: {id: "naver-C3"},
      });
      // 기존 identity_index 매핑 존재 + 미인증 호출 → conflictKind null,
      // isNewUser=false (재로그인).
      mockIdxGet.mockResolvedValue({exists: true});
      mockTxGet.mockResolvedValue({
        exists: true,
        data: () => ({firebaseUid: "existing-uid-C3"}),
      });
      mockUserDocSet.mockClear();

      const wrapped = testEnv.wrap(myFunctions.naverCustomToken);
      const result = (await wrapped({
        app: {appId: "test"},
        data: {
          accessToken: "FAKE_NAVER_TOKEN_C3",
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
