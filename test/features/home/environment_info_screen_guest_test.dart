import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/home/presentation/environment_info_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockUser extends Mock implements fb.User {}

/// [EnvironmentInfoScreen] 의 게스트 UI (Phase 10 D-13, D-11) 검증 harness.
///
/// [authStateUser] 가 null → AsyncData(null), non-null → AsyncData(user).
/// [isFirebaseInitialized] 를 통해 Provider 분기 제어.
Future<void> pumpGuestHarness(
  WidgetTester tester, {
  required bool isFirebaseInitialized,
  fb.User? authStateUser,
}) async {
  tester.view.physicalSize = const Size(800, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final mockAuth = _MockFirebaseAuth();
  when(() => mockAuth.currentUser).thenReturn(authStateUser);

  final mockRepo = _MockAuthRepository();

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const EnvironmentInfoScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (_, _) => const Scaffold(body: Center(child: Text('LoginStub'))),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        isFirebaseInitializedProvider.overrideWithValue(isFirebaseInitialized),
        firebaseAuthProvider.overrideWithValue(mockAuth),
        authStateProvider.overrideWith((ref) => Stream.value(authStateUser)),
        currentUserProvider.overrideWith((ref) => null),
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
  group('EnvironmentInfoScreen 게스트 UI (Phase 10 D-13, D-11)', () {
    testWidgets(
      'isAnonymous=true 사용자 → body 상단에 _GuestBanner 렌더',
      (tester) async {
        final anonUser = _MockUser();
        when(() => anonUser.isAnonymous).thenReturn(true);
        when(() => anonUser.uid).thenReturn('anon-uid');

        await pumpGuestHarness(
          tester,
          isFirebaseInitialized: true,
          authStateUser: anonUser,
        );

        final l10n = AppLocalizations.of(
          tester.element(find.byType(EnvironmentInfoScreen)),
        );
        expect(
          find.text(l10n.homeGuestBanner),
          findsOneWidget,
          reason: '익명 사용자에게 게스트 배너가 상단에 노출되어야 함',
        );
      },
    );

    testWidgets(
      'isAnonymous=false 사용자 → 게스트 배너/AppBar 로그인 버튼 숨김',
      (tester) async {
        final verifiedUser = _MockUser();
        when(() => verifiedUser.isAnonymous).thenReturn(false);
        when(() => verifiedUser.uid).thenReturn('verified-uid');

        await pumpGuestHarness(
          tester,
          isFirebaseInitialized: true,
          authStateUser: verifiedUser,
        );

        final l10n = AppLocalizations.of(
          tester.element(find.byType(EnvironmentInfoScreen)),
        );
        expect(
          find.text(l10n.homeGuestBanner),
          findsNothing,
          reason: '정식 사용자는 게스트 배너 없음',
        );
        expect(
          find.text(l10n.homeSignIn),
          findsNothing,
          reason: '정식 사용자는 AppBar 로그인 버튼 없음',
        );
      },
    );

    testWidgets(
      'isAnonymous=true 사용자 → AppBar 우측에 homeSignIn TextButton 표시',
      (tester) async {
        final anonUser = _MockUser();
        when(() => anonUser.isAnonymous).thenReturn(true);
        when(() => anonUser.uid).thenReturn('anon-uid');

        await pumpGuestHarness(
          tester,
          isFirebaseInitialized: true,
          authStateUser: anonUser,
        );

        final l10n = AppLocalizations.of(
          tester.element(find.byType(EnvironmentInfoScreen)),
        );
        final appBarLoginFinder = find.widgetWithText(
          TextButton,
          l10n.homeSignIn,
        );
        expect(appBarLoginFinder, findsOneWidget);
      },
    );

    testWidgets(
      '_ProtectedExampleSection 이 항상 렌더 + AuthRequired 래핑 OutlinedButton 포함',
      (tester) async {
        // isAnonymous=false 인 정식 사용자 케이스로도 섹션이 렌더되어야 함.
        final verifiedUser = _MockUser();
        when(() => verifiedUser.isAnonymous).thenReturn(false);
        when(() => verifiedUser.uid).thenReturn('verified-uid');

        await pumpGuestHarness(
          tester,
          isFirebaseInitialized: true,
          authStateUser: verifiedUser,
        );

        final l10n = AppLocalizations.of(
          tester.element(find.byType(EnvironmentInfoScreen)),
        );
        expect(
          find.text(l10n.homeProtectedExampleTitle),
          findsOneWidget,
          reason: '보호 예시 섹션은 isAnonymous 관계없이 항상 렌더',
        );
        expect(
          find.text(l10n.homeProtectedExampleBody),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(
            OutlinedButton,
            l10n.homeProtectedExampleCta,
          ),
          findsOneWidget,
          reason: 'AuthRequired 래핑된 OutlinedButton.icon 필요',
        );
      },
    );
  });
}
