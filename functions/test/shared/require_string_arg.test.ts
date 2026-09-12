/**
 * `requireStringArg` 회귀 테스트 (Phase 15 리뷰 WR-03 / IN-03).
 *
 * 5 사이트 (kakao / naver / line / yahoojp / linkCustomTokenProvider) 가
 * 공유하는 문자열 인자 가드다. 이전에는 각 endpoint 가
 * `request.data ?? ({} as XRequest)` 로 타입을 **단언** 한 뒤 falsy 검사만
 * 했기 때문에 `{idToken: 12345, nonce: {}}` 같은 페이로드가 통과했다.
 *
 * 특히 `nonce` 가 객체이면 verifier 의 `claimNonce !== expectedNonce` 가 참조
 * 비교라 **항상 참** 이 되어 정상 토큰까지 nonce 불일치로 거부된다 — 본
 * 가드가 그 경로에 도달하기 전에 입력 오류로 잘라낸다.
 */

// eslint-disable-next-line import/first
import {HttpsError} from "firebase-functions/https";

// eslint-disable-next-line import/first
import {
  MAX_NONCE_ARG_LENGTH,
  MAX_TOKEN_ARG_LENGTH,
  requireStringArg,
} from "../../src/shared/require_string_arg";

describe("requireStringArg — WR-03 공용 타입 가드", () => {
  it("정상 문자열은 그대로 통과시킨다", () => {
    expect(requireStringArg("FAKE_JWT")).toBe("FAKE_JWT");
  });

  // falsy-only 가드가 놓치던 비-string 타입들. 각각이 이전 구현에서
  // jose 단계까지 내려가 "자격증명 무효" 로 오분류되던 입력이다.
  const nonStringCases: Array<[string, unknown]> = [
    ["number", 12345],
    ["object", {}],
    ["array", ["FAKE_JWT"]],
    ["boolean", true],
    ["null", null],
    ["undefined", undefined],
  ];
  it.each(nonStringCases)(
    "비-string (%s) 은 invalid-argument 로 거부한다",
    (_label, value) => {
      expect(() => requireStringArg(value)).toThrow(HttpsError);
      try {
        requireStringArg(value);
      } catch (err: unknown) {
        expect(err).toMatchObject({
          code: "invalid-argument",
          message: "errorInvalidArgument",
        });
      }
    },
  );

  it("빈 문자열은 invalid-argument 로 거부한다", () => {
    expect(() => requireStringArg("")).toThrow(HttpsError);
  });

  it("상한 이하 길이는 통과, 초과는 거부한다", () => {
    const atLimit = "a".repeat(MAX_TOKEN_ARG_LENGTH);
    expect(requireStringArg(atLimit)).toHaveLength(MAX_TOKEN_ARG_LENGTH);
    expect(() => requireStringArg(`${atLimit}a`)).toThrow(HttpsError);
  });

  it("nonce 상한은 별도 인자로 좁힐 수 있다", () => {
    const overNonceLimit = "n".repeat(MAX_NONCE_ARG_LENGTH + 1);
    // 기본 상한(8192) 으로는 통과하지만 nonce 상한(512) 으로는 거부된다.
    expect(requireStringArg(overNonceLimit)).toBe(overNonceLimit);
    expect(() =>
      requireStringArg(overNonceLimit, MAX_NONCE_ARG_LENGTH),
    ).toThrow(HttpsError);
  });
});
