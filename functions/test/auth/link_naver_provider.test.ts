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
 *
 * PII sentinel: access token · code · state · client secret · Naver 이메일
 * fixture 값(`PII_NAVER_*`) 은 어느 logger 호출 인자에도 나오면 안 된다.
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
import {signedInCallerAuth} from "../mocks/caller_auth";
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

/** NAVER `/v1/nid/me` — 전역 fetch 호출 모양 단언용. */
const NAVER_PROFILE_URL = "https://openapi.naver.com/v1/nid/me";

/** 모든 케이스의 logger 호출 누적 — N15 PII sentinel 이 검사한다. */
const accumulatedLogCalls: unknown[][] = [];

/** 이번 케이스의 identity_index tx read 결과 (undefined = 문서 없음). */
let idxOwnerUid: string | undefined;

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

/** 1-tap 모양 요청 data. */
const APP_DATA = {idToken: "FRESH", accessToken: "PII_NAVER_ACCESS_TOKEN"};

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
  mockOrdered = createOrderedTx((ref) =>
    (ref as {label: string}).label === "identity_index" ?
      {
        exists: idxOwnerUid !== undefined,
        data: () => ({firebaseUid: idxOwnerUid}),
      } :
      {exists: true, data: () => ({})},
  );
});

describe("linkNaverProvider — 1-tap 연결 · transaction (N1~N3)", () => {
  it("N1: 1-tap 성공 — idx 신규 + linkedProviders arrayUnion", async () => {
    mockProfileOk();

    const result = await callLink(APP_DATA);

    expect(result).toEqual({ok: true});
    expect(mockVerifyIdToken).toHaveBeenCalledWith("FRESH", true);
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
    // read 1 → set 2 (idx 신규 + users merge) — 순서 강제 tx 통과.
    expect(mockOrdered.calls).toEqual(["get", "set", "set"]);
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

    expect(mockOrdered.calls).toEqual(["get", "set"]);
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
    expect(mockOrdered.calls).toEqual(["get"]);
    expect(mockOrdered.sets).toHaveLength(0);
    expect(infoMock).not.toHaveBeenCalled();
  });
});
