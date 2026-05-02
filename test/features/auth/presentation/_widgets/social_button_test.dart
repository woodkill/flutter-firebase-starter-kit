import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  final Future<void> Function(Ref ref)? onSignIn;

  @override
  String get providerId => _providerId;
  @override
  String get labelKey => _labelKey;
  @override
  String get iconAsset => _iconAsset;

  @override
  Future<void> signIn(Ref ref) async {
    if (onSignIn != null) {
      await onSignIn!(ref);
    }
  }
}

/// 영문 로케일 + light theme 으로 [SocialButton] 을 pump 하는 helper.
Widget _wrap(Widget child, {Brightness brightness = Brightness.light}) {
  return ProviderScope(
    child: MaterialApp(
      theme: brightness == Brightness.dark
          ? AppTheme.dark()
          : AppTheme.light(),
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('SocialButton _resolveButtons (Buttons enum 매핑)', () {
    testWidgets('Google providerId + light → Buttons.google', (tester) async {
      final strategy = _FakeStrategy(
        kProviderIdGoogle,
        'authGoogleSignIn',
        'google',
      );
      await tester.pumpWidget(
        _wrap(SocialButton(strategy: strategy, isDisabled: false)),
      );
      await tester.pumpAndSettle();

      final btn = tester.widget<SignInButton>(find.byType(SignInButton));
      expect(btn.button, Buttons.google);
    });

    testWidgets('Google providerId + dark → Buttons.googleDark', (
      tester,
    ) async {
      final strategy = _FakeStrategy(
        kProviderIdGoogle,
        'authGoogleSignIn',
        'google',
      );
      await tester.pumpWidget(
        _wrap(
          SocialButton(strategy: strategy, isDisabled: false),
          brightness: Brightness.dark,
        ),
      );
      await tester.pumpAndSettle();

      final btn = tester.widget<SignInButton>(find.byType(SignInButton));
      expect(btn.button, Buttons.googleDark);
    });

    testWidgets('Apple providerId + light → Buttons.apple', (tester) async {
      final strategy = _FakeStrategy(
        kProviderIdApple,
        'authAppleSignIn',
        'apple',
      );
      await tester.pumpWidget(
        _wrap(SocialButton(strategy: strategy, isDisabled: false)),
      );
      await tester.pumpAndSettle();

      final btn = tester.widget<SignInButton>(find.byType(SignInButton));
      expect(btn.button, Buttons.apple);
    });

    testWidgets('Apple providerId + dark → Buttons.appleDark', (tester) async {
      final strategy = _FakeStrategy(
        kProviderIdApple,
        'authAppleSignIn',
        'apple',
      );
      await tester.pumpWidget(
        _wrap(
          SocialButton(strategy: strategy, isDisabled: false),
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
      final strategy = _FakeStrategy(
        kProviderIdFacebook,
        'authFacebookSignIn',
        'facebook',
      );
      await tester.pumpWidget(
        _wrap(
          SocialButton(strategy: strategy, isDisabled: false),
          brightness: Brightness.dark,
        ),
      );
      await tester.pumpAndSettle();

      final btn = tester.widget<SignInButton>(find.byType(SignInButton));
      expect(btn.button, Buttons.facebookNew);
    });

    testWidgets('Unknown providerId → UnsupportedError', (tester) async {
      final strategy = _FakeStrategy('unknown.com', 'authUnknown', 'unknown');
      // suppress framework error log
      FlutterError.onError = (_) {};
      await tester.pumpWidget(
        _wrap(SocialButton(strategy: strategy, isDisabled: false)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isA<UnsupportedError>());
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
}
