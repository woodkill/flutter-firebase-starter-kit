/**
 * rate_limits 문서 ID 소스 sentinel (Phase 32 · D-14).
 *
 * 회원탈퇴 Step 5 는 `UID_RATE_LIMIT_DOC_PREFIXES` 목록의 접두사에 uid 를
 * 붙여 uid 축 counter 를 지운다. callable 이 목록 밖에서 접두사를 따로 적으면
 * (값이 조금만 어긋나도) 탈퇴가 그 counter 를 조용히 못 지운다. 또 counter
 * 컬렉션을 helper 밖에서 직접 쓰면 새 창의 만료 시각 규칙을 건너뛴다. 이
 * 시험은 그 두 어긋남을 막는다.
 *
 * **왜 런타임이 아니라 소스 검사인가:** 어긋남은 「어떤 문자열로 문서 ID 를
 * 만들었나」 이고, 시험 mock 은 문서 ID 를 시험 자신이 정한 값으로 받아 주기
 * 때문에 런타임 시험으로는 목록 밖 접두사를 가려낼 수 없다. 그래서 `src/`
 * 전체 소스(owner `src/shared/rate_limit.ts` 제외)를 훑는다. Firestore 는
 * 읽지 않는다.
 *
 * 주석은 제거한 뒤 매칭한다 — 주석에 적힌 접두사 · 컬렉션 이름 설명이
 * 위반으로 잡히지 않게 하기 위해서다.
 *  - ① 컬렉션 리터럴(따옴표 · 백틱으로 감싼 `rate_limits`)은 owner 에만.
 *  - ② `UID_RATE_LIMIT_DOC_PREFIXES` 값(시험이 src 에서 import — 목록과
 *    시험이 저절로 같다)은 owner 밖 0.
 *  - ③ 인라인 uid counter 문서 ID template(`접두:` 또는 `${…PREFIX}` 뒤에
 *    `uid` · `Uid` 로 끝나는 보간)은 owner 밖 0 — 목록에 없는 새 축도 잡는다.
 *
 * **한계:** 줄 끝 `//` 주석은 지우지 않으므로 그 안의 설명이 오탐을 낼 수
 * 있다. 또 줄 끝 `//` 주석이나 문자열 리터럴 속 `/*` 는 블록 주석 시작으로
 * 잡혀 다음 블록 주석 끝까지 코드를 지울 수 있어 미탐이 날 수 있다. 그래서
 * 줄 전체 `//` 주석을 블록 주석보다 먼저 지운다 — 그 안의 `/*` 는 이 문제를
 * 내지 않는다.
 * `"prefix:" + uid` 같은 문자열 연결과 `uid` · `Uid` 로 끝나지 않는 변수
 * 이름(`callerId` 등)은 ③ 이 못 잡는다 — 알려진 4종은 ② 가 따로 잡는다.
 * uid 를 문서 ID 에 넣는 새 코드는 공유 함수(`buildUidRateLimitDocId`)로
 * 만든다.
 */

import {readFileSync, readdirSync, statSync} from "node:fs";
import {join, relative} from "node:path";

import {UID_RATE_LIMIT_DOC_PREFIXES} from "../src/shared/rate_limit";

const SRC_DIR = join(__dirname, "..", "src");
const OWNER = join(SRC_DIR, "shared", "rate_limit.ts");

/** ① counter 컬렉션 리터럴. */
const COLLECTION_LITERAL = /["'`]rate_limits["'`]/;

/** ③ 인라인 uid counter 문서 ID template. */
const INLINE_UID_DOC_ID =
  /`(?:[A-Za-z]+:|\$\{[A-Z_]*PREFIX\})\$\{[^}`]*[uU]id\}/;

/**
 * `src/` 아래 모든 `.ts` 파일 경로를 재귀 수집한다.
 *
 * @param {string} dir 탐색 시작 디렉터리.
 * @return {Array<string>} `.ts` 파일 절대 경로 목록.
 */
function collectTsFiles(dir: string): string[] {
  const out: string[] = [];
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) {
      out.push(...collectTsFiles(full));
    } else if (full.endsWith(".ts")) {
      out.push(full);
    }
  }
  return out;
}

/**
 * 블록 / 라인 주석을 제거한다 (주석 hit 로 인한 false-positive 차단).
 *
 * @param {string} source TypeScript 원본.
 * @return {string} 주석이 제거된 소스.
 */
function stripComments(source: string): string {
  // 줄 전체 `//` 주석을 먼저 지운다 — 그 안의 `/*` 가 블록 주석 시작으로
  // 잡혀 다음 `*/` 까지 실제 코드를 삼키지 않게 하기 위해서다.
  return source
    .replace(/^[ \t]*\/\/.*$/gm, "")
    .replace(/\/\*[\s\S]*?\*\//g, "");
}

/**
 * owner 밖 파일 가운데 조건에 맞는 파일을 `src/…` 상대 경로로 모은다.
 *
 * @param {Array<string>} files 검사 대상 파일(절대 경로).
 * @param {function(string): boolean} hit 주석을 지운 소스를 받는 판정.
 * @return {Array<string>} 위반 파일의 `src/…` 경로 목록.
 */
function offenders(
  files: string[],
  hit: (code: string) => boolean,
): string[] {
  return files
    .filter((f) => hit(stripComments(readFileSync(f, "utf8"))))
    .map((f) => join("src", relative(SRC_DIR, f)));
}

describe("rate_limits 문서 ID sentinel — Phase 32", () => {
  const others = collectTsFiles(SRC_DIR).filter((f) => f !== OWNER);
  const prefixes: string[] = Object.values(UID_RATE_LIMIT_DOC_PREFIXES);

  it("T-32-SENT-00: owner 리터럴 · 접두사 4개 · 검사 대상이 있다", () => {
    const ownerCode = stripComments(readFileSync(OWNER, "utf8"));
    expect(COLLECTION_LITERAL.test(ownerCode)).toBe(true);
    expect(Object.keys(UID_RATE_LIMIT_DOC_PREFIXES)).toHaveLength(4);
    expect(others.length).toBeGreaterThan(0);
  });

  it("T-32-SENT-01: 컬렉션 리터럴은 owner 밖에 없다", () => {
    expect(offenders(others, (code) => COLLECTION_LITERAL.test(code)))
      .toEqual([]);
  });

  it("T-32-SENT-02: uid 축 접두사 값은 owner 밖에 없다", () => {
    expect(
      offenders(others, (code) => prefixes.some((p) => code.includes(p))),
    ).toEqual([]);
  });

  it("T-32-SENT-03: 인라인 uid counter 문서 ID template 이 없다", () => {
    expect(offenders(others, (code) => INLINE_UID_DOC_ID.test(code)))
      .toEqual([]);
  });
});
