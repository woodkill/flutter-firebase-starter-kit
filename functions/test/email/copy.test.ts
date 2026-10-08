/**
 * 공유 문구 파일 `functions/src/email/copy.json` 키 계약 테스트
 * (Phase 17.5 — see ROADMAP.md · D-16).
 *
 * 문구 진실원은 이 파일 1개다 — 메일 렌더(`render_mail.ts`)와 결과 페이지
 * 빌드가 같은 파일을 읽는다. 앱 ARB 에는 넣지 않는다.
 *
 * 시나리오:
 *  - ko · en · ja 키 집합 동일 · 각 55키 · 접두 `page.` / `mail.`
 *  - 메일 키 14개 존재
 *  - 키마다 치환자 집합(`{appName}` · `{email}`)이 세 locale 에서 같다
 *  - 모든 값이 빈 문자열이 아니다
 *  - 문의 채널 단어 0 (킷 문구는 문의 채널을 가정하지 않는다)
 *  - 앱 ARB 에 `page.` · `mail.` 키 0
 */

import {readFileSync} from "fs";
import * as path from "path";

import copy from "../../src/email/copy.json";

/** 문구 파일 최상위 locale (정렬). */
const LOCALES = ["en", "ja", "ko"] as const;

/** locale 1개의 키 수. */
const KEY_COUNT = 55;

/** 메일 렌더가 읽는 키 (subject 포함). */
const MAIL_KEYS = [
  "mail.verifyEmail.subject",
  "mail.verifyEmail.preheader",
  "mail.verifyEmail.heading",
  "mail.verifyEmail.body",
  "mail.verifyEmail.button",
  "mail.verifyEmail.ignore",
  "mail.resetPassword.subject",
  "mail.resetPassword.preheader",
  "mail.resetPassword.heading",
  "mail.resetPassword.body",
  "mail.resetPassword.button",
  "mail.resetPassword.ignore",
  "mail.fallback",
  "mail.footer",
];

/**
 * 문의 채널 단어 — 이 파일 자체가 검사에 걸리지 않도록 조각을 잇는다.
 */
const CONTACT_CHANNEL_WORDS = [
  ["고객", "센터"].join(""),
  ["관리", "자"].join(""),
  ["문", "의"].join(""),
  ["sup", "port"].join(""),
  ["サポ", "ート"].join(""),
  ["問い", "合わせ"].join(""),
];

/** 문구 파일 (locale → 키 → 문구). */
const COPY: Record<string, Record<string, string>> = copy;

/**
 * 문구 1개의 치환자 집합을 정렬해 돌려준다.
 *
 * @param {string} value 문구.
 * @return {string[]} `{name}` 치환자 목록 (정렬 · 중복 제거).
 */
function placeholdersOf(value: string): string[] {
  const found = value.match(/\{[A-Za-z]+\}/g) ?? [];
  return Array.from(new Set(found)).sort();
}

describe("copy.json 키 계약", () => {
  it("최상위 locale 은 ko · en · ja 3개다", () => {
    expect(Object.keys(COPY).sort()).toEqual([...LOCALES]);
  });

  it("세 locale 의 키 집합이 같고 각 55키다", () => {
    const koKeys = Object.keys(COPY.ko).sort();

    expect(koKeys).toHaveLength(KEY_COUNT);
    for (const locale of LOCALES) {
      expect(Object.keys(COPY[locale]).sort()).toEqual(koKeys);
    }
  });

  it("모든 키는 page. 또는 mail. 로 시작한다", () => {
    const stray = Object.keys(COPY.ko).filter(
      (key) => !key.startsWith("page.") && !key.startsWith("mail."),
    );

    expect(stray).toEqual([]);
  });

  it("메일 렌더가 읽는 키 14개가 있다", () => {
    for (const key of MAIL_KEYS) {
      expect(Object.keys(COPY.ko)).toContain(key);
    }
  });

  it("키마다 치환자 집합이 세 locale 에서 같다", () => {
    for (const key of Object.keys(COPY.ko)) {
      const expected = placeholdersOf(COPY.ko[key]);
      for (const locale of LOCALES) {
        expect({key, locale, found: placeholdersOf(COPY[locale][key])})
          .toEqual({key, locale, found: expected});
      }
    }
  });

  it("치환자는 {appName} · {email} 만 쓴다", () => {
    for (const locale of LOCALES) {
      for (const value of Object.values(COPY[locale])) {
        for (const placeholder of placeholdersOf(value)) {
          expect(["{appName}", "{email}"]).toContain(placeholder);
        }
      }
    }
  });

  it("모든 값은 빈 문자열이 아니다", () => {
    for (const locale of LOCALES) {
      for (const [key, value] of Object.entries(COPY[locale])) {
        expect({key, empty: value.trim() === ""}).toEqual({key, empty: false});
      }
    }
  });

  it("문의 채널 단어가 0 이다", () => {
    for (const locale of LOCALES) {
      for (const value of Object.values(COPY[locale])) {
        const lower = value.toLowerCase();
        for (const word of CONTACT_CHANNEL_WORDS) {
          expect(lower).not.toContain(word);
        }
      }
    }
  });
});

describe("앱 ARB 와 분리 (D-16)", () => {
  it("lib/l10n/*.arb 에 page. · mail. 키가 0 이다", () => {
    const l10nDir = path.join(__dirname, "..", "..", "..", "lib", "l10n");
    for (const locale of LOCALES) {
      const arb: unknown = JSON.parse(
        readFileSync(path.join(l10nDir, `app_${locale}.arb`), "utf8"),
      );
      const keys = Object.keys(arb as Record<string, unknown>);
      const leaked = keys.filter(
        (key) => key.startsWith("page.") || key.startsWith("mail."),
      );

      expect(leaked).toEqual([]);
    }
  });
});
