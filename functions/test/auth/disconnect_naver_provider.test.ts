/**
 * disconnectNaverProvider onCall 테스트 (Phase 16.10 plan 03 · SOCL-13 ·
 * SOCL-15).
 *
 * **Mock 한계 — 실 단말 UAT (plan 10) 가 ground truth.** 본 파일은 전역
 * `fetch`(NAVER token 교환 · `/v1/nid/me` · `/oauth2.0/revoke`) · Firestore
 * `identity_index` 문서 read · Admin Auth `createCustomToken` 을 jest stub
 * 으로 흉내낸다. 실 NAVER 서버의 revoke 응답 · 재동의 뒤 같은 id(D-14)는
 * UAT 가 관측한다.
 *
 * 시나리오:
 *  - NR1: 1-tap 성공 — 프로필 → 소유 대조 → revoke → custom token 순서 ·
 *    응답 `{ok, customToken, uid}` · 성공 로그 path `disconnect_app`
 *  - NR2: 소유 불일치(타 uid · 원장 부재) → permission-denied
 *    (caller_identity_mismatch) · revoke 0 · custom token 0
 *  - NR3: 웹 성공 — code 교환 → 프로필 → revoke · path `disconnect_web`
 *  - NR4: revoke form body 4 필드 정확 · URL 에 시크릿 없음
 *  - NR5~NR8: 입력 모양 · 위생 — 모양 섞임 · 모양 부재 · CRLF · state 상한
 *    → invalid-argument · 외부 호출 0 (1회용 code 미소비)
 *  - NR9 · NR10: 익명(anonymous_caller) · 미인증 거부 · 외부 호출 0
 *  - NR11: 프로필 401 → unauthenticated · 원장 read 0 · revoke 0
 *  - NR12~NR15: revoke 실패 매핑 — provider_config · 200+error 본문 ·
 *    401 빈 본문 · fetch reject
 *  - NR16: custom token 발급 실패 → internal · 실패 로그
 *  - NR17: PII sentinel — 모든 케이스의 logger 호출 누적 검사 (마지막)
 *
 * PII sentinel: access token · code · state · client secret · Naver id ·
 * 발급 custom token · 이메일 fixture(`PII_NAVER_*` · `PII_MINTED_*` ·
 * `pii-naver@example.com`)는 HttpsError message/details 와 어느 logger 호출
 * 인자에도 나오면 안 된다.
 */

// fetch mock — token 교환 · /v1/nid/me · revoke 호출을 순서대로 stub.
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
// client_secret 은 PII sentinel 값으로 둔다 (로그 노출 0 단언 대상).
jest.mock("firebase-functions/params", () => ({
  defineSecret: (name: string) => ({
    value: () =>
      name === "NAVER_CLIENT_ID" ? "fake-naver-client-id" : "PII_NAVER_SECRET",
  }),
}));

// firebase-admin/auth — 재로그인 custom token 발급 stub.
const mockCreateCustomToken = jest.fn();
jest.mock("firebase-admin/auth", () => ({
  getAuth: jest.fn(() => ({createCustomToken: mockCreateCustomToken})),
}));

// jose — index 가 load 하는 OIDC verifier 모듈용 stub (link 테스트 mirror).
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
  return {
    jwtVerify: jest.fn(),
    createRemoteJWKSet: jest.fn(() => "MOCK_JWKS"),
    errors: {JOSEError},
  };
});

// firebase-admin/firestore — `collection(name).doc(id).get()` 을 기록한다.
// jest hoisting: factory 가 참조하는 바깥 변수는 이름이 `mock` 으로 시작해야
// 한다. 호출 시점에 지연 참조한다.
const mockDocGet = jest.fn();
jest.mock("firebase-admin/firestore", () => ({
  Firestore: class MockFirestore {},
  getFirestore: jest.fn(() => ({
    collection: (name: string) => ({
      doc: (id: string) => ({get: () => mockDocGet(name, id)}),
    }),
  })),
  FieldValue: {
    serverTimestamp: () => "MOCK_TIMESTAMP",
    delete: () => "MOCK_DELETE",
    arrayUnion: (item: unknown) => ({mockArrayUnion: item}),
  },
}));

// eslint-disable-next-line import/first
import functionsTest from "firebase-functions-test";
// eslint-disable-next-line import/first
import * as logger from "firebase-functions/logger";
// eslint-disable-next-line import/first
import {HttpsError} from "firebase-functions/https";
// eslint-disable-next-line import/first
import {
  anonymousCallerAuth,
  signedInCallerAuth,
} from "../mocks/caller_auth";
// eslint-disable-next-line import/first
import type {CallerAuthFixture} from "../mocks/caller_auth";

const testEnv = functionsTest();

// eslint-disable-next-line import/first
import * as myFunctions from "../../src/index";

const infoMock = logger.info as unknown as jest.Mock;
const warnMock = logger.warn as unknown as jest.Mock;
const errorMock = logger.error as unknown as jest.Mock;
const debugMock = logger.debug as unknown as jest.Mock;
const logMock = logger.log as unknown as jest.Mock;

/** 정식 로그인 caller UID. */
const CALLER_UID = "caller-uid-naver";

/** `/v1/nid/me` 가 돌려주는 Naver 사용자 id fixture (PII sentinel). */
const NAVER_ID = "PII_NAVER_ID";

/** 발급 custom token fixture — 응답에만 있고 로그에는 없어야 한다. */
const MINTED_TOKEN = "PII_MINTED_CUSTOM_TOKEN";

/** NAVER endpoint — 전역 fetch 호출 모양 단언용. */
const NAVER_TOKEN_URL = "https://nid.naver.com/oauth2.0/token";
const NAVER_PROFILE_URL = "https://openapi.naver.com/v1/nid/me";
const NAVER_REVOKE_URL = "https://nid.naver.com/oauth2.0/revoke";

/** HttpsError message/details · logger 인자에 나오면 안 되는 값. */
const PII_SENTINELS = [
  "PII_NAVER_ACCESS_TOKEN",
  "PII_NAVER_CODE",
  "PII_NAVER_STATE",
  "PII_NAVER_SECRET",
  "PII_NAVER_ID",
  "PII_MINTED_CUSTOM_TOKEN",
  "pii-naver@example.com",
];

/** 1-tap 모양 요청 data. */
const APP_DATA = {accessToken: "PII_NAVER_ACCESS_TOKEN"};

/** 웹 모양 요청 data. */
const WEB_DATA = {code: "PII_NAVER_CODE", state: "PII_NAVER_STATE"};

/** 모든 케이스의 logger 호출 누적 — 마지막 describe 의 PII sentinel 이 검사. */
const accumulatedLogCalls: unknown[][] = [];

/**
 * identity_index 문서 read 결과를 구성한다.
 *
 * @param {string | undefined} ownerUid 문서의 `firebaseUid`
 *     (undefined = 문서 없음).
 */
function arrangeOwner(ownerUid: string | undefined): void {
  mockDocGet.mockResolvedValue({
    exists: ownerUid !== undefined,
    data: () => ({firebaseUid: ownerUid, provider: "naver"}),
  });
}

beforeEach(() => {
  jest.clearAllMocks();
  fetchMock.mockReset();
  mockDocGet.mockReset();
  mockCreateCustomToken.mockReset();
  mockCreateCustomToken.mockResolvedValue(MINTED_TOKEN);
  arrangeOwner(CALLER_UID);
});

afterEach(() => {
  // 다음 beforeEach 의 clearAllMocks 가 지우기 전에 누적한다.
  accumulatedLogCalls.push(
    ...infoMock.mock.calls,
    ...warnMock.mock.calls,
    ...errorMock.mock.calls,
    ...debugMock.mock.calls,
    ...logMock.mock.calls,
  );
});

afterAll(() => testEnv.cleanup());

/**
 * fetch mock — 응답 1건. `json()` · `text()` 둘 다 같은 본문을 읽는다.
 *
 * @param {number} status HTTP status.
 * @param {string} body 응답 본문 원문 (빈 문자열 = 본문 없음).
 */
function mockFetchResponse(status: number, body = ""): void {
  fetchMock.mockResolvedValueOnce({
    ok: status >= 200 && status < 300,
    status,
    json: async () => JSON.parse(body),
    text: async () => body,
  });
}

/** `/v1/nid/me` 정상 응답 — email 은 PII sentinel (미독 확인용). */
function mockProfileOk(): void {
  mockFetchResponse(
    200,
    JSON.stringify({
      resultcode: "00",
      message: "success",
      response: {id: NAVER_ID, email: "pii-naver@example.com"},
    }),
  );
}

/** token 교환 정상 응답 — access_token 은 PII sentinel. */
function mockExchangeOk(): void {
  mockFetchResponse(
    200,
    JSON.stringify({
      access_token: "PII_NAVER_ACCESS_TOKEN",
      expires_in: "3600",
    }),
  );
}

/** revoke 정상 응답 — 본문 없이 HTTP 200 (Naver 문서 6.2.4). */
function mockRevokeOk(): void {
  mockFetchResponse(200, "");
}

/**
 * disconnectNaverProvider 를 호출한다.
 *
 * @param {object} data callable 요청 data.
 * @param {CallerAuthFixture | null} auth `request.auth` fixture
 *     (null = auth 부재).
 * @return {Promise<unknown>} callable 결과 promise.
 */
function callDisconnect(
  data: object,
  auth: CallerAuthFixture | null = signedInCallerAuth(CALLER_UID),
): Promise<unknown> {
  const wrapped = testEnv.wrap(myFunctions.disconnectNaverProvider);
  const request = auth === null ?
    {app: {appId: "test"}, data} :
    {auth, app: {appId: "test"}, data};
  return wrapped(request as never) as Promise<unknown>;
}

/**
 * 거부된 callable 의 HttpsError 를 꺼내고 message · details 에 PII 가
 * 없음을 단언한다.
 *
 * @param {Promise<unknown>} promise callable 호출.
 * @return {Promise<HttpsError>} 던져진 HttpsError.
 */
async function captureHttpsError(
  promise: Promise<unknown>,
): Promise<HttpsError> {
  const err = await promise.then(
    () => undefined,
    (e: unknown) => e,
  );
  expect(err).toBeInstanceOf(HttpsError);
  const httpsErr = err as HttpsError;
  const serialized = JSON.stringify({
    message: httpsErr.message,
    details: httpsErr.details,
  });
  for (const sentinel of PII_SENTINELS) {
    expect(serialized).not.toContain(sentinel);
  }
  return httpsErr;
}

/**
 * fetch 호출의 form body 를 꺼낸다.
 *
 * @param {number} index fetch 호출 순번.
 * @return {URLSearchParams} 요청 body.
 */
function fetchBodyAt(index: number): URLSearchParams {
  const init = fetchMock.mock.calls[index][1] as {body: URLSearchParams};
  return init.body;
}

describe("disconnectNaverProvider — 1-tap 성공 · 소유 대조", () => {
  it("NR1: 1-tap — 프로필 → 대조 → revoke → 토큰 · 응답", async () => {
    mockProfileOk();
    mockRevokeOk();

    // customToken 은 호출자 응답에만 간다 — 「응답에만 있고 로그에는 없음」
    // 의 뒤쪽 절반은 NR17 PII sentinel 이 누적 logger 호출로 함께 증명한다.
    await expect(callDisconnect(APP_DATA)).resolves.toEqual({
      ok: true,
      customToken: "PII_MINTED_CUSTOM_TOKEN",
      uid: CALLER_UID,
    });

    // fetch 2회 — 프로필 GET(Bearer) → revoke POST (교환 없음).
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(fetchMock.mock.calls[0][0]).toBe(NAVER_PROFILE_URL);
    expect(fetchMock.mock.calls[0][1]).toEqual(
      expect.objectContaining({
        method: "GET",
        headers: expect.objectContaining({
          Authorization: "Bearer PII_NAVER_ACCESS_TOKEN",
        }),
        signal: expect.anything(),
      }),
    );
    expect(fetchMock.mock.calls[1][0]).toBe(NAVER_REVOKE_URL);
    expect(fetchMock.mock.calls[1][1]).toEqual(
      expect.objectContaining({
        method: "POST",
        headers: expect.objectContaining({
          "Content-Type": "application/x-www-form-urlencoded",
        }),
        signal: expect.anything(),
      }),
    );
    // 소유 대조는 프로필 id 의 원장 문서 1건 read.
    expect(mockDocGet.mock.calls).toEqual([
      ["identity_index", "naver:PII_NAVER_ID"],
    ]);
    // custom token 은 caller uid 로만 · developer claims 0.
    expect(mockCreateCustomToken.mock.calls).toEqual([[CALLER_UID]]);
    // 호출 순서: 소유 대조 < revoke < custom token (D-08 · D-07).
    const docOrder = mockDocGet.mock.invocationCallOrder[0];
    const revokeOrder = fetchMock.mock.invocationCallOrder[1];
    const mintOrder = mockCreateCustomToken.mock.invocationCallOrder[0];
    expect(docOrder).toBeLessThan(revokeOrder);
    expect(revokeOrder).toBeLessThan(mintOrder);
    expect(infoMock).toHaveBeenCalledWith(
      {
        event: "disconnect_naver_succeeded",
        uid: CALLER_UID,
        path: "disconnect_app",
      },
      expect.any(String),
    );
  });

  it("NR2: 소유 불일치 → caller_identity_mismatch · revoke 0", async () => {
    // 다른 계정 소유 · 원장 부재(연결되지 않은 신원) 모두 같은 거부다.
    for (const ownerUid of ["other-uid", undefined]) {
      fetchMock.mockReset();
      arrangeOwner(ownerUid);
      mockProfileOk();

      const err = await captureHttpsError(callDisconnect(APP_DATA));
      expect(err.code).toBe("permission-denied");
      expect(err.message).toBe("errorReauthUserMismatch");
      expect(err.details).toEqual({reason: "caller_identity_mismatch"});
      // 프로필 1회뿐 — revoke 호출 0.
      expect(fetchMock).toHaveBeenCalledTimes(1);
      expect(fetchMock.mock.calls[0][0]).toBe(NAVER_PROFILE_URL);
    }
    expect(mockCreateCustomToken).not.toHaveBeenCalled();
    expect(infoMock).not.toHaveBeenCalled();
  });
});

describe("disconnectNaverProvider — 웹 성공 · revoke 요청 모양", () => {
  it("NR3: 웹 — code 교환 → 프로필 → revoke · path web", async () => {
    mockExchangeOk();
    mockProfileOk();
    mockRevokeOk();

    await expect(callDisconnect(WEB_DATA)).resolves.toEqual({
      ok: true,
      customToken: "PII_MINTED_CUSTOM_TOKEN",
      uid: CALLER_UID,
    });

    expect(fetchMock).toHaveBeenCalledTimes(3);
    expect(fetchMock.mock.calls.map((call) => call[0])).toEqual([
      NAVER_TOKEN_URL,
      NAVER_PROFILE_URL,
      NAVER_REVOKE_URL,
    ]);
    const exchangeBody = fetchBodyAt(0);
    expect(exchangeBody.get("grant_type")).toBe("authorization_code");
    expect(exchangeBody.get("code")).toBe("PII_NAVER_CODE");
    expect(exchangeBody.get("state")).toBe("PII_NAVER_STATE");
    // 교환으로 얻은 access token 이 프로필 · revoke 에 쓰인다.
    expect(fetchMock.mock.calls[1][1]).toEqual(
      expect.objectContaining({
        headers: expect.objectContaining({
          Authorization: "Bearer PII_NAVER_ACCESS_TOKEN",
        }),
      }),
    );
    expect(fetchBodyAt(2).get("token")).toBe("PII_NAVER_ACCESS_TOKEN");
    expect(mockCreateCustomToken.mock.calls).toEqual([[CALLER_UID]]);
    expect(infoMock).toHaveBeenCalledWith(
      {
        event: "disconnect_naver_succeeded",
        uid: CALLER_UID,
        path: "disconnect_web",
      },
      expect.any(String),
    );
  });

  it("NR4: revoke form body 4 필드 정확 · URL 에 시크릿 없음", async () => {
    mockProfileOk();
    mockRevokeOk();

    await callDisconnect(APP_DATA);

    expect(fetchMock.mock.calls[1][0]).toBe(NAVER_REVOKE_URL);
    expect(Array.from(fetchBodyAt(1).entries())).toEqual([
      ["client_id", "fake-naver-client-id"],
      ["client_secret", "PII_NAVER_SECRET"],
      ["token", "PII_NAVER_ACCESS_TOKEN"],
      ["token_type_hint", "access_token"],
    ]);
    expect(fetchMock.mock.calls[1][0]).not.toContain("PII_NAVER_SECRET");
  });
});

describe("disconnectNaverProvider — 입력 모양 · 위생", () => {
  it("NR5: accessToken + code 동시 → invalid-argument · fetch 0", async () => {
    const err = await captureHttpsError(
      callDisconnect({...APP_DATA, code: "PII_NAVER_CODE"}),
    );
    expect(err.code).toBe("invalid-argument");
    expect(err.message).toBe("errorInvalidArgument");
    expect(fetchMock).not.toHaveBeenCalled();
    expect(mockDocGet).not.toHaveBeenCalled();
  });

  it("NR6: 모양 필드 0 → invalid-argument · fetch 0", async () => {
    const err = await captureHttpsError(callDisconnect({}));
    expect(err.code).toBe("invalid-argument");
    expect(err.message).toBe("errorInvalidArgument");
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("NR7: accessToken CRLF · code NUL → invalid-argument", async () => {
    for (const data of [
      {accessToken: "PII_NAVER_ACCESS_TOKEN\r\nX-Injected: 1"},
      {code: "PII_NAVER_CODE\u0000", state: "PII_NAVER_STATE"},
    ]) {
      const err = await captureHttpsError(callDisconnect(data));
      expect(err.code).toBe("invalid-argument");
      expect(err.message).toBe("errorInvalidArgument");
    }
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("NR8: state 513자 → invalid-argument · 교환 0", async () => {
    const err = await captureHttpsError(
      callDisconnect({code: "PII_NAVER_CODE", state: "s".repeat(513)}),
    );
    expect(err.code).toBe("invalid-argument");
    expect(err.message).toBe("errorInvalidArgument");
    expect(fetchMock).not.toHaveBeenCalled();
  });
});

describe("disconnectNaverProvider — caller 가드", () => {
  it("NR9: 익명 → anonymous_caller · fetch 0 · 원장 read 0", async () => {
    const err = await captureHttpsError(
      callDisconnect(WEB_DATA, anonymousCallerAuth("anon-uid")),
    );
    expect(err.code).toBe("failed-precondition");
    expect(err.message).toBe("errorAnonymousDisconnectNotAllowed");
    expect(err.details).toEqual({reason: "anonymous_caller"});
    // 거부되는 caller 는 1회용 code 를 소비하지 않는다.
    expect(fetchMock).not.toHaveBeenCalled();
    expect(mockDocGet).not.toHaveBeenCalled();
    expect(mockCreateCustomToken).not.toHaveBeenCalled();
  });

  it("NR10: request.auth 부재 → unauthenticated · fetch 0", async () => {
    const err = await captureHttpsError(callDisconnect(APP_DATA, null));
    expect(err.code).toBe("unauthenticated");
    expect(err.message).toBe("errorUnauthenticated");
    expect(fetchMock).not.toHaveBeenCalled();
    expect(mockDocGet).not.toHaveBeenCalled();
  });
});

describe("disconnectNaverProvider — 프로필 · revoke 실패 매핑", () => {
  it("NR11: 프로필 401 → unauthenticated · 대조 0 · revoke 0", async () => {
    mockFetchResponse(401, "");

    const err = await captureHttpsError(callDisconnect(APP_DATA));
    expect(err.code).toBe("unauthenticated");
    expect(err.message).toBe("errorInvalidCredentials");
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(mockDocGet).not.toHaveBeenCalled();
    expect(mockCreateCustomToken).not.toHaveBeenCalled();
    expect(warnMock).toHaveBeenCalledWith(
      {
        event: "naver_verify_unauthenticated",
        path: "disconnect_app",
        status: 401,
      },
      expect.any(String),
    );
  });

  it("NR12: revoke unauthorized_client → provider_config", async () => {
    mockProfileOk();
    mockFetchResponse(
      400,
      JSON.stringify({
        error: "unauthorized_client",
        error_description: "PII_NAVER_SECRET rejected",
      }),
    );

    const err = await captureHttpsError(callDisconnect(APP_DATA));
    expect(err.code).toBe("failed-precondition");
    expect(err.message).toBe("errorProviderConfig");
    expect(err.details).toEqual({reason: "provider_config"});
    expect(mockCreateCustomToken).not.toHaveBeenCalled();
    // 로그는 화이트리스트 error 코드 · status 만 — error_description 0.
    expect(errorMock).toHaveBeenCalledWith(
      {
        event: "disconnect_naver_revoke_failed",
        uid: CALLER_UID,
        path: "disconnect_app",
        status: 400,
        code: "unauthorized_client",
      },
      expect.any(String),
    );
  });

  it("NR13: revoke 200 + error 본문 → unavailable (성공 오판 0)", async () => {
    mockProfileOk();
    mockFetchResponse(200, JSON.stringify({error: "invalid_request"}));

    const err = await captureHttpsError(callDisconnect(APP_DATA));
    expect(err.code).toBe("unavailable");
    expect(err.message).toBe("errorServiceUnavailable");
    expect(mockCreateCustomToken).not.toHaveBeenCalled();
    expect(infoMock).not.toHaveBeenCalled();
    expect(errorMock).toHaveBeenCalledWith(
      {
        event: "disconnect_naver_revoke_failed",
        uid: CALLER_UID,
        path: "disconnect_app",
        status: 200,
        code: "invalid_request",
      },
      expect.any(String),
    );
  });

  it("NR14: revoke 401 + 빈 본문 → unauthenticated", async () => {
    mockProfileOk();
    mockFetchResponse(401, "");

    const err = await captureHttpsError(callDisconnect(APP_DATA));
    expect(err.code).toBe("unauthenticated");
    expect(err.message).toBe("errorInvalidCredentials");
    expect(mockCreateCustomToken).not.toHaveBeenCalled();
    expect(errorMock).toHaveBeenCalledWith(
      {
        event: "disconnect_naver_revoke_failed",
        uid: CALLER_UID,
        path: "disconnect_app",
        status: 401,
        code: "none",
      },
      expect.any(String),
    );
  });

  it("NR15: revoke fetch reject → unavailable · err.name 만 로그", async () => {
    mockProfileOk();
    fetchMock.mockRejectedValueOnce(
      new TypeError("PII_NAVER_ACCESS_TOKEN fetch failed"),
    );

    const err = await captureHttpsError(callDisconnect(APP_DATA));
    expect(err.code).toBe("unavailable");
    expect(err.message).toBe("errorServiceUnavailable");
    expect(mockCreateCustomToken).not.toHaveBeenCalled();
    expect(errorMock).toHaveBeenCalledWith(
      {
        event: "disconnect_naver_revoke_failed",
        uid: CALLER_UID,
        path: "disconnect_app",
        code: "TypeError",
      },
      expect.any(String),
    );
  });
});

describe("disconnectNaverProvider — custom token 발급 실패", () => {
  it("NR16: createCustomToken 던짐 → internal · 실패 로그", async () => {
    mockProfileOk();
    mockRevokeOk();
    mockCreateCustomToken.mockRejectedValueOnce(
      new Error("PII_MINTED_CUSTOM_TOKEN signer failed"),
    );

    const err = await captureHttpsError(callDisconnect(APP_DATA));
    expect(err.code).toBe("internal");
    expect(err.message).toBe("errorUnknown");
    expect(errorMock).toHaveBeenCalledWith(
      {
        event: "disconnect_relogin_token_failed",
        provider: "naver",
        code: "Error",
      },
      expect.any(String),
    );
    expect(infoMock).not.toHaveBeenCalled();
  });
});

// 반드시 마지막 describe — 앞선 모든 케이스의 logger 호출을 검사한다.
describe("disconnectNaverProvider — PII sentinel (NR17)", () => {
  it("NR17: 모든 케이스의 logger 호출에 PII fixture 값 0", () => {
    // 앞선 케이스들이 실제로 로그를 남겼는지부터 확인 (공허 통과 방지).
    expect(accumulatedLogCalls.length).toBeGreaterThan(10);
    const serialized = JSON.stringify(accumulatedLogCalls);
    for (const sentinel of [
      "PII_NAVER_ACCESS_TOKEN",
      "PII_NAVER_CODE",
      "PII_NAVER_STATE",
      "PII_NAVER_SECRET",
      "PII_NAVER_ID",
      "PII_MINTED_CUSTOM_TOKEN",
      "pii-naver@example.com",
    ]) {
      expect(serialized).not.toContain(sentinel);
    }
  });
});
