/**
 * Phase 17 — see ROADMAP.md (D-24 · D-43) — 클라이언트 App Check 판별자의
 * 서버 불변식.
 *
 * 클라이언트 `lib/core/functions/callable_rejection.dart` 는 callable 거부가
 * `unauthenticated` · details 없음 · message `Unauthenticated` 일 때만 App Check
 * 차단(SDK 계층 검증 거부)으로 판정한다. 이 판별자가 맞으려면 두 사실이 계속
 * 참이어야 한다.
 *
 * 1. 서버 코드는 `Unauthenticated` 를 message 로 쓰지 않는다 — 서버 자체
 *    `unauthenticated` 는 모두 taxonomy 키(`errorUnauthenticated` ·
 *    `errorInvalidCredentials` · `errorReauthenticationRequired`)를 쓴다.
 * 2. firebase-functions SDK 는 ID token 무효 · App Check 무효 · App Check 부재
 *    세 경로에 `new HttpsError("unauthenticated", "Unauthenticated")` 를
 *    던진다(7.2.5 `lib/common/providers/https.js`). SDK 를 올려 이 상수가
 *    바뀌면 클라이언트 판별자도 바꿔야 하므로 설치본을 pin 한다.
 *
 * 소스 검사 방식 · 주석 제거는 `app_check_sentinel.test.ts` 와 같다 — 주석에
 * 적힌 문자열이 결과를 흔들지 않게 한다.
 */

import {existsSync, readFileSync, readdirSync, statSync} from "node:fs";
import {dirname, join} from "node:path";

const SRC_DIR = join(__dirname, "..", "src");

/** 서버가 SDK 상수 message 로 던지는 형태 (따옴표 종류 무관). */
const SDK_MESSAGE_THROW =
  /HttpsError\(\s*["']unauthenticated["'],\s*["']Unauthenticated["']/g;

/** 양성 대조 — 서버 taxonomy message 로 던지는 형태. */
const TAXONOMY_MESSAGE_THROW =
  /HttpsError\(\s*["']unauthenticated["'],\s*["']errorUnauthenticated["']/g;

/** SDK 설치본에 있어야 하는 throw 원문. */
const SDK_THROW_LITERAL =
  "new HttpsError(\"unauthenticated\", \"Unauthenticated\")";

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
 * 블록 / 라인 주석을 제거한다 (주석 hit 로 인한 오판 차단).
 *
 * @param {string} source TypeScript 원본.
 * @return {string} 주석이 제거된 소스.
 */
function stripComments(source: string): string {
  return source
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/^[ \t]*\/\/.*$/gm, "");
}

/**
 * 설치된 firebase-functions 패키지 루트를 찾는다.
 *
 * 패키지 `exports` 가 `lib/common/providers/https.js` · `package.json` 서브패스를
 * 막으므로 main entry 를 resolve 한 뒤 `name` 이 일치하는 `package.json` 까지
 * 거슬러 올라간다.
 *
 * @return {string} 패키지 루트 절대 경로.
 */
function resolveFirebaseFunctionsRoot(): string {
  let dir = dirname(require.resolve("firebase-functions"));
  for (;;) {
    const manifest = join(dir, "package.json");
    if (existsSync(manifest)) {
      const pkg: unknown = JSON.parse(readFileSync(manifest, "utf8"));
      if (
        typeof pkg === "object" &&
        pkg !== null &&
        "name" in pkg &&
        pkg.name === "firebase-functions"
      ) {
        return dir;
      }
    }
    const parent = dirname(dir);
    if (parent === dir) {
      throw new Error("firebase-functions 패키지 루트를 찾지 못했다");
    }
    dir = parent;
  }
}

/**
 * `src/` 전 파일(주석 제거)에서 [pattern] 이 나온 횟수를 센다.
 *
 * @param {RegExp} pattern global 플래그가 있는 정규식.
 * @return {number} 전체 매칭 수.
 */
function countInSources(pattern: RegExp): number {
  let count = 0;
  for (const file of collectTsFiles(SRC_DIR)) {
    const code = stripComments(readFileSync(file, "utf8"));
    count += (code.match(pattern) ?? []).length;
  }
  return count;
}

describe("unauthenticated message sentinel — Phase 17 D-24 · D-43", () => {
  it(
    "T-17-APPCHECK-06: 서버는 SDK 상수 message 'Unauthenticated' 를 " +
      "쓰지 않는다",
    () => {
      // 양성 대조 — 같은 스캔이 taxonomy throw 를 찾지 못하면 스캔 자체가
      // 고장난 것이므로 0건 단언이 공허해진다.
      expect(countInSources(TAXONOMY_MESSAGE_THROW)).toBeGreaterThanOrEqual(1);
      expect(countInSources(SDK_MESSAGE_THROW)).toBe(0);
    },
  );

  it(
    "T-17-APPCHECK-07: firebase-functions SDK 가 App Check/auth 거부에 " +
      "'Unauthenticated' 를 던진다",
    () => {
      const httpsJs = readFileSync(
        join(
          resolveFirebaseFunctionsRoot(),
          "lib",
          "common",
          "providers",
          "https.js",
        ),
        "utf8",
      );
      const occurrences = httpsJs.split(SDK_THROW_LITERAL).length - 1;
      expect(occurrences).toBe(3);
    },
  );
});
