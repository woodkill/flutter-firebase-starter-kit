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

import {readFileSync} from "fs";
import {resolve} from "path";

import type {TermsAcceptanceJson} from "../../src/shared/terms_acceptance_json";
import {
  SERVER_TERMS_CURRENT_VERSION,
  parseTermsAcceptanceJson,
} from "../../src/shared/terms_acceptance_json";

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

/**
 * client 짝 상수의 소스 경로 (IN-08, 4차 리뷰).
 *
 * `functions/test/shared/` → repo root 는 3단계 위다. 경로가 바뀌면 아래
 * readFileSync 가 즉시 throw 하므로 stale 참조가 조용히 남지 않는다.
 */
const CLIENT_TERMS_NOTIFIER_PATH = resolve(
  __dirname,
  "../../../lib/features/terms/presentation/terms_notifier.dart",
);

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

/**
 * WR-02 — 런타임 타입가드 `parseTermsAcceptanceJson`.
 *
 * `TermsAcceptanceJson` 은 컴파일타임 타입일 뿐이고 callable arg 는 임의
 * JSON 이므로, mirror 직전 검증이 없으면 (a) 임의 값이 Firestore
 * `users/{uid}.termsAccepted` 에 착지하고 (b) `version` 위조로 client 의
 * 재동의 강제 로직이 무력화되며 (c) 파싱 불가 `acceptedAt` 하나로
 * `HttpsError('internal')` → 로그인 전체가 실패한다.
 */
describe("parseTermsAcceptanceJson (WR-02)", () => {
  const valid = {
    version: 1,
    service: true,
    privacy: true,
    marketing: false,
    acceptedAt: "2026-09-07T09:00:00.000Z",
  };

  it("정상 5 필드 → 그대로 좁혀진 값을 반환한다", () => {
    expect(parseTermsAcceptanceJson(valid)).toEqual(valid);
  });

  it("여분 키는 제거된다 (Firestore 착지 표면 0)", () => {
    const parsed = parseTermsAcceptanceJson({...valid, evil: "payload"});
    expect(parsed).not.toBeNull();
    expect(Object.keys(parsed as object).sort()).toEqual([
      "acceptedAt",
      "marketing",
      "privacy",
      "service",
      "version",
    ]);
  });

  it.each([
    ["object 아님 (string)", "not-an-object"],
    ["object 아님 (number)", 7],
    ["null", null],
    ["undefined", undefined],
    ["version 문자열", {...valid, version: "1"}],
    ["version 비정수", {...valid, version: 1.5}],
    ["service 문자열", {...valid, service: "yes"}],
    ["privacy 문자열", {...valid, privacy: "yes"}],
    ["marketing 숫자", {...valid, marketing: 1}],
    ["acceptedAt 숫자", {...valid, acceptedAt: 1757236800000}],
    ["acceptedAt 파싱 불가", {...valid, acceptedAt: "not-a-date"}],
    ["필드 누락", {version: 1, service: true}],
    // WR-02 (2차 리뷰) — docstring 이 약속한 방어가 코드에 없던 구멍.
    ["version 미래 위조 (999)", {...valid, version: 999}],
    [
      "version 상한 +1",
      {...valid, version: SERVER_TERMS_CURRENT_VERSION + 1},
    ],
    ["version 0", {...valid, version: 0}],
    ["version 음수", {...valid, version: -1}],
    ["service=false (필수 동의 미충족)", {...valid, service: false}],
    ["privacy=false (필수 동의 미충족)", {...valid, privacy: false}],
  ])("%s → null (필드 무시, 로그인은 계속)", (_label, input) => {
    expect(parseTermsAcceptanceJson(input)).toBeNull();
  });

  it("marketing=false 는 선택 동의라 통과한다 (과잉 차단 방지)", () => {
    expect(parseTermsAcceptanceJson({...valid, marketing: false})).toEqual({
      ...valid,
      marketing: false,
    });
  });

  it("version 상한 = client TermsNotifier.currentVersion mirror", () => {
    // IN-08 (4차 리뷰): 이전 sentinel 은 `toBe(1)` 로 **서버 상수를 서버
    // 테스트가 다시 단언**할 뿐이라 self-referential 이었다. 서버 단독 bump 는
    // 잡지만 **client 단독 bump 는 잡지 못했고**, 그 방향이 실제 위험 방향이다
    // — 약관 개정 시 앱이 먼저 배포되면 모든 신규 가입의
    // termsAcceptanceSnapshot 이 상한에 걸려 null 로 폐기되고
    // (fail-open, 로그 0 이라 관측도 안 된다) users/{uid}.termsAccepted 미러가
    // 통째로 유실된다.
    //
    // 따라서 client 소스에서 실제 값을 읽어 비교한다. 본 저장소에서
    // cross-language 상수 mirror 를 강제하는 유일한 실효 수단이다.
    const clientSource = readFileSync(CLIENT_TERMS_NOTIFIER_PATH, "utf8");
    const match = /static const int currentVersion = (\d+);/.exec(clientSource);
    expect(match).not.toBeNull();
    const clientVersion = Number(match?.[1]);

    expect(SERVER_TERMS_CURRENT_VERSION).toBe(clientVersion);
    expect(parseTermsAcceptanceJson({
      ...valid,
      version: SERVER_TERMS_CURRENT_VERSION,
    })).not.toBeNull();
  });
});
