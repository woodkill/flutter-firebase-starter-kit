# LINE Brand Asset (Phase 14 자상 commit 대기)

Phase 13.1 sentinel — LINE 로그인 버튼 자상은 Phase 14 (LINE Login) 진입 시 commit 의무. 본 디렉토리에 `.placeholder` 빈 파일 + README 만 사전 정비.

## 공식 BI URL
https://developers.line.biz/en/docs/line-login/login-button/

## 자산 다운로드 URL
https://developers.line.biz/en/docs/line-login/login-button/ (PNG 다중 해상도 + PSD, 19 언어)

## 다운로드 일자
N/A (Phase 14 진입 시 갱신)

## 라이선스
LINE Branding License (LICENSE.txt — Phase 14 commit 시 동봉).

## 사전 검수 절차
사용자 책임 — LINE Developer Console 자상 사용 가이드 직접 확인 의무.

## 미포함 변형 추가 절차
Phase 14 (LINE Login) 진입 시 19 언어 중 starter-kit 채택 변형 결정 + 자상 commit.

## 자산 freshness 갱신 빈도
1년 권장 — Phase 14 진입 후 적용.

## Phase 14 진입 절차
1. LINE Developer Console (https://developers.line.biz/console/) 자상 다운
2. `assets/brand/line/{언어}/{light,dark}/line_login_*.png` + LICENSE.txt commit
3. `git rm assets/brand/line/.placeholder` (sentinel 해제)
4. `lib/features/auth/presentation/_widgets/_brand_assets.dart` 의 `kPlaceholderProviders` list 에서 'line' 제거
5. `fvm flutter test test/features/auth/presentation/_widgets/brand_assets_lint_test.dart` PASS 검증
