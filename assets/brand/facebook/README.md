# Facebook Brand Asset (community package retain)

Phase 13.1 — Facebook 로그인 버튼은 `sign_in_button: ^4.1.0` community
package 의 `Buttons.facebookNew` (community-rendered, Meta 공식 BI 아님) 사용. Phase 18 Brand Center 권한 확보 후 공식 자산으로 교체 예정.

## 공식 BI URL
https://developers.facebook.com/docs/facebook-login/userexperience/

## 자산 다운로드 URL
Phase 18 — Meta Brand Center 권한 확보 후 공식 자상 다운 절차 추가 예정.

## 다운로드 일자
N/A (Phase 18 까지 N/A)

## 라이선스
현재 — `sign_in_button` 패키지 MIT (community-rendered Buttons.facebookNew 위제). Phase 18 — Meta Brand Center License (TBD).

## 사전 검수 절차
N/A (Phase 18 — 권한 확보 후 명시).

## 미포함 변형 추가 절차
Phase 18 — 공식 자상 도입 후 명시.

## 자산 freshness 갱신 빈도
Phase 18 까지 N/A.

## 주의
- `pubspec.yaml` 의 `sign_in_button: ^4.1.0` 보존 의무 (R12 acceptance + SPEC.md Boundaries 'sign_in_button 패키지 폐기 — Facebook 자상 미확인 상태에서 위험').
- `lib/features/auth/presentation/_widgets/social_button.dart` 의 Facebook 분기 가 `SignInButton(Buttons.facebookNew, ...)` 직접 호출.
- Phase 18 마이그 시 1) Meta Brand Center 자상 다운 + 2) `BrandedSocialButton.facebook()` factory 도입 + 3) `social_button.dart` 의 Facebook 분기 전환 + 4) `sign_in_button` 패키지 제거.
