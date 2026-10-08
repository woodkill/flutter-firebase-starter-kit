/**
 * `renderMail` · `attachLang` 회귀 테스트 (Phase 17.5 — see ROADMAP.md ·
 * D-05 · D-07 · D-11 · D-15 · MAIL-02).
 *
 * 메일 HTML · text 는 함수 코드가 Handlebars 로 렌더한다(D-11). 이 테스트는
 * 배포본과 같은 렌더러(`src/email/render_mail.ts` + `templates/*.hbs`)를
 * 직접 부른다.
 *
 * 시나리오:
 *  - ko 인증 메일 · 로고 없음 — subject · lang · 문구 · 버튼 href = 대체 링크 ·
 *    `<img` 0
 *  - `attachLang` — Admin 링크에 `lang` 1개 부착 · 기존 값 덮어쓰기
 *  - 치환자 완전 치환 · `&#x3D;` 0 (Pitfall 6)
 *  - handlebars 4.7.10 의 `escapeExpression("a=b")` 결과 고정 (Pitfall 6 재확인)
 *  - 렌더 스냅샷 (이름 규칙 `snapshot ${kind} ${locale} logo=${none|with}`)
 */

import Handlebars from "handlebars";

import type {MailBrand} from "../../src/email/brand";
import {attachLang, renderMail} from "../../src/email/render_mail";

// brand.ts 가 import 하는 params 모듈 — 이 suite 는 env 를 읽지 않는다.
jest.mock("firebase-functions/params", () => ({
  defineString: () => ({value: () => ""}),
}));

/** Admin SDK 가 만드는 액션 링크 모양 (lang 없음 — RESEARCH §R1). */
const ADMIN_LINK =
  "https://example.firebaseapp.com/__/auth/action" +
  "?mode=verifyEmail&oobCode=c&apiKey=k";

/** 로고 파일이 없는 킷 기본 상태의 브랜드 값. */
const BRAND_NO_LOGO: MailBrand = {
  appName: "Kit",
  brandColor: "#673AB7",
  onBrandColor: "#FFFFFF",
  logoUrl: "",
};

/** 요청자 주소 fixture. */
const EMAIL = "a@example.com";

/**
 * html 안 `href="…"` 값을 순서대로 모은다.
 *
 * @param {string} html 렌더된 메일 HTML.
 * @return {string[]} href 속성 값 목록.
 */
function collectHrefs(html: string): string[] {
  const pattern = /href="([^"]*)"/g;
  const hrefs: string[] = [];
  let match = pattern.exec(html);
  while (match !== null) {
    hrefs.push(match[1]);
    match = pattern.exec(html);
  }
  return hrefs;
}

describe("attachLang", () => {
  it("Admin 링크에 lang 을 1개 붙인다", () => {
    const out = new URL(attachLang(ADMIN_LINK, "ja"));

    expect(out.searchParams.getAll("lang")).toEqual(["ja"]);
    expect(out.searchParams.get("oobCode")).toBe("c");
    expect(out.searchParams.get("mode")).toBe("verifyEmail");
  });

  it("이미 있는 lang 은 덮어쓴다", () => {
    const out = new URL(attachLang(`${ADMIN_LINK}&lang=fr`, "ko"));

    expect(out.searchParams.getAll("lang")).toEqual(["ko"]);
  });
});

describe("renderMail verifyEmail ko", () => {
  const link = attachLang(ADMIN_LINK, "ko");
  const mail = renderMail("verifyEmail", {
    locale: "ko",
    email: EMAIL,
    link,
    brand: BRAND_NO_LOGO,
  });

  it("subject 는 앱 이름을 치환한 평문이다", () => {
    expect(mail.subject).toBe("Kit 이메일 주소 인증");
  });

  it("html 은 ko 문구 · lang 을 담는다", () => {
    expect(mail.html).toContain("<html lang=\"ko\">");
    expect(mail.html).toContain("이 이메일 주소가 본인 것인지 확인합니다.");
    expect(mail.html).toContain("이메일 주소를 인증해 주세요");
    expect(mail.html).toContain("이메일 인증하기");
  });

  it("버튼 href 와 대체 링크가 같은 URL 이다", () => {
    const hrefs = collectHrefs(mail.html);

    expect(hrefs).toEqual([link, link]);
    expect(mail.html).toContain(`>${link}</a>`);
  });

  it("로고가 없으면 이미지 요청이 0 이다", () => {
    expect(mail.html).not.toContain("<img");
  });

  it("치환자가 남지 않고 &#x3D; 가 0 이다", () => {
    for (const part of [mail.subject, mail.html, mail.text]) {
      expect(part).not.toContain("{appName}");
      expect(part).not.toContain("{email}");
      expect(part).not.toContain("&#x3D;");
    }
  });
});

describe("handlebars 4.7.10 escape 동작 (Pitfall 6)", () => {
  it("escapeExpression 은 = 를 &#x3D; 로 바꾼다", () => {
    expect(Handlebars.VERSION).toBe("4.7.10");
    expect(Handlebars.Utils.escapeExpression("a=b")).toBe("a&#x3D;b");
  });
});

describe("renderMail 스냅샷", () => {
  it("snapshot verifyEmail ko logo=none", () => {
    const mail = renderMail("verifyEmail", {
      locale: "ko",
      email: EMAIL,
      link: attachLang(ADMIN_LINK, "ko"),
      brand: BRAND_NO_LOGO,
    });

    expect(mail).toMatchSnapshot();
  });
});
