import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_in_button/sign_in_button.dart';

import 'package:flutter_starter_kit/core/auth/auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
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

void main() {
  group('SocialButton _resolveButtons (Buttons enum 매핑)', () {
    testWidgets('Google providerId + light → Buttons.google', (tester) async {
      const strategy = _FakeStrategy(
        kProviderIdGoogle,
        'authGoogleSignIn',
        'google',
      );
      await tester.pumpWidget(
        _wrap(const SocialButton(strategy: strategy, isDisabled: false)),
      );
      await tester.pumpAndSettle();

      final btn = tester.widget<SignInButton>(find.byType(SignInButton));
      expect(btn.button, Buttons.google);
    });

    testWidgets('Google providerId + dark → Buttons.googleDark', (
      tester,
    ) async {
      const strategy = _FakeStrategy(
        kProviderIdGoogle,
        'authGoogleSignIn',
        'google',
      );
      await tester.pumpWidget(
        _wrap(
          const SocialButton(strategy: strategy, isDisabled: false),
          brightness: Brightness.dark,
        ),
      );
      await tester.pumpAndSettle();

      final btn = tester.widget<SignInButton>(find.byType(SignInButton));
      expect(btn.button, Buttons.googleDark);
    });

    testWidgets('Apple providerId + light → Buttons.apple', (tester) async {
      const strategy = _FakeStrategy(
        kProviderIdApple,
        'authAppleSignIn',
        'apple',
      );
      await tester.pumpWidget(
        _wrap(const SocialButton(strategy: strategy, isDisabled: false)),
      );
      await tester.pumpAndSettle();

      final btn = tester.widget<SignInButton>(find.byType(SignInButton));
      expect(btn.button, Buttons.apple);
    });

    testWidgets('Apple providerId + dark → Buttons.appleDark', (tester) async {
      const strategy = _FakeStrategy(
        kProviderIdApple,
        'authAppleSignIn',
        'apple',
      );
      await tester.pumpWidget(
        _wrap(
          const SocialButton(strategy: strategy, isDisabled: false),
          brightness: Brightness.dark,
        ),
      );
      await tester.pumpAndSettle();

      final btn = tester.widget<SignInButton>(find.byType(SignInButton));
      expect(btn.button, Buttons.appleDark);
    });

    testWidgets('Facebook providerId → Buttons.facebookNew (다크 분기 없음)', (
      tester,
    ) async {
      const strategy = _FakeStrategy(
        kProviderIdFacebook,
        'authFacebookSignIn',
        'facebook',
      );
      await tester.pumpWidget(
        _wrap(
          const SocialButton(strategy: strategy, isDisabled: false),
          brightness: Brightness.dark,
        ),
      );
      await tester.pumpAndSettle();

      final btn = tester.widget<SignInButton>(find.byType(SignInButton));
      expect(btn.button, Buttons.facebookNew);
    });

    testWidgets('Unknown providerId → UnsupportedError', (tester) async {
      const strategy = _FakeStrategy('unknown.com', 'authUnknown', 'unknown');
      // build 안에서 throw → flutter test framework 의 default error handler
      // 가 capture 후 [tester.takeException] 으로 surface 한다.
      await tester.pumpWidget(
        _wrap(const SocialButton(strategy: strategy, isDisabled: false)),
      );
      final ex = tester.takeException();
      expect(ex, isA<UnsupportedError>());
    });
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
      await tester.pumpWidget(
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
      await tester.pumpWidget(
        _wrap(SocialButton(strategy: strategy, isDisabled: true)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SocialButton));
      await tester.pump();
      expect(signInCallCount, 0, reason: 'isDisabled=true 면 위임 호출 안 됨');
    });
  });

  // Phase 12 D-25 옵션 A — Kakao 분기는 sign_in_button 미지원으로
  // Material+InkWell+SVG 로 직접 그린다. 12-UI-SPEC line 391-437.
  group('SocialButton Kakao 분기 (Phase 12 D-25)', () {
    /// social_button.dart 의 private 상수 _kKakaoYellow 와 동일 리터럴.
    /// 단일 진실원은 lib/features/auth/presentation/_widgets/social_button.dart.
    const expectedKakaoYellow = Color(0xFFFEE500);

    testWidgets(
      'Kakao providerId → SignInButton 미사용 + Material 노란 배경 + InkWell 자식',
      (tester) async {
        const strategy = _FakeStrategy(
          kProviderIdKakao,
          'authKakaoSignIn',
          'kakao',
        );
        await tester.pumpWidget(
          _wrap(const SocialButton(strategy: strategy, isDisabled: false)),
        );
        await tester.pumpAndSettle();

        // sign_in_button 패키지의 SignInButton 미사용 (Kakao 미지원).
        expect(find.byType(SignInButton), findsNothing);

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
        await tester.pumpWidget(
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
        await tester.pumpWidget(
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
      'Kakao 분기 — SvgPicture 로 kakao_logo.svg 자산 로드',
      (tester) async {
        const strategy = _FakeStrategy(
          kProviderIdKakao,
          'authKakaoSignIn',
          'kakao',
        );
        await tester.pumpWidget(
          _wrap(const SocialButton(strategy: strategy, isDisabled: false)),
        );
        await tester.pumpAndSettle();

        // SvgPicture 1개 이상 매치 (Kakao 분기 외에는 SVG 미사용 — 본 테스트
        // wrap 안에 다른 SVG 미존재).
        expect(find.byType(SvgPicture), findsOneWidget);
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
        await tester.pumpWidget(
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
        await tester.pumpWidget(
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
}
