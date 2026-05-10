// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/auth/auth_strategies_registry.dart';
import 'package:flutter_starter_kit/core/auth/auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/apple_auth_strategy.dart';
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/email_field.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/form_error_banner.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/social_button.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/social_sign_in_section.dart';
import 'package:flutter_starter_kit/features/auth/presentation/login_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late _MockAuthRepository mockRepo;

  setUp(() {
    mockRepo = _MockAuthRepository();
  });

  // (Phase 9.2 R3 / D-31 / D-34) login_screen.dart 의 listener body 에서
  // D-10 자동 채움 + focus 호출 4줄 삭제로 인해 AsyncError(
  // AccountExistsWithDifferentCredential) emit 시 EmailField 가 비어있는
  // 상태 유지 + EmailField focusNode 미포커스 + unknown fallback 메시지 banner
  // 표시 invariant 검증.
  //
  // setState({_socialError = err, _emailError = null}) 블록은 보존 — banner
  // 표시 + email 필드 자체는 보존 (Phase 17 부활 anchor).
  group(
    'Phase 9.2 R3 — LoginScreen AccountExistsWithDifferentCredential D-31 '
    '검증',
    () {
      testWidgets(
        'AsyncError(AccountExistsWithDifferentCredential) emit → '
        '_emailController.text 빈 + _emailFocus.hasFocus=false + unknown '
        '메시지 banner 표시',
        (tester) async {
          // (D-34) Apple strategy → AsyncError(AccountExistsWithDifferentCredential).
          when(() => mockRepo.signInWithApple()).thenAnswer(
            (_) async => const Result<User>.failure(
              AccountExistsWithDifferentCredential(email: 'old@example.com'),
            ),
          );

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                authRepositoryProvider.overrideWithValue(mockRepo),
                activeStrategiesProvider(
                  const Locale('en'),
                ).overrideWithValue(
                  const <AuthStrategy>[AppleAuthStrategy()],
                ),
              ],
              child: MaterialApp(
                theme: AppTheme.light(),
                locale: const Locale('en'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: const LoginScreen(),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Apple 버튼 탭 → AsyncError emit.
          await tester.tap(find.byType(SocialButton).first);
          await tester.pumpAndSettle();

          // (R3 acceptance #1) 자동 채움 0 — _emailController.text.isEmpty.
          // EmailField 안 TextFormField 의 controller 가 LoginScreen 의
          // _emailController 와 바인드 → 빈 상태 유지 검증.
          final emailFormField = tester.widget<TextFormField>(
            find.descendant(
              of: find.byType(EmailField),
              matching: find.byType(TextFormField),
            ),
          );
          expect(emailFormField.controller?.text, isEmpty);

          // (R3 acceptance #2) _emailFocus.hasFocus == false 검증.
          // EmailField 의 focusNode props 가 LoginScreen 의 _emailFocus 와
          // 바인드 → tester.widget<EmailField>() 로 직접 추출 + hasFocus 검사.
          final emailField = tester.widget<EmailField>(
            find.byType(EmailField),
          );
          expect(emailField.focusNode.hasFocus, isFalse);

          // (R3 acceptance #3) 메시지 banner 표시 — unknown fallback 메시지
          // verbatim. setState({_socialError = err}) 블록 보존으로 SocialSignInSection
          // 안 FormErrorBanner.exception 이 AccountExistsWithDifferentCredential
          // 인스턴스를 받음 → exception_l10n 의 special-case branch 가
          // errorAccountExistsWithUnknownProvider 로 단일 매핑.
          final banner = tester.widget<FormErrorBanner>(
            find.descendant(
              of: find.byType(SocialSignInSection),
              matching: find.byType(FormErrorBanner),
            ),
          );
          expect(banner.exception, isA<AccountExistsWithDifferentCredential>());

          // unknown fallback 메시지 verbatim 매치 (P1 ARB en 정합).
          expect(
            find.text(
              'This email is already registered with another sign-in method. '
              'Please sign in with the method you originally used.',
            ),
            findsOneWidget,
          );
        },
      );
    },
  );
}
