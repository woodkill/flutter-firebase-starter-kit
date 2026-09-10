import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/auth/auth_strategies_registry.dart';
import 'package:flutter_starter_kit/core/auth/auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/apple_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/facebook_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/google_auth_strategy.dart';
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/branded_social_button.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/email_auth_cta.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/email_field.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/form_error_banner.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/social_button.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/social_sign_in_section.dart';
import 'package:flutter_starter_kit/features/auth/presentation/login_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

/// [AuthRepository] 를 mocktail 로 대체하기 위한 Mock.
class _MockAuthRepository extends Mock implements AuthRepository {}

/// [LoginScreen] 을 영문 로케일 + [AppTheme.light] 주입 상태로 pump 한다.
Future<void> _pumpLogin(
  WidgetTester tester,
  _MockAuthRepository mockRepo,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(mockRepo),
        activeStrategiesProvider(const Locale('en')).overrideWithValue(
          const <AuthStrategy>[
            GoogleAuthStrategy(),
            AppleAuthStrategy(),
            FacebookAuthStrategy(),
          ],
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
  await tester.pump();
}

void main() {
  late _MockAuthRepository mockRepo;

  setUp(() {
    mockRepo = _MockAuthRepository();
  });

  group('LoginScreen', () {
    testWidgets('6. 소셜 버튼 3개(Google + Apple + Facebook) 렌더링 — '
        'Phase 13.2 caller refactor 후 모든 provider 가 '
        'BrandedSocialButton 단일 위임', (tester) async {
      when(() => mockRepo.signInWithFacebook()).thenAnswer((_) async => null);
      await _pumpLogin(tester, mockRepo);
      // Phase 13.2 R7/R8 (옵션 A pivot, Wave 0 lock D-94) — Facebook 분기도
      // BrandedSocialButton.facebook 위임 (Meta 공식 자상 PNG + Apple
      // SignInWithAppleButton 패턴 mirror 의 _renderFacebookButton 위제).
      // Google/Apple/Facebook 3 provider 모두 BrandedSocialButton 단일
      // 위임 — sign_in_button 패키지 의존 폐기 (R10).
      expect(find.byType(SocialButton), findsNWidgets(3));
      expect(find.byType(BrandedSocialButton), findsNWidgets(3));
    });

    testWidgets('7. OrDivider "or" 텍스트가 표시된다', (tester) async {
      await _pumpLogin(tester, mockRepo);
      expect(find.text('or'), findsOneWidget);
    });

    testWidgets('8. 소셜 버튼 영역이 EmailAuthCta 위에 위치한다 (Phase 16.1 SC 1)', (
      tester,
    ) async {
      await _pumpLogin(tester, mockRepo);

      // Plan 13.1-08 — 첫 SocialButton (Google) 의 위치를 검증 (분기와 무관하게
      // SocialButton wrapper 는 모든 분기에서 사용됨).
      // Phase 16.1 — A 에서 이메일 form 이 제거되어 비교 대상이 EmailField 에서
      // 격하 CTA ([EmailAuthCta]) 로 바뀌었다. 좌표 비교 구조는 동일하다.
      final firstSocialButton = tester.getTopLeft(
        find.byType(SocialButton).first,
      );
      final emailCta = tester.getTopLeft(find.byType(EmailAuthCta));
      expect(
        firstSocialButton.dy,
        lessThan(emailCta.dy),
        reason: '소셜 버튼 영역이 이메일 CTA 위에 배치되어야 한다',
      );
    });

    // -----------------------------------------------------------------
    // Phase 8 Apple 로그인 시나리오 (AUTH-03-15, 16, 17)
    // Phase 9: 플랫폼 분기 제거(D-04). 통일 순서 Google→Apple→Facebook.
    // Phase 13.1-08: Apple 버튼은 두 번째(index 1) SocialButton — 내부적으로
    // BrandedSocialButton.apple() (SignInWithAppleButton 위제 위임) 사용.
    // -----------------------------------------------------------------
    group('LoginScreen Apple sign-in integration', () {
      /// Apple 버튼 finder — 통일 순서에서 두 번째(index 1) SocialButton.
      Finder findAppleButton() => find.byType(SocialButton).at(1);

      testWidgets('AUTH-03-15: Apple 로그인 성공 시 FormErrorBanner에 에러 없음 '
          '(navigation은 authRedirect 위임)', (tester) async {
        when(() => mockRepo.signInWithApple()).thenAnswer(
          (_) async => Result<User>.success(
            User(
              uid: 'apple-uid',
              email: 'x@privaterelay.appleid.com',
              emailVerified: true,
              displayName: 'Apple User',
              createdAt: DateTime.utc(2026, 4, 11),
              providerIds: const <String>['apple.com'],
            ),
          ),
        );
        when(() => mockRepo.signInWithFacebook()).thenAnswer((_) async => null);

        await _pumpLogin(tester, mockRepo);
        await tester.pumpAndSettle();

        // D-04: 통일 순서에서 Apple 버튼은 두 번째.
        await tester.tap(findAppleButton());
        await tester.pumpAndSettle();

        // Repository 호출 검증.
        verify(() => mockRepo.signInWithApple()).called(1);

        // 소셜 영역 FormErrorBanner.exception == null (에러 없음).
        final banner = tester.widget<FormErrorBanner>(
          find.descendant(
            of: find.byType(SocialSignInSection),
            matching: find.byType(FormErrorBanner),
          ),
        );
        expect(banner.exception, isNull);
      });

      testWidgets(
        'AUTH-03-16: Apple 에러(ServiceUnavailable) 시 FormErrorBanner 표시',
        (tester) async {
          when(() => mockRepo.signInWithApple()).thenAnswer(
            (_) async => const Result<User>.failure(ServiceUnavailable()),
          );
          when(
            () => mockRepo.signInWithFacebook(),
          ).thenAnswer((_) async => null);

          await _pumpLogin(tester, mockRepo);
          await tester.pumpAndSettle();

          // D-04: 통일 순서에서 Apple 버튼은 두 번째.
          await tester.tap(findAppleButton());
          await tester.pumpAndSettle();

          final banner = tester.widget<FormErrorBanner>(
            find.descendant(
              of: find.byType(SocialSignInSection),
              matching: find.byType(FormErrorBanner),
            ),
          );
          expect(banner.exception, isA<ServiceUnavailable>());
        },
      );

      testWidgets('AUTH-03-17 (Phase 9.2 D-31 / Phase 16.1 SC 1): Apple '
          'AccountExistsWithDifferentCredential(email) 시 이메일 자동 채움 0 — '
          'A 에 이메일 필드 자체가 없고 소셜 배너만 표시된다', (tester) async {
        when(() => mockRepo.signInWithApple()).thenAnswer(
          (_) async => const Result<User>.failure(
            AccountExistsWithDifferentCredential(
              email: 'collision@example.com',
            ),
          ),
        );
        when(() => mockRepo.signInWithFacebook()).thenAnswer((_) async => null);

        await _pumpLogin(tester, mockRepo);
        await tester.pumpAndSettle();

        // D-04: 통일 순서에서 Apple 버튼은 두 번째.
        await tester.tap(findAppleButton());
        await tester.pumpAndSettle();

        // (Phase 9.2 D-31 / R3) D-10 자동 채움 + focus 호출 제거의 후속.
        // Phase 16.1 SC 1 — A 는 chooser 로 감산되어 EmailField 가 아예
        // 렌더되지 않으므로 "자동 채움 0" 이 구조적으로 보장된다. 원래 단언
        // (controller.text.isEmpty / focusNode 미포커스) 의 의도를 보존하면서
        // SC 1 회귀 가드로 강화한 형태다. exception.email 필드 자체는 보존
        // (Phase 17 부활 anchor — server-side provider 매핑 input).
        expect(find.byType(EmailField), findsNothing);

        // 소셜 영역 FormErrorBanner에는 여전히 에러가 표시되어야 한다 —
        // setState({_socialError = err, _emailError = null}) 블록 보존.
        final banner = tester.widget<FormErrorBanner>(
          find.descendant(
            of: find.byType(SocialSignInSection),
            matching: find.byType(FormErrorBanner),
          ),
        );
        expect(banner.exception, isA<AccountExistsWithDifferentCredential>());
      });
    });
  });
}
