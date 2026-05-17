# Google Brand Asset

Phase 13.1 — Google Identity Branding Guidelines 공식 SVG 6종.

## 공식 BI URL
https://developers.google.com/identity/branding-guidelines

## 자산 다운로드 URL
https://developers.google.com/identity/branding-guidelines (Light/Dark/Neutral × full button/icon-only — 6 SVG)

## 다운로드 일자
2026-05-09 (Plan 13.1-07 checkpoint commit)

## 라이선스
Google Terms of Service (LICENSE.txt). Plan 13.1-08 에서 LICENSE.txt 동봉.

## 사전 검수 절차
N/A — Google Identity Branding Guidelines 가 사전 검수 신청 부재.

## 미포함 변형 추가 절차
Google Identity Branding Guidelines 가 변형 금지 명시. 신규 변형 도입 시 별 phase.

## 자산 freshness 갱신 빈도
1년 권장.

## 디렉토리 구조 (Phase 13.3 code review IN-03 정정 후)

```
assets/brand/google/
├── btn_signin_icon.svg
├── LICENSE.txt
└── README.md
```

**Phase 13.3 IN-03 정정 (2026-05-17):** Google Identity Branding Guidelines 의
"G" 마크는 theme-independent — light/dark variant 는 button bg + outline +
label color 만 분기, 아이콘 자체는 동일 4-color "G" 단일. 기존 `light/` /
`dark/` 디렉토리 + byte-identical SVG 2개 폐기 → 단일
`assets/brand/google/btn_signin_icon.svg` 로 일원화 (Facebook 의 "single
Primary Logo" 패턴 mirror). theme 분기 책임은 `_renderGoogleButton` 의
bg/label/outline 색 분기로 일관.

**자산 형식 결정 (Plan 13.1-07 retro):** Google 공식 자상은 5차원 매트릭스 (platform × format × theme × shape × label) 로 360+ 파일 제공 (iOS/Android/Web 별 ZIP). 본 starter-kit 은 다음 차원 채택:

- **Platform:** Android (Flutter Material framework default 와 일관, mobile 양쪽 platform 에 어색하지 않음)
- **Format:** SVG (vector, density-free, `flutter_svg` 의존성 이미 있음)
- **Theme:** light / dark / neutral (Plan 가정 일치)
- **Shape:** `rd` (rounded — `BrandedSocialButton.borderRadius=12` 와 일관)
- **Label:** `ctn` (Continue with Google — sign-in + sign-up 포괄, OAuth 첫-로그인 흐름과 일치) + `na` (icon-only 변형)

**Cross-platform 사용 정책:** Google Identity Branding Guidelines 가 platform 일치를 강제하지 않음 — "You can scale the button as needed for different devices" 명시. iOS 앱에서 Android 자상 사용도 라이선스/정책 위반 아님 (LICENSE.txt verbatim 인용).

**공식 ↔ starter-kit 명명 매핑:**
- `android_{light,dark,neutral}_rd_ctn.svg` → `google/{theme}/btn_signin_full.svg`
- `android_{light,dark,neutral}_rd_na.svg` → `google/{theme}/btn_signin_icon.svg`

**미포함 변형:** iOS 자상 (`ios_*_rd_*.svg`), Web 자상, sq shape, SI/SU label, png 형식. Flutter starter-kit 단순성 원칙 + Material framework default 일관성으로 위 6 SVG 만 채택.
