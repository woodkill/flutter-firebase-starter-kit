/**
 * disconnectLineProvider onCall 테스트 (Phase 16.10 plan 04 · SOCL-13 ·
 * SOCL-15).
 *
 * **Mock 한계 — 실 단말 UAT (plan 10) 가 ground truth.** 본 파일은 전역
 * `fetch`(LINE `/v2/profile` · stateless channel token 발급 · deauthorize) ·
 * Firestore `identity_index` 문서 read · Admin Auth `createCustomToken` 을
 * jest stub 으로 흉내낸다. 실 LINE 서버의 deauthorize 응답 · 「연동 중인 앱」
 * 목록 소멸(D-16)은 UAT 가 관측한다.
 *
 * 시나리오:
 *  - LR1: 성공 — 프로필 GET → 소유 대조 → channel token 발급 POST(form) →
 *    deauthorize POST(JSON) → custom token 순서 · 응답 `{ok, customToken, uid}`
 *  - LR2: 소유 불일치(타 uid · 원장 부재) → permission-denied
 *    (caller_identity_mismatch) · 발급 · 해제 · custom token 0
 *  - LR3: deauthorize 400 → 이미 해제 · 성공 (D-14 멱등)
 *  - LR4: 익명 → anonymous_caller · 외부 호출 0
 *
 * PII sentinel: 사용자 access token · LINE userId · channel secret ·
 * channel token · 프로필 displayName · 발급 custom token fixture
 * (`PII_LINE_*` · `PII_MINTED_*`)는 HttpsError message/details 와 어느
 * logger 호출 인자에도 나오면 안 된다.
 */

// fetch mock — 프로필 · channel token 발급 · deauthorize 호출을 순서대로 stub.
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

// secret 주입 — 이름으로 분기한다. channel secret 은 PII sentinel 값으로
// 둔다 (로그 노출 0 단언 대상).
jest.mock("firebase-functions/params", () => ({
  defineSecret: (name: string) => ({
    value: () => {
      if (name === "LINE_CHANNEL_ID") return "fake-line-channel-id";
      if (name === "LINE_CHANNEL_SECRET") return "PII_LINE_CHANNEL_SECRET";
      return `stub-${name}`;
    },
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
const CALLER_UID = "caller-uid-line";

/** 발급 custom token fixture — 응답에만 있고 로그에는 없어야 한다. */
const MINTED_TOKEN = "PII_MINTED_CUSTOM_TOKEN";

/** LINE endpoint — 전역 fetch 호출 모양 단언용. */
const LINE_PROFILE_URL = "https://api.line.me/v2/profile";
const LINE_STATELESS_TOKEN_URL = "https://api.line.me/oauth2/v3/token";
const LINE_DEAUTHORIZE_URL = "https://api.line.me/user/v1/deauthorize";

/** HttpsError message/details · logger 인자에 나오면 안 되는 값. */
const PII_SENTINELS = [
  "PII_LINE_ACCESS_TOKEN",
  "PII_LINE_USER_ID",
  "PII_LINE_CHANNEL_SECRET",
  "PII_LINE_CHANNEL_TOKEN",
  "PII_LINE_DISPLAY_NAME",
  "PII_MINTED_CUSTOM_TOKEN",
];

/** 요청 data — LINE SDK 재로그인 access token. */
const LINE_DATA = {accessToken: "PII_LINE_ACCESS_TOKEN"};

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
    data: () => ({firebaseUid: ownerUid, provider: "line"}),
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

/** `/v2/profile` 정상 응답 — displayName 은 PII sentinel (미독 확인용). */
function mockProfileOk(): void {
  mockFetchResponse(
    200,
    JSON.stringify({
      userId: "PII_LINE_USER_ID",
      displayName: "PII_LINE_DISPLAY_NAME",
    }),
  );
}

/** stateless channel token 발급 정상 응답 — access_token 은 PII sentinel. */
function mockChannelTokenOk(): void {
  mockFetchResponse(
    200,
    JSON.stringify({
      access_token: "PII_LINE_CHANNEL_TOKEN",
      expires_in: 900,
      token_type: "Bearer",
    }),
  );
}

/** deauthorize 정상 응답 — 본문 없이 204 (LINE reference). */
function mockDeauthorizeOk(): void {
  mockFetchResponse(204, "");
}

/**
 * disconnectLineProvider 를 호출한다.
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
  const wrapped = testEnv.wrap(myFunctions.disconnectLineProvider);
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

/** fetch 요청 init 중 단언에 쓰는 필드. */
type FetchInit = {
  method?: string;
  headers?: Record<string, string>;
  body?: unknown;
};

/**
 * fetch 호출의 요청 init 을 꺼낸다.
 *
 * @param {number} index fetch 호출 순번.
 * @return {FetchInit} 요청 init.
 */
function fetchInitAt(index: number): FetchInit {
  return fetchMock.mock.calls[index][1] as FetchInit;
}

describe("disconnectLineProvider — 성공 · 소유 대조", () => {
  it("LR1: 프로필 → 대조 → 발급 → 해제 → 토큰 · 응답", async () => {
    mockProfileOk();
    mockChannelTokenOk();
    mockDeauthorizeOk();

    // customToken 은 호출자 응답에만 간다 — 「응답에만 있고 로그에는 없음」
    // 의 뒤쪽 절반은 PII sentinel 이 누적 logger 호출로 함께 증명한다.
    await expect(callDisconnect(LINE_DATA)).resolves.toEqual({
      ok: true,
      customToken: "PII_MINTED_CUSTOM_TOKEN",
      uid: CALLER_UID,
    });

    // fetch 3회 순서 — 프로필 GET → channel token POST → deauthorize POST.
    expect(fetchMock.mock.calls.map((call) => call[0])).toEqual([
      LINE_PROFILE_URL,
      LINE_STATELESS_TOKEN_URL,
      LINE_DEAUTHORIZE_URL,
    ]);

    // 프로필 — 사용자 access token 을 Bearer 로.
    expect(fetchInitAt(0)).toEqual(
      expect.objectContaining({
        method: "GET",
        headers: {Authorization: "Bearer PII_LINE_ACCESS_TOKEN"},
        signal: expect.anything(),
      }),
    );

    // channel token 발급 — form body 3 필드 정확 · URL 에 시크릿 없음.
    const tokenInit = fetchInitAt(1);
    expect(tokenInit.method).toBe("POST");
    expect(tokenInit.headers).toEqual({
      "Content-Type": "application/x-www-form-urlencoded",
    });
    expect(
      Array.from((tokenInit.body as URLSearchParams).entries()),
    ).toEqual([
      ["grant_type", "client_credentials"],
      ["client_id", "fake-line-channel-id"],
      ["client_secret", "PII_LINE_CHANNEL_SECRET"],
    ]);
    expect(fetchMock.mock.calls[1][0]).not.toContain(
      "PII_LINE_CHANNEL_SECRET",
    );

    // deauthorize — channel token Bearer + JSON 본문 userAccessToken (A11).
    const deauthInit = fetchInitAt(2);
    expect(deauthInit.method).toBe("POST");
    expect(deauthInit.headers).toEqual({
      "Authorization": "Bearer PII_LINE_CHANNEL_TOKEN",
      "Content-Type": "application/json",
    });
    expect(deauthInit.body).toBe(
      "{\"userAccessToken\":\"PII_LINE_ACCESS_TOKEN\"}",
    );
    expect(JSON.parse(deauthInit.body as string)).toEqual({
      userAccessToken: "PII_LINE_ACCESS_TOKEN",
    });

    // 소유 대조는 프로필 userId 의 원장 문서 1건 read.
    expect(mockDocGet.mock.calls).toEqual([
      ["identity_index", "line:PII_LINE_USER_ID"],
    ]);
    // custom token 은 caller uid 로만 · developer claims 0.
    expect(mockCreateCustomToken.mock.calls).toEqual([[CALLER_UID]]);

    // 호출 순서: 소유 대조 < 발급 < 해제 < custom token (D-08 · D-07).
    const docOrder = mockDocGet.mock.invocationCallOrder[0];
    const issueOrder = fetchMock.mock.invocationCallOrder[1];
    const deauthOrder = fetchMock.mock.invocationCallOrder[2];
    const mintOrder = mockCreateCustomToken.mock.invocationCallOrder[0];
    expect(docOrder).toBeLessThan(issueOrder);
    expect(issueOrder).toBeLessThan(deauthOrder);
    expect(deauthOrder).toBeLessThan(mintOrder);
    expect(infoMock).toHaveBeenCalledWith(
      {event: "disconnect_line_succeeded", uid: CALLER_UID},
      expect.any(String),
    );
  });

  it("LR2: 소유 불일치 → caller_identity_mismatch · 발급 0", async () => {
    // 다른 계정 소유 · 원장 부재(연결되지 않은 신원) 모두 같은 거부다.
    for (const ownerUid of ["other-uid", undefined]) {
      fetchMock.mockReset();
      arrangeOwner(ownerUid);
      mockProfileOk();

      const err = await captureHttpsError(callDisconnect(LINE_DATA));
      expect(err.code).toBe("permission-denied");
      expect(err.message).toBe("errorReauthUserMismatch");
      expect(err.details).toEqual({reason: "caller_identity_mismatch"});
      // 프로필 1회뿐 — channel token 발급 · deauthorize 호출 0.
      expect(fetchMock).toHaveBeenCalledTimes(1);
      expect(fetchMock.mock.calls[0][0]).toBe(LINE_PROFILE_URL);
    }
    expect(mockCreateCustomToken).not.toHaveBeenCalled();
    expect(infoMock).not.toHaveBeenCalled();
  });

  it("LR3: deauthorize 400 → 이미 해제 · 성공 (D-14 멱등)", async () => {
    mockProfileOk();
    mockChannelTokenOk();
    mockFetchResponse(
      400,
      JSON.stringify({
        message: "Invalid access token for the target user",
      }),
    );

    await expect(callDisconnect(LINE_DATA)).resolves.toEqual({
      ok: true,
      customToken: "PII_MINTED_CUSTOM_TOKEN",
      uid: CALLER_UID,
    });
    expect(fetchMock).toHaveBeenCalledTimes(3);
    expect(mockCreateCustomToken.mock.calls).toEqual([[CALLER_UID]]);
    expect(infoMock).toHaveBeenCalledWith(
      {event: "disconnect_line_already_deauthorized", uid: CALLER_UID},
      expect.any(String),
    );
    expect(infoMock).toHaveBeenCalledWith(
      {event: "disconnect_line_succeeded", uid: CALLER_UID},
      expect.any(String),
    );
    expect(errorMock).not.toHaveBeenCalled();
  });
});

describe("disconnectLineProvider — caller 가드", () => {
  it("LR4: 익명 → anonymous_caller · fetch 0 · 원장 read 0", async () => {
    const err = await captureHttpsError(
      callDisconnect(LINE_DATA, anonymousCallerAuth("anon-uid")),
    );
    expect(err.code).toBe("failed-precondition");
    expect(err.message).toBe("errorAnonymousDisconnectNotAllowed");
    expect(err.details).toEqual({reason: "anonymous_caller"});
    expect(fetchMock).not.toHaveBeenCalled();
    expect(mockDocGet).not.toHaveBeenCalled();
    expect(mockCreateCustomToken).not.toHaveBeenCalled();
  });
});
