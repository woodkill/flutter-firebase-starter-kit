# 브랜드 자산 갱신 (유지보수자 문서)

> 킷 사용자 문서가 아니다 — 킷 사용자는 출시 전에 로고 사용 조건만 확인한다([직접 하는 일](../guide.md#소셜-로고--브랜드-자산) 「출시 전 점검」).

소셜 로그인 버튼 6개가 그리는 로고 자산을 다시 받거나 바꿀 때의 절차다. 자산마다 README
(`assets/brand/<provider>/README.md`)가 공식 BI URL · 자산 다운로드 URL · 라이선스 · 사전
검수 절차를 담고, 이 문서는 그 README 들을 갱신하는 순서와 받은 날을 담는다.
버튼 라벨 글꼴(`assets/fonts/`) · 시험 글꼴(`assets/test_fonts/`)의 받은 날 · 만든 날과 시험 글꼴
subset 을 다시 만드는 법도 여기에 둔다.

---

## 자산 디렉토리 구조

```
assets/brand/
├── apple/
│   ├── black_logo/btn_signin_icon.svg
│   ├── white_logo/btn_signin_icon.svg
│   └── README.md
├── facebook/
│   ├── btn_signin_icon.svg
│   ├── LICENSE.txt
│   └── README.md
├── google/
│   ├── g.png
│   ├── 2.0x/g.png
│   ├── 3.0x/g.png
│   ├── 4.0x/g.png
│   ├── LICENSE.txt
│   └── README.md
├── kakao/
│   ├── btn_signin_icon.svg
│   ├── LICENSE.txt
│   └── README.md
├── line/
│   ├── btn_signin_icon.svg
│   ├── LICENSE.txt
│   └── README.md
└── naver/
    ├── btn_signin_icon.svg
    ├── LICENSE.txt
    └── README.md
```

- 로고는 provider 마다 한 벌이다. 라벨 글자는 그림에 들어 있지 않고 ARB 문구로 따로 그린다.
- Apple 은 `LICENSE.txt` 가 없다 — Apple HIG 를 지키는 범위의 사용이라 배포 라이선스 본문이
  없다(`assets/brand/apple/README.md` 「라이선스」 절).
- 각 자산의 형식(SVG path 를 어디서 옮겼는지 · PNG 를 어떻게 만들었는지)은 그 README 의
  디렉토리 구조 절과 자산 다운로드 URL 절에 있다:
  [Apple](../../assets/brand/apple/README.md) ·
  [Facebook](../../assets/brand/facebook/README.md) ·
  [Google](../../assets/brand/google/README.md) ·
  [Kakao](../../assets/brand/kakao/README.md) ·
  [LINE](../../assets/brand/line/README.md) ·
  [Naver](../../assets/brand/naver/README.md).
- `pubspec.yaml` 의 assets 는 디렉토리 등록이 재귀가 아니다. 하위 디렉토리(`apple/black_logo/`
  · `google/2.0x/` 꼴)를 새로 만들면 그 디렉토리를 따로 등록한다.

## 자산 다운로드

자산을 다시 받거나 새 변형을 더할 때의 순서다.

1. 그 자산 README 의 `## 공식 BI URL` · `## 자산 다운로드 URL` 에 적힌 공식 페이지를 직접
   방문해 받는다. wikipedia · seeklogo · 블로그 같은 제3자 출처는 쓰지 않는다 — 색 · 문구 ·
   조항은 공식 페이지 원문을 인용한다.
2. 받은 그림의 내용은 바꾸지 않는다(색 · 비율 · 회전 · 일부만 쓰기 금지). 파일 이름만 킷
   이름(`btn_signin_icon.svg` 등)으로 바꾼다. AI · PSD 원본에서 path 를 옮기거나 공식 SVG 를
   PNG 로 그리는 자산은 그 README 의 만드는 절차를 그대로 따른다.
3. 라이선스 조항이 바뀌었으면 같은 디렉토리의 `LICENSE.txt` 원문 인용을 갱신한다.
   `LICENSE.txt` 를 새로 더하거나 지우면 저장소 루트 `LICENSE` 의 제3자 절 경로 목록도 같이
   고친다(T-174-ART-03 이 두 목록이 같은지 본다).
4. 그 README 를 갱신한다. 7개 제목(`## 공식 BI URL` · `## 자산 다운로드 URL` ·
   `## 다운로드 일자` · `## 라이선스` · `## 사전 검수 절차` · `## 미포함 변형 추가 절차` ·
   `## 자산 freshness 갱신 빈도`)은 이름을 바꾸지 않는다. README 는 킷 사용자가 읽는 문서라
   사용자 문서 금지 패턴(날짜 · 이력 · 내부 식별자)을 쓰지 않는다 — 날짜는 아래
   [받은 날 · 만든 날](#받은-날--만든-날) 표에만 적는다.
5. 파일의 sha256 을 README 에 적는 자산은 64자리 전체로 적고, 같은 값을 고정한 시험
   (`brand_button_assets_test.dart`)도 함께 고친다.
6. [회귀 가드](#회귀-가드)를 돌린다.

새 provider 의 자산을 더할 때도 같은 꼴(로고 · `LICENSE.txt` · 7개 제목 README)로 디렉토리를
만들고 `pubspec.yaml` 에 등록한다.

## 공식 BI URL · 라이선스 · 사전 검수 확인

자산마다 공식 근거는 그 README 의 세 절에 있다. 공식 페이지를 다시 확인할 때는 이 표의
절을 열어 적힌 URL 을 방문하고, 페이지의 제공 형식 · 색 · 문구 · 조항이 README 의 설명과
같은지 본다.

| 자산 | 공식 BI URL | 라이선스 | 사전 검수 |
|---|---|---|---|
| Apple | [README 「공식 BI URL」](../../assets/brand/apple/README.md#공식-bi-url) | [README 「라이선스」](../../assets/brand/apple/README.md#라이선스) | [README 「사전 검수 절차」](../../assets/brand/apple/README.md#사전-검수-절차) |
| Facebook | [README 「공식 BI URL」](../../assets/brand/facebook/README.md#공식-bi-url) | [README 「라이선스」](../../assets/brand/facebook/README.md#라이선스) | [README 「사전 검수 절차」](../../assets/brand/facebook/README.md#사전-검수-절차) |
| Google | [README 「공식 BI URL」](../../assets/brand/google/README.md#공식-bi-url) | [README 「라이선스」](../../assets/brand/google/README.md#라이선스) | [README 「사전 검수 절차」](../../assets/brand/google/README.md#사전-검수-절차) |
| Kakao | [README 「공식 BI URL」](../../assets/brand/kakao/README.md#공식-bi-url) | [README 「라이선스」](../../assets/brand/kakao/README.md#라이선스) | [README 「사전 검수 절차」](../../assets/brand/kakao/README.md#사전-검수-절차) |
| LINE | [README 「공식 BI URL」](../../assets/brand/line/README.md#공식-bi-url) | [README 「라이선스」](../../assets/brand/line/README.md#라이선스) | [README 「사전 검수 절차」](../../assets/brand/line/README.md#사전-검수-절차) |
| Naver | [README 「공식 BI URL」](../../assets/brand/naver/README.md#공식-bi-url) | [README 「라이선스」](../../assets/brand/naver/README.md#라이선스) | [README 「사전 검수 절차」](../../assets/brand/naver/README.md#사전-검수-절차) |

- Naver 는 회사 브랜드 색(`#03C75A`)과 로그인 버튼 색(`#03A94D`)이 다르다. 버튼은 NAVER ID
  로그인 BI 페이지의 `#03A94D` 를 쓴다 — 제3자 출처에서 `#03C75A` 가 보여도 버튼 색으로 쓰지
  않는다.
- 사전 검수 신청 절차를 공식 페이지가 따로 두지 않는 자산은 README 에 그렇게 적고, 가이드
  조항을 지키는 것으로 갈음한다. 공식 페이지에 신청 절차가 새로 생기면 README 의
  `## 사전 검수 절차` 를 고친다.

## freshness 갱신

자산마다 [받은 날 · 만든 날](#받은-날--만든-날) 표의 날짜에서 1년이 지나면 공식 페이지를
다시 확인한다.

1. 그 자산 README 의 `## 공식 BI URL` · `## 자산 다운로드 URL` 페이지를 다시 방문한다.
2. 그림이 바뀌었으면 [자산 다운로드](#자산-다운로드) 순서대로 자산 · `LICENSE.txt` · README 를
   갱신한다. 바뀌지 않았으면 받은 날 표의 날짜만 고친다.
3. 공식 페이지의 제공 형식(파일 형식 · 테마 · 언어 · 크기 변형)이 그 README 의 자산 설명과
   같은지 본다. 다르면 README 의 `## 미포함 변형 추가 절차` 와 디렉토리 구조 절을 지금 형식에
   맞게 고친다.
4. 그림을 바꿨으면 golden 을 다시 만든다:
   `fvm flutter test --update-goldens test/features/auth/presentation/_widgets/branded_social_button_golden_test.dart`.
   바뀐 PNG 를 눈으로 비교해 버튼 색 · 크기가 의도대로인지 본다. iOS golden(`*_ios.png`)은
   저장소에 두지 않는다.
5. `LICENSE.txt` 의 원문 조항이 바뀌었으면 조항을 검토한 뒤 반영한다.

그림을 다시 옮기는 방법은 자산마다 다르다:

- Facebook — Brand Asset Pack 의 `Logo/Primary Logo/Facebook_Logo_Primary.ai` 에서 vector
  path 2개(파란 원 + 흰 'f')를 옮겨 `btn_signin_icon.svg` 를 만든다.
- LINE — `LINE_Login_Button_Image.zip` 의 PSD 안 vector smart-object(`벡터 고급 개체.ai`)를
  다시 옮기고, `git diff` 로 path 가 바뀌었는지 본다. Usage Guidelines 원문이 바뀌었으면
  `LICENSE.txt` 발췌를 고친다. LINE 이 BI 갱신을 알리면(Usage Guidelines Section 4.16)
  1년을 기다리지 않고 바로 갱신한다.
- Google — 그 README 의 「만드는 절차」 · 「다시 만들 때의 확인」 절을 따른다.
- Apple — 그 README 의 「자산 다운로드 URL」 절에 적힌 대로 공식 웹 로그인 스크립트의 `medium`
  로고 객체를 좌표 그대로 옮긴다.

## 받은 날 · 만든 날

| 자산 | 받은 날 · 만든 날 | 확인한 공식 페이지 |
|---|---|---|
| Apple 로고(`apple/{black_logo,white_logo}/btn_signin_icon.svg`) | 2026-10-12 공식 웹 로그인 스크립트를 받아 `medium` path 를 옮김 | https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/1/en_US/appleid.auth.js · https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple |
| Google 로고(`google/g.png` · `2.0x` · `3.0x` · `4.0x`) | 2026-10-12 공식 묶음을 받아 PNG 4장을 만듦 · 확인한 가이드 본문 끝 표기 `Last updated 2026-07-07 UTC` | https://developers.google.com/static/identity/images/signin-assets.zip · https://developers.google.com/identity/branding-guidelines |
| Facebook 로고(`facebook/btn_signin_icon.svg`) | 2026-05-13 받음(Facebook Brand Asset Pack ZIP) · 다음 확인 2027-05-13 | https://www.meta.com/brand/resources/facebook/logo/ |
| Kakao 로고(`kakao/btn_signin_icon.svg`) | 2026-05-09 받음(로그인 버튼 리소스 PSD ZIP) | https://developers.kakao.com/tool/resource/login · https://developers.kakao.com/docs/ko/kakaologin/design-guide |
| Naver 로고(`naver/btn_signin_icon.svg`) | 2026-05-09 받음(NAVER ID 로그인 BI 디자인 가이드 자료) | https://developers.naver.com/docs/login/bi/bi.md |
| LINE 로고(`line/btn_signin_icon.svg`) | 2026-05-19 받음(LINE Login Button Image ZIP · Usage Guidelines 원문 발췌) | https://developers.line.biz/en/docs/line-login/login-button/ · https://terms2.line.me/LINE_Developers_Guidelines_for_Login_Button |
| Google Sans 글꼴(`assets/fonts/googlesans/GoogleSans-Latin-wght.ttf`) | 2026-10-12 원본 가변 파일 `GoogleSans[GRAD,opsz,wght].ttf` 를 받아 라틴 subset 을 만듦 | https://github.com/google/fonts/tree/main/ofl/googlesans |
| Roboto 글꼴(`assets/fonts/roboto/Roboto-VariableFont_wdth_wght.ttf`) | 2026-05-16 받음(가변 파일 그대로) | https://github.com/google/fonts/tree/main/ofl/roboto |
| 시험 글꼴 subset(`assets/test_fonts/NotoSansCJKKR-Regular-Subset.otf` · `NotoSansCJKJP-Regular-Subset.otf`) | 2026-09-26 KR · JP 를 만듦 · JP 를 마지막으로 다시 만든 날 2026-10-03 | 원본 = Android Studio 동봉 AOSP 시스템 폰트 `NotoSansCJK-Regular.ttc` · https://github.com/notofonts/noto-cjk |
| 시험 글꼴 라이선스 사본(`assets/test_fonts/NotoSansCJK_LICENSE.txt`) | upstream 마지막 변경 커밋 `a99a4354c68964f6bfac488d01010b1fb6d9178a`(2022-03-20) 의 원문 사본 | https://raw.githubusercontent.com/notofonts/noto-cjk/main/Sans/LICENSE |

## 시험 글꼴 subset 다시 만들기

`assets/test_fonts/` 의 `NotoSansCJKKR-Regular-Subset.otf` · `NotoSansCJKJP-Regular-Subset.otf` 는
AOSP 시스템 폰트 `NotoSansCJK-Regular.ttc`(Android Studio `plugins/design-tools/resources/layoutlib/data/fonts/`
동봉)에서 ko · ja golden 이 쓰는 글자만 남긴 subset 이다. `app_ja.arb` 에 subset 에 없는 한자가
더해지면 ja golden 에 tofu 가 보인다 — 그때 JP 파일을 다시 만든다. 한글은 완성형 전 음절을 담아
다시 만들지 않는다.

스크립트는 `scripts/subset_cjk.py` 다. `lib/l10n/app_{ko,ja}.arb` 를 읽고 `assets/test_fonts/` 에
쓰므로 저장소 루트에서 돌린다. 원본 파일의 sha256 이 스크립트에 고정한 값과 다르면 아무것도 쓰지 않고
멈춘다.

```bash
uv venv /tmp/ftenv && uv pip install --python /tmp/ftenv/bin/python fonttools==4.66.0
/tmp/ftenv/bin/python -X utf8 scripts/subset_cjk.py "<NotoSansCJK-Regular.ttc 경로>"
```

- 도구: fonttools 4.66.0. `recalcTimestamp=False` 라 같은 입력으로 두 번 만들면 결과가 byte 단위로 같다(`cmp`).
- subset 옵션: `layout_features=['*']` · `name_IDs=['*']` · `name_languages=['*']` · `notdef_outline=True` ·
  variable 축(`wght`) 유지.
- 확인: 두 subset 파일로 렌더한 그림이 원본 face 추출본(subset 전)으로 렌더한 그림과 byte 단위로 같은지
  `cmp` 로 본다.
- 다시 만든 뒤: `assets/test_fonts/README.md` 「글리프 범위 · 해시」 표의 cmap 수 · 크기 · sha256 과 위
  [받은 날 · 만든 날](#받은-날--만든-날) 표의 만든 날을 고친다.

## 회귀 가드

자산 · README 를 바꾼 뒤 아래를 돌린다.

```bash
fvm flutter test --no-pub test/features/auth/presentation/_widgets/ test/docs test/release/public_artifacts_test.dart
```

| 시험 파일 | 지키는 것 |
|---|---|
| `test/features/auth/presentation/_widgets/brand_assets_lint_test.dart` | `kPlaceholderProviders` 가 비어 있음 · 자산 디렉토리에 `.placeholder` 가 없음 · 여섯 README 의 7개 제목 |
| `test/features/auth/presentation/_widgets/brand_label_whitelist_test.dart` | ARB 의 로그인 버튼 문구 ↔ 공식 가이드 문구 |
| `test/features/auth/presentation/_widgets/branded_social_button_golden_test.dart` | 버튼 6개 × 밝기 2 × 플랫폼 2 의 그림(허용 오차 0) |
| `test/features/auth/presentation/_widgets/brand_button_assets_test.dart` | 자산 · 글꼴 파일의 sha256 · 번들 선언 · Google · Apple 자산 디렉토리의 추적 파일 집합(T-177-ASSET-12) |
| `test/features/auth/presentation/_widgets/docs_compliance_lint_test.dart` | Facebook · Google · Kakao · Naver 디렉토리의 `LICENSE.txt` · `README.md` 동시 존재 · Facebook README 의 `sign_in_button` 언급과 7개 제목 · `facebook/facebook_login.png` 가 없음 |
| `test/release/public_artifacts_test.dart` | 추적되는 자산 라이선스 파일 목록 = 루트 `LICENSE` 제3자 절 경로 목록(T-174-ART-03) |
| `test/docs/` | README 의 사용자 문서 금지 패턴 0(T-21-DOCS-02) · 링크 · 앵커가 풀림(T-21-LINK-02) |

golden 이 실패하면 `--update-goldens` 로 다시 만들고 PNG 차이를 본 뒤에만 커밋한다.
