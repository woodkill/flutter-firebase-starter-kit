/**
 * App Check enforcement sentinel (Phase 15 리뷰 IN-05).
 *
 * 배포되는 callable 중 `ping` 하나만 `enforceAppCheck: true` 없이 export 되고
 * 있었다. `ping` 자체의 위험은 낮지만 (인증만 요구하고 region / 서버시각만
 * 반환), `index.ts` 주석이 스스로를 "Phase 12~16 Custom Token 함수가 복제할
 * 패턴" 이라고 선언하는 레퍼런스여서 빠진 옵션이 그대로 잘못된 템플릿이 된다.
 *
 * **왜 런타임 metadata 가 아니라 소스 검사인가:** `enforceAppCheck` 는
 * `onCall` 이 반환한 함수의 `__endpoint` / `__trigger` 어디에도 노출되지 않고
 * (firebase-functions 7.x 확인), 실제 강제는 `testEnv.wrap()` 이 우회하는
 * HTTP 핸들러 안에서 일어난다. 따라서 **선언 자체** 를 잠그는 것이 이 불변식을
 * 검증할 수 있는 유일한 지점이다.
 *
 * 주석은 제거한 뒤 매칭한다 — 주석에 적힌 `enforceAppCheck` 문자열이
 * false-positive 로 통과시키는 함정을 피하기 위해서다.
 */

import {readFileSync, readdirSync, statSync} from "node:fs";
import {join} from "node:path";

const SRC_DIR = join(__dirname, "..", "src");

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
  return source
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/^[ \t]*\/\/.*$/gm, "");
}

describe("App Check enforcement sentinel — IN-05", () => {
  const files = collectTsFiles(SRC_DIR);

  it("src/ 아래에 onCall 선언이 실제로 존재한다 (sentinel 자체 sanity)", () => {
    const withOnCall = files.filter((f) =>
      stripComments(readFileSync(f, "utf8")).includes("onCall"),
    );
    // 9 callable 이 5개 파일 이상에 흩어져 있다 — 0이면 본 sentinel 이 아무것도
    // 검사하지 않는 상태이므로 즉시 RED.
    expect(withOnCall.length).toBeGreaterThan(0);
  });

  it("onCall 을 선언한 모든 파일이 enforceAppCheck: true 를 지정한다", () => {
    const offenders: string[] = [];
    for (const file of files) {
      const code = stripComments(readFileSync(file, "utf8"));
      if (!code.includes("onCall")) continue;
      if (!code.includes("enforceAppCheck: true")) {
        offenders.push(file.replace(`${SRC_DIR}/`, "src/"));
      }
    }
    expect(offenders).toEqual([]);
  });
});
