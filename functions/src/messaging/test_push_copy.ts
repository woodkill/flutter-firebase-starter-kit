// Phase 17 — see ROADMAP.md (D-31) — `sendTestPush` 서버 발송 문구.
//
// 알림 제목 · 본문은 OS 가 그리므로 앱 ARB 를 쓸 수 없다. 서버가 토큰 문서의
// `locale` 로 언어를 골라 이 상수에서 문구를 꺼낸다. 값은 17-UI-SPEC.md
// 「서버 발송 문구」 표와 verbatim 동일하다.

/** 서버 발송 문구가 있는 locale (토큰 문서 `locale` 지원 집합과 같다). */
export type TestPushLocale = "ko" | "en" | "ja";

/** 알림 1건의 제목 · 본문. */
export type TestPushCopy = {
  /** `notification.title`. */
  title: string;
  /** `notification.body`. */
  body: string;
};

/**
 * locale 별 테스트 알림 문구 (D-31).
 *
 * **ARB 와 별개다** — 앱 문구(`lib/l10n/*.arb`)를 바꿔도 이 상수는 따라
 * 바뀌지 않는다. 본문 「설정 화면을 엽니다」 는 발송 payload 의
 * `data.route = "/settings"` 와 짝이다.
 *
 * **언어 추가 (manual 커스터마이징 포인트):** 이 상수에 항목 1개를 더하고
 * `TestPushLocale` 에 코드를 넣는다. 앱이 그 locale 을 토큰 문서에 저장하도록
 * 앱 locale 지원(plan 15 `normalizeFcmLocale` · `firestore.rules` 의 fcmTokens
 * `locale` 허용 집합)도 함께 넓혀야 그 언어 기기가 새 문구를 받는다.
 */
export const TEST_PUSH_COPY: Record<TestPushLocale, TestPushCopy> = {
  ko: {
    title: "테스트 알림",
    body: "알림이 도착했습니다. 탭하면 설정 화면을 엽니다.",
  },
  en: {
    title: "Test notification",
    body: "Your notification arrived. Tap to open Settings.",
  },
  ja: {
    title: "テスト通知",
    body: "通知が届きました。タップすると設定画面を開きます。",
  },
};

/** locale 이 없거나 지원 밖일 때 쓰는 문구 언어 (D-31). */
const FALLBACK_LOCALE: TestPushLocale = "en";

/**
 * 토큰 문서의 `locale` 원시값을 문구 locale 로 정한다 (D-31).
 *
 * 문자열이 아니거나 [TEST_PUSH_COPY] 에 없는 값이면 `en` 이다. 앞뒤 공백 ·
 * 대소문자 차이는 무시한다(앱은 소문자 2자로 저장하지만 수동 편집 문서를
 * 방어한다).
 *
 * @param {unknown} raw 토큰 문서 `locale` 필드 값.
 * @return {TestPushLocale} 문구를 고를 locale.
 */
export function resolveTestPushLocale(raw: unknown): TestPushLocale {
  if (typeof raw !== "string") return FALLBACK_LOCALE;
  const normalized = raw.trim().toLowerCase();
  return Object.prototype.hasOwnProperty.call(TEST_PUSH_COPY, normalized) ?
    (normalized as TestPushLocale) :
    FALLBACK_LOCALE;
}
