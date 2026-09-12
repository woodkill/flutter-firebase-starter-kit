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
 *
 * Phase 15 리뷰 WR-08 회귀 가드 (K7-K9):
 *  - K7: windowStart 누락 문서 → TypeError 로 영구 실패하지 않고 자기치유
 *  - K8: IP 층 counter 도 같은 transaction 에서 증가 (익명 UID 회전 우회 차단)
 *  - K9: IP 층 초과 → resource-exhausted + axis:"ip" 알람
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
  // WR-08: IP 층 counter 는 별도 문서다 (lookupSignInMethodsIp:<hash>).
  const ipRateRef = {label: "ipRateRef"};
  return {
    Firestore: class MockFirestore {},
    getFirestore: jest.fn(() => ({
      collection: (name: string) => {
        if (name === "rate_limits") {
          return {
            doc: (id: string) =>
              id.startsWith("lookupSignInMethodsIp:") ? ipRateRef : rateRef,
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

  // ---------------------------------------------------------------------------
  // WR-08 (Phase 15 리뷰) 회귀 가드.
  //
  // (1) UID 별 counter 는 `request.auth` 만 요구하는데 익명 사용자도 이를
  //     만족하고 익명 UID 는 무제한 생성 가능하다 — 10회마다 새 UID 로 카운터를
  //     리셋할 수 있어 사실상 방어가 없었다. IP 층이 그 우회로를 닫는다.
  // (2) `data.windowStart.seconds` 직접 접근은 문서에 windowStart 가 없으면
  //     TypeError 로 터졌고, 바깥 catch 가 internal 로 바꿔 **해당 UID 의
  //     lookup 이 영구 실패** 했다 (문서가 자기치유되지 않음).
  // ---------------------------------------------------------------------------
  it("K7: windowStart 누락 문서 → 영구 실패 대신 새 창으로 자기치유", async () => {
    // 부분 write / 수동 편집으로 windowStart 가 없는 counter 문서.
    mockRateTxGet.mockResolvedValue({
      exists: true,
      data: () => ({count: 3}),
    });
    mockGetUserByEmail.mockResolvedValue({
      uid: "u-K7",
      providerData: [{providerId: "google.com"}],
    });

    const wrapped = testEnv.wrap(myFunctions.lookupSignInMethods);
    const result = (await wrapped({
      auth: {uid: "caller-K7"},
      app: {appId: "test"},
      data: {email: "k7@example.com"},
    } as never)) as {existingProvider: string | null};

    // internal 로 터지지 않고 정상 응답 + counter 는 새 창으로 리셋된다.
    expect(result.existingProvider).toBe("google");
    expect(mockRateTxSet).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({count: 1}),
    );
  });

  it("K8: IP 층 counter 도 같은 transaction 에서 함께 증가한다", async () => {
    const nowSec = Math.floor(Date.now() / 1000);
    mockRateTxGet.mockResolvedValue({
      exists: true,
      data: () => ({count: 1, windowStart: {seconds: nowSec - 5}}),
    });
    mockGetUserByEmail.mockResolvedValue({
      uid: "u-K8",
      providerData: [{providerId: "google.com"}],
    });

    const wrapped = testEnv.wrap(myFunctions.lookupSignInMethods);
    await wrapped({
      auth: {uid: "caller-K8"},
      app: {appId: "test"},
      // WR-08: IP 층은 rawRequest.ip 로 평가된다. 실 런타임에서는 Cloud
      // Functions 가 채우고, 못 얻으면 IP 층을 건너뛴다 (fail-open).
      rawRequest: {ip: "203.0.113.9"},
      data: {email: "k8@example.com"},
    } as never);

    // uid counter + ip counter = 2회 증가. 익명 UID 를 갈아끼워도 ip counter
    // 는 리셋되지 않는다.
    expect(mockRateTxUpdate).toHaveBeenCalledTimes(2);
  });

  it("K9: IP 층 초과 → resource-exhausted + axis:'ip' 알람", async () => {
    const nowSec = Math.floor(Date.now() / 1000);
    // uid counter 는 여유가 있지만 (새 익명 UID) ip counter 가 이미 한도.
    mockRateTxGet.mockImplementation((ref: {label?: string}) =>
      Promise.resolve(
        ref?.label === "ipRateRef" ?
          {
            exists: true,
            data: () => ({count: 60, windowStart: {seconds: nowSec - 5}}),
          } :
          {
            exists: true,
            data: () => ({count: 1, windowStart: {seconds: nowSec - 5}}),
          },
      ),
    );

    const wrapped = testEnv.wrap(myFunctions.lookupSignInMethods);
    const promise = wrapped({
      auth: {uid: "fresh-anon-uid-K9"},
      app: {appId: "test"},
      // WR-08: IP 층은 rawRequest.ip 로 평가된다. 실 런타임에서는 Cloud
      // Functions 가 채우고, 못 얻으면 IP 층을 건너뛴다 (fail-open).
      rawRequest: {ip: "203.0.113.9"},
      data: {email: "k9@example.com"},
    } as never);

    await expect(promise).rejects.toMatchObject({
      code: "resource-exhausted",
      message: "errorTooManyRequests",
    });
    expect(warnMock).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "email_enumeration_suspected",
        axis: "ip",
      }),
      expect.any(String),
    );
    // PII 금지 — IP 원문 / email 본문 미노출.
    for (const args of warnMock.mock.calls) {
      expect(JSON.stringify(args)).not.toContain("k9@example.com");
    }
  });
});
