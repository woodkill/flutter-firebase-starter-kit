/**
 * linkNaverProvider onCall 테스트 (Phase 16.9 plan 01 · SOCL-12).
 *
 * **Mock 한계 — 실 단말 UAT (plan 04) 가 ground truth.** 본 파일은
 * Firebase Admin `verifyIdToken` · Firestore transaction · 전역 `fetch`
 * (NAVER token 교환 · `/v1/nid/me`) 를 jest stub 으로 흉내낸다. 실 NAVER
 * 서버 · App Check · cold start 경계는 실 단말 UAT 가 관측한다.
 * transaction 은 `test/mocks/ordered_transaction.ts` 의 순서 강제 tx 를
 * 주입해 write 뒤 `tx.get` 이 오면 `READ_AFTER_WRITE` 로 실패하게 만든다
 * (memory feedback_mock_transaction_constraint).
 *
 * 시나리오 (N1~N15):
 *  - N1: 1-tap 성공 — identity_index 신규 + linkedProviders arrayUnion
 *  - N2: 같은 uid 재연결 — idx 재작성 0 · users self-heal 만
 *  - N3: 타 uid 소유 — already-exists · write 0
 *  - N4: 웹 성공 — code 교환 → /v1/nid/me → 연결
 *  - N5: stale auth_time + 웹 — 재인증 요구 · code 교환 0
 *  - N6: revoked idToken + 웹 — 재인증 요구 · fingerprint 로그 · 교환 0
 *  - N7: 입력 모양 — 모양 부재 · 섞임 · state 부재 → invalid-argument
 *  - N8: 입력 위생 — CRLF · NUL · state 길이 상한 → invalid-argument
 *  - N9: request.auth 부재 → unauthenticated
 *  - N10: idToken uid ≠ caller uid → permission-denied
 *  - N11: 익명 caller → failed-precondition
 *  - N12: 프로필 검증 실패 매핑 (1-tap)
 *  - N13: code 교환 실패 매핑 (웹)
 *  - N14: transaction 일반 오류 → internal + fingerprint 로그
 *  - N15: PII sentinel — 모든 케이스의 logger 호출 누적 검사
 *  - N16~N19: provider 당 신원 1개 (16.9 review IN-03) — 같은 provider 다른
 *    신원 거부 · 같은 신원 멱등 · 다른 provider 허용 · 판별 불가 항목 거부.
 *    모든 tx.get 이 첫 tx.set 보다 앞선다 (순서 강제 tx + calls 단언).
 *
 * PII sentinel: caller idToken · access token · code · state · client secret ·
 * Naver 이메일 fixture 값(`PII_NAVER_*`) 은 어느 logger 호출 인자에도 나오면
 * 안 된다 (idToken 은 서버 docstring PII 금지 목록 첫 항목 — 16.9 review IN-01).
 */

// fetch mock — token 교환 · /v1/nid/me 호출을 순서대로 stub.
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

// firebase-admin/auth — verifyIdToken 자체 stub (자체 JWT decode 0).
const mockVerifyIdToken = jest.fn();
jest.mock("firebase-admin/auth", () => ({
  getAuth: jest.fn(() => ({
    verifyIdToken: mockVerifyIdToken,
  })),
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

// firebase-admin/firestore — 순서 강제 tx 주입.
// jest hoisting: factory 가 참조하는 바깥 변수는 이름이 `mock` 으로 시작해야
// 한다. 호출 시점에 지연 참조한다.
let mockOrdered: OrderedTxHandle;
jest.mock("firebase-admin/firestore", () => ({
  Firestore: class MockFirestore {},
  getFirestore: jest.fn(() => ({
    collection: (name: string) => ({
      doc: (id?: string) => ({label: name, id}),
    }),
    runTransaction: async (fn: (t: unknown) => Promise<unknown>) =>
      fn(mockOrdered.tx),
  })),
  FieldValue: {
    serverTimestamp: () => "MOCK_TIMESTAMP",
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
import {createOrderedTx} from "../mocks/ordered_transaction";
// eslint-disable-next-line import/first
import type {OrderedTxHandle} from "../mocks/ordered_transaction";
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

/** `/v1/nid/me` 가 돌려주는 Naver 사용자 id fixture. */
const NAVER_SUB = "naver-sub-1";

/** NAVER endpoint — 전역 fetch 호출 모양 단언용. */
const NAVER_TOKEN_URL = "https://nid.naver.com/oauth2.0/token";
const NAVER_PROFILE_URL = "https://openapi.naver.com/v1/nid/me";

/** 모든 케이스의 logger 호출 누적 — N15 PII sentinel 이 검사한다. */
const accumulatedLogCalls: unknown[][] = [];

/** 이번 케이스의 identity_index tx read 결과 (undefined = 문서 없음). */
let idxOwnerUid: string | undefined;

/**
 * 이번 케이스의 users/{uid} tx read 결과의 `linkedProviders`
 * (undefined = 필드 없음 · 16.9 review IN-03).
 */
let userLinkedProviders: unknown[] | undefined;

afterEach(() => {
  // beforeEach 의 clearAllMocks 가 지우기 전에 누적한다.
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
 * auth_time 신선 (now - 60s) — fresh ID Token fixture.
 * @return {number} auth_time epoch seconds.
 */
function freshAuthTime(): number {
  return Math.floor(Date.now() / 1000) - 60;
}

/**
 * auth_time 만료 (now - 600s = 10분) — stale ID Token fixture.
 * @return {number} auth_time epoch seconds.
 */
function staleAuthTime(): number {
  return Math.floor(Date.now() / 1000) - 600;
}

/**
 * fetch mock — 정상 200 응답.
 *
 * @param {object} body 응답 본문 stub.
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

/**
 * fetch mock — TimeoutError (5s `AbortSignal.timeout` 초과).
 */
function mockFetchTimeout() {
  const err = new Error("The operation was aborted due to timeout");
  (err as Error & {name: string}).name = "TimeoutError";
  fetchMock.mockRejectedValueOnce(err);
}

/** `/v1/nid/me` 정상 응답 — email 은 PII sentinel. */
function mockProfileOk() {
  mockFetchOk({
    resultcode: "00",
    message: "success",
    response: {id: NAVER_SUB, email: "PII_NAVER_EMAIL"},
  });
}

/**
 * linkNaverProvider 를 호출한다.
 *
 * @param {object} data callable 요청 data.
 * @param {CallerAuthFixture | null} auth `request.auth` fixture
 *     (null = auth 부재).
 * @return {Promise<unknown>} callable 결과 promise.
 */
function callLink(
  data: object,
  auth: CallerAuthFixture | null = signedInCallerAuth(CALLER_UID, "google.com"),
): Promise<unknown> {
  const wrapped = testEnv.wrap(myFunctions.linkNaverProvider);
  const request = auth === null ?
    {app: {appId: "test"}, data} :
    {auth, app: {appId: "test"}, data};
  return wrapped(request as never) as Promise<unknown>;
}

/** token 교환 정상 응답 — access_token 은 PII sentinel. */
function mockExchangeOk() {
  mockFetchOk({access_token: "PII_NAVER_ACCESS_TOKEN", expires_in: "3600"});
}

/** caller fresh idToken fixture — PII sentinel (N15 · 16.9 review IN-01). */
const ID_TOKEN = "PII_NAVER_ID_TOKEN";

/** 1-tap 모양 요청 data. */
const APP_DATA = {idToken: ID_TOKEN, accessToken: "PII_NAVER_ACCESS_TOKEN"};

/** 웹 모양 요청 data. */
const WEB_DATA = {
  idToken: ID_TOKEN,
  code: "PII_NAVER_CODE",
  state: "PII_NAVER_STATE",
};

beforeEach(() => {
  jest.clearAllMocks();
  fetchMock.mockReset();
  mockVerifyIdToken.mockReset();
  mockVerifyIdToken.mockResolvedValue({
    uid: CALLER_UID,
    auth_time: freshAuthTime(),
    firebase: {sign_in_provider: "google.com"},
  });
  idxOwnerUid = undefined;
  userLinkedProviders = undefined;
  mockOrdered = createOrderedTx((ref) =>
    (ref as {label: string}).label === "identity_index" ?
      {
        exists: idxOwnerUid !== undefined,
        data: () => ({firebaseUid: idxOwnerUid}),
      } :
      {
        exists: true,
        data: () =>
          userLinkedProviders === undefined ?
            {} :
            {linkedProviders: userLinkedProviders},
      },
  );
});

describe("linkNaverProvider — 1-tap 연결 · transaction (N1~N3)", () => {
  it("N1: 1-tap 성공 — idx 신규 + linkedProviders arrayUnion", async () => {
    mockProfileOk();

    const result = await callLink(APP_DATA);

    expect(result).toEqual({ok: true});
    expect(mockVerifyIdToken).toHaveBeenCalledWith(ID_TOKEN, true);
    // 전역 fetch 정확히 1회 — /v1/nid/me Bearer (교환 없음).
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(fetchMock).toHaveBeenCalledWith(
      NAVER_PROFILE_URL,
      expect.objectContaining({
        method: "GET",
        headers: expect.objectContaining({
          Authorization: "Bearer PII_NAVER_ACCESS_TOKEN",
        }),
        signal: expect.anything(),
      }),
    );
    // read 2 (idx + users — 16.9 review IN-03) → set 2 (idx 신규 + users
    // merge) — 순서 강제 tx 통과.
    expect(mockOrdered.calls).toEqual(["get", "get", "set", "set"]);
    expect(mockOrdered.sets[0].ref).toEqual({
      label: "identity_index",
      id: `naver:${NAVER_SUB}`,
    });
    expect(mockOrdered.sets[0].data).toMatchObject({
      firebaseUid: CALLER_UID,
      provider: "naver",
      providerUserId: NAVER_SUB,
    });
    const usersData = mockOrdered.sets[1].data as {
      linkedProviders: unknown;
      providerLinkedAt: Record<string, unknown>;
    };
    expect(mockOrdered.sets[1].ref).toEqual({label: "users", id: CALLER_UID});
    expect(usersData.linkedProviders).toEqual({
      mockArrayUnion: {providerId: "naver", providerUserId: NAVER_SUB},
    });
    expect(usersData.providerLinkedAt.naver).toBe("MOCK_TIMESTAMP");
    // 연결은 가입 이벤트가 아니다 (Phase 16.7 D-14 · D-18 · C-06).
    expect(usersData).not.toHaveProperty("signUpProviderId");
    expect(infoMock).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "link_naver_provider_succeeded",
        uid: CALLER_UID,
        path: "link_app",
      }),
      expect.any(String),
    );
  });

  it("N2: 같은 uid 재연결 — idx 재작성 0 · users self-heal 만", async () => {
    idxOwnerUid = CALLER_UID;
    mockProfileOk();

    await expect(callLink(APP_DATA)).resolves.toEqual({ok: true});

    expect(mockOrdered.calls).toEqual(["get", "get", "set"]);
    expect(mockOrdered.sets[0].ref).toEqual({label: "users", id: CALLER_UID});
  });

  it("N3: 타 uid 소유 — already-exists · write 0", async () => {
    idxOwnerUid = "other-owner-uid";
    mockProfileOk();

    const promise = callLink(APP_DATA);
    await expect(promise).rejects.toBeInstanceOf(HttpsError);
    await expect(promise).rejects.toMatchObject({
      code: "already-exists",
      message: "errorAccountAlreadyLinked",
    });
    expect(mockOrdered.calls).toEqual(["get", "get"]);
    expect(mockOrdered.sets).toHaveLength(0);
    expect(infoMock).not.toHaveBeenCalled();
  });
});

describe("linkNaverProvider — 웹 연결 · code 교환 후순위 (N4~N6)", () => {
  it("N4: 웹 성공 — code 교환 → /v1/nid/me → 연결", async () => {
    mockExchangeOk();
    mockProfileOk();

    await expect(callLink(WEB_DATA)).resolves.toEqual({ok: true});

    // 교환 → 프로필 순서로 전역 fetch 2회.
    expect(fetchMock).toHaveBeenCalledTimes(2);
    const [exchangeUrl, exchangeInit] = fetchMock.mock.calls[0] as [
      string,
      {method: string; body: unknown},
    ];
    expect(exchangeUrl).toBe(NAVER_TOKEN_URL);
    expect(exchangeInit).toEqual(expect.objectContaining({method: "POST"}));
    const form = String(exchangeInit.body);
    expect(form).toContain("grant_type=authorization_code");
    expect(form).toContain("client_id=fake-naver-client-id");
    expect(form).toContain("code=PII_NAVER_CODE");
    expect(form).toContain("state=PII_NAVER_STATE");
    expect(fetchMock.mock.calls[1][0]).toBe(NAVER_PROFILE_URL);
    expect(fetchMock.mock.calls[1][1]).toEqual(
      expect.objectContaining({
        method: "GET",
        headers: expect.objectContaining({
          Authorization: "Bearer PII_NAVER_ACCESS_TOKEN",
        }),
      }),
    );
    expect(mockOrdered.calls).toEqual(["get", "get", "set", "set"]);
    expect(infoMock).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "link_naver_provider_succeeded",
        uid: CALLER_UID,
        path: "link_web",
      }),
      expect.any(String),
    );
  });

  it("N5: stale auth_time + 웹 — 재인증 요구 · code 교환 0", async () => {
    mockVerifyIdToken.mockResolvedValue({
      uid: CALLER_UID,
      auth_time: staleAuthTime(),
      firebase: {sign_in_provider: "google.com"},
    });

    await expect(callLink(WEB_DATA)).rejects.toMatchObject({
      code: "unauthenticated",
      message: "errorReauthenticationRequired",
      details: {reason: "reauthentication_required"},
    });
    // 1회용 code 미소비 — 교환 · 프로필 fetch 모두 0 (D-01 흐름 1 · D-04).
    expect(fetchMock).not.toHaveBeenCalled();
    expect(mockOrdered.calls).toEqual([]);
  });

  it("N6: revoked idToken + 웹 — 재인증 요구 · fingerprint 로그 · 교환 0", async () => {
    // firebase-admin 은 code 프로퍼티를 가진 Error 를 던진다 — fingerprintError
    // 는 Error 인스턴스일 때만 code 를 읽는다.
    mockVerifyIdToken.mockRejectedValue(
      Object.assign(new Error("revoked"), {code: "auth/id-token-revoked"}),
    );

    await expect(callLink(WEB_DATA)).rejects.toMatchObject({
      code: "unauthenticated",
      message: "errorReauthenticationRequired",
      details: {reason: "reauthentication_required"},
    });
    expect(warnMock).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "link_naver_id_token_verify_failed",
        code: "auth/id-token-revoked",
      }),
      expect.any(String),
    );
    expect(fetchMock).not.toHaveBeenCalled();
    expect(mockOrdered.calls).toEqual([]);
  });
});

describe("linkNaverProvider — 입력 모양 · 위생 (N7 · N8)", () => {
  it("N7: (a) 모양 부재 {idToken} — invalid-argument · Admin Auth 0", async () => {
    await expect(callLink({idToken: ID_TOKEN})).rejects.toMatchObject({
      code: "invalid-argument",
      message: "errorInvalidArgument",
    });
    expect(mockVerifyIdToken).not.toHaveBeenCalled();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("N7: (b) 모양 섞임 {accessToken, code, state} — 거부", async () => {
    await expect(
      callLink({...WEB_DATA, accessToken: "PII_NAVER_ACCESS_TOKEN"}),
    ).rejects.toMatchObject({
      code: "invalid-argument",
      message: "errorInvalidArgument",
    });
    expect(mockVerifyIdToken).not.toHaveBeenCalled();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("N7: (c) 웹 모양 state 부재 {idToken, code} — invalid-argument", async () => {
    await expect(
      callLink({idToken: ID_TOKEN, code: "PII_NAVER_CODE"}),
    ).rejects.toMatchObject({
      code: "invalid-argument",
      message: "errorInvalidArgument",
    });
    expect(mockVerifyIdToken).not.toHaveBeenCalled();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it.each([
    ["accessToken CRLF", {idToken: ID_TOKEN, accessToken: "a\r\nb"}],
    ["code NUL", {...WEB_DATA, code: "c\x00"}],
    ["state 513자", {...WEB_DATA, state: "s".repeat(513)}],
  ])("N8: 위생 — %s → invalid-argument", async (_label, data) => {
    await expect(callLink(data)).rejects.toMatchObject({
      code: "invalid-argument",
      message: "errorInvalidArgument",
    });
    expect(mockVerifyIdToken).not.toHaveBeenCalled();
    expect(fetchMock).not.toHaveBeenCalled();
  });
});

describe("linkNaverProvider — caller 검사 (N9~N11)", () => {
  it("N9: request.auth 부재 — unauthenticated", async () => {
    await expect(callLink(APP_DATA, null)).rejects.toMatchObject({
      code: "unauthenticated",
      message: "errorUnauthenticated",
    });
    expect(mockVerifyIdToken).not.toHaveBeenCalled();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("N10: idToken uid ≠ caller uid — permission-denied", async () => {
    mockVerifyIdToken.mockResolvedValue({
      uid: "someone-else",
      auth_time: freshAuthTime(),
      firebase: {sign_in_provider: "google.com"},
    });

    await expect(callLink(WEB_DATA)).rejects.toMatchObject({
      code: "permission-denied",
      message: "errorUnauthenticated",
    });
    expect(fetchMock).not.toHaveBeenCalled();
    expect(mockOrdered.calls).toEqual([]);
  });

  it("N11: 익명 caller — failed-precondition · fetch 0", async () => {
    mockVerifyIdToken.mockResolvedValue({
      uid: CALLER_UID,
      auth_time: freshAuthTime(),
      firebase: {sign_in_provider: "anonymous"},
    });

    await expect(
      callLink(WEB_DATA, anonymousCallerAuth(CALLER_UID)),
    ).rejects.toMatchObject({
      code: "failed-precondition",
      message: "errorAnonymousLinkNotAllowed",
    });
    expect(fetchMock).not.toHaveBeenCalled();
    expect(mockOrdered.calls).toEqual([]);
  });
});

describe("linkNaverProvider — 실패 매핑 WR-01 (N12 · N13)", () => {
  it.each([
    [
      "401",
      () => mockFetchStatus(401),
      "unauthenticated",
      "errorInvalidCredentials",
      warnMock,
      {event: "naver_verify_unauthenticated", path: "link_app", status: 401},
    ],
    [
      "503",
      () => mockFetchStatus(503),
      "unavailable",
      "errorServiceUnavailable",
      warnMock,
      {event: "naver_verify_unavailable", path: "link_app", status: 503},
    ],
    [
      "timeout",
      () => mockFetchTimeout(),
      "unavailable",
      "errorServiceUnavailable",
      warnMock,
      {event: "naver_fetch_failed", path: "link_app", code: "TimeoutError"},
    ],
    [
      "resultcode 024",
      () => mockFetchOk({resultcode: "024"}),
      "unauthenticated",
      "errorInvalidCredentials",
      warnMock,
      {
        event: "naver_resultcode_non_success",
        path: "link_app",
        resultcode: "024",
      },
    ],
    [
      "id 부재",
      () => mockFetchOk({resultcode: "00", response: {}}),
      "unauthenticated",
      "errorInvalidCredentials",
      errorMock,
      {event: "naver_response_id_missing", path: "link_app"},
    ],
  ])(
    "N12: 프로필 %s — 매핑 · 연결 tx 0",
    async (_label, arrange, code, message, logMockFn, logPayload) => {
      arrange();

      const err = await callLink(APP_DATA).catch((e: unknown) => e);
      expect(err).toMatchObject({code, message});
      // 16.9 review WR-01: IdP 거부 · 도달 실패는 재인증 reason 을 싣지
      // 않는다 — client 는 재로그인이 아니라 일시 오류로 안내한다.
      expect((err as HttpsError).details).toBeUndefined();
      expect(logMockFn).toHaveBeenCalledWith(
        expect.objectContaining(logPayload),
        expect.any(String),
      );
      expect(fetchMock).toHaveBeenCalledTimes(1);
      expect(mockOrdered.calls).toEqual([]);
    },
  );

  it.each([
    [
      "교환 401",
      () => mockFetchStatus(401),
      "unauthenticated",
      "errorInvalidCredentials",
      {event: "naver_web_token_exchange_failed", status: 401},
    ],
    [
      "교환 본문 error",
      () => mockFetchOk({error: "invalid_grant"}),
      "unauthenticated",
      "errorInvalidCredentials",
      {event: "naver_web_token_error_response", error: "invalid_grant"},
    ],
    [
      "교환 timeout",
      () => mockFetchTimeout(),
      "unavailable",
      "errorServiceUnavailable",
      {event: "naver_web_token_exchange_failed", code: "TimeoutError"},
    ],
  ])(
    "N13: 웹 %s — 매핑 · 프로필 미호출",
    async (_label, arrange, code, message, logPayload) => {
      arrange();

      const err = await callLink(WEB_DATA).catch((e: unknown) => e);
      expect(err).toMatchObject({code, message});
      // 16.9 review WR-01: code 교환 거부(`invalid_grant` 등)도 재인증
      // reason 이 없다 — Firebase 세션은 정상이다.
      expect((err as HttpsError).details).toBeUndefined();
      expect(warnMock).toHaveBeenCalledWith(
        expect.objectContaining(logPayload),
        expect.any(String),
      );
      // 교환 1회뿐 — /v1/nid/me 는 부르지 않는다.
      expect(fetchMock).toHaveBeenCalledTimes(1);
      expect(fetchMock.mock.calls[0][0]).toBe(NAVER_TOKEN_URL);
      expect(mockOrdered.calls).toEqual([]);
    },
  );
});

describe("linkNaverProvider — transaction 오류 (N14)", () => {
  it("N14: tx 일반 Error — internal + link_transaction_failed", async () => {
    mockOrdered = createOrderedTx(() => {
      throw new Error("tx boom");
    });
    mockProfileOk();

    await expect(callLink(APP_DATA)).rejects.toMatchObject({
      code: "internal",
      message: "errorUnknown",
    });
    expect(errorMock).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "link_transaction_failed",
        uid: CALLER_UID,
        code: "Error",
      }),
      expect.any(String),
    );
    expect(infoMock).not.toHaveBeenCalled();
  });
});

describe("linkNaverProvider — provider 당 신원 1개 (N16~N19 · IN-03)", () => {
  it.each([
    ["연결 신원", {providerId: "naver", providerUserId: "naver-sub-OTHER"}],
    // 가입 경로(`resolveIdentity` 신규 등록)도 같은 모양의 항목을 쓴다.
    ["가입 신원", {providerId: "naver", providerUserId: "naver-signup-sub"}],
  ])(
    "N16: 같은 provider 의 다른 %s 이미 연결 — already-exists · reason · write 0",
    async (_label, entry) => {
      userLinkedProviders = [{providerId: "google.com"}, entry];
      mockProfileOk();

      const err = await callLink(APP_DATA).catch((e: unknown) => e);
      expect(err).toBeInstanceOf(HttpsError);
      expect(err).toMatchObject({
        code: "already-exists",
        message: "errorProviderAlreadyLinked",
        details: {reason: "provider_already_linked"},
      });
      // 모든 read 가 먼저 · write 0.
      expect(mockOrdered.calls).toEqual(["get", "get"]);
      expect(mockOrdered.sets).toHaveLength(0);
      expect(warnMock).toHaveBeenCalledWith(
        {
          event: "link_provider_already_linked",
          uid: CALLER_UID,
          provider: "naver",
        },
        expect.any(String),
      );
      expect(infoMock).not.toHaveBeenCalled();
    },
  );

  it("N16: 다른 uid 소유 거부는 reason 없는 errorAccountAlreadyLinked 그대로", async () => {
    idxOwnerUid = "other-owner-uid";
    userLinkedProviders = [
      {providerId: "naver", providerUserId: "naver-sub-OTHER"},
    ];
    mockProfileOk();

    const err = await callLink(APP_DATA).catch((e: unknown) => e);
    expect(err).toMatchObject({
      code: "already-exists",
      message: "errorAccountAlreadyLinked",
    });
    expect((err as HttpsError).details).toBeUndefined();
    expect(mockOrdered.sets).toHaveLength(0);
  });

  it("N17: 같은 신원 재연결 — 멱등 성공 · idx 재작성 0 (WR-10 유지)", async () => {
    idxOwnerUid = CALLER_UID;
    userLinkedProviders = [{providerId: "naver", providerUserId: NAVER_SUB}];
    mockProfileOk();

    await expect(callLink(APP_DATA)).resolves.toEqual({ok: true});
    expect(mockOrdered.calls).toEqual(["get", "get", "set"]);
    expect(mockOrdered.sets[0].ref).toEqual({label: "users", id: CALLER_UID});
  });

  it("N17: idx 가 내 소유면 다른 naver 항목이 남아 있어도 재연결은 멱등", async () => {
    // 이 가드 이전에 생긴 다중 신원 상태 — 새 신원 추가가 아니므로 거부 0.
    idxOwnerUid = CALLER_UID;
    userLinkedProviders = [
      {providerId: "naver", providerUserId: "naver-sub-OTHER"},
      {providerId: "naver", providerUserId: NAVER_SUB},
    ];
    mockProfileOk();

    await expect(callLink(APP_DATA)).resolves.toEqual({ok: true});
    expect(mockOrdered.calls).toEqual(["get", "get", "set"]);
  });

  it("N18: 다른 provider 만 연결돼 있으면 허용 — idx 신규 + users merge", async () => {
    userLinkedProviders = [
      {providerId: "kakao", providerUserId: "kakao-sub-1"},
      {providerId: "line", providerUserId: "line-sub-1"},
    ];
    mockExchangeOk();
    mockProfileOk();

    await expect(callLink(WEB_DATA)).resolves.toEqual({ok: true});
    expect(mockOrdered.calls).toEqual(["get", "get", "set", "set"]);
    expect(mockOrdered.sets[0].ref).toEqual({
      label: "identity_index",
      id: `naver:${NAVER_SUB}`,
    });
  });

  it("N19: providerUserId 판별 불가 naver 항목 — fail-closed 거부", async () => {
    userLinkedProviders = [{providerId: "naver"}];
    mockProfileOk();

    await expect(callLink(APP_DATA)).rejects.toMatchObject({
      code: "already-exists",
      details: {reason: "provider_already_linked"},
    });
    expect(mockOrdered.sets).toHaveLength(0);
  });
});

// 반드시 마지막 describe — 앞선 모든 케이스의 logger 호출을 검사한다.
describe("linkNaverProvider — PII sentinel (N15)", () => {
  it("N15: 모든 케이스의 logger 호출에 PII fixture 값 0", () => {
    // 앞선 케이스들이 실제로 로그를 남겼는지부터 확인 (공허 통과 방지).
    expect(accumulatedLogCalls.length).toBeGreaterThan(10);
    const serialized = JSON.stringify(accumulatedLogCalls);
    for (const sentinel of [
      "PII_NAVER_ID_TOKEN",
      "PII_NAVER_ACCESS_TOKEN",
      "PII_NAVER_CODE",
      "PII_NAVER_STATE",
      "PII_NAVER_SECRET",
      "PII_NAVER_EMAIL",
    ]) {
      expect(serialized).not.toContain(sentinel);
    }
  });
});
