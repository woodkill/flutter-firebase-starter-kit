import functionsTest from "firebase-functions-test";
import {HttpsError} from "firebase-functions/https";

const testEnv = functionsTest();

// ping import 는 testEnv 초기화 이후 (firebase-functions-test 권장 패턴).
// eslint-disable-next-line import/first
import * as myFunctions from "../src/index";

afterAll(() => testEnv.cleanup());

describe("ping onCall", () => {
  it("returns ok=true when authenticated", async () => {
    const wrapped = testEnv.wrap(myFunctions.ping);
    const result = await wrapped({
      auth: {uid: "test-user-123"},
      data: {},
    } as any);
    expect((result as any).ok).toBe(true);
    expect((result as any).region).toBe("asia-northeast3");
    expect(typeof (result as any).serverTime).toBe("string");
  });

  it("throws unauthenticated when no auth context", async () => {
    const wrapped = testEnv.wrap(myFunctions.ping);
    await expect(
      wrapped({data: {}} as any),
    ).rejects.toBeInstanceOf(HttpsError);
  });
});
