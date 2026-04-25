import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/auth_required.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/login_prompt_sheet.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

/// [fb.FirebaseAuth] 를 mocktail 로 대체하기 위한 Mock.
class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

/// [fb.User] 를 mocktail 로 대체하기 위한 Mock.
class _MockUser extends Mock implements fb.User {}

/// [AuthRepository] 를 mocktail 로 대체하기 위한 Mock.
///
/// [LoginPromptSheet] 이 내부적으로 [SocialSignInSection] 을 사용하므로
/// `authRepositoryProvider` override 가 필요하다.
class _MockAuthRepository extends Mock implements AuthRepository {}

/// [AuthRequired] 를 [GoRouter] + [MaterialApp.router] 환경에서 pump 하는
/// 공통 harness.
///
/// [isFirebaseInitialized] 와 [currentUser] 로 인증 상태를 시뮬레이션한다.
/// [onAuthenticated] 는 Test 3/4 에서 호출 카운트 검증에 사용한다.
Future<void> pumpAuthRequired(
  WidgetTester tester, {
  required bool isFirebaseInitialized,
  fb.User? currentUser,
  required VoidCallback onAuthenticated,
}) async {
  final mockAuth = _MockFirebaseAuth();
  when(() => mockAuth.currentUser).thenReturn(currentUser);

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
          body: Center(
            child: AuthRequired(
              onAuthenticated: onAuthenticated,
              child: const ElevatedButton(
                onPressed: null,
                child: Text('Protected'),
              ),
            ),
          ),
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        isFirebaseInitializedProvider.overrideWithValue(isFirebaseInitialized),
        firebaseAuthProvider.overrideWithValue(mockAuth),
        authRepositoryProvider.overrideWithValue(mockRepo),
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
}

void main() {
  group('AuthRequired (Phase 10 D-12)', () {
    testWidgets('currentUser=null (미인증) 상태에서 탭 → LoginPromptSheet 표시', (
      tester,
    ) async {
      var callbackInvoked = 0;

      await pumpAuthRequired(
        tester,
        isFirebaseInitialized: true,
        currentUser: null,
        onAuthenticated: () => callbackInvoked++,
      );

      // AbsorbPointer 안의 Text 는 hit test 에서 미스하지만 바깥
      // GestureDetector 가 동일 위치에서 탭을 수신한다. 경고 억제.
      await tester.tap(find.text('Protected'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byType(LoginPromptSheet), findsOneWidget);
      expect(
        callbackInvoked,
        0,
        reason: '미인증 시 onAuthenticated 콜백은 호출되지 않아야 함',
      );
    });

    testWidgets(
      'currentUser.isAnonymous=true (익명) 상태에서 탭 → LoginPromptSheet 표시',
      (tester) async {
        var callbackInvoked = 0;
        final anonymousUser = _MockUser();
        when(() => anonymousUser.isAnonymous).thenReturn(true);
        when(() => anonymousUser.uid).thenReturn('anon-uid');

        await pumpAuthRequired(
          tester,
          isFirebaseInitialized: true,
          currentUser: anonymousUser,
          onAuthenticated: () => callbackInvoked++,
        );

        await tester.tap(find.text('Protected'), warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(find.byType(LoginPromptSheet), findsOneWidget);
        expect(callbackInvoked, 0);
      },
    );

    testWidgets(
      'currentUser.isAnonymous=false (정식) 상태에서 탭 → onAuthenticated 호출',
      (tester) async {
        var callbackInvoked = 0;
        final verifiedUser = _MockUser();
        when(() => verifiedUser.isAnonymous).thenReturn(false);
        when(() => verifiedUser.uid).thenReturn('verified-uid');

        await pumpAuthRequired(
          tester,
          isFirebaseInitialized: true,
          currentUser: verifiedUser,
          onAuthenticated: () => callbackInvoked++,
        );

        await tester.tap(find.text('Protected'), warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(find.byType(LoginPromptSheet), findsNothing);
        expect(callbackInvoked, 1, reason: '정식 인증 사용자는 onAuthenticated 1회 호출');
      },
    );

    testWidgets('Firebase 미초기화 (Phase 1 D-13) → Sheet 미표시 + fallback 콜백 실행', (
      tester,
    ) async {
      var callbackInvoked = 0;

      await pumpAuthRequired(
        tester,
        isFirebaseInitialized: false,
        currentUser: null,
        onAuthenticated: () => callbackInvoked++,
      );

      await tester.tap(find.text('Protected'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(
        find.byType(LoginPromptSheet),
        findsNothing,
        reason: 'Firebase 미초기화 시 Sheet 을 표시하지 않음',
      );
      expect(
        callbackInvoked,
        1,
        reason: 'Phase 1 D-13: Firebase 없이도 앱 정상 실행 철학',
      );
    });
  });
}
