/**
 * sendPasswordResetMail onCall 회귀 테스트 (Phase 17.5 plan 05 · D-10 · D-11 ·
 * D-15 · D-23).
 *
 * kit 모드 재설정 메일 callable — 로그인 전 요청이라 익명 세션도 받고, 가입
 * 여부를 드러내지 않는다(없는 주소 = 같은 `{ok: true}`). rate limit 3축(uid ·
 * IP 해시 · 이메일 해시)을 링크 생성 **전** 한 transaction 에서 판정한다.
 * 그 뒤 · 링크 생성 전에 Admin `getUserByEmail` 로 계정 유무를 본다(D-23 —
 * 열거 보호 프로젝트는 없는 주소의 링크 생성이 `auth/internal-error`).
 * Admin 링크는 결과 페이지 링크로 재작성한다(`toResultPageLink` — D-22 ①).
 * `renderMail` 은 mock 하지 않는다(렌더 관통).
 *
 * **Mock 한계:** Admin 링크 · Firestore add · transaction 은 mock 이다. rate
 * limit transaction 은 `createOrderedTx` 로 reads-before-writes 를 강제한다
 * (memory feedback_mock_transaction_constraint). 실 확장 발송은 plan 12 UAT.
 *
 * 시나리오 (plan 05 Task 2 R1~R6 · plan 14 R7 · R8 · plan 18 R9~R12):
 *  - R1: 익명 caller · 있는 주소 → 조회 1회(링크 생성보다 앞) · 링크 1회 ·
 *    mail add 1회 · ko 제목 · 결과 페이지 링크
 *    (`https://demo.web.app/?mode=resetPassword…&lang=ko`) · 원 링크 호스트 0
 *  - R2: 조회는 있음 · 링크 생성이 계정 없음(email-not-found · user-not-found
 *    — 조회와 생성 사이 삭제 경합) → add 0 · R1 과 같은 반환
 *  - R3: 미인증 · email 누락 · 321자 · Admin invalid-email → 각 오류 코드
 *  - R4: 이메일 · uid · IP 축 초과 → resource-exhausted + 알람 · 링크 생성 0
 *  - R5: 정식 caller 허용 · 요청 브랜드 값 · resultPageUrl · link 무시
 *  - R6: logger 인자에 이메일 · oobCode · IP 원문 · 결과 페이지 호스트 0 ·
 *    env 미설정 → internal
 *  - R7: 결과 페이지 env 빈 값 → 있는 주소 · 없는 주소 같은 internal · 링크
 *    생성 · rate limit · add 0 (D-22 ③ · 가입 여부 비노출)
 *  - R8: Admin 링크에 oobCode 없음 → internal + password_reset_mail_failed ·
 *    add 0 · 로그에 호스트 0
 *  - R9: 열거 보호 dev 모양(조회 user-not-found · 링크 생성 internal-error)
 *    → 링크 생성 0 · add 0 · `{ok: true}` · no_account 1회 (D-23)
 *  - R10: 조회 invalid-email → invalid-argument · 링크 생성 · add 0
 *  - R11: 조회 서버 오류 → internal + password_reset_mail_lookup_failed ·
 *    링크 생성 · add 0 · 로그에 이메일 0
 *  - R12: 있는 주소 · 없는 주소(조회) · 경합(생성) 세 응답이 같다 · 셋 다
 *    rate limit 3축 소비
 *  - R3-b · R4-a · R6-b · R7: 입력 오류 · rate limit 초과 · env 미설정 경로는
 *    계정 조회 0 (조회가 제한 없는 존재 확인 수단이 되지 않게)
 */

jest.mock("firebase-functions/logger", () => ({
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
  debug: jest.fn(),
  log: jest.fn(),
}));

// 브랜드 env — 테스트마다 값을 바꾼다 (param 인스턴스는 첫 호출 때 캐시되므로
// value() 가 호출 시점의 값을 읽게 한다).
const mockEnv: Record<string, string> = {};
jest.mock("firebase-functions/params", () => ({
  defineSecret: () => ({value: () => "fake-secret"}),
  defineString: (name: string) => ({value: () => mockEnv[name] ?? ""}),
}));

const mockGenerateResetLink = jest.fn();
// 계정 조회 (D-23) — 기본은 있는 주소(레코드 반환). 없는 주소 · 조회 실패는
// 케이스마다 `adminError(...)` 로 거부하게 바꾼다.
const mockGetUserByEmail = jest.fn();
jest.mock("firebase-admin/auth", () => ({
  getAuth: jest.fn(() => ({
    generatePasswordResetLink: mockGenerateResetLink,
    getUserByEmail: mockGetUserByEmail,
  })),
}));

// jest hoisting: factory 가 참조하는 바깥 변수는 이름이 `mock` 으로 시작해야
// 한다. 모두 호출 시점에 지연 참조한다.
const mockMailAdd = jest.fn();
let mockOrdered: OrderedTxHandle;
let mockNewTx: () => OrderedTxHandle;
jest.mock("firebase-admin/firestore", () => ({
  Firestore: class MockFirestore {},
  getFirestore: jest.fn(() => ({
    collection: (name: string) => ({
      doc: (id: string) => ({label: `${name}/${id}`}),
      add: (payload: unknown) => mockMailAdd(name, payload),
    }),
    // transaction 마다 새 순서 강제 tx — 한 테스트에서 여러 번 호출해도
    // 앞 호출의 write 기록이 다음 read 를 막지 않는다.
    runTransaction: async (fn: (t: unknown) => Promise<unknown>) => {
      mockOrdered = mockNewTx();
      return fn(mockOrdered.tx);
    },
  })),
  FieldValue: {
    serverTimestamp: () => "MOCK_TIMESTAMP",
    increment: (n: number) => ({mockIncrement: n}),
  },
  Timestamp: {
    now: () => ({seconds: Math.floor(Date.now() / 1000)}),
  },
}));

// eslint-disable-next-line import/first
import functionsTest from "firebase-functions-test";
// eslint-disable-next-line import/first
import * as logger from "firebase-functions/logger";
// eslint-disable-next-line import/first
import {HttpsError} from "firebase-functions/https";
// eslint-disable-next-line import/first
import {anonymousCallerAuth, signedInCallerAuth} from "../mocks/caller_auth";
// eslint-disable-next-line import/first
import {createOrderedTx} from "../mocks/ordered_transaction";
// eslint-disable-next-line import/first
import type {OrderedTxHandle} from "../mocks/ordered_transaction";
// eslint-disable-next-line import/first
import {hashEmail} from "../../src/email/email_hash";
// eslint-disable-next-line import/first
import {hashClientIp} from "../../src/shared/client_ip_hash";

const testEnv = functionsTest();

// eslint-disable-next-line import/first
import * as myFunctions from "../../src/index";

const infoMock = logger.info as unknown as jest.Mock;
const warnMock = logger.warn as unknown as jest.Mock;
const errorMock = logger.error as unknown as jest.Mock;
const debugMock = logger.debug as unknown as jest.Mock;
const logMock = logger.log as unknown as jest.Mock;

afterAll(() => testEnv.cleanup());

/** 요청 email fixture — 로그에 나오면 안 된다. */
const REQUEST_EMAIL = "pii-reset-sentinel@example.com";

/** 클라이언트 IP fixture — 원문이 로그 · 문서 id 에 나오면 안 된다. */
const CLIENT_IP = "203.0.113.77";

/** Admin 링크 fixture — oobCode · 링크 모두 로그에 나오면 안 된다. */
const ADMIN_LINK =
  "https://demo.firebaseapp.com/__/auth/action?mode=resetPassword" +
  "&oobCode=OOB_RESET_SENTINEL&apiKey=fake-api-key";

/** 결과 페이지 env 값 fixture (`EMAIL_RESULT_PAGE_URL`). */
const RESULT_PAGE_URL = "https://demo.web.app/";

/** [ADMIN_LINK] 를 [RESULT_PAGE_URL] 로 재작성한 ko 링크 (D-22 ①). */
const RESULT_LINK_KO =
  "https://demo.web.app/?mode=resetPassword" +
  "&oobCode=OOB_RESET_SENTINEL&apiKey=fake-api-key&lang=ko";

/** caller uid fixture. */
const UID = "u-reset";

/** rate limit 문서 id 들 (fixture 키). */
const UID_DOC = `sendPasswordResetMail:${UID}`;
const IP_DOC = `sendPasswordResetMailIp:${hashClientIp(CLIENT_IP)}`;
const EMAIL_DOC = `sendPasswordResetMailEmail:${hashEmail(REQUEST_EMAIL)}`;

/** `mail/` add 1건의 payload 모양. */
type MailDoc = {
  to: string[];
  message: {subject: string; html: string; text: string};
};

/** rate limit 문서 id → `{count, ageSec}` fixture (없으면 문서 없음). */
let counters: Map<string, {count: number; ageSec: number}>;

/**
 * [counters] fixture 를 읽는 순서 강제 transaction 을 만든다. 읽힌 문서 id 는
 * [readDocIds] 에 기록한다.
 *
 * @return {OrderedTxHandle} 새 transaction handle.
 */
function newTx(): OrderedTxHandle {
  return createOrderedTx((ref: unknown) => {
    const label = (ref as {label: string}).label;
    const docId = label.replace(/^rate_limits\//, "");
    readDocIds.push(docId);
    const fixture = counters.get(docId);
    if (fixture === undefined) return {exists: false, data: () => undefined};
    const nowSec = Math.floor(Date.now() / 1000);
    return {
      exists: true,
      data: () => ({
        count: fixture.count,
        windowStart: {seconds: nowSec - fixture.ageSec},
      }),
    };
  });
}

/** transaction 이 읽은 rate limit 문서 id (호출 순). */
let readDocIds: string[];

/**
 * callable 을 호출한다.
 *
 * @param {unknown} auth onCall `request.auth` (undefined = 미인증).
 * @param {unknown} data callable data.
 * @param {string|null} ip `rawRequest.ip` (null = IP 없음).
 * @return {Promise<unknown>} callable 결과.
 */
function call(
  auth: unknown,
  data: unknown,
  ip: string | null = CLIENT_IP,
): Promise<unknown> {
  const wrapped = testEnv.wrap(myFunctions.sendPasswordResetMail);
  return wrapped({
    auth,
    app: {appId: "test"},
    rawRequest: ip === null ? {} : {ip},
    data,
  } as never);
}

/**
 * 모든 logger 호출 인자를 문자열로 모은다.
 *
 * @return {string} JSON 문자열.
 */
function allLogText(): string {
  return JSON.stringify([
    ...infoMock.mock.calls,
    ...warnMock.mock.calls,
    ...errorMock.mock.calls,
    ...debugMock.mock.calls,
    ...logMock.mock.calls,
  ]);
}

/**
 * `mail/` add 로 들어간 문서들을 돌려준다.
 *
 * @return {Array<MailDoc>} add payload 목록 (컬렉션이 `mail` 인 것만).
 */
function mailDocs(): MailDoc[] {
  return mockMailAdd.mock.calls
    .filter((call) => call[0] === "mail")
    .map((call) => call[1] as MailDoc);
}

/**
 * Admin SDK 오류 모양(`code` 프로퍼티가 있는 Error)을 만든다.
 *
 * @param {string} code `auth/...` 코드.
 * @return {Error} 오류 — message 에 이메일을 실어 로그 누출을 검사한다.
 */
function adminError(code: string): Error {
  return Object.assign(new Error(`admin failed for ${REQUEST_EMAIL}`), {code});
}

/**
 * info 로그 중 `password_reset_mail_no_account` 이벤트 호출만 돌려준다.
 *
 * @return {Array<Array<unknown>>} 해당 이벤트의 logger.info 인자 목록.
 */
function noAccountInfoCalls(): unknown[][] {
  return infoMock.mock.calls.filter(
    (args) =>
      (args[0] as {event?: string}).event === "password_reset_mail_no_account",
  );
}

/**
 * 계정 없음 응답 계약을 단언한다 — 있는 주소와 같은 `{ok: true}` · 메일 0 ·
 * rate limit 3축 소비 · no_account info 정확히 1회 · warn · error 0.
 *
 * @param {unknown} result callable 결과.
 */
function expectNoAccountResponse(result: unknown): void {
  expect(result).toEqual({ok: true});
  expect(mockMailAdd).not.toHaveBeenCalled();
  // 존재 여부와 무관하게 rate limit 3축은 소비된다(같은 제한).
  expect(mockOrdered.sets).toHaveLength(3);
  const calls = noAccountInfoCalls();
  expect(calls).toHaveLength(1);
  expect(calls[0][0]).toEqual({
    event: "password_reset_mail_no_account",
    uid: UID,
  });
  // 오류 경로 로그(warn · error)는 남기지 않는다.
  expect(warnMock).not.toHaveBeenCalled();
  expect(errorMock).not.toHaveBeenCalled();
}

describe("sendPasswordResetMail onCall — Phase 17.5 D-10 (T-175-RMAIL)", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockEnv.EMAIL_APP_NAME = "Kit";
    mockEnv.EMAIL_BRAND_COLOR = "#673AB7";
    mockEnv.EMAIL_LOGO_URL = "";
    mockEnv.EMAIL_RESULT_PAGE_URL = RESULT_PAGE_URL;
    counters = new Map();
    readDocIds = [];
    mockNewTx = newTx;
    // transaction 이 한 번도 열리지 않은 경우의 기록 (빈 handle).
    mockOrdered = newTx();
    mockGenerateResetLink.mockReset();
    mockGenerateResetLink.mockResolvedValue(ADMIN_LINK);
    mockGetUserByEmail.mockReset();
    mockGetUserByEmail.mockResolvedValue({uid: "existing-uid"});
    mockMailAdd.mockReset();
    mockMailAdd.mockResolvedValue({id: "mail-1"});
  });

  // eslint-disable-next-line max-len
  it("R1: 익명 caller · 있는 주소 → 링크 → 결과 페이지 링크(lang=ko) → renderMail → mail add 1회 → {ok: true}", async () => {
    const result = await call(anonymousCallerAuth(UID), {
      email: REQUEST_EMAIL,
      locale: "ko",
    });

    expect(result).toEqual({ok: true});
    // 계정 조회 1회 → 링크 생성 1회 순서 (D-23 — 조회가 링크 생성보다 앞).
    expect(mockGetUserByEmail).toHaveBeenCalledTimes(1);
    expect(mockGetUserByEmail).toHaveBeenCalledWith(REQUEST_EMAIL);
    expect(mockGenerateResetLink).toHaveBeenCalledTimes(1);
    expect(mockGenerateResetLink).toHaveBeenCalledWith(REQUEST_EMAIL);
    expect(mockGetUserByEmail.mock.invocationCallOrder[0]).toBeLessThan(
      mockGenerateResetLink.mock.invocationCallOrder[0],
    );
    const docs = mailDocs();
    expect(docs).toHaveLength(1);
    expect(docs[0].to).toEqual([REQUEST_EMAIL]);
    expect(docs[0].message.subject).toBe("Kit 비밀번호 재설정");
    expect(docs[0].message.html).toContain("lang=ko");
    expect(docs[0].message.html).toContain("oobCode=OOB_RESET_SENTINEL");
    expect(docs[0].message.html).not.toContain("&#x3D;");
    // 링크 = 결과 페이지 재작성 결과 · 원 링크 호스트 0 (D-22 ①).
    expect(docs[0].message.html).toContain(`href="${RESULT_LINK_KO}"`);
    expect(docs[0].message.text).toContain(RESULT_LINK_KO);
    expect(docs[0].message.html).not.toContain("demo.firebaseapp.com");
    expect(docs[0].message.text).not.toContain("demo.firebaseapp.com");
    // 3축이 한 transaction 에서 read 전부 → write 순으로 처리됐다.
    expect(mockOrdered.calls).toEqual([
      "get",
      "get",
      "get",
      "set",
      "set",
      "set",
    ]);
    expect(readDocIds).toEqual([UID_DOC, IP_DOC, EMAIL_DOC]);
    // 문서 id 에 이메일 · IP 원문 0.
    expect(readDocIds.join(" ")).not.toContain("@");
    expect(readDocIds.join(" ")).not.toContain(CLIENT_IP);
  });

  // eslint-disable-next-line max-len
  it("R2: 조회는 있음 · 링크 생성이 계정 없음(auth/email-not-found — 조회와 생성 사이 삭제 경합) → 메일 0 · 있는 주소와 같은 {ok: true}", async () => {
    mockGenerateResetLink.mockRejectedValueOnce(
      adminError("auth/email-not-found"),
    );

    const result = await call(anonymousCallerAuth(UID), {
      email: REQUEST_EMAIL,
      locale: "ko",
    });

    expect(mockGetUserByEmail).toHaveBeenCalledTimes(1);
    expect(mockGenerateResetLink).toHaveBeenCalledTimes(1);
    expectNoAccountResponse(result);
  });

  // eslint-disable-next-line max-len
  it("R2-b: 조회는 있음 · 링크 생성이 auth/user-not-found(경합) → R2 와 같은 결과", async () => {
    mockGenerateResetLink.mockRejectedValueOnce(
      adminError("auth/user-not-found"),
    );

    const result = await call(anonymousCallerAuth(UID), {
      email: REQUEST_EMAIL,
      locale: "ko",
    });

    expect(mockGetUserByEmail).toHaveBeenCalledTimes(1);
    expect(mockGenerateResetLink).toHaveBeenCalledTimes(1);
    expectNoAccountResponse(result);
  });

  it("R3-a: request.auth 없음 → unauthenticated", async () => {
    const promise = call(undefined, {email: REQUEST_EMAIL, locale: "ko"});
    await expect(promise).rejects.toBeInstanceOf(HttpsError);
    await expect(promise).rejects.toMatchObject({
      code: "unauthenticated",
      message: "errorUnauthenticated",
    });
    expect(mockGenerateResetLink).not.toHaveBeenCalled();
  });

  // eslint-disable-next-line max-len
  it("R3-b: email 누락 · 문자열 아님 · 공백뿐 · 321자 → invalid-argument · rate limit 소비 0", async () => {
    const tooLong = `${"a".repeat(309)}@example.com`;
    expect(tooLong).toHaveLength(321);
    for (const data of [
      {locale: "ko"},
      {email: 12345, locale: "ko"},
      {email: "   ", locale: "ko"},
      {email: tooLong, locale: "ko"},
    ]) {
      await expect(call(anonymousCallerAuth(UID), data)).rejects.toMatchObject({
        code: "invalid-argument",
        message: "errorInvalidArgument",
      });
    }
    expect(mockOrdered.calls).toEqual([]);
    expect(mockGenerateResetLink).not.toHaveBeenCalled();
    expect(mockGetUserByEmail).not.toHaveBeenCalled();
  });

  it("R3-c: Admin auth/invalid-email → invalid-argument · 메일 0", async () => {
    mockGenerateResetLink.mockRejectedValueOnce(
      adminError("auth/invalid-email"),
    );
    await expect(
      call(anonymousCallerAuth(UID), {email: "not-an-email", locale: "ko"}),
    ).rejects.toMatchObject({
      code: "invalid-argument",
      message: "errorInvalidArgument",
    });
    expect(mockMailAdd).not.toHaveBeenCalled();
  });

  // eslint-disable-next-line max-len
  it("R4-a: 같은 이메일 4번째(10분 안) → resource-exhausted + password_reset_mail_rate_limited(axis email) · 링크 생성 0", async () => {
    counters.set(EMAIL_DOC, {count: 3, ageSec: 300});

    const promise = call(anonymousCallerAuth(UID), {
      email: REQUEST_EMAIL,
      locale: "ko",
    });
    await expect(promise).rejects.toMatchObject({
      code: "resource-exhausted",
      message: "errorTooManyRequests",
    });
    expect(warnMock).toHaveBeenCalledTimes(1);
    expect(warnMock).toHaveBeenCalledWith(
      {
        event: "password_reset_mail_rate_limited",
        uid: UID,
        axis: "email",
        count: 3,
      },
      expect.any(String),
    );
    // 판정은 계정 조회 · 링크 생성 전 — 없는 주소여도 같은 제한이다.
    expect(mockGenerateResetLink).not.toHaveBeenCalled();
    expect(mockMailAdd).not.toHaveBeenCalled();
    expect(mockOrdered.sets).toHaveLength(0);
    expect(mockOrdered.updates).toHaveLength(0);
    expect(mockGetUserByEmail).not.toHaveBeenCalled();
  });

  // eslint-disable-next-line max-len
  it("R4-b: 대소문자 · 공백만 다른 주소도 같은 이메일 축 counter 를 쓴다", async () => {
    counters.set(EMAIL_DOC, {count: 3, ageSec: 300});

    await expect(
      call(anonymousCallerAuth(UID), {
        email: ` ${REQUEST_EMAIL.toUpperCase()} `,
        locale: "ko",
      }),
    ).rejects.toMatchObject({code: "resource-exhausted"});
    expect(mockGenerateResetLink).not.toHaveBeenCalled();
  });

  it("R4-c: uid 축 6번째(60초 안) → resource-exhausted + axis uid", async () => {
    counters.set(UID_DOC, {count: 5, ageSec: 30});

    await expect(
      call(anonymousCallerAuth(UID), {email: REQUEST_EMAIL, locale: "ko"}),
    ).rejects.toMatchObject({code: "resource-exhausted"});
    expect(warnMock).toHaveBeenCalledWith(
      {
        event: "password_reset_mail_rate_limited",
        uid: UID,
        axis: "uid",
        count: 5,
      },
      expect.any(String),
    );
    expect(mockGenerateResetLink).not.toHaveBeenCalled();
  });

  it("R4-d: IP 축 31번째(60초 안) → resource-exhausted + axis ip", async () => {
    counters.set(IP_DOC, {count: 30, ageSec: 30});

    await expect(
      call(anonymousCallerAuth(UID), {email: REQUEST_EMAIL, locale: "ko"}),
    ).rejects.toMatchObject({code: "resource-exhausted"});
    expect(warnMock).toHaveBeenCalledWith(
      {
        event: "password_reset_mail_rate_limited",
        uid: UID,
        axis: "ip",
        count: 30,
      },
      expect.any(String),
    );
    expect(mockGenerateResetLink).not.toHaveBeenCalled();
  });

  // eslint-disable-next-line max-len
  it("R4-e: 세 축 동시 초과 → 축마다 알람 1회 · resource-exhausted 1번", async () => {
    counters.set(UID_DOC, {count: 5, ageSec: 30});
    counters.set(IP_DOC, {count: 30, ageSec: 30});
    counters.set(EMAIL_DOC, {count: 3, ageSec: 30});

    await expect(
      call(anonymousCallerAuth(UID), {email: REQUEST_EMAIL, locale: "ko"}),
    ).rejects.toMatchObject({code: "resource-exhausted"});
    const axes = warnMock.mock.calls.map(
      (args) => (args[0] as {axis: string}).axis,
    );
    expect(axes).toEqual(["uid", "ip", "email"]);
  });

  // eslint-disable-next-line max-len
  it("R4-f: 창이 지난 counter(uid 60초 · 이메일 600초 초과)는 새 창으로 허용한다", async () => {
    counters.set(UID_DOC, {count: 5, ageSec: 61});
    counters.set(EMAIL_DOC, {count: 3, ageSec: 601});

    const result = await call(anonymousCallerAuth(UID), {
      email: REQUEST_EMAIL,
      locale: "ko",
    });
    expect(result).toEqual({ok: true});
    expect(mockOrdered.sets).toHaveLength(3);
  });

  it("R4-g: IP 를 못 얻으면 IP 축만 건너뛴다(fail-open)", async () => {
    const result = await call(
      anonymousCallerAuth(UID),
      {email: REQUEST_EMAIL, locale: "ko"},
      null,
    );
    expect(result).toEqual({ok: true});
    expect(readDocIds).toEqual([UID_DOC, EMAIL_DOC]);
  });

  // eslint-disable-next-line max-len
  it("R5: 정식 caller 도 허용 · 요청의 appName · brandColor · logoUrl · resultPageUrl · link 는 무시한다", async () => {
    const result = await call(signedInCallerAuth(UID, "password"), {
      email: REQUEST_EMAIL,
      locale: "en",
      appName: "Evil Corp",
      brandColor: "#000000",
      logoUrl: "https://evil.example.com/logo.png",
      resultPageUrl: "https://evil.example.com/",
      link: "https://evil.example.com/x",
    });

    expect(result).toEqual({ok: true});
    const docs = mailDocs();
    expect(docs).toHaveLength(1);
    expect(docs[0].message.subject).toBe("Reset your password for Kit");
    expect(docs[0].message.html).not.toContain("Evil Corp");
    expect(docs[0].message.html).not.toContain("evil.example.com");
    expect(docs[0].message.html).toContain("#673AB7");
    expect(docs[0].message.html).toContain("lang=en");
    expect(docs[0].message.text).not.toContain("evil.example.com");
    expect(
      docs[0].message.html.split("https://demo.web.app/?mode=resetPassword")
        .length - 1,
    ).toBeGreaterThanOrEqual(1);
  });

  // eslint-disable-next-line max-len
  it("R6-a: 성공 · 없는 주소 · 조회 실패 · Admin 실패 · add 실패 · 초과 경로 모두 logger 인자에 이메일 · oobCode · IP 원문 0", async () => {
    const auth = anonymousCallerAuth(UID);
    const data = {email: REQUEST_EMAIL, locale: "ja"};
    await call(auth, data);

    mockGenerateResetLink.mockRejectedValueOnce(
      adminError("auth/email-not-found"),
    );
    await call(auth, data);

    // 계정 조회 서버 오류 — err.message(이메일 포함)가 로그에 실리면 안 된다.
    mockGetUserByEmail.mockRejectedValueOnce(adminError("auth/internal-error"));
    await expect(call(auth, data)).rejects.toMatchObject({
      code: "internal",
      message: "errorUnknown",
    });

    // 있는 계정(조회 성공)의 링크 생성 internal-error 는 진짜 서버 오류다.
    mockGenerateResetLink.mockRejectedValueOnce(
      adminError("auth/internal-error"),
    );
    await expect(call(auth, data)).rejects.toMatchObject({
      code: "internal",
      message: "errorUnknown",
    });

    mockMailAdd.mockRejectedValueOnce(new Error(`write ${ADMIN_LINK}`));
    await expect(call(auth, data)).rejects.toMatchObject({
      code: "internal",
      message: "errorUnknown",
    });

    counters.set(EMAIL_DOC, {count: 3, ageSec: 30});
    await expect(call(auth, data)).rejects.toMatchObject({
      code: "resource-exhausted",
    });

    expect(warnMock).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "password_reset_mail_failed",
        uid: UID,
        code: "auth/internal-error",
      }),
      expect.any(String),
    );
    expect(warnMock).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "password_reset_mail_lookup_failed",
        uid: UID,
        code: "auth/internal-error",
      }),
      expect.any(String),
    );
    const text = allLogText();
    expect(text).not.toContain(REQUEST_EMAIL);
    expect(text).not.toContain("oobCode");
    expect(text).not.toContain("OOB_RESET_SENTINEL");
    expect(text).not.toContain("firebaseapp.com");
    expect(text).not.toContain("web.app");
    expect(text).not.toContain(CLIENT_IP);
  });

  // eslint-disable-next-line max-len
  it("R6-b: 브랜드 env appName 빈 값 → internal + email_brand_unset · 링크 · add 0", async () => {
    mockEnv.EMAIL_APP_NAME = "";

    await expect(
      call(anonymousCallerAuth(UID), {email: REQUEST_EMAIL, locale: "ko"}),
    ).rejects.toMatchObject({code: "internal", message: "errorUnknown"});
    expect(errorMock).toHaveBeenCalledWith(
      expect.objectContaining({event: "email_brand_unset"}),
      expect.any(String),
    );
    expect(mockGenerateResetLink).not.toHaveBeenCalled();
    expect(mockMailAdd).not.toHaveBeenCalled();
    expect(mockGetUserByEmail).not.toHaveBeenCalled();
  });

  // eslint-disable-next-line max-len
  it("R7: 결과 페이지 env 빈 값 → 있는 주소 · 없는 주소 모두 같은 internal · 링크 생성 · rate limit · add 0", async () => {
    mockEnv.EMAIL_RESULT_PAGE_URL = "";
    const auth = anonymousCallerAuth(UID);

    // 있는 주소 — Admin mock 은 링크를 돌려주도록 둔다.
    const existing = await call(auth, {email: REQUEST_EMAIL, locale: "ko"})
      .then(() => null, (err: unknown) => err);
    // 없는 주소 — Admin mock 이 계정 없음으로 거부하도록 둔다.
    mockGenerateResetLink.mockRejectedValueOnce(
      adminError("auth/email-not-found"),
    );
    const missing = await call(auth, {
      email: "no-account@example.com",
      locale: "ko",
    }).then(() => null, (err: unknown) => err);

    for (const err of [existing, missing]) {
      expect(err).toBeInstanceOf(HttpsError);
      expect(err).toMatchObject({code: "internal", message: "errorUnknown"});
    }
    expect(mockGenerateResetLink).not.toHaveBeenCalled();
    expect(mockOrdered.calls).toEqual([]);
    expect(
      errorMock.mock.calls.filter(
        (args) =>
          (args[0] as {event?: string}).event === "email_result_page_unset",
      ),
    ).toHaveLength(2);
    expect(mockMailAdd).not.toHaveBeenCalled();
    expect(mockGetUserByEmail).not.toHaveBeenCalled();
  });

  // eslint-disable-next-line max-len
  it("R8: Admin 링크에 oobCode 없음 → internal + password_reset_mail_failed · add 0 · 로그에 호스트 0", async () => {
    mockGenerateResetLink.mockResolvedValue(
      "https://demo.firebaseapp.com/__/auth/action?mode=resetPassword" +
        "&apiKey=fake-api-key",
    );

    await expect(
      call(anonymousCallerAuth(UID), {email: REQUEST_EMAIL, locale: "ko"}),
    ).rejects.toMatchObject({code: "internal", message: "errorUnknown"});
    expect(warnMock).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "password_reset_mail_failed",
        uid: UID,
      }),
      expect.any(String),
    );
    expect(mockMailAdd).not.toHaveBeenCalled();
    const text = allLogText();
    expect(text).not.toContain(REQUEST_EMAIL);
    expect(text).not.toContain("firebaseapp.com");
    expect(text).not.toContain("web.app");
    expect(text).not.toContain("fake-api-key");
  });

  // eslint-disable-next-line max-len
  it("R9: 열거 보호 모양(조회 auth/user-not-found · 링크 생성 auth/internal-error) → 링크 생성 0 · 메일 0 · 있는 주소와 같은 {ok: true}", async () => {
    // dev 실측 모양 (D-23 · G-P12-2): 열거 보호가 켜진 프로젝트에서 없는
    // 주소는 accounts:lookup 이 users 없음 → auth/user-not-found, 링크 생성은
    // oobLink 없음 → auth/internal-error 다.
    mockGetUserByEmail.mockRejectedValueOnce(
      adminError("auth/user-not-found"),
    );
    mockGenerateResetLink.mockRejectedValue(adminError("auth/internal-error"));

    const result = await call(anonymousCallerAuth(UID), {
      email: REQUEST_EMAIL,
      locale: "ko",
    });

    expect(mockGetUserByEmail).toHaveBeenCalledTimes(1);
    expect(mockGetUserByEmail).toHaveBeenCalledWith(REQUEST_EMAIL);
    expect(mockGenerateResetLink).not.toHaveBeenCalled();
    expectNoAccountResponse(result);
  });

  // eslint-disable-next-line max-len
  it("R10: 조회 auth/invalid-email → invalid-argument · 링크 생성 0 · 메일 0", async () => {
    mockGetUserByEmail.mockRejectedValueOnce(adminError("auth/invalid-email"));

    await expect(
      call(anonymousCallerAuth(UID), {email: "not-an-email", locale: "ko"}),
    ).rejects.toMatchObject({
      code: "invalid-argument",
      message: "errorInvalidArgument",
    });
    expect(mockGetUserByEmail).toHaveBeenCalledTimes(1);
    expect(mockGenerateResetLink).not.toHaveBeenCalled();
    expect(mockMailAdd).not.toHaveBeenCalled();
    expect(noAccountInfoCalls()).toHaveLength(0);
  });

  // eslint-disable-next-line max-len
  it("R11: 조회 서버 오류(auth/internal-error) → internal + password_reset_mail_lookup_failed · 링크 생성 0 · 메일 0 · 로그에 이메일 0", async () => {
    mockGetUserByEmail.mockRejectedValueOnce(adminError("auth/internal-error"));

    await expect(
      call(anonymousCallerAuth(UID), {email: REQUEST_EMAIL, locale: "ko"}),
    ).rejects.toMatchObject({code: "internal", message: "errorUnknown"});
    expect(warnMock).toHaveBeenCalledTimes(1);
    expect(warnMock).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "password_reset_mail_lookup_failed",
        uid: UID,
        code: "auth/internal-error",
      }),
      expect.any(String),
    );
    expect(mockGenerateResetLink).not.toHaveBeenCalled();
    expect(mockMailAdd).not.toHaveBeenCalled();
    expect(noAccountInfoCalls()).toHaveLength(0);
    expect(allLogText()).not.toContain(REQUEST_EMAIL);
  });

  // eslint-disable-next-line max-len
  it("R12: 있는 주소 · 없는 주소(조회 user-not-found) · 경합(생성 email-not-found) 세 응답이 같고 셋 다 rate limit 3축을 소비한다", async () => {
    const auth = anonymousCallerAuth(UID);
    const data = {email: REQUEST_EMAIL, locale: "ko"};
    const setsPerCall: number[] = [];

    // 있는 주소 (기본 mock).
    const existing = await call(auth, data);
    setsPerCall.push(mockOrdered.sets.length);

    // 없는 주소 — 조회 단계에서 계정 없음.
    mockGetUserByEmail.mockRejectedValueOnce(
      adminError("auth/user-not-found"),
    );
    const missing = await call(auth, data);
    setsPerCall.push(mockOrdered.sets.length);

    // 경합 — 조회는 있음 · 링크 생성 때 계정 없음.
    mockGenerateResetLink.mockRejectedValueOnce(
      adminError("auth/email-not-found"),
    );
    const raced = await call(auth, data);
    setsPerCall.push(mockOrdered.sets.length);

    expect(existing).toEqual({ok: true});
    expect(missing).toEqual(existing);
    expect(raced).toEqual(existing);
    expect(setsPerCall).toEqual([3, 3, 3]);
    // 메일은 있는 주소 1번뿐.
    expect(mailDocs()).toHaveLength(1);
    expect(noAccountInfoCalls()).toHaveLength(2);
    expect(warnMock).not.toHaveBeenCalled();
    expect(errorMock).not.toHaveBeenCalled();
  });
});
