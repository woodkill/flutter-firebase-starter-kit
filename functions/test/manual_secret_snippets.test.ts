/**
 * `docs/setup.md` 「secret 값 확인하기」 의 secret 점검 셸 스니펫 동작 검증.
 *
 * 스니펫을 setup.md 에서 글자 그대로 추출해(정확히 1개여야 한다) 실행한다 — secret
 * 값을 어떤 경우에도 출력하지 않는다. secret 은 위저드(`./setup.sh --providers`)가
 * 만들므로 문서에 secret 을 만드는 셸 명령은 없다.
 * `firebase` 는 PATH 의 가짜 실행 파일로 대체해 인자와 stdin 을 기록한다. 실제 CLI ·
 * 네트워크는 쓰지 않는다. bash 와 (있으면) `zsh -f` 양쪽에서 돌린다.
 */

import {spawnSync} from "node:child_process";
import {
  chmodSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import {tmpdir} from "node:os";
import {join} from "node:path";

/** 셸 실행 결과. */
type RunResult = {status: number | null; stdout: string; stderr: string};

const SETUP_PATH = join(__dirname, "..", "..", "docs", "setup.md");
const PROJECT = "my-proj";
const SECRET = "KAKAO_ADMIN_KEY";

/** 가짜 `secrets:access` 응답 종류 → [종료 코드, 출력 스트림, 메시지]. */
const GET_RESPONSES: Record<string, [number, "out" | "err", string]> = {
  403: [
    1,
    "out",
    "Error: Request to https://secretmanager.googleapis.com/v1/x had HTTP " +
      "Error: 403, Permission 'secretmanager.versions.list' denied.",
  ],
};

/**
 * setup.md 의 「secret 값 확인하기」 소절 본문(다음 `##` · `###` 머리 앞까지).
 *
 * @return {string} 소절 본문(머리가 없으면 빈 문자열).
 */
function readSection(): string {
  const doc = readFileSync(SETUP_PATH, "utf8");
  const start = doc.indexOf("\n### secret 값 확인하기\n");
  if (start === -1) {
    return "";
  }
  const body = doc.slice(start + 1);
  const next = body.slice(1).search(/\n#{2,3} /);
  return next === -1 ? body : body.slice(0, next + 1);
}

/**
 * 절 본문에서 첫 줄 ~ 끝 줄 사이 스니펫을 정확히 1개 추출한다.
 *
 * @param {string} first 시작 줄(앞 공백 포함 전체 일치).
 * @param {string} last 끝 줄(앞 공백 포함 전체 일치).
 * @param {number} indent 공통으로 벗길 들여쓰기 칸 수.
 * @return {string} 들여쓰기를 벗기고 치환 전 상태인 스니펫 텍스트.
 */
function extractSnippet(first: string, last: string, indent: number): string {
  const lines = readSection().split("\n");
  const starts = lines.flatMap((l, i) => (l === first ? [i] : []));
  expect(starts).toHaveLength(1);
  const begin = starts[0] ?? -1;
  const end = lines.findIndex((l, i) => i > begin && l === last);
  expect(end).toBeGreaterThan(begin);
  const pad = " ".repeat(indent);
  return lines
    .slice(begin, end + 1)
    .map((l) => {
      expect(l.startsWith(pad)).toBe(true);
      return l.slice(indent);
    })
    .join("\n");
}

/**
 * 「secret 값 확인하기」 점검 스니펫(치환 후).
 *
 * @return {string} 스니펫 텍스트.
 */
function checkSnippet(): string {
  return extractSnippet(
    "  if v=\"$(firebase functions:secrets:access <secret 이름> " +
      "--project <your-project-id> 2>&1)\"; then",
    "  unset v",
    2,
  )
    .replace(/<your-project-id>/g, PROJECT)
    .replace(/<secret 이름>/g, SECRET);
}

const HAS_ZSH = spawnSync("sh", ["-c", "command -v zsh"]).status === 0;
/** [이름, 실행 명령, 사용 가능 여부]. zsh 가 없으면 행을 skip 으로 보고한다. */
const SHELLS: Array<[string, string[], boolean]> = [
  ["bash", ["bash"], true],
  ["zsh", ["zsh", "-f"], HAS_ZSH],
];

let sandbox = "";
let logFile = "";

beforeEach(() => {
  sandbox = mkdtempSync(join(tmpdir(), "secret-snip-"));
  logFile = join(sandbox, "calls.log");
  writeFileSync(logFile, "");
  const bin = join(sandbox, "bin");
  mkdirSync(bin);
  writeFileSync(
    join(bin, "firebase"),
    [
      "#!/bin/bash",
      "sub=\"$1\"",
      "if [ \"$sub\" = functions:secrets:set ]; then",
      "  stdin=\"$(cat)\"",
      "  echo \"set|$*|stdin=[$stdin]\" >> \"$FAKE_LOG\"",
      "  exit \"${FAKE_SET_EXIT:-0}\"",
      "fi",
      "n=$(grep -c '^get|' \"$FAKE_LOG\")",
      "echo \"${sub#functions:secrets:}|$*\" >> \"$FAKE_LOG\"",
      "IFS=\\; read -ra specs <<< \"$FAKE_SPEC\"",
      "i=$n; [ \"$i\" -ge \"${#specs[@]}\" ] && i=$((${#specs[@]} - 1))",
      "IFS='|' read -r code stream msg <<< \"${specs[$i]}\"",
      "if [ \"$stream\" = err ]; then echo \"$msg\" >&2;" +
        " else echo \"$msg\"; fi",
      "exit \"$code\"",
      "",
    ].join("\n"),
  );
  chmodSync(join(bin, "firebase"), 0o755);
});

afterEach(() => {
  rmSync(sandbox, {recursive: true, force: true});
});

/**
 * 가짜 firebase 로 스니펫을 셸에서 실행한다.
 *
 * @param {string[]} shell 셸 실행 명령(인자 포함).
 * @param {string} script 실행할 스니펫.
 * @param {string} spec 호출 순서별 응답 종류(세미콜론 구분, 마지막 값 반복).
 * @param {Record<string, string>} extraEnv 추가 환경 변수.
 * @return {RunResult} 종료 코드와 출력.
 */
function run(
  shell: string[],
  script: string,
  spec: string,
  extraEnv: Record<string, string> = {},
): RunResult {
  const encoded = spec
    .split(";")
    .map((k) => {
      if (k.startsWith("raw:")) {
        return k.slice(4);
      }
      const r = GET_RESPONSES[k];
      return `${r[0]}|${r[1]}|${r[2]}`;
    })
    .join(";");
  const file = join(sandbox, "snippet.sh");
  writeFileSync(file, script);
  const [cmd, ...args] = shell;
  const r = spawnSync(cmd as string, [...args, file], {
    encoding: "utf8",
    env: {
      PATH: `${join(sandbox, "bin")}:/usr/bin:/bin`,
      FAKE_LOG: logFile,
      FAKE_SPEC: encoded,
      ...extraEnv,
    },
  });
  return {status: r.status, stdout: r.stdout, stderr: r.stderr};
}

for (const [shellName, shell, available] of SHELLS) {
  const suite = available ? describe : describe.skip;
  suite(`setup.md secret check snippet under ${shellName}`, () => {
    it("T-173-SNIPPET-00 점검 스니펫이 -n 문법 검사를 통과한다", () => {
      const [cmd, ...args] = shell;
      const file = join(sandbox, "syn.sh");
      writeFileSync(file, checkSnippet());
      const r = spawnSync(cmd as string, [...args, "-n", file]);
      expect(r.status).toBe(0);
    });

    it("T-173-SNIPPET-21 값이 unset 이면 등록 안내만 출력한다", () => {
      const r = run(shell, checkSnippet(), "raw:0|out|unset");
      expect(r.stdout).toBe("unset — 실제 값을 등록한다\n");
    });

    it("T-173-SNIPPET-22 실제 값은 어디에도 출력하지 않는다", () => {
      const value = "s3cr3t-VALUE-xyz";
      const r = run(shell, checkSnippet(), `raw:0|out|${value}`);
      expect(r.stdout).toBe("unset 이 아니다\n");
      expect((r.stdout + r.stderr).split(value)).toHaveLength(1);
    });

    it("T-173-SNIPPET-23 실패하면 오류 메시지만 출력한다", () => {
      const r = run(shell, checkSnippet(), "403");
      expect(r.stdout).toBe(`${GET_RESPONSES["403"]?.[2]}\n`);
      expect(r.stdout).not.toContain("unset 이 아니다");
      expect(r.stdout).not.toContain("실제 값을 등록한다");
    });

    it("T-173-SNIPPET-24 스니펫 뒤 변수 v 가 비어 있다", () => {
      const r = run(
        shell,
        `${checkSnippet()}\nprintf '[%s]' "\${v-}"\n`,
        "raw:0|out|s3cr3t-VALUE-xyz",
      );
      expect(r.stdout.endsWith("[]")).toBe(true);
      expect(r.stdout).not.toContain("s3cr3t-VALUE-xyz");
    });
  });
}

// 기본 zsh(대화형 · interactive_comments 꺼짐)에 붙여 넣으면 `#` 이하가 명령 인수가
// 되어 스니펫이 깨진다. 셸 레인(bash · `zsh -f` 비대화형)은 주석을 허용해 동적으로는
// 잡히지 않으므로, 셸과 무관한 정적 검사로 점검 스니펫을 한 번만 확인한다.
// `#` 은 단어 첫 글자일 때 주석을 시작하므로 줄 머리 · 공백뿐 아니라 `;` `|` `&` `(` `)`
// 바로 뒤도 잡는다. 단어 중간의 `#`(`${#a[@]}` · `$#`)은 주석이 아니라 제외된다.
describe("setup.md secret check snippet (static)", () => {
  it("T-173-SNIPPET-10 점검 스니펫에 주석이 없다", () => {
    for (const line of checkSnippet().split("\n")) {
      expect(line).not.toMatch(/(^|[\s;|&()])#/);
    }
  });
});
