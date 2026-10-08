/**
 * sendPasswordResetMail onCall 회귀 테스트 (Phase 17.5 plan 05 · D-10 · D-11 ·
 * D-15).
 *
 * kit 모드 재설정 메일 callable — 로그인 전 요청이라 익명 세션도 받고, 가입
 * 여부를 드러내지 않는다(없는 주소 = 같은 `{ok: true}`). rate limit 3축(uid ·
 * IP 해시 · 이메일 해시)을 링크 생성 **전** 한 transaction 에서 판정한다.
 * `renderMail` 은 mock 하지 않는다(렌더 관통).
 *
 * **Mock 한계:** Admin 링크 · Firestore add · transaction 은 mock 이다. rate
 * limit transaction 은 `createOrderedTx` 로 reads-before-writes 를 강제한다
 * (memory feedback_mock_transaction_constraint). 실 확장 발송은 plan 12 UAT.
 *
 * 시나리오 (plan 05 Task 2 R1~R6):
 *  - R1: 익명 caller · 있는 주소 → 링크 1회 · mail add 1회 · ko 제목 · lang=ko
 *  - R2: 없는 주소(email-not-found) → add 0 · R1 과 같은 반환
 *  - R3: 미인증 · email 누락 · 321자 · Admin invalid-email → 각 오류 코드
 *  - R4: 이메일 · uid · IP 축 초과 → resource-exhausted + 알람 · 링크 생성 0
 *  - R5: 정식 caller 허용 · 요청 브랜드 값 무시
 *  - R6: logger 인자에 이메일 · oobCode · IP 원문 0 · env 미설정 → internal
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
jest.mock("firebase-admin/auth", () => ({
  getAuth: jest.fn(() => ({
    generatePasswordResetLink: mockGenerateResetLink,
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
import {createHash} from "node:crypto";
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

/** caller uid fixture. */
const UID = "u-reset";

/** rate limit 문서 id 들 (fixture 키). */
const UID_DOC = `sendPasswordResetMail:${UID}`;
const IP_DOC = "sendPasswordResetMailIp:" +
  createHash("sha256").update(CLIENT_IP).digest("hex").slice(0, 32);
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

describe("sendPasswordResetMail onCall — Phase 17.5 D-10 (T-175-RMAIL)", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockEnv.EMAIL_APP_NAME = "Kit";
    mockEnv.EMAIL_BRAND_COLOR = "#673AB7";
    mockEnv.EMAIL_LOGO_URL = "";
    counters = new Map();
    readDocIds = [];
    mockNewTx = newTx;
    // transaction 이 한 번도 열리지 않은 경우의 기록 (빈 handle).
    mockOrdered = newTx();
    mockGenerateResetLink.mockReset();
    mockGenerateResetLink.mockResolvedValue(ADMIN_LINK);
    mockMailAdd.mockReset();
    mockMailAdd.mockResolvedValue({id: "mail-1"});
  });

  // eslint-disable-next-line max-len
  it("R1: 익명 caller · 있는 주소 → 링크 → lang=ko → renderMail → mail add 1회 → {ok: true}", async () => {
    const result = await call(anonymousCallerAuth(UID), {
      email: REQUEST_EMAIL,
      locale: "ko",
    });

    expect(result).toEqual({ok: true});
    expect(mockGenerateResetLink).toHaveBeenCalledTimes(1);
    expect(mockGenerateResetLink).toHaveBeenCalledWith(REQUEST_EMAIL);
    const docs = mailDocs();
    expect(docs).toHaveLength(1);
    expect(docs[0].to).toEqual([REQUEST_EMAIL]);
    expect(docs[0].message.subject).toBe("Kit 비밀번호 재설정");
    expect(docs[0].message.html).toContain("lang=ko");
    expect(docs[0].message.html).toContain("oobCode=OOB_RESET_SENTINEL");
    expect(docs[0].message.html).not.toContain("&#x3D;");
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
  it("R2: 없는 주소(auth/email-not-found) → 메일 0 · 있는 주소와 같은 {ok: true}", async () => {
    mockGenerateResetLink.mockRejectedValueOnce(
      adminError("auth/email-not-found"),
    );

    const result = await call(anonymousCallerAuth(UID), {
      email: REQUEST_EMAIL,
      locale: "ko",
    });

    expect(result).toEqual({ok: true});
    expect(mockMailAdd).not.toHaveBeenCalled();
    // 존재 여부와 무관하게 rate limit 은 소비된다(같은 제한).
    expect(mockOrdered.sets).toHaveLength(3);
    expect(infoMock).toHaveBeenCalledWith(
      {event: "password_reset_mail_no_account", uid: UID},
      expect.any(String),
    );
    // 오류 경로 로그(warn · error)는 남기지 않는다.
    expect(warnMock).not.toHaveBeenCalled();
    expect(errorMock).not.toHaveBeenCalled();
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
    // 판정은 링크 생성 전 — 없는 주소여도 같은 제한이다.
    expect(mockGenerateResetLink).not.toHaveBeenCalled();
    expect(mockMailAdd).not.toHaveBeenCalled();
    expect(mockOrdered.sets).toHaveLength(0);
    expect(mockOrdered.updates).toHaveLength(0);
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
  it("R5: 정식 caller 도 허용 · 요청의 appName · brandColor · logoUrl 은 무시한다", async () => {
    const result = await call(signedInCallerAuth(UID, "password"), {
      email: REQUEST_EMAIL,
      locale: "en",
      appName: "Evil Corp",
      brandColor: "#000000",
      logoUrl: "https://evil.example.com/logo.png",
    });

    expect(result).toEqual({ok: true});
    const docs = mailDocs();
    expect(docs).toHaveLength(1);
    expect(docs[0].message.subject).toBe("Reset your password for Kit");
    expect(docs[0].message.html).not.toContain("Evil Corp");
    expect(docs[0].message.html).not.toContain("evil.example.com");
    expect(docs[0].message.html).toContain("#673AB7");
    expect(docs[0].message.html).toContain("lang=en");
  });

  // eslint-disable-next-line max-len
  it("R6-a: 성공 · 없는 주소 · Admin 실패 · add 실패 · 초과 경로 모두 logger 인자에 이메일 · oobCode · IP 원문 0", async () => {
    const auth = anonymousCallerAuth(UID);
    const data = {email: REQUEST_EMAIL, locale: "ja"};
    await call(auth, data);

    mockGenerateResetLink.mockRejectedValueOnce(
      adminError("auth/email-not-found"),
    );
    await call(auth, data);

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
    const text = allLogText();
    expect(text).not.toContain(REQUEST_EMAIL);
    expect(text).not.toContain("oobCode");
    expect(text).not.toContain("OOB_RESET_SENTINEL");
    expect(text).not.toContain("firebaseapp.com");
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
  });
});
