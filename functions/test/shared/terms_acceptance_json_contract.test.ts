/**
 * TermsAcceptanceJson 5-key 계약 sentinel (Phase 16 Plan 16-14 — G-16-A9-1).
 *
 * 서버 수신 타입 `functions/src/shared/terms_acceptance_json.ts` 의 키 집합을
 * 컴파일타임 + 런타임 양쪽에서 고정한다. 4 Custom Token endpoint
 * (kakao/naver/line/yahoojp) 가 `termsAcceptanceSnapshot` 으로 수신하는 값의
 * 형태가 곧 이 타입이다.
 *
 * **client 짝 (한쪽만 바꾸면 안 된다):**
 * `test/features/auth/data/auth_repository_terms_snapshot_test.dart` 의
 * `_serverContractKeys` 상수. 본 파일의 `CONTRACT_KEYS` 와 항상 동일해야 하며,
 * 어느 한쪽 키 집합을 바꾸면 반대쪽도 반드시 함께 갱신한다.
 *
 * **본 파일은 test 전용이다** — `functions/src/` 변경 0, Cloud Function
 * 재배포를 유발하지 않는다.
 */

import type {TermsAcceptanceJson} from "../../src/shared/terms_acceptance_json";

/** 서버 계약 키 배열 — client `_serverContractKeys` 와 동일 집합. */
const CONTRACT_KEYS = [
  "version",
  "service",
  "privacy",
  "marketing",
  "acceptedAt",
] as const;

/** [CONTRACT_KEYS] 원소 타입. */
type ContractKey = (typeof CONTRACT_KEYS)[number];

/**
 * `T` 가 `never` 일 때만 `true` 로 평가되는 조건부 타입.
 *
 * 아래 두 할당이 컴파일되면 타입 키 집합과 [CONTRACT_KEYS] 가 양방향으로
 * 일치한다는 뜻이다 (6번째 필드가 생기거나 필드가 사라지면 컴파일 실패).
 */
type IsNever<T> = [T] extends [never] ? true : false;

/** 타입에는 있으나 계약 배열에 없는 키 — 반드시 never. */
const noExtraTypeKey: IsNever<
  Exclude<keyof TermsAcceptanceJson, ContractKey>
> = true;

/** 계약 배열에는 있으나 타입에 없는 키 — 반드시 never. */
const noExtraContractKey: IsNever<
  Exclude<ContractKey, keyof TermsAcceptanceJson>
> = true;

describe("TermsAcceptanceJson 5-key 계약", () => {
  it("컴파일타임 양방향 exhaustiveness — 타입 키 집합 == CONTRACT_KEYS", () => {
    // 두 상수가 `true` 로 컴파일된 것 자체가 exhaustiveness 증거다.
    expect(noExtraTypeKey).toBe(true);
    expect(noExtraContractKey).toBe(true);
  });

  it("런타임 계약 키 집합이 정확히 5 키다", () => {
    expect([...CONTRACT_KEYS].sort()).toEqual([
      "acceptedAt",
      "marketing",
      "privacy",
      "service",
      "version",
    ]);
  });
});
