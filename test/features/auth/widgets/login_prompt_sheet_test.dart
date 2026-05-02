import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/core/auth/auth_strategies_registry.dart';
import 'package:flutter_starter_kit/core/auth/auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/apple_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/facebook_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/google_auth_strategy.dart';
import 'package:flutter_starter_kit/core/router/app_routes.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/login_prompt_sheet.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/or_divider.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/social_sign_in_section.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sign_in_button/sign_in_button.dart';

/// [AuthRepository] 를 mocktail 로 대체하기 위한 Mock.
class _MockAuthRepository extends Mock implements AuthRepository {}

/// 마지막으로 push 된 URL 을 기록하기 위한 단순 라우터 observer.
class LastLocationRecorder {
  /// 마지막으로 GoRouter 가 진입한 location (query 포함 URL) .
  String? lastPushedLocation;
}

/// [LoginPromptSheet] 을 pump 하는 harness.
///
/// - [MaterialApp.router] + [GoRouter] 로 `/` (트리거 버튼) 와 `/login`
///   두 route 를 구성한다. `/login` 진입 시 마지막 push 된 URL 을 기록하여
///   "이메일로 계속" 클릭 시 `focus=email` 쿼리가 전달되었는지 확인한다.
/// - 트리거 버튼 탭 → [showLoginPromptSheet] 호출.
Future<LastLocationRecorder> pumpLoginPromptSheetHarness(
  WidgetTester tester,
) async {
  final recorder = LastLocationRecorder();
  final mockRepo = _MockAuthRepository();
  when(() => mockRepo.signInWithGoogle()).thenAnswer((_) async => null);
  when(() => mockRepo.signInWithApple()).thenAnswer((_) async => null);
  when(() => mockRepo.signInWithFacebook()).thenAnswer((_) async => null);

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showLoginPromptSheet(context),
                child: const Text('Trigger'),
              ),
            ),
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (_, state) {
          recorder.lastPushedLocation = state.uri.toString();
          return const Scaffold(body: Center(child: Text('LoginStub')));
        },
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(mockRepo),
        activeStrategiesProvider(
          const Locale('en'),
        ).overrideWithValue(const <AuthStrategy>[
          GoogleAuthStrategy(),
          AppleAuthStrategy(),
          FacebookAuthStrategy(),
        ]),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return recorder;
}

void main() {
  group('LoginPromptSheet (Phase 10 D-10)', () {
    testWidgets('헤더 title + body 텍스트가 렌더된다', (tester) async {
      await pumpLoginPromptSheetHarness(tester);
      await tester.tap(find.text('Trigger'));
      await tester.pumpAndSettle();

      final sheetContext = tester.element(find.byType(LoginPromptSheet));
      final l10n = AppLocalizations.of(sheetContext);
      expect(find.text(l10n.authPromptSheetTitle), findsOneWidget);
      expect(find.text(l10n.authPromptSheetBody), findsOneWidget);
    });

    testWidgets(
      'SocialSignInSection 이 showOrDivider:false 로 렌더되어 OrDivider 없음',
      (tester) async {
        await pumpLoginPromptSheetHarness(tester);
        await tester.tap(find.text('Trigger'));
        await tester.pumpAndSettle();

        // 소셜 3 버튼 렌더 확인.
        expect(find.byType(SignInButton), findsNWidgets(3));
        // showOrDivider:false → OrDivider 없어야 함.
        expect(
          find.byType(OrDivider),
          findsNothing,
          reason: 'LoginPromptSheet 은 showOrDivider:false 로 렌더해야 함',
        );

        // SocialSignInSection 위젯 인스턴스의 showOrDivider prop 검증.
        final section = tester.widget<SocialSignInSection>(
          find.byType(SocialSignInSection),
        );
        expect(section.showOrDivider, isFalse);
      },
    );

    testWidgets('authContinueWithEmail TextButton 이 렌더된다', (tester) async {
      await pumpLoginPromptSheetHarness(tester);
      await tester.tap(find.text('Trigger'));
      await tester.pumpAndSettle();

      final sheetContext = tester.element(find.byType(LoginPromptSheet));
      final l10n = AppLocalizations.of(sheetContext);
      final emailButtonFinder = find.widgetWithText(
        TextButton,
        l10n.authContinueWithEmail,
      );
      expect(emailButtonFinder, findsOneWidget);
    });

    testWidgets('"이메일로 계속" 탭 → Sheet 닫힘 + /login 으로 push (focus=email 포함)', (
      tester,
    ) async {
      final recorder = await pumpLoginPromptSheetHarness(tester);
      await tester.tap(find.text('Trigger'));
      await tester.pumpAndSettle();

      final sheetContext = tester.element(find.byType(LoginPromptSheet));
      final l10n = AppLocalizations.of(sheetContext);
      await tester.tap(find.text(l10n.authContinueWithEmail));
      await tester.pumpAndSettle();

      // Sheet 은 닫혔어야 함.
      expect(find.byType(LoginPromptSheet), findsNothing);
      // /login 으로 이동했고, 쿼리 파라미터 focus=email 이 포함되어야 함.
      expect(recorder.lastPushedLocation, isNotNull);
      expect(
        recorder.lastPushedLocation,
        contains(AppRoutes.login),
        reason: 'LoginScreen 경로로 이동해야 함',
      );
    });

    testWidgets('WARNING #12 / D-31: push URL 이 focus=email 쿼리 파라미터를 포함한다', (
      tester,
    ) async {
      final recorder = await pumpLoginPromptSheetHarness(tester);
      await tester.tap(find.text('Trigger'));
      await tester.pumpAndSettle();

      final sheetContext = tester.element(find.byType(LoginPromptSheet));
      final l10n = AppLocalizations.of(sheetContext);
      await tester.tap(find.text(l10n.authContinueWithEmail));
      await tester.pumpAndSettle();

      expect(recorder.lastPushedLocation, isNotNull);
      expect(
        recorder.lastPushedLocation,
        contains('focus=email'),
        reason: 'Bottom Sheet → LoginScreen 이메일 포커스 유도 쿼리 필수',
      );
    });
  });
}
