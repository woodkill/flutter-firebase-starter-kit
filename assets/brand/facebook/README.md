# Facebook (Meta) Brand Asset

Facebook 로그인 버튼의 로고 자산이다. Meta Brand Resource Center 의 Primary Logo
로 만든 SVG 1장을 싣고, 버튼은 `BrandedSocialButton` 의 공통 골격이 그린다.
community package `sign_in_button` 의 `Buttons.facebookNew` (community-rendered,
Meta 공식 BI 아님) 위젯은 쓰지 않는다.

`BrandedSocialButton.facebook(...)` 은 로고 SVG 와 ARB 라벨을 공통 골격으로 그린다 —
라벨이 그림에 들어 있는 wide 버튼 이미지는 쓰지 않는다. 이유는 아래
「미포함 변형 추가 절차」 에 있다.

## 공식 BI URL

- 1순위 (라벨 · 색 · 변형 금지 원문): `https://developers.facebook.com/docs/facebook-login/userexperience/`
- 2순위 (자산 다운로드 + 라이선스 원문): `https://www.meta.com/brand/resources/facebook/logo/`
- 보조 (Login Button 위젯 크기 표 + JS SDK 동적 위젯 명세): `https://developers.facebook.com/docs/facebook-login/web/login-button`

공식 색 원문 (Meta Login UX Guide):
- Hex `#1877F2`
- RGB `R = 24, G = 119, B = 242`

라벨 옵션 원문 (2종, Meta Login UX Guide):
- `'Continue with Facebook'`
- `'Login with Facebook'`

킷의 버튼은 두 번째 문구 `'Login with Facebook'` 을 쓴다. 한국어 · 일본어 문구는
`'Facebook으로 로그인'` · `'Facebookでログイン'` 이다(ARB `authFacebookSignIn`).

변형 금지 원문 (Meta Login UX Guide):
- `DON'T modify the 'f' logo in any way`

## 자산 다운로드 URL

`https://www.meta.com/brand/resources/facebook/logo/` → "Download" 버튼 →
`Facebook Brand Asset Pack` ZIP 을 받아 푼다.

ZIP 의 로고 파일:

```
Logo/
├── Primary Logo/
│   ├── Facebook_Logo_Primary.ai    (164217 bytes, Adobe Illustrator 원본 — Flutter 비호환)
│   └── Facebook_Logo_Primary.png   (54771 bytes, 2084×2084 square, PNG 8-bit/color RGBA non-interlaced)
└── Secondary Logo/
    ├── Facebook_Logo_Secondary.ai  (153146 bytes, Adobe Illustrator 원본 — Flutter 비호환)
    └── Facebook_Logo_Secondary.png (47324 bytes, 2084×2084 square, 모노크롬 흰 원 + 검정 'f')
```

킷의 로고는 `Primary Logo/Facebook_Logo_Primary.ai` 의 vector path 2개(파란 원
`#0866FF` + 흰 'f')를 그대로 옮긴 SVG 다: `assets/brand/facebook/btn_signin_icon.svg`.
이 디렉토리에 PNG 는 두지 않는다.

## 다운로드 일자

받은 날은 [브랜드 자산 갱신 — 받은 날 · 만든 날](../../../docs/maintainer/brand-assets.md#받은-날--만든-날) 표에 적는다.

## 라이선스

Meta Brand Resource Center License (원문 단락은 `LICENSE.txt` 참조).

원문 요약 (`https://www.meta.com/brand/resources/facebook/logo/`):

> Meta's trademarks are owned by Meta and may only be used as provided in these
> guidelines or with Meta's permission.

킷의 사용 방식은 일반 OAuth 로그인 버튼 ("as provided in these guidelines"
범위)이라, 마케팅 자료에 로고를 크게 싣는 것처럼 Meta's permission 을 따로 받아야
하는 경우에 들지 않는다. 사용 의무 · 변형 금지 · 사전 검수 원문은 `LICENSE.txt`
동봉 단락을 본다.
계정 연결 절의 'f' 아이콘 버튼은 로그인 UX 가이드의 'f' 로고 조항과 다르다 — 아래 「아이콘 단독 사용」 절을 본다.

## 사전 검수 절차

Meta Brand Resource Center (`https://www.meta.com/brand/resources/`) 에는 별도
신청 form 이 없다 — Brand Asset Pack ZIP 에도 `LICENSE.txt` / `Terms.txt` /
`Brand_Guidelines.pdf` 같은 약관 문서가 들어 있지 않다. 출시 전에 다음을
직접 확인한다:

1. Meta Brand Resource Center 이용 약관 (페이지의 동의 checkbox)
2. 로고 사용 가이드라인 (`https://www.meta.com/brand/resources/facebook/logo/` +
   `https://developers.facebook.com/docs/facebook-login/userexperience/`) 의
   변형 금지 · 라벨 옵션 · 공식 색 단락
3. Meta's permission 이 필요한 경우 (예: 마케팅 자료에 로고를 크게 배치) 에
   해당하는지 — 해당하면 Meta Brand 팀에 먼저 문의한다

로그인 화면의 로그인 버튼으로만 쓰면 "as provided in these guidelines" 범위다.
로고를 로그인 버튼 밖에서 쓸 때의 확인은 [직접 하는 일 — 소셜 로고 · 브랜드 자산](../../../docs/guide.md#소셜-로고--브랜드-자산)
에 있다.

계정 연결 절의 Facebook 'f' 아이콘 버튼은 검수 전에 [직접 하는 일 — 소셜 로고 · 브랜드 자산](../../../docs/guide.md#소셜-로고--브랜드-자산) 의 「Facebook 검수 전」 대로 글자 버튼 모양으로 바꿀 수 있다.

## 아이콘 단독 사용

- 계정 정보 화면(설정 → 내 계정)의 「계정 연결」 절에 Facebook 이 아직 연결되지 않았을 때만, Facebook 으로 로그인해 계정을 연결하는 원형 아이콘 버튼이 나온다 — 스크린 리더 라벨은 「Facebook 연결」 이다.
- 크기는 지름 `48dp`(`kBrandIconButtonSize`) · 로고 상자 높이 = 지름 × 0.5 = 24dp 다 — 바탕 · 외곽선 · 로고는 로그인 버튼과 같다(밝은 바탕 `#FFFFFF` + 외곽선 `#747775` · 어두운 바탕 `#131314` + 외곽선 `#8E918F` · 로고는 파란 원 + 흰 'f' 그대로).
- Facebook 로그인 가이드(`https://developers.facebook.com/docs/facebook-login/userexperience/` 의 한국어판)는 「적절한 행동 유도(예: 'Facebook으로 계속하기' 또는 'Facebook으로 로그인') 없이 버튼에 'f' 로고를 사용하지 마세요.」 라고 적는다 — 킷의 아이콘 버튼은 이 조항과 다르다.
- Meta 브랜드 리소스 센터 Facebook 로고 페이지(`https://www.meta.com/brand/resources/facebook/logo/`)의 여백(로고 너비 ÷ 4) · 디지털 최소 너비 16px · 외곽선 금지 · 색 바꾸기 금지는 로고 자체에서 지킨다 — 24dp 로고에 필요한 여백 6 보다 원 안 여백 12 가 넓고, 외곽선은 로고가 아니라 원에 있다.
- 글자 버튼 모양으로 바꾸려면 `lib/features/settings/presentation/account_screen.dart` 의 `AccountLinkingSection(leadingGap: true)` 에 `shape: AccountLinkingShape.button` 을 더한다 — Facebook 앱 검수를 신청하기 전에 할 일이다.
- 한 화면에서 맞추느라 다르게 둔 곳은 [직접 하는 일 — 소셜 로고 · 브랜드 자산](../../../docs/guide.md#소셜-로고--브랜드-자산) 의 「알고 둔 가이드와의 차이」 에 있다.

## 미포함 변형 추가 절차

킷은 Meta Brand Asset Pack 의 로고 가운데 **Primary Logo 1개**만 SVG 로 싣는다.

- Form: Primary (파란 원형 배경 + 흰 'f') 하나
- Theme: 로고는 밝기와 무관하게 한 장이다 (`FacebookSpec` 의 로고 경로가 하나다).
  밝기에 따라 바뀌는 것은 스킨 값이다 — `FacebookSpec` 의 배경색 (light `#FFFFFF`
  / dark `#131314`) · 글자색 (`#1F1F1F` / `#E3E3E3`) · 외곽선 색 (`#747775` /
  `#8E918F`).
- Locale: 언어별 파일이 없다. 'f' 마크만 있어 언어와 무관하다. 라벨 텍스트
  (`'Login with Facebook'` / `'Facebook으로 로그인'` / `'Facebookでログイン'`) 는
  `Text(AppLocalizations.of(context).authFacebookSignIn)` 가 따로 그린다.
- Format: SVG 1장 (`btn_signin_icon.svg` — Meta 의 logo pack 은 AI + PNG
  만 주고 SVG 는 없어서 AI 원본의 vector path 로 만든다). `BrandedSocialButton` 의
  공통 골격이 20 × 20 상자에 색 지정 없이 그린다.

다른 변형을 쓰려면:

1. Meta Brand Resource Center (`https://www.meta.com/brand/resources/facebook/logo/`)
   에서 Brand Asset Pack 을 다시 받는다.
2. 받은 로고는 내용을 그대로 둔다 — Meta 가 색 · 비율 · 회전 변형을 금지한다.
   파일 이름만 바꿔 이 디렉토리에 둔다.
3. 하위 디렉토리를 새로 만들면 `pubspec.yaml` 의 assets 에 그 디렉토리를 따로
   등록한다 (디렉토리 등록은 재귀가 아니다).

싣지 않는 변형:

- **Secondary Logo** (흰 원형 + 검정 'f', 모노크롬 인쇄 · 단색 환경 전용) —
  컬러 화면에서는 Primary 하나로 충분하다
- **AI 원본 파일** (`*.ai`) — Flutter `Image.asset` 이 읽지 못한다
- **라벨이 그림에 들어 있는 Login Button 이미지** (예: "Continue with Facebook" 라벨
  포함 wide PNG) — Meta 는 `developers.facebook.com/docs/facebook-login/web/login-button`
  에서 JS SDK 동적 위젯 (`<div class="fb-login-button"
  data-button-type="continue_with">`) + 크기 표 (Small `20 × 200` /
  Medium `28 × 200-320` / Large `40 × 240-400`) 만 주고, 내려받을 수 있는
  PNG · SVG 는 주지 않는다. Flutter 앱에는 JS SDK 위젯을 넣을 수 없어서
  킷이 로고 SVG + ARB 라벨을 `BrandedSocialButton` 의 공통 골격으로 직접 그린다

## 자산 freshness 갱신 빈도

1년마다 공식 페이지(`https://www.meta.com/brand/resources/facebook/logo/`)를 다시
확인한다 — 절차는 [브랜드 자산 갱신 — freshness 갱신](../../../docs/maintainer/brand-assets.md#freshness-갱신)
에 있다.

## 디렉토리 구조

```
assets/brand/facebook/
├── btn_signin_icon.svg (Primary Logo 의 vector path 2개 — 파란 원 + 흰 'f', viewBox 0 0 20 20)
├── LICENSE.txt         (Meta 라이선스 원문 + 변형 금지 + 사전 검수)
└── README.md           (이 파일)
```

언어 · 밝기별 하위 디렉토리는 없다. `pubspec.yaml` 의 assets 에는
`- assets/brand/facebook/` 한 줄로 등록한다.

## 주의

- 킷은 `sign_in_button` 패키지를 의존성으로 두지 않는다 — Facebook 버튼은
  `BrandedSocialButton` 이 그린다.
- `btn_signin_icon.svg` 의 그림을 바꾸지 않는다 — Meta 변형 금지 원문
  (`DON'T modify the 'f' logo in any way`).
- `BrandedSocialButton` 의 공통 골격이 로고를 20dp 상자 (20 × 20) 에 그린다 — 로고에
  색을 덧입히지 않는다 (`FacebookSpec` 의 로고 단색 칠 값이 null 이다). 색 · 모양
  변형 금지.
- 밝기에 따른 차이는 스킨 값 (`FacebookSpec` 의 배경색 · 글자색 · 외곽선 색) 이
  맡는다 — 로고는 두 밝기에서 같은 그림이다 (자산의 파란 원 + 흰 'f' 그대로).
