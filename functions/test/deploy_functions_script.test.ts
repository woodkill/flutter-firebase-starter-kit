/**
 * `scripts/deploy_functions.sh` 동작 검증 (Phase 17.3 SOCL-09 · D-08 · D-09 ·
 * Phase 17.5 원칙 P — `emailDelivery` 가 kit 일 때만 `email.kit` 함수 포함).
 *
 * 스크립트를 임시 디렉터리에 복사해(ROOT 는 스크립트 위치 기준) fixture
 * `config/dev.json` 으로 실행한다. 실제 config 는 읽지 않고, `firebase` 는 PATH 의
 * 가짜 실행 파일로 대체해 호출 인자를 기록한다. 기대 함수 목록은 실제
 * `scripts/functions_manifest.json` 에서 계산한다(이름 하드코딩 없음).
 * manifest ↔ index.ts 대조는 `deploy_manifest.test.ts` 가 맡는다.
 */

import {spawnSync} from "node:child_process";
import {
  chmodSync,
  copyFileSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import {tmpdir} from "node:os";
import {join} from "node:path";

/** manifest JSON 모양. */
type Manifest = {
  common: string[];
  providers: Record<string, string[]>;
  email: {kit: string[]};
};

/** 메일 발송 모드 (config `emailDelivery` 정규화 값). */
type EmailMode = "firebase" | "kit";

/** 스크립트 실행 결과. */
type RunResult = {status: number | null; stdout: string; stderr: string};

const REPO_SCRIPTS = join(__dirname, "..", "..", "scripts");
const manifest = JSON.parse(
  readFileSync(join(REPO_SCRIPTS, "functions_manifest.json"), "utf8"),
) as Manifest;
const ALL_SLUGS = Object.keys(manifest.providers);
const BATCH_MAX = 10;

/**
 * 프로젝트 ID 검사를 돌릴 로캘. C 는 하네스 기본이고, UTF-8 두 개는 macOS
 * `/bin/bash` 3.2 가 대괄호 문자 범위를 정렬 순서로 해석하는 경로다(ko_KR 은
 * 유지보수자 로캘).
 *
 * 한계: 이 로캘 행들은 PATH 의 `bash` 가 그 로캘을 갖고 범위를 정렬 순서로 해석하는
 * 환경에서만 회귀를 잡는다. 설치되지 않은 로캘은 bash 가 C 로 처리하므로 옛 범위
 * 패턴도 통과한다. 환경과 무관한 회귀 가드는 T-173-DEPLOY-12d(스크립트 소스 잠금)다.
 */
const ID_CHECK_LOCALES: string[] = ["C", "en_US.UTF-8", "ko_KR.UTF-8"];

/** 형식 검사에서 거부돼야 하는 프로젝트 ID (라벨, 값). */
const INVALID_PROJECT_IDS: Array<[string, string]> = [
  ["빈 값", ""],
  ["하이픈 시작", "-evil"],
  ["대문자 포함", "myProj"],
  ["대문자 시작", "My-proj"],
  ["허용 밖 문자", "my_proj"],
  ["공백 포함", "my proj"],
];

/** 잘못된 프로젝트 ID 를 로캘마다 펼친 (라벨, 로캘, 값) 표. */
const INVALID_PROJECT_ID_CASES: Array<[string, string, string]> =
  INVALID_PROJECT_IDS.flatMap(([label, id]) =>
    ID_CHECK_LOCALES.map((locale): [string, string, string] => [
      label,
      locale,
      id,
    ]),
  );

let sandbox = "";
let fakeBin = "";
let invocationLog = "";
let markerFile = "";

beforeEach(() => {
  sandbox = mkdtempSync(join(tmpdir(), "deploy-fn-"));
  mkdirSync(join(sandbox, "scripts"));
  mkdirSync(join(sandbox, "config"));
  copyFileSync(
    join(REPO_SCRIPTS, "deploy_functions.sh"),
    join(sandbox, "scripts", "deploy_functions.sh"),
  );
  copyFileSync(
    join(REPO_SCRIPTS, "functions_manifest.json"),
    join(sandbox, "scripts", "functions_manifest.json"),
  );
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
 * @param {Record<string, string>} extraEnv 추가 환경변수(예: locale).
 * @return {RunResult} 종료 코드 · stdout · stderr.
 */
function runScript(
  args: string[],
  extraEnv: Record<string, string> = {LC_ALL: "C"},
): RunResult {
  const result = spawnSync(
    "bash",
    [join(sandbox, "scripts", "deploy_functions.sh"), ...args],
    {
      encoding: "utf8",
      env: {
        ...process.env,
        ...extraEnv,
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
 * manifest 순서로 기대 함수 목록(common + 켠 provider + kit 모드면 email.kit)을
 * 계산한다.
 * @param {string[]} enabled 켠 provider slug.
 * @param {EmailMode} mode 메일 발송 모드.
 * @return {string[]} 기대 함수 이름 목록.
 */
function expectedFunctions(
  enabled: string[],
  mode: EmailMode = "firebase",
): string[] {
  const list = [...manifest.common];
  for (const slug of ALL_SLUGS) {
    if (enabled.includes(slug)) list.push(...manifest.providers[slug]);
  }
  if (mode === "kit") list.push(...manifest.email.kit);
  return list;
}

/**
 * sandbox 의 `functions/.env.my-proj` 를 쓴다(kit --apply 사전 확인 대상).
 * @param {string} body 파일 내용.
 */
function writeFnEnv(body: string): void {
  mkdirSync(join(sandbox, "functions"), {recursive: true});
  writeFileSync(join(sandbox, "functions", ".env.my-proj"), body);
}

/**
 * stdout 의 `command:` 줄에서 `--only` 값(함수 이름 배열)을 묶음별로 뽑는다.
 * @param {string} stdout 스크립트 stdout.
 * @return {Array<Array<string>>} 묶음별 함수 이름.
 */
function parseBatches(stdout: string): string[][] {
  return stdout
    .split("\n")
    .filter((line) => line.startsWith("command: "))
    .map((line) => {
      const only = line.split(" --only ")[1] ?? "";
      return only.split(",").map((f) => f.replace(/^functions:/, ""));
    });
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

describe("deploy_functions.sh", () => {
  it("T-173-DEPLOY-04 dry-run 이 기본이며 firebase 를 호출하지 않는다", () => {
    writeConfig({firebaseProjectId: "my-proj", enabledAuthProviders: "kakao"});
    const r = runScript(["dev"]);
    const n = expectedFunctions(["kakao"]).length;
    expect(r.status).toBe(0);
    expect(lastLine(r.stdout)).toBe(`DRY-RUN OK dev functions=${n} batches=1`);
    expect(existsSync(markerFile)).toBe(false);
  });

  it("T-173-DEPLOY-05 CSV 가 비면 common 함수만 1묶음으로 고른다", () => {
    writeConfig({firebaseProjectId: "my-proj", enabledAuthProviders: ""});
    const r = runScript(["dev"]);
    expect(r.status).toBe(0);
    expect(parseBatches(r.stdout)).toEqual([manifest.common]);
    expect(lastLine(r.stdout)).toBe(
      `DRY-RUN OK dev functions=${manifest.common.length} batches=1`,
    );
  });

  it("T-173-DEPLOY-06 provider 하나면 common + 그 함수를 manifest 순서로 명령에 담는다", () => {
    const slug = ALL_SLUGS.find((s) => manifest.providers[s].length > 0);
    if (slug === undefined) {
      throw new Error("함수를 가진 provider 가 manifest 에 없다");
    }
    writeConfig({firebaseProjectId: "my-proj", enabledAuthProviders: slug});
    const r = runScript(["dev"]);
    const expected = expectedFunctions([slug]);
    expect(r.status).toBe(0);
    const only = expected.map((f) => `functions:${f}`).join(",");
    expect(r.stdout).toContain(
      `command: firebase deploy --project my-proj --only ${only}\n`,
    );
    expect(parseBatches(r.stdout).flat()).toEqual(expected);
  });

  it("T-173-DEPLOY-07 provider 전부 켜면 10개 이하 묶음으로 나누고 합집합이 기대 목록과 같다", () => {
    writeConfig({
      firebaseProjectId: "my-proj",
      enabledAuthProviders: ALL_SLUGS.join(","),
    });
    const r = runScript(["dev"]);
    const expected = expectedFunctions(ALL_SLUGS);
    const batches = parseBatches(r.stdout);
    expect(r.status).toBe(0);
    expect(expected.length).toBeGreaterThan(BATCH_MAX);
    expect(batches.length).toBe(Math.ceil(expected.length / BATCH_MAX));
    for (const b of batches) {
      expect(b.length).toBeGreaterThan(0);
      expect(b.length).toBeLessThanOrEqual(BATCH_MAX);
    }
    const flat = batches.flat();
    expect(new Set(flat).size).toBe(flat.length);
    expect(flat).toEqual(expected);
    expect(lastLine(r.stdout)).toBe(
      `DRY-RUN OK dev functions=${expected.length} batches=${batches.length}`,
    );
  });

  it("T-173-DEPLOY-08 토큰 순서 · 공백 · 빈 토큰 · 중복이 달라도 함수 목록 · 명령이 같다", () => {
    const [a, b] = ALL_SLUGS.slice(-2);
    const variants = [
      `${a},${b}`,
      `${b},${a}`,
      ` ${b} , ${a} `,
      `,${a},,${b},`,
      `${a},${b},${a},${b}`,
    ];
    // 결정성 계약은 함수 목록 · 명령에만 걸린다. `enabled:` 안내 줄은 사용자가 적은
    // CSV 순서를 그대로 보여주는 것이 정상이라 제외하고 비교한다.
    const outputs = variants.map((csv) => {
      writeConfig({firebaseProjectId: "my-proj", enabledAuthProviders: csv});
      const r = runScript(["dev"]);
      expect(r.status).toBe(0);
      return r.stdout
        .split("\n")
        .filter((l) => !l.startsWith("enabled:"))
        .join("\n");
    });
    for (const out of outputs) expect(out).toBe(outputs[0]);
  });

  it("T-173-DEPLOY-09 알 수 없는 provider 는 FAIL 로 거부하고 명령을 출력하지 않는다", () => {
    writeConfig({
      firebaseProjectId: "my-proj",
      enabledAuthProviders: "google,bogusprov",
    });
    const r = runScript(["dev"]);
    expect(r.status).toBe(1);
    expect(r.stderr.startsWith("FAIL:")).toBe(true);
    expect(r.stderr).toContain("bogusprov");
    expect(r.stdout).not.toContain("command:");
  });

  it("T-173-DEPLOY-10 config 파일이 없으면 FAIL 로 끝난다", () => {
    const r = runScript(["dev"]);
    expect(r.status).toBe(1);
    expect(r.stderr.startsWith("FAIL:")).toBe(true);
    expect(r.stdout).not.toContain("command:");
  });

  it.each([
    ["인자 없음", []],
    ["잘못된 flavor", ["qa"]],
    ["알 수 없는 2번째 인자", ["dev", "--force"]],
    ["인자 3개", ["dev", "--apply", "extra"]],
  ])("T-173-DEPLOY-11 인자 오류(%s)는 exit 2 + usage", (_label, args) => {
    writeConfig({firebaseProjectId: "my-proj", enabledAuthProviders: ""});
    const r = runScript(args);
    expect(r.status).toBe(2);
    expect(r.stderr).toContain("usage:");
    expect(r.stdout).toBe("");
    expect(existsSync(markerFile)).toBe(false);
  });

  // 표 전체를 C 와 UTF-8 로캘에서 모두 돌린다 — 형식 검사가 로캘에 기대지 않는다.
  it.each(INVALID_PROJECT_ID_CASES)(
    "T-173-DEPLOY-12 잘못된 firebaseProjectId(%s · LC_ALL=%s)는 FAIL",
    (_label, locale, id) => {
      writeConfig({firebaseProjectId: id, enabledAuthProviders: ""});
      const r = runScript(["dev"], {LC_ALL: locale});
      expect(r.status).toBe(1);
      expect(r.stderr.startsWith("FAIL:")).toBe(true);
      expect(r.stdout).not.toContain("command:");
    },
  );

  // 회귀 가드(quick 261007-0j4): macOS `/bin/bash` 3.2 는 UTF-8 로캘에서 대괄호
  // 문자 범위를 정렬 순서로 해석해 소문자 범위가 대문자까지 매치했다(대문자 ID 통과).
  // 스크립트는 허용 문자를 나열해 로캘과 무관하게 거부한다 — 그 동작을 지킨다.
  it("T-173-DEPLOY-12b UTF-8 locale 대문자 ID 거부", () => {
    writeConfig({firebaseProjectId: "My-proj", enabledAuthProviders: ""});
    const r = runScript(["dev"], {LC_ALL: "en_US.UTF-8"});
    expect(r.status).toBe(1);
    expect(r.stderr.startsWith("FAIL:")).toBe(true);
    expect(r.stderr).toContain("firebaseProjectId 형식이 잘못됐다");
    expect(r.stdout).not.toContain("command:");
  });

  it.each(ID_CHECK_LOCALES)(
    "T-173-DEPLOY-12c 유효한 소문자 ID(LC_ALL=%s)는 통과",
    (locale) => {
      writeConfig({firebaseProjectId: "my-proj-123", enabledAuthProviders: ""});
      const r = runScript(["dev"], {LC_ALL: locale});
      expect(r.status).toBe(0);
      expect(r.stdout).toContain("project: my-proj-123\n");
      expect(r.stdout).toContain(
        "command: firebase deploy --project my-proj-123 --only ",
      );
      expect(lastLine(r.stdout)).toBe(
        `DRY-RUN OK dev functions=${manifest.common.length} batches=1`,
      );
    },
  );

  // 환경과 무관한 회귀 가드: 위 로캘 행은 실행 bash · 설치 로캘에 따라 옛 범위
  // 패턴으로도 통과할 수 있다. 그래서 스크립트 소스의 형식 검사 두 줄이 허용 문자
  // 나열이고, 코드 줄(주석 제외)에 대괄호 문자 범위가 없음을 직접 잠근다.
  it("T-173-DEPLOY-12d 프로젝트 ID 검사는 문자 범위 없이 허용 문자를 나열한다(소스 잠금)", () => {
    const lines = readFileSync(
      join(REPO_SCRIPTS, "deploy_functions.sh"),
      "utf8",
    ).split("\n");
    expect(lines).toContain("  [abcdefghijklmnopqrstuvwxyz]*) ;;");
    expect(
      lines.filter((l) =>
        l.startsWith("  *[!abcdefghijklmnopqrstuvwxyz0123456789-]*) fail "),
      ),
    ).toHaveLength(1);

    // 대괄호 안의 `a-z` · `0-9` 꼴 범위(부정 `[!…]` 포함).
    const rangePattern = /\[!?[^\]]*[A-Za-z0-9]-[A-Za-z0-9]/;
    // 양성 대조 — 옛 패턴은 잡고 나열 패턴은 잡지 않는다.
    expect(rangePattern.test("  [a-z]*) ;;")).toBe(true);
    expect(rangePattern.test("  *[!a-z0-9-]*) fail")).toBe(true);
    expect(
      rangePattern.test("  [abcdefghijklmnopqrstuvwxyz]*) ;;"),
    ).toBe(false);
    expect(
      rangePattern.test("  *[!abcdefghijklmnopqrstuvwxyz0123456789-]*) fail"),
    ).toBe(false);

    const codeRanges = lines.filter(
      (l) => !l.trimStart().startsWith("#") && rangePattern.test(l),
    );
    expect(codeRanges).toEqual([]);
  });

  it("T-173-DEPLOY-13 --apply 는 출력한 명령을 같은 순서 · 인자로 실행한다", () => {
    writeConfig({
      firebaseProjectId: "my-proj",
      enabledAuthProviders: ALL_SLUGS.join(","),
    });
    const r = runScript(["dev", "--apply"]);
    const expected = expectedFunctions(ALL_SLUGS);
    const batches = parseBatches(r.stdout);
    expect(r.status).toBe(0);
    expect(lastLine(r.stdout)).toBe(
      `DEPLOY OK dev functions=${expected.length} batches=${batches.length}`,
    );

    const calls = readFileSync(invocationLog, "utf8")
      .split("\n")
      .filter((l) => l.length > 0)
      .map((l) => l.split("\t").filter((t) => t.length > 0));
    expect(calls.length).toBe(batches.length);
    const printed = batches.map((b) => [
      "deploy",
      "--project",
      "my-proj",
      "--only",
      b.map((f) => `functions:${f}`).join(","),
    ]);
    expect(calls).toEqual(printed);
    for (const argv of calls) {
      expect(argv).not.toContain("--force");
      expect(argv).not.toContain("--non-interactive");
    }
    const runningLines = r.stdout
      .split("\n")
      .filter((l) => l.startsWith("running: "))
      .map((l) => l.replace("running: ", "command: "));
    const commandLines = r.stdout
      .split("\n")
      .filter((l) => l.startsWith("command: "));
    expect(runningLines).toEqual(commandLines);
  });

  it("T-173-DEPLOY-14 다른 config 키는 읽지도 출력하지도 않는다", () => {
    const sentinel = "SENTINEL_SECRET_VALUE_9f3a";
    writeConfig({
      firebaseProjectId: "my-proj",
      enabledAuthProviders: "kakao",
      kakaoNativeAppKey: sentinel,
      someApiKey: sentinel,
    });
    for (const args of [["dev"], ["dev", "--apply"]]) {
      const r = runScript(args);
      expect(r.status).toBe(0);
      expect(r.stdout).not.toContain(sentinel);
      expect(r.stderr).not.toContain(sentinel);
    }
    expect(readFileSync(invocationLog, "utf8")).not.toContain(sentinel);
  });

  it.each([
    ["키 없음", undefined],
    ["빈 값", ""],
    ["firebase", "firebase"],
  ])(
    "T-175-DEPLOY-11 emailDelivery %s 면 메일 함수 0 · mode: firebase",
    (_label, mode) => {
      const config: Record<string, unknown> = {
        firebaseProjectId: "my-proj",
        enabledAuthProviders: "kakao",
      };
      if (mode !== undefined) config.emailDelivery = mode;
      writeConfig(config);
      const r = runScript(["dev"]);
      expect(r.status).toBe(0);
      expect(parseBatches(r.stdout).flat()).toEqual(
        expectedFunctions(["kakao"]),
      );
      for (const fn of manifest.email.kit) {
        expect(r.stdout).not.toContain(fn);
      }
      expect(
        r.stdout.split("\n").filter((l) => l.startsWith("mode: ")),
      ).toEqual(["mode: firebase"]);
    },
  );

  it("T-175-DEPLOY-12 emailDelivery kit 이면 email.kit 2개를 더한다", () => {
    writeConfig({
      firebaseProjectId: "my-proj",
      enabledAuthProviders: "kakao",
      emailDelivery: "kit",
    });
    writeFnEnv("EMAIL_APP_NAME=\"Kit App\"\n");
    const r = runScript(["dev"]);
    const expected = expectedFunctions(["kakao"], "kit");
    const batches = parseBatches(r.stdout);
    expect(r.status).toBe(0);
    expect(manifest.email.kit).toHaveLength(2);
    expect(expected.length).toBe(expectedFunctions(["kakao"]).length + 2);
    expect(batches.flat()).toEqual(expected);
    expect(r.stdout).toContain("mode: kit\n");
    expect(lastLine(r.stdout)).toBe(
      `DRY-RUN OK dev functions=${expected.length} batches=${batches.length}`,
    );
    expect(r.stderr).not.toContain("warn:");
  });

  // 세 번째 열 = 출력에 나오면 안 되는 원문 조각. ` kit` 은 FAIL 안내문(「· kit 가운데」)과
  // 겹쳐 원문 단언을 걸 수 없으므로 null 이다.
  it.each([
    ["허용 밖 값", "smtp", "smtp"],
    ["대문자", "Kit", "Kit"],
    ["앞뒤 공백", " kit", null],
    ["문자열 아님", true, "true"],
  ])("T-175-DEPLOY-13 emailDelivery %s 는 FAIL · 원문 미출력", (
    _label,
    mode,
    leak,
  ) => {
    const sentinel = "SENTINEL_SECRET_VALUE_175";
    writeConfig({
      firebaseProjectId: "my-proj",
      enabledAuthProviders: "",
      emailDelivery: mode,
      someApiKey: sentinel,
    });
    for (const args of [["dev"], ["dev", "--apply"]]) {
      const r = runScript(args);
      expect(r.status).toBe(1);
      expect(r.stderr.startsWith("FAIL:")).toBe(true);
      expect(r.stderr).toContain("emailDelivery");
      expect(r.stdout).not.toContain("command:");
      for (const out of [r.stdout, r.stderr]) {
        if (leak !== null) expect(out).not.toContain(leak);
        expect(out).not.toContain(sentinel);
      }
    }
    expect(existsSync(markerFile)).toBe(false);
  });

  it.each([
    ["env 파일 없음", null],
    ["EMAIL_APP_NAME 없음", "SEND_TEST_PUSH_ENABLED=true\n"],
    ["EMAIL_APP_NAME 빈 값", "EMAIL_APP_NAME=\"\"\n"],
    ["EMAIL_APP_NAME 빈 값(따옴표 없음)", "EMAIL_APP_NAME=\n"],
  ])("T-175-DEPLOY-14a kit --apply 사전 확인(%s)은 FAIL", (_label, body) => {
    writeConfig({
      firebaseProjectId: "my-proj",
      enabledAuthProviders: "",
      emailDelivery: "kit",
    });
    if (body !== null) writeFnEnv(body);
    const r = runScript(["dev", "--apply"]);
    expect(r.status).toBe(1);
    expect(r.stderr.startsWith("FAIL:")).toBe(true);
    expect(r.stderr).toContain("deploy_email.sh dev kit --apply");
    expect(existsSync(markerFile)).toBe(false);
  });

  it("T-175-DEPLOY-14b kit --apply 는 브랜드 env 가 있으면 메일 함수까지 배포한다", () => {
    writeConfig({
      firebaseProjectId: "my-proj",
      enabledAuthProviders: "",
      emailDelivery: "kit",
    });
    writeFnEnv("SEND_TEST_PUSH_ENABLED=true\nEMAIL_APP_NAME=\"Kit App\"\n");
    const r = runScript(["dev", "--apply"]);
    const expected = expectedFunctions([], "kit");
    expect(r.status).toBe(0);
    const deployed = readFileSync(invocationLog, "utf8")
      .split("\n")
      .filter((l) => l.length > 0)
      .map((l) => l.split("\t").filter((t) => t.length > 0)[4] ?? "")
      .join(",")
      .split(",")
      .map((f) => f.replace(/^functions:/, ""));
    expect(deployed).toEqual(expected);
    expect(lastLine(r.stdout)).toMatch(
      new RegExp(`^DEPLOY OK dev functions=${expected.length} batches=`),
    );
  });

  it("T-175-DEPLOY-15 kit dry-run 은 브랜드 env 가 없으면 warn 1줄 뒤 DRY-RUN OK", () => {
    writeConfig({
      firebaseProjectId: "my-proj",
      enabledAuthProviders: "",
      emailDelivery: "kit",
    });
    const r = runScript(["dev"]);
    const expected = expectedFunctions([], "kit");
    expect(r.status).toBe(0);
    expect(
      r.stderr.split("\n").filter((l) => l.startsWith("warn: ")),
    ).toHaveLength(1);
    expect(r.stderr).toContain("deploy_email.sh dev kit --apply");
    expect(lastLine(r.stdout)).toBe(
      `DRY-RUN OK dev functions=${expected.length} batches=1`,
    );
    expect(existsSync(markerFile)).toBe(false);
  });
});
