#!/usr/bin/env node
// Phase 17.5 — see ROADMAP.md (D-03 · D-05 · D-16) — 인증 결과 페이지 주입 빌드.
//
// 사용법:
//   node hosting/build.mjs --flavor <dev|stg|prod> [--root <dir>] [--out <dir>]
//   node hosting/build.mjs --project <projectId>   [--root <dir>] [--out <dir>]
//   --project 는 firebase.json 의 hosting predeploy 가 쓴다 — config/{dev,stg,prod}.json
//   가운데 firebaseProjectId 가 같은 파일 1개를 고른다.
//
// 출력 계약:
//   성공 — 마지막 줄 `BUILD OK flavor=<f> project=<p> logo=<0|1> out=<root 기준 경로>` · exit 0
//   brandColor 형식 오류 — stderr `warn: …` 1줄 뒤 기본 색으로 계속
//   실패 — stderr `FAIL: …` · exit 1 / 인자 오류 — stderr usage · exit 2
//
// 안전 계약:
//   - config 에서 읽는 키는 firebaseProjectId · appName · brandColor ·
//     firebaseWebApiKey 넷뿐이다. 다른 키(클라이언트 ID · 시크릿 등) 값은
//     산출물 · 출력에 넣지 않는다.
//   - firebaseWebApiKey 는 페이지가 Firebase 를 초기화하는 이 프로젝트의 Web API
//     키다(공개 값 — 산출물에 넣는다). 페이지는 링크 쿼리의 apiKey 를 쓰지 않는다.
//     키가 없거나 자리표시 값이면 FAIL — 값은 출력하지 않는다.
//   - 문구는 functions/src/email/copy.json 의 `page.*` 키만 넣는다(메일 문구 제외).
//   - 주입 JSON 의 `<` 는 `<` 로 바꾼다 — 값에 든 `</script>` 가 블록을 닫지 못한다.
//   - 필수 페이지 파일이 하나라도 없으면 빌드하지 않는다(깨진 페이지 배포 방지).
//   - 산출 디렉터리는 매번 지우고 다시 만든다 — 저장소 root · hosting/ 안은 거부한다.

import fs from "node:fs";
import path from "node:path";
import {fileURLToPath} from "node:url";

import {normalizeBrandColor, onAccentColor} from "./public/state.mjs";

const FLAVORS = ["dev", "stg", "prod"];
const LOCALES = ["ko", "en", "ja"];
/** noscript 는 언어 판정 전에 보이므로 3 locale 을 이 순서로 모두 넣는다. */
const NOSCRIPT_ORDER = ["en", "ko", "ja"];
const PROJECT_ID_PATTERN = /^[a-z][a-z0-9-]*$/;
/**
 * Web API 키 형식 — Google API 키는 `AIza` 로 시작하고 영숫자 · `_` · `-` 만 쓴다.
 * example 파일의 자리표시 값(`YOUR_…_HERE`)은 여기서 걸린다.
 */
const WEB_API_KEY_PATTERN = /^AIza[0-9A-Za-z_-]+$/;
const CONFIG_TOKEN = "__KIT_CONFIG__";
const NOSCRIPT_TOKEN = "__KIT_NOSCRIPT__";
const LOGO_FILE = "logo.png";

/** 주입 JSON 에 인라인하는 표지 · 폼 아이콘 이름 (`icons/<이름>.svg`). */
const ICON_NAMES = [
  "check",
  "schedule",
  "link_off",
  "person_off",
  "wifi_off",
  "error",
  "lock_reset",
  "visibility",
  "visibility_off",
];

/** `hosting/public/` 에 반드시 있어야 하는 파일 — 없으면 FAIL. */
const REQUIRED_FILES = [
  "index.html",
  "state.mjs",
  "page.css",
  "page.js",
  ...ICON_NAMES.map((name) => `icons/${name}.svg`),
];

/** 산출물에 그대로 복사하는 파일 (index.html 은 치환해서 쓰고, 아이콘은 인라인만). */
const COPIED_FILES = ["state.mjs", "page.css", "page.js"];

const USAGE =
  "usage: node hosting/build.mjs (--flavor <dev|stg|prod> | --project <projectId>) " +
  "[--root <dir>] [--out <dir>]";

/** 실패를 알리고 exit 1 로 끝낸다. */
function fail(message) {
  process.stderr.write(`FAIL: ${message}\n`);
  process.exit(1);
}

/** 인자 오류를 알리고 exit 2 로 끝낸다. */
function usage(message) {
  process.stderr.write(`${message}\n${USAGE}\n`);
  process.exit(2);
}

/**
 * 명령줄 인자를 읽는다. `--flavor` · `--project` 가운데 정확히 하나가 필요하다.
 *
 * @param {string[]} argv `process.argv.slice(2)`.
 * @returns {{flavor?: string, project?: string, root: string, out?: string}} 인자.
 */
function parseArgs(argv) {
  const known = new Set(["--flavor", "--project", "--root", "--out"]);
  const args = {};
  for (let i = 0; i < argv.length; i += 2) {
    const flag = argv[i];
    const value = argv[i + 1];
    if (!known.has(flag)) usage(`알 수 없는 인자: ${flag}`);
    if (value === undefined || value.startsWith("--")) usage(`${flag} 에 값이 없다`);
    const key = flag.slice(2);
    if (key in args) usage(`${flag} 를 두 번 줬다`);
    args[key] = value;
  }
  if ((args.flavor === undefined) === (args.project === undefined)) {
    usage("--flavor 와 --project 가운데 하나만 준다");
  }
  if (args.flavor !== undefined && !FLAVORS.includes(args.flavor)) {
    usage("--flavor 는 dev · stg · prod 가운데 하나다");
  }
  const scriptRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
  args.root = path.resolve(args.root ?? scriptRoot);
  return args;
}

/** config 파일 1개를 JSON 으로 읽는다 (객체가 아니면 FAIL). */
function readConfig(root, flavor) {
  const file = path.join(root, "config", `${flavor}.json`);
  if (!fs.existsSync(file)) {
    fail(`config/${flavor}.json 이 없다 — cp config/${flavor}.example.json config/${flavor}.json 뒤 값을 채운다`);
  }
  let parsed;
  try {
    parsed = JSON.parse(fs.readFileSync(file, "utf8"));
  } catch {
    fail(`config/${flavor}.json 을 JSON 으로 읽지 못했다`);
  }
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
    fail(`config/${flavor}.json 이 JSON 객체가 아니다`);
  }
  return parsed;
}

/**
 * 빌드할 flavor 와 config 를 고른다. `--project` 면 firebaseProjectId 가 같은
 * config 가 정확히 1개여야 한다.
 */
function selectConfig(args) {
  if (args.flavor !== undefined) {
    return {flavor: args.flavor, config: readConfig(args.root, args.flavor)};
  }
  if (!PROJECT_ID_PATTERN.test(args.project)) {
    fail("--project 형식이 잘못됐다 (소문자로 시작 · 소문자 · 숫자 · - 만)");
  }
  const matches = FLAVORS.filter((flavor) =>
    fs.existsSync(path.join(args.root, "config", `${flavor}.json`)),
  )
    .map((flavor) => ({flavor, config: readConfig(args.root, flavor)}))
    .filter(({config}) => config.firebaseProjectId === args.project);
  if (matches.length !== 1) {
    fail(
      `firebaseProjectId 가 ${args.project} 인 config 가 ${matches.length}개다 — ` +
        "config/{dev,stg,prod}.json 가운데 정확히 1개여야 한다",
    );
  }
  return matches[0];
}

/** 안전 계약의 브랜드 세 키만 꺼내 검증한다. */
function readBrand(flavor, config) {
  const projectId = config.firebaseProjectId;
  if (typeof projectId !== "string" || !PROJECT_ID_PATTERN.test(projectId)) {
    fail(`config/${flavor}.json 의 firebaseProjectId 형식이 잘못됐다 (소문자로 시작 · 소문자 · 숫자 · - 만)`);
  }
  const appName = typeof config.appName === "string" ? config.appName.trim() : "";
  if (appName === "") fail(`config/${flavor}.json 의 appName 이 비어 있다`);

  const rawColor = config.brandColor;
  const brandColor = normalizeBrandColor(rawColor);
  // 키가 없거나 빈 값이면 기본 색이 정상 동작이다 — 값이 있는데 형식이 틀릴 때만 알린다.
  if (rawColor !== undefined && rawColor !== "" && brandColor !== rawColor) {
    process.stderr.write(`warn: brandColor 형식이 아니라 ${brandColor} 로 빌드한다\n`);
  }
  return {projectId, appName, brandColor};
}

/**
 * 페이지가 Firebase 를 초기화할 Web API 키를 꺼낸다. 없거나 형식이 아니면 FAIL —
 * 결과 페이지를 빌드할 때(`kit` 발송 모드)만 필요한 키다. 값은 출력하지 않는다.
 */
function readWebApiKey(flavor, config) {
  const apiKey = config.firebaseWebApiKey;
  if (typeof apiKey !== "string" || !WEB_API_KEY_PATTERN.test(apiKey)) {
    fail(
      `config/${flavor}.json 의 firebaseWebApiKey 가 비었거나 자리표시 값이다 — ` +
        "Firebase Console → 프로젝트 설정 → 일반 의 웹 API 키(AIza 로 시작)를 넣는다",
    );
  }
  return apiKey;
}

/** 문구 파일에서 locale 별 `page.*` 키만 꺼낸다. */
function readPageCopy(root) {
  const file = path.join(root, "functions", "src", "email", "copy.json");
  if (!fs.existsSync(file)) fail("functions/src/email/copy.json 이 없다");
  let all;
  try {
    all = JSON.parse(fs.readFileSync(file, "utf8"));
  } catch {
    fail("functions/src/email/copy.json 을 JSON 으로 읽지 못했다");
  }
  const copy = {};
  for (const locale of LOCALES) {
    const entries = Object.entries(all?.[locale] ?? {}).filter(
      ([key, value]) => key.startsWith("page.") && typeof value === "string",
    );
    if (entries.length === 0) fail(`copy.json 에 ${locale} 의 page.* 문구가 없다`);
    copy[locale] = Object.fromEntries(entries);
  }
  return copy;
}

/** 아이콘 SVG 를 읽어 크기 속성(24)을 걷어낸 마크업으로 돌려준다. */
function readIcons(publicDir) {
  const icons = {};
  for (const name of ICON_NAMES) {
    const svg = fs
      .readFileSync(path.join(publicDir, "icons", `${name}.svg`), "utf8")
      .trim()
      .replace(/ (width|height)="24"/g, "");
    if (!svg.startsWith("<svg")) fail(`hosting/public/icons/${name}.svg 가 SVG 가 아니다`);
    icons[name] = svg;
  }
  return icons;
}

/** HTML 본문 텍스트용 escape. */
function escapeHtml(text) {
  return text.replace(/[&<>"']/g, (c) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  })[c]);
}

/** [template] 의 [token] 을 정확히 1회 [value] 로 바꾼다 (`$` 치환 패턴 없이). */
function replaceOnce(template, token, value) {
  const parts = template.split(token);
  if (parts.length !== 2) {
    fail(`hosting/public/index.html 에 ${token} 가 정확히 1개여야 한다 (지금 ${parts.length - 1}개)`);
  }
  return parts.join(value);
}

/** 산출 디렉터리가 지워도 되는 위치인지 확인한다. */
function assertSafeOut(root, out) {
  const rel = path.relative(out, root);
  const outContainsRoot = rel === "" || (!rel.startsWith("..") && !path.isAbsolute(rel));
  const hostingDir = path.join(root, "hosting");
  const relToHosting = path.relative(hostingDir, out);
  const insideHosting =
    relToHosting === "" || (!relToHosting.startsWith("..") && !path.isAbsolute(relToHosting));
  if (outContainsRoot || insideHosting || out === path.parse(out).root) {
    fail("--out 은 저장소 root · 그 상위 · hosting/ 안을 가리킬 수 없다");
  }
}

/** 빌드 진입점. */
function main() {
  const args = parseArgs(process.argv.slice(2));
  const {root} = args;
  const publicDir = path.join(root, "hosting", "public");
  const out = path.resolve(args.out ?? path.join(root, "build", "hosting", "public"));
  assertSafeOut(root, out);

  for (const file of REQUIRED_FILES) {
    if (!fs.existsSync(path.join(publicDir, file))) fail(`hosting/public/${file} 없음`);
  }

  const {flavor, config} = selectConfig(args);
  const {projectId, appName, brandColor} = readBrand(flavor, config);
  const apiKey = readWebApiKey(flavor, config);
  const copy = readPageCopy(root);
  const logoPath = path.join(publicDir, LOGO_FILE);
  const hasLogo = fs.existsSync(logoPath) && fs.statSync(logoPath).isFile();

  const kitConfig = {
    appName,
    brandColor,
    onBrandColor: onAccentColor(brandColor),
    hasLogo,
    apiKey,
    authDomain: `${projectId}.firebaseapp.com`,
    copy,
    icons: readIcons(publicDir),
  };
  const configJson = JSON.stringify(kitConfig).replace(/</g, "\\u003c");
  const noscript = NOSCRIPT_ORDER.map(
    (locale) => `<p>${escapeHtml(copy[locale]["page.noscript"] ?? "")}</p>`,
  ).join("\n");

  const template = fs.readFileSync(path.join(publicDir, "index.html"), "utf8");
  const html = replaceOnce(
    replaceOnce(template, CONFIG_TOKEN, configJson),
    NOSCRIPT_TOKEN,
    noscript,
  );

  fs.rmSync(out, {recursive: true, force: true});
  fs.mkdirSync(out, {recursive: true});
  fs.writeFileSync(path.join(out, "index.html"), html);
  for (const file of COPIED_FILES) {
    fs.copyFileSync(path.join(publicDir, file), path.join(out, file));
  }
  if (hasLogo) fs.copyFileSync(logoPath, path.join(out, LOGO_FILE));

  const outLabel = path.relative(root, out).split(path.sep).join("/");
  process.stdout.write(
    `BUILD OK flavor=${flavor} project=${projectId} logo=${hasLogo ? 1 : 0} out=${outLabel}\n`,
  );
}

main();
