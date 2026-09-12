// Phase 15 code review WR-03 / IN-03 — callable 문자열 인자 공용 타입 가드.
//
// 이전에는 5 사이트 (kakao / line / yahoojp / naver / linkCustomTokenProvider)
// 가 각각 `request.data ?? ({} as XRequest)` 로 타입을 **단언** 한 뒤
// `!idToken || !nonce` 의 falsy 검사만 수행했다. `{idToken: 12345, nonce: {}}`
// 같은 페이로드가 그 가드를 통과해 jose 검증 단계까지 내려갔고,
//
// - 오류가 "입력 타입 오류" 가 아니라 "자격증명 무효" 로 로깅되어 triage 를
//   오도했으며,
// - `nonce` 가 객체일 때 `claimNonce !== expectedNonce` 가 참조 비교라 **항상
//   참** 이 되어 정상 토큰까지 nonce 불일치로 거부될 수 있었다.
//
// 본 helper 로 5 사이트를 동시에 좁히면 `as` 단언 자체가 불필요해진다
// (.claude/rules/cloud-functions-typescript.md "as 타입 단언 최소화 — 타입
// 가드 우선").
import {HttpsError} from "firebase-functions/https";

/** ID Token / access token 계열 인자의 기본 상한 (bytes 가 아닌 UTF-16 길이). */
export const MAX_TOKEN_ARG_LENGTH = 8192;

/** nonce 계열 짧은 인자의 상한. */
export const MAX_NONCE_ARG_LENGTH = 512;

/**
 * 신뢰할 수 없는 callable 인자를 비어 있지 않은 `string` 으로 좁힌다 (WR-03).
 *
 * 상한을 두는 이유는 두 가지다. (1) 거대 페이로드가 jose / fetch 단계까지
 * 내려가 CPU·네트워크를 낭비하지 않게 한다. (2) 상한 초과를 "자격증명 무효"
 * 가 아니라 "입력 오류" 로 분류해 ops triage 를 정확하게 만든다.
 *
 * @param {unknown} value callable arg 의 원본 값 (`request.data?.x`).
 * @param {number} [maxLength] 허용 최대 길이. 기본 [MAX_TOKEN_ARG_LENGTH].
 * @return {string} 검증을 통과한 문자열.
 * @throws {HttpsError} `invalid-argument` / `errorInvalidArgument` — 값이
 *     문자열이 아니거나, 빈 문자열이거나, [maxLength] 를 초과하는 경우.
 */
export function requireStringArg(
  value: unknown,
  maxLength: number = MAX_TOKEN_ARG_LENGTH,
): string {
  if (
    typeof value !== "string" ||
    value.length === 0 ||
    value.length > maxLength
  ) {
    throw new HttpsError("invalid-argument", "errorInvalidArgument");
  }
  return value;
}
