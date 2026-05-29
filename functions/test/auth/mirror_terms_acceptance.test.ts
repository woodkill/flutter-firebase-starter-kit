/**
 * mirrorTermsAcceptanceSnapshot onCall 회귀 테스트
 * (Phase 16 Plan 16-02 Task 2.2).
 *
 * **Mock 한계 — 실 단말 backend tier UAT (Plan 16-07 A9) 가 ground truth.**
 * 본 test 는 Firestore set merge mock + Timestamp.fromDate mock 으로 시나리오
 * 시뮬레이션. 실 Firestore 의 nested map merge 동작 + Timestamp 직렬화는
 * Firebase Emulator integration test 또는 실 단말 UAT 가 진짜 contract
 * (memory feedback_mock_transaction_constraint mirror).
 *
 * Task 2.2 시나리오 (M1-M3):
 *  - M1: happy 5 필드 — Firestore users/{uid}.termsAccepted set merge
 *  - M2: snapshot missing → invalid-argument
 *  - M3: 5 필드 round-trip schema sentinel (Pitfall 4 회피)
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
const lastSetPayload: {value: unknown} = {value: null};
jest.mock("firebase-admin/firestore", () => {
  return {
    Firestore: class MockFirestore {},
    getFirestore: jest.fn(() => ({
      collection: () => ({
        doc: () => ({
          set: (payload: unknown, options: unknown) => {
            lastSetPayload.value = {payload, options};
            return mockSet(payload, options);
          },
        }),
      }),
    })),
    FieldValue: {
      serverTimestamp: () => "MOCK_TIMESTAMP",
    },
    Timestamp: {
      now: () => ({seconds: Math.floor(Date.now() / 1000)}),
      fromDate: (d: Date) => ({
        _kind: "MOCK_TIMESTAMP",
        seconds: Math.floor(d.getTime() / 1000),
        iso: d.toISOString(),
      }),
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

afterAll(() => testEnv.cleanup());

describe("mirrorTermsAcceptanceSnapshot onCall — Task 2.2 (M1-M3)", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockSet.mockReset();
    mockSet.mockResolvedValue(undefined);
    lastSetPayload.value = null;
  });

  // eslint-disable-next-line max-len
  it("M1: happy 5 필드 — Firestore users/{uid}.termsAccepted atomic set merge", async () => {
    const wrapped = testEnv.wrap(myFunctions.mirrorTermsAcceptanceSnapshot);
    const result = (await wrapped({
      auth: {uid: "uid-M1"},
      app: {appId: "test"},
      data: {
        snapshot: {
          version: 1,
          service: true,
          privacy: true,
          marketing: false,
          acceptedAt: "2026-05-29T12:00:00Z",
        },
      },
    } as never)) as {ok: true};

    expect(result.ok).toBe(true);
    expect(mockSet).toHaveBeenCalledTimes(1);
    // set merge option 검증.
    const setArgs = (lastSetPayload.value as {
      payload: {termsAccepted: Record<string, unknown>};
      options: {merge: boolean};
    });
    expect(setArgs.options).toEqual({merge: true});
    // happy path info log.
    expect(infoMock).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "mirror_terms_acceptance_snapshot_done",
        uid: "uid-M1",
      }),
      expect.any(String),
    );
  });

  it("M2: snapshot missing → invalid-argument", async () => {
    const wrapped = testEnv.wrap(myFunctions.mirrorTermsAcceptanceSnapshot);
    const promise = wrapped({
      auth: {uid: "uid-M2"},
      app: {appId: "test"},
      data: {},
    } as never);
    await expect(promise).rejects.toBeInstanceOf(HttpsError);
    await expect(promise).rejects.toMatchObject({
      code: "invalid-argument",
      message: "errorInvalidArgument",
    });
    expect(mockSet).not.toHaveBeenCalled();
  });

  // eslint-disable-next-line max-len
  it("M3: 5 필드 round-trip schema (Pitfall 4 — TermsAcceptance schema drift 회피)", async () => {
    const wrapped = testEnv.wrap(myFunctions.mirrorTermsAcceptanceSnapshot);
    await wrapped({
      auth: {uid: "uid-M3"},
      app: {appId: "test"},
      data: {
        snapshot: {
          version: 2,
          service: true,
          privacy: true,
          marketing: true,
          acceptedAt: "2026-06-01T09:30:00Z",
        },
      },
    } as never);

    // Pitfall 4 회귀 가드 — Firestore set 의 termsAccepted 가 5 필드 verbatim
    // 보존.
    const setArgs = (lastSetPayload.value as {
      payload: {
        termsAccepted: {
          version: number;
          service: boolean;
          privacy: boolean;
          marketing: boolean;
          acceptedAt: unknown;
        };
      };
    });
    expect(setArgs.payload.termsAccepted.version).toBe(2);
    expect(typeof setArgs.payload.termsAccepted.version).toBe("number");
    expect(setArgs.payload.termsAccepted.service).toBe(true);
    expect(typeof setArgs.payload.termsAccepted.service).toBe("boolean");
    expect(setArgs.payload.termsAccepted.privacy).toBe(true);
    expect(typeof setArgs.payload.termsAccepted.privacy).toBe("boolean");
    expect(setArgs.payload.termsAccepted.marketing).toBe(true);
    expect(typeof setArgs.payload.termsAccepted.marketing).toBe("boolean");
    // acceptedAt 은 Timestamp.fromDate 변환 결과 (_kind sentinel).
    const acceptedAt = setArgs.payload.termsAccepted.acceptedAt as {
      _kind?: string;
      iso?: string;
    };
    expect(acceptedAt._kind).toBe("MOCK_TIMESTAMP");
    expect(acceptedAt.iso).toBe("2026-06-01T09:30:00.000Z");
  });
});
