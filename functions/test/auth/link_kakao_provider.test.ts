/**
 * linkKakaoProvider onCall 테스트 (Phase 17.3 plan 01 · SOCL-09 · D-01).
 *
 * **Mock 한계 — 실 단말 UAT(plan 10)가 ground truth.** 본 파일은 Firebase
 * Admin `verifyIdToken` · Firestore transaction · OIDC verifier 를 jest stub
 * 으로 흉내낸다. 실 Kakao JWKS · App Check · cold start 경계와 실 Firestore
 * 의 「all reads before all writes」 강제는 실 단말 UAT 가 관측한다.
 * transaction 은 `test/mocks/ordered_transaction.ts` 의 순서 강제 tx 를 주입해
 * write 뒤 `tx.get` 이 오면 `READ_AFTER_WRITE` 로 실패하게 만든다
 * (memory feedback_mock_transaction_constraint).
 *
 * OIDC verifier mock 은 `createOidcVerifier` 가 받은 issuer 를 첫 인자로
 * 넘겨, 어느 provider 의 verifier 가 불렸는지 issuer 로 단언한다(자체 verifier
 * 가정 0 — memory feedback_oidc_mock_self_referential).
 *
 * 시나리오 (T-173-KAKAO-01~15, 괄호는 옛 공유 callable 의 L 번호):
 *  - 01: 성공 — kakao issuer verifier 1회 · identity_index `kakao:<sub>` (L1)
 *  - 02: secret binding 이 정확히 `KAKAO_NATIVE_APP_KEY` 1개
 *  - 03: 요청에 `targetProvider: "line"` 이 섞여도 kakao verifier 로 검증
 *  - 04: 다른 uid 소유 신원 → already-exists · write 0 (L2)
 *  - 05: 같은 uid 재연결 → 멱등 성공 · idx 재작성 0 (L8)
 *  - 06: tx read 2건이 첫 write 보다 앞 (L9 · 순서 강제 tx)
 *  - 07: 같은 provider 다른 신원 → already-exists + reason · write 0 (L10)
 *  - 08: 다른 provider(line)만 연결 → 허용 (L11)
 *  - 09: stale auth_time(10분 전) → 연결 진행 (L3)
 *  - 10: verifyIdToken throw → unauthenticated + reauth reason (L4)
 *  - 11: decoded uid ≠ caller uid → permission-denied (L5)
 *  - 12: target 토큰 거부 → 매핑된 오류 + fingerprint code (L6)
 *  - 13: 익명 caller → failed-precondition (L7)
 *  - 14: `request.auth` 부재 → unauthenticated · verifier 미호출
 *  - 15: PII sentinel — 모든 케이스의 logger 호출 누적에 fixture 문자열 0
 */

// firebase-functions/logger mock — read-only export 라 jest.spyOn 미동작.
jest.mock("firebase-functions/logger", () => ({
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
  debug: jest.fn(),
  log: jest.fn(),
}));

// secret 주입 — `name` 을 남겨 `__endpoint.secretEnvironmentVariables` 가
// secret 이름을 싣게 한다 (T-173-KAKAO-02).
jest.mock("firebase-functions/params", () => ({
  defineSecret: (name: string) => ({name, value: () => "fake-secret"}),
}));

// jose — caller 가 errors 만 사용 (instanceof 분기), createRemoteJWKSet stub.
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
  /** Mock JWTClaimValidationFailed — JOSEError 서브클래스. */
  class JWTClaimValidationFailed extends JOSEError {
    /** @param {string} [message] error message. */
    constructor(message?: string) {
      super(message);
      this.name = "JWTClaimValidationFailed";
      this.code = "ERR_JWT_CLAIM_VALIDATION_FAILED";
    }
  }
  return {
    jwtVerify: jest.fn(),
    createRemoteJWKSet: jest.fn(() => "MOCK_JWKS"),
    errors: {JOSEError, JWTClaimValidationFailed},
  };
});

// createOidcVerifier mock — provider 별 verifier 가 자기 issuer 를 첫 인자로
// 넘긴다. jest hoisting: factory 가 참조하는 바깥 변수는 `mock` 접두.
const mockVerifyTargetIdToken = jest.fn();
jest.mock("../../src/shared/oidc_verifier", () => ({
  createOidcVerifier: jest.fn(
    (config: {issuer: string}) => (token: string, nonce: string) =>
      mockVerifyTargetIdToken(config.issuer, token, nonce),
  ),
}));

// firebase-admin/auth — verifyIdToken 자체 stub (자체 JWT decode 0).
const mockVerifyIdToken = jest.fn();
jest.mock("firebase-admin/auth", () => ({
  getAuth: jest.fn(() => ({
    verifyIdToken: mockVerifyIdToken,
  })),
}));

// firebase-admin/firestore — 순서 강제 tx 주입. 호출 시점에 지연 참조한다.
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
import * as jose from "jose";
// eslint-disable-next-line import/first
import {createOrderedTx} from "../mocks/ordered_transaction";
// eslint-disable-next-line import/first
import type {OrderedTxHandle} from "../mocks/ordered_transaction";
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

/** Kakao OIDC `sub` fixture. */
const KAKAO_SUB = "kakao-sub-1";

/** Kakao verifier issuer (`shared/oidc_providers.ts`). */
const KAKAO_ISSUER = "https://kauth.kakao.com";

/** caller ID token fixture — PII sentinel (T-173-KAKAO-15). */
const ID_TOKEN = "PII_KAKAO_ID_TOKEN";

/** target Kakao ID token fixture — PII sentinel. */
const TARGET_TOKEN = "PII_KAKAO_TARGET_TOKEN";

/** OIDC nonce fixture — PII sentinel. */
const NONCE = "PII_KAKAO_NONCE";

/** verifier payload 의 email fixture — PII sentinel. */
const TARGET_EMAIL = "PII_KAKAO_EMAIL";

/** target verifier 거부 오류 본문 fixture — PII sentinel (로그 노출 0). */
const TARGET_ERROR_BODY = "PII_KAKAO_TARGET_BODY";

/** 기본 요청 data — `targetProvider` 필드 없음. */
const LINK_DATA = {
  idToken: ID_TOKEN,
  targetProviderToken: TARGET_TOKEN,
  nonce: NONCE,
};

/** 모든 케이스의 logger 호출 누적 — T-173-KAKAO-15 PII sentinel 이 검사한다. */
const accumulatedLogCalls: unknown[][] = [];

/** 이번 케이스의 identity_index tx read 결과 (undefined = 문서 없음). */
let idxOwnerUid: string | undefined;

/** 이번 케이스의 users/{uid} tx read `linkedProviders` (undefined = 없음). */
let userLinkedProviders: unknown[] | undefined;

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
 * auth_time 만료 (now - 600s = 10분) — stale ID Token fixture.
 * @return {number} auth_time epoch seconds.
 */
function staleAuthTime(): number {
  return Math.floor(Date.now() / 1000) - 600;
}

/**
 * jose `JWTClaimValidationFailed` (mock) 인스턴스를 만든다.
 *
 * @param {string} message 오류 본문 — PII sentinel 로그 노출 0 단언 대상.
 * @return {Error} target verifier 가 던질 오류.
 */
function buildClaimValidationError(message: string): Error {
  const ErrCtor = jose.errors.JWTClaimValidationFailed as unknown as new (
    m: string,
  ) => Error;
  return new ErrCtor(message);
}

/**
 * linkKakaoProvider 를 호출한다.
 *
 * @param {object} data callable 요청 data.
 * @param {CallerAuthFixture | null} auth `request.auth` fixture
 *     (null = auth 부재).
 * @return {Promise<unknown>} callable 결과 promise.
 */
function callLink(
  data: object = LINK_DATA,
  auth: CallerAuthFixture | null = signedInCallerAuth(CALLER_UID, "google.com"),
): Promise<unknown> {
  const wrapped = testEnv.wrap(myFunctions.linkKakaoProvider);
  const request = auth === null ?
    {app: {appId: "test"}, data} :
    {auth, app: {appId: "test"}, data};
  return wrapped(request as never) as Promise<unknown>;
}

beforeEach(() => {
  jest.clearAllMocks();
  mockVerifyIdToken.mockReset();
  mockVerifyIdToken.mockResolvedValue({
    uid: CALLER_UID,
    auth_time: freshAuthTime(),
    firebase: {sign_in_provider: "google.com"},
  });
  mockVerifyTargetIdToken.mockReset();
  mockVerifyTargetIdToken.mockResolvedValue({
    sub: KAKAO_SUB,
    email: TARGET_EMAIL,
  });
  idxOwnerUid = undefined;
  userLinkedProviders = undefined;
  mockOrdered = createOrderedTx((ref) =>
    (ref as {label: string}).label === "identity_index" ?
      {
        exists: idxOwnerUid !== undefined,
        data: () => ({firebaseUid: idxOwnerUid}),
      } :
      {
        exists: true,
        data: () =>
          userLinkedProviders === undefined ?
            {} :
            {linkedProviders: userLinkedProviders},
      },
  );
});

describe("linkKakaoProvider — provider 전용 연결 callable", () => {
  // eslint-disable-next-line max-len
  it("T-173-KAKAO-01: 성공 — kakao issuer verifier 1회 · identity_index kakao:<sub> · {ok: true}", async () => {
    const result = await callLink();

    expect(result).toEqual({ok: true});
    expect(mockVerifyIdToken).toHaveBeenCalledWith(ID_TOKEN, true);
    expect(mockVerifyTargetIdToken).toHaveBeenCalledTimes(1);
    expect(mockVerifyTargetIdToken).toHaveBeenCalledWith(
      KAKAO_ISSUER,
      TARGET_TOKEN,
      NONCE,
    );
    // read 2 (idx + users) → set 2 (idx 신규 + users merge).
    expect(mockOrdered.calls).toEqual(["get", "get", "set", "set"]);
    expect(mockOrdered.sets[0].ref).toEqual({
      label: "identity_index",
      id: `kakao:${KAKAO_SUB}`,
    });
    expect(mockOrdered.sets[0].data).toMatchObject({
      firebaseUid: CALLER_UID,
      provider: "kakao",
      providerUserId: KAKAO_SUB,
    });
    const usersData = mockOrdered.sets[1].data as {linkedProviders: unknown};
    expect(mockOrdered.sets[1].ref).toEqual({label: "users", id: CALLER_UID});
    expect(usersData.linkedProviders).toEqual({
      mockArrayUnion: {providerId: "kakao", providerUserId: KAKAO_SUB},
    });
    // 연결은 가입 이벤트가 아니다 (Phase 16.7 D-14 · D-18).
    expect(usersData).not.toHaveProperty("signUpProviderId");
    expect(infoMock).toHaveBeenCalledWith(
      {
        event: "link_kakao_provider_succeeded",
        uid: CALLER_UID,
        isNewUser: false,
      },
      expect.any(String),
    );
  });

  // eslint-disable-next-line max-len
  it("T-173-KAKAO-02: secret binding 이 정확히 KAKAO_NATIVE_APP_KEY 1개", () => {
    const secrets =
      myFunctions.linkKakaoProvider.__endpoint.secretEnvironmentVariables ?? [];
    expect(secrets.map((s) => s.key)).toEqual(["KAKAO_NATIVE_APP_KEY"]);
  });

  // eslint-disable-next-line max-len
  it("T-173-KAKAO-03: 요청에 targetProvider \"line\" 이 섞여도 kakao verifier 로 검증 · 문서 id kakao:", async () => {
    const result = await callLink({...LINK_DATA, targetProvider: "line"});

    expect(result).toEqual({ok: true});
    expect(mockVerifyTargetIdToken).toHaveBeenCalledTimes(1);
    expect(mockVerifyTargetIdToken).toHaveBeenCalledWith(
      "https://kauth.kakao.com",
      TARGET_TOKEN,
      NONCE,
    );
    expect(mockVerifyTargetIdToken).not.toHaveBeenCalledWith(
      "https://access.line.me",
      expect.anything(),
      expect.anything(),
    );
    const idxRef = mockOrdered.sets[0].ref as {label: string; id: string};
    expect(idxRef.label).toBe("identity_index");
    expect(idxRef.id.startsWith("kakao:")).toBe(true);
  });
});

// eslint-disable-next-line max-len
describe("linkKakaoProvider — 연결 transaction (옛 L2 · L8 · L9 · L10 · L11)", () => {
  // eslint-disable-next-line max-len
  it("T-173-KAKAO-04: 다른 uid 소유 신원 → already-exists · write 0 (L2)", async () => {
    idxOwnerUid = "other-owner-uid";

    const promise = callLink();
    await expect(promise).rejects.toBeInstanceOf(HttpsError);
    await expect(promise).rejects.toMatchObject({
      code: "already-exists",
      message: "errorAccountAlreadyLinked",
    });
    expect(mockOrdered.calls).toEqual(["get", "get"]);
    expect(mockOrdered.sets).toHaveLength(0);
    expect(infoMock).not.toHaveBeenCalled();
  });

  // eslint-disable-next-line max-len
  it("T-173-KAKAO-05: 같은 uid 재연결 → 멱등 성공 · idx 재작성 0 (L8)", async () => {
    idxOwnerUid = CALLER_UID;

    await expect(callLink()).resolves.toEqual({ok: true});

    // idx 문서는 다시 쓰지 않는다 (최초 linkedAt 보존) — users self-heal 만.
    expect(mockOrdered.calls).toEqual(["get", "get", "set"]);
    expect(mockOrdered.sets[0].ref).toEqual({label: "users", id: CALLER_UID});
  });

  // eslint-disable-next-line max-len
  it("T-173-KAKAO-06: tx read 2건이 첫 write 보다 앞 — 순서 강제 tx (L9)", async () => {
    await expect(callLink()).resolves.toEqual({ok: true});

    // 순서 강제 tx 는 write 뒤 get 이면 READ_AFTER_WRITE 로 reject 한다 —
    // 여기까지 왔다면 위반이 없었고, 호출 기록으로 순서를 한 번 더 잠근다.
    expect(mockOrdered.calls).toEqual(["get", "get", "set", "set"]);
    expect(mockOrdered.calls.lastIndexOf("get")).toBeLessThan(
      mockOrdered.calls.indexOf("set"),
    );
  });

  // eslint-disable-next-line max-len
  it("T-173-KAKAO-07: 같은 provider 다른 신원 → already-exists + reason provider_already_linked · write 0 (L10)", async () => {
    userLinkedProviders = [
      {providerId: "kakao", providerUserId: "kakao-sub-EXISTING"},
    ];

    await expect(callLink()).rejects.toMatchObject({
      code: "already-exists",
      message: "errorProviderAlreadyLinked",
      details: {reason: "provider_already_linked"},
    });
    expect(mockOrdered.calls).toEqual(["get", "get"]);
    expect(mockOrdered.sets).toHaveLength(0);
  });

  // eslint-disable-next-line max-len
  it("T-173-KAKAO-08: 다른 provider(line)만 연결돼 있으면 kakao 연결 허용 (L11)", async () => {
    userLinkedProviders = [{providerId: "line", providerUserId: "line-sub"}];

    await expect(callLink()).resolves.toEqual({ok: true});

    expect(mockOrdered.calls).toEqual(["get", "get", "set", "set"]);
  });
});

describe("linkKakaoProvider — caller 검사 (옛 L3 · L4 · L5 · L7)", () => {
  // eslint-disable-next-line max-len
  it("T-173-KAKAO-09: stale auth_time(10분 전) → 연결 진행 (L3 · 260928-cxs)", async () => {
    // Firebase 는 계정 연결에 최근 로그인을 요구하지 않는다 — 오래된 세션도
    // Step 1(checkRevoked · uid 일치)만 통과하면 target 검증으로 진행한다.
    mockVerifyIdToken.mockResolvedValue({
      uid: CALLER_UID,
      auth_time: staleAuthTime(),
      firebase: {sign_in_provider: "google.com"},
    });

    await expect(callLink()).resolves.toEqual({ok: true});

    expect(mockVerifyTargetIdToken).toHaveBeenCalledWith(
      KAKAO_ISSUER,
      TARGET_TOKEN,
      NONCE,
    );
    expect(mockOrdered.sets).toHaveLength(2);
  });

  // eslint-disable-next-line max-len
  it("T-173-KAKAO-10: verifyIdToken throw → unauthenticated + reason reauthentication_required (L4)", async () => {
    mockVerifyIdToken.mockRejectedValue(
      Object.assign(new Error("id token revoked"), {
        code: "auth/id-token-revoked",
      }),
    );

    await expect(callLink()).rejects.toMatchObject({
      code: "unauthenticated",
      message: "errorReauthenticationRequired",
      details: {reason: "reauthentication_required"},
    });
    expect(warnMock).toHaveBeenCalledWith(
      {
        event: "link_kakao_id_token_verify_failed",
        code: "auth/id-token-revoked",
      },
      expect.any(String),
    );
    expect(mockVerifyTargetIdToken).not.toHaveBeenCalled();
    expect(mockOrdered.calls).toEqual([]);
  });

  // eslint-disable-next-line max-len
  it("T-173-KAKAO-11: decoded uid ≠ caller uid → permission-denied (L5)", async () => {
    mockVerifyIdToken.mockResolvedValue({
      uid: "DIFFERENT-UID",
      auth_time: freshAuthTime(),
      firebase: {sign_in_provider: "google.com"},
    });

    await expect(callLink()).rejects.toMatchObject({
      code: "permission-denied",
      message: "errorUnauthenticated",
    });
    expect(mockVerifyTargetIdToken).not.toHaveBeenCalled();
    expect(mockOrdered.calls).toEqual([]);
  });

  // eslint-disable-next-line max-len
  it("T-173-KAKAO-12: target 토큰 거부 → unauthenticated(reason 없음) + fingerprint 로그 (L6)", async () => {
    mockVerifyTargetIdToken.mockRejectedValue(
      buildClaimValidationError(TARGET_ERROR_BODY),
    );

    const promise = callLink();
    // WR-01 / WR-02: Custom Token endpoint 와 같은 공용 매핑 표 — IdP 자격증명
    // 거부는 `unauthenticated` · 재인증 reason 없음 (16.9 review WR-01).
    await expect(promise).rejects.toMatchObject({
      code: "unauthenticated",
      message: "errorInvalidCredentials",
    });
    const rejection = await promise.catch((e: unknown) => e);
    expect((rejection as HttpsError).details).toBeUndefined();
    expect(warnMock).toHaveBeenCalledWith(
      {
        event: "link_kakao_target_token_verify_failed",
        code: "ERR_JWT_CLAIM_VALIDATION_FAILED",
      },
      expect.any(String),
    );
    expect(mockOrdered.calls).toEqual([]);
  });

  // eslint-disable-next-line max-len
  it("T-173-KAKAO-13: 익명 caller → failed-precondition errorAnonymousLinkNotAllowed (L7)", async () => {
    mockVerifyIdToken.mockResolvedValue({
      uid: CALLER_UID,
      auth_time: freshAuthTime(),
      firebase: {sign_in_provider: "anonymous"},
    });

    await expect(
      callLink(LINK_DATA, anonymousCallerAuth(CALLER_UID)),
    ).rejects.toMatchObject({
      code: "failed-precondition",
      message: "errorAnonymousLinkNotAllowed",
    });
    // Step 2 거부 뒤 Step 3(target 검증) 미진입.
    expect(mockVerifyTargetIdToken).not.toHaveBeenCalled();
    expect(mockOrdered.calls).toEqual([]);
  });

  // eslint-disable-next-line max-len
  it("T-173-KAKAO-14: request.auth 부재 → unauthenticated · verifier 미호출", async () => {
    await expect(callLink(LINK_DATA, null)).rejects.toMatchObject({
      code: "unauthenticated",
      message: "errorUnauthenticated",
    });
    expect(mockVerifyIdToken).not.toHaveBeenCalled();
    expect(mockVerifyTargetIdToken).not.toHaveBeenCalled();
    expect(mockOrdered.calls).toEqual([]);
  });
});

// 반드시 마지막 describe — 앞선 모든 케이스의 logger 호출을 검사한다.
describe("linkKakaoProvider — PII sentinel", () => {
  // eslint-disable-next-line max-len
  it("T-173-KAKAO-15: 모든 케이스의 logger 호출에 idToken · target 토큰 · nonce · email fixture 0", () => {
    // 앞선 케이스들이 실제로 로그를 남겼는지부터 확인 (공허 통과 방지).
    expect(accumulatedLogCalls.length).toBeGreaterThan(5);
    const serialized = JSON.stringify(accumulatedLogCalls);
    for (const sentinel of [
      ID_TOKEN,
      TARGET_TOKEN,
      NONCE,
      TARGET_EMAIL,
      TARGET_ERROR_BODY,
    ]) {
      expect(serialized).not.toContain(sentinel);
    }
  });
});
