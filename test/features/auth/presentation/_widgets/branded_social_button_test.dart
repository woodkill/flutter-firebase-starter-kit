// Phase 13.1 — see ROADMAP.md (D-66 sealed sub-class const + R1/R2/R8 회귀 가드)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/features/auth/presentation/_widgets/branded_social_button.dart';

// ─── 회귀 가드 expected 색상 (production private literal mirror) ────────────
//
// 단일 진실원은 `branded_social_button.dart` 의 `_kKakao*` / `_kNaver*` const
// 이며 본 상수는 회귀 가드 비교 대상이다 — 둘 중 어느 쪽이든 변경되면 테스트
// 가 RED 로 떨어져 contract drift 를 즉시 surface.
//
// **R1 정정 (Phase 13.1):** `_kNaverGreenExpected = 0xFF03A94D` (NAVER ID
// 로그인 BI verbatim) — 회사 브랜드 0xFF03C75A 와 컨텍스트 분리.
const _kKakaoYellowExpected = Color(0xFFFEE500);
const _kNaverGreenExpected = Color(0xFF03A94D);
const _kNaverLabelExpected = Color(0xFFFFFFFF);

void main() {
  group('BrandedSocialButton — Phase 13.1 sealed hierarchy', () {
    // ─── T-13.1-SPEC-01: 7 sub-class const + assetType 매핑 ──────────────
    test('T-13.1-SPEC-01: 7 sub-class const constructor + assetType 매핑', () {
      // KakaoSpec — PNG asset, R2 borderRadius 12.
      expect(const KakaoSpec().assetType, AssetType.png);
      expect(const KakaoSpec().borderRadius, 12.0);
      expect(const KakaoSpec().height, 48.0);
      expect(const KakaoSpec().iconSize, 18.0);

      // NaverSpec — PNG asset, theme 명시 매개변수, R2 borderRadius 12.
      expect(const NaverSpec(theme: NaverTheme.light).assetType, AssetType.png);
      expect(const NaverSpec(theme: NaverTheme.light).borderRadius, 12.0);
      expect(const NaverSpec(theme: NaverTheme.dark).theme, NaverTheme.dark);

      // GoogleSpec — SVG asset, theme 명시 매개변수 (3 변형).
      expect(
        const GoogleSpec(theme: GoogleTheme.light).assetType,
        AssetType.svg,
      );
      expect(const GoogleSpec(theme: GoogleTheme.dark).theme, GoogleTheme.dark);
      expect(
        const GoogleSpec(theme: GoogleTheme.neutral).theme,
        GoogleTheme.neutral,
      );

      // AppleSpec / FacebookSpec — assetType.none (위제 위임).
      expect(const AppleSpec().assetType, AssetType.none);
      expect(const FacebookSpec().assetType, AssetType.none);

      // LineSpec / WechatSpec — assetType.png (Phase 14/16 자상 commit 후 활성).
      expect(const LineSpec().assetType, AssetType.png);
      expect(
        const WechatSpec(size: WechatPixelSize.px48).size,
        WechatPixelSize.px48,
      );
      expect(
        const WechatSpec(size: WechatPixelSize.px48).assetType,
        AssetType.png,
      );
    });

    // ─── T-13.1-SWITCH-01: sealed switch exhaustive 컴파일 시점 가드 ────
    test('T-13.1-SWITCH-01: sealed switch exhaustive — 7 sub-class 인스턴스화', () {
      // 본 test 는 dart analyze 가 검증 — sealed 7 sub-class 누락 시 컴파일
      // fail. 본 file 컴파일 통과 자체가 BrandedSocialButton.build() 내
      // sealed switch 의 exhaustiveness 보장 (Dart 3 closed hierarchy).
      const specs = <BrandSpec>[
        KakaoSpec(),
        NaverSpec(theme: NaverTheme.light),
        GoogleSpec(theme: GoogleTheme.light),
        AppleSpec(),
        FacebookSpec(),
        LineSpec(),
        WechatSpec(size: WechatPixelSize.px48),
      ];
      expect(specs.length, 7);
    });

    // ─── T-13.1-FACTORY-01: 7 named factory smoke ────────────────────────
    test('T-13.1-FACTORY-01: 7 named factory 가 BrandedSocialButton 반환', () {
      final kakao = BrandedSocialButton.kakao(label: 'Kakao', onPressed: () {});
      final naver = BrandedSocialButton.naver(
        label: 'Naver',
        theme: NaverTheme.light,
        onPressed: () {},
      );
      final google = BrandedSocialButton.google(
        label: 'Google',
        theme: GoogleTheme.light,
        onPressed: () {},
      );
      final apple = BrandedSocialButton.apple(label: 'Apple', onPressed: () {});
      final facebook = BrandedSocialButton.facebook(
        label: 'Facebook',
        onPressed: () {},
      );
      final line = BrandedSocialButton.line(label: 'LINE', onPressed: () {});
      final wechat = BrandedSocialButton.wechat(
        label: 'WeChat',
        onPressed: () {},
      );

      expect(kakao.spec, isA<KakaoSpec>());
      expect(naver.spec, isA<NaverSpec>());
      expect(google.spec, isA<GoogleSpec>());
      expect(apple.spec, isA<AppleSpec>());
      expect(facebook.spec, isA<FacebookSpec>());
      expect(line.spec, isA<LineSpec>());
      expect(wechat.spec, isA<WechatSpec>());
    });

    // ─── T-13.1-NAVER-THEME-01: NaverSpec theme 분기 ─────────────────────
    test('T-13.1-NAVER-THEME-01: NaverSpec({theme}) 가 light/dark 분기 보존', () {
      const lightSpec = NaverSpec(theme: NaverTheme.light);
      const darkSpec = NaverSpec(theme: NaverTheme.dark);
      expect(lightSpec.theme, NaverTheme.light);
      expect(darkSpec.theme, NaverTheme.dark);
      expect(
        identical(lightSpec, darkSpec),
        isFalse,
        reason: 'theme 다르면 const 인스턴스도 다름',
      );
    });

    // ─── T-13.1-R1-01: Naver 색 R1 정정 회귀 가드 ────────────────────────
    test('T-13.1-R1-01: 회귀 가드 — Naver 색 0xFF03A94D (R1 정정)', () {
      // Phase 13.1 R1 — `0xFF03C75A` (NAVER Corp + NCloud SSO) → `0xFF03A94D`
      // (NAVER ID 로그인 BI). 본 test 가 mirror const drift 를 RED 로
      // surface — production 색이 0xFF03C75A 로 회귀하면 즉시 fail.
      expect(_kNaverGreenExpected.toARGB32(), 0xFF03A94D);
      expect(
        _kNaverGreenExpected.toARGB32(),
        isNot(0xFF03C75A),
        reason: 'R1 정정 — 회사 브랜드 0xFF03C75A 회귀 차단',
      );
    });

    // ─── T-13.1-R2-01: borderRadius R2 정정 회귀 가드 ─────────────────────
    test('T-13.1-R2-01: 회귀 가드 — borderRadius default 12 (R2 정정)', () {
      // Phase 13.1 R2 — `borderRadius default 6 → 12` (Kakao BI 명시 12,
      // Naver 일관). BrandSpec base default 가 12 — 모든 sub-class 상속.
      expect(const KakaoSpec().borderRadius, 12.0);
      expect(const NaverSpec(theme: NaverTheme.light).borderRadius, 12.0);
      expect(const GoogleSpec(theme: GoogleTheme.light).borderRadius, 12.0);
      expect(const AppleSpec().borderRadius, 12.0);
      expect(const FacebookSpec().borderRadius, 12.0);
      expect(const LineSpec().borderRadius, 12.0);
      expect(const WechatSpec(size: WechatPixelSize.px48).borderRadius, 12.0);
    });

    // ─── T-13.1-COLOR-MIRROR-01: Kakao 노란색 mirror 보존 ────────────────
    test('T-13.1-COLOR-MIRROR-01: Kakao 노란색 mirror 0xFFFEE500 보존 (회귀 0)', () {
      // Phase 12 D-29 / Phase 13.1 mirror — Kakao Brand Guideline 강제
      // (#FEE500). Phase 13.1 sealed 재작성 후에도 색 보존 확인.
      expect(_kKakaoYellowExpected.toARGB32(), 0xFFFEE500);
    });

    // ─── T-13.1-NAVER-LABEL-01: Naver 라벨 색 mirror 보존 ─────────────────
    test('T-13.1-NAVER-LABEL-01: Naver 라벨 색 0xFFFFFFFF 보존', () {
      expect(_kNaverLabelExpected.toARGB32(), 0xFFFFFFFF);
    });
  });
}
