/**
 * sendTestPush onCall 회귀 테스트 (Phase 17 — see ROADMAP.md · D-05 · D-31 ·
 * D-33 · D-34 · D-35).
 *
 * **Mock 한계:** Admin Messaging · Firestore 는 jest stub 이다. 실 FCM 수신
 * (포그라운드 · 백그라운드 · 종료 3상태)은 plan 21 실기기 UAT 가 ground truth.
 *
 * 시나리오:
 *  - T-17-SEND-01: 관통 — 호출자 토큰 전체 → locale 그룹별 발송 → sentCount ·
 *    로그 payload 에 토큰 문자열 0
 *  - T-17-SEND-04: 환경 스위치 꺼짐 → failed-precondition · reason · 읽기 0
 *  - T-17-SEND-05: uid 별 10회/60초 — 11번째 resource-exhausted · 발송 0
 *  - T-17-SEND-06: 미등록 · 무효 토큰 응답 → 문서 삭제 · 그 밖 실패는 유지
 *  - T-17-SEND-07: expireAt 이 지난 토큰 → 발송 제외 + 삭제 · 0개면 발송 0
 *  - T-17-SEND-13: 익명 caller → failed-precondition · anonymous_caller ·
 *    rate limit 카운터 · 토큰 읽기 0 (리뷰 WR-02 · D-28)
 */

jest.mock("firebase-functions/logger", () => ({
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
  debug: jest.fn(),
  log: jest.fn(),
}));

// 테스트가 켜고 끄는 환경 스위치 값 (D-35).
let mockTestPushEnabled = true;
jest.mock("firebase-functions/params", () => ({
  // index.ts 가 함께 불러오는 다른 함수들의 secret 선언용.
  defineSecret: () => ({value: () => "fake-secret"}),
  defineBoolean: () => ({value: () => mockTestPushEnabled}),
}));

/** 토큰 문서 fixture — id = FCM 토큰 문자열. */
type MockTokenDoc = {id: string; data: Record<string, unknown>};

let mockTokenDocs: MockTokenDoc[] = [];
const mockTokensGet = jest.fn();
const mockTokenDelete = jest.fn();
const mockRunTransaction = jest.fn();
// rate_limits 문서 저장소 (path → data) — 트랜잭션 commit 을 흉내 낸다.
const mockRateStore = new Map<string, Record<string, unknown>>();

jest.mock("firebase-admin/firestore", () => {
  /** Admin Timestamp 의 테스트용 최소 구현 (seconds · toMillis). */
  class MockTimestamp {
    /**
     * @param {number} seconds epoch 초.
     */
    constructor(readonly seconds: number) {}

    /**
     * @return {MockTimestamp} 현재 시각.
     */
    static now(): MockTimestamp {
      return MockTimestamp.fromMillis(Date.now());
    }

    /**
     * @param {number} millis epoch 밀리초.
     * @return {MockTimestamp} 해당 시각.
     */
    static fromMillis(millis: number): MockTimestamp {
      return new MockTimestamp(Math.floor(millis / 1000));
    }

    /**
     * @return {number} epoch 밀리초.
     */
    toMillis(): number {
      return this.seconds * 1000;
    }
  }
  return {
    Firestore: class MockFirestore {},
    Timestamp: MockTimestamp,
    FieldValue: {
      serverTimestamp: () => "MOCK_TIMESTAMP",
      increment: (n: number) => ({increment: n}),
    },
    getFirestore: jest.fn(() => ({
      // consumeRateLimit — 순서 강제 tx 로 reads-before-writes 를 검증하고
      // write 를 저장소에 반영한다 (count 가 숫자가 아니면 increment 1).
      runTransaction: async (fn: (tx: unknown) => Promise<unknown>) => {
        mockRunTransaction();
        const {createOrderedTx} = jest.requireActual(
          "../mocks/ordered_transaction",
        );
        const handle = createOrderedTx((ref: {path: string}) => {
          const data = mockRateStore.get(ref.path);
          return {exists: data !== undefined, data: () => data};
        });
        const result = await fn(handle.tx);
        for (const {ref, data} of handle.sets) {
          mockRateStore.set(ref.path, data);
        }
        for (const {ref, data} of handle.updates) {
          const prev = mockRateStore.get(ref.path) ?? {};
          const next = (data as {count?: unknown}).count;
          const count = typeof next === "number" ?
            next :
            (typeof prev.count === "number" ? prev.count : 0) + 1;
          mockRateStore.set(ref.path, {...prev, count});
        }
        return result;
      },
      collection: (name: string) => ({
        doc: (id: string) => ({
          path: `${name}/${id}`,
          collection: (sub: string) => ({
            get: async () => {
              mockTokensGet(`${name}/${id}/${sub}`);
              const docs = mockTokenDocs.map((d) => ({
                id: d.id,
                data: () => d.data,
                ref: {delete: async () => mockTokenDelete(d.id)},
              }));
              return {empty: docs.length === 0, size: docs.length, docs};
            },
          }),
        }),
      }),
    })),
  };
});

const mockSendEachForMulticast = jest.fn();
jest.mock("firebase-admin/messaging", () => ({
  getMessaging: jest.fn(() => ({
    sendEachForMulticast: mockSendEachForMulticast,
  })),
}));

// eslint-disable-next-line import/first
import functionsTest from "firebase-functions-test";
// eslint-disable-next-line import/first
import * as logger from "firebase-functions/logger";
// eslint-disable-next-line import/first
import {Timestamp} from "firebase-admin/firestore";
// eslint-disable-next-line import/first
import {HttpsError} from "firebase-functions/https";

const testEnv = functionsTest();

// eslint-disable-next-line import/first
import * as myFunctions from "../../src/index";

const infoMock = logger.info as unknown as jest.Mock;
const warnMock = logger.warn as unknown as jest.Mock;
const errorMock = logger.error as unknown as jest.Mock;

afterAll(() => testEnv.cleanup());

/** 발송 요청 1건의 테스트용 부분 shape. */
type SentMessage = {
  tokens: string[];
  notification: {title: string; body: string};
  data: Record<string, string>;
  android: {notification: {channelId: string}};
  apns: {payload: {aps: {sound: string}}};
};

/**
 * 만료 전(30일 뒤) 토큰 문서 fixture 를 만든다.
 *
 * @param {string} token FCM 토큰 (= 문서 id).
 * @param {string} locale 토큰 문서 locale.
 * @return {MockTokenDoc} fixture.
 */
function liveToken(token: string, locale: string): MockTokenDoc {
  return {
    id: token,
    data: {
      token,
      platform: "android",
      locale,
      updatedAt: Timestamp.now(),
      expireAt: Timestamp.fromMillis(Date.now() + 30 * 24 * 3600 * 1000),
    },
  };
}

/**
 * 이미 만료된(1시간 전) 토큰 문서 fixture 를 만든다.
 *
 * @param {string} token FCM 토큰 (= 문서 id).
 * @return {MockTokenDoc} fixture.
 */
function expiredToken(token: string): MockTokenDoc {
  const doc = liveToken(token, "ko");
  doc.data.expireAt = Timestamp.fromMillis(Date.now() - 3600 * 1000);
  return doc;
}

/**
 * FCM 응답 오류 객체를 만든다 (Admin `FirebaseMessagingError` 의 code 모양).
 *
 * @param {string} code 오류 code.
 * @return {Error} code 가 붙은 Error.
 */
function fcmError(code: string): Error {
  return Object.assign(new Error("fcm rejected"), {code});
}

/**
 * 모든 응답이 성공인 BatchResponse 를 돌려주도록 발송 mock 을 설정한다.
 */
function stubAllSuccess(): void {
  mockSendEachForMulticast.mockImplementation(
    async (message: SentMessage) => ({
      successCount: message.tokens.length,
      failureCount: 0,
      responses: message.tokens.map(() => ({success: true})),
    }),
  );
}

/**
 * sendTestPush 를 uid 로 호출한다 (입력 0).
 *
 * @param {string} uid 호출자 uid.
 * @return {Promise<{sentCount: number}>} callable 응답.
 */
async function callAs(uid: string): Promise<{sentCount: number}> {
  const wrapped = testEnv.wrap(myFunctions.sendTestPush);
  return (await wrapped({
    auth: {uid},
    app: {appId: "test"},
    data: {},
  } as never)) as {sentCount: number};
}

/**
 * 모든 logger 호출 인자를 JSON 한 덩어리로 모은다 (토큰 노출 검사용).
 *
 * @return {string} 직렬화된 로그 인자.
 */
function allLogText(): string {
  return JSON.stringify([
    ...infoMock.mock.calls,
    ...warnMock.mock.calls,
    ...errorMock.mock.calls,
  ]);
}

beforeEach(() => {
  jest.clearAllMocks();
  mockSendEachForMulticast.mockReset();
  mockTestPushEnabled = true;
  mockTokenDocs = [];
  mockRateStore.clear();
});

describe("sendTestPush — Phase 17 D-05 · D-31 · D-34", () => {
  it("T-17-SEND-01: 호출자 토큰 전체를 locale 그룹으로 발송하고 성공 수를 " +
    "돌려준다 · 로그에 토큰 0", async () => {
    mockTokenDocs = [
      liveToken("tok-ko-1", "ko"),
      liveToken("tok-ja-1", "ja"),
      liveToken("tok-ko-2", "ko"),
    ];
    stubAllSuccess();

    const result = await callAs("u1");

    expect(result).toEqual({sentCount: 3});
    expect(mockTokensGet).toHaveBeenCalledWith("users/u1/fcmTokens");
    expect(mockSendEachForMulticast).toHaveBeenCalledTimes(2);

    const sent = mockSendEachForMulticast.mock.calls.map(
      (c) => c[0] as SentMessage,
    );
    const ko = sent.find((m) => m.notification.title === "테스트 알림");
    const ja = sent.find((m) => m.notification.title === "テスト通知");
    expect(ko?.tokens.sort()).toEqual(["tok-ko-1", "tok-ko-2"]);
    expect(ko?.notification.body).toBe(
      "알림이 도착했습니다. 탭하면 설정 화면을 엽니다.",
    );
    expect(ja?.tokens).toEqual(["tok-ja-1"]);
    for (const message of sent) {
      expect(message.data.route).toBe("/settings");
      expect(message.android.notification.channelId).toBe("general");
      expect(message.apns.payload.aps.sound).toBe("default");
    }

    const done = infoMock.mock.calls.find(
      (c) => (c[0] as {event?: string}).event === "send_test_push_done",
    );
    expect(done).toBeDefined();
    expect(Object.keys(done?.[0] as object).sort()).toEqual(
      ["event", "failed", "pruned", "sent", "uid"],
    );
    expect(done?.[0]).toEqual(
      expect.objectContaining({uid: "u1", sent: 3, failed: 0, pruned: 0}),
    );
    expect(allLogText()).not.toContain("tok-");
  });
});

describe("sendTestPush 방어 — Phase 17 D-35 · D-33 · Phase 16 D-10", () => {
  it("T-17-SEND-04: 환경 스위치가 꺼져 있으면 읽기 · 발송 없이 " +
    "failed-precondition · test_push_disabled", async () => {
    mockTestPushEnabled = false;
    mockTokenDocs = [liveToken("tok-ko-1", "ko")];
    stubAllSuccess();

    const error = await callAs("u4").catch((e: unknown) => e);

    expect(error).toBeInstanceOf(HttpsError);
    expect((error as HttpsError).code).toBe("failed-precondition");
    expect((error as HttpsError).message).toBe("errorTestPushDisabled");
    expect((error as HttpsError).details).toEqual(
      {reason: "test_push_disabled"},
    );
    expect(mockRunTransaction).not.toHaveBeenCalled();
    expect(mockTokensGet).not.toHaveBeenCalled();
    expect(mockSendEachForMulticast).not.toHaveBeenCalled();
  });

  it("T-17-SEND-13: 익명 caller 는 카운터 · 읽기 · 발송 없이 " +
    "failed-precondition · anonymous_caller", async () => {
    mockTokenDocs = [liveToken("tok-ko-1", "ko")];
    stubAllSuccess();
    const wrapped = testEnv.wrap(myFunctions.sendTestPush);

    const error = await (wrapped({
      auth: {uid: "anon-1", token: {firebase: {sign_in_provider: "anonymous"}}},
      app: {appId: "test"},
      data: {},
    } as never) as Promise<unknown>).catch((e: unknown) => e);

    expect(error).toBeInstanceOf(HttpsError);
    expect((error as HttpsError).code).toBe("failed-precondition");
    expect((error as HttpsError).message).toBe(
      "errorAnonymousCallerNotAllowed",
    );
    expect((error as HttpsError).details).toEqual(
      {reason: "anonymous_caller"},
    );
    expect(mockRunTransaction).not.toHaveBeenCalled();
    expect(mockRateStore.size).toBe(0);
    expect(mockTokensGet).not.toHaveBeenCalled();
    expect(mockSendEachForMulticast).not.toHaveBeenCalled();
  });

  it("T-17-SEND-05: 같은 uid 11번째 호출은 resource-exhausted · " +
    "발송 0", async () => {
    mockTokenDocs = [liveToken("tok-ko-1", "ko")];
    stubAllSuccess();

    for (let i = 0; i < 10; i += 1) {
      await expect(callAs("u5")).resolves.toEqual({sentCount: 1});
    }
    expect(mockSendEachForMulticast).toHaveBeenCalledTimes(10);

    const error = await callAs("u5").catch((e: unknown) => e);

    expect(error).toBeInstanceOf(HttpsError);
    expect((error as HttpsError).code).toBe("resource-exhausted");
    expect((error as HttpsError).message).toBe("errorTooManyRequests");
    expect(mockSendEachForMulticast).toHaveBeenCalledTimes(10);
    expect([...mockRateStore.keys()]).toEqual(["rate_limits/sendTestPush:u5"]);
    expect(mockRateStore.get("rate_limits/sendTestPush:u5")?.count).toBe(10);
  });

  it("T-17-SEND-06: 미등록 · 무효 토큰 문서만 지우고 그 밖 실패는 " +
    "유지한다", async () => {
    mockTokenDocs = [
      liveToken("tok-ok", "ko"),
      liveToken("tok-unreg", "ko"),
      liveToken("tok-invalid", "ko"),
      liveToken("tok-busy", "ko"),
    ];
    const codes: Record<string, string> = {
      "tok-unreg": "messaging/registration-token-not-registered",
      "tok-invalid": "messaging/invalid-registration-token",
      "tok-busy": "messaging/internal-error",
    };
    mockSendEachForMulticast.mockImplementation(
      async (message: SentMessage) => ({
        successCount: message.tokens.filter((t) => !codes[t]).length,
        failureCount: message.tokens.filter((t) => codes[t]).length,
        responses: message.tokens.map((t) => codes[t] ?
          {success: false, error: fcmError(codes[t])} :
          {success: true}),
      }),
    );

    const result = await callAs("u6");

    expect(result).toEqual({sentCount: 1});
    expect(mockTokenDelete.mock.calls.map((c) => c[0]).sort()).toEqual(
      ["tok-invalid", "tok-unreg"],
    );
    expect(infoMock).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "send_test_push_done",
        uid: "u6",
        sent: 1,
        failed: 3,
        pruned: 2,
      }),
      expect.any(String),
    );
    expect(allLogText()).not.toContain("tok-");
  });

  it("T-17-SEND-07: expireAt 이 지난 토큰은 발송하지 않고 지운다 · " +
    "남은 토큰 0 → 발송 0", async () => {
    mockTokenDocs = [expiredToken("tok-old-1"), expiredToken("tok-old-2")];
    stubAllSuccess();

    const result = await callAs("u7");

    expect(result).toEqual({sentCount: 0});
    expect(mockSendEachForMulticast).not.toHaveBeenCalled();
    expect(mockTokenDelete.mock.calls.map((c) => c[0]).sort()).toEqual(
      ["tok-old-1", "tok-old-2"],
    );

    // 만료 1 + 유효 1 → 유효 토큰만 발송.
    jest.clearAllMocks();
    mockTokenDocs = [expiredToken("tok-old-3"), liveToken("tok-new", "ja")];

    const mixed = await callAs("u7");

    expect(mixed).toEqual({sentCount: 1});
    expect(mockSendEachForMulticast).toHaveBeenCalledTimes(1);
    expect(
      (mockSendEachForMulticast.mock.calls[0][0] as SentMessage).tokens,
    ).toEqual(["tok-new"]);
    expect(mockTokenDelete.mock.calls.map((c) => c[0])).toEqual(["tok-old-3"]);
  });
});
