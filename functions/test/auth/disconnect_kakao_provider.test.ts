/**
 * disconnectKakaoProvider onCall 테스트 (Phase 16.10 plan 02 · SOCL-13 ·
 * SOCL-15).
 *
 * **Mock 한계 — 실 단말 UAT (plan 10) 가 ground truth.** 본 파일은 Firestore
 * `identity_index` where 조회 · 전역 `fetch`(Kakao `/v1/user/unlink`)를 jest
 * stub 으로 흉내낸다. 실 Kakao 응답 코드(`-101` 멱등 등)는 UAT 가 관측하고
 * plan 11 이 실측 fixture 로 잠근다.
 *
 * 시나리오:
 *  - K1: 성공 — where 인자 · fetch 모양(URL · POST · KakaoAK 헤더 · form
 *    body 문자열 그대로) · 성공 로그
 *  - K2: `-101`(이미 끊긴 사용자) → 성공 · 멱등 (D-14)
 *  - K3: 익명 caller → failed-precondition(anonymous_caller) · 조회 0 · fetch 0
 *  - K14: UAT1610 실측 재진입 — 200 뒤 재호출 -101 → 둘 다 성공 (plan 11)
 *
 * PII sentinel: Kakao 회원번호(`1234567890123456789`) · 어드민 키
 * (`PII_KAKAO_ADMIN_KEY`) · Kakao 응답 `msg`(`PII_KAKAO_MSG`)는 HttpsError
 * message/details 와 어느 logger 호출 인자에도 나오면 안 된다.
 */

// fetch mock — Kakao unlink 호출을 순서대로 stub.
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

// secret 주입 — 이름별 값. 시크릿은 PII sentinel 값으로 둔다.
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

// firebase-admin/auth — Kakao 끊기는 Admin Auth 를 쓰지 않는다 (호출 0 단언용).
const mockGetUser = jest.fn();
jest.mock("firebase-admin/auth", () => ({
  getAuth: jest.fn(() => ({getUser: mockGetUser})),
}));

// firebase-admin/firestore — where 가 2회 chain 된다. 호출 인자를 기록한다.
// jest hoisting: factory 가 참조하는 바깥 변수는 이름이 `mock` 으로 시작해야
// 한다. 모두 호출 시점에 지연 참조한다.
const mockWhere = jest.fn();
const mockWhereGet = jest.fn();
jest.mock("firebase-admin/firestore", () => {
  type MockQuery = {
    where: (...args: unknown[]) => MockQuery;
    get: () => unknown;
  };
  return {
    Firestore: class MockFirestore {},
    getFirestore: jest.fn(() => ({
      collection: (name: string) => {
        const query: MockQuery = {
          where: (...args: unknown[]) => {
            mockWhere(name, ...args);
            return query;
          },
          get: () => mockWhereGet(),
        };
        return {
          doc: (id?: string) => ({label: `${name}/${id ?? "?"}`}),
          where: query.where,
        };
      },
    })),
    FieldValue: {
      serverTimestamp: () => "MOCK_TIMESTAMP",
      delete: () => "MOCK_DELETE",
      arrayUnion: (item: unknown) => ({mockArrayUnion: item}),
    },
  };
});

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
const CALLER_UID = "caller-uid-kakao";

/** Kakao 회원번호 fixture — Long 정밀도 밖 19자리 (파기 대상 PII). */
const KAKAO_USER_ID = "1234567890123456789";

/** Kakao unlink endpoint — fetch 호출 모양 단언용. */
const KAKAO_UNLINK_URL = "https://kapi.kakao.com/v1/user/unlink";

/** HttpsError message/details · logger 인자에 나오면 안 되는 값. */
const PII_SENTINELS = [
  KAKAO_USER_ID,
  "PII_KAKAO_ADMIN_KEY",
  "PII_KAKAO_MSG",
];

/** 모든 케이스의 logger 호출 누적 — 마지막 describe 의 PII sentinel 이 검사한다. */
const accumulatedLogCalls: unknown[][] = [];

beforeEach(() => {
  jest.clearAllMocks();
  fetchMock.mockReset();
  mockWhereGet.mockReset();
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
 * `identity_index` where 조회 결과를 구성한다.
 *
 * @param {Array<unknown>} providerUserIds 문서별 `providerUserId` 값
 *     (문자열이 아닌 값 = 데이터 결함 fixture).
 */
function arrangeKakaoIdentities(providerUserIds: unknown[]): void {
  mockWhereGet.mockResolvedValue({
    docs: providerUserIds.map((providerUserId, i) => ({
      id: `kakao:doc-${i}`,
      data: () => ({
        firebaseUid: CALLER_UID,
        provider: "kakao",
        providerUserId,
      }),
    })),
  });
}

/**
 * fetch mock — Kakao 응답 1건.
 *
 * @param {number} status HTTP status.
 * @param {unknown} body `resp.json()` 결과.
 */
function mockKakaoResponse(status: number, body: unknown): void {
  fetchMock.mockResolvedValueOnce({
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  });
}

/**
 * disconnectKakaoProvider 를 호출한다 (입력 0).
 *
 * @param {CallerAuthFixture | null} auth `request.auth` fixture
 *     (null = auth 부재).
 * @return {Promise<unknown>} callable 결과 promise.
 */
function callDisconnect(
  auth: CallerAuthFixture | null = signedInCallerAuth(CALLER_UID),
): Promise<unknown> {
  const wrapped = testEnv.wrap(myFunctions.disconnectKakaoProvider);
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

describe("disconnectKakaoProvider — 성공 · 멱등", () => {
  it("K1: 연결 끊기 200 → {ok, disconnectedCount: 1} · 원장 조회 · 요청 모양", async () => {
    arrangeKakaoIdentities([KAKAO_USER_ID]);
    mockKakaoResponse(200, {id: KAKAO_USER_ID});

    await expect(callDisconnect()).resolves.toEqual({
      ok: true,
      disconnectedCount: 1,
    });

    // 대상은 caller uid 의 Kakao 원장 문서에서만 도출한다 (IDOR 차단).
    expect(mockWhere.mock.calls).toEqual([
      ["identity_index", "firebaseUid", "==", CALLER_UID],
      ["identity_index", "provider", "==", "kakao"],
    ]);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(fetchMock).toHaveBeenCalledWith(
      KAKAO_UNLINK_URL,
      expect.objectContaining({
        method: "POST",
        headers: expect.objectContaining({
          "Authorization": "KakaoAK PII_KAKAO_ADMIN_KEY",
          "Content-Type": "application/x-www-form-urlencoded",
        }),
        signal: expect.anything(),
      }),
    );
    // 회원번호는 숫자 변환 없이 문자열 그대로 전송된다 (Long 정밀도 보존).
    const body = fetchBodyAt(0);
    expect(body.get("target_id")).toBe("1234567890123456789");
    expect(body.get("target_id_type")).toBe("user_id");
    expect(mockGetUser).not.toHaveBeenCalled();
    expect(infoMock).toHaveBeenCalledWith(
      {
        event: "disconnect_kakao_succeeded",
        uid: CALLER_UID,
        disconnectedCount: 1,
      },
      expect.any(String),
    );
  });

  it("K2: -101(이미 끊긴 사용자) → 성공 · 멱등 로그", async () => {
    arrangeKakaoIdentities([KAKAO_USER_ID]);
    mockKakaoResponse(400, {code: -101, msg: "PII_KAKAO_MSG"});

    await expect(callDisconnect()).resolves.toEqual({
      ok: true,
      disconnectedCount: 1,
    });
    expect(infoMock).toHaveBeenCalledWith(
      {event: "disconnect_kakao_already_unlinked", uid: CALLER_UID},
      expect.any(String),
    );
    expect(errorMock).not.toHaveBeenCalled();
  });

  // UAT1610 실측 fixture (plan 11 · D-14 · RESEARCH A10) — plan 10 Android
  // 실기기 UAT 재진입 순서를 그대로 재현한다.
  // 근거: uat-evidence/android-uat-16.10.md `## 2.` 첫 패스 23:44:24Z
  // `disconnect_kakao_succeeded`(1) → `## 4.` 재진입 23:52:58Z 호출 →
  // 23:52:59Z `disconnect_kakao_already_unlinked` + 같은 ms
  // `disconnect_kakao_succeeded`(1) · `## 9.` 마커
  // `UAT1610_REENTRY_KAKAO: already_unlinked`.
  // 서버 분기 역추적 · 원시 본문 미로깅: Kakao 원시 응답은 로그에 없다.
  // `disconnect_kakao_already_unlinked` 를 내는 분기는 `!resp.ok` + 본문
  // `code === -101` 하나뿐이므로 fixture code = -101 이다.
  // [ASSUMED] -101 응답의 HTTP status 400 — 서버 분기가 status 를 읽지 않고
  // 로그에도 없다(K2 값 재사용). 첫 호출 성공 본문 `{id}` 도 로그에 없다
  // (`resp.ok` 분기는 본문을 읽지 않는다).
  it(
    "K14: UAT1610 실측 재진입 — 200 뒤 재호출 -101 → 둘 다 성공 · 멱등",
    async () => {
      arrangeKakaoIdentities([KAKAO_USER_ID]);
      // 첫 패스: 연결 끊기 성공.
      mockKakaoResponse(200, {id: KAKAO_USER_ID});
      // 재진입: 이미 끊긴 사용자.
      mockKakaoResponse(400, {code: -101, msg: "PII_KAKAO_MSG"});

      await expect(callDisconnect()).resolves.toEqual({
        ok: true,
        disconnectedCount: 1,
      });
      await expect(callDisconnect()).resolves.toEqual({
        ok: true,
        disconnectedCount: 1,
      });

      // 두 호출 모두 같은 원장 회원번호로 끊기를 시도한다.
      expect(fetchMock).toHaveBeenCalledTimes(2);
      expect(fetchBodyAt(0).get("target_id")).toBe(KAKAO_USER_ID);
      expect(fetchBodyAt(1).get("target_id")).toBe(KAKAO_USER_ID);
      // UAT 서버 로그 event 순서와 같다.
      expect(infoMock.mock.calls.map((call) => call[0])).toEqual([
        {
          event: "disconnect_kakao_succeeded",
          uid: CALLER_UID,
          disconnectedCount: 1,
        },
        {event: "disconnect_kakao_already_unlinked", uid: CALLER_UID},
        {
          event: "disconnect_kakao_succeeded",
          uid: CALLER_UID,
          disconnectedCount: 1,
        },
      ]);
      expect(errorMock).not.toHaveBeenCalled();
    },
  );
});

describe("disconnectKakaoProvider — caller 가드", () => {
  it("K3: 익명 caller → anonymous_caller 거부 · 조회 0 · fetch 0", async () => {
    const err = await captureHttpsError(
      callDisconnect(anonymousCallerAuth("anon-uid")),
    );
    expect(err.code).toBe("failed-precondition");
    expect(err.message).toBe("errorAnonymousDisconnectNotAllowed");
    expect(err.details).toEqual({reason: "anonymous_caller"});
    expect(mockWhere).not.toHaveBeenCalled();
    expect(fetchMock).not.toHaveBeenCalled();
  });
});

describe("disconnectKakaoProvider — 미인증 · 0 건", () => {
  it("K4: request.auth 부재 → unauthenticated · 조회 0 · fetch 0", async () => {
    const err = await captureHttpsError(callDisconnect(null));
    expect(err.code).toBe("unauthenticated");
    expect(err.message).toBe("errorUnauthenticated");
    expect(mockWhere).not.toHaveBeenCalled();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("K5: Kakao 신원 없음 → {ok, disconnectedCount: 0} · fetch 0", async () => {
    arrangeKakaoIdentities([]);

    await expect(callDisconnect()).resolves.toEqual({
      ok: true,
      disconnectedCount: 0,
    });
    expect(fetchMock).not.toHaveBeenCalled();
    expect(infoMock).toHaveBeenCalledWith(
      {
        event: "disconnect_kakao_succeeded",
        uid: CALLER_UID,
        disconnectedCount: 0,
      },
      expect.any(String),
    );
  });
});

describe("disconnectKakaoProvider — Kakao 오류 코드 매핑", () => {
  it("K6: -401(어드민 키 무효) → failed-precondition(provider_config)", async () => {
    arrangeKakaoIdentities([KAKAO_USER_ID]);
    mockKakaoResponse(401, {code: -401, msg: "PII_KAKAO_MSG"});

    const err = await captureHttpsError(callDisconnect());
    expect(err.code).toBe("failed-precondition");
    expect(err.message).toBe("errorProviderConfig");
    expect(err.details).toEqual({reason: "provider_config"});
    // 로그는 정수 코드 · status 만 — msg 본문 · 회원번호 0.
    expect(errorMock).toHaveBeenCalledWith(
      {
        event: "disconnect_kakao_unlink_failed",
        uid: CALLER_UID,
        status: 401,
        code: -401,
      },
      expect.any(String),
    );
  });

  it("K7: -3(앱 설정 미허용) → failed-precondition(provider_config)", async () => {
    arrangeKakaoIdentities([KAKAO_USER_ID]);
    mockKakaoResponse(400, {code: -3, msg: "PII_KAKAO_MSG"});

    const err = await captureHttpsError(callDisconnect());
    expect(err.code).toBe("failed-precondition");
    expect(err.message).toBe("errorProviderConfig");
    expect(err.details).toEqual({reason: "provider_config"});
  });

  it("K8: -10(사용량 제한) → resource-exhausted", async () => {
    arrangeKakaoIdentities([KAKAO_USER_ID]);
    mockKakaoResponse(400, {code: -10, msg: "PII_KAKAO_MSG"});

    const err = await captureHttpsError(callDisconnect());
    expect(err.code).toBe("resource-exhausted");
    expect(err.message).toBe("errorTooManyRequests");
  });

  it("K9: fetch reject(TypeError) → unavailable · err.name 만 로그", async () => {
    arrangeKakaoIdentities([KAKAO_USER_ID]);
    fetchMock.mockRejectedValueOnce(
      new TypeError("PII_KAKAO_MSG fetch failed"),
    );

    const err = await captureHttpsError(callDisconnect());
    expect(err.code).toBe("unavailable");
    expect(err.message).toBe("errorServiceUnavailable");
    expect(errorMock).toHaveBeenCalledWith(
      {
        event: "disconnect_kakao_unlink_failed",
        uid: CALLER_UID,
        code: "TypeError",
      },
      expect.any(String),
    );
  });

  it("K10: 500 + 비-JSON 본문 → unavailable · code other", async () => {
    arrangeKakaoIdentities([KAKAO_USER_ID]);
    fetchMock.mockResolvedValueOnce({
      ok: false,
      status: 500,
      json: async () => {
        throw new SyntaxError("Unexpected token < in JSON");
      },
    });

    const err = await captureHttpsError(callDisconnect());
    expect(err.code).toBe("unavailable");
    expect(err.message).toBe("errorServiceUnavailable");
    expect(errorMock).toHaveBeenCalledWith(
      {
        event: "disconnect_kakao_unlink_failed",
        uid: CALLER_UID,
        status: 500,
        code: "other",
      },
      expect.any(String),
    );
  });
});

describe("disconnectKakaoProvider — 원장 결함", () => {
  it("K11: 회원번호 형식 밖(abc) → internal · fetch 0 · 값 로그 0", async () => {
    arrangeKakaoIdentities(["abc"]);

    const err = await captureHttpsError(callDisconnect());
    expect(err.code).toBe("internal");
    expect(err.message).toBe("errorUnknown");
    expect(fetchMock).not.toHaveBeenCalled();
    expect(errorMock).toHaveBeenCalledWith(
      {event: "disconnect_kakao_target_invalid", uid: CALLER_UID},
      expect.any(String),
    );
  });

  it("K12: identity_index 조회 throw → internal · fingerprint 로그", async () => {
    mockWhereGet.mockRejectedValueOnce(
      Object.assign(new Error("PII_KAKAO_MSG"), {code: "unavailable"}),
    );

    const err = await captureHttpsError(callDisconnect());
    expect(err.code).toBe("internal");
    expect(err.message).toBe("errorUnknown");
    expect(fetchMock).not.toHaveBeenCalled();
    expect(errorMock).toHaveBeenCalledWith(
      {
        event: "disconnect_kakao_precheck_failed",
        uid: CALLER_UID,
        code: "unavailable",
      },
      expect.any(String),
    );
  });
});

// 반드시 마지막 describe — 앞선 모든 케이스의 logger 호출을 검사한다.
describe("disconnectKakaoProvider — PII sentinel (K13)", () => {
  it("K13: 모든 케이스의 logger 호출에 회원번호 · 어드민 키 · msg 0", () => {
    // 앞선 케이스들이 실제로 로그를 남겼는지부터 확인 (공허 통과 방지).
    expect(accumulatedLogCalls.length).toBeGreaterThan(8);
    const serialized = JSON.stringify(accumulatedLogCalls);
    for (const sentinel of PII_SENTINELS) {
      expect(serialized).not.toContain(sentinel);
    }
  });
});
