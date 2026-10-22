# LINE Brand Asset

LINE Login 버튼의 로고 자산이다. LINE 공식 버튼 이미지 묶음의 심볼을 SVG 1장으로
싣고, 버튼 바탕 · 라벨은 `BrandedSocialButton` 의 공통 골격이 그린다(배경 `#06C755`).

## 공식 BI URL
https://developers.line.biz/en/docs/line-login/login-button/ (LINE Developers >
LINE Login > LINE Login button design guidelines)

**Usage Guidelines (원문 출처):**
https://terms2.line.me/LINE_Developers_Guidelines_for_Login_Button (Enacted:
12 01, 2014, operator: LY Corporation)

## 자산 다운로드 URL
https://vos.line-scdn.net/line-developers/docs/media/line-login/login-button/LINE_Login_Button_Image.zip
(LINE Login Button Image.zip — Android drawable / iOS 1x~3x × 32dp~44dp /
Desktop 1x~2x × 20dp~32dp~44dp PSD + PNG 일괄 패키지).

킷은 PSD 안의 vector smart-object (`벡터 고급 개체.ai`, PDF native 94×88 pt) 만
옮겨 `btn_signin_icon.svg` 1개로 싣는다. 언어별 라벨이 그림에 들어 있는 PNG 는
싣지 않는다 — 라벨은 ARB 키 `authLineSignIn` 으로 앱이 그린다.

## 다운로드 일자
받은 날은 [브랜드 자산 갱신 — 받은 날 · 만든 날](../../../docs/maintainer/brand-assets.md#받은-날--만든-날) 표에 적는다.

## 라이선스
LINE Branding License — `LICENSE.txt` 의 원문 발췌 참조. Usage Guidelines
for the LINE Login Button (terms2.line.me, Enacted 12 01, 2014). 핵심:
  - Section 4.3.2 색상 alteration 금지 (#06C755 보존)
  - Section 4.3.1 aspect ratio modification 금지 (47:44 비율 유지)
  - Section 4.4 padding 의무 (LINE Icon Speech Bubble 폭 이상)
  - Section 4.5 Isolation Zone 의무
  - Section 4.7 logo/icon 단독 사용 금지
  - Section 4.16 BI 가 갱신되면 따라 갱신할 의무
  - Section 9 일본 법 / 도쿄지방법원 전속 관할

## 사전 검수 절차
LINE Developers Console (https://developers.line.biz/console/) 에는 로고 사용의
사전 검수 신청 절차가 없다 — Section 4.3 의 의무를 직접 지킨다. 단, **Section
4.6.3 / 4.14** 위반 (false impression of endorsement) 이면 LINE 이 사후 시정을
요구할 수 있다. 앱 출시 전에 하는 LINE 쪽 확인(email permission · 비즈니스
인증)은 [직접 하는 일 — 로그인 수단 검수 · 인증](../../../docs/guide.md#로그인-수단-검수--인증)
에 있다.

## 미포함 변형 추가 절차
LINE design guideline 은 Login button text 를 19 언어 (en/ja/ko/de/es/fr/id/it/ms/
pt-BR/pt-PT/ru/th/tr/vi/zh-CN/zh-TW + α) 로 준다. 킷의 ARB 는 ko · en · ja 의
`authLineSignIn` 을 담는다. 언어를 더하려면:
  1. LINE 공식 design guideline 의 "Login button text" 표 (long / short) 에서
     그 언어의 문구를 그대로 가져온다.
  2. `lib/l10n/app_{locale}.arb` 의 `authLineSignIn` 키에 그 문구를 넣는다
     (자산 변경 0).
  3. `BrandedSocialButton` 의 공통 골격 (LINE 스킨) 은 바꾸지 않는다 — ARB 키만
     더하면 그 언어의 버튼이 그려진다.

state variant (Hover / Press / Disabled) 의 색 원문 spec 은
`LICENSE.txt` 의 design guidelines Color 표에 있다. `BrandedSocialButton` 의
공통 골격 (LINE 스킨) 은 그 표의 state 색을 따로 그리지 않는다 — 비활성은 여섯
버튼 공통으로 버튼 전체를 투명도 0.38 (`kBrandButtonDisabledOpacity`) 로 그리고,
눌림 · hover 는 `InkWell` 의 기본 표시다.

## 자산 freshness 갱신 빈도
1년마다 공식 페이지(https://developers.line.biz/en/docs/line-login/login-button/)와
Usage Guidelines(https://terms2.line.me/LINE_Developers_Guidelines_for_Login_Button)를
다시 확인한다 — 절차는 [브랜드 자산 갱신 — freshness 갱신](../../../docs/maintainer/brand-assets.md#freshness-갱신)
에 있다. Section 4.16 에 따라 LINE 이 BI 갱신을 알리면 1년을 기다리지 않고 바로
갱신한다.

## 디렉토리 구조
```
assets/brand/line/
├── btn_signin_icon.svg   (vector symbol, viewBox 0 0 47 44, fill=currentColor)
├── LICENSE.txt           (LINE Usage Guidelines + design guidelines 원문 발췌)
└── README.md             (이 파일)
```

로고는 디렉토리 바로 아래 한 장이고, 언어 · 밝기별 하위 디렉토리는 없다.

## 주의
- wikipedia / seeklogo / 블로그 같은 제3자 출처의 그림 · 색은 쓰지 않는다 —
  공식 BI 페이지 원문만 쓴다.
- 로고를 직접 그려 만들지 않는다 — LINE 공식 PSD 의 vector smart-object 에서
  옮긴 그림만 쓴다.
- `btn_signin_icon.svg` 의 viewBox `0 0 47 44` + `fill="currentColor"` 를 그대로
  둔다 — 색은 `BrandedSocialButton` 이 그릴 때 정한다. SVG 를 손으로 고치지
  않는다 — 바꿀 때는 PSD 에서 다시 옮긴다.
