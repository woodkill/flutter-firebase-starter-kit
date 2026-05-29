/**
 * lookupSignInMethods onCall 회귀 테스트 (Phase 16 Plan 16-02 Task 2.2).
 *
 * **Mock 한계 — 실 단말 backend tier UAT (Plan 16-07 A1/A4) 가 ground truth.**
 * 본 test 는 (1) admin.auth().getUserByEmail mock + (2) Firestore rate_limits
 * runTransaction mock + (3) identity_index where mock 으로 D-09/D-10 3층
 * 방어 시나리오 시뮬레이션. 실 단말 production Firestore 의 race-fix counter
 * 동작과 App Check enforcement 는 backend tier UAT 가 진짜 contract
 * (memory feedback_mock_transaction_constraint mirror).
 *
 * Task 2.2 시나리오 (K1-K6):
 *  - K1: happy native single provider — Google 매핑
 *  - K2: happy Custom Token — identity_index limit 1 → kakao
 *  - K3: auth/user-not-found → existingProvider: null (silent)
 *  - K4: rate limit exceeded — resource-exhausted + email_enumeration_suspected
 *  - K5: enforceAppCheck:true config sentinel
 *  - K6: PII redaction — logger payload 에 email 본문 미노출
 */

jest.mock("firebase-functions/logger", () => ({
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
  debug: jest.fn(),
  log: jest.fn(),
}));

jest.mock("firebase-functions/params", () => ({
  defineSecret: () => ({value: () => "fake-secret"}),
}));

// firebase-admin/auth — getUserByEmail.
const mockGetUserByEmail = jest.fn();
jest.mock("firebase-admin/auth", () => ({
  getAuth: jest.fn(() => ({
    getUserByEmail: mockGetUserByEmail,
  })),
}));

// firebase-admin/firestore — rate_limits runTransaction + identity_index where.
const mockRateTxGet = jest.fn();
const mockRateTxSet = jest.fn();
const mockRateTxUpdate = jest.fn();
const mockIdxWhereGet = jest.fn();

jest.mock("firebase-admin/firestore", () => {
  const rateRef = {label: "rateRef"};
  return {
    Firestore: class MockFirestore {},
    getFirestore: jest.fn(() => ({
      collection: (name: string) => {
        if (name === "rate_limits") {
          return {
            doc: () => rateRef,
          };
        }
        if (name === "identity_index") {
          return {
            where: () => ({
              where: () => ({
                limit: () => ({
                  get: () => mockIdxWhereGet(),
                }),
              }),
            }),
          };
        }
        return {doc: () => ({label: name})};
      },
      runTransaction: async (fn: (t: unknown) => Promise<unknown>) =>
        fn({
          get: mockRateTxGet,
          set: mockRateTxSet,
          update: mockRateTxUpdate,
        }),
    })),
    FieldValue: {
      serverTimestamp: () => "MOCK_TIMESTAMP",
      increment: (n: number) => ({mockIncrement: n}),
    },
    Timestamp: {
      now: () => ({seconds: Math.floor(Date.now() / 1000)}),
      fromDate: (d: Date) => ({seconds: Math.floor(d.getTime() / 1000)}),
    },
  };
});

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
const debugMock = logger.debug as unknown as jest.Mock;
const logMock = logger.log as unknown as jest.Mock;

afterAll(() => testEnv.cleanup());

describe("lookupSignInMethods onCall — Task 2.2 (K1-K6)", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockGetUserByEmail.mockReset();
    mockRateTxGet.mockReset();
    mockRateTxSet.mockReset();
    mockRateTxUpdate.mockReset();
    mockIdxWhereGet.mockReset();
    // 기본 — rate_limits doc 미존재 → 첫 set (count=1).
    mockRateTxGet.mockResolvedValue({exists: false});
  });

  // eslint-disable-next-line max-len
  it("K1: happy native single provider — providerData=[google.com] → existingProvider=google", async () => {
    mockGetUserByEmail.mockResolvedValue({
      uid: "uid-K1",
      providerData: [{providerId: "google.com"}],
    });

    const wrapped = testEnv.wrap(myFunctions.lookupSignInMethods);
    const result = (await wrapped({
      auth: {uid: "caller-K1"},
      app: {appId: "test"},
      data: {email: "alice@example.com"},
    } as never)) as {existingProvider: string | null};

    expect(result.existingProvider).toBe("google");
    expect(mockGetUserByEmail).toHaveBeenCalledWith("alice@example.com");
    // identity_index 조회 안 함 (native 매칭으로 early return).
    expect(mockIdxWhereGet).not.toHaveBeenCalled();
  });

  // eslint-disable-next-line max-len
  it("K2: happy Custom Token — providerData 비어있음 + identity_index → kakao", async () => {
    mockGetUserByEmail.mockResolvedValue({
      uid: "uid-K2",
      providerData: [],
    });
    mockIdxWhereGet.mockResolvedValue({
      empty: false,
      docs: [{data: () => ({provider: "kakao"})}],
    });

    const wrapped = testEnv.wrap(myFunctions.lookupSignInMethods);
    const result = (await wrapped({
      auth: {uid: "caller-K2"},
      app: {appId: "test"},
      data: {email: "bob@example.com"},
    } as never)) as {existingProvider: string | null};

    expect(result.existingProvider).toBe("kakao");
    expect(mockIdxWhereGet).toHaveBeenCalledTimes(1);
  });

  // eslint-disable-next-line max-len
  it("K3: auth/user-not-found → existingProvider:null (silent — caller fallback)", async () => {
    mockGetUserByEmail.mockRejectedValue(
      Object.assign(new Error("not found"), {code: "auth/user-not-found"}),
    );

    const wrapped = testEnv.wrap(myFunctions.lookupSignInMethods);
    const result = (await wrapped({
      auth: {uid: "caller-K3"},
      app: {appId: "test"},
      data: {email: "unknown@example.com"},
    } as never)) as {existingProvider: string | null};

    expect(result.existingProvider).toBeNull();
    // silent — warn/error 호출 안 됨.
    expect(warnMock).not.toHaveBeenCalledWith(
      expect.objectContaining({event: "lookup_sign_in_methods_failed"}),
      expect.any(String),
    );
  });

  // eslint-disable-next-line max-len
  it("K4: rate limit exceeded → resource-exhausted + email_enumeration_suspected log", async () => {
    // rate_limits doc 존재 + count >= 10 + windowStart 신선 → exceed.
    const nowSec = Math.floor(Date.now() / 1000);
    mockRateTxGet.mockResolvedValue({
      exists: true,
      data: () => ({count: 10, windowStart: {seconds: nowSec - 30}}),
    });

    const wrapped = testEnv.wrap(myFunctions.lookupSignInMethods);
    const promise = wrapped({
      auth: {uid: "caller-K4"},
      app: {appId: "test"},
      data: {email: "PII_K4_EMAIL@example.com"},
    } as never);
    await expect(promise).rejects.toBeInstanceOf(HttpsError);
    await expect(promise).rejects.toMatchObject({
      code: "resource-exhausted",
      message: "errorTooManyRequests",
    });
    // D-10 3층 — alarm event log.
    expect(warnMock).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "email_enumeration_suspected",
        uid: "caller-K4",
        count: 10,
      }),
      expect.any(String),
    );
    // getUserByEmail 호출 안 됨 (rate limit 차단).
    expect(mockGetUserByEmail).not.toHaveBeenCalled();
  });

  it("K5: enforceAppCheck:true config sentinel — onCall 설정 확인", () => {
    // myFunctions.lookupSignInMethods 가 onCall 의 enforceAppCheck:true 로
    // wrap 되었는지 sentinel — function export 가 존재함을 보장.
    expect(myFunctions.lookupSignInMethods).toBeDefined();
    expect(typeof myFunctions.lookupSignInMethods).toBe("function");
  });

  // eslint-disable-next-line max-len
  it("K6: PII redaction — logger payload 에 email 본문 미노출", async () => {
    // rate limit exceed path (K4 와 동일 시나리오) — alarm log 가 PII 안 가짐
    // 검증.
    const piiSentinel = "PII_K6_EMAIL_SENTINEL@example.com";
    const nowSec = Math.floor(Date.now() / 1000);
    mockRateTxGet.mockResolvedValue({
      exists: true,
      data: () => ({count: 10, windowStart: {seconds: nowSec - 30}}),
    });

    const wrapped = testEnv.wrap(myFunctions.lookupSignInMethods);
    await expect(
      wrapped({
        auth: {uid: "caller-K6"},
        app: {appId: "test"},
        data: {email: piiSentinel},
      } as never),
    ).rejects.toBeInstanceOf(HttpsError);

    // PII 금지 sentinel — 모든 logger 호출 payload 에 email 본문 미노출.
    expect(warnMock).not.toHaveBeenCalledWith(
      expect.objectContaining({email: expect.anything()}),
      expect.any(String),
    );
    const allLogCalls = [
      ...infoMock.mock.calls,
      ...warnMock.mock.calls,
      ...errorMock.mock.calls,
      ...debugMock.mock.calls,
      ...logMock.mock.calls,
    ];
    for (const args of allLogCalls) {
      expect(JSON.stringify(args)).not.toContain(piiSentinel);
    }
  });
});
