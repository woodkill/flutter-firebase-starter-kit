/**
 * disconnectFacebookProvider onCall 테스트 (Phase 16.10 plan 02 · SOCL-13 ·
 * SOCL-15).
 *
 * **Mock 한계 — 실 단말 UAT (plan 10) 가 ground truth.** 본 파일은 Admin
 * `getUser` · 전역 `fetch`(Graph `DELETE /{asid}/permissions`)를 jest stub
 * 으로 흉내낸다. 「이미 끊긴 사용자」 의 실제 Graph 응답(A2)은 UAT 재진입이
 * 관측하고 plan 11 이 실측 fixture 로 잠근다 — 그 전까지는 보수 매핑이다.
 *
 * 시나리오:
 *  - F1: 성공 `{success: true}` — getUser(uid) · 정확 URL · DELETE · Bearer
 *    헤더 · URL 에 시크릿 부재 · 성공 로그
 *  - F2: 성공 본문 `true` → 성공
 *  - F3: providerData 에 facebook.com 없음 → `{ok, disconnectedCount: 0}` ·
 *    fetch 0
 *  - F4: 익명 caller → failed-precondition(anonymous_caller) · getUser 0 ·
 *    fetch 0
 *
 * PII sentinel: Facebook asid(`9876543210123456`) · 앱 시크릿
 * (`PII_FB_APP_SECRET`) · Graph 응답 `message`(`PII_FB_GRAPH_MESSAGE`)는
 * HttpsError message/details 와 어느 logger 호출 인자에도 나오면 안 된다.
 */

// fetch mock — Graph 호출을 순서대로 stub.
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

// secret 주입 — 이름별 값. 앱 시크릿은 PII sentinel 값으로 둔다.
jest.mock("firebase-functions/params", () => ({
  defineSecret: (name: string) => ({
    value: () => {
      if (name === "KAKAO_ADMIN_KEY") return "PII_KAKAO_ADMIN_KEY";
      if (name === "FACEBOOK_APP_ID") return "fake-fb-app-id";
      if (name === "FACEBOOK_APP_SECRET") return "PII_FB_APP_SECRET";
      return `stub-${name}`;
    },
  }),
}));

// firebase-admin/auth — getUser 만 (providerData 원장).
const mockGetUser = jest.fn();
jest.mock("firebase-admin/auth", () => ({
  getAuth: jest.fn(() => ({getUser: mockGetUser})),
}));

// firebase-admin/firestore — Facebook 끊기는 Firestore 를 쓰지 않는다
// (호출 0 단언용 기록만).
const mockCollection = jest.fn();
jest.mock("firebase-admin/firestore", () => ({
  Firestore: class MockFirestore {},
  getFirestore: jest.fn(() => ({
    collection: (name: string) => {
      mockCollection(name);
      return {doc: (id?: string) => ({label: `${name}/${id ?? "?"}`})};
    },
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
const CALLER_UID = "caller-uid-facebook";

/** Facebook app-scoped ID fixture (PII). */
const FB_ASID = "9876543210123456";

/** Graph 권한 삭제 URL — asid 가 경로에 들어간다. */
const GRAPH_PERMISSIONS_URL =
  "https://graph.facebook.com/9876543210123456/permissions";

/** HttpsError message/details · logger 인자에 나오면 안 되는 값. */
const PII_SENTINELS = [
  FB_ASID,
  "PII_FB_APP_SECRET",
  "PII_FB_GRAPH_MESSAGE",
];

/** 모든 케이스의 logger 호출 누적 — 마지막 describe 의 PII sentinel 이 검사한다. */
const accumulatedLogCalls: unknown[][] = [];

beforeEach(() => {
  jest.clearAllMocks();
  fetchMock.mockReset();
  mockGetUser.mockReset();
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
 * Admin `getUser(uid).providerData` 를 구성한다.
 *
 * @param {Array<{providerId: string, uid: string}>} providerData 연결 목록.
 */
function arrangeProviderData(
  providerData: Array<{providerId: string; uid: string}>,
): void {
  mockGetUser.mockResolvedValue({uid: CALLER_UID, providerData});
}

/**
 * fetch mock — Graph 응답 1건.
 *
 * @param {number} status HTTP status.
 * @param {unknown} body `resp.json()` 결과.
 */
function mockGraphResponse(status: number, body: unknown): void {
  fetchMock.mockResolvedValueOnce({
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  });
}

/**
 * disconnectFacebookProvider 를 호출한다 (입력 0).
 *
 * @param {CallerAuthFixture | null} auth `request.auth` fixture
 *     (null = auth 부재).
 * @return {Promise<unknown>} callable 결과 promise.
 */
function callDisconnect(
  auth: CallerAuthFixture | null = signedInCallerAuth(
    CALLER_UID,
    "facebook.com",
  ),
): Promise<unknown> {
  const wrapped = testEnv.wrap(myFunctions.disconnectFacebookProvider);
  const request = auth === null ?
    {app: {appId: "test"}, data: {}} :
    {auth, app: {appId: "test"}, data: {}};
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

describe("disconnectFacebookProvider — 성공 · 0 건", () => {
  it("F1: {success: true} → 끊기 1 건 · Bearer 헤더 요청", async () => {
    arrangeProviderData([
      {providerId: "google.com", uid: "google-sub"},
      {providerId: "facebook.com", uid: FB_ASID},
    ]);
    mockGraphResponse(200, {success: true});

    await expect(callDisconnect()).resolves.toEqual({
      ok: true,
      disconnectedCount: 1,
    });

    // 대상은 caller uid 의 Admin 원장에서만 도출한다 (IDOR 차단).
    expect(mockGetUser).toHaveBeenCalledTimes(1);
    expect(mockGetUser).toHaveBeenCalledWith(CALLER_UID);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(fetchMock).toHaveBeenCalledWith(
      GRAPH_PERMISSIONS_URL,
      expect.objectContaining({
        method: "DELETE",
        headers: {Authorization: "Bearer fake-fb-app-id|PII_FB_APP_SECRET"},
        signal: expect.anything(),
      }),
    );
    // 앱 시크릿은 헤더로만 — URL 쿼리에 싣지 않는다 (T-16.10-07).
    const url = fetchMock.mock.calls[0][0] as string;
    expect(url).not.toContain("PII_FB_APP_SECRET");
    expect(url).not.toContain("?");
    expect(mockCollection).not.toHaveBeenCalled();
    expect(infoMock).toHaveBeenCalledWith(
      {
        event: "disconnect_facebook_succeeded",
        uid: CALLER_UID,
        disconnectedCount: 1,
      },
      expect.any(String),
    );
  });

  it("F2: 성공 본문 true → 성공", async () => {
    arrangeProviderData([{providerId: "facebook.com", uid: FB_ASID}]);
    mockGraphResponse(200, true);

    await expect(callDisconnect()).resolves.toEqual({
      ok: true,
      disconnectedCount: 1,
    });
    expect(errorMock).not.toHaveBeenCalled();
  });

  it("F3: facebook.com 연결 없음 → 끊기 0 건 · fetch 0", async () => {
    arrangeProviderData([{providerId: "google.com", uid: "google-sub"}]);

    await expect(callDisconnect()).resolves.toEqual({
      ok: true,
      disconnectedCount: 0,
    });
    expect(fetchMock).not.toHaveBeenCalled();
    expect(infoMock).toHaveBeenCalledWith(
      {
        event: "disconnect_facebook_succeeded",
        uid: CALLER_UID,
        disconnectedCount: 0,
      },
      expect.any(String),
    );
  });
});

describe("disconnectFacebookProvider — caller 가드", () => {
  it("F4: 익명 caller → anonymous_caller 거부 · getUser 0 · fetch 0", async () => {
    const err = await captureHttpsError(
      callDisconnect(anonymousCallerAuth("anon-uid")),
    );
    expect(err.code).toBe("failed-precondition");
    expect(err.message).toBe("errorAnonymousDisconnectNotAllowed");
    expect(err.details).toEqual({reason: "anonymous_caller"});
    expect(mockGetUser).not.toHaveBeenCalled();
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
