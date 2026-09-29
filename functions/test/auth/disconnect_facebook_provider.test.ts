/**
 * disconnectFacebookProvider onCall 테스트 (Phase 16.10 plan 02 · SOCL-13 ·
 * SOCL-15).
 *
 * **Mock 한계 — 실 단말 UAT (plan 10) 가 ground truth.** 본 파일은 Admin
 * `getUser` · 전역 `fetch`(Graph `DELETE /{asid}/permissions`)를 jest stub
 * 으로 흉내낸다. 「이미 끊긴 사용자」 의 실제 Graph 응답(A2)은 plan 10 UAT
 * 재진입이 관측했다 — 재삭제도 성공 본문이고 F15 가 그 실측 fixture 다. 오류
 * 응답 경로(iOS Limited Login 등)는 미실측이라 보수 매핑이다.
 *
 * 시나리오:
 *  - F1: 성공 `{success: true}` — getUser(uid) · 정확 URL · DELETE · Bearer
 *    헤더 · URL 에 시크릿 부재 · 성공 로그
 *  - F2: 성공 본문 `true` → 성공
 *  - F3: providerData 에 facebook.com 없음 → `{ok, disconnectedCount: 0}` ·
 *    fetch 0
 *  - F4: 익명 caller → failed-precondition(anonymous_caller) · getUser 0 ·
 *    fetch 0
 *  - F15: UAT1610 실측 재진입 — 재삭제도 성공 본문 → 둘 다 성공 (plan 11)
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

  // UAT1610 실측 fixture (plan 11 · D-14 · RESEARCH A2) — plan 10 Android
  // 실기기 UAT 재진입 순서를 그대로 재현한다.
  // 근거: uat-evidence/android-uat-16.10.md `## 2.` 첫 패스 23:44:28Z
  // `disconnect_facebook_succeeded`(1) → `## 4.` 재진입 23:52:58Z 호출 →
  // 23:53:00Z `disconnect_facebook_succeeded`(1) ·
  // `disconnect_facebook_delete_failed` 0 · `## 9.` 마커
  // `UAT1610_FB_REDELETE: success`.
  // 서버 분기 역추적 · 원시 본문 미로깅: Graph 원시 응답은 로그에 없다.
  // `disconnect_facebook_delete_failed` 없이 `succeeded` 가 나오는 분기는
  // `resp.ok` + `isGraphDeleteSuccess(body)` 하나뿐이다 → 이미 지운 권한의
  // 재삭제도 Graph 는 성공 본문으로 응답한다(오류 code/subcode 없음).
  // [ASSUMED] 성공 본문 모양 `{success: true}` · status 200 — 서버는 `true`
  // 와 `{success: true}` 를 모두 수용하고 어느 쪽인지 로그에 없다.
  // (이름 F15: `F14` 는 마지막 describe 의 PII sentinel 이 이미 쓴다.)
  it(
    "F15: UAT1610 실측 재진입 — 권한 삭제 뒤 재삭제도 성공 본문 → 둘 다 성공",
    async () => {
      arrangeProviderData([{providerId: "facebook.com", uid: FB_ASID}]);
      // 첫 패스: 권한 삭제 성공.
      mockGraphResponse(200, {success: true});
      // 재진입: 이미 지운 권한의 재삭제.
      mockGraphResponse(200, {success: true});

      await expect(callDisconnect()).resolves.toEqual({
        ok: true,
        disconnectedCount: 1,
      });
      await expect(callDisconnect()).resolves.toEqual({
        ok: true,
        disconnectedCount: 1,
      });

      // 두 호출 모두 같은 원장 asid 경로로 삭제를 시도한다.
      expect(fetchMock).toHaveBeenCalledTimes(2);
      expect(fetchMock.mock.calls[0][0]).toBe(GRAPH_PERMISSIONS_URL);
      expect(fetchMock.mock.calls[1][0]).toBe(GRAPH_PERMISSIONS_URL);
      // UAT 서버 로그 event 순서와 같다 — delete_failed 0.
      expect(infoMock.mock.calls.map((call) => call[0])).toEqual([
        {
          event: "disconnect_facebook_succeeded",
          uid: CALLER_UID,
          disconnectedCount: 1,
        },
        {
          event: "disconnect_facebook_succeeded",
          uid: CALLER_UID,
          disconnectedCount: 1,
        },
      ]);
      expect(errorMock).not.toHaveBeenCalled();
    },
  );

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

describe("disconnectFacebookProvider — 미인증", () => {
  it("F5: auth 부재 → unauthenticated · getUser 0 · fetch 0", async () => {
    const err = await captureHttpsError(callDisconnect(null));
    expect(err.code).toBe("unauthenticated");
    expect(err.message).toBe("errorUnauthenticated");
    expect(mockGetUser).not.toHaveBeenCalled();
    expect(fetchMock).not.toHaveBeenCalled();
  });
});

describe("disconnectFacebookProvider — Graph 오류 코드 매핑", () => {
  it("F6: 190(app token 무효) → provider_config 거부", async () => {
    arrangeProviderData([{providerId: "facebook.com", uid: FB_ASID}]);
    mockGraphResponse(401, {
      error: {code: 190, error_subcode: 460, message: "PII_FB_GRAPH_MESSAGE"},
    });

    const err = await captureHttpsError(callDisconnect());
    expect(err.code).toBe("failed-precondition");
    expect(err.message).toBe("errorProviderConfig");
    expect(err.details).toEqual({reason: "provider_config"});
    // 로그는 정수 코드 · status 만 — Graph message · asid 0.
    expect(errorMock).toHaveBeenCalledWith(
      {
        event: "disconnect_facebook_delete_failed",
        uid: CALLER_UID,
        status: 401,
        code: 190,
        subcode: 460,
      },
      expect.any(String),
    );
  });

  it("F7: 613(호출 한도) → resource-exhausted", async () => {
    arrangeProviderData([{providerId: "facebook.com", uid: FB_ASID}]);
    mockGraphResponse(400, {
      error: {code: 613, message: "PII_FB_GRAPH_MESSAGE"},
    });

    const err = await captureHttpsError(callDisconnect());
    expect(err.code).toBe("resource-exhausted");
    expect(err.message).toBe("errorTooManyRequests");
  });

  it.each([4, 17])(
    "F8: Graph code %i(호출 한도) → resource-exhausted",
    async (code) => {
      arrangeProviderData([{providerId: "facebook.com", uid: FB_ASID}]);
      mockGraphResponse(400, {
        error: {code, message: "PII_FB_GRAPH_MESSAGE"},
      });

      const err = await captureHttpsError(callDisconnect());
      expect(err.code).toBe("resource-exhausted");
      expect(err.message).toBe("errorTooManyRequests");
    },
  );

  // A2 보수 매핑 (RESEARCH Pitfall 7): 「이미 끊긴 사용자」 후보(100/33)는
  // 성공으로 매핑하지 않는다. plan 10 실측에서 재삭제는 이 오류가 아니라 성공
  // 본문이었다(F15) — 이 오류 코드 자체는 미실측이다.
  it("F9: 100/33(이미 끊김 후보) → unavailable · A2 보수", async () => {
    arrangeProviderData([{providerId: "facebook.com", uid: FB_ASID}]);
    mockGraphResponse(400, {
      error: {code: 100, error_subcode: 33, message: "PII_FB_GRAPH_MESSAGE"},
    });

    const err = await captureHttpsError(callDisconnect());
    expect(err.code).toBe("unavailable");
    expect(err.message).toBe("errorServiceUnavailable");
  });

  it("F10: fetch reject(TypeError) → unavailable · err.name 만 로그", async () => {
    arrangeProviderData([{providerId: "facebook.com", uid: FB_ASID}]);
    fetchMock.mockRejectedValueOnce(
      new TypeError("PII_FB_GRAPH_MESSAGE fetch failed"),
    );

    const err = await captureHttpsError(callDisconnect());
    expect(err.code).toBe("unavailable");
    expect(err.message).toBe("errorServiceUnavailable");
    expect(errorMock).toHaveBeenCalledWith(
      {
        event: "disconnect_facebook_delete_failed",
        uid: CALLER_UID,
        code: "TypeError",
      },
      expect.any(String),
    );
  });

  it("F11: 200 + {success: false} → unavailable", async () => {
    arrangeProviderData([{providerId: "facebook.com", uid: FB_ASID}]);
    mockGraphResponse(200, {success: false});

    const err = await captureHttpsError(callDisconnect());
    expect(err.code).toBe("unavailable");
    expect(err.message).toBe("errorServiceUnavailable");
    expect(errorMock).toHaveBeenCalledWith(
      {
        event: "disconnect_facebook_delete_failed",
        uid: CALLER_UID,
        status: 200,
        code: "unexpected_body",
      },
      expect.any(String),
    );
  });
});

describe("disconnectFacebookProvider — 원장 결함", () => {
  it("F12: asid 형식 밖(abc) → internal · fetch 0 · 값 로그 0", async () => {
    arrangeProviderData([{providerId: "facebook.com", uid: "abc"}]);

    const err = await captureHttpsError(callDisconnect());
    expect(err.code).toBe("internal");
    expect(err.message).toBe("errorUnknown");
    expect(fetchMock).not.toHaveBeenCalled();
    expect(errorMock).toHaveBeenCalledWith(
      {event: "disconnect_facebook_target_invalid", uid: CALLER_UID},
      expect.any(String),
    );
  });

  it("F13: getUser throw → internal · fingerprint 로그", async () => {
    mockGetUser.mockRejectedValueOnce(
      Object.assign(new Error("PII_FB_GRAPH_MESSAGE"), {
        code: "auth/internal-error",
      }),
    );

    const err = await captureHttpsError(callDisconnect());
    expect(err.code).toBe("internal");
    expect(err.message).toBe("errorUnknown");
    expect(fetchMock).not.toHaveBeenCalled();
    expect(errorMock).toHaveBeenCalledWith(
      {
        event: "disconnect_facebook_precheck_failed",
        uid: CALLER_UID,
        code: "auth/internal-error",
      },
      expect.any(String),
    );
  });
});

// 반드시 마지막 describe — 앞선 모든 케이스의 logger 호출을 검사한다.
describe("disconnectFacebookProvider — PII sentinel (F14)", () => {
  it("F14: 모든 logger 호출에 asid · 시크릿 · Graph message 0", () => {
    // 앞선 케이스들이 실제로 로그를 남겼는지부터 확인 (공허 통과 방지).
    expect(accumulatedLogCalls.length).toBeGreaterThan(8);
    const serialized = JSON.stringify(accumulatedLogCalls);
    for (const sentinel of PII_SENTINELS) {
      expect(serialized).not.toContain(sentinel);
    }
  });
});
