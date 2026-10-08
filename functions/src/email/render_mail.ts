// Phase 17.5 — see ROADMAP.md (D-07 · D-11 · D-15 · D-16) — `kit` 모드 메일 렌더.
//
// 인증 · 재설정 메일의 subject · html · text 를 함수 코드가 만든다(D-11 —
// 확장의 `templates/` 컬렉션은 쓰지 않는다). html 은 `templates/*.hbs` 를
// Handlebars 로 렌더하고, text 는 Handlebars 없이 문자열로 잇는다.
//
// **문구는 앱 ARB 와 별개다** — 값은 `copy.json` 1개(UI-SPEC 문구 표
// verbatim)에 있고, 그 파일은 결과 페이지 빌드와 공유한다(D-16). 앱 문구
// (`lib/l10n/*.arb`)를 바꿔도 메일 문구는 따라 바뀌지 않는다 — 앱 버튼 이름
// (「인증 메일 재전송」 등)을 바꾸면 `copy.json` 의 해당 문구도 함께 고친다.
//
// **언어 추가 (매뉴얼 커스터마이징 포인트):** `copy.json` 에 locale 객체
// 1개(모든 키)를 더하고 `mail_locale.ts` 의 `MailLocale` · `MAIL_LOCALES` 와
// 아래 `FONT_STACKS` 에 같은 코드를 넣는다. 앱 · 결과 페이지의 언어 지원도
// 함께 넓혀야 그 언어 사용자가 새 문구를 받는다.

import {readFileSync} from "fs";
import * as path from "path";

import Handlebars from "handlebars";

import {isEmbeddableUrl, normalizeBrandColor, onAccentColor} from "./brand";
import type {MailBrand} from "./brand";
import copy from "./copy.json";
import type {MailLocale} from "./mail_locale";

/** 메일 종류 — Admin 액션 링크의 `mode` 값과 같다. */
export type MailKind = "verifyEmail" | "resetPassword";

/** [renderMail] 입력. */
export type RenderMailInput = {
  /** 문구 · `lang` locale (`resolveMailLocale` 결과). */
  locale: MailLocale;
  /** 받는 사람 주소 — 본문 `{email}` 자리. */
  email: string;
  /** 버튼 · 대체 링크 URL (`attachLang` 결과). */
  link: string;
  /** 서버 브랜드 값 (`readMailBrand` 결과). */
  brand: MailBrand;
};

/** 렌더 결과 — Trigger Email 확장 `mail/` 문서의 `message` 필드 모양. */
export type RenderedMail = {
  /** 제목 평문 (escape 없음). */
  subject: string;
  /** HTML 본문. */
  html: string;
  /** text 본문 (줄 끝 공백 0). */
  text: string;
};

/** 메일 종류별 템플릿 파일 이름 (`templates/` 아래). */
const TEMPLATE_FILES: Record<MailKind, string> = {
  verifyEmail: "verify_email.hbs",
  resetPassword: "reset_password.hbs",
};

/** locale 별 메일 글꼴 스택 (UI-SPEC §Typography — 웹 폰트 없음). */
const FONT_STACKS: Record<MailLocale, string> = {
  ko: "-apple-system,'Apple SD Gothic Neo',Roboto,'Noto Sans KR'," +
    "'Malgun Gothic',sans-serif",
  en: "-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif",
  ja: "-apple-system,'Hiragino Sans',Roboto,'Noto Sans JP','Yu Gothic'," +
    "Meiryo,sans-serif",
};

/** 링크로 허용하는 scheme (에뮬레이터 링크는 http). */
const LINK_PROTOCOLS: readonly string[] = ["https:", "http:"];

/** 문구 치환자 — `{appName}` · `{email}` 를 한 번에 찾는다. */
const PLACEHOLDER_PATTERN = /\{(appName|email)\}/g;

/** 공유 문구 파일 (locale → 키 → 문구). */
const COPY: Record<MailLocale, Record<string, string>> = copy;

/** 컴파일한 템플릿 캐시 — 첫 렌더 때 채운다(모듈 로드 시 파일 I/O 0). */
const compiledTemplates = new Map<MailKind, Handlebars.TemplateDelegate>();

/**
 * Admin 액션 링크에 `lang` 쿼리를 붙인다 (D-15 · RESEARCH §R1).
 *
 * Admin `generate*Link` 결과에는 언어 인자가 없으므로 결과 페이지가 메일과
 * 같은 언어로 열리도록 함수가 붙인다. 이미 `lang` 이 있으면 덮어쓴다.
 *
 * @param {string} link Admin SDK 가 만든 절대 URL.
 * @param {MailLocale} locale 메일 locale.
 * @return {string} `lang=<locale>` 이 1개 실린 URL.
 */
export function attachLang(link: string, locale: MailLocale): string {
  const url = new URL(link);
  url.searchParams.set("lang", locale);
  return url.toString();
}

/**
 * 메일 1통의 subject · html · text 를 렌더한다 (D-07 · D-11).
 *
 * html 의 문구 조각 · 앱 이름 · 주소는 조각별로 HTML escape 한 뒤 넣고,
 * 링크 · 로고 URL 은 `=` 가 `&#x3D;` 로 바뀌지 않게 escape 없이 넣는다
 * (Pitfall 6 — 그래서 속성 밖으로 새는 문자가 있는 URL 은 거부한다).
 *
 * @param {MailKind} kind 메일 종류.
 * @param {RenderMailInput} input locale · 주소 · 링크 · 브랜드 값.
 * @return {RenderedMail} 렌더 결과.
 * @throws {Error} 앱 이름이 비었거나 링크가 넣을 수 없는 URL 일 때.
 */
export function renderMail(
  kind: MailKind,
  input: RenderMailInput,
): RenderedMail {
  const {locale, email, link, brand} = input;
  const appName = brand.appName.trim();
  if (appName === "") {
    throw new Error("renderMail: brand.appName is empty");
  }
  if (!isEmbeddableUrl(link, LINK_PROTOCOLS)) {
    throw new Error("renderMail: link is not an embeddable http(s) URL");
  }
  const values = {appName, email};
  const text = (key: string): string => copyText(locale, key);
  const html = (key: string): string => htmlFragment(text(key), values);
  const brandColor = normalizeBrandColor(brand.brandColor);
  const logoUrl = isEmbeddableUrl(brand.logoUrl, ["https:"]) ?
    brand.logoUrl :
    "";

  // subject 는 평문 — 헤더 줄바꿈 주입을 막으려고 개행을 공백으로 바꾼다.
  const subject = plainFragment(text(`mail.${kind}.subject`), values)
    .replace(/[\r\n]+/g, " ");

  const rendered = compiledTemplate(kind)({
    lang: locale,
    subject: Handlebars.Utils.escapeExpression(subject),
    preheader: html(`mail.${kind}.preheader`),
    heading: html(`mail.${kind}.heading`),
    body: html(`mail.${kind}.body`),
    button: html(`mail.${kind}.button`),
    ignore: html(`mail.${kind}.ignore`),
    fallback: html("mail.fallback"),
    footer: html("mail.footer"),
    appName: Handlebars.Utils.escapeExpression(appName),
    fontFamily: FONT_STACKS[locale],
    keepAll: locale === "ko" ? "word-break:keep-all;" : "",
    brandColor,
    onBrandColor: onAccentColor(brandColor),
    logoUrl,
    link,
  });

  // text 파트 — UI-SPEC §메일 조립 규칙. `{email}` 원문 · 줄 끝 공백 0.
  const plain = [
    plainFragment(text(`mail.${kind}.heading`), values),
    plainFragment(text(`mail.${kind}.body`), values),
    link,
    plainFragment(text(`mail.${kind}.ignore`), values),
    `--\n${plainFragment(text("mail.footer"), values)}`,
  ].join("\n\n");

  return {subject, html: rendered, text: plain};
}

/**
 * 공유 문구 파일에서 문구 1개를 꺼낸다.
 *
 * @param {MailLocale} locale 문구 locale.
 * @param {string} key 문구 키 (예: `mail.verifyEmail.subject`).
 * @return {string} 치환 전 문구.
 * @throws {Error} 키가 없을 때 (copy.json 계약 위반).
 */
function copyText(locale: MailLocale, key: string): string {
  const value = COPY[locale]?.[key];
  if (typeof value !== "string") {
    throw new Error(`renderMail: copy key missing ${locale}.${key}`);
  }
  return value;
}

/**
 * 문구의 치환자를 원문 값으로 바꾼다 (subject · text 파트용).
 *
 * 치환은 한 번에 한다 — 앱 이름에 `{email}` 같은 글자가 있어도 다시 치환되지
 * 않는다.
 *
 * @param {string} raw 치환 전 문구.
 * @param {{appName: string, email: string}} values 치환 값.
 * @return {string} 치환된 평문.
 */
function plainFragment(
  raw: string,
  values: {appName: string; email: string},
): string {
  return raw.replace(PLACEHOLDER_PATTERN, (_match, name: string) =>
    name === "appName" ? values.appName : values.email,
  );
}

/**
 * 문구를 HTML escape 한 뒤 치환자를 escape 된 값으로 바꾼다 (html 파트용).
 *
 * `{email}` 은 긴 주소가 넘치지 않도록 `word-break:break-all` span 으로
 * 감싼다(UI-SPEC §(M)). 결과는 템플릿에 escape 없이 넣는다.
 *
 * @param {string} raw 치환 전 문구.
 * @param {{appName: string, email: string}} values 치환 값 (원문).
 * @return {string} 안전한 HTML 조각.
 */
function htmlFragment(
  raw: string,
  values: {appName: string; email: string},
): string {
  const escape = Handlebars.Utils.escapeExpression;
  return escape(raw).replace(PLACEHOLDER_PATTERN, (_match, name: string) =>
    name === "appName" ?
      escape(values.appName) :
      `<span style="word-break:break-all;">${escape(values.email)}</span>`,
  );
}

/**
 * 메일 종류의 템플릿을 컴파일해 돌려준다 (첫 호출 때 1회 · 이후 캐시).
 *
 * 경로는 `__dirname` 기준이라 테스트(`src/`)와 배포본(`lib/` — build 가
 * `templates/` 를 복사한다, Pitfall 7)이 같은 상대 경로를 읽는다.
 *
 * @param {MailKind} kind 메일 종류.
 * @return {Handlebars.TemplateDelegate} 컴파일된 템플릿.
 */
function compiledTemplate(kind: MailKind): Handlebars.TemplateDelegate {
  const cached = compiledTemplates.get(kind);
  if (cached !== undefined) return cached;
  const source = readFileSync(
    path.join(__dirname, "templates", TEMPLATE_FILES[kind]),
    "utf8",
  );
  const template = Handlebars.compile(source, {strict: true});
  compiledTemplates.set(kind, template);
  return template;
}
