// Phase 17.5 — see ROADMAP.md (D-15) — 메일 · 결과 페이지 언어 정규화.
//
// callable 이 받은 앱 로케일을 메일 문구 locale 로 정한다. 같은 규칙을 결과
// 페이지(`state.mjs normalizeLang`)와 앱 fallback(`locale_provider.dart`)이
// 쓰며, 세 구현의 판정 일치는 공유 표 `hosting/test/shared_rules.json` 의
// `lang` 행으로 고정한다.

/** 메일 · 결과 페이지 문구가 있는 locale (`copy.json` 최상위 키와 같다). */
export type MailLocale = "ko" | "en" | "ja";

/** 지원 locale 전체 목록 (스냅샷 · 키 계약 테스트가 순회한다). */
export const MAIL_LOCALES: readonly MailLocale[] = ["ko", "en", "ja"];

/** locale 이 없거나 지원 밖일 때 쓰는 언어 (앱 fallback 과 같다). */
const FALLBACK_LOCALE: MailLocale = "en";

/**
 * 원시 로케일 값을 메일 locale 로 정규화한다 (D-15).
 *
 * 문자열이 아니면 `en` 이다. 앞뒤 공백 · 대소문자를 무시하고 `ko-KR` ·
 * `ja_JP` 처럼 지역이 붙은 값은 앞부분(언어)만 본다. 지원 밖 언어 · 빈 값은
 * `en` 이다.
 *
 * @param {unknown} raw callable 요청의 `locale` 등 신뢰할 수 없는 입력.
 * @return {MailLocale} 문구를 고를 locale.
 */
export function resolveMailLocale(raw: unknown): MailLocale {
  if (typeof raw !== "string") return FALLBACK_LOCALE;
  const language = raw.trim().toLowerCase().split(/[-_]/)[0];
  const match = MAIL_LOCALES.find((locale) => locale === language);
  return match ?? FALLBACK_LOCALE;
}
