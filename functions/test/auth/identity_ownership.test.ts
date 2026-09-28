/**
 * identity_ownership helper 테스트 (Phase 16.10 plan 02 · D-08).
 *
 * `assertIdentityOwnedByCaller` 는 db 를 인자로 받으므로 Firestore 모듈 mock
 * 대신 `collection().doc().get()` 모양의 객체를 직접 주입한다 (tx 0 ·
 * write 0 — 읽기 1회만 검사).
 *
 * 시나리오:
 *  - IO1: owner == caller → resolve · get 1회 · 문서 id 형식
 *  - IO2: 다른 owner → permission-denied(caller_identity_mismatch)
 *  - IO3: 문서 없음 → IO2 와 같은 거부 (존재 여부 비노출)
 *  - IO4: get throw → internal · fingerprint 로그
 *  - IO5: readStringField — 비객체 · 비문자열 → undefined
 *
 * PII: providerUserId(`PII_IO_PROVIDER_USER_ID`)는 HttpsError details 와
 * logger 호출 인자 어디에도 나오면 안 된다.
 */

jest.mock("firebase-functions/logger", () => ({
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
  debug: jest.fn(),
  log: jest.fn(),
}));

// eslint-disable-next-line import/first
import * as logger from "firebase-functions/logger";
// eslint-disable-next-line import/first
import {HttpsError} from "firebase-functions/https";
// eslint-disable-next-line import/first
import type {Firestore} from "firebase-admin/firestore";
// eslint-disable-next-line import/first
import {
  assertIdentityOwnedByCaller,
  readStringField,
} from "../../src/auth/identity_ownership";

const warnMock = logger.warn as unknown as jest.Mock;
const errorMock = logger.error as unknown as jest.Mock;

/** caller UID. */
const CALLER_UID = "caller-uid-io";

/** provider 사용자 식별자 fixture — 로그 · details 금지 대상. */
const PROVIDER_USER_ID = "PII_IO_PROVIDER_USER_ID";

/** 주입 db 와 호출 기록. */
type InjectedDb = {
  db: Firestore;
  collection: jest.Mock;
  doc: jest.Mock;
  get: jest.Mock;
};

/**
 * `collection().doc().get()` 모양의 db 를 만든다.
 *
 * @param {jest.Mock} get `doc().get()` 구현.
 * @return {InjectedDb} 주입용 db 와 호출 기록 mock.
 */
function makeDb(get: jest.Mock): InjectedDb {
  const doc = jest.fn(() => ({get}));
  const collection = jest.fn(() => ({doc}));
  return {db: {collection} as unknown as Firestore, collection, doc, get};
}

/**
 * snapshot fixture 를 돌려주는 get mock 을 만든다.
 *
 * @param {Record<string, unknown> | undefined} data 문서 data
 *     (undefined = 문서 없음).
 * @return {jest.Mock} get mock.
 */
function snapshotGet(data: Record<string, unknown> | undefined): jest.Mock {
  return jest.fn(async () => ({
    exists: data !== undefined,
    data: () => data,
  }));
}

/**
 * helper 를 호출하고 HttpsError 를 꺼낸다 (details 에 PII 부재 단언).
 *
 * @param {Firestore} db 주입 db.
 * @return {Promise<HttpsError>} 던져진 HttpsError.
 */
async function captureOwnershipError(db: Firestore): Promise<HttpsError> {
  const err = await assertIdentityOwnedByCaller({
    db,
    provider: "kakao",
    providerUserId: PROVIDER_USER_ID,
    callerUid: CALLER_UID,
  }).then(
    () => undefined,
    (e: unknown) => e,
  );
  expect(err).toBeInstanceOf(HttpsError);
  const httpsErr = err as HttpsError;
  expect(
    JSON.stringify({message: httpsErr.message, details: httpsErr.details}),
  ).not.toContain(PROVIDER_USER_ID);
  return httpsErr;
}

beforeEach(() => {
  jest.clearAllMocks();
});

afterEach(() => {
  // 모든 케이스 — logger 인자에 providerUserId · 문서 id 0.
  const serialized = JSON.stringify([
    ...warnMock.mock.calls,
    ...errorMock.mock.calls,
    ...(logger.info as unknown as jest.Mock).mock.calls,
  ]);
  expect(serialized).not.toContain(PROVIDER_USER_ID);
});

describe("assertIdentityOwnedByCaller — 소유 대조 (D-08)", () => {
  it("IO1: owner == caller → resolve · 원장 문서 1회 읽기", async () => {
    const injected = makeDb(snapshotGet({firebaseUid: CALLER_UID}));

    await expect(
      assertIdentityOwnedByCaller({
        db: injected.db,
        provider: "kakao",
        providerUserId: PROVIDER_USER_ID,
        callerUid: CALLER_UID,
      }),
    ).resolves.toBeUndefined();
    expect(injected.collection).toHaveBeenCalledWith("identity_index");
    expect(injected.doc).toHaveBeenCalledWith(`kakao:${PROVIDER_USER_ID}`);
    expect(injected.get).toHaveBeenCalledTimes(1);
    expect(warnMock).not.toHaveBeenCalled();
  });

  it("IO2: 다른 owner → caller_identity_mismatch 거부", async () => {
    const injected = makeDb(snapshotGet({firebaseUid: "other-uid"}));

    const err = await captureOwnershipError(injected.db);
    expect(err.code).toBe("permission-denied");
    expect(err.message).toBe("errorReauthUserMismatch");
    expect(err.details).toEqual({reason: "caller_identity_mismatch"});
    expect(warnMock).toHaveBeenCalledWith(
      {
        event: "identity_ownership_mismatch",
        uid: CALLER_UID,
        provider: "kakao",
      },
      expect.any(String),
    );
  });

  it("IO3: 문서 없음 → IO2 와 같은 거부", async () => {
    const injected = makeDb(snapshotGet(undefined));

    const err = await captureOwnershipError(injected.db);
    expect(err.code).toBe("permission-denied");
    expect(err.message).toBe("errorReauthUserMismatch");
    expect(err.details).toEqual({reason: "caller_identity_mismatch"});
  });

  it("IO4: get throw → internal · fingerprint 로그", async () => {
    const injected = makeDb(
      jest.fn(async () => {
        throw Object.assign(new Error(PROVIDER_USER_ID), {code: "unavailable"});
      }),
    );

    const err = await captureOwnershipError(injected.db);
    expect(err.code).toBe("internal");
    expect(err.message).toBe("errorUnknown");
    expect(errorMock).toHaveBeenCalledWith(
      {
        event: "identity_ownership_read_failed",
        provider: "kakao",
        code: "unavailable",
      },
      expect.any(String),
    );
  });
});

describe("readStringField", () => {
  it("IO5: 비객체 · 비문자열 필드 → undefined, 문자열 → 값", () => {
    expect(readStringField(null, "k")).toBeUndefined();
    expect(readStringField("k", "k")).toBeUndefined();
    expect(readStringField(undefined, "k")).toBeUndefined();
    expect(readStringField({k: 1}, "k")).toBeUndefined();
    expect(readStringField({}, "k")).toBeUndefined();
    expect(readStringField({k: "v"}, "k")).toBe("v");
  });
});
