// Phase 13.1 Plan 13.1-08 — caller refactor 회귀 가드.
//
// **갱신 의도 (D-13.1-05-CASCADE acceptance):**
// - Plan 13.1-05 의 sealed BrandSpec 마이그레이션 + Plan 13.1-07 자상 commit +
//   Plan 13.1-08 caller refactor 결과를 종합 검증한다.
// - Apple/Google/Naver 분기는 BrandedSocialButton 의 named factory 위임 검증
//   (Buttons.* enum 검증 폐기 — Buttons.{apple,googleDark,...} 는 Phase 13.1
//   에서 사용하지 않음).
// - Facebook 만 sign_in_button (Buttons.facebookNew) 잔존 (R12 acceptance).
// - Kakao 6 deferred RED → GREEN 전환 (자상 PNG + BrandedSocialButton 위임).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_in_button/sign_in_button.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'package:flutter_starter_kit/core/auth/auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/branded_social_button.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/social_button.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

/// 테스트용 fake [AuthStrategy].
///
/// 생성자가 `const` — 모든 필드가 `final` 이다. 단, `onSignIn` closure 인자를
/// 받는 invocation site 에서는 closure literal 이 const expression 이 아니므로
/// `const _FakeStrategy(...)` 호출은 사용하지 않는다 (Dart 언어 제약).
class _FakeStrategy extends AuthStrategy {
  const _FakeStrategy(
    this._providerId,
    this._labelKey,
    this._iconAsset, {
    this.onSignIn,
  }) : super();

  final String _providerId;
  final String _labelKey;
  final String _iconAsset;
  final Future<void> Function(WidgetRef ref)? onSignIn;

  @override
  String get providerId => _providerId;
  @override
  String get labelKey => _labelKey;
  @override
  String get iconAsset => _iconAsset;

  @override
  Future<void> signIn(WidgetRef ref) async {
    if (onSignIn != null) {
      await onSignIn!(ref);
    }
  }
}

/// 영문 로케일 + light theme 으로 [SocialButton] 을 pump 하는 helper.
///
/// [locale] 인자로 ko/ja 로케일 회귀도 가능 (Phase 12 — Kakao 라벨 검증).
Widget _wrap(
  Widget child, {
  Brightness brightness = Brightness.light,
  Locale locale = const Locale('en'),
}) {
  return ProviderScope(
    child: MaterialApp(
      theme: brightness == Brightness.dark
          ? AppTheme.dark()
          : AppTheme.light(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

/// 좁은 시뮬레이터 surface 로 pump — 자상 placeholder 의 native size 가 큰
/// 기본 800x600 viewport 에서 발생하는 Row overflow 회피.
///
/// `tester.view.physicalSize` 는 deprecated 경로라 본 helper 는
/// `binding.setSurfaceSize` 를 사용한다. 모바일 280~674dp 범위 내 360dp 가
/// starter-kit 의 전형적 Pixel 수준 폭이다.
Future<void> _pumpWithMobileViewport(
  WidgetTester tester,
  Widget child,
) async {
  // iPhone 14 Pro 표준 폭 (393dp) + 약간 여유 — Google 자상 + 라벨 Row 가
  // 360dp 에서는 ~25px overflow 발생. 마진 포함 412dp 채택.
  await tester.binding.setSurfaceSize(const Size(412, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(child);
}

void main() {
  group('SocialButton — provider 별 BrandedSocialButton 위임 (Plan 13.1-08)', () {
    testWidgets(
      'Google 분기 (light) → BrandedSocialButton.google + GoogleSpec.theme=light',
      (tester) async {
        const strategy = _FakeStrategy(
          kProviderIdGoogle,
          'authGoogleSignIn',
          'google',
        );
        await _pumpWithMobileViewport(
          tester,
          _wrap(const SocialButton(strategy: strategy, isDisabled: false)),
        );
        await tester.pumpAndSettle();

        // sign_in_button `Buttons` enum 사용 폐기 — SignInButton 미렌더.
        expect(find.byType(SignInButton), findsNothing);
        // BrandedSocialButton 위임.
        final btn = tester.widget<BrandedSocialButton>(
          find.byType(BrandedSocialButton),
        );
        expect(btn.spec, isA<GoogleSpec>());
        expect((btn.spec as GoogleSpec).theme, GoogleTheme.light);
      },
    );

    testWidgets(
      'Google 분기 (dark) → GoogleSpec.theme=dark',
      (tester) async {
        const strategy = _FakeStrategy(
          kProviderIdGoogle,
          'authGoogleSignIn',
          'google',
        );
        await _pumpWithMobileViewport(
          tester,
          _wrap(
            const SocialButton(strategy: strategy, isDisabled: false),
            brightness: Brightness.dark,
          ),
        );
        await tester.pumpAndSettle();

        final btn = tester.widget<BrandedSocialButton>(
          find.byType(BrandedSocialButton),
        );
        expect((btn.spec as GoogleSpec).theme, GoogleTheme.dark);
      },
    );

    testWidgets(
      'Apple 분기 (light) → BrandedSocialButton.apple + AppleSpec '
      '+ SignInWithAppleButtonStyle.black',
      (tester) async {
        const strategy = _FakeStrategy(
          kProviderIdApple,
          'authAppleSignIn',
          'apple',
        );
        await _pumpWithMobileViewport(
          tester,
          _wrap(const SocialButton(strategy: strategy, isDisabled: false)),
        );
        await tester.pumpAndSettle();

        // sign_in_button `Buttons` enum 사용 폐기 — SignInButton 미렌더.
        expect(find.byType(SignInButton), findsNothing);
        // BrandedSocialButton 위임 + AppleSpec + style.black.
        final btn = tester.widget<BrandedSocialButton>(
          find.byType(BrandedSocialButton),
        );
        expect(btn.spec, isA<AppleSpec>());
        expect(btn.appleStyle, SignInWithAppleButtonStyle.black);
        // Apple SDK 위제 렌더 검증.
        expect(find.byType(SignInWithAppleButton), findsOneWidget);
      },
    );

    testWidgets(
      'Apple 분기 (dark) → SignInWithAppleButtonStyle.white',
      (tester) async {
        const strategy = _FakeStrategy(
          kProviderIdApple,
          'authAppleSignIn',
          'apple',
        );
        await _pumpWithMobileViewport(
          tester,
          _wrap(
            const SocialButton(strategy: strategy, isDisabled: false),
            brightness: Brightness.dark,
          ),
        );
        await tester.pumpAndSettle();

        final btn = tester.widget<BrandedSocialButton>(
          find.byType(BrandedSocialButton),
        );
        expect(btn.appleStyle, SignInWithAppleButtonStyle.white);
      },
    );

    testWidgets(
      'Facebook 분기 → Buttons.facebookNew 잔존 (R12 acceptance)',
      (tester) async {
        const strategy = _FakeStrategy(
          kProviderIdFacebook,
          'authFacebookSignIn',
          'facebook',
        );
        await _pumpWithMobileViewport(
          tester,
          _wrap(
            const SocialButton(strategy: strategy, isDisabled: false),
            brightness: Brightness.dark,
          ),
        );
        await tester.pumpAndSettle();

        // Facebook 만 sign_in_button SignInButton 사용.
        final btn = tester.widget<SignInButton>(find.byType(SignInButton));
        expect(btn.button, Buttons.facebookNew);
        // BrandedSocialButton 도달 안 함.
        expect(find.byType(BrandedSocialButton), findsNothing);
      },
    );

    testWidgets(
      'Unknown providerId → UnsupportedError',
      (tester) async {
        const strategy = _FakeStrategy(
          'unknown.com',
          'authUnknown',
          'unknown',
        );
        // build 안에서 throw → flutter test framework 의 default error handler
        // 가 capture 후 [tester.takeException] 으로 surface 한다.
        await _pumpWithMobileViewport(
          tester,
          _wrap(const SocialButton(strategy: strategy, isDisabled: false)),
        );
        final ex = tester.takeException();
        expect(ex, isA<UnsupportedError>());
      },
    );
  });

  group('SocialButton 위임 invariant (D-11/D-12)', () {
    testWidgets('isDisabled=false + tap → strategy.signIn 호출', (tester) async {
      var signInCallCount = 0;
      final strategy = _FakeStrategy(
        kProviderIdGoogle,
        'authGoogleSignIn',
        'google',
        onSignIn: (ref) async {
          signInCallCount += 1;
        },
      );
      await _pumpWithMobileViewport(
        tester,
        _wrap(SocialButton(strategy: strategy, isDisabled: false)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SocialButton));
      await tester.pump();
      expect(
        signInCallCount,
        1,
        reason: 'tap 시 strategy.signIn(ref) 가 1회 호출되어야 한다',
      );
    });

    testWidgets('isDisabled=true + tap → strategy.signIn 호출 안 됨', (tester) async {
      var signInCallCount = 0;
      final strategy = _FakeStrategy(
        kProviderIdGoogle,
        'authGoogleSignIn',
        'google',
        onSignIn: (ref) async {
          signInCallCount += 1;
        },
      );
      await _pumpWithMobileViewport(
        tester,
        _wrap(SocialButton(strategy: strategy, isDisabled: true)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SocialButton));
      await tester.pump();
      expect(signInCallCount, 0, reason: 'isDisabled=true 면 위임 호출 안 됨');
    });
  });

  // Phase 12 D-25 옵션 A → Phase 13.1 sealed BrandSpec.
  // Kakao 분기는 sign_in_button 미지원으로 BrandedSocialButton.kakao 위임.
  // Plan 13.1-07 commit 후 자상 = `kakao_login_large_wide.png` (PNG).
  group('SocialButton Kakao 분기 (Plan 13.1-08 cascade GREEN)', () {
    /// branded_social_button.dart 의 private 상수 _kKakaoYellow 와 동일 리터럴.
    /// 단일 진실원은 `branded_social_button.dart`.
    const expectedKakaoYellow = Color(0xFFFEE500);

    testWidgets(
      'Kakao providerId → SignInButton 미사용 + Material 노란 배경 + InkWell 자식',
      (tester) async {
        const strategy = _FakeStrategy(
          kProviderIdKakao,
          'authKakaoSignIn',
          'kakao',
        );
        await _pumpWithMobileViewport(
          tester,
          _wrap(const SocialButton(strategy: strategy, isDisabled: false)),
        );
        await tester.pumpAndSettle();

        // sign_in_button 패키지의 SignInButton 미사용 (Kakao 미지원).
        expect(find.byType(SignInButton), findsNothing);
        // BrandedSocialButton 위임 + KakaoSpec.
        final btn = tester.widget<BrandedSocialButton>(
          find.byType(BrandedSocialButton),
        );
        expect(btn.spec, isA<KakaoSpec>());

        // _kKakaoYellow 배경 Material 1개 이상 매치.
        final yellowMaterials = tester
            .widgetList<Material>(find.byType(Material))
            .where((m) => m.color == expectedKakaoYellow)
            .toList();
        expect(
          yellowMaterials,
          isNotEmpty,
          reason: '_kKakaoYellow (#FEE500) 배경 Material 이 1개 이상 존재해야 한다',
        );

        // InkWell 자식 — Material + InkWell 조합으로 button semantics 확보.
        expect(find.byType(InkWell), findsAtLeastNWidgets(1));
      },
    );

    testWidgets(
      'Kakao 라벨 — en 로케일에서 "Continue with Kakao" 표시 (D-29 ARB)',
      (tester) async {
        const strategy = _FakeStrategy(
          kProviderIdKakao,
          'authKakaoSignIn',
          'kakao',
        );
        await _pumpWithMobileViewport(
          tester,
          _wrap(const SocialButton(strategy: strategy, isDisabled: false)),
        );
        await tester.pumpAndSettle();

        expect(find.text('Continue with Kakao'), findsOneWidget);
      },
    );

    testWidgets(
      'Kakao 라벨 — ko 로케일에서 "카카오 로그인" 표시 (D-29 ARB)',
      (tester) async {
        const strategy = _FakeStrategy(
          kProviderIdKakao,
          'authKakaoSignIn',
          'kakao',
        );
        await _pumpWithMobileViewport(
          tester,
          _wrap(
            const SocialButton(strategy: strategy, isDisabled: false),
            locale: const Locale('ko'),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('카카오 로그인'), findsOneWidget);
      },
    );

    testWidgets(
      'Kakao 분기 — Image.asset 으로 PNG 자상 로드 (Plan 13.1-07 자상 commit 결과)',
      (tester) async {
        const strategy = _FakeStrategy(
          kProviderIdKakao,
          'authKakaoSignIn',
          'kakao',
        );
        await _pumpWithMobileViewport(
          tester,
          _wrap(const SocialButton(strategy: strategy, isDisabled: false)),
        );
        await tester.pumpAndSettle();

        // SVG 미사용 (Plan 13.1-05 sealed refactor — Kakao 자상 PNG 마이그레이션).
        expect(find.byType(SvgPicture), findsNothing);
        // PNG 자상 1개 (KakaoSpec.assetType == AssetType.png).
        expect(find.byType(Image), findsOneWidget);
      },
    );

    testWidgets(
      'Kakao 분기 + isDisabled=true → InkWell.onTap == null (탭 무효)',
      (tester) async {
        const strategy = _FakeStrategy(
          kProviderIdKakao,
          'authKakaoSignIn',
          'kakao',
        );
        await _pumpWithMobileViewport(
          tester,
          _wrap(const SocialButton(strategy: strategy, isDisabled: true)),
        );
        await tester.pumpAndSettle();

        // SocialButton 내부의 첫 InkWell — onTap 이 null 이어야 함.
        final inkWells = tester
            .widgetList<InkWell>(find.byType(InkWell))
            .toList();
        expect(inkWells, isNotEmpty);
        // 첫 번째 InkWell (Kakao 버튼 본체) 의 onTap 검증.
        expect(
          inkWells.first.onTap,
          isNull,
          reason: 'isDisabled=true 면 InkWell.onTap == null 로 탭 무효화',
        );
      },
    );

    testWidgets(
      'Kakao 분기 + isDisabled=false + tap → strategy.signIn 위임 1회',
      (tester) async {
        var signInCallCount = 0;
        final strategy = _FakeStrategy(
          kProviderIdKakao,
          'authKakaoSignIn',
          'kakao',
          onSignIn: (ref) async {
            signInCallCount += 1;
          },
        );
        await _pumpWithMobileViewport(
          tester,
          _wrap(SocialButton(strategy: strategy, isDisabled: false)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(SocialButton));
        await tester.pump();
        expect(
          signInCallCount,
          1,
          reason: 'Kakao 분기 tap 시 strategy.signIn(ref) 가 1회 호출되어야 한다',
        );
      },
    );
  });

  // Phase 13.1 신규 — Naver 분기 회귀 가드 (Plan 13.1-05 NaverTheme 매개변수
  // 추가 + Plan 13.1-07 자상 commit 결과 검증).
  group('SocialButton Naver 분기 (Plan 13.1-08)', () {
    /// branded_social_button.dart 의 private 상수 _kNaverGreen 과 동일 리터럴
    /// (R1 정정 — 0xFF03A94D, NAVER ID 로그인 BI).
    const expectedNaverGreen = Color(0xFF03A94D);

    testWidgets(
      'Naver 분기 (light) → NaverSpec.theme=light + 그린 배경',
      (tester) async {
        const strategy = _FakeStrategy(
          kProviderIdNaver,
          'authNaverSignIn',
          'naver',
        );
        await _pumpWithMobileViewport(
          tester,
          _wrap(const SocialButton(strategy: strategy, isDisabled: false)),
        );
        await tester.pumpAndSettle();

        expect(find.byType(SignInButton), findsNothing);
        final btn = tester.widget<BrandedSocialButton>(
          find.byType(BrandedSocialButton),
        );
        expect(btn.spec, isA<NaverSpec>());
        expect((btn.spec as NaverSpec).theme, NaverTheme.light);

        final greenMaterials = tester
            .widgetList<Material>(find.byType(Material))
            .where((m) => m.color == expectedNaverGreen)
            .toList();
        expect(
          greenMaterials,
          isNotEmpty,
          reason: '_kNaverGreen (#03A94D) 배경 Material 이 1개 이상 존재해야 한다',
        );
      },
    );

    testWidgets(
      'Naver 분기 (dark) → NaverSpec.theme=dark',
      (tester) async {
        const strategy = _FakeStrategy(
          kProviderIdNaver,
          'authNaverSignIn',
          'naver',
        );
        await _pumpWithMobileViewport(
          tester,
          _wrap(
            const SocialButton(strategy: strategy, isDisabled: false),
            brightness: Brightness.dark,
          ),
        );
        await tester.pumpAndSettle();

        final btn = tester.widget<BrandedSocialButton>(
          find.byType(BrandedSocialButton),
        );
        expect((btn.spec as NaverSpec).theme, NaverTheme.dark);
      },
    );
  });
}
