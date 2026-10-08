/**
 * 메일 브랜드 값 · locale 판정 회귀 테스트 (Phase 17.5 — see ROADMAP.md ·
 * D-05 · D-06 · D-15).
 *
 * brandColor · lang · on-accent 판정은 결과 페이지 빌드 · 앱 테마와 같아야
 * 한다(UI-SPEC §Color · RESEARCH §R12). 판정 표는 공유 파일
 * `hosting/test/shared_rules.json` 1개이고, 페이지(mjs) · 앱(Dart) 테스트가
 * 같은 파일을 읽는다 — 표를 바꾸면 세 구현이 함께 맞아야 한다.
 *
 * 시나리오:
 *  - 공유 표 `brandColor` 행 → `normalizeBrandColor`
 *  - 공유 표 `lang` 행 → `resolveMailLocale`
 *  - 공유 표 `onAccent` 행 → `onAccentColor`
 *  - `readMailBrand` — env 조합(빈 앱 이름 → null · 잘못된 색 → 기본 ·
 *    http 로고 → 빈 값)
 *  - `readResultPageUrl` (D-22 ②) — https · 쿼리 · 해시 없음만 그대로, 빈 값 ·
 *    env 없음 · http · 쿼리 · 해시 · 따옴표 → null
 */

import {readFileSync} from "fs";
import * as path from "path";

import {
  DEFAULT_BRAND_COLOR,
  normalizeBrandColor,
  onAccentColor,
  readMailBrand,
  readResultPageUrl,
} from "../../src/email/brand";
import {resolveMailLocale} from "../../src/email/mail_locale";

// 테스트가 바꾸는 env 값 (param 이름 → 값). 없으면 기본값 "".
let mockEnv: Record<string, string> = {};
jest.mock("firebase-functions/params", () => ({
  defineString: (name: string) => ({value: () => mockEnv[name] ?? ""}),
}));

/** 공유 판정 표의 행 1개. */
type RuleRow = {input: unknown; expected: string};

/** 공유 판정 표 파일 모양. */
type SharedRules = {
  brandColor: RuleRow[];
  lang: RuleRow[];
  onAccent: RuleRow[];
};

/** `functions/test/email/` → repo root 는 3단계 위다. */
const SHARED_RULES_PATH = path.join(
  __dirname,
  "..",
  "..",
  "..",
  "hosting",
  "test",
  "shared_rules.json",
);

/**
 * 값이 공유 표 행 배열인지 판정한다.
 *
 * @param {unknown} value JSON 에서 읽은 값.
 * @return {boolean} `{input, expected: string}` 배열이면 true.
 */
function isRuleRows(value: unknown): value is RuleRow[] {
  return (
    Array.isArray(value) &&
    value.every(
      (row: unknown) =>
        typeof row === "object" &&
        row !== null &&
        "input" in row &&
        "expected" in row &&
        typeof (row as {expected: unknown}).expected === "string",
    )
  );
}

/**
 * 공유 판정 표를 읽고 모양을 확인한다.
 *
 * @return {SharedRules} 세 표.
 */
function loadSharedRules(): SharedRules {
  const parsed: unknown = JSON.parse(readFileSync(SHARED_RULES_PATH, "utf8"));
  if (typeof parsed !== "object" || parsed === null) {
    throw new Error("shared_rules.json 이 객체가 아니다");
  }
  const {brandColor, lang, onAccent} = parsed as Record<string, unknown>;
  if (!isRuleRows(brandColor) || !isRuleRows(lang) || !isRuleRows(onAccent)) {
    throw new Error("shared_rules.json 표 모양이 다르다");
  }
  return {brandColor, lang, onAccent};
}

const rules = loadSharedRules();

describe("공유 판정 표 (hosting/test/shared_rules.json)", () => {
  it("표 3종의 최소 행 수를 지킨다", () => {
    expect(rules.brandColor.length).toBeGreaterThanOrEqual(6);
    expect(rules.lang.length).toBeGreaterThanOrEqual(7);
    expect(rules.onAccent.length).toBeGreaterThanOrEqual(5);
  });

  it.each(rules.brandColor.map((row) => [row.input, row.expected]))(
    "normalizeBrandColor(%j) = %s",
    (input, expected) => {
      expect(normalizeBrandColor(input)).toBe(expected);
    },
  );

  it.each(rules.lang.map((row) => [row.input, row.expected]))(
    "resolveMailLocale(%j) = %s",
    (input, expected) => {
      expect(resolveMailLocale(input)).toBe(expected);
    },
  );

  it.each(rules.onAccent.map((row) => [row.input, row.expected]))(
    "onAccentColor(%j) = %s",
    (input, expected) => {
      expect(onAccentColor(String(input))).toBe(expected);
    },
  );
});

describe("readMailBrand", () => {
  beforeEach(() => {
    mockEnv = {
      EMAIL_APP_NAME: "Kit",
      EMAIL_BRAND_COLOR: "#3F51B5",
      EMAIL_LOGO_URL: "https://example.web.app/logo.png",
    };
  });

  it("env 3종이 유효하면 그대로 쓰고 on-accent 를 계산한다", () => {
    expect(readMailBrand()).toEqual({
      appName: "Kit",
      brandColor: "#3F51B5",
      onBrandColor: "#FFFFFF",
      logoUrl: "https://example.web.app/logo.png",
    });
  });

  it("앱 이름은 앞뒤 공백을 걷어 낸다", () => {
    mockEnv.EMAIL_APP_NAME = "  Kit  ";

    expect(readMailBrand()?.appName).toBe("Kit");
  });

  it("앱 이름이 비면 null 이다", () => {
    mockEnv.EMAIL_APP_NAME = "   ";

    expect(readMailBrand()).toBeNull();
  });

  it("앱 이름 env 가 없으면 null 이다", () => {
    delete mockEnv.EMAIL_APP_NAME;

    expect(readMailBrand()).toBeNull();
  });

  it("잘못된 색은 기본 색 · 흰 글자다", () => {
    mockEnv.EMAIL_BRAND_COLOR = "673AB7";

    const brand = readMailBrand();

    expect(brand?.brandColor).toBe(DEFAULT_BRAND_COLOR);
    expect(brand?.onBrandColor).toBe("#FFFFFF");
  });

  it("밝은 색은 검정 글자다", () => {
    mockEnv.EMAIL_BRAND_COLOR = "#FFEB3B";

    expect(readMailBrand()?.onBrandColor).toBe("#000000");
  });

  it("http 로고 URL 은 빈 값이다", () => {
    mockEnv.EMAIL_LOGO_URL = "http://example.web.app/logo.png";

    expect(readMailBrand()?.logoUrl).toBe("");
  });

  it("따옴표가 든 로고 URL 은 빈 값이다", () => {
    mockEnv.EMAIL_LOGO_URL = "https://example.web.app/a\"onerror=\"x.png";

    expect(readMailBrand()?.logoUrl).toBe("");
  });

  it("로고 env 가 없으면 빈 값이다", () => {
    delete mockEnv.EMAIL_LOGO_URL;

    expect(readMailBrand()?.logoUrl).toBe("");
  });
});

describe("readResultPageUrl (D-22)", () => {
  beforeEach(() => {
    mockEnv = {EMAIL_RESULT_PAGE_URL: "https://example.web.app/"};
  });

  it("https · 쿼리 · 해시 없는 주소는 그대로 쓴다", () => {
    expect(readResultPageUrl()).toBe("https://example.web.app/");
  });

  it("빈 값 · env 없음은 null 이다", () => {
    mockEnv.EMAIL_RESULT_PAGE_URL = "";
    expect(readResultPageUrl()).toBeNull();

    delete mockEnv.EMAIL_RESULT_PAGE_URL;
    expect(readResultPageUrl()).toBeNull();
  });

  it("http 주소는 null 이다", () => {
    mockEnv.EMAIL_RESULT_PAGE_URL = "http://example.web.app/";

    expect(readResultPageUrl()).toBeNull();
  });

  it("쿼리가 붙은 주소는 null 이다", () => {
    mockEnv.EMAIL_RESULT_PAGE_URL = "https://example.web.app/?x=1";

    expect(readResultPageUrl()).toBeNull();
  });

  it("해시가 붙은 주소는 null 이다", () => {
    mockEnv.EMAIL_RESULT_PAGE_URL = "https://example.web.app/#a";

    expect(readResultPageUrl()).toBeNull();
  });

  it("따옴표가 든 주소는 null 이다", () => {
    mockEnv.EMAIL_RESULT_PAGE_URL = "https://example.web.app/a\"onclick=\"x";

    expect(readResultPageUrl()).toBeNull();
  });
});
