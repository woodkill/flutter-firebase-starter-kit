/**
 * `docs/manual.md` 「로그인 수단 켜고 끄기」 의 secret 셸 스니펫 동작 검증
 * (Phase 17.3 SOCL-09 성공 4 · T-173-11 · review WR-03 / WR-04).
 *
 * 스니펫 두 개를 매뉴얼에서 글자 그대로 추출해(각각 정확히 1개여야 한다) 실행한다.
 *  - 「켜기」 ④ 반복문: `secrets:get` 이 `HTTP Error: 404` 일 때만 자리표시 secret 을
 *    만들고, 그 밖의 오류는 메시지를 stderr 로 내고 멈춘다.
 *  - 「문제 해결」 확인 스니펫: secret 값을 어떤 경우에도 출력하지 않는다.
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

const MANUAL_PATH = join(__dirname, "..", "..", "docs", "manual.md");
const PROJECT = "my-proj";
const SECRET = "KAKAO_ADMIN_KEY";

/** 가짜 `secrets:get` 응답 종류 → [종료 코드, 출력 스트림, 메시지]. */
const GET_RESPONSES: Record<string, [number, "out" | "err", string]> = {
  ok: [0, "out", "unset"],
  nfErr: [
    1,
    "err",
    "Error: Request to https://secretmanager.googleapis.com/v1/x had HTTP " +
      "Error: 404, Secret [projects/my-proj/secrets/X] not found.",
  ],
  nfOut: [
    1,
    "out",
    "Error: Request to https://secretmanager.googleapis.com/v1/x had HTTP " +
      "Error: 404, Secret [projects/my-proj/secrets/X] not found.",
  ],
  403: [
    1,
    "out",
    "Error: Request to https://secretmanager.googleapis.com/v1/x had HTTP " +
      "Error: 403, Permission 'secretmanager.versions.list' denied.",
  ],
  auth: [
    1,
    "out",
    "Error: Authentication Error: Your credentials are no longer valid. " +
      "Please run firebase login --reauth",
  ],
  net: [2, "out", "Error: Failed to make request to https://x"],
};

/**
 * 매뉴얼의 「로그인 수단 켜고 끄기」 절 본문.
 *
 * @return {string} 절 본문.
 */
function readSection(): string {
  const manual = readFileSync(MANUAL_PATH, "utf8");
  const start = manual.indexOf("\n## 로그인 수단 켜고 끄기\n");
  const next = manual.indexOf("\n## ", start + 1);
  return manual.slice(start, next === -1 ? undefined : next);
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
 * 「켜기」 ④ 반복문(치환 후).
 *
 * @return {string} 반복문 텍스트.
 */
function loopSnippet(): string {
  return extractSnippet(
    "for s in KAKAO_NATIVE_APP_KEY KAKAO_ADMIN_KEY LINE_CHANNEL_ID " +
      "LINE_CHANNEL_SECRET \\",
    "done",
    0,
  ).replace(/<your-project-id>/g, PROJECT);
}

/**
 * 「문제 해결」 secret 확인 스니펫(치환 후).
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
  sandbox = mkdtempSync(join(tmpdir(), "manual-snip-"));
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

/**
 * 기록 파일에서 `get|` / `set|` 호출 줄을 돌려준다.
 *
 * @param {string} kind `get` 또는 `set`.
 * @return {string[]} 해당 호출 기록 줄.
 */
function calls(kind: string): string[] {
  return readFileSync(logFile, "utf8")
    .split("\n")
    .filter((l) => l.startsWith(`${kind}|`));
}

/** 반복문 케이스 표: [ID, 설명, spec, get 수, set 수]. */
const LOOP_CASES: Array<[string, string, string, number, number]> = [
  ["01", "전부 존재하면 건너뜀", "ok", 8, 0],
  ["02", "전부 404(stderr)면 8개 생성", "nfErr", 8, 8],
  ["03", "404 메시지가 stdout 이어도 8개 생성", "nfOut", 8, 8],
  ["04", "혼합이면 없는 6개만 생성", "ok;ok;nfOut", 8, 6],
  ["05", "403 이면 멈추고 생성 0", "403", 1, 0],
  ["06", "인증 실패면 멈추고 생성 0", "auth", 1, 0],
  ["07", "네트워크 오류면 멈추고 생성 0", "net", 1, 0],
  ["08", "404 두 번 뒤 403 이면 생성 2 에서 멈춤", "nfOut;nfOut;403", 3, 2],
];

for (const [shellName, shell, available] of SHELLS) {
  const suite = available ? describe : describe.skip;
  suite(`manual secret snippets under ${shellName}`, () => {
    it("T-173-SNIPPET-00 두 스니펫이 -n 문법 검사를 통과한다", () => {
      const [cmd, ...args] = shell;
      for (const s of [loopSnippet(), checkSnippet()]) {
        const file = join(sandbox, "syn.sh");
        writeFileSync(file, s);
        const r = spawnSync(cmd as string, [...args, "-n", file]);
        expect(r.status).toBe(0);
      }
    });

    it.each(LOOP_CASES)(
      "T-173-SNIPPET-%s %s",
      (_id, _label, spec, gets, sets) => {
        const r = run(shell, loopSnippet(), spec);
        expect(calls("get")).toHaveLength(gets);
        const setCalls = calls("set");
        expect(setCalls).toHaveLength(sets);
        for (const c of setCalls) {
          expect(c).toContain(`--project ${PROJECT} --data-file -`);
          expect(c.endsWith("stdin=[unset]")).toBe(true);
        }
        if (sets === 0 || /403|auth|net/.test(spec)) {
          expect(r.status).toBe(0);
        }
        if (/403|auth|net/.test(spec)) {
          const msg = GET_RESPONSES[spec.split(";").pop() as string]?.[2];
          expect(r.stderr).toContain(msg);
        }
      },
    );

    it("T-173-SNIPPET-09 404 뒤 set 이 실패하면 멈춘다", () => {
      run(shell, loopSnippet(), "nfOut", {FAKE_SET_EXIT: "2"});
      expect(calls("get")).toHaveLength(1);
      expect(calls("set")).toHaveLength(1);
    });

    it("T-173-SNIPPET-10 반복문에 주석 줄이 없다", () => {
      for (const line of loopSnippet().split("\n")) {
        expect(line).not.toMatch(/^\s*#/);
        expect(line).not.toMatch(/\s#/);
      }
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
