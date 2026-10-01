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
