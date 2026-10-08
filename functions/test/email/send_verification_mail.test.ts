/**
 * sendVerificationMail onCall 회귀 테스트 (Phase 17.5 plan 05 · D-11 · D-15 ·
 * 17 D-26).
 *
 * kit 모드 인증 메일 callable — 서버가 검증한 ID token 의 `email` 로 Admin
 * 링크를 만들고 결과 페이지 링크로 재작성(`toResultPageLink` — 쿼리 보존 ·
 * `lang` 부착, D-22 ①)해 실제 `renderMail` 로 렌더한 뒤 Firestore `mail/` 에
 * `{to, message}` 를 add 한다. `renderMail` 은 mock 하지 않는다(렌더 관통).
 *
 * **Mock 한계:** Admin 링크 · Firestore add · transaction 은 mock 이다. rate
 * limit transaction 은 `createOrderedTx` 로 reads-before-writes 를 강제한다
 * (memory feedback_mock_transaction_constraint). 실 확장 발송은 plan 12 UAT.
 *
 * 시나리오 (plan 05 Task 1 V1~V7 · plan 14 V8~V10):
 *  - V1: 관통 — 토큰 email · ja → 링크 1회 · mail add 1회 · ja 제목 · 결과
 *    페이지 링크(`https://demo.web.app/?mode=…&lang=ja`) · 원 링크 호스트 0
 *  - V2: 요청 본문 email · appName · resultPageUrl · link 위조 무시 (17 D-26 ·
 *    D-22 ②)
 *  - V3: 익명 caller 거부 (failed-precondition + reason)
 *  - V4: 미인증 · 토큰 email 없음 · 이미 인증됨
 *  - V5: uid 축 · 이메일 해시 축 rate limit 초과 → resource-exhausted + 알람
 *  - V6: 브랜드 env 미설정 → internal + email_brand_unset
 *  - V7: logger 인자에 이메일 · oobCode · 링크 · 결과 페이지 호스트 0
 *  - V8: 결과 페이지 env 빈 값 · `http://` → internal + email_result_page_unset
 *    · 링크 생성 · rate limit · add 0 (D-22 ③)
 *  - V9: Admin 링크가 web.app 기본 핸들러여도 V1 과 같은 링크 (A1 무관)
 *  - V10: Admin 링크에 oobCode 없음 → internal + verification_mail_failed ·
 *    add 0 · 로그에 호스트 0
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

const mockGenerateVerifyLink = jest.fn();
jest.mock("firebase-admin/auth", () => ({
  getAuth: jest.fn(() => ({
    generateEmailVerificationLink: mockGenerateVerifyLink,
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

/** 토큰 email fixture — 로그에 나오면 안 된다. */
const TOKEN_EMAIL = "pii-verify-sentinel@example.com";

/** Admin 링크 fixture — oobCode · 링크 모두 로그에 나오면 안 된다. */
const ADMIN_LINK =
  "https://demo.firebaseapp.com/__/auth/action?mode=verifyEmail" +
  "&oobCode=OOB_SENTINEL_123&apiKey=fake-api-key";

/** 결과 페이지 env 값 fixture (`EMAIL_RESULT_PAGE_URL`). */
const RESULT_PAGE_URL = "https://demo.web.app/";

/** [ADMIN_LINK] 를 [RESULT_PAGE_URL] 로 재작성한 ja 링크 (D-22 ①). */
const RESULT_LINK_JA =
  "https://demo.web.app/?mode=verifyEmail" +
  "&oobCode=OOB_SENTINEL_123&apiKey=fake-api-key&lang=ja";

/** `mail/` add 1건의 payload 모양. */
type MailDoc = {
  to: string[];
  message: {subject: string; html: string; text: string};
};

/** rate limit 문서 id → `{count, ageSec}` fixture (없으면 문서 없음). */
let counters: Map<string, {count: number; ageSec: number}>;

/**
 * [counters] fixture 를 읽는 순서 강제 transaction 을 만든다.
 *
 * @return {OrderedTxHandle} 새 transaction handle.
 */
function newTx(): OrderedTxHandle {
  return createOrderedTx((ref: unknown) => {
    const label = (ref as {label: string}).label;
    const docId = label.replace(/^rate_limits\//, "");
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

/**
 * 정식 로그인 caller 로 callable 을 호출한다.
 *
 * @param {Record<string, unknown>} token ID token claim (sign_in_provider 포함).
 * @param {unknown} data callable data.
 * @return {Promise<unknown>} callable 결과.
 */
function callAs(
  token: Record<string, unknown>,
  data: unknown,
): Promise<unknown> {
  const wrapped = testEnv.wrap(myFunctions.sendVerificationMail);
  return wrapped({
    auth: {uid: "u-verify", token},
    app: {appId: "test"},
    data,
  } as never);
}

/** 미인증 정식 사용자(비밀번호 가입) 토큰 fixture. */
const UNVERIFIED_TOKEN = {
  email: TOKEN_EMAIL,
  email_verified: false,
  firebase: {sign_in_provider: "password"},
};

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

describe("sendVerificationMail onCall — Phase 17.5 D-11 (T-175-VMAIL)", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockEnv.EMAIL_APP_NAME = "Kit";
    mockEnv.EMAIL_BRAND_COLOR = "#673AB7";
    mockEnv.EMAIL_LOGO_URL = "";
    mockEnv.EMAIL_RESULT_PAGE_URL = RESULT_PAGE_URL;
    counters = new Map();
    mockNewTx = newTx;
    // transaction 이 한 번도 열리지 않은 경우의 기록 (빈 handle).
    mockOrdered = newTx();
    mockGenerateVerifyLink.mockReset();
    mockGenerateVerifyLink.mockResolvedValue(ADMIN_LINK);
    mockMailAdd.mockReset();
    mockMailAdd.mockResolvedValue({id: "mail-1"});
  });

  // eslint-disable-next-line max-len
  it("V1: 토큰 email 로 링크 → 결과 페이지 링크(lang=ja) → renderMail → mail add 1회 → {ok: true}", async () => {
    const result = await callAs(UNVERIFIED_TOKEN, {locale: "ja"});

    expect(result).toEqual({ok: true});
    expect(mockGenerateVerifyLink).toHaveBeenCalledTimes(1);
    expect(mockGenerateVerifyLink).toHaveBeenCalledWith(TOKEN_EMAIL);
    const docs = mailDocs();
    expect(docs).toHaveLength(1);
    expect(docs[0].to).toEqual([TOKEN_EMAIL]);
    expect(docs[0].message.subject).toBe("Kitのメールアドレス確認");
    expect(docs[0].message.html).toContain("lang=ja");
    expect(docs[0].message.html).toContain("oobCode=OOB_SENTINEL_123");
    expect(docs[0].message.html).not.toContain("&#x3D;");
    expect(docs[0].message.text).toContain("lang=ja");
    // 링크 = 결과 페이지 재작성 결과 · 원 링크 호스트 0 (D-22 ①).
    expect(docs[0].message.html).toContain(`href="${RESULT_LINK_JA}"`);
    expect(docs[0].message.text).toContain(RESULT_LINK_JA);
    expect(docs[0].message.html).not.toContain("demo.firebaseapp.com");
    expect(docs[0].message.text).not.toContain("demo.firebaseapp.com");
    // rate limit 2축이 같은 transaction 에서 read 뒤 새 창으로 쓰였다.
    expect(mockOrdered.calls).toEqual(["get", "get", "set", "set"]);
  });

  // eslint-disable-next-line max-len
  it("V2: 요청 본문의 email · appName · brandColor · resultPageUrl · link 는 무시하고 토큰 email · env 값만 쓴다", async () => {
    const result = await callAs(UNVERIFIED_TOKEN, {
      locale: "ko",
      email: "evil@example.com",
      appName: "X",
      brandColor: "#000000",
      logoUrl: "https://evil.example.com/logo.png",
      resultPageUrl: "https://evil.example.com/",
      link: "https://evil.example.com/x",
    });

    expect(result).toEqual({ok: true});
    expect(mockGenerateVerifyLink).toHaveBeenCalledWith(TOKEN_EMAIL);
    const docs = mailDocs();
    expect(docs).toHaveLength(1);
    expect(docs[0].to).toEqual([TOKEN_EMAIL]);
    expect(docs[0].message.subject).toBe("Kit 이메일 주소 인증");
    expect(docs[0].message.html).not.toContain("evil@");
    expect(docs[0].message.html).not.toContain("evil.example.com");
    expect(docs[0].message.html).toContain("#673AB7");
    expect(docs[0].message.text).not.toContain("evil.example.com");
    expect(
      docs[0].message.html.split("https://demo.web.app/?mode=verifyEmail")
        .length - 1,
    ).toBeGreaterThanOrEqual(1);
  });

  // eslint-disable-next-line max-len
  it("V3: 익명 caller → failed-precondition + reason anonymous_caller · 링크 · add 0", async () => {
    const promise = callAs(
      {firebase: {sign_in_provider: "anonymous"}},
      {locale: "ko"},
    );
    await expect(promise).rejects.toBeInstanceOf(HttpsError);
    await expect(promise).rejects.toMatchObject({
      code: "failed-precondition",
      details: {reason: "anonymous_caller"},
    });
    expect(mockGenerateVerifyLink).not.toHaveBeenCalled();
    expect(mockMailAdd).not.toHaveBeenCalled();
  });

  it("V4-a: request.auth 없음 → unauthenticated", async () => {
    const wrapped = testEnv.wrap(myFunctions.sendVerificationMail);
    const promise = wrapped({
      app: {appId: "test"},
      data: {locale: "ko"},
    } as never);
    await expect(promise).rejects.toMatchObject({
      code: "unauthenticated",
      message: "errorUnauthenticated",
    });
    expect(mockMailAdd).not.toHaveBeenCalled();
  });

  it("V4-b: 토큰 email 없음 → failed-precondition · 링크 · add 0", async () => {
    const promise = callAs(
      {firebase: {sign_in_provider: "custom"}},
      {locale: "ko"},
    );
    await expect(promise).rejects.toMatchObject({
      code: "failed-precondition",
    });
    expect(mockGenerateVerifyLink).not.toHaveBeenCalled();
    expect(mockMailAdd).not.toHaveBeenCalled();
  });

  // eslint-disable-next-line max-len
  it("V4-c: 이미 email_verified → 메일 없이 {ok: true} · rate limit 소비 0", async () => {
    const result = await callAs(
      {...UNVERIFIED_TOKEN, email_verified: true},
      {locale: "ko"},
    );
    expect(result).toEqual({ok: true});
    expect(mockGenerateVerifyLink).not.toHaveBeenCalled();
    expect(mockMailAdd).not.toHaveBeenCalled();
    expect(mockOrdered.calls).toEqual([]);
    expect(infoMock).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "verification_mail_already_verified",
        uid: "u-verify",
      }),
      expect.any(String),
    );
  });

  // eslint-disable-next-line max-len
  it("V5-a: uid 축 6번째 호출 → resource-exhausted + verification_mail_rate_limited(axis uid)", async () => {
    counters.set("sendVerificationMail:u-verify", {count: 5, ageSec: 60});

    const promise = callAs(UNVERIFIED_TOKEN, {locale: "ko"});
    await expect(promise).rejects.toMatchObject({
      code: "resource-exhausted",
      message: "errorTooManyRequests",
    });
    expect(warnMock).toHaveBeenCalledWith(
      {
        event: "verification_mail_rate_limited",
        uid: "u-verify",
        axis: "uid",
        count: 5,
      },
      expect.any(String),
    );
    expect(mockGenerateVerifyLink).not.toHaveBeenCalled();
    expect(mockMailAdd).not.toHaveBeenCalled();
    // 초과 시 counter write 0.
    expect(mockOrdered.sets).toHaveLength(0);
    expect(mockOrdered.updates).toHaveLength(0);
  });

  // eslint-disable-next-line max-len
  it("V5-b: 이메일 해시 축 초과 → resource-exhausted + axis email · 문서 id 에 원문 0", async () => {
    const emailDocId = `sendVerificationMailEmail:${hashEmail(TOKEN_EMAIL)}`;
    counters.set(emailDocId, {count: 5, ageSec: 60});

    const promise = callAs(UNVERIFIED_TOKEN, {locale: "ko"});
    await expect(promise).rejects.toMatchObject({
      code: "resource-exhausted",
    });
    expect(warnMock).toHaveBeenCalledWith(
      {
        event: "verification_mail_rate_limited",
        uid: "u-verify",
        axis: "email",
        count: 5,
      },
      expect.any(String),
    );
    expect(emailDocId).not.toContain("@");
    expect(mockMailAdd).not.toHaveBeenCalled();
  });

  it("V5-c: 창이 지난 counter 는 새 창으로 리셋해 허용한다", async () => {
    counters.set("sendVerificationMail:u-verify", {count: 5, ageSec: 601});

    const result = await callAs(UNVERIFIED_TOKEN, {locale: "ko"});
    expect(result).toEqual({ok: true});
    expect(mockOrdered.sets).toHaveLength(2);
  });

  // eslint-disable-next-line max-len
  it("V6: 브랜드 env appName 빈 값 → internal + email_brand_unset · 링크 · add 0", async () => {
    mockEnv.EMAIL_APP_NAME = "   ";

    const promise = callAs(UNVERIFIED_TOKEN, {locale: "ko"});
    await expect(promise).rejects.toMatchObject({
      code: "internal",
      message: "errorUnknown",
    });
    expect(errorMock).toHaveBeenCalledWith(
      expect.objectContaining({event: "email_brand_unset"}),
      expect.any(String),
    );
    expect(mockGenerateVerifyLink).not.toHaveBeenCalled();
    expect(mockMailAdd).not.toHaveBeenCalled();
  });

  // eslint-disable-next-line max-len
  it("V7: 성공 · Admin 실패 · add 실패 경로 모두 logger 인자에 이메일 · oobCode · 링크 0", async () => {
    await callAs(UNVERIFIED_TOKEN, {locale: "en"});

    const adminErr = Object.assign(new Error(`bad ${TOKEN_EMAIL}`), {
      code: "auth/internal-error",
    });
    mockGenerateVerifyLink.mockRejectedValueOnce(adminErr);
    await expect(
      callAs(UNVERIFIED_TOKEN, {locale: "en"}),
    ).rejects.toMatchObject({code: "internal", message: "errorUnknown"});

    mockMailAdd.mockRejectedValueOnce(new Error(`write ${ADMIN_LINK}`));
    await expect(
      callAs(UNVERIFIED_TOKEN, {locale: "en"}),
    ).rejects.toMatchObject({code: "internal", message: "errorUnknown"});

    expect(warnMock).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "verification_mail_failed",
        uid: "u-verify",
        code: "auth/internal-error",
      }),
      expect.any(String),
    );
    const text = allLogText();
    expect(text).not.toContain(TOKEN_EMAIL);
    expect(text).not.toContain("oobCode");
    expect(text).not.toContain("OOB_SENTINEL_123");
    expect(text).not.toContain("firebaseapp.com");
    expect(text).not.toContain("web.app");
  });

  it.each([
    ["빈 값", ""],
    ["http://", "http://demo.web.app/"],
  ])(
    // eslint-disable-next-line max-len
    "V8: 결과 페이지 env %s → internal + email_result_page_unset · 링크 · rate limit · add 0",
    async (_label, value) => {
      mockEnv.EMAIL_RESULT_PAGE_URL = value;

      const promise = callAs(UNVERIFIED_TOKEN, {locale: "ko"});
      await expect(promise).rejects.toBeInstanceOf(HttpsError);
      await expect(promise).rejects.toMatchObject({
        code: "internal",
        message: "errorUnknown",
      });
      expect(errorMock).toHaveBeenCalledWith(
        {event: "email_result_page_unset"},
        expect.any(String),
      );
      expect(mockGenerateVerifyLink).not.toHaveBeenCalled();
      expect(mockMailAdd).not.toHaveBeenCalled();
      expect(mockOrdered.calls).toEqual([]);
    },
  );

  // eslint-disable-next-line max-len
  it("V9: Admin 링크가 web.app 기본 핸들러여도 V1 과 같은 결과 페이지 링크다 (A1 무관)", async () => {
    mockGenerateVerifyLink.mockResolvedValue(
      "https://demo.web.app/__/auth/action?mode=verifyEmail" +
        "&oobCode=OOB_SENTINEL_123&apiKey=fake-api-key",
    );

    const result = await callAs(UNVERIFIED_TOKEN, {locale: "ja"});

    expect(result).toEqual({ok: true});
    const docs = mailDocs();
    expect(docs).toHaveLength(1);
    expect(docs[0].message.html).toContain(`href="${RESULT_LINK_JA}"`);
    expect(docs[0].message.text).toContain(RESULT_LINK_JA);
    expect(docs[0].message.html).not.toContain("/__/auth/action");
    expect(docs[0].message.text).not.toContain("/__/auth/action");
  });

  // eslint-disable-next-line max-len
  it("V10: Admin 링크에 oobCode 없음 → internal + verification_mail_failed · add 0 · 로그에 호스트 0", async () => {
    mockGenerateVerifyLink.mockResolvedValue(
      "https://demo.firebaseapp.com/__/auth/action?mode=verifyEmail" +
        "&apiKey=fake-api-key",
    );

    const promise = callAs(UNVERIFIED_TOKEN, {locale: "ko"});
    await expect(promise).rejects.toMatchObject({
      code: "internal",
      message: "errorUnknown",
    });
    expect(warnMock).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "verification_mail_failed",
        uid: "u-verify",
      }),
      expect.any(String),
    );
    expect(mockMailAdd).not.toHaveBeenCalled();
    const text = allLogText();
    expect(text).not.toContain(TOKEN_EMAIL);
    expect(text).not.toContain("firebaseapp.com");
    expect(text).not.toContain("web.app");
    expect(text).not.toContain("fake-api-key");
  });
});

describe("hashEmail — rate limit 문서 id 용 이메일 해시", () => {
  it("trim · 소문자 정규화 뒤 sha256 앞 32 hex 다", () => {
    const hash = hashEmail("A@Example.com ");
    expect(hash).toMatch(/^[0-9a-f]{32}$/);
    expect(hash).toBe(hashEmail("a@example.com"));
    expect(hash).not.toBe(hashEmail("b@example.com"));
  });
});
