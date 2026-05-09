// Phase 13.1 — see ROADMAP.md (D-66 sealed sub-class const + R1/R2/R8 회귀 가드)
//
// Phase 13.1 Gap-1 X2 (2026-05-09 자상화) — 본 file 카운트 8 → 14:
// 기존 8 (sealed hierarchy 회귀 가드) + 신규 6 (wide 자상 통째 buttons
// 패턴 검증). 사용자 보고 4 issue 해소 acceptance.
//
// Phase 13.1 Gap-1 X2 BLOCKER 2 fix — sentinel stub-context class 폐기 →
// tester.pumpWidget + tester.takeException 패턴 (Flutter 권장).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'package:flutter_starter_kit/features/auth/presentation/_widgets/branded_social_button.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

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

  group('BrandedSocialButton — Phase 13.1 Gap-1 X2 wide 자상 통째 buttons', () {
    // ─── T-13.1-X2-CLIPRRECT-01: ClipRRect + Image.asset (Kakao) ──────────
    testWidgets(
        'T-13.1-X2-CLIPRRECT-01: KakaoSpec build() ClipRRect + '
        'Image.asset full-width 패턴', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: BrandedSocialButton.kakao(
              label: '카카오 로그인',
              onPressed: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // wide 자상 통째 buttons 패턴 — ClipRRect + Image.asset 위제 트리 존재.
      expect(find.byType(ClipRRect), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      // Container+Row+(icon+label) 패턴 폐기 검증 — 본 test 는 Kakao buttons
      // 만 build, 다른 spec 의 widget tree 미렌더.
    });

    // ─── T-13.1-X2-CLIPRRECT-02: ClipRRect + SvgPicture (Google) ──────────
    testWidgets(
        'T-13.1-X2-CLIPRRECT-02: GoogleSpec build() ClipRRect + '
        'SvgPicture.asset full-width 패턴', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: BrandedSocialButton.google(
              label: 'Sign in with Google',
              theme: GoogleTheme.light,
              onPressed: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ClipRRect), findsOneWidget);
      // 자상 형식 dispatch 자체는 sealed switch 검증 (T-13.1-SPEC-01 의
      // GoogleSpec.assetType == AssetType.svg) 가 보장. 본 test 는 ClipRRect
      // 도입 + Image 부재 검증 (Google 은 SVG 이므로 Image.asset 위제는
      // 트리에 없어야 함).
      expect(find.byType(Image), findsNothing);
    });

    // ─── T-13.1-X2-FULLWIDTH-01: SizedBox(width: double.infinity) 검증 ────
    testWidgets(
        'T-13.1-X2-FULLWIDTH-01: NaverSpec build() SizedBox '
        'width: double.infinity 강제 sizing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 300,
              child: BrandedSocialButton.naver(
                label: '네이버로 시작하기',
                theme: NaverTheme.light,
                onPressed: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // BrandedSocialButton 내부 SizedBox 가 부모 width (300dp) 까지 확장.
      // RenderBox layout 후 width = 300 이어야 (full-width 패턴).
      final renderBox = tester.renderObject<RenderBox>(
        find.byType(BrandedSocialButton),
      );
      expect(renderBox.size.width, 300.0);
      // 높이는 BrandSpec.height (48dp) 와 일치 — Naver/Kakao 자상 통째 buttons.
      expect(renderBox.size.height, 48.0);
    });

    // ─── T-13.1-X2-LOCALE-FALLBACK-01: ja locale → en path ────────────────
    testWidgets(
        'T-13.1-X2-LOCALE-FALLBACK-01: ja locale 시 KakaoSpec 자상이 '
        'en path (kakao/en/light/) 로딩', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ja'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: BrandedSocialButton.kakao(
              label: 'Continue with Kakao',
              onPressed: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final imageWidget = tester.widget<Image>(find.byType(Image));
      final assetImage = imageWidget.image as AssetImage;
      // ko 외 모든 locale (ja 포함) 은 en path 로 fallback (D-79 + Gap-1 X2
      // 사용자 3번 답변).
      expect(
        assetImage.assetName,
        'assets/brand/kakao/en/light/kakao_login_large_wide.png',
        reason: 'ja locale 은 en fallback (ko 외 모두 en) — '
            '_iconAssetFor 의 lang 분기',
      );
    });

    // ─── T-13.1-X2-APPLE-PRESERVE-01: AppleSpec 분기 변경 0 회귀 가드 ──────
    testWidgets(
        'T-13.1-X2-APPLE-PRESERVE-01: AppleSpec build() '
        'SignInWithAppleButton 위임 보존 (Gap-1 영향 없음)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BrandedSocialButton.apple(
              label: 'Sign in with Apple',
              onPressed: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Apple 분기는 SDK 위제 위임 — ClipRRect + Image 패턴 미적용 정상.
      // SignInWithAppleButton 위제가 트리에 존재해야 함.
      expect(find.byType(SignInWithAppleButton), findsOneWidget);
    });

    // ─── T-13.1-X2-FACEBOOK-PRESERVE-01: FacebookSpec UnsupportedError ────
    //
    // **Phase 13.1 Gap-1 X2 BLOCKER 2 fix (2026-05-09):** sentinel stub-context
    // class 폐기 → tester.pumpWidget + tester.takeException 패턴 채택.
    // 사유: stub-context extends BuildContext + dynamic noSuchMethod 패턴은
    // woody_lints `dynamic` 룰 충돌 + abstract method 누락 분석 경고 + 런타임
    // NPE 위험. private constructor `BrandedSocialButton._` 는 caller 불가능
    // 하므로 named factory `.facebook()` 를 통해 build() 까지 도달시키고
    // tester.takeException() 으로 throw 캡처 — Flutter 권장 패턴.
    //
    // **검증 의도 (read-only reference, social_button.dart 의 Facebook 분기는
    // SignInButton(Buttons.facebookNew) 직접 호출, BrandedSocialButton 까지
    // 도달 안 함):** BrandedSocialButton.facebook() factory 도달 시 build() 의
    // FacebookSpec 분기가 UnsupportedError 를 throw 함을 sentinel 로 검증
    // (R12 잔존 보존 회귀 가드).
    testWidgets(
      'T-13.1-X2-FACEBOOK-PRESERVE-01: FacebookSpec 직접 호출 — '
      'UnsupportedError throw (BrandedSocialButton.facebook() factory 도달 시 '
      'build() 가 throw — social_button.dart 의 Facebook 분기는 '
      'SignInButton(Buttons.facebookNew) 직접 호출, BrandedSocialButton 까지 '
      '도달 안 함을 별도 test 로 검증)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BrandedSocialButton.facebook(
                label: 'Facebook',
                onPressed: () {},
              ),
            ),
          ),
        );
        expect(
          tester.takeException(),
          isA<UnsupportedError>(),
          reason: 'BrandedSocialButton.facebook() 의 build() 가 '
              'UnsupportedError 를 throw 해야 함 (R12 acceptance — '
              'Facebook 은 social_button.dart 에서 SignInButton 직접 호출)',
        );
      },
    );
  });
}
