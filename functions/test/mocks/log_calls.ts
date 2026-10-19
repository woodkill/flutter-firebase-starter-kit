/**
 * logger mock 호출을 PII sentinel 검사용 문자열로 만드는 helper.
 *
 * firebase-functions logger(`entryFromArgs`)는 **마지막** 인자가 plain
 * object 일 때만 그것을 구조화 entry 로 떼어 내고, 나머지 인자는
 * `util.format`(= `util.inspect`) 으로 이어 `message` 를 만든다. 이 저장소의
 * 운영 logger 호출은 전부 「객체 먼저 · 문자열 마지막」
 * (`logger.error({event, …}, "msg")`) 꼴이라, payload 객체가 inspect
 * 문자열로 `message` 에 실린다(운영은 inspect 기본 옵션 — depth 2 ·
 * 문자열 10000자 · 배열 100개에서 자른다). 그 안의 Error 는 message ·
 * stack 째 실린다.
 *
 * 그래서 sentinel 도 inspect 로 직렬화해 본다 — 운영 logger message 를
 * 포함하는(상한 없는) 직렬화라 운영이 싣는 것을 빠짐없이 보고, 운영이
 * 자르는 부분까지 더 본다. `JSON.stringify` 는 Error 의 message ·
 * stack(열거 불가 속성)을 버려 이 누출을 보지 못한다.
 *
 * 파일명에 `.test.ts` 접미어를 붙이지 않는다 — `jest.config.js` 의
 * `testMatch` 에 잡히지 않게 하는 `test/mocks/` 관례.
 */
import {inspect} from "util";

/**
 * logger mock 호출 배열을 PII sentinel 검사용 문자열로 직렬화한다.
 *
 * 깊이 · 배열 길이 · 문자열 길이 상한을 모두 풀어(`null` = 무제한) 누적
 * 호출이 많거나 payload 가 깊어도 잘린 부분에 원문이 숨지 않게 한다
 * (inspect 기본 옵션은 depth 2 · 배열 100개 · 문자열 10000자에서 자른다).
 * 운영이 `[Object]` · `... more items` · `... more characters` 로 자르는
 * 부분까지 보므로 운영 message 의 상위 집합이고, sentinel 은 운영보다
 * 엄격하다 — 「운영과 같게」 맞춘다며 상한을 되돌리지 않는다.
 *
 * @param {Array<Array<unknown>>} calls `mock.calls` 를 이은 배열 (호출마다 인자 배열).
 * @return {string} 운영 logger message 를 포함하는(상한 없는) inspect
 *   직렬화 결과.
 */
export function serializeLogCalls(calls: unknown[][]): string {
  return inspect(calls, {
    depth: null,
    maxArrayLength: null,
    maxStringLength: null,
  });
}
