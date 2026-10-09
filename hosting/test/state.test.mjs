// Phase 17.5 — see ROADMAP.md (D-06 · D-17 · D-18) — 결과 페이지 상태 판정 모듈 테스트.
//
// 실행: node --test --test-reporter=tap 'hosting/test/*.test.mjs'
// (디렉터리 인자는 Node 24 에서 실패로 처리된다 — glob 으로 넘긴다.)

import {test} from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import {fileURLToPath} from "node:url";

import {
  DEFAULT_BRAND_COLOR,
  MIN_PASSWORD_LENGTH,
  MODES,
  SUPPORTED_LANGS,
  firebaseOptions,
  formErrorFor,
  initialState,
  normalizeBrandColor,
  normalizeLang,
  onAccentColor,
  stateForError,
  viewFor,
} from "../public/state.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
// 앱 · 메일 · 페이지가 같은 판정을 쓰는지 고정하는 공유 표.
const SHARED_RULES = JSON.parse(
  fs.readFileSync(path.join(HERE, "shared_rules.json"), "utf8"),
);

/** 문서용 쿼리 문자열로 initialState 를 부른다. */
function stateFor(query) {
  return initialState(new URLSearchParams(query));
}

test("상수 — mode 3개 · 언어 3개 · 8자 · 기본 색", () => {
  assert.deepEqual([...MODES], ["verifyEmail", "resetPassword", "recoverEmail"]);
  assert.deepEqual([...SUPPORTED_LANGS], ["ko", "en", "ja"]);
  assert.equal(MIN_PASSWORD_LENGTH, 8);
  assert.equal(DEFAULT_BRAND_COLOR, "#673AB7");
});

test("initialState — 쿼리가 모자라거나 mode 를 모르면 badLink", () => {
  assert.deepEqual(stateFor(""), {kind: "badLink"});
  assert.deepEqual(stateFor("mode=foo&oobCode=x&apiKey=k"), {kind: "badLink"});
  assert.deepEqual(stateFor("mode=verifyEmail&apiKey=k"), {kind: "badLink"});
  assert.deepEqual(stateFor("mode=verifyEmail&oobCode=x"), {kind: "badLink"});
  assert.deepEqual(stateFor("mode=verifyEmail&oobCode=&apiKey=k"), {
    kind: "badLink",
  });
  // 프로토타입 키 이름이 mode 로 들어와도 화이트리스트 밖이다.
  assert.deepEqual(stateFor("mode=toString&oobCode=x&apiKey=k"), {
    kind: "badLink",
  });
});

test("initialState — mode · oobCode · apiKey 가 모두 있으면 loading", () => {
  for (const mode of MODES) {
    assert.deepEqual(stateFor(`mode=${mode}&oobCode=x&apiKey=k`), {
      kind: "loading",
      mode,
    });
  }
});

test("firebaseOptions — 쿼리 apiKey 와 무관하게 빌드 주입 키로 초기화", () => {
  const config = {apiKey: "AIzaInjectedOwnProjectKey", authDomain: "p.firebaseapp.com"};
  for (const query of [
    "mode=resetPassword&oobCode=x&apiKey=AIzaOtherProjectKey",
    "mode=verifyEmail&oobCode=x&apiKey=AIzaInjectedOwnProjectKey",
  ]) {
    // 링크 모양은 그대로 loading 이고, 초기화 옵션은 쿼리 값을 보지 않는다.
    assert.equal(stateFor(query).kind, "loading", query);
    assert.deepEqual(firebaseOptions(config), {
      apiKey: "AIzaInjectedOwnProjectKey",
      authDomain: "p.firebaseapp.com",
    });
  }
  // 쿼리를 받는 인자가 없다 — 설정 1개만 받는다.
  assert.equal(firebaseOptions.length, 1);
});

test("firebaseOptions — 주입 키 · 도메인이 없거나 문자열이 아니면 null", () => {
  assert.equal(firebaseOptions(null), null);
  assert.equal(firebaseOptions({}), null);
  assert.equal(firebaseOptions({apiKey: "", authDomain: "p.firebaseapp.com"}), null);
  assert.equal(firebaseOptions({apiKey: 1, authDomain: "p.firebaseapp.com"}), null);
  assert.equal(firebaseOptions({apiKey: "AIzaKey", authDomain: ""}), null);
  // 추가 키는 옵션에 싣지 않는다.
  assert.deepEqual(
    firebaseOptions({apiKey: "AIzaKey", authDomain: "d", appName: "Kit"}),
    {apiKey: "AIzaKey", authDomain: "d"},
  );
});

test("stateForError — 오류 코드 표 7행", () => {
  const rows = [
    ["auth/expired-action-code", "expired"],
    ["auth/invalid-action-code", "invalid"],
    ["auth/user-disabled", "disabled"],
    ["auth/user-not-found", "notFound"],
    ["auth/network-request-failed", "network"],
    ["auth/too-many-requests", "tooMany"],
    ["auth/internal-error", "unknown"],
  ];
  for (const [code, expected] of rows) {
    assert.equal(stateForError(code), expected, code);
  }
  // 코드가 없는 오류 · API 키 · App Check 거부도 새 상태 없이 unknown 이다.
  assert.equal(stateForError(undefined), "unknown");
  assert.equal(stateForError("auth/api-key-not-valid"), "unknown");
  assert.equal(stateForError("auth/firebase-app-check-token-is-invalid"), "unknown");
});

test("formErrorFor — 서버 비밀번호 오류 2종만 입력 아래 문구", () => {
  assert.equal(formErrorFor("auth/weak-password"), "errorWeak");
  assert.equal(
    formErrorFor("auth/password-does-not-meet-requirements"),
    "errorPolicy",
  );
  assert.equal(formErrorFor("auth/network-request-failed"), null);
  assert.equal(formErrorFor(undefined), null);
});

test("viewFor — 성공은 check · brand 표지 · 재시도 없음", () => {
  for (const mode of MODES) {
    assert.deepEqual(viewFor("success", mode), {
      icon: "check",
      titleKey: `page.${mode}.success.title`,
      bodyKey: `page.${mode}.success.body`,
      retry: false,
      brandBadge: true,
    });
  }
});

test("viewFor — 만료 · 사용할 수 없음 · 잘못된 주소", () => {
  assert.deepEqual(viewFor("expired", "resetPassword"), {
    icon: "schedule",
    titleKey: "page.expired.title",
    bodyKey: "page.resetPassword.expired.body",
    retry: false,
    brandBadge: false,
  });
  assert.deepEqual(viewFor("invalid", "recoverEmail"), {
    icon: "link_off",
    titleKey: "page.invalid.title",
    bodyKey: "page.recoverEmail.invalid.body",
    retry: false,
    brandBadge: false,
  });
  assert.deepEqual(viewFor("badLink", null), {
    icon: "link_off",
    titleKey: "page.invalid.title",
    bodyKey: "page.badLink.body",
    retry: false,
    brandBadge: false,
  });
});

test("viewFor — 계정 2종은 person_off · page.account.*", () => {
  for (const kind of ["disabled", "notFound"]) {
    assert.deepEqual(viewFor(kind, "verifyEmail"), {
      icon: "person_off",
      titleKey: "page.account.title",
      bodyKey: `page.account.${kind}`,
      retry: false,
      brandBadge: false,
    });
  }
});

test("viewFor — 연결 · 과다 · 알 수 없음에만 재시도", () => {
  assert.deepEqual(viewFor("network", "verifyEmail"), {
    icon: "wifi_off",
    titleKey: "page.network.title",
    bodyKey: "page.network.body",
    retry: true,
    brandBadge: false,
  });
  for (const kind of ["tooMany", "unknown"]) {
    assert.deepEqual(viewFor(kind, "verifyEmail"), {
      icon: "error",
      titleKey: `page.${kind}.title`,
      bodyKey: `page.${kind}.body`,
      retry: true,
      brandBadge: false,
    });
  }
  const retryKinds = [
    "success", "expired", "invalid", "badLink", "disabled", "notFound",
    "network", "tooMany", "unknown",
  ].filter((kind) => viewFor(kind, "verifyEmail").retry);
  assert.deepEqual(retryKinds, ["network", "tooMany", "unknown"]);
});

test("viewFor — 확인 중은 제목 없이 page.loading · 폼은 lock_reset", () => {
  assert.deepEqual(viewFor("loading", "verifyEmail"), {
    icon: null,
    titleKey: null,
    bodyKey: "page.loading",
    retry: false,
    brandBadge: false,
  });
  assert.deepEqual(viewFor("form", "resetPassword"), {
    icon: "lock_reset",
    titleKey: "page.resetPassword.form.title",
    bodyKey: "page.resetPassword.form.body",
    retry: false,
    brandBadge: false,
  });
});

test("viewFor — 모르는 상태 · mode 는 새 상태 없이 unknown 화면", () => {
  assert.deepEqual(viewFor("nope", "verifyEmail"), viewFor("unknown", null));
  assert.deepEqual(viewFor("success", "nope"), viewFor("unknown", null));
});

test("공유 표 — brandColor 정규화 (trim 없음)", () => {
  for (const {input, expected} of SHARED_RULES.brandColor) {
    assert.equal(normalizeBrandColor(input), expected, JSON.stringify(input));
  }
  assert.equal(normalizeBrandColor(undefined), DEFAULT_BRAND_COLOR);
  assert.equal(normalizeBrandColor(123456), DEFAULT_BRAND_COLOR);
});

test("공유 표 — lang 정규화 (trim · 앞부분 · 그 밖 en)", () => {
  for (const {input, expected} of SHARED_RULES.lang) {
    assert.equal(normalizeLang(input), expected, JSON.stringify(input));
  }
  assert.equal(normalizeLang(undefined), "en");
});

test("공유 표 — on-accent 흰색 · 검정 판정", () => {
  for (const {input, expected} of SHARED_RULES.onAccent) {
    assert.equal(onAccentColor(input), expected, input);
  }
  // 무효 색은 기본 색으로 정규화한 뒤 판정한다.
  assert.equal(onAccentColor("blue"), onAccentColor(DEFAULT_BRAND_COLOR));
});
