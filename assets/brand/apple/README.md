# Apple Brand Asset (없음 — SDK 위제 위임)

Phase 13.1 — Apple Sign-In 위제는 1st-party `sign_in_with_apple` 패키지의
`SignInWithAppleButton` 위제로 위임 (D-62 / R6). 자상 commit 미발생.

## 공식 BI URL
https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple

## 자산 다운로드 URL
N/A — `sign_in_with_apple` v8.0.0 가 ASAuthorizationController + native iOS 무결성 + Apple HIG 자동 라벨 (ko: `Apple로 로그인`, en: `Sign in with Apple`, ja: `Appleでサインイン`) 처리.

## 다운로드 일자
N/A

## 라이선스
Apple HIG 준수 — `sign_in_with_apple` 패키지 (BSD-3-Clause).

## 사전 검수 절차
N/A

## 미포함 변형 추가 절차
Apple HIG 의 3 변형 (Sign in / Sign up / Continue) 중 starter-kit 은 Sign in 변형만 사용. Sign up / Continue 추가는 별 phase (D-81 + SPEC.md Boundaries).

## 자산 freshness 갱신 빈도
Apple HIG 변경 시 — `sign_in_with_apple` 패키지 메이저 업데이트 추적 의무.

## 주의
- `lib/features/auth/presentation/_widgets/branded_social_button.dart` 의
  `BrandedSocialButton.apple()` factory 가 `SignInWithAppleButton` 위제로 위임.
- `borderRadius` 인수는 `BorderRadius.circular(12)` 형태 의무 (D-72-CLARIFY-2 — int 12 직접 주입 시 컴파일 에러).
- `style: SignInWithAppleButtonStyle.whiteOutlined` (D-G-CLARIFY 정확 표기).
- height 는 SDK 기본값 44 존종 — 외부 SizedBox 래핑 안 함 (D-72-CLARIFY-1).
