/**
 * `scripts/deploy_email.sh` 동작 검증 (Phase 17.5 D-02 · D-04 · D-05 · D-06 ·
 * D-09 · D-14 · D-22).
 *
 * 스크립트 · `hosting/`(public · build.mjs) · `functions/src/email/copy.json` ·
 * 추적 중인 확장 env 두 파일을 임시 디렉터리에 복사해(ROOT 는 스크립트 위치
 * 기준) fixture `config/dev.json` 으로 실행한다. 실제 config 는 읽지 않고,
 * `firebase` 는 PATH 의 가짜 실행 파일로 대체해 호출 인자를 기록한다. `node` 는
 * 진짜를 쓴다 — 결과 페이지 빌드 산출 확인이 목적이다.
 *
 * 가짜 `firebase` 는 env `FAKE_FIREBASE_FAIL_ON` 값과 같은 인자를 받으면 호출을
 * 기록한 뒤 exit 1 이다(배포 실패 주입 — 값이 없으면 항상 성공).
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

/** 확장 env 파일 (sandbox 기준 경로) — 사용자가 예시에서 복사해 만드는 파일. */
const EXT_ENV_REL = `extensions/firestore-send-email.env.${PROJECT_ID}`;

/** 함수 env 파일 (sandbox 기준 경로) — kit --apply 가 메일 env 4줄을 쓴다. */
const FN_ENV_REL = `functions/.env.${PROJECT_ID}`;

/** 확장 env 값에 넣는 sentinel — 어떤 출력에도 나오면 안 된다. */
const SMTP_SENTINEL = "SENTINEL_SMTP_175";

/** 키 4개가 다 있는 확장 env (값에 sentinel 을 섞는다). */
const VALID_EXT_ENV: Record<string, string> = {
  DATABASE_REGION: "asia-northeast3",
  DEFAULT_FROM: `"Kit <no-reply@${SMTP_SENTINEL}.example.com>"`,
  SMTP_CONNECTION_URI: `smtps://${SMTP_SENTINEL}@smtp.example.com:465`,
  SMTP_PASSWORD:
    `projects/123/secrets/${SMTP_SENTINEL}_PASSWORD/versions/latest`,
};

/** 1×1 PNG — 로고 있음 케이스에서 sandbox 에 쓴다. */
const TINY_PNG = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA" +
    "60e6kgAAAABJRU5ErkJggg==",
  "base64",
);

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
  // 가짜 firebase: 호출 표시 + 인자를 탭 구분 한 줄로 기록한다. 기록한 뒤
  // FAKE_FIREBASE_FAIL_ON 과 같은 인자가 있으면 exit 1(배포 실패 주입).
  const fake =
    "#!/usr/bin/env bash\n" +
    `touch '${markerFile}'\n` +
    `printf '%s\\t' "$@" >> '${invocationLog}'\n` +
    `printf '\\n' >> '${invocationLog}'\n` +
    "if [ -n \"${FAKE_FIREBASE_FAIL_ON:-}\" ]; then\n" +
    "  for arg in \"$@\"; do\n" +
    "    [ \"$arg\" = \"$FAKE_FIREBASE_FAIL_ON\" ] && exit 1\n" +
    "  done\n" +
    "fi\n" +
    "exit 0\n";
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
 * sandbox 확장 env 파일을 쓴다.
 * @param {Record<string, string>} entries 키 → 값 (값은 파일에 그대로 쓴다).
 */
function writeExtEnv(entries: Record<string, string>): void {
  const body = Object.entries(entries)
    .map(([key, value]) => `${key}=${value}\n`)
    .join("");
  writeFileSync(join(sandbox, EXT_ENV_REL), body);
}

/**
 * sandbox 함수 env 파일 내용 (없으면 null).
 * @return {string | null} 파일 내용.
 */
function readFnEnv(): string | null {
  const file = join(sandbox, FN_ENV_REL);
  return existsSync(file) ? readFileSync(file, "utf8") : null;
}

/**
 * [text] 에서 [prefix] 로 시작하는 줄 수.
 * @param {string} text 여러 줄 텍스트.
 * @param {string} prefix 줄 머리.
 * @return {number} 줄 수.
 */
function countLines(text: string, prefix: string): number {
  return text.split("\n").filter((l) => l.startsWith(prefix)).length;
}

/**
 * 스크립트를 bash 로 실행한다(가짜 firebase 가 PATH 앞).
 * @param {string[]} args 스크립트 인자.
 * @param {Record<string, string>} extraEnv 더 넘길 env(예: 가짜 firebase 의
 *   실패 주입 `FAKE_FIREBASE_FAIL_ON`). 기본은 없음.
 * @return {RunResult} 종료 코드 · stdout · stderr.
 */
function runScript(
  args: string[],
  extraEnv: Record<string, string> = {},
): RunResult {
  const result = spawnSync(
    "bash",
    [join(sandbox, "scripts", "deploy_email.sh"), ...args],
    {
      encoding: "utf8",
      env: {
        ...process.env,
        LC_ALL: "C",
        PATH: `${fakeBin}:${process.env.PATH ?? ""}`,
        ...extraEnv,
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

describe("deploy_email.sh kit", () => {
  const KIT_CONFIG = {...BASE_CONFIG, emailDelivery: "kit"};

  it.each([
    ["모드 키 없음", BASE_CONFIG],
    ["firebase", {...BASE_CONFIG, emailDelivery: "firebase"}],
  ])("T-175-DEPLOY-06 firebase 모드(%s)에서 kit 은 FAIL", (_label, config) => {
    writeConfig(config);
    writeExtEnv(VALID_EXT_ENV);
    for (const args of [["dev", "kit"], ["dev", "kit", "--apply"]]) {
      const r = runScript(args);
      expect(r.status).toBe(1);
      expect(r.stderr.startsWith("FAIL:")).toBe(true);
      expect(r.stderr).toContain("emailDelivery");
      expect(r.stderr).toContain("kit");
      expect(r.stdout).not.toContain("command:");
    }
    expect(existsSync(markerFile)).toBe(false);
    expect(readFnEnv()).toBeNull();
  });

  it("T-175-DEPLOY-07a 확장 env 파일이 없으면 cp 안내와 함께 FAIL", () => {
    writeConfig(KIT_CONFIG);
    const r = runScript(["dev", "kit", "--apply"]);
    expect(r.status).toBe(1);
    expect(r.stderr).toContain(
      "cp extensions/firestore-send-email.env.example " + EXT_ENV_REL,
    );
    expect(existsSync(markerFile)).toBe(false);
    expect(readFnEnv()).toBeNull();
  });

  it.each([
    ["DATABASE_REGION 없음", "DATABASE_REGION", undefined],
    ["DEFAULT_FROM 없음", "DEFAULT_FROM", undefined],
    ["SMTP_CONNECTION_URI 없음", "SMTP_CONNECTION_URI", undefined],
    ["SMTP_PASSWORD 없음", "SMTP_PASSWORD", undefined],
    ["SMTP_CONNECTION_URI 빈 값", "SMTP_CONNECTION_URI", ""],
    ["SMTP_PASSWORD 가 리소스 이름 아님", "SMTP_PASSWORD", SMTP_SENTINEL],
    [
      "SMTP_PASSWORD 자리표시 그대로",
      "SMTP_PASSWORD",
      "projects/<your-project-number>/secrets/x/versions/latest",
    ],
  ])("T-175-DEPLOY-07b 확장 env %s → 키 이름만 알리고 FAIL", (_l, key, value) => {
    const entries = {...VALID_EXT_ENV};
    if (value === undefined) {
      delete entries[key];
    } else {
      entries[key] = value;
    }
    writeConfig(KIT_CONFIG);
    writeExtEnv(entries);
    const r = runScript(["dev", "kit", "--apply"]);
    expect(r.status).toBe(1);
    expect(r.stderr.startsWith("FAIL:")).toBe(true);
    expect(r.stderr).toContain(key);
    expect(r.stdout + r.stderr).not.toContain(SMTP_SENTINEL);
    expect(existsSync(markerFile)).toBe(false);
    expect(readFnEnv()).toBeNull();
  });

  it("T-175-DEPLOY-08 kit dry-run 은 빌드 · env 4줄 · 명령 2줄 · 다음 단계만 출력", () => {
    writeConfig(KIT_CONFIG);
    writeExtEnv(VALID_EXT_ENV);
    const r = runScript(["dev", "kit"]);
    expect(r.status).toBe(0);
    expect(r.stdout).toContain("mode: kit\n");
    expect(r.stdout).toContain("target: kit\n");
    expect(linesWith(r.stdout, "env: ")).toEqual([
      "env: EMAIL_APP_NAME=\"Starter Kit\"",
      "env: EMAIL_BRAND_COLOR=\"#673AB7\"",
      "env: EMAIL_LOGO_URL=\"\"",
      `env: EMAIL_RESULT_PAGE_URL="https://${PROJECT_ID}.web.app/"`,
    ]);
    expect(linesWith(r.stdout, "command: ")).toEqual([
      `command: firebase deploy --project ${PROJECT_ID} --only hosting`,
      `command: firebase deploy --project ${PROJECT_ID} --only extensions`,
    ]);
    expect(linesWith(r.stdout, "BUILD OK")).toHaveLength(1);
    expect(linesWith(r.stdout, "next: ")).toEqual([
      "next: bash scripts/deploy_functions.sh dev --apply",
      "next: gcloud firestore fields ttls update delivery.expireAt " +
        `--collection-group=mail --enable-ttl --project ${PROJECT_ID}`,
    ]);
    expect(lastLine(r.stdout)).toBe("DRY-RUN OK dev target=kit mode=kit");
    expect(readFnEnv()).toBeNull();
    expect(existsSync(markerFile)).toBe(false);
    expect(
      existsSync(join(sandbox, "build", "hosting", "public", "index.html")),
    ).toBe(true);
    expect(r.stdout + r.stderr).not.toContain(SMTP_SENTINEL);
  });

  it("T-175-DEPLOY-09 kit --apply 는 결과 페이지 → 메일 env 4줄 → 확장 순이다", () => {
    writeConfig(KIT_CONFIG);
    writeExtEnv(VALID_EXT_ENV);
    writeFileSync(
      join(sandbox, FN_ENV_REL),
      "# 사용자 주석\n" +
        "SEND_TEST_PUSH_ENABLED=true\n" +
        "EMAIL_APP_NAME=\"Old\"\n" +
        "export EMAIL_LOGO_URL=\"https://old.example.com/x.png\"\n" +
        "EMAIL_RESULT_PAGE_URL=\"https://old.example.com/\"\n",
    );
    const r = runScript(["dev", "kit", "--apply"]);
    expect(r.status).toBe(0);
    const env = readFnEnv() ?? "";
    expect(env).toBe(
      "# 사용자 주석\n" +
        "SEND_TEST_PUSH_ENABLED=true\n" +
        "EMAIL_APP_NAME=\"Starter Kit\"\n" +
        "EMAIL_BRAND_COLOR=\"#673AB7\"\n" +
        "EMAIL_LOGO_URL=\"\"\n" +
        `EMAIL_RESULT_PAGE_URL="https://${PROJECT_ID}.web.app/"\n`,
    );
    expect(countLines(env, "SEND_TEST_PUSH_ENABLED=true")).toBe(1);
    expect(countLines(env, "EMAIL_APP_NAME=")).toBe(1);
    expect(countLines(env, "EMAIL_BRAND_COLOR=")).toBe(1);
    expect(countLines(env, "EMAIL_LOGO_URL=")).toBe(1);
    expect(countLines(env, "EMAIL_RESULT_PAGE_URL=")).toBe(1);
    expect(readCalls()).toEqual([
      ["deploy", "--project", PROJECT_ID, "--only", "hosting"],
      ["deploy", "--project", PROJECT_ID, "--only", "extensions"],
    ]);
    expect(linesWith(r.stdout, "running: ")).toEqual([
      `running: firebase deploy --project ${PROJECT_ID} --only hosting`,
      `running: firebase deploy --project ${PROJECT_ID} --only extensions`,
    ]);
    expect(linesWith(r.stdout, "next: ")).toHaveLength(2);
    expect(lastLine(r.stdout)).toBe("DEPLOY OK dev target=kit mode=kit");
    expect(r.stdout + r.stderr).not.toContain(SMTP_SENTINEL);
    expect(readFileSync(invocationLog, "utf8")).not.toContain(SMTP_SENTINEL);
  });

  it("T-175-DEPLOY-16 결과 페이지 배포가 실패하면 함수 env · 확장은 그대로다", () => {
    writeConfig(KIT_CONFIG);
    writeExtEnv(VALID_EXT_ENV);
    const before =
      "# 사용자 주석\n" +
      "SEND_TEST_PUSH_ENABLED=true\n" +
      "EMAIL_APP_NAME=\"Old\"\n";
    writeFileSync(join(sandbox, FN_ENV_REL), before);
    const r = runScript(["dev", "kit", "--apply"], {
      FAKE_FIREBASE_FAIL_ON: "hosting",
    });
    expect(r.status).toBe(1);
    expect(r.stderr.startsWith("FAIL:")).toBe(true);
    expect(r.stderr).toContain("결과 페이지");
    expect(readCalls()).toEqual([
      ["deploy", "--project", PROJECT_ID, "--only", "hosting"],
    ]);
    expect(readFnEnv()).toBe(before);
    expect(r.stdout).not.toContain("wrote:");
    expect(r.stdout).not.toContain("DEPLOY OK");
  });

  it("T-175-DEPLOY-10a 로고 파일이 있으면 Hosting 절대 URL, 없으면 빈 값", () => {
    writeConfig(KIT_CONFIG);
    writeExtEnv(VALID_EXT_ENV);
    const without = runScript(["dev", "kit", "--apply"]);
    expect(without.status).toBe(0);
    expect(readFnEnv()).toContain("EMAIL_LOGO_URL=\"\"\n");

    writeFileSync(join(sandbox, "hosting", "public", "logo.png"), TINY_PNG);
    const withLogo = runScript(["dev", "kit", "--apply"]);
    expect(withLogo.status).toBe(0);
    expect(readFnEnv()).toContain(
      `EMAIL_LOGO_URL="https://${PROJECT_ID}.web.app/logo.png"\n`,
    );
  });

  it.each([
    ["형식 오류", "blue", "#673AB7", true],
    ["앞뒤 공백", " #00FF00", "#673AB7", true],
    ["키 없음", undefined, "#673AB7", false],
    ["빈 값", "", "#673AB7", false],
    ["소문자 유효", "#abcdef", "#abcdef", false],
  ])(
    "T-175-DEPLOY-10b brandColor %s → 정규화 · 형식 오류만 warn",
    (_label, color, expected, warns) => {
      const config: Record<string, unknown> = {...KIT_CONFIG};
      if (color === undefined) {
        delete config.brandColor;
      } else {
        config.brandColor = color;
      }
      writeConfig(config);
      writeExtEnv(VALID_EXT_ENV);
      const r = runScript(["dev", "kit", "--apply"]);
      expect(r.status).toBe(0);
      expect(readFnEnv()).toContain(`EMAIL_BRAND_COLOR="${expected}"\n`);
      expect(countLines(r.stderr, "warn: ")).toBe(warns ? 1 : 0);
    },
  );

  it.each([
    ["큰따옴표", "A\"B"],
    ["달러", "A$B"],
    ["역슬래시", "A\\B"],
    ["백틱", "A`B"],
    ["줄바꿈", "A\nB"],
    ["빈 값", ""],
    ["공백만", "   "],
  ])("T-175-DEPLOY-10c appName %s 는 FAIL", (_label, appName) => {
    writeConfig({...KIT_CONFIG, appName});
    writeExtEnv(VALID_EXT_ENV);
    const r = runScript(["dev", "kit", "--apply"]);
    expect(r.status).toBe(1);
    expect(r.stderr.startsWith("FAIL:")).toBe(true);
    expect(r.stderr).toContain("appName");
    expect(existsSync(markerFile)).toBe(false);
    expect(readFnEnv()).toBeNull();
  });
});
