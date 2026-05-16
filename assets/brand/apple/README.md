# Apple Brand Asset — Apple Sign-in JS API SVG verbatim

Phase 13.3 Wave 4 Step 3 (2026-05-16) — SDK 위제 → 자체 render 전환 + Apple
Sign-in JS API 의 inline SVG verbatim 채택.

## 공식 BI URL

- https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple
- https://developer.apple.com/design/resources/ (Apple Design Resources)

## 자산 다운로드 URL

- **최종 자산 출처** (Step 3 채택): https://id.apple.com/IDMSEmailVetting/static/siwaDemo-{hash}.js
- Apple Sign-in JS API runtime asset 의 `R` 객체 (locale-agnostic logo path
  size variants — small/medium/large)
- `small` variant 채택: `R.small = { height: 44, width: 24, logoWidth: 12,
  path: "M12.2337..." }` — Apple Button generator
  (account.apple.com/signinwithapple/button) 의 default size
- **폐기된 자산 출처** (Step 2 → Step 3 supersede): Apple Design Resources DMG
  (`Logo-Sign-in-with-Apple.dmg` from developer.apple.com/design/resources/)
  의 Logo-Only SVG (viewBox 56×56) — visible logo 비율이 Apple Button
  generator 외관과 미매칭. DMG 자산 ≠ Button API 자산 (다른 용도).

**자산 변형 0** — Apple Sign-in JS API 의 path coordinates 와 viewBox 좌표
verbatim. 추출 후 변형 없이 그대로 사용:
- viewBox: `"6 0 12 44"` (i = (width-logoWidth)/2 = 6, x origin)
- path: `R.small.path` 전체 verbatim
- fill: `#000000` (light variant) / `#FFFFFF` (dark variant) — wrapper bg 와
  일치 시 visible logo 만 표시

## Apple HIG mandate 부합

| HIG mandate | 본 자산 부합 |
|---|---|
| `logo.height = button.height` (필수) | ✓ render height = spec.height (48dp) |
| `logo.aspectRatio = 1:1` (필수) | ✓ visible Apple logo path 자체 ~1:1 aspect |
| `logo.padding = artwork 자체 padding` + "Don't add vertical padding" | ✓ viewBox "6 0 12 44" 자체 padding (logoWidth 12 + canvas width 24 의 비율) |
| `colorMode = black or white only` (필수) | ✓ Black variant (light) / White variant (dark) |
| 자산 변형 금지 ("Never crop" + "never create a custom Apple logo") | ✓ path 좌표 변경 0 + viewBox 변경 0 |

## 라이선스

**Apple Sign-in JS API 의 inline SVG 추출 + 재사용**:
- Apple 의 Sign-in with Apple Web SDK 가 Apple Sign-in 버튼 외관 강제 위해
  공개적으로 제공하는 자산 — HIG compliance 범위 내 사용
- Apple HIG: "Display a Sign in with Apple button on a non-Apple platform"
  허용 — Web SDK 의 button 외관 mirror 가 정확한 compliance path
- 자산 변형 0 + Apple Sign-in 버튼 단독 사용 (다른 UI 요소에 미사용)

**Apple SF Pro Font 미배포** (`assets/fonts/inter/README.md` 참조):
- Apple Font Software License Agreement §2.B "may not embed the Apple Font"
  위반 회피
- iOS/macOS 환경: system 'SF Pro Text' 자동 사용 (Apple OS license 의 일부)
- Android/Linux/Windows: Inter Medium/Regular (SIL OFL 1.1) fallback

## 다운로드 일자

2026-05-16 (Apple Sign-in JS API JS bundle fetch + R['small'].path verbatim
추출 + SVG 작성).

## 사전 검수 절차

1. Apple HIG (developer.apple.com/design/human-interface-guidelines/sign-in-with-apple)
   verbatim 부합 검증 (logo aspectRatio + color mode + 변형 금지).
2. Apple Sign-in JS API JS bundle 의 `R['small'].path` 와 본 SVG 의 path
   문자열 정확 일치 검증.
3. Button API generator (account.apple.com/signinwithapple/button) 의 light/
   dark variant 외관과 시각 비교 + 사용자 sign-off.

## 미포함 변형 추가 절차

1. Apple Sign-in JS API 의 R 객체에서 새 size variant (medium/large) path
   추출.
2. viewBox + canvas width/height 정확 변경 (R 의 size variant 별 spec).
3. `_renderAppleButton` 의 logoWidth + middleMargin + fontSize 비율 재계산
   (Button API verbatim spec).
4. 회귀 가드 신규 + golden 재생성 + 시각 sign-off.

## 자산 freshness 갱신 빈도

Apple Button API 의 JS bundle hash 변경 시 — Apple 의 brand refresh / spec
변경 추적 의무. JS bundle URL 의 `siwaDemo-{hash}.js` 의 hash 부분이 변경되면
재 fetch + path/spec 비교 + 변경 있을 시 자산 + spec 갱신.

## locale 라벨

`STEP2-apple-LOCALE-REFERENCE.md` 참조 — Apple Button API 의 40 locale × 3
variants (sign-in / sign-up / continue) verbatim. starter kit 의 현재 ARB
(en/ko/ja) 는 Apple verbatim 정확 매칭 ✓.

## 주의

- `lib/features/auth/presentation/_widgets/branded_social_button.dart` 의
  `_renderAppleButton` 함수가 본 자산을 `SvgPicture.asset(width: 13,
  height: spec.height)` 으로 render.
- Button API verbatim spec 의 hardcoded 정량값 (logoWidth 13 / middleMargin
  9 / fontSize 20 / letterSpacing -0.44) 은 본 자산 (R['small']) + button.height
  48 조합 기준. button.height 변경 시 재계산 의무.
- font fallback: iOS/macOS = system 'SF Pro Text' / Android/Linux/Windows =
  asset Inter Regular w400.
