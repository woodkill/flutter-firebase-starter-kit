import functionsTest from "firebase-functions-test";
import * as logger from "firebase-functions/logger";
import {CallableRequest, HttpsError} from "firebase-functions/https";

// firebase-functions/logger 의 export 는 read-only 라 jest.spyOn 가 동작하지 않는다.
// 모듈 자체를 mock 해 mock fn 으로 대체 (BL-02 hotfix).
jest.mock("firebase-functions/logger", () => ({
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
  debug: jest.fn(),
  log: jest.fn(),
}));

const testEnv = functionsTest();

// ping import 는 testEnv 초기화 이후 (firebase-functions-test 권장 패턴).
// eslint-disable-next-line import/first
import * as myFunctions from "../src/index";

const infoMock = logger.info as unknown as jest.Mock;
const warnMock = logger.warn as unknown as jest.Mock;

afterAll(() => testEnv.cleanup());

/**
 * BL-02 hotfix: `as any` 캐스트만으로는 `wrap()` 이 `request.auth` 를 정확히
 * 주입했는지 입증 못 하므로 (false positive 가능), logger mock 으로 ping 함수
 * 본문이 인증 분기에 진입했음을 명시 검증한다.
 *
 * 양성 케이스: event="ping_invoked" + uid="test-user-123" structured log
 * 음성 케이스: logger.info 미호출 + event="ping_unauthenticated" warn
 *           + HttpsError throw
 */
describe("ping onCall", () => {
  beforeEach(() => {
    infoMock.mockClear();
    warnMock.mockClear();
  });

  it("authenticated: ok=true + structured ping_invoked log", async () => {
    const wrapped = testEnv.wrap(myFunctions.ping);
    const result = await wrapped({
      auth: {uid: "test-user-123"},
      data: {},
    } as unknown as CallableRequest);

    // 1. 응답 셰이프 — region 잠금 + ISO timestamp
    const typed = result as {ok: boolean; region: string; serverTime: string};
    expect(typed.ok).toBe(true);
    expect(typed.region).toBe("asia-northeast3");
    expect(typed.serverTime).toMatch(/^\d{4}-\d{2}-\d{2}T/);

    // 2. BL-02: logger mock 으로 인증 분기 진입 입증.
    //    `as any` 캐스트로 wrap input 이 우회됐어도 함수 본문이 실제로
    //    `request.auth?.uid` 를 읽고 structured event 를 발행했는지 확인.
    expect(infoMock).toHaveBeenCalledTimes(1);
    const [payload] = infoMock.mock.calls[0] as [
      Record<string, unknown>,
      string,
    ];
    expect(payload).toMatchObject({
      event: "ping_invoked",
      uid: "test-user-123",
    });

    // 3. 음성 분기 (warn) 는 호출되지 않아야 함.
    expect(warnMock).not.toHaveBeenCalled();
  });

  it("unauthenticated: HttpsError + ping_unauthenticated warn", async () => {
    const wrapped = testEnv.wrap(myFunctions.ping);
    await expect(
      wrapped({data: {}} as unknown as CallableRequest),
    ).rejects.toBeInstanceOf(HttpsError);

    // BL-02: 미인증 분기는 warn 만 호출되고 info 는 호출되지 않아야 함.
    expect(warnMock).toHaveBeenCalledTimes(1);
    const [payload] = warnMock.mock.calls[0] as [
      Record<string, unknown>,
      string,
    ];
    expect(payload).toMatchObject({event: "ping_unauthenticated"});
    expect(infoMock).not.toHaveBeenCalled();
  });
});
