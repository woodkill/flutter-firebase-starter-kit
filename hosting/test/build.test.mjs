// Phase 17.5 — see ROADMAP.md (D-03 · D-05 · D-16) — 결과 페이지 주입 빌드 테스트.
//
// 실행: node --test --test-reporter=tap 'hosting/test/*.test.mjs'
//
// 각 테스트는 임시 root 에 fixture config · 실제 `hosting/public/` 사본 · 실제
// 문구 파일 사본을 두고 `hosting/build.mjs --root <tmp>` 를 돌린다. 로고 파일은
// fixture 가 명시적으로 정한다 — 복사 직후 지운다(없음이 기본). 그래서 저장소에
// 사용자 로고가 있어도 결과가 같다.

import {test} from "node:test";
import assert from "node:assert/strict";
import {spawnSync} from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {fileURLToPath} from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(HERE, "..", "..");
const BUILD = path.join(REPO, "hosting", "build.mjs");
const COPY = JSON.parse(
  fs.readFileSync(path.join(REPO, "functions", "src", "email", "copy.json"), "utf8"),
);
const SECRET = "SENTINEL_SECRET_175";
// 형식만 맞춘 가짜 Web API 키 — 실제 키가 아니다.
const FAKE_WEB_API_KEY = "PLACEHOLDER";
const OUT_REL = "build/hosting/public";
const ICON_NAMES = [
  "check", "schedule", "link_off", "person_off", "wifi_off", "error",
  "lock_reset", "visibility", "visibility_off",
];
// 1×1 투명 PNG — 실제 저장소 로고 파일에 기대지 않는다.
const TINY_PNG = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=",
  "base64",
);

/** 기본 fixture config — 읽지 말아야 할 비밀 sentinel 을 함께 둔다. */
function devConfig(overrides = {}) {
  return {
    flavor: "dev",
    appName: "Kit",
    firebaseProjectId: "your-project-dev",
    brandColor: "#673AB7",
    firebaseWebApiKey: FAKE_WEB_API_KEY,
    naverClientSecret: SECRET,
    ...overrides,
  };
}

/**
 * 임시 root 를 만든다. [configs] 의 키(dev · stg · prod)마다 config 파일을 쓴다.
 * 로고 파일은 지운 상태가 기본이다.
 */
function makeFixture(t, configs) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "kit-hosting-build-"));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  fs.mkdirSync(path.join(root, "config"));
  for (const [flavor, config] of Object.entries(configs)) {
    fs.writeFileSync(
      path.join(root, "config", `${flavor}.json`),
      JSON.stringify(config, null, 2),
    );
  }
  fs.mkdirSync(path.join(root, "hosting"));
  fs.cpSync(path.join(REPO, "hosting", "public"), path.join(root, "hosting", "public"), {
    recursive: true,
  });
  fs.rmSync(path.join(root, "hosting", "public", "logo.png"), {force: true});
  fs.mkdirSync(path.join(root, "functions", "src", "email"), {recursive: true});
  fs.copyFileSync(
    path.join(REPO, "functions", "src", "email", "copy.json"),
    path.join(root, "functions", "src", "email", "copy.json"),
  );
  return root;
}

/** build.mjs 를 [root] 기준으로 실행한다. */
function runBuild(root, args) {
  return spawnSync(process.execPath, [BUILD, ...args, "--root", root], {
    encoding: "utf8",
  });
}

/** 산출물 index.html 을 읽는다. */
function readIndex(root) {
  return fs.readFileSync(path.join(root, OUT_REL, "index.html"), "utf8");
}

/** 산출물 index.html 의 주입 JSON 을 파싱한다. */
function readKitConfig(root) {
  const html = readIndex(root);
  const match = html.match(
    /<script type="application\/json" id="kit-config">([\s\S]*?)<\/script>/,
  );
  assert.ok(match, "kit-config 스크립트 블록이 있어야 한다");
  return JSON.parse(match[1]);
}

/** 출력의 마지막 줄. */
function lastLine(text) {
  return text.trimEnd().split("\n").at(-1);
}

test("--flavor dev — BUILD OK 줄 · 주입 값 · 로고 없음", (t) => {
  const root = makeFixture(t, {dev: devConfig()});
  const result = runBuild(root, ["--flavor", "dev"]);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(
    lastLine(result.stdout),
    `BUILD OK flavor=dev project=your-project-dev logo=0 out=${OUT_REL}`,
  );
  assert.equal(result.stderr, "");

  const config = readKitConfig(root);
  assert.equal(config.appName, "Kit");
  assert.equal(config.brandColor, "#673AB7");
  assert.equal(config.onBrandColor, "#FFFFFF");
  assert.equal(config.hasLogo, false);
  assert.equal(config.apiKey, FAKE_WEB_API_KEY);
  assert.equal(config.authDomain, "your-project-dev.firebaseapp.com");
  // 주입 키 목록 고정 — config 에서 온 값은 appName · brandColor · apiKey ·
  // authDomain(프로젝트 ID) 뿐이다.
  assert.deepEqual(Object.keys(config).sort(), [
    "apiKey", "appName", "authDomain", "brandColor", "copy", "hasLogo", "icons",
    "onBrandColor",
  ]);
  assert.deepEqual(Object.keys(config.copy), ["ko", "en", "ja"]);
  assert.equal(config.copy.ko["page.loading"], COPY.ko["page.loading"]);
  for (const locale of ["ko", "en", "ja"]) {
    const keys = Object.keys(config.copy[locale]);
    assert.ok(keys.length > 0);
    assert.equal(keys.filter((k) => !k.startsWith("page.")).length, 0, locale);
    assert.equal(keys.filter((k) => k.startsWith("mail.")).length, 0, locale);
  }
  assert.deepEqual(Object.keys(config.icons).sort(), [...ICON_NAMES].sort());
  for (const [name, svg] of Object.entries(config.icons)) {
    assert.ok(svg.startsWith("<svg"), name);
    assert.equal(/ (width|height)="24"/.test(svg), false, name);
  }
  assert.equal(fs.existsSync(path.join(root, OUT_REL, "logo.png")), false);
  for (const file of ["index.html", "state.mjs", "page.css", "page.js"]) {
    assert.equal(fs.existsSync(path.join(root, OUT_REL, file)), true, file);
  }
  // 아이콘은 주입 JSON 에 인라인만 한다 — 파일로 복사하지 않는다.
  assert.equal(fs.existsSync(path.join(root, OUT_REL, "icons")), false);
});

test("로고 파일이 있으면 복사 · logo=1 · hasLogo true", (t) => {
  const root = makeFixture(t, {dev: devConfig()});
  fs.writeFileSync(path.join(root, "hosting", "public", "logo.png"), TINY_PNG);
  const result = runBuild(root, ["--flavor", "dev"]);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(
    lastLine(result.stdout),
    `BUILD OK flavor=dev project=your-project-dev logo=1 out=${OUT_REL}`,
  );
  assert.equal(readKitConfig(root).hasLogo, true);
  assert.deepEqual(fs.readFileSync(path.join(root, OUT_REL, "logo.png")), TINY_PNG);
});

test("자리표시자 치환 · noscript 3 locale", (t) => {
  const root = makeFixture(t, {dev: devConfig()});
  assert.equal(runBuild(root, ["--flavor", "dev"]).status, 0);
  const html = readIndex(root);
  assert.equal(html.includes("__KIT_CONFIG__"), false);
  assert.equal(html.includes("__KIT_NOSCRIPT__"), false);
  const noscript = html.match(/<noscript>([\s\S]*?)<\/noscript>/);
  assert.ok(noscript);
  assert.deepEqual(noscript[1].match(/<p>[^<]*<\/p>/g), [
    `<p>${COPY.en["page.noscript"]}</p>`,
    `<p>${COPY.ko["page.noscript"]}</p>`,
    `<p>${COPY.ja["page.noscript"]}</p>`,
  ]);
});

test("이전 산출물은 지우고 다시 만든다", (t) => {
  const root = makeFixture(t, {dev: devConfig()});
  const stale = path.join(root, OUT_REL, "stale.txt");
  fs.mkdirSync(path.dirname(stale), {recursive: true});
  fs.writeFileSync(stale, "old");
  assert.equal(runBuild(root, ["--flavor", "dev"]).status, 0);
  assert.equal(fs.existsSync(stale), false);
});

test("--project — 일치하는 config 1개로 빌드", (t) => {
  const root = makeFixture(t, {
    dev: devConfig(),
    stg: devConfig({flavor: "stg", firebaseProjectId: "your-project-stg"}),
  });
  const dev = runBuild(root, ["--project", "your-project-dev"]);
  assert.equal(dev.status, 0, dev.stderr);
  assert.equal(
    lastLine(dev.stdout),
    `BUILD OK flavor=dev project=your-project-dev logo=0 out=${OUT_REL}`,
  );
  const stg = runBuild(root, ["--project", "your-project-stg"]);
  assert.equal(stg.status, 0, stg.stderr);
  assert.equal(
    lastLine(stg.stdout),
    `BUILD OK flavor=stg project=your-project-stg logo=0 out=${OUT_REL}`,
  );
  assert.equal(readKitConfig(root).authDomain, "your-project-stg.firebaseapp.com");
});

test("--project — 일치 0개 · 2개 이상이면 FAIL", (t) => {
  const root = makeFixture(t, {
    dev: devConfig(),
    stg: devConfig({flavor: "stg"}),
  });
  const none = runBuild(root, ["--project", "other-project"]);
  assert.equal(none.status, 1);
  assert.match(none.stderr, /^FAIL: /m);
  const twice = runBuild(root, ["--project", "your-project-dev"]);
  assert.equal(twice.status, 1);
  assert.match(twice.stderr, /^FAIL: /m);
});

test("appName 이 비면 FAIL", (t) => {
  for (const appName of ["", "   "]) {
    const root = makeFixture(t, {dev: devConfig({appName})});
    const result = runBuild(root, ["--flavor", "dev"]);
    assert.equal(result.status, 1, JSON.stringify(appName));
    assert.match(result.stderr, /^FAIL: /m);
  }
  const missing = devConfig();
  delete missing.appName;
  const root = makeFixture(t, {dev: missing});
  assert.equal(runBuild(root, ["--flavor", "dev"]).status, 1);
});

test("프로젝트 ID 형식이 틀리면 FAIL", (t) => {
  for (const id of ["Bad_ID", "-starts-with-dash", "", "1abc"]) {
    const root = makeFixture(t, {dev: devConfig({firebaseProjectId: id})});
    const result = runBuild(root, ["--flavor", "dev"]);
    assert.equal(result.status, 1, id);
    assert.match(result.stderr, /^FAIL: /m);
  }
  const root = makeFixture(t, {dev: devConfig()});
  const arg = runBuild(root, ["--project", "Bad_ID"]);
  assert.equal(arg.status, 1);
  assert.match(arg.stderr, /^FAIL: /m);
});

test("brandColor 무효 → warn 1줄 + 기본 색 · 키 없음 → 조용히 기본 색", (t) => {
  const invalid = makeFixture(t, {dev: devConfig({brandColor: "blue"})});
  const result = runBuild(invalid, ["--flavor", "dev"]);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stderr.split("\n").filter((l) => l.startsWith("warn: ")).length, 1);
  assert.equal(readKitConfig(invalid).brandColor, "#673AB7");

  const noKey = devConfig();
  delete noKey.brandColor;
  const missing = makeFixture(t, {dev: noKey});
  const quiet = runBuild(missing, ["--flavor", "dev"]);
  assert.equal(quiet.status, 0, quiet.stderr);
  assert.equal(quiet.stderr, "");
  assert.equal(readKitConfig(missing).brandColor, "#673AB7");

  const yellow = makeFixture(t, {dev: devConfig({brandColor: "#FFEB3B"})});
  assert.equal(runBuild(yellow, ["--flavor", "dev"]).status, 0);
  assert.equal(readKitConfig(yellow).brandColor, "#FFEB3B");
  assert.equal(readKitConfig(yellow).onBrandColor, "#000000");
});

test("appName 의 </script> 는 주입 JSON 을 깨지 못한다", (t) => {
  const appName = "Kit</script><b>";
  const root = makeFixture(t, {dev: devConfig({appName})});
  assert.equal(runBuild(root, ["--flavor", "dev"]).status, 0);
  const html = readIndex(root);
  assert.equal(html.includes("</script><b>"), false);
  assert.ok(html.includes("</script"));
  assert.equal(readKitConfig(root).appName, appName);
});

test("다른 config 키 값은 산출물 · 출력에 0건", (t) => {
  const root = makeFixture(t, {dev: devConfig()});
  const result = runBuild(root, ["--flavor", "dev"]);
  assert.equal(result.status, 0);
  const outputs = [result.stdout, result.stderr];
  for (const file of fs.readdirSync(path.join(root, OUT_REL), {recursive: true})) {
    const full = path.join(root, OUT_REL, file);
    if (fs.statSync(full).isFile()) outputs.push(fs.readFileSync(full, "utf8"));
  }
  for (const text of outputs) {
    assert.equal(text.includes(SECRET), false);
  }
});

test("firebaseWebApiKey 가 없거나 자리표시 값이면 FAIL · 값은 출력 0 · 산출물 0", (t) => {
  const placeholder = "YOUR_FIREBASE_WEB_API_KEY_HERE";
  const cases = [
    ["키 없음", undefined],
    ["빈 값", ""],
    ["자리표시 값", placeholder],
    ["문자열 아님", 12345],
    ["앞뒤 공백", ` ${FAKE_WEB_API_KEY}`],
  ];
  for (const [label, value] of cases) {
    const config = devConfig({firebaseWebApiKey: value});
    if (value === undefined) delete config.firebaseWebApiKey;
    const root = makeFixture(t, {dev: config});
    const result = runBuild(root, ["--flavor", "dev"]);
    assert.equal(result.status, 1, label);
    const failLines = result.stderr.split("\n").filter((l) => l.startsWith("FAIL: "));
    assert.equal(failLines.length, 1, label);
    assert.ok(failLines[0].includes("firebaseWebApiKey"), label);
    assert.ok(failLines[0].includes("웹 API 키"), label);
    assert.equal(result.stderr.includes(placeholder), false, label);
    assert.equal(result.stdout, "", label);
    assert.equal(fs.existsSync(path.join(root, OUT_REL)), false, label);
  }
});

test("--project 빌드도 고른 config 의 firebaseWebApiKey 를 넣는다", (t) => {
  const stgKey = "AIzaTestOnly-FakeStgWebApiKey_00000000";
  const root = makeFixture(t, {
    dev: devConfig(),
    stg: devConfig({
      flavor: "stg",
      firebaseProjectId: "your-project-stg",
      firebaseWebApiKey: stgKey,
    }),
  });
  assert.equal(runBuild(root, ["--project", "your-project-stg"]).status, 0);
  assert.equal(readKitConfig(root).apiKey, stgKey);
});

test("필수 파일이 없으면 FAIL", (t) => {
  for (const file of ["state.mjs", "page.js", "page.css", "icons/check.svg"]) {
    const root = makeFixture(t, {dev: devConfig()});
    fs.rmSync(path.join(root, "hosting", "public", file), {force: true});
    const result = runBuild(root, ["--flavor", "dev"]);
    assert.equal(result.status, 1, file);
    assert.ok(
      result.stderr.split("\n").includes(`FAIL: hosting/public/${file} 없음`),
      result.stderr,
    );
    assert.equal(fs.existsSync(path.join(root, OUT_REL)), false, file);
  }
});

/** 행 주석(`//` 로 시작하는 줄)을 뺀 소스 줄. */
function codeLines(file) {
  return fs
    .readFileSync(path.join(REPO, "hosting", "public", file), "utf8")
    .split("\n")
    .filter((line) => !line.trimStart().startsWith("//"));
}

test("page.js 소스 계약 — continueUrl 0 · innerHTML 1곳 · SDK 판 고정 동적 import", () => {
  const lines = codeLines("page.js");
  assert.equal(lines.filter((l) => l.includes("continueUrl")).length, 0);
  assert.equal(lines.filter((l) => l.includes("innerHTML")).length, 1);
  const source = lines.join("\n");
  assert.equal(source.split("firebasejs/12.19.0/firebase-app.js").length - 1, 1);
  assert.equal(source.split("firebasejs/12.19.0/firebase-auth.js").length - 1, 1);
  assert.ok(source.split("import(").length - 1 >= 2);
  assert.match(source, /from "\.\/state\.mjs"/);
  // 정적 import 로 CDN 을 부르면 로드 실패를 연결 실패 상태로 보일 수 없다.
  assert.equal(/^import .* from "https:/m.test(source), false);
});

// 쿼리 독립성 보장 — 링크 쿼리의 apiKey 가 무엇이든 SDK 초기화 옵션은 빌드가 주입한
// 설정에서만 나온다. page.js 가 쿼리에서 꺼내는 키는 lang · oobCode 둘뿐이다.
test("page.js 소스 계약 — 링크 쿼리 apiKey 와 무관하게 주입 키로만 초기화 · 쿼리 키는 lang · oobCode 뿐", () => {
  const source = codeLines("page.js").join("\n");
  // 쿼리에서 apiKey 를 꺼내는 코드 0 — 링크 모양 확인은 state.mjs initialState 가 한다.
  assert.equal(/get\(\s*["']apiKey["']\s*\)/.test(source), false);
  // query.get( 호출은 모두 문자열 리터럴 키이고, 그 키 집합은 정확히 lang · oobCode 다.
  const queryKeys = [...source.matchAll(/query\.get\(\s*["']([^"']+)["']\s*\)/g)]
    .map((m) => m[1])
    .sort();
  assert.equal(source.split("query.get(").length - 1, queryKeys.length);
  assert.deepEqual(queryKeys, ["lang", "oobCode"]);
  assert.equal(source.split("initializeApp(").length - 1, 1);
  assert.match(source, /initializeApp\(options\)/);
  assert.match(source, /const options = firebaseOptions\(config\);/);
});

test("page.css 소스 계약 — 720px 미디어 쿼리 1개 · 다크 · 움직임 줄이기 · 촬영 스위치 0", () => {
  const css = fs.readFileSync(path.join(REPO, "hosting", "public", "page.css"), "utf8");
  assert.equal(css.split("@media (min-width: 720px)").length - 1, 1);
  assert.ok(css.includes("prefers-color-scheme: dark"));
  assert.ok(css.includes("prefers-reduced-motion"));
  for (const file of ["page.css", "page.js"]) {
    const text = fs.readFileSync(path.join(REPO, "hosting", "public", file), "utf8");
    assert.equal(/data-(theme|palette|layout|chip)|frozen/.test(text), false, file);
  }
});

test("config 파일이 없으면 FAIL", (t) => {
  const root = makeFixture(t, {dev: devConfig()});
  const result = runBuild(root, ["--flavor", "prod"]);
  assert.equal(result.status, 1);
  assert.match(result.stderr, /^FAIL: /m);
});

test("잘못된 인자는 usage + exit 2", (t) => {
  const root = makeFixture(t, {dev: devConfig()});
  for (const args of [
    [],
    ["--flavor", "qa"],
    ["--flavor", "dev", "--project", "your-project-dev"],
    ["--flavor"],
    ["--unknown", "x"],
  ]) {
    const result = runBuild(root, args);
    assert.equal(result.status, 2, JSON.stringify(args));
    assert.match(result.stderr, /usage: /);
  }
});
