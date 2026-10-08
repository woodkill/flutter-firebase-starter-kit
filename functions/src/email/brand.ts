// Phase 17.5 — see ROADMAP.md (D-05 · D-06) — 메일 브랜드 값(앱 이름 · 색 · 로고).
//
// 서버 브랜드 값은 함수 런타임 env 에서만 읽는다 — 클라이언트 입력값을 메일에
// 넣지 않는다(17 D-26). env 값은 배포 스크립트가 `config/<flavor>.json` 에서
// `functions/.env.<projectId>` 로 쓴다(`.env.*` 는 root `.gitignore` 대상).
//
// brandColor 판정 · on-accent 규칙은 결과 페이지 빌드 · 앱 테마와 같아야 한다
// (UI-SPEC §Color). 세 구현의 일치는 공유 표 `hosting/test/shared_rules.json`
// 의 `brandColor` · `onAccent` 행으로 고정한다.

import {defineString} from "firebase-functions/params";
import type {StringParam} from "firebase-functions/params";

/** brandColor 가 없거나 형식이 틀릴 때 쓰는 색 (앱 `Colors.deepPurple` 과 같다). */
export const DEFAULT_BRAND_COLOR = "#673AB7";

/** 유효한 brandColor 형식 — `#RRGGBB`(대소문자 무관)만. 앞뒤 공백도 거부한다. */
const BRAND_COLOR_PATTERN = /^#[0-9A-Fa-f]{6}$/;

/** 흰 글자를 쓰는 최소 대비 (WCAG 2.x AA 본문). */
const MIN_WHITE_CONTRAST = 4.5;

/** 메일 HTML 속성에 그대로 넣을 수 없는 문자 (공백 · 따옴표 · 꺾쇠 · 역슬래시). */
const UNSAFE_URL_CHARS = /[\s"'<>`\\]/;

/** 메일 렌더에 쓰는 브랜드 값 묶음. */
export type MailBrand = {
  /** 앱 이름 — subject · 헤더 · 꼬리말 · 로고 alt. 빈 값이면 렌더하지 않는다. */
  appName: string;
  /** CTA 버튼 면 색 (`#RRGGBB`). */
  brandColor: string;
  /** CTA 버튼 글자 색 — [onAccentColor] 결과. */
  onBrandColor: "#FFFFFF" | "#000000";
  /** 로고 절대 URL (`https://`) — 빈 문자열이면 앱 이름 텍스트 헤더. */
  logoUrl: string;
};

/**
 * brandColor 원시값을 정규화한다 (D-06).
 *
 * `^#[0-9A-Fa-f]{6}$` 를 그대로 통과한 값만 쓰고(대소문자 보존), 그 밖
 * (없음 · 빈 값 · `#` 없음 · 길이 다름 · 앞뒤 공백)은 [DEFAULT_BRAND_COLOR] 다.
 *
 * @param {unknown} raw env 또는 config 의 brandColor 값.
 * @return {string} `#RRGGBB` 색.
 */
export function normalizeBrandColor(raw: unknown): string {
  if (typeof raw !== "string" || !BRAND_COLOR_PATTERN.test(raw)) {
    return DEFAULT_BRAND_COLOR;
  }
  return raw;
}

/**
 * sRGB 채널 값(0~255)을 선형 값으로 바꾼다 (WCAG 2.x 상대 휘도 정의).
 *
 * @param {number} channel 0~255 채널 값.
 * @return {number} 0~1 선형 값.
 */
function linearize(channel: number): number {
  const v = channel / 255;
  return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
}

/**
 * accent 면 위 글자 색을 고른다 (UI-SPEC §Color on-accent 규칙).
 *
 * 색을 [normalizeBrandColor] 로 먼저 정규화한 뒤 WCAG 상대 휘도 L 을 구해
 * 흰색 대비 `1.05 / (L + 0.05)` 가 4.5 이상이면 흰색, 아니면 검정이다
 * (흰색이 4.5 미만이면 검정 대비는 4.67 이상).
 *
 * @param {string} hex `#RRGGBB` 색.
 * @return {string} 글자 색 — `#FFFFFF` 또는 `#000000`.
 */
export function onAccentColor(hex: string): "#FFFFFF" | "#000000" {
  const color = normalizeBrandColor(hex);
  const r = linearize(parseInt(color.slice(1, 3), 16));
  const g = linearize(parseInt(color.slice(3, 5), 16));
  const b = linearize(parseInt(color.slice(5, 7), 16));
  const luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  const whiteContrast = 1.05 / (luminance + 0.05);
  return whiteContrast >= MIN_WHITE_CONTRAST ? "#FFFFFF" : "#000000";
}

/**
 * 메일 HTML 속성(`href` · `src`)에 escape 없이 넣어도 되는 절대 URL 인지 판정한다.
 *
 * 링크 · 로고 URL 은 Handlebars 가 `=` 를 `&#x3D;` 로 바꾸지 않도록
 * triple-stash 로 넣는다(Pitfall 6). 그래서 속성 밖으로 새는 문자(공백 ·
 * 따옴표 · 꺾쇠 · 역슬래시)가 없고 허용 scheme 으로 파싱되는 값만 받는다.
 *
 * @param {string} raw 검사할 URL 문자열.
 * @param {string[]} protocols 허용 scheme (예: `["https:"]`).
 * @return {boolean} 넣어도 되면 true.
 */
export function isEmbeddableUrl(
  raw: string,
  protocols: readonly string[],
): boolean {
  if (raw === "" || UNSAFE_URL_CHARS.test(raw)) return false;
  try {
    return protocols.includes(new URL(raw).protocol);
  } catch {
    // URL 파싱 실패 = 형식이 틀린 값.
    return false;
  }
}

/** env 브랜드 param 3종. */
type MailBrandParams = {
  appName: StringParam;
  brandColor: StringParam;
  logoUrl: StringParam;
};

let mailBrandParams: MailBrandParams | undefined;

/**
 * 브랜드 env param 3종을 돌려준다 (D-05 · D-06).
 *
 * **선언 시점:** 공식 예제처럼 모듈 스코프 상수로 두지 않고 첫 호출 때 한 번
 * 선언한다(`send_test_push.ts` 와 같은 lazy 패턴). `src/index.ts` 전체를
 * import 하는 기존 jest suite 들이 `firebase-functions/params` 를
 * `defineSecret` 만 있는 mock 으로 바꿔 두어, 모듈 로드 시점 `defineString`
 * 호출이 그 suite 들을 import 단계에서 깨뜨린다. 값 해석(`process.env` ·
 * 없으면 기본 `""`)은 같다.
 *
 * @return {MailBrandParams} 선언된 param (같은 인스턴스를 재사용한다).
 */
function brandParams(): MailBrandParams {
  if (mailBrandParams === undefined) {
    mailBrandParams = {
      appName: defineString("EMAIL_APP_NAME", {default: ""}),
      brandColor: defineString("EMAIL_BRAND_COLOR", {default: ""}),
      logoUrl: defineString("EMAIL_LOGO_URL", {default: ""}),
    };
  }
  return mailBrandParams;
}

/**
 * 함수 런타임 env 에서 메일 브랜드 값을 읽는다 (D-05 · D-06).
 *
 * handler 안에서만 부른다(배포 시점 평가 금지). `EMAIL_APP_NAME` 이 trim 뒤
 * 빈 값이면 `null` 이다(메일 헤더 · subject 가 깨지므로 호출자가 렌더를
 * 멈춘다). `EMAIL_BRAND_COLOR` 는 [normalizeBrandColor] 로 정규화하고,
 * `EMAIL_LOGO_URL` 은 `https://` 로 시작하는 안전한 절대 URL 일 때만 쓰며
 * 그 밖은 빈 문자열(앱 이름 텍스트 헤더)이다.
 *
 * @return {MailBrand | null} 브랜드 값 또는 앱 이름 미설정 시 null.
 */
export function readMailBrand(): MailBrand | null {
  const params = brandParams();
  const appName = params.appName.value().trim();
  if (appName === "") return null;
  const brandColor = normalizeBrandColor(params.brandColor.value());
  const rawLogoUrl = params.logoUrl.value();
  const logoUrl =
    rawLogoUrl.startsWith("https://") &&
    isEmbeddableUrl(rawLogoUrl, ["https:"]) ?
      rawLogoUrl :
      "";
  return {
    appName,
    brandColor,
    onBrandColor: onAccentColor(brandColor),
    logoUrl,
  };
}
