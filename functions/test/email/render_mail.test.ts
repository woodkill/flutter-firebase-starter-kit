/**
 * `renderMail` · `attachLang` · `toResultPageLink` 회귀 테스트 (Phase 17.5 —
 * see ROADMAP.md · D-05 · D-07 · D-11 · D-15 · D-22 · MAIL-02).
 *
 * 메일 HTML · text 는 함수 코드가 Handlebars 로 렌더한다(D-11). 이 테스트는
 * 배포본과 같은 렌더러(`src/email/render_mail.ts` + `templates/*.hbs`)를
 * 직접 부른다.
 *
 * 시나리오:
 *  - ko 인증 메일 · 로고 없음 — subject · lang · 문구 · 버튼 href = 대체 링크 ·
 *    `<img` 0
 *  - `attachLang` — Admin 링크에 `lang` 1개 부착 · 기존 값 덮어쓰기
 *  - RP1~RP4: `toResultPageLink` — 결과 페이지 호스트 · 경로 + 원 쿼리 보존 ·
 *    원 링크 호스트 무관 · `continueUrl` 보존 · `lang` 1개 · 필수 쿼리 없으면 throw
 *  - 치환자 완전 치환 · `&#x3D;` 0 (Pitfall 6)
 *  - handlebars 4.7.10 의 `escapeExpression("a=b")` 결과 고정 (Pitfall 6 재확인)
 *  - 로고 있음 / 없음 헤더 · 앱 이름 HTML escape · text 파트 조립 규칙
 *  - 입력 방어 — 빈 앱 이름 · 속성 밖으로 새는 링크 거부
 *  - 확장 `templates/` 컬렉션 미사용 (D-11)
 *  - 렌더 스냅샷 12개 (이름 규칙 `snapshot ${kind} ${locale} logo=${none|with}`)
 *
 * 스냅샷 갱신: 템플릿 · 문구를 의도해서 바꿨을 때만
 * `pnpm test -- -u test/email` 로 다시 쓰고, diff 를 눈으로 대조한 뒤 커밋한다.
 */

import {readdirSync, readFileSync} from "fs";
import * as path from "path";

import Handlebars from "handlebars";

import type {MailBrand} from "../../src/email/brand";
import type {MailLocale} from "../../src/email/mail_locale";
import {
  attachLang,
  renderMail,
  toResultPageLink,
} from "../../src/email/render_mail";
import type {MailKind} from "../../src/email/render_mail";

// brand.ts 가 import 하는 params 모듈 — 이 suite 는 env 를 읽지 않는다.
jest.mock("firebase-functions/params", () => ({
  defineString: () => ({value: () => ""}),
}));

/** Admin SDK 가 만드는 인증 액션 링크 모양 (lang 없음 — RESEARCH §R1). */
const ADMIN_LINK =
  "https://example.firebaseapp.com/__/auth/action" +
  "?mode=verifyEmail&oobCode=c&apiKey=k";

/** 결과 페이지 주소 fixture (`EMAIL_RESULT_PAGE_URL` 값 모양 — D-22 ②). */
const RESULT_PAGE_URL = "https://example.web.app/";

/** 로고 파일이 없는 킷 기본 상태의 브랜드 값. */
const BRAND_NO_LOGO: MailBrand = {
  appName: "Kit",
  brandColor: "#673AB7",
  onBrandColor: "#FFFFFF",
  logoUrl: "",
};

/** Hosting 로고 파일이 있는 브랜드 값 (D-05). */
const BRAND_WITH_LOGO: MailBrand = {
  ...BRAND_NO_LOGO,
  logoUrl: "https://example.web.app/logo.png",
};

/** 요청자 주소 fixture. */
const EMAIL = "a@example.com";

/** 스냅샷 행렬 — 메일 종류. */
const KINDS: readonly MailKind[] = ["verifyEmail", "resetPassword"];

/** 스냅샷 행렬 — locale. */
const LOCALES: readonly MailLocale[] = ["ko", "en", "ja"];

/** 스냅샷 행렬 — 로고 유/무. */
const LOGOS = [
  {label: "none", brand: BRAND_NO_LOGO},
  {label: "with", brand: BRAND_WITH_LOGO},
] as const;

/**
 * 메일 종류에 맞는 Admin 액션 링크를 만든다.
 *
 * @param {MailKind} kind 메일 종류.
 * @return {string} `mode` 가 kind 인 링크 (lang 없음).
 */
function adminLinkFor(kind: MailKind): string {
  return ADMIN_LINK.replace("mode=verifyEmail", `mode=${kind}`);
}

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

/**
 * 문자열 안 부분 문자열 개수를 센다.
 *
 * @param {string} haystack 대상 문자열.
 * @param {string} needle 찾을 문자열.
 * @return {number} 겹치지 않는 출현 횟수.
 */
function countOf(haystack: string, needle: string): number {
  return haystack.split(needle).length - 1;
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

describe("toResultPageLink (D-22)", () => {
  // eslint-disable-next-line max-len
  it("RP1: firebaseapp.com 기본 핸들러 링크 → 결과 페이지 루트 + 원 쿼리 + lang", () => {
    expect(toResultPageLink(ADMIN_LINK, RESULT_PAGE_URL, "ko")).toBe(
      "https://example.web.app/?mode=verifyEmail&oobCode=c&apiKey=k&lang=ko",
    );
  });

  // eslint-disable-next-line max-len
  it("RP2: web.app 기본 핸들러 링크여도 RP1 과 같은 결과다 (원 링크 호스트 무관)", () => {
    const webAppLink =
      "https://example.web.app/__/auth/action" +
      "?mode=verifyEmail&oobCode=c&apiKey=k";

    expect(toResultPageLink(webAppLink, RESULT_PAGE_URL, "ko")).toBe(
      toResultPageLink(ADMIN_LINK, RESULT_PAGE_URL, "ko"),
    );
    expect(toResultPageLink(webAppLink, RESULT_PAGE_URL, "ko")).toBe(
      "https://example.web.app/?mode=verifyEmail&oobCode=c&apiKey=k&lang=ko",
    );
  });

  // eslint-disable-next-line max-len
  it("RP3: continueUrl 은 그대로 남고 기존 lang 은 덮어써 1개다", () => {
    const withContinue =
      `${ADMIN_LINK}&continueUrl=https%3A%2F%2Fapp.example.com%2Fdone`;
    const withLang =
      "https://example.web.app/__/auth/action" +
      "?mode=resetPassword&oobCode=c&apiKey=k&lang=fr";

    expect(toResultPageLink(withContinue, RESULT_PAGE_URL, "en")).toBe(
      "https://example.web.app/?mode=verifyEmail&oobCode=c&apiKey=k" +
        "&continueUrl=https%3A%2F%2Fapp.example.com%2Fdone&lang=en",
    );
    const out = toResultPageLink(withLang, RESULT_PAGE_URL, "ja");
    expect(out).toBe(
      "https://example.web.app/?mode=resetPassword&oobCode=c&apiKey=k&lang=ja",
    );
    expect(new URL(out).searchParams.getAll("lang")).toEqual(["ja"]);
  });

  it.each([
    [
      "mode",
      "https://example.firebaseapp.com/__/auth/action" +
        "?oobCode=OOB_RP4_SECRET&apiKey=KEY_RP4_SECRET",
    ],
    [
      "oobCode",
      "https://example.firebaseapp.com/__/auth/action" +
        "?mode=verifyEmail&apiKey=KEY_RP4_SECRET",
    ],
    [
      "apiKey",
      "https://example.firebaseapp.com/__/auth/action" +
        "?mode=verifyEmail&oobCode=OOB_RP4_SECRET",
    ],
  ])(
    "RP4: %s 없는 링크는 throw 하고 메시지에 링크 · 값이 없다",
    (_missing, link) => {
      let message = "";
      try {
        toResultPageLink(link, RESULT_PAGE_URL, "ko");
      } catch (err: unknown) {
        message = err instanceof Error ? err.message : String(err);
      }

      expect(message).toBe(
        "toResultPageLink: link has no mode, oobCode or apiKey",
      );
      expect(message).not.toContain("firebaseapp.com");
      expect(message).not.toContain("OOB_RP4_SECRET");
      expect(message).not.toContain("KEY_RP4_SECRET");
    },
  );
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

describe("renderMail 헤더 · escape · text 파트", () => {
  it("로고가 있으면 높이 40 이미지 1개 · alt = 앱 이름이다", () => {
    const mail = renderMail("resetPassword", {
      locale: "en",
      email: EMAIL,
      link: attachLang(adminLinkFor("resetPassword"), "en"),
      brand: BRAND_WITH_LOGO,
    });

    expect(countOf(mail.html, "<img")).toBe(1);
    expect(mail.html).toContain(
      "<img src=\"https://example.web.app/logo.png\" alt=\"Kit\" height=\"40\"",
    );
  });

  it("앱 이름은 html 에서 escape · subject 에서는 원문이다", () => {
    const appName = "<b>&\"";
    const mail = renderMail("verifyEmail", {
      locale: "en",
      email: EMAIL,
      link: attachLang(ADMIN_LINK, "en"),
      brand: {...BRAND_WITH_LOGO, appName},
    });

    expect(mail.subject).toBe(`Verify your email for ${appName}`);
    expect(mail.html).toContain("alt=\"&lt;b&gt;&amp;&quot;\"");
    expect(mail.html).toContain("This email was sent by &lt;b&gt;&amp;&quot;.");
    expect(mail.html).not.toContain(appName);
  });

  it("주소는 html 에서 escape 되고 break-all span 으로 감싼다", () => {
    const mail = renderMail("verifyEmail", {
      locale: "en",
      email: "a<b>@example.com",
      link: attachLang(ADMIN_LINK, "en"),
      brand: BRAND_NO_LOGO,
    });

    expect(mail.html).toContain(
      "<span style=\"word-break:break-all;\">a&lt;b&gt;@example.com</span>",
    );
    expect(mail.text).toContain("verify a<b>@example.com.");
  });

  it.each(KINDS.flatMap((kind) => LOCALES.map((locale) => [kind, locale])))(
    "text 파트 조립 규칙 %s %s",
    (kind, locale) => {
      const mailKind = kind as MailKind;
      const link = attachLang(adminLinkFor(mailKind), locale as MailLocale);
      const mail = renderMail(mailKind, {
        locale: locale as MailLocale,
        email: EMAIL,
        link,
        brand: BRAND_NO_LOGO,
      });
      const lines = mail.text.split("\n");
      const separator = lines.indexOf("--");

      // 줄 끝 공백 0.
      expect(lines.filter((line) => line !== line.trimEnd())).toEqual([]);
      // 링크 줄 = html 의 href 값.
      expect(lines).toContain(collectHrefs(mail.html)[0]);
      expect(collectHrefs(mail.html)[0]).toBe(link);
      // `--` 줄 다음 줄이 마지막 줄(footer)이다.
      expect(separator).toBe(lines.length - 2);
      expect(lines[lines.length - 1]).toContain("Kit");
      // 조립 순서: heading ⏎⏎ body ⏎⏎ 링크 ⏎⏎ ignore ⏎⏎ -- ⏎ footer.
      expect(mail.text.split("\n\n")).toHaveLength(5);
      expect(mail.text).not.toContain("<");
    },
  );
});

describe("renderMail 입력 방어", () => {
  it("앱 이름이 비면 렌더하지 않는다", () => {
    expect(() =>
      renderMail("verifyEmail", {
        locale: "ko",
        email: EMAIL,
        link: attachLang(ADMIN_LINK, "ko"),
        brand: {...BRAND_NO_LOGO, appName: "  "},
      }),
    ).toThrow("appName");
  });

  it.each([
    "javascript:alert(1)",
    "https://example.com/a\"onmouseover=\"x",
    "https://example.com/a b",
    "not a url",
  ])("속성 밖으로 새거나 http(s) 가 아닌 링크 %j 를 거부한다", (link) => {
    expect(() =>
      renderMail("verifyEmail", {
        locale: "ko",
        email: EMAIL,
        link,
        brand: BRAND_NO_LOGO,
      }),
    ).toThrow("link");
  });

  it("안전하지 않은 로고 URL 은 앱 이름 텍스트 헤더로 대체한다", () => {
    const mail = renderMail("verifyEmail", {
      locale: "ko",
      email: EMAIL,
      link: attachLang(ADMIN_LINK, "ko"),
      brand: {...BRAND_NO_LOGO, logoUrl: "http://example.web.app/logo.png"},
    });

    expect(mail.html).not.toContain("<img");
  });
});

describe("확장 templates/ 컬렉션 미사용 (D-11)", () => {
  it("src/email 소스가 Firestore 컬렉션 templates 를 읽지 않는다", () => {
    const dir = path.join(__dirname, "..", "..", "src", "email");
    const sources = readdirSync(dir).filter((name) => name.endsWith(".ts"));

    expect(sources.length).toBeGreaterThan(0);
    for (const name of sources) {
      const source = readFileSync(path.join(dir, name), "utf8");
      expect(source).not.toMatch(/collection\(\s*["'`]templates/);
    }
  });
});

describe("renderMail 스냅샷", () => {
  for (const kind of KINDS) {
    for (const locale of LOCALES) {
      for (const logo of LOGOS) {
        it(`snapshot ${kind} ${locale} logo=${logo.label}`, () => {
          const mail = renderMail(kind, {
            locale,
            email: EMAIL,
            link: attachLang(adminLinkFor(kind), locale),
            brand: logo.brand,
          });

          expect(mail).toMatchSnapshot();
        });
      }
    }
  }
});
