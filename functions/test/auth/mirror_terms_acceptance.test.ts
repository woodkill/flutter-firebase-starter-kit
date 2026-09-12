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
 *
 * Phase 15 리뷰 CR-01 회귀 가드 (M4-M7):
 *  본 callable 은 Phase 16 에서 `parseTermsAcceptanceJson` 을 적용받지 못한 채
 *  배포되어, client 가 payload 형태 하나로 `internal` 500 을 유발하거나 필수
 *  동의 없이 `termsAccepted` 를 기록할 수 있었다. 아래 4 케이스가 그 경로를
 *  fail-closed (`invalid-argument`) 로 잠근다 — **Firestore write 0건** 이
 *  회귀 판정의 핵심 단언이다.
 *  - M4: `{snapshot: {}}` (빈 객체 — 이전 falsy 가드를 통과했다)
 *  - M5: `acceptedAt` 파싱 불가 문자열
 *  - M6: 미래 version 위조 (SERVER_TERMS_CURRENT_VERSION 상한 초과)
 *  - M7: 필수 동의 `service`/`privacy` false
 *  - M8: 계약 외 여분 키는 Firestore 에 착지하지 않는다
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
          // CR-01: version 은 SERVER_TERMS_CURRENT_VERSION (=1) 상한 이하만
          // 통과한다. 약관 개정으로 상한이 bump 되면 본 fixture 도 함께
          // 올린다 (terms_acceptance_json.ts 의 동시 갱신 의무와 동일 계약).
          version: 1,
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
    expect(setArgs.payload.termsAccepted.version).toBe(1);
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

  // --------------------------------------------------------------------------
  // CR-01 (Phase 15 리뷰) 회귀 가드 — 미검증 client JSON 이 동의 기록에 직접
  // write 되던 경로를 fail-closed 로 잠근다. 각 케이스는 (1) invalid-argument
  // 거부 + (2) Firestore write 0건 을 **둘 다** 단언한다 — 거부만 하고 write
  // 가 남으면 회귀다.
  // --------------------------------------------------------------------------

  /**
   * CR-01 회귀 케이스 공용 실행기.
   *
   * @param {string} uid 호출자 uid (케이스별 구분용).
   * @param {unknown} snapshot 거부되어야 할 snapshot payload.
   * @return {Promise<void>} 단언 완료 시 resolve.
   */
  async function expectRejectedSnapshot(
    uid: string,
    snapshot: unknown,
  ): Promise<void> {
    const wrapped = testEnv.wrap(myFunctions.mirrorTermsAcceptanceSnapshot);
    const promise = wrapped({
      auth: {uid},
      app: {appId: "test"},
      data: {snapshot},
    } as never);
    await expect(promise).rejects.toBeInstanceOf(HttpsError);
    await expect(promise).rejects.toMatchObject({
      code: "invalid-argument",
      message: "errorInvalidArgument",
    });
    // 핵심 단언 — 거부된 payload 는 Firestore 에 단 한 번도 닿지 않는다.
    expect(mockSet).not.toHaveBeenCalled();
  }

  it("M4: 빈 객체 snapshot → invalid-argument + Firestore write 0", async () => {
    // 이전 구현의 `!snapshot` 가드는 빈 객체를 truthy 로 통과시켜
    // Firestore set 이 undefined 값으로 throw → internal 500 이었다.
    await expectRejectedSnapshot("uid-M4", {});
  });

  // eslint-disable-next-line max-len
  it("M5: acceptedAt 파싱 불가 → invalid-argument + Firestore write 0", async () => {
    // Timestamp.fromDate(Invalid Date) throw → internal 500 이던 경로.
    await expectRejectedSnapshot("uid-M5", {
      version: 1,
      service: true,
      privacy: true,
      marketing: false,
      acceptedAt: "not-a-date",
    });
  });

  // eslint-disable-next-line max-len
  it("M6: 미래 version 위조 → invalid-argument + Firestore write 0", async () => {
    // client 의 `restored.version >= currentVersion` 재동의 강제 로직을
    // 사용자가 스스로 영구 무력화할 수 있던 경로.
    await expectRejectedSnapshot("uid-M6", {
      version: 999,
      service: true,
      privacy: true,
      marketing: false,
      acceptedAt: "2026-06-01T09:30:00Z",
    });
  });

  // eslint-disable-next-line max-len
  it("M7: 필수 동의 service/privacy false → invalid-argument + Firestore write 0", async () => {
    // "필수 동의 없이 동의 기록 존재" 라는 모순 상태를 차단한다.
    await expectRejectedSnapshot("uid-M7", {
      version: 1,
      service: false,
      privacy: false,
      marketing: false,
      acceptedAt: "2026-06-01T09:30:00Z",
    });
  });

  it("M8: 계약 외 여분 키는 Firestore 에 착지하지 않는다", async () => {
    const wrapped = testEnv.wrap(myFunctions.mirrorTermsAcceptanceSnapshot);
    await wrapped({
      auth: {uid: "uid-M8"},
      app: {appId: "test"},
      data: {
        snapshot: {
          version: 1,
          service: true,
          privacy: true,
          marketing: false,
          acceptedAt: "2026-06-01T09:30:00Z",
          isAdmin: true,
          injected: "payload",
        },
      },
    } as never);

    const setArgs = lastSetPayload.value as {
      payload: {termsAccepted: Record<string, unknown>};
    };
    expect(Object.keys(setArgs.payload.termsAccepted).sort()).toEqual([
      "acceptedAt",
      "marketing",
      "privacy",
      "service",
      "version",
    ]);
  });
});
