/**
 * mirrorAccountEmail onCall 회귀 테스트 (Phase 17 Plan 17-10 · D-26 · D-13).
 *
 * native 경로 email mirror — 입력 0 callable 이 서버가 검증한 ID token 의
 * `email` · `email_verified` claim 만 `users/{uid}` 에 set-merge 한다.
 *
 * **Mock 한계:** Firestore set merge 는 mock 이다. 실 Firestore 의 merge
 * 동작 · 배포 뒤 App Check 강제는 plan 20 배포 + plan 22 실기기 UAT 가
 * ground truth 다 (memory feedback_mock_transaction_constraint).
 *
 * 시나리오:
 *  - T-17-MIRROR-01: 관통 — 토큰 email · email_verified → set-merge 1회 ·
 *    `{ok: true}` · logger payload 키 = event · uid · hasEmail 만.
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

jest.mock("firebase-admin/auth", () => ({
  getAuth: jest.fn(() => ({})),
}));

// firebase-admin/firestore — users/{uid}.set merge mock.
const mockSet = jest.fn();
const mockDoc = jest.fn();
const setCalls: Array<{path: string; payload: unknown; options: unknown}> =
  [];
jest.mock("firebase-admin/firestore", () => {
  return {
    Firestore: class MockFirestore {},
    getFirestore: jest.fn(() => ({
      collection: (name: string) => ({
        doc: (id: string) => {
          mockDoc(`${name}/${id}`);
          return {
            set: (payload: unknown, options: unknown) => {
              setCalls.push({path: `${name}/${id}`, payload, options});
              return mockSet(payload, options);
            },
          };
        },
      }),
    })),
    FieldValue: {
      serverTimestamp: () => "MOCK_TIMESTAMP",
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

const testEnv = functionsTest();

// eslint-disable-next-line import/first
import * as myFunctions from "../../src/index";

const infoMock = logger.info as unknown as jest.Mock;
const errorMock = logger.error as unknown as jest.Mock;

afterAll(() => testEnv.cleanup());

/**
 * logger mock 의 모든 호출에서 첫 인자(payload) 객체를 모은다.
 *
 * @return {Array<Record<string, unknown>>} payload 목록.
 */
function loggedPayloads(): Array<Record<string, unknown>> {
  return [...infoMock.mock.calls, ...errorMock.mock.calls].map(
    (call) => call[0] as Record<string, unknown>,
  );
}

describe("mirrorAccountEmail onCall — Phase 17 D-26 (T-17-MIRROR)", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockSet.mockReset();
    mockSet.mockResolvedValue(undefined);
    setCalls.length = 0;
  });

  // eslint-disable-next-line max-len
  it("T-17-MIRROR-01: 토큰 email · email_verified 만 users/{uid} 에 set-merge 한다", async () => {
    const wrapped = testEnv.wrap(myFunctions.mirrorAccountEmail);
    const result = (await wrapped({
      auth: {
        uid: "u1",
        token: {
          email: "a@example.com",
          email_verified: true,
          firebase: {sign_in_provider: "google.com"},
        },
      },
      app: {appId: "test"},
      data: {},
    } as never)) as {ok: true};

    expect(result).toEqual({ok: true});
    expect(mockSet).toHaveBeenCalledTimes(1);
    expect(setCalls[0]).toEqual({
      path: "users/u1",
      payload: {email: "a@example.com", emailVerified: true},
      options: {merge: true},
    });

    // logger payload — event · uid · hasEmail 만 (이메일 본문 0).
    expect(infoMock).toHaveBeenCalledTimes(1);
    const payload = infoMock.mock.calls[0][0] as Record<string, unknown>;
    expect(Object.keys(payload).sort()).toEqual(["event", "hasEmail", "uid"]);
    expect(payload).toEqual({
      event: "mirror_account_email_done",
      uid: "u1",
      hasEmail: true,
    });
    const serialized = JSON.stringify(infoMock.mock.calls);
    expect(serialized).not.toContain("a@example.com");
    for (const p of loggedPayloads()) {
      expect(JSON.stringify(p)).not.toContain("a@example.com");
    }
  });
});
