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
});
