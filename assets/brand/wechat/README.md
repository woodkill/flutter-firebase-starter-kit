# WeChat Brand Asset (Phase 16 자상 commit 대기)

Phase 13.1 sentinel — WeChat 로그인 버튼 자상은 Phase 16 (WeChat Login) 진입 시 commit 의무. 본 디렉토리에 `.placeholder` 빈 파일 + README 만 사전 정비.

## 공식 BI URL
https://developers.weixin.qq.com/doc/oplatform/en/Downloads/Design_Resource.html

## 자산 다운로드 URL
https://developers.weixin.qq.com/doc/oplatform/en/Downloads/Design_Resource.html (PNG only — 24/32/48/64px 4 해상도)

## 다운로드 일자
N/A (Phase 16 진입 시 갱신)

## 라이선스
WeChat Brand Guideline (LICENSE.txt — Phase 16 commit 시 동봉).

## 사전 검수 절차
사용자 책임 — WeChat Open Platform 자상 사용 사전 검수 신청 의무 가능 (사용자 직접 확인).

## 미포함 변형 추가 절차
**변형 절대 금지** — WeChat Brand Guideline 명시. 24/32/48/64px 4 해상도 외 다른 사이즈 / 색상 / 비율 변형 금지.

## 자산 freshness 갱신 빈도
1년 권장 — Phase 16 진입 후 적용.

## Phase 16 진입 절차
1. WeChat Open Platform (https://open.weixin.qq.com/) 자상 다운 (4 해상도 PNG)
2. `assets/brand/wechat/{24,32,48,64}/wechat_login.png` + LICENSE.txt commit
3. `git rm assets/brand/wechat/.placeholder`
4. `lib/features/auth/presentation/_widgets/_brand_assets.dart` 의 `kPlaceholderProviders` list 에서 'wechat' 제거
5. `fvm flutter test test/features/auth/presentation/_widgets/brand_assets_lint_test.dart` PASS

## 주의
- WeChat 자상 PNG 만 — SVG / PSD 미제공.
- `BrandedSocialButton.wechat({required WechatPixelSize size, ...})` factory 가 4 해상도 enum 분기.
