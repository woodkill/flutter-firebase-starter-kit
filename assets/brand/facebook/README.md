# Facebook (Meta) Brand Asset

Phase 13.2 — Meta 공식 자상으로 마이그 (옵션 A pivot 채택, Apple
`SignInWithAppleButton` 패턴 mirror). Phase 13.1 까지 `sign_in_button: ^4.1.0`
community package 의 `Buttons.facebookNew` (community-rendered, Meta 공식 BI
아님) 위제 사용 → Phase 13.2 Wave 1 부터 Meta Brand Resource Center 의 Primary
Logo PNG + 자체 render (`_renderFacebookButton` 함수) 로 전환.

본 starter-kit 의 `BrandedSocialButton.facebook(...)` factory (Plan 13.2-04
도입) 는 Apple `SignInWithAppleButton` 패턴 mirror — 별도 wide 자상 통째
buttons 패턴 (Kakao/Naver/Google 의 wide PNG 통째 로드) 비채택. 사유는 본
파일 §"미포함 변형 추가 절차" 참조.

## 공식 BI URL

- 1순위 (라벨/색/변형 금지 verbatim): `https://developers.facebook.com/docs/facebook-login/userexperience/`
- 2순위 (자상 다운 + 라이선스 verbatim): `https://www.meta.com/brand/resources/facebook/logo/`
- 보조 (Login Button 위제 사이즈 매트릭스 + JS SDK 동적 위젯 명세): `https://developers.facebook.com/docs/facebook-login/web/login-button`

공식 색 verbatim (Meta Login UX Guide):
- Hex `#1877F2`
- RGB `R = 24, G = 119, B = 242`

라벨 옵션 verbatim (2종, Meta Login UX Guide):
- `'Continue with Facebook'`
- `'Login with Facebook'`

변형 금지 verbatim (Meta Login UX Guide):
- `DON'T modify the 'f' logo in any way`

## 자산 다운로드 URL

`https://www.meta.com/brand/resources/facebook/logo/` → "Download" 버튼 클릭 →
`Facebook Brand Asset Pack` ZIP 다운 → 압축 해제 후 `Logo/Primary Logo/Facebook_Logo_Primary.png` (54771 bytes) 채택.

ZIP 내 자상 매트릭스 (Wave 0 사용자 verbatim 확인):

```
Logo/
├── Primary Logo/
│   ├── Facebook_Logo_Primary.ai    (164217 bytes, Adobe Illustrator 원본 — Flutter 비호환)
│   └── Facebook_Logo_Primary.png   (54771 bytes, 2084×2084 square, PNG 8-bit/color RGBA non-interlaced)
└── Secondary Logo/
    ├── Facebook_Logo_Secondary.ai  (153146 bytes, Adobe Illustrator 원본 — Flutter 비호환)
    └── Facebook_Logo_Secondary.png (47324 bytes, 2084×2084 square, 모노크롬 흰 원 + 검정 'f')
```

채택 자상: `Primary Logo/Facebook_Logo_Primary.ai` (PyMuPDF vector path 추출 →
SVG 변환). starter-kit 내 명명: `assets/brand/facebook/btn_signin_icon.svg`
(AI verbatim 2 paths — blue circle `#0866FF` + white 'f').

**Phase 13.3 Wave 4 Step 2 (2026-05-15) supersede:** 이전 Wave 0~3 에서는
PNG 자상 (`assets/brand/facebook/facebook_login.png`, 54771 bytes) 을 채택했
으나 Wave 4 Step 2 에서 AI 원본 vector path 추출 → SVG 전환. PNG 는
2026-05-17 Phase 13.3 code review CR-01 정정 commit 에서 `git rm` 으로 폐기
(stale asset 이 production bundle 에 동봉되어 Meta brand license 혼동 위험
회피). 회귀 가드: `docs_compliance_lint_test.dart` 의 "CR-01 SENTINEL"
test 가 PNG 파일 부재를 lint 시점에 검증.

## 다운로드 일자

2026-05-13 (Phase 13.2 Plan 01 Wave 0 Task 1 commit 시점, `b2213e0`)

## 라이선스

Meta Brand Resource Center License (verbatim 단락은 `LICENSE.txt` 참조).

verbatim 요약 (`https://www.meta.com/brand/resources/facebook/logo/`):

> Meta's trademarks are owned by Meta and may only be used as provided in these
> guidelines or with Meta's permission.

본 starter-kit 의 사용 케이스는 일반 OAuth 로그인 버튼 ("as provided in these
guidelines" 범위 내) 이며, Meta's permission 별도 요청 의무 case (예: 마케팅
자료 prominent 배치) 미해당. 자세한 사용 의무 사항·변형 금지·사전 검수 절차
verbatim 은 `LICENSE.txt` 동봉 단락 참조.

## 사전 검수 절차

Meta Brand Resource Center (`https://www.meta.com/brand/resources/`) 가 별도
신청 form 명시 부재 (Wave 0 사용자 verbatim 확인 — ZIP 내 `LICENSE.txt` /
`Terms.txt` / `Brand_Guidelines.pdf` 동등 문서 부재). 사용자 책임으로 다음
정책 사전 검토 의무:

1. Meta Brand Resource Center 이용 약관 (페이지 acceptance checkbox 동의)
2. 자상 사용 가이드라인 (`https://www.meta.com/brand/resources/facebook/logo/` +
   `https://developers.facebook.com/docs/facebook-login/userexperience/`) 의
   변형 금지·라벨 옵션·공식 색 보존 verbatim 단락
3. Meta's permission 의무 케이스 (예: 마케팅 자료 prominent 배치) 해당 여부
   판단 — 해당 시 Meta Brand 팀 사전 문의 의무

본 starter-kit 의 default 사용 (로그인 화면 OAuth 진입 버튼) 은 "as provided in
these guidelines" 범위 내 verified.

## 미포함 변형 추가 절차

본 starter-kit 은 Meta Brand Asset Pack ZIP 의 자상 매트릭스 중 **Primary
Logo PNG 1개** 만 동봉. 채택 차원 (Wave 0 lock `13.2-WAVE0-LOCK.md` 일관):

- Form: Primary (파란 `#1877F2` 원형 배경 + 흰 'f') 단독 채택
- Theme: 미분기 (D-94 Kakao 패턴 — `FacebookSpec` theme 필드 부재). Primary 의
  `#1877F2` 배경이 Theme.brightness light/dark 양쪽에서 가시성 보장 — 외부
  wrapper (`_renderFacebookButton`) 의 white/dark background + grey/lighter
  outline 으로 분기 대응.
- Locale: 미분기 (D-96 Google 패턴). 'f' 마크 단독 (Roboto/Helvetica Latin
  라벨 baked-in 0) → 언어 중립. 라벨 텍스트 (`'Continue with Facebook'` /
  `'Facebook 으로 시작하기'` / `'Facebookでログイン'`) 는
  `Text(AppLocalizations.of(context).authFacebookSignIn)` 외부 layer 단독
  책임 (Phase 13.1 D-82 ARB 라벨 패턴 일관).
- Format: PNG only (D-95 = `AssetType.png` — Meta 의 logo pack 은 AI + PNG
  제공, SVG 미제공이라 PNG 채택. `Image.asset` 표준 로드).

미포함 변형 신규 도입 시 절차:

1. Meta Brand Resource Center 재방문
   (`https://www.meta.com/brand/resources/facebook/logo/`) → 갱신된 자상 매트릭스
   확인 (1년 freshness 정책 일관)
2. 신규 자상이 `D-94 Kakao 패턴` 또는 `D-96 Google 패턴` 범위를 벗어나는 경우
   (예: locale-aware 자상 제공 시작, Secondary Logo 도 동봉 필요 시) → 별
   phase 의 retroactive cycle 로 처리 (Phase 13.1 D-A~D-L 패턴, Phase 14
   LINE 도입 mirror)
3. Meta 가 자상 변형 (색상 / 비율 / 회전) 금지 명시 — 신규 도입 자상은 ZIP
   콘텐츠 그대로 (rename 만 허용) commit 의무

미포함 variants:

- **Secondary Logo** (흰 원형 + 검정 'f', 모노크롬 인쇄/단색 환경 전용) —
  Flutter mobile 컬러 환경에서는 Primary 단독으로 충분, 미동봉
- **AI 원본 파일** (`*.ai`) — Flutter `Image.asset` 호환 불가, 미동봉
- **Login Button baked-in 자상** (예: "Continue with Facebook" 라벨 포함
  wide PNG) — Meta 가 `developers.facebook.com/docs/facebook-login/web/login-button`
  에서 JS SDK 동적 위젯 (`<div class="fb-login-button"
  data-button-type="continue_with">`) + 사이즈 매트릭스 (Small `20 × 200` /
  Medium `28 × 200-320` / Large `40 × 240-400`) 만 명시 — 다운로드 가능
  PNG/SVG 0건 verified. Flutter mobile 환경 (Dart VM, Skia render) 내 JS SDK
  위젯 임베드 불가 → starter-kit 이 Apple `SignInWithAppleButton` 패턴 mirror
  로 자체 render (Plan 13.2-04 의 `_renderFacebookButton` 함수, 옵션 A pivot
  채택)

## 자산 freshness 갱신 빈도

1년 권장 — `다운로드 일자` (2026-05-13) 1년 경과 시점 (2027-05-13 권장 검토
시점) 에 `https://www.meta.com/brand/resources/facebook/logo/` 재방문 + 자상
갱신 여부 확인 의무. Phase 13.1 `docs/manual.md` 의 "Brand Asset Management"
단락 3단계 (1) 자산 다운로드 (2) `LICENSE.txt` 동봉 (3) 1년 검토 패턴 mirror.

## 디렉토리 구조 (Phase 13.2 Wave 1 commit 후)

```
assets/brand/facebook/
├── facebook_login.png  (Primary Logo PNG, 54771 bytes, 2084×2084 square)
├── LICENSE.txt         (Meta verbatim 라이선스 + 변형 금지 + 자상 enumerate + freshness 1년)
└── README.md           (본 파일, 7필드 schema — Phase 13.1 Naver/Kakao mirror)
```

자상 디렉토리 분기 차원 0 (light/dark 미분기, ko/en 미분기) — D-94 + D-96
lock 영향. `pubspec.yaml` 의 assets 단락 등록은 `- assets/brand/facebook/` 단일
leaf (재귀 미지원, Plan 13.1-08 Rule 2 verbatim 일관).

## 주의

- Phase 13.1 까지 사용한 `sign_in_button` community package 위제 (`Buttons.facebookNew`) 는 Phase 13.2 Wave 2 에서 코드 path 폐기 + Wave 5 에서
  pubspec 의존성 단락 제거 예정 (R8/R9/R10 acceptance 단일 진실원).
- `assets/brand/facebook/facebook_login.png` 콘텐츠 변경 금지 — Meta 변형 금지
  verbatim (`DON'T modify the 'f' logo in any way`) 일관. rename (디렉토리
  구조에서 차원 분리 위해) 만 허용.
- `_renderFacebookButton` 함수 (Plan 13.2-04 도입) 가 `Image.asset(..., width: 18, height: 18)` 로 18dp icon 슬롯 로드 — `Image.asset` 의 `color` /
  `colorBlendMode` 적용 금지 (자상 색상 변형 회귀, Phase 13.1 Kakao RESEARCH
  §Pitfall 7 mirror).
- Theme.brightness 자동 분기는 외부 wrapper (`_renderFacebookButton` 본문)
  단독 책임 — `Image.asset` 자체는 색상 invariant (Primary 의 `#1877F2` +
  흰 'f' 그대로 render).
