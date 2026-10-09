// Phase 17.5 — see ROADMAP.md (D-06 · D-17 · D-18) — 결과 페이지 상태 판정 순수 모듈.
//
// DOM · 네트워크에 닿지 않는 판정만 둔다 — 브라우저(page.js) · 빌드(build.mjs) ·
// node:test 가 같은 파일을 import 한다.
//
// brandColor · lang · on-accent 판정은 메일 렌더 · 앱 테마와 같아야 한다.
// 세 구현의 일치는 공유 표 `hosting/test/shared_rules.json` 으로 고정한다.

/** 처리하는 mode — 그 밖의 값은 잘못된 주소(badLink)다. */
export const MODES = Object.freeze(["verifyEmail", "resetPassword", "recoverEmail"]);

/** 지원 언어 — 그 밖은 en 으로 표시한다. */
export const SUPPORTED_LANGS = Object.freeze(["ko", "en", "ja"]);

/** 새 비밀번호 최소 길이 — 앱 password_field.dart 의 `v.length < 8` 과 같은 값. */
export const MIN_PASSWORD_LENGTH = 8;

/** brandColor 가 없거나 형식이 틀릴 때 쓰는 색 (앱 기본 seed 와 같다). */
export const DEFAULT_BRAND_COLOR = "#673AB7";

/** 유효한 brandColor 형식 — `#RRGGBB`(대소문자 무관)만. 앞뒤 공백도 거부한다. */
const BRAND_COLOR_PATTERN = /^#[0-9A-Fa-f]{6}$/;

/** 흰 글자를 쓰는 최소 대비 (WCAG 2.x AA 본문). */
const MIN_WHITE_CONTRAST = 4.5;

/**
 * 쿼리 `lang` 값을 지원 언어 하나로 정한다.
 *
 * 앞뒤 공백을 걷고 소문자로 바꾼 뒤 `-` · `_` 앞부분만 본다(`ko-KR` → ko ·
 * `ja_JP` → ja). 문자열이 아니거나 지원 밖이면 en 이다.
 *
 * @param {unknown} raw 쿼리 값 (없으면 null).
 * @returns {"ko" | "en" | "ja"} 표시 언어.
 */
export function normalizeLang(raw) {
  if (typeof raw !== "string") return "en";
  const head = raw.trim().toLowerCase().split(/[-_]/)[0];
  return SUPPORTED_LANGS.includes(head) ? head : "en";
}

/**
 * brandColor 를 정규화한다 — `#RRGGBB` 면 그대로, 아니면 [DEFAULT_BRAND_COLOR].
 *
 * trim 하지 않는다 — 앞뒤 공백이 있는 값은 무효다(공유 표와 같다).
 *
 * @param {unknown} raw config 의 brandColor 값.
 * @returns {string} `#RRGGBB` 색.
 */
export function normalizeBrandColor(raw) {
  if (typeof raw !== "string" || !BRAND_COLOR_PATTERN.test(raw)) {
    return DEFAULT_BRAND_COLOR;
  }
  return raw;
}

/** sRGB 8bit 채널 값을 선형 값으로 바꾼다 (WCAG 상대 휘도 식). */
function linearize(channel) {
  const v = channel / 255;
  return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
}

/**
 * accent 면 위 글자 색을 고른다.
 *
 * 색을 [normalizeBrandColor] 로 먼저 정규화한 뒤 WCAG 상대 휘도 L 을 구해 흰색
 * 대비 `1.05 / (L + 0.05)` 가 4.5 이상이면 흰색, 아니면 검정이다(흰색이 4.5
 * 미만이면 검정 대비는 4.67 이상).
 *
 * @param {unknown} hex `#RRGGBB` 색.
 * @returns {"#FFFFFF" | "#000000"} 글자 색.
 */
export function onAccentColor(hex) {
  const color = normalizeBrandColor(hex);
  const r = linearize(parseInt(color.slice(1, 3), 16));
  const g = linearize(parseInt(color.slice(3, 5), 16));
  const b = linearize(parseInt(color.slice(5, 7), 16));
  const luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  return 1.05 / (luminance + 0.05) >= MIN_WHITE_CONTRAST ? "#FFFFFF" : "#000000";
}

/**
 * Firebase Auth 오류 코드를 결과 화면 상태로 바꾼다.
 *
 * 표에 없는 코드(내부 오류 · API 키 · App Check 거부 등)는 새 상태를 만들지
 * 않고 모두 unknown 이다. `auth/invalid-action-code` 는 「이미 처리됨」 과
 * 「잘못됨」 을 구분할 수 없어 invalid 하나로 묶는다.
 *
 * @param {unknown} code 오류 객체의 `code`.
 * @returns {"expired" | "invalid" | "disabled" | "notFound" | "network" | "tooMany" | "unknown"} 상태.
 */
export function stateForError(code) {
  switch (code) {
    case "auth/expired-action-code":
      return "expired";
    case "auth/invalid-action-code":
      return "invalid";
    case "auth/user-disabled":
      return "disabled";
    case "auth/user-not-found":
      return "notFound";
    case "auth/network-request-failed":
      return "network";
    case "auth/too-many-requests":
      return "tooMany";
    default:
      return "unknown";
  }
}

/**
 * 비밀번호 변경 실패 코드 가운데 입력 아래 문구로 보일 것을 고른다.
 *
 * @param {unknown} code 오류 객체의 `code`.
 * @returns {"errorWeak" | "errorPolicy" | null} 문구 키 끝부분 — null 이면 [stateForError] 로 판정한다.
 */
export function formErrorFor(code) {
  if (code === "auth/weak-password") return "errorWeak";
  if (code === "auth/password-does-not-meet-requirements") return "errorPolicy";
  return null;
}

/**
 * 페이지 쿼리로 첫 상태를 정한다.
 *
 * `mode` 가 [MODES] 중 하나이고 `oobCode` · `apiKey` 가 모두 비어 있지 않을
 * 때만 확인 중(loading)이다. 하나라도 없으면 SDK 를 부르지 않고 잘못된
 * 주소(badLink)다. `apiKey` 는 Firebase 액션 링크가 늘 싣는 값이라 링크 모양만
 * 본다 — SDK 초기화에는 쓰지 않는다([firebaseOptions] 가 빌드 주입 키만 쓴다).
 *
 * @param {URLSearchParams} query 페이지 쿼리.
 * @returns {{kind: "badLink"} | {kind: "loading", mode: string}} 첫 상태.
 */
export function initialState(query) {
  const mode = query.get("mode");
  const oobCode = query.get("oobCode");
  const apiKey = query.get("apiKey");
  if (MODES.includes(mode) && oobCode && apiKey) {
    return {kind: "loading", mode};
  }
  return {kind: "badLink"};
}

/**
 * 빌드 주입 설정으로 Firebase 초기화 옵션을 만든다.
 *
 * 링크 쿼리의 `apiKey` 는 받지 않는다 — 다른 프로젝트 키를 실은 링크가 이
 * 페이지에서 그 프로젝트로 요청을 보내지 못하게, 빌드가 넣은 이 프로젝트의
 * Web API 키만 쓴다(공식 custom email handler 예제와 같은 방식). 다른 프로젝트의
 * 링크는 oobCode 가 맞지 않아 「사용할 수 없는 링크」 로 끝난다.
 *
 * @param {{apiKey?: unknown, authDomain?: unknown} | null} config 빌드 주입 설정.
 * @returns {{apiKey: string, authDomain: string} | null} 옵션 — 키 · 도메인이
 *   비었거나 문자열이 아니면 null.
 */
export function firebaseOptions(config) {
  const apiKey = config?.apiKey;
  const authDomain = config?.authDomain;
  if (typeof apiKey !== "string" || apiKey === "") return null;
  if (typeof authDomain !== "string" || authDomain === "") return null;
  return {apiKey, authDomain};
}

/** 상태 하나의 화면 묶음을 만든다. */
function view(icon, titleKey, bodyKey, {retry = false, brandBadge = false} = {}) {
  return {icon, titleKey, bodyKey, retry, brandBadge};
}

/**
 * 상태 · mode 로 화면 구성(표지 아이콘 · 제목 키 · 설명 키 · 재시도 · brand 표지)을 돌려준다.
 *
 * UI-SPEC 상태 표 그대로다. 모르는 상태나, mode 가 필요한 상태에 모르는 mode 가
 * 오면 새 상태를 만들지 않고 unknown 화면이다.
 *
 * @param {string} kind 상태 (loading · form · success · expired · invalid · badLink ·
 *   disabled · notFound · network · tooMany · unknown).
 * @param {string | null} mode [MODES] 중 하나 (badLink · 계정 · 오류 상태에서는 무시).
 * @returns {{icon: string | null, titleKey: string | null, bodyKey: string, retry: boolean, brandBadge: boolean}} 화면 구성.
 */
export function viewFor(kind, mode) {
  const hasMode = MODES.includes(mode);
  switch (kind) {
    case "loading":
      return view(null, null, "page.loading");
    case "form":
      return view(
        "lock_reset",
        "page.resetPassword.form.title",
        "page.resetPassword.form.body",
      );
    case "success":
      if (!hasMode) break;
      return view("check", `page.${mode}.success.title`, `page.${mode}.success.body`, {
        brandBadge: true,
      });
    case "expired":
      if (!hasMode) break;
      return view("schedule", "page.expired.title", `page.${mode}.expired.body`);
    case "invalid":
      if (!hasMode) break;
      return view("link_off", "page.invalid.title", `page.${mode}.invalid.body`);
    case "badLink":
      return view("link_off", "page.invalid.title", "page.badLink.body");
    case "disabled":
    case "notFound":
      return view("person_off", "page.account.title", `page.account.${kind}`);
    case "network":
      return view("wifi_off", "page.network.title", "page.network.body", {retry: true});
    case "tooMany":
      return view("error", "page.tooMany.title", "page.tooMany.body", {retry: true});
    default:
      break;
  }
  // 재시도는 연결 · 과다 · 알 수 없음에만 — 다시 시도하면 결과가 바뀔 수 있는 오류다.
  return view("error", "page.unknown.title", "page.unknown.body", {retry: true});
}
