// Phase 17.5 — see ROADMAP.md (D-03 · D-05 · D-17 · D-18) — 인증 결과 페이지.
//
// Firebase Auth 메일 링크(custom email action handler)가 여는 페이지다. 쿼리
// mode · oobCode · apiKey · lang 만 읽고, 앱 복귀 주소는 읽지 않는다 — 성공
// 화면은 「앱에서 계속」 문구뿐이고 이동 버튼이 없다. 쿼리 apiKey 는 링크 모양
// 확인에만 쓰고, SDK 는 빌드가 넣은 이 프로젝트의 Web API 키로만 초기화한다.
//
// 앱 이름 · 색 · 로고 유무 · Web API 키 · 문구 · 아이콘은 hosting/build.mjs 가
// index.html 의 #kit-config JSON 으로 넣는다. 동적 텍스트는 모두 textContent 로 넣고, 마크업을
// 넣는 곳은 빌드가 만든 아이콘 SVG 1곳(setIcon)뿐이다.
//
// Firebase JS SDK 는 판을 고정한 gstatic ES module 을 동적 import 한다 —
// 불러오지 못하면 연결 실패 상태로 보인다.

import {
  MIN_PASSWORD_LENGTH,
  firebaseOptions,
  formErrorFor,
  initialState,
  normalizeBrandColor,
  normalizeLang,
  onAccentColor,
  stateForError,
  viewFor,
} from "./state.mjs";

const SDK_APP_URL = "https://www.gstatic.com/firebasejs/12.19.0/firebase-app.js";
const SDK_AUTH_URL = "https://www.gstatic.com/firebasejs/12.19.0/firebase-auth.js";

// 폼 제출 실패 가운데 폼을 유지하고 인라인 오류로 보일 상태 → 문구 키 끝부분.
const FORM_ALERT_KEYS = Object.freeze({
  network: "errorNetwork",
  tooMany: "errorTooMany",
  unknown: "errorUnknown",
});

const FORM_KEY = "page.resetPassword.form.";

const query = new URLSearchParams(location.search);
const lang = normalizeLang(query.get("lang"));

/** 빌드 주입 설정 (#kit-config). */
let config = null;
/** 상태 화면이 들어가는 section.status. */
let statusSection = null;
/** 불러온 SDK 함수 묶음 — 불러오기 전이면 null. */
let sdk = null;
/** 초기화한 Auth 인스턴스 (재시도 때 다시 초기화하지 않는다). */
let auth = null;

/**
 * 빌드 주입 JSON 을 읽는다.
 *
 * @returns {object | null} 설정 — 없거나 깨졌으면 null.
 */
function readConfig() {
  const node = document.getElementById("kit-config");
  if (!node) return null;
  try {
    const parsed = JSON.parse(node.textContent ?? "");
    return parsed && typeof parsed === "object" ? parsed : null;
  } catch {
    return null;
  }
}

/**
 * 판정 언어의 문구를 돌려준다 (없으면 en · 그래도 없으면 빈 문자열).
 *
 * @param {string | null} key 문구 키.
 * @returns {string} 문구.
 */
function translate(key) {
  if (!key) return "";
  return config.copy?.[lang]?.[key] ?? config.copy?.en?.[key] ?? "";
}

/**
 * 요소를 만든다.
 *
 * @param {string} tag 태그 이름.
 * @param {{className?: string, text?: string}} [options] 클래스 · 텍스트.
 * @returns {HTMLElement} 요소.
 */
function createElement(tag, {className, text} = {}) {
  const element = document.createElement(tag);
  if (className) element.className = className;
  if (text !== undefined) element.textContent = text;
  return element;
}

// [container] 의 내용을 빌드가 주입한 아이콘 SVG 로 바꾼다 — 마크업을 넣는 유일한 곳.
// 아이콘 이름은 viewFor · 이 파일의 고정 값뿐이고, 값은 저장소 아이콘 파일이다.
function setIcon(container, name) {
  const svg = (name && config.icons?.[name]) || "";
  container.innerHTML = svg;
  const icon = container.querySelector("svg");
  if (icon) {
    icon.setAttribute("aria-hidden", "true");
    icon.setAttribute("focusable", "false");
  }
}

/**
 * 문서 제목을 `{문구} · {앱 이름}` 으로 바꾼다.
 *
 * @param {string} text 화면 제목 (확인 중이면 확인 중 문구).
 */
function setDocumentTitle(text) {
  document.title = `${text} · ${config.appName}`;
}

/**
 * 설명 문단을 만든다. `{email}` 자리는 굵은 span.email 로 넣는다.
 *
 * @param {string} text 문구.
 * @param {string} email 주소 (없으면 빈 문자열).
 * @returns {HTMLElement} p.body.
 */
function createBody(text, email) {
  const paragraph = createElement("p", {className: "body"});
  text.split("{email}").forEach((part, index) => {
    if (index > 0) paragraph.append(createElement("span", {className: "email", text: email}));
    if (part) paragraph.append(document.createTextNode(part));
  });
  return paragraph;
}

/**
 * 상태 표지(56 원 + 아이콘)를 만든다.
 *
 * @param {string | null} icon 아이콘 이름.
 * @param {boolean} brand 성공 표지(brandColor 면)인가.
 * @returns {HTMLElement} div.badge.
 */
function createBadge(icon, brand) {
  const badge = createElement("div", {className: brand ? "badge success" : "badge"});
  setIcon(badge, icon);
  return badge;
}

/** 확인 중 화면 — 중립 스피너 + 확인 중 문구(role=status), 제목 · 버튼 없음. */
function showLoading() {
  const badge = createElement("div", {className: "badge"});
  const spinner = createElement("div", {className: "spinner"});
  spinner.setAttribute("aria-hidden", "true");
  badge.append(spinner);
  const text = translate("page.loading");
  const paragraph = createElement("p", {className: "body muted", text});
  paragraph.setAttribute("role", "status");
  statusSection.replaceChildren(badge, paragraph);
  setDocumentTitle(text);
}

/**
 * 결과 상태 화면을 그린다 (UI-SPEC 상태 표 — viewFor).
 *
 * @param {string} kind 상태.
 * @param {string | null} mode mode.
 * @param {string} [email] 설명의 `{email}` 자리 값.
 */
function showState(kind, mode, email = "") {
  const view = viewFor(kind, mode);
  const title = translate(view.titleKey);
  const children = [
    createBadge(view.icon, view.brandBadge),
    createElement("h1", {text: title}),
    createBody(translate(view.bodyKey), email),
  ];
  if (view.retry) {
    const button = createElement("button", {className: "btn", text: translate("page.retry")});
    button.type = "button";
    button.addEventListener("click", retry);
    children.push(button);
  }
  statusSection.replaceChildren(...children);
  setDocumentTitle(title);
}

/** 재시도 — 실패한 흐름을 처음부터 다시 돈다. SDK 를 못 불러왔으면 새로고침한다. */
function retry() {
  if (!sdk) {
    location.reload();
    return;
  }
  void run();
}

/**
 * gstatic 의 Firebase JS SDK 를 불러온다.
 *
 * @returns {Promise<object>} 이 페이지가 쓰는 함수 묶음.
 */
async function loadSdk() {
  const [appModule, authModule] = await Promise.all([import(SDK_APP_URL), import(SDK_AUTH_URL)]);
  return {
    initializeApp: appModule.initializeApp,
    getAuth: authModule.getAuth,
    applyActionCode: authModule.applyActionCode,
    checkActionCode: authModule.checkActionCode,
    verifyPasswordResetCode: authModule.verifyPasswordResetCode,
    confirmPasswordReset: authModule.confirmPasswordReset,
  };
}

/**
 * 비밀번호 재설정 폼을 그린다 (UI-SPEC §(F)).
 *
 * @param {string} mode resetPassword.
 * @param {string} oobCode 링크의 일회용 코드.
 * @param {string} email 재설정할 계정 주소 (verifyPasswordResetCode 결과).
 */
function showResetForm(mode, oobCode, email) {
  const view = viewFor("form", mode);
  const title = translate(view.titleKey);

  const form = createElement("form");
  form.noValidate = true;

  // 비밀번호 관리자가 계정을 알아보게 하는 숨은 username 입력.
  const username = createElement("input");
  username.type = "email";
  username.name = "username";
  username.autocomplete = "username";
  username.value = email;
  username.hidden = true;
  username.readOnly = true;

  const label = createElement("label", {className: "field-label", text: translate(`${FORM_KEY}label`)});
  label.htmlFor = "pw";

  const field = createElement("div", {className: "field"});
  const input = createElement("input");
  input.id = "pw";
  input.type = "password";
  input.autocomplete = "new-password";
  input.setAttribute("aria-describedby", "pw-help");
  const toggle = createElement("button", {className: "toggle"});
  toggle.type = "button";
  field.append(input, toggle);

  const helper = createElement("div", {className: "helper"});
  helper.id = "pw-help";

  const submit = createElement("button", {className: "btn"});
  submit.type = "submit";

  let alertBox = null;
  let submitting = false;

  const setPasswordVisible = (visible) => {
    input.type = visible ? "text" : "password";
    toggle.setAttribute("aria-pressed", String(visible));
    toggle.setAttribute("aria-label", translate(`${FORM_KEY}${visible ? "hide" : "show"}`));
    setIcon(toggle, visible ? "visibility_off" : "visibility");
  };

  // 입력 아래 문구 — 오류 키가 없으면 도움말로 돌아간다.
  const setFieldError = (errorKey) => {
    const invalid = errorKey !== null;
    field.classList.toggle("invalid", invalid);
    helper.classList.toggle("error", invalid);
    helper.textContent = translate(`${FORM_KEY}${invalid ? errorKey : "helper"}`);
    if (invalid) {
      input.setAttribute("aria-invalid", "true");
    } else {
      input.removeAttribute("aria-invalid");
    }
  };

  // 폼 위 인라인 오류(role=alert) — 입력값은 그대로 둔다.
  const setAlert = (alertKey) => {
    alertBox?.remove();
    alertBox = null;
    if (!alertKey) return;
    alertBox = createElement("div", {className: "alert"});
    alertBox.setAttribute("role", "alert");
    setIcon(alertBox, "error");
    alertBox.append(createElement("span", {text: translate(`${FORM_KEY}${alertKey}`)}));
    submit.before(alertBox);
  };

  const setSubmitting = (on) => {
    submitting = on;
    input.disabled = on;
    toggle.disabled = on;
    submit.disabled = on;
    submit.textContent = translate(`${FORM_KEY}${on ? "submitting" : "submit"}`);
  };

  toggle.addEventListener("click", () => setPasswordVisible(input.type === "password"));
  input.addEventListener("input", () => {
    if (field.classList.contains("invalid")) setFieldError(null);
  });
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (submitting) return;
    setAlert(null);
    const password = input.value;
    // 앱과 같은 규칙 — 공백을 걷지 않고 UTF-16 길이로 본다. 서버를 부르지 않는다.
    if (password.length < MIN_PASSWORD_LENGTH) {
      setFieldError("errorTooShort");
      input.focus();
      return;
    }
    setSubmitting(true);
    try {
      await sdk.confirmPasswordReset(auth, oobCode, password);
      showState("success", mode);
    } catch (error) {
      setSubmitting(false);
      const fieldKey = formErrorFor(error?.code);
      if (fieldKey) {
        setFieldError(fieldKey);
        input.focus();
        return;
      }
      const kind = stateForError(error?.code);
      if (Object.hasOwn(FORM_ALERT_KEYS, kind)) {
        setAlert(FORM_ALERT_KEYS[kind]);
        return;
      }
      // 만료 · 사용할 수 없음 · 계정 오류는 폼을 치우고 전체 상태로 바꾼다.
      showState(kind, mode);
    }
  });

  setPasswordVisible(false);
  setFieldError(null);
  setSubmitting(false);
  form.append(username, label, field, helper, submit);
  statusSection.replaceChildren(
    createBadge(view.icon, view.brandBadge),
    createElement("h1", {text: title}),
    createBody(translate(view.bodyKey), email),
    form,
  );
  setDocumentTitle(title);
}

/** 쿼리로 흐름을 처음부터 실행한다 (UI-SPEC §(R) 흐름). */
async function run() {
  const initial = initialState(query);
  if (initial.kind === "badLink") {
    showState("badLink", null);
    return;
  }
  const {mode} = initial;
  const oobCode = query.get("oobCode");
  // 링크 쿼리의 apiKey 가 아니라 빌드 주입 키로만 초기화한다 — 다른 프로젝트
  // 링크가 이 페이지에서 그 프로젝트로 비밀번호를 보내지 못한다.
  const options = firebaseOptions(config);
  if (!options) {
    console.error("kit-config 에 apiKey 가 없다 — hosting/build.mjs 로 다시 빌드해 배포한다");
    showState("unknown", mode);
    return;
  }
  showLoading();

  if (!sdk) {
    try {
      sdk = await loadSdk();
    } catch (error) {
      console.warn("Firebase SDK load failed", error?.message);
      showState("network", mode);
      return;
    }
  }

  try {
    auth ??= sdk.getAuth(sdk.initializeApp(options));
    if (mode === "verifyEmail") {
      await sdk.applyActionCode(auth, oobCode);
      showState("success", mode);
    } else if (mode === "recoverEmail") {
      // checkActionCode 의 data.email = 되돌릴(복원될) 주소.
      const info = await sdk.checkActionCode(auth, oobCode);
      const email = info?.data?.email ?? "";
      await sdk.applyActionCode(auth, oobCode);
      showState("success", mode, email);
    } else {
      const email = await sdk.verifyPasswordResetCode(auth, oobCode);
      showResetForm(mode, oobCode, email);
    }
  } catch (error) {
    console.warn("Firebase Auth action failed", error?.code);
    showState(stateForError(error?.code), mode);
  }
}

/** 페이지 시작 — 설정 · 언어 · 색 · 헤더를 적용하고 흐름을 실행한다. */
function start() {
  config = readConfig();
  const main = document.getElementById("app");
  if (!config || !main) {
    console.error("kit-config 가 없거나 읽을 수 없다 — hosting/build.mjs 로 빌드한 산출물을 배포한다");
    return;
  }
  const root = document.documentElement;
  root.lang = lang;
  const brandColor = normalizeBrandColor(config.brandColor);
  root.style.setProperty("--brand", brandColor);
  root.style.setProperty("--on-brand", onAccentColor(brandColor));

  const sheet = createElement("div", {className: "sheet"});
  const header = createElement("header", {className: "brand"});
  const name = createElement("span", {className: "name", text: config.appName});
  if (config.hasLogo) {
    const logo = createElement("img", {className: "logo"});
    logo.src = "/logo.png";
    logo.alt = config.appName;
    // 로고를 불러오지 못하면 앱 이름 텍스트 헤더로 바꾼다.
    logo.addEventListener("error", () => logo.replaceWith(name), {once: true});
    header.append(logo);
  } else {
    header.append(name);
  }
  statusSection = createElement("section", {className: "status"});
  statusSection.setAttribute("aria-live", "polite");
  sheet.append(header, statusSection);
  main.replaceChildren(sheet);

  void run();
}

start();
