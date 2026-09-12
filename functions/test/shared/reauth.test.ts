/**
 * 재인증 신선도 검사 회귀 테스트 (Phase 15 리뷰 WR-11).
 *
 * `deleteUserAccount` / `linkCustomTokenProvider` 두 최고 위험 동작의 유일한
 * 신선도 근거다. 이전 인라인 구현 (`nowSec - authTime > 300`) 은
 *
 * - `auth_time` 누락 시 `NaN > 300 === false` 로 **검사를 통과** 했고,
 * - 미래값 (시계 오차 / 위조) 도 차이가 음수라 무조건 통과했다.
 */

// eslint-disable-next-line import/first
import {HttpsError} from "firebase-functions/https";

// eslint-disable-next-line import/first
import {
  REAUTH_CLOCK_SKEW_SEC,
  REAUTH_MAX_AGE_SEC,
  assertFreshAuth,
} from "../../src/shared/reauth";

/**
 * 현재 epoch seconds 에서 [offset] 만큼 이동한 값.
 *
 * @param {number} offset 초 단위 오프셋 (음수 = 과거).
 * @return {number} epoch seconds.
 */
function nowPlus(offset: number): number {
  return Math.floor(Date.now() / 1000) + offset;
}

describe("assertFreshAuth — WR-11", () => {
  it("방금 재인증한 토큰은 통과한다", () => {
    expect(() => assertFreshAuth(nowPlus(-10))).not.toThrow();
  });

  it("상한 직전 (299초) 은 통과한다", () => {
    expect(() =>
      assertFreshAuth(nowPlus(-(REAUTH_MAX_AGE_SEC - 1)),
      ),
    ).not.toThrow();
  });

  it("상한 초과 (10분 전) 는 거부한다", () => {
    expect(() => assertFreshAuth(nowPlus(-600))).toThrow(HttpsError);
  });

  // 아래 두 케이스가 이번 수정의 핵심이다 — 이전 구현에서는 **둘 다
  // 통과** 했다.
  it("auth_time 누락 (undefined) 은 거부한다", () => {
    // nowSec - undefined = NaN, NaN > 300 === false → 이전 구현은 통과.
    expect(() => assertFreshAuth(undefined)).toThrow(HttpsError);
  });

  it("허용 오차를 넘는 미래값은 거부한다", () => {
    // nowSec - future < 0 → 이전 구현은 무조건 통과.
    expect(() =>
      assertFreshAuth(nowPlus(REAUTH_CLOCK_SKEW_SEC + 120)),
    ).toThrow(HttpsError);
  });

  it("허용 오차 내 미래값 (시계 동기화 오차) 은 통과한다", () => {
    expect(() =>
      assertFreshAuth(nowPlus(REAUTH_CLOCK_SKEW_SEC - 10)),
    ).not.toThrow();
  });

  const nonNumberCases: Array<[string, unknown]> = [
    ["string", "1700000000"],
    ["null", null],
    ["object", {}],
    ["NaN", Number.NaN],
    ["Infinity", Number.POSITIVE_INFINITY],
  ];
  it.each(nonNumberCases)("비-유한숫자 (%s) 는 거부한다", (_label, value) => {
    expect(() => assertFreshAuth(value)).toThrow(HttpsError);
  });

  it("거부 시 표준 재인증 에러를 던진다", () => {
    try {
      assertFreshAuth(undefined);
      throw new Error("should have thrown");
    } catch (err: unknown) {
      expect(err).toMatchObject({
        code: "unauthenticated",
        message: "errorReauthenticationRequired",
      });
    }
  });
});
