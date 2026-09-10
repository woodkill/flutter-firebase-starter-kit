import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/core/auth/auth_strategies_registry.dart';
import 'package:flutter_starter_kit/core/auth/auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/apple_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/facebook_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/google_auth_strategy.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/router/app_routes.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/email_auth_cta.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/email_field.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/or_divider.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/password_field.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/social_button.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/social_sign_in_section.dart';
import 'package:flutter_starter_kit/features/auth/presentation/login_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _FakeFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _FakeAuthRepository extends Mock implements AuthRepository {}

/// GoRouter 가 마지막으로 진입한 location 을 기록하는 recorder.
class LastLocationRecorder {
  /// 마지막으로 진입한 location (query 포함 URL).
  String? lastPushedLocation;
}

/// [LoginScreen] 을 [GoRouter] + [MaterialApp.router] 로 pump 한다.
///
/// `/login` 에서 시작하며, [AppRoutes.emailLogin] stub route 를 함께 등록해
/// chooser CTA 의 push 대상 (Phase 16.1 SC 2) 을 단언할 수 있게 한다.
/// Phase 16.1 에서 `?focus=email` 쿼리 진입 계약이 폐기되어 이 harness 는 더
/// 이상 쿼리 파라미터를 주입하지 않는다.
Widget pumpWrapper({LastLocationRecorder? recorder}) {
  final mockAuth = _FakeFirebaseAuth();
  when(
    () => mockAuth.authStateChanges(),
  ).thenAnswer((_) => const Stream<fb.User?>.empty());
  when(() => mockAuth.currentUser).thenReturn(null);

  final mockRepo = _FakeAuthRepository();
  when(() => mockRepo.signInWithGoogle()).thenAnswer((_) async => null);
  when(() => mockRepo.signInWithApple()).thenAnswer((_) async => null);
  when(() => mockRepo.signInWithFacebook()).thenAnswer((_) async => null);

  final router = GoRouter(
    initialLocation: AppRoutes.login,
    routes: [
      GoRoute(path: AppRoutes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: AppRoutes.emailLogin,
        builder: (_, state) {
          recorder?.lastPushedLocation = state.uri.toString();
          return const Scaffold(
            body: Center(child: Text('EMAIL_LOGIN_REACHED')),
          );
        },
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      isFirebaseInitializedProvider.overrideWithValue(false),
      firebaseAuthProvider.overrideWithValue(mockAuth),
      authRepositoryProvider.overrideWithValue(mockRepo),
      activeStrategiesProvider(const Locale('en')).overrideWithValue(
        const <AuthStrategy>[
          GoogleAuthStrategy(),
          AppleAuthStrategy(),
          FacebookAuthStrategy(),
        ],
      ),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light(),
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}

void main() {
  group('LoginScreen chooser 레이아웃 회귀 가드 (Phase 16.1 SC 1/2)', () {
    testWidgets('D-31/SC 1: SocialSignInSection 이 EmailAuthCta 보다 트리 상단에 위치', (
      tester,
    ) async {
      await tester.pumpWidget(pumpWrapper());
      await tester.pumpAndSettle();

      final socialFinder = find.byType(SocialSignInSection);
      final ctaFinder = find.byType(EmailAuthCta);
      expect(socialFinder, findsOneWidget);
      expect(ctaFinder, findsOneWidget);

      final socialOffset = tester.getTopLeft(socialFinder);
      final ctaOffset = tester.getTopLeft(ctaFinder);
      expect(
        socialOffset.dy,
        lessThan(ctaOffset.dy),
        reason: 'D-31: 소셜 섹션이 이메일 CTA 보다 상단에 위치해야 함',
      );
    });

    testWidgets(
      'D-31: OrDivider 1개가 SocialSignInSection 내부에 렌더 (기본 showOrDivider=true)',
      (tester) async {
        await tester.pumpWidget(pumpWrapper());
        await tester.pumpAndSettle();
        expect(find.byType(OrDivider), findsOneWidget);
      },
    );

    testWidgets('D-04/D-31: Google/Apple/Facebook 3 소셜 버튼 라벨이 모두 렌더', (
      tester,
    ) async {
      await tester.pumpWidget(pumpWrapper());
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(LoginScreen)),
      );
      // Phase 13.1 Gap-1 X2 (2026-05-09 자상화) — Google 자상이 wide 자상
      // baked-in 패턴 (라벨이 SVG 내부에 통합) 이라 `find.text(authGoogleSignIn)`
      // 무효. 대신 SocialButton (strategy.providerId == kProviderIdGoogle) 의
      // 렌더 존재 검증으로 의도 변경. Apple/Facebook 은 SDK 위제 위임으로
      // 외부 텍스트 layer 보존되어 라벨 finder 유효.
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is SocialButton && w.strategy.providerId == kProviderIdGoogle,
        ),
        findsOneWidget,
      );
      expect(find.text(l10n.authAppleSignIn), findsOneWidget);
      expect(find.text(l10n.authFacebookSignIn), findsOneWidget);
    });

    testWidgets('SC 2: EmailAuthCta 탭 시 /login/email 로 push 된다', (
      tester,
    ) async {
      final recorder = LastLocationRecorder();
      await tester.pumpWidget(pumpWrapper(recorder: recorder));
      await tester.pumpAndSettle();

      // form-tail CTA 는 default 800x600 viewport 밖 좌표가 될 수 있고
      // hit-test 가 조용히 실패한다 (RESEARCH Pitfall 6). enterText 우회가
      // 없는 경로이므로 명시적 ensureVisible 이 필수다.
      final ctaFinder = find.byType(EmailAuthCta);
      await tester.ensureVisible(ctaFinder);
      await tester.pumpAndSettle();
      await tester.tap(ctaFinder);
      await tester.pumpAndSettle();

      expect(recorder.lastPushedLocation, isNotNull);
      expect(
        recorder.lastPushedLocation,
        contains(AppRoutes.emailLogin),
        reason: 'SC 2: 이메일 CTA 는 /login/email 로 push 해야 함',
      );
      expect(find.text('EMAIL_LOGIN_REACHED'), findsOneWidget);
    });

    testWidgets('SC 1: chooser 에 EmailField 가 렌더되지 않는다', (tester) async {
      await tester.pumpWidget(pumpWrapper());
      await tester.pumpAndSettle();
      expect(find.byType(EmailField), findsNothing);
    });

    testWidgets('SC 1: chooser 에 PasswordField 가 렌더되지 않는다', (tester) async {
      await tester.pumpWidget(pumpWrapper());
      await tester.pumpAndSettle();
      expect(find.byType(PasswordField), findsNothing);
    });
  });
}
