# LINE Brand Asset

Phase 14 — LINE Login 버튼 공식 자상 (D-LINE-08/12/13). Phase 13.1 sentinel
(`.placeholder`) 폐기 후 Symbol SVG + LICENSE.txt 동봉. Phase 13.3 Wave 4 패턴
(symbol SVG + ARB 자체 render) mirror.

## 공식 BI URL
https://developers.line.biz/en/docs/line-login/login-button/ (LINE Developers >
LINE Login > LINE Login button design guidelines)

**Usage Guidelines (verbatim source):**
https://terms2.line.me/LINE_Developers_Guidelines_for_Login_Button (Enacted:
12 01, 2014, operator: LY Corporation)

## 자산 다운로드 URL
https://vos.line-scdn.net/line-developers/docs/media/line-login/login-button/LINE_Login_Button_Image.zip
(LINE Login Button Image.zip — Android drawable / iOS 1x~3x × 32dp~44dp /
Desktop 1x~2x × 20dp~32dp~44dp PSD + PNG 일괄 패키지).

본 starter-kit 은 PSD 내 vector smart-object (`벡터 고급 개체.ai`, PDF native
94×88 pt) 만 추출하여 `btn_signin_icon.svg` 1개 동봉. 19 언어 baked-in 라벨 PNG
는 미포함 — ARB 신규 키 (`authLineSignIn`) 기반 자체 render 채택 (Phase 13.3
Wave 4 패턴 mirror).

## 다운로드 일자
2026-05-19 (Plan 14-02 checkpoint commit)

## 라이선스
LINE Branding License — `LICENSE.txt` 의 verbatim 발췌 참조. Usage Guidelines
for the LINE Login Button (terms2.line.me, Enacted 12 01, 2014). 핵심:
  - Section 4.3.2 색상 alteration 금지 (#06C755 보존)
  - Section 4.3.1 aspect ratio modification 금지 (47:44 비율 유지)
  - Section 4.4 padding 의무 (LINE Icon Speech Bubble 폭 이상)
  - Section 4.5 Isolation Zone 의무
  - Section 4.7 logo/icon 단독 사용 금지
  - Section 4.16 BI 갱신 시 update 의무 (1년 freshness 정책)
  - Section 9 일본 법 / 도쿄지방법원 전속 관할

## 사전 검수 절차
LINE Developer Console (https://developers.line.biz/console/) 의 Channel >
LINE Login provider 설정에 BI 자상 사용 자체 검수 절차 미명시 — Section 4.3
의무 만 self-enforce. 단, **Section 4.6.3 / 4.14** 위반 (false impression of
endorsement) 시 사후 시정 조치 가능성 있음. 자세한 절차는
`docs/manual.md` 의 D-LINE-22a (1) "LINE Console > Channel > Linking 사전 검수"
단락 참조 (Phase 14 Plan 14-07 commit 예정).

## 미포함 변형 추가 절차
19 언어 (en/ja/ko/de/es/fr/id/it/ms/pt-BR/pt-PT/ru/th/tr/vi/zh-CN/zh-TW + α)
의 Login button text 는 Phase 14 Plan 14-03 에서 ARB 신규 키 (`authLineSignIn`)
로 verbatim 동봉. 신규 언어 추가 시:
  1. LINE 공식 design guideline 의 "Login button text" 매트릭스 (long / short)
     verbatim 인용 (`14-LINE-LOCALE-REFERENCE.md` 갱신).
  2. `lib/l10n/app_{locale}.arb` 의 `authLineSignIn` 키에 verbatim string 추가
     (자상 변경 0).
  3. `_renderLineButton` widget spec 변경 0 — ARB 신규 키만 추가하면 19 언어
     확장 자동 (Phase 13.3 Wave 4 패턴 invariant).

state variant (Hover / Press / Disabled) 의 색 verbatim spec 은
`LICENSE.txt` 의 design guidelines Color 표 + Phase 14 Plan 14-06 의
`_renderLineButton` widget spec 에 hardcoded.

## 자산 freshness 갱신 빈도
1년 권장. `다운로드 일자` 1년 경과 시:
  1. https://developers.line.biz/en/docs/line-login/login-button/ 재방문 +
     LINE Login Button Image.zip 갱신 여부 확인.
  2. PSD vector smart-object (`벡터 고급 개체.ai`) re-extract → `git diff`
     로 vector path 변경 확인. 차이 있을 시 `btn_signin_icon.svg` 재추출.
  3. https://terms2.line.me/LINE_Developers_Guidelines_for_Login_Button
     verbatim 변경 확인 → 차이 있을 시 `LICENSE.txt` 갱신.
  4. Section 4.16 의 update 의무는 LINE 측 통보 시 즉시 갱신 의무 — freshness
     주기 1년과 별도로 ad-hoc 갱신 가능.

## 디렉토리 구조 (Phase 14 Plan 14-02 이후)
```
assets/brand/line/
├── btn_signin_icon.svg   (D-LINE-08/12 vector symbol, viewBox 0 0 47 44, fill=currentColor)
├── LICENSE.txt           (LINE Usage Guidelines + design guidelines verbatim 발췌)
└── README.md             (본 파일)
```

**Phase 13.1 sentinel 해제 (Plan 14-02 commit):**
- `assets/brand/line/.placeholder` git rm — D-LINE-13 invariant 충족.
- `lib/features/auth/presentation/_widgets/_brand_assets.dart` 의
  `kPlaceholderProviders` const list 에서 `'line'` 토큰 제거 → `['wechat']`
  만 잔존 (Phase 16 WeChat 진입 시 동일 패턴 재적용 예정).

## 주의
- third-party 출처 (wikipedia / seeklogo / 블로그 등) 채택 절대 금지
  (memory `feedback_official_bi_verification`).
- hand-crafted SVG 자체 생성 절대 금지 — LINE 공식 PSD vector smart-object
  추출 결과만 채택 (memory `feedback_psd_ai_vector_extraction` + Phase 13.3
  Wave 1.C 패턴).
- `btn_signin_icon.svg` 의 viewBox `0 0 47 44` + `fill="currentColor"` 는
  Wave 4 ColorFilter.srcIn 동작 의무 (BrandedSocialButton color enforcement).
  사용자가 svg 수동 편집 금지 — 재추출 워크플로우 (PATTERNS.md Wave 1.C) 만
  허용.
