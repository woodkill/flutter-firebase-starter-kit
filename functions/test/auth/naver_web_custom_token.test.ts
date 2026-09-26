/**
 * Phase 16.5 SOCL-14 — naverWebCustomToken onCall 회귀 테스트 (Plan 16.5-02).
 *
 * 킷 소유 웹 경로의 서버 조각: authorization code → NAVER token 교환 →
 * 공용 helper(`verifyNaverProfileAndIssueCustomToken`) 위임으로 끝
 * (폐기 없음 — quick 260924-lw2, 16.5 D-15 번복).
 * 셋업은 `naver_custom_token.test.ts` 의 mock 패턴(fetch · logger · params ·
 * admin) 을 미러한다. 케이스 마커 T-16.5-NAVER-WEB-CT-01~07 · 09~11
 * (08 · 12 · 13 은 폐기 전용이라 quick 260924-lw2 에서 삭제) +
 * T-QUICK-260924-LW2-* + Phase 16.7 D-21(웹 신규 등록 가입 수단 기록).
 *
 * 모든 jest.mock 호출은 hoist 되므로 src import 보다 먼저 정의되어야 한다
 * (firebase-functions-test 공식 권장 패턴).
 */

// fetch mock — token 교환 · /v1/nid/me 2 호출을 순서대로 stub.
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

// secret 주입 — 이름으로 분기해 client_id / client_secret 을 구분한다.
jest.mock("firebase-functions/params", () => ({
  defineSecret: (name: string) => ({
    value: () =>
      name === "NAVER_CLIENT_ID" ? "fake-naver-client-id" : "fake-naver-secret",
  }),
}));

// firebase-admin/auth — helper 가 쓰는 admin SDK 표면.
const mockCreateCustomToken = jest.fn().mockResolvedValue("MOCK_NAVER_TOKEN");
const mockCreateUser = jest.fn().mockResolvedValue({uid: "new-uid-naver"});
const mockDeleteUser = jest.fn().mockResolvedValue(undefined);
const mockUpdateUser = jest.fn().mockResolvedValue(undefined);
const mockGetUserByEmail = jest.fn().mockRejectedValue(
  Object.assign(new Error("not found"), {code: "auth/user-not-found"}),
);
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
    getUser: mockGetUser,
  })),
}));

// firebase-admin/firestore — 단일 mock transaction (naver_custom_token 미러).
const mockTxGet = jest.fn();
const mockTxSet = jest.fn();
const mockTxUpdate = jest.fn();
const mockIdxGet = jest.fn();
const mockIdxWhere = jest.fn();
const mockIdxWhereGet = jest.fn().mockResolvedValue({docs: []});
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
    Timestamp: {
      fromDate: (d: Date) => ({_kind: "MOCK_TIMESTAMP", iso: d.toISOString()}),
    },
  };
});

// 위 mock 셋업 이후에 testEnv + src import (지연 import).
// eslint-disable-next-line import/first
import functionsTest from "firebase-functions-test";
// eslint-disable-next-line import/first
import * as logger from "firebase-functions/logger";

const testEnv = functionsTest();

// eslint-disable-next-line import/first
import {naverWebCustomToken} from "../../src/auth/naver_web_custom_token";
// eslint-disable-next-line import/first
import {anonymousCallerAuth} from "../mocks/caller_auth";

const infoMock = logger.info as unknown as jest.Mock;
const warnMock = logger.warn as unknown as jest.Mock;
const errorMock = logger.error as unknown as jest.Mock;

afterAll(() => testEnv.cleanup());

const NAVER_TOKEN_URL = "https://nid.naver.com/oauth2.0/token";
const NAVER_PROFILE_URL = "https://openapi.naver.com/v1/nid/me";

const FAKE_CODE = "FAKE_AUTH_CODE_web_0123456789";
const FAKE_STATE_22CHARS = "st4te-FAKE-0123456789a";
const FAKE_ACCESS_TOKEN = "FAKE_ACCESS_TOKEN_web_abcdef";
const FAKE_REFRESH_TOKEN = "FAKE_REFRESH_TOKEN_web_zyxwvu";

const TERMS_SNAPSHOT = {
  version: 1,
  service: true,
  privacy: true,
  marketing: false,
  acceptedAt: "2026-09-23T10:00:00.000Z",
};

type WebResult = {customToken: string; uid: string; isNewUser: boolean};

/**
 * onCall 을 testEnv 로 감싸 호출한다.
 *
 * @param {object} request onCall request 부분 shape (data · auth · app).
 * @return {Promise<unknown>} callable 반환값.
 */
function callWeb(request: object): Promise<unknown> {
  const wrapped = testEnv.wrap(naverWebCustomToken);
  return wrapped({app: {appId: "test"}, ...request} as never);
}

/**
 * fetch mock — 임의 status + JSON 본문 1회.
 *
 * @param {number} status HTTP status 코드.
 * @param {unknown} body `json()` 이 돌려줄 본문.
 */
function mockFetchJson(status: number, body: unknown) {
  fetchMock.mockResolvedValueOnce({
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  });
}

/** fetch mock — token 교환 성공 (access + refresh token 동봉). */
function mockTokenOk() {
  mockFetchJson(200, {
    access_token: FAKE_ACCESS_TOKEN,
    refresh_token: FAKE_REFRESH_TOKEN,
    token_type: "bearer",
    expires_in: "3600",
  });
}

/**
 * fetch mock — `/v1/nid/me` 정상 응답.
 *
 * @param {string} id Naver 사용자 id.
 */
function mockProfileOk(id: string) {
  mockFetchJson(200, {resultcode: "00", message: "success", response: {id}});
}

/**
 * fetch mock — 이름 있는 Error 로 reject.
 *
 * @param {string} name `err.name` 값 (예: TimeoutError — `AbortSignal.timeout`
 *     초과 시 fetch 가 reject 하는 이름).
 */
function mockFetchReject(name: string) {
  const err = new Error("fetch failed");
  err.name = name;
  fetchMock.mockRejectedValueOnce(err);
}

/**
 * n 번째 fetch 호출의 form body 를 파싱한다.
 *
 * @param {number} index `fetchMock.mock.calls` 인덱스.
 * @return {URLSearchParams} 파싱된 form body.
 */
function formBodyOf(index: number): URLSearchParams {
  const init = fetchMock.mock.calls[index][1] as {body?: unknown};
  return new URLSearchParams(String(init.body));
}

/**
 * 지금까지의 fetch 호출 URL 목록 (호출 순서).
 *
 * @return {string[]} `fetchMock.mock.calls` 의 첫 인자 목록.
 */
function fetchUrls(): string[] {
  return fetchMock.mock.calls.map((call) => String(call[0]));
}

/**
 * 호출마다 form body 의 grant_type 을 뽑는다 (body 없는 GET 은 null).
 *
 * @return {(string|null)[]} 호출 순서대로의 grant_type 목록.
 */
function grantTypesSent(): (string | null)[] {
  return fetchMock.mock.calls.map((call) => {
    const init = call[1] as {body?: unknown} | undefined;
    if (init?.body === undefined) {
      return null;
    }
    return new URLSearchParams(String(init.body)).get("grant_type");
  });
}

/**
 * logger info/warn/error 전체 호출 인자를 JSON 문자열 하나로 합친다.
 *
 * @return {string} 모든 logger 호출 인자의 직렬화.
 */
function allLoggerArgsJson(): string {
  return JSON.stringify([
    ...infoMock.mock.calls,
    ...warnMock.mock.calls,
    ...errorMock.mock.calls,
  ]);
}

describe("naverWebCustomToken onCall (T-16.5-NAVER-WEB-CT)", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    fetchMock.mockReset();
    mockCreateCustomToken.mockResolvedValue("MOCK_NAVER_TOKEN");
    mockGetUserByEmail.mockReset();
    mockGetUserByEmail.mockRejectedValue(
      Object.assign(new Error("not found"), {code: "auth/user-not-found"}),
    );
    mockIdxWhere.mockReset();
    mockIdxWhereGet.mockReset();
    mockIdxWhereGet.mockResolvedValue({docs: []});
    mockUserDocSet.mockReset();
    mockUserDocSet.mockResolvedValue(undefined);
  });

  it(
    // eslint-disable-next-line max-len
    "T-16.5-NAVER-WEB-CT-01: 교환 성공 · 신규 사용자 → token → /v1/nid/me (NAVER 2회 · 폐기 없음) · isNewUser=true · terms mirror · expiresInSec",
    async () => {
      mockTokenOk();
      mockProfileOk("naver-web-01");
      mockIdxGet.mockResolvedValue({exists: false});
      mockTxGet.mockResolvedValue({exists: false});

      const result = (await callWeb({
        auth: anonymousCallerAuth("anon-web-01"),
        data: {
          code: FAKE_CODE,
          state: FAKE_STATE_22CHARS,
          termsAcceptanceSnapshot: TERMS_SNAPSHOT,
        },
      })) as WebResult;

      // 응답은 3 필드뿐 — access/refresh token 은 클라이언트로 가지 않는다.
      expect(result).toEqual({
        customToken: "MOCK_NAVER_TOKEN",
        uid: "anon-web-01",
        isNewUser: true,
      });
      expect(fetchMock).toHaveBeenCalledTimes(2);

      // 1) token 교환 — POST · form-urlencoded · 5 키 (redirect_uri 없음).
      const [tokenUrl, tokenInit] = fetchMock.mock.calls[0] as [
        string,
        {method: string; headers: Record<string, string>; signal: unknown},
      ];
      expect(tokenUrl).toBe(NAVER_TOKEN_URL);
      expect(tokenInit.method).toBe("POST");
      expect(tokenInit.headers["Content-Type"]).toBe(
        "application/x-www-form-urlencoded",
      );
      // IN-04 — 수동 AbortController 가 아니라 본문 읽기까지 덮는
      // AbortSignal.timeout 신호를 넘긴다.
      expect(tokenInit.signal).toBeInstanceOf(AbortSignal);
      const tokenForm = formBodyOf(0);
      expect([...tokenForm.keys()].sort()).toEqual(
        ["client_id", "client_secret", "code", "grant_type", "state"],
      );
      expect(tokenForm.get("grant_type")).toBe("authorization_code");
      expect(tokenForm.get("client_id")).toBe("fake-naver-client-id");
      expect(tokenForm.get("client_secret")).toBe("fake-naver-secret");
      expect(tokenForm.get("code")).toBe(FAKE_CODE);
      expect(tokenForm.get("state")).toBe(FAKE_STATE_22CHARS);
      expect(tokenForm.has("redirect_uri")).toBe(false);

      // 2) /v1/nid/me — GET Bearer (helper 위임).
      expect(fetchMock.mock.calls[1][0]).toBe(NAVER_PROFILE_URL);
      expect(fetchMock.mock.calls[1][1]).toEqual(
        expect.objectContaining({
          method: "GET",
          headers: expect.objectContaining({
            Authorization: `Bearer ${FAKE_ACCESS_TOKEN}`,
          }),
        }),
      );

      // OAuth 첫-로그인 — terms mirror 1회.
      expect(mockUserDocSet).toHaveBeenCalledTimes(1);
      expect(infoMock).toHaveBeenCalledWith(
        expect.objectContaining({
          event: "naver_web_custom_token_issued",
          uid: "anon-web-01",
          isNewUser: true,
          expiresInSec: 3600,
        }),
        expect.any(String),
      );
      // IN-02 — 공용 helper 이벤트는 이름 불변 · path="web" 으로 1-tap 과 구분.
      expect(infoMock).toHaveBeenCalledWith(
        expect.objectContaining({
          event: "naver_custom_token_issued",
          path: "web",
        }),
        expect.any(String),
      );
    },
  );

  // Phase 16.7 D-21 — 웹 경로도 1-tap 과 같은 공용 helper 를 거쳐 실제
  // resolveIdentity 신규 등록 분기에 도달한다. mock transaction 이 tx.set 을
  // 노출하므로 spy 대신 users payload 를 직접 단언한다 (end-to-end 배선).
  it(
    // eslint-disable-next-line max-len
    "D-21: 웹 신규 등록 → 공용 helper → resolveIdentity 신규 등록 tx 의 users payload signUpProviderId === \"naver\"",
    async () => {
      mockTokenOk();
      mockProfileOk("naver-web-d21");
      mockIdxGet.mockResolvedValue({exists: false});
      mockTxGet.mockResolvedValue({exists: false});

      const result = (await callWeb({
        auth: anonymousCallerAuth("anon-web-d21"),
        data: {
          code: FAKE_CODE,
          state: FAKE_STATE_22CHARS,
          termsAcceptanceSnapshot: TERMS_SNAPSHOT,
        },
      })) as WebResult;

      expect(result).toMatchObject({uid: "anon-web-d21", isNewUser: true});
      // users 문서 set (linkedProviders 를 싣는 호출) 은 정확히 1건.
      const usersSetCalls = mockTxSet.mock.calls.filter(
        (c: unknown[]) =>
          typeof c[1] === "object" &&
          c[1] !== null &&
          "linkedProviders" in (c[1] as Record<string, unknown>),
      );
      expect(usersSetCalls).toHaveLength(1);
      expect(usersSetCalls[0][1]).toMatchObject({signUpProviderId: "naver"});
      expect(usersSetCalls[0][2]).toEqual({merge: true});
    },
  );

  it(
    // eslint-disable-next-line max-len
    "T-QUICK-260924-LW2-NOREVOKE-01: 성공 경로 NAVER 호출 = [token 교환, /v1/nid/me] · delete grant 없음",
    async () => {
      mockTokenOk();
      mockProfileOk("naver-web-lw2-01");
      mockIdxGet.mockResolvedValue({exists: false});
      mockTxGet.mockResolvedValue({exists: false});

      const result = (await callWeb({
        auth: anonymousCallerAuth("anon-web-lw2-01"),
        data: {
          code: FAKE_CODE,
          state: FAKE_STATE_22CHARS,
          termsAcceptanceSnapshot: TERMS_SNAPSHOT,
        },
      })) as WebResult;

      expect(result.customToken).toBe("MOCK_NAVER_TOKEN");
      expect(fetchUrls()).toEqual([NAVER_TOKEN_URL, NAVER_PROFILE_URL]);
      expect(grantTypesSent()).toEqual(["authorization_code", null]);
    },
  );

  // eslint-disable-next-line max-len
  describe("T-QUICK-260924-LW2-NOREVOKE-02: helper 실패 경로도 NAVER 2회에서 끝", () => {
    it.each([
      [
        "/v1/nid/me fetch TimeoutError",
        "profile_timeout",
        {code: "unavailable", message: "errorServiceUnavailable"},
      ],
      [
        "createCustomToken reject",
        "custom_token_reject",
        {code: "internal", message: "errorUnknown"},
      ],
    ])(
      "T-QUICK-260924-LW2-NOREVOKE-02: %s → 예외 전파 · NAVER 2회",
      async (_label, failure, expected) => {
        mockTokenOk();
        if (failure === "profile_timeout") {
          mockFetchReject("TimeoutError");
        } else {
          mockProfileOk("naver-web-lw2-02");
          mockIdxGet.mockResolvedValue({exists: false});
          mockTxGet.mockResolvedValue({exists: false});
          mockCreateCustomToken.mockRejectedValueOnce(new Error("boom"));
        }

        await expect(
          callWeb({
            auth: anonymousCallerAuth("anon-web-lw2-02"),
            data: {code: FAKE_CODE, state: FAKE_STATE_22CHARS},
          }),
        ).rejects.toMatchObject(expected);
        expect(fetchMock).toHaveBeenCalledTimes(2);
        expect(grantTypesSent()).not.toContain("delete");
        expect(infoMock).not.toHaveBeenCalledWith(
          expect.objectContaining({event: "naver_web_custom_token_issued"}),
          expect.any(String),
        );
      },
    );
  });

  describe("T-QUICK-260924-LW2-TTL-01: expires_in → expiresInSec", () => {
    it.each([
      ["문자열 \"3600\"", {expires_in: "3600"}, 3600],
      ["정수 7200", {expires_in: 7200}, 7200],
      ["키 부재", {}, null],
      ["숫자 아닌 문자열", {expires_in: "abc"}, null],
      ["8자리 문자열", {expires_in: "12345678"}, null],
      ["음수", {expires_in: -1}, null],
      ["소수", {expires_in: 1.5}, null],
      ["토큰 반사", {expires_in: FAKE_ACCESS_TOKEN}, null],
    ])(
      "T-QUICK-260924-LW2-TTL-01: %s",
      async (_label, expiresField, expected) => {
        mockFetchJson(200, {
          access_token: FAKE_ACCESS_TOKEN,
          token_type: "bearer",
          ...expiresField,
        });
        mockProfileOk("naver-web-lw2-ttl");
        mockIdxGet.mockResolvedValue({exists: false});
        mockTxGet.mockResolvedValue({exists: false});

        const result = (await callWeb({
          auth: anonymousCallerAuth("anon-web-lw2-ttl"),
          data: {code: FAKE_CODE, state: FAKE_STATE_22CHARS},
        })) as WebResult;

        expect(result.customToken).toBe("MOCK_NAVER_TOKEN");
        expect(infoMock).toHaveBeenCalledWith(
          expect.objectContaining({
            event: "naver_web_custom_token_issued",
            expiresInSec: expected,
          }),
          expect.any(String),
        );
        expect(allLoggerArgsJson()).not.toContain(FAKE_ACCESS_TOKEN);
      },
    );
  });

  it(
    // eslint-disable-next-line max-len
    "T-16.5-NAVER-WEB-CT-02: 재로그인 (identity 기존) → isNewUser=false · terms mirror 미호출",
    async () => {
      mockTokenOk();
      mockProfileOk("naver-web-02");
      mockIdxGet.mockResolvedValue({exists: true});
      mockTxGet.mockResolvedValue({
        exists: true,
        data: () => ({firebaseUid: "existing-uid-web-02"}),
      });

      const result = (await callWeb({
        data: {
          code: FAKE_CODE,
          state: FAKE_STATE_22CHARS,
          termsAcceptanceSnapshot: TERMS_SNAPSHOT,
        },
      })) as WebResult;

      expect(result.isNewUser).toBe(false);
      expect(result.uid).toBe("existing-uid-web-02");
      expect(mockUserDocSet).not.toHaveBeenCalled();
      // 재로그인에서도 NAVER 는 2회뿐 — 폐기 요청 없음 (quick 260924-lw2).
      expect(fetchMock).toHaveBeenCalledTimes(2);
      expect(grantTypesSent()).not.toContain("delete");
    },
  );

  it(
    // eslint-disable-next-line max-len
    "T-16.5-NAVER-WEB-CT-03: token 200 + 본문 error=invalid_grant → unauthenticated · /v1/nid/me 미호출",
    async () => {
      mockFetchJson(200, {
        error: "invalid_grant",
        error_description: "no valid data in session",
      });

      await expect(
        callWeb({data: {code: FAKE_CODE, state: FAKE_STATE_22CHARS}}),
      ).rejects.toMatchObject({
        code: "unauthenticated",
        message: "errorInvalidCredentials",
      });
      expect(fetchMock).toHaveBeenCalledTimes(1);
      expect(warnMock).toHaveBeenCalledWith(
        expect.objectContaining({
          event: "naver_web_token_error_response",
          error: "invalid_grant",
        }),
        expect.any(String),
      );
    },
  );

  it(
    // eslint-disable-next-line max-len
    "T-16.5-NAVER-WEB-CT-04: token 200 + access_token 부재 (error 도 없음) → unauthenticated",
    async () => {
      mockFetchJson(200, {token_type: "bearer"});

      await expect(
        callWeb({data: {code: FAKE_CODE, state: FAKE_STATE_22CHARS}}),
      ).rejects.toMatchObject({
        code: "unauthenticated",
        message: "errorInvalidCredentials",
      });
      expect(fetchMock).toHaveBeenCalledTimes(1);
      expect(warnMock).toHaveBeenCalledWith(
        expect.objectContaining({
          event: "naver_web_token_error_response",
          error: "other",
        }),
        expect.any(String),
      );
    },
  );

  it(
    // eslint-disable-next-line max-len
    "T-16.5-NAVER-WEB-CT-05: token fetch reject (TimeoutError) → unavailable + exchange_failed fingerprint",
    async () => {
      mockFetchReject("TimeoutError");

      await expect(
        callWeb({data: {code: FAKE_CODE, state: FAKE_STATE_22CHARS}}),
      ).rejects.toMatchObject({
        code: "unavailable",
        message: "errorServiceUnavailable",
      });
      expect(fetchMock).toHaveBeenCalledTimes(1);
      expect(warnMock).toHaveBeenCalledWith(
        expect.objectContaining({
          event: "naver_web_token_exchange_failed",
          code: "TimeoutError",
        }),
        expect.any(String),
      );
    },
  );

  it(
    // eslint-disable-next-line max-len
    "T-16.5-NAVER-WEB-CT-05b: token 본문 읽기 중 timeout (TimeoutError) → unavailable (internal 아님) · IN-04",
    async () => {
      fetchMock.mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => {
          const err = new Error("The operation was aborted due to timeout");
          err.name = "TimeoutError";
          throw err;
        },
      });

      await expect(
        callWeb({data: {code: FAKE_CODE, state: FAKE_STATE_22CHARS}}),
      ).rejects.toMatchObject({
        code: "unavailable",
        message: "errorServiceUnavailable",
      });
      expect(fetchMock).toHaveBeenCalledTimes(1);
      expect(warnMock).toHaveBeenCalledWith(
        expect.objectContaining({
          event: "naver_web_token_exchange_failed",
          code: "TimeoutError",
        }),
        expect.any(String),
      );
    },
  );

  describe("T-16.5-NAVER-WEB-CT-06: token HTTP 오류 매핑", () => {
    it.each([
      [500, "unavailable", "errorServiceUnavailable"],
      [401, "unauthenticated", "errorInvalidCredentials"],
      [429, "unavailable", "errorServiceUnavailable"],
    ])(
      "T-16.5-NAVER-WEB-CT-06: HTTP %i → %s",
      async (status, code, message) => {
        mockFetchJson(status, {});

        await expect(
          callWeb({data: {code: FAKE_CODE, state: FAKE_STATE_22CHARS}}),
        ).rejects.toMatchObject({code, message});
        expect(fetchMock).toHaveBeenCalledTimes(1);
        expect(warnMock).toHaveBeenCalledWith(
          expect.objectContaining({
            event: "naver_web_token_exchange_failed",
            status,
          }),
          expect.any(String),
        );
      },
    );
  });

  it(
    "T-16.5-NAVER-WEB-CT-07: token 응답 JSON parse 실패 → internal",
    async () => {
      fetchMock.mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => {
          throw new SyntaxError("Unexpected token <");
        },
      });

      await expect(
        callWeb({data: {code: FAKE_CODE, state: FAKE_STATE_22CHARS}}),
      ).rejects.toMatchObject({code: "internal", message: "errorUnknown"});
      expect(fetchMock).toHaveBeenCalledTimes(1);
    },
  );

  it(
    // eslint-disable-next-line max-len
    "T-16.5-NAVER-WEB-CT-09: /v1/nid/me 401 (helper 실패) → 예외 전파 · NAVER 2회 (폐기 없음)",
    async () => {
      mockTokenOk();
      mockFetchJson(401, {});

      await expect(
        callWeb({data: {code: FAKE_CODE, state: FAKE_STATE_22CHARS}}),
      ).rejects.toMatchObject({
        code: "unauthenticated",
        message: "errorInvalidCredentials",
      });
      expect(warnMock).toHaveBeenCalledWith(
        expect.objectContaining({
          event: "naver_verify_unauthenticated",
          path: "web",
        }),
        expect.any(String),
      );
      expect(fetchMock).toHaveBeenCalledTimes(2);
      expect(fetchUrls()).toEqual([NAVER_TOKEN_URL, NAVER_PROFILE_URL]);
      expect(grantTypesSent()).not.toContain("delete");
      expect(infoMock).not.toHaveBeenCalledWith(
        expect.objectContaining({event: "naver_web_custom_token_issued"}),
        expect.any(String),
      );
    },
  );

  it(
    // eslint-disable-next-line max-len
    "T-16.5-NAVER-WEB-CT-10: PII 0 — 토큰 · secret · code · state 가 logger 인자에 없다",
    async () => {
      // 시나리오 A: 성공 경로 (info).
      mockTokenOk();
      mockProfileOk("naver-web-10");
      mockIdxGet.mockResolvedValue({exists: false});
      mockTxGet.mockResolvedValue({exists: false});
      await callWeb({
        auth: anonymousCallerAuth("anon-web-10"),
        data: {
          code: FAKE_CODE,
          state: FAKE_STATE_22CHARS,
          termsAcceptanceSnapshot: TERMS_SNAPSHOT,
        },
      });

      // 양성 대조군 — 값이 실제로 fetch 본문에 실렸음을 먼저 세운다.
      const exchangeBody = String(
        (fetchMock.mock.calls[0][1] as {body?: unknown}).body,
      );
      expect(exchangeBody).toContain(FAKE_CODE);
      expect(exchangeBody).toContain(FAKE_STATE_22CHARS);
      expect(exchangeBody).toContain("fake-naver-secret");
      // access_token 은 /v1/nid/me Authorization 헤더로만 나간다.
      const profileInit = fetchMock.mock.calls[1][1] as {
        headers: Record<string, string>;
      };
      expect(profileInit.headers.Authorization).toBe(
        `Bearer ${FAKE_ACCESS_TOKEN}`,
      );

      // 시나리오 B: 본문 error 응답 (error_description 에 code 반사).
      mockFetchJson(200, {
        error: "invalid_request",
        error_description: `bad code ${FAKE_CODE}`,
        refresh_token: FAKE_REFRESH_TOKEN,
      });
      await expect(
        callWeb({data: {code: FAKE_CODE, state: FAKE_STATE_22CHARS}}),
      ).rejects.toMatchObject({code: "unauthenticated"});

      // 시나리오 C: error 필드가 화이트리스트 밖 (토큰 반사 시도).
      mockFetchJson(200, {error: FAKE_ACCESS_TOKEN});
      await expect(
        callWeb({data: {code: FAKE_CODE, state: FAKE_STATE_22CHARS}}),
      ).rejects.toMatchObject({code: "unauthenticated"});

      // 로그가 실제로 남았는지 (공허 단언 방지).
      expect(infoMock.mock.calls.length).toBeGreaterThan(0);
      expect(warnMock.mock.calls.length).toBeGreaterThan(0);

      const logged = allLoggerArgsJson();
      for (const secret of [
        FAKE_ACCESS_TOKEN,
        FAKE_REFRESH_TOKEN,
        "fake-naver-secret",
        FAKE_CODE,
        FAKE_STATE_22CHARS,
      ]) {
        expect(logged).not.toContain(secret);
      }
    },
  );

  describe("T-16.5-NAVER-WEB-CT-11: 입력 검증 → invalid-argument", () => {
    it.each([
      ["code 부재", {state: FAKE_STATE_22CHARS}],
      ["state 가 number", {code: FAKE_CODE, state: 12345}],
      ["state 에 CR", {code: FAKE_CODE, state: "abc\rdef"}],
      ["state 길이 513", {code: FAKE_CODE, state: "s".repeat(513)}],
    ])("T-16.5-NAVER-WEB-CT-11: %s", async (_label, data) => {
      await expect(callWeb({data})).rejects.toMatchObject({
        code: "invalid-argument",
        message: "errorInvalidArgument",
      });
      expect(fetchMock).not.toHaveBeenCalled();
    });
  });
});
