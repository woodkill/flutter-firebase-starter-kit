/**
 * `scripts/deploy_email.sh` 동작 검증 (Phase 17.5 D-02 · D-04 · D-09).
 *
 * 스크립트 · `hosting/`(public · build.mjs) · `functions/src/email/copy.json` ·
 * 추적 중인 확장 env 두 파일을 임시 디렉터리에 복사해(ROOT 는 스크립트 위치
 * 기준) fixture `config/dev.json` 으로 실행한다. 실제 config 는 읽지 않고,
 * `firebase` 는 PATH 의 가짜 실행 파일로 대체해 호출 인자를 기록한다. `node` 는
 * 진짜를 쓴다 — 결과 페이지 빌드 산출 확인이 목적이다.
 *
 * 로고 파일은 sandbox 복사 직후 지운다(없음이 기본) — 사용자가 저장소에 자기
 * 로고를 둬도 결과가 같다.
 */

import {spawnSync} from "node:child_process";
import {
  chmodSync,
  copyFileSync,
  cpSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import {tmpdir} from "node:os";
import {join} from "node:path";

/** 스크립트 실행 결과. */
type RunResult = {status: number | null; stdout: string; stderr: string};

const REPO_ROOT = join(__dirname, "..", "..");
const PROJECT_ID = "your-project-dev";

/** 결과 페이지 빌드가 통과하는 최소 config (모드 키 없음 = firebase). */
const BASE_CONFIG: Record<string, unknown> = {
  firebaseProjectId: PROJECT_ID,
  appName: "Starter Kit",
  brandColor: "#673AB7",
};

let sandbox = "";
let fakeBin = "";
let invocationLog = "";
let markerFile = "";

beforeEach(() => {
  sandbox = mkdtempSync(join(tmpdir(), "deploy-email-"));
  for (const dir of ["scripts", "config", "extensions", "functions"]) {
    mkdirSync(join(sandbox, dir));
  }
  copyFileSync(
    join(REPO_ROOT, "scripts", "deploy_email.sh"),
    join(sandbox, "scripts", "deploy_email.sh"),
  );
  mkdirSync(join(sandbox, "hosting"));
  copyFileSync(
    join(REPO_ROOT, "hosting", "build.mjs"),
    join(sandbox, "hosting", "build.mjs"),
  );
  cpSync(
    join(REPO_ROOT, "hosting", "public"),
    join(sandbox, "hosting", "public"),
    {recursive: true},
  );
  // 저장소에 사용자 로고가 있어도 sandbox 기본은 「로고 없음」 이다.
  rmSync(join(sandbox, "hosting", "public", "logo.png"), {force: true});
  mkdirSync(join(sandbox, "functions", "src", "email"), {recursive: true});
  copyFileSync(
    join(REPO_ROOT, "functions", "src", "email", "copy.json"),
    join(sandbox, "functions", "src", "email", "copy.json"),
  );
  // 추적 중인 두 파일만 복사한다 — 사용자의 프로젝트별 env 파일은 읽지 않는다.
  for (const name of [
    "firestore-send-email.env",
    "firestore-send-email.env.example",
  ]) {
    copyFileSync(
      join(REPO_ROOT, "extensions", name),
      join(sandbox, "extensions", name),
    );
  }
  fakeBin = join(sandbox, "fakebin");
  mkdirSync(fakeBin);
  invocationLog = join(sandbox, "firebase_calls.log");
  markerFile = join(sandbox, "firebase_called.marker");
  // 가짜 firebase: 호출 표시 + 인자를 탭 구분 한 줄로 기록한다.
  const fake =
    "#!/usr/bin/env bash\n" +
    `touch '${markerFile}'\n` +
    `printf '%s\\t' "$@" >> '${invocationLog}'\n` +
    `printf '\\n' >> '${invocationLog}'\n`;
  writeFileSync(join(fakeBin, "firebase"), fake);
  chmodSync(join(fakeBin, "firebase"), 0o755);
});

afterEach(() => {
  rmSync(sandbox, {recursive: true, force: true});
});

/**
 * fixture config/dev.json 을 쓴다.
 * @param {Record<string, unknown>} config config JSON 내용.
 */
function writeConfig(config: Record<string, unknown>): void {
  writeFileSync(join(sandbox, "config", "dev.json"), JSON.stringify(config));
}

/**
 * 스크립트를 bash 로 실행한다(가짜 firebase 가 PATH 앞).
 * @param {string[]} args 스크립트 인자.
 * @return {RunResult} 종료 코드 · stdout · stderr.
 */
function runScript(args: string[]): RunResult {
  const result = spawnSync(
    "bash",
    [join(sandbox, "scripts", "deploy_email.sh"), ...args],
    {
      encoding: "utf8",
      env: {
        ...process.env,
        LC_ALL: "C",
        PATH: `${fakeBin}:${process.env.PATH ?? ""}`,
      },
    },
  );
  return {
    status: result.status,
    stdout: result.stdout ?? "",
    stderr: result.stderr ?? "",
  };
}

/**
 * 가짜 firebase 호출 인자 목록 (호출마다 한 배열).
 * @return {Array<Array<string>>} 호출별 인자.
 */
function readCalls(): string[][] {
  if (!existsSync(invocationLog)) return [];
  return readFileSync(invocationLog, "utf8")
    .split("\n")
    .filter((l) => l.length > 0)
    .map((l) => l.split("\t").filter((t) => t.length > 0));
}

/**
 * 마지막 비어있지 않은 stdout 줄.
 * @param {string} stdout 스크립트 stdout.
 * @return {string} 마지막 줄.
 */
function lastLine(stdout: string): string {
  const lines = stdout.split("\n").filter((l) => l.length > 0);
  return lines[lines.length - 1] ?? "";
}

/**
 * [prefix] 로 시작하는 stdout 줄.
 * @param {string} stdout 스크립트 stdout.
 * @param {string} prefix 줄 머리.
 * @return {string[]} 일치하는 줄.
 */
function linesWith(stdout: string, prefix: string): string[] {
  return stdout.split("\n").filter((l) => l.startsWith(prefix));
}

describe("deploy_email.sh hosting", () => {
  it("T-175-DEPLOY-01 hosting dry-run 은 빌드 후 명령만 출력하고 firebase 호출 0", () => {
    writeConfig(BASE_CONFIG);
    const r = runScript(["dev", "hosting"]);
    expect(r.status).toBe(0);
    expect(r.stdout).toContain("flavor: dev\n");
    expect(r.stdout).toContain(`project: ${PROJECT_ID}\n`);
    expect(r.stdout).toContain("mode: firebase\n");
    expect(r.stdout).toContain("target: hosting\n");
    expect(linesWith(r.stdout, "command: ")).toEqual([
      `command: firebase deploy --project ${PROJECT_ID} --only hosting`,
    ]);
    expect(lastLine(r.stdout)).toBe(
      "DRY-RUN OK dev target=hosting mode=firebase",
    );
    expect(existsSync(markerFile)).toBe(false);
    expect(
      existsSync(join(sandbox, "build", "hosting", "public", "index.html")),
    ).toBe(true);
  });

  it("T-175-DEPLOY-02 hosting 은 발송 모드와 독립이다(kit 모드도 DRY-RUN OK)", () => {
    writeConfig({...BASE_CONFIG, emailDelivery: "kit"});
    const r = runScript(["dev", "hosting"]);
    expect(r.status).toBe(0);
    expect(r.stdout).toContain("mode: kit\n");
    expect(lastLine(r.stdout)).toBe("DRY-RUN OK dev target=hosting mode=kit");
    expect(existsSync(markerFile)).toBe(false);
  });

  it("T-175-DEPLOY-03 hosting --apply 는 deploy --only hosting 1회 실행", () => {
    writeConfig({...BASE_CONFIG, emailDelivery: "firebase"});
    const r = runScript(["dev", "hosting", "--apply"]);
    expect(r.status).toBe(0);
    expect(readCalls()).toEqual([
      ["deploy", "--project", PROJECT_ID, "--only", "hosting"],
    ]);
    expect(lastLine(r.stdout)).toBe(
      "DEPLOY OK dev target=hosting mode=firebase",
    );
  });

  it.each([
    ["인자 없음", []],
    ["대상 누락", ["dev"]],
    ["알 수 없는 대상", ["dev", "foo"]],
    ["잘못된 flavor", ["qa", "hosting"]],
    ["알 수 없는 3번째 인자", ["dev", "hosting", "--force"]],
    ["인자 4개", ["dev", "hosting", "--apply", "extra"]],
  ])("T-175-DEPLOY-04a 인자 오류(%s)는 exit 2 + usage", (_label, args) => {
    writeConfig(BASE_CONFIG);
    const r = runScript(args);
    expect(r.status).toBe(2);
    expect(r.stderr).toContain("usage:");
    expect(r.stdout).toBe("");
    expect(existsSync(markerFile)).toBe(false);
  });

  it.each([
    ["config 없음", null],
    ["프로젝트 ID 형식 오류", {...BASE_CONFIG, firebaseProjectId: "My_Proj"}],
    ["프로젝트 ID 빈 값", {...BASE_CONFIG, firebaseProjectId: ""}],
    ["emailDelivery 허용 밖 값", {...BASE_CONFIG, emailDelivery: "smtp"}],
    ["emailDelivery 대문자", {...BASE_CONFIG, emailDelivery: "Kit"}],
    ["emailDelivery 앞뒤 공백", {...BASE_CONFIG, emailDelivery: " kit"}],
    ["emailDelivery 문자열 아님", {...BASE_CONFIG, emailDelivery: true}],
  ])("T-175-DEPLOY-04b 입력 오류(%s)는 FAIL exit 1", (_label, config) => {
    if (config !== null) writeConfig(config);
    const r = runScript(["dev", "hosting", "--apply"]);
    expect(r.status).toBe(1);
    expect(r.stderr.startsWith("FAIL:")).toBe(true);
    expect(r.stdout).not.toContain("command:");
    expect(existsSync(markerFile)).toBe(false);
  });

  it("T-175-DEPLOY-05 다른 config 키 값 · 모드 원문 값을 출력하지 않는다", () => {
    const sentinel = "SENTINEL_SECRET_175";
    const config = {...BASE_CONFIG, naverClientSecret: sentinel};
    writeConfig(config);
    for (const args of [["dev", "hosting"], ["dev", "hosting", "--apply"]]) {
      const r = runScript(args);
      expect(r.status).toBe(0);
      expect(r.stdout).not.toContain(sentinel);
      expect(r.stderr).not.toContain(sentinel);
    }
    expect(readFileSync(invocationLog, "utf8")).not.toContain(sentinel);

    writeConfig({...config, emailDelivery: "smtp"});
    const bad = runScript(["dev", "hosting"]);
    expect(bad.status).toBe(1);
    expect(bad.stderr).toContain("emailDelivery");
    for (const out of [bad.stdout, bad.stderr]) {
      expect(out).not.toContain("smtp");
      expect(out).not.toContain(sentinel);
    }
  });
});
