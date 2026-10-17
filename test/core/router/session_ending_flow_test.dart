// quick 261011-e6c — production `App()` 관통: 계정 화면 로그아웃 → 진행 오버레이
// → 온보딩 전환 뒤 걷힘.
//
// - E6C-FLOW-01: 로그아웃 행 → 확인 → `App()` 의 [SessionEndingOverlay] 가
//   로그아웃 문구로 덮는다 → 저장소 완료 뒤에도 유지 → 온보딩 전환 중 유지 →
//   전환 뒤 걷힘
// - E6C-FLOW-02: 저장소가 throw → 오버레이 0 · 계정 화면 유지 · 예외는 전파
//
// 계정 화면은 로그아웃 예외를 잡지 않는다(탭 핸들러의 future 가 error 로 끝난다).
// flutter_test 는 잡히지 않은 비동기 error 를 받는 즉시 테스트를 실패로 끝내므로
// `tester.takeException()` 으로는 받을 수 없다 — FLOW-02 는 로그아웃 행 탭을
// `runZonedGuarded` 안에서 일으켜 그 zone 으로 전파된 error 를 모은다.
//
// 이 하네스(`pumpProductionApp`)는 Firebase 미초기화라 guard 가 redirect 하지
// 않는다. 실제 redirect(authStateChanges → resolveAuthRedirect)는 guard 테스트가
// 보므로, 여기서는 route 이동만 `router.go` 로 대신한다.
//
// 하네스가 `UncontrolledProviderScope` 라 관리자의 30초 타이머가 남은 채 끝나면
// 「A Timer is still pending」 으로 실패한다 — 두 테스트 모두 「없음」 으로 끝낸다.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_starter_kit/app.dart' show App;
import 'package:flutter_starter_kit/core/auth/auth_strategies_registry.dart'
    show activeStrategiesProvider;
import 'package:flutter_starter_kit/core/auth/auth_strategy.dart'
    show AuthStrategy;
import 'package:flutter_starter_kit/core/auth/strategies/google_auth_strategy.dart'
    show GoogleAuthStrategy;
import 'package:flutter_starter_kit/core/router/app_routes.dart' show AppRoutes;
import 'package:flutter_starter_kit/features/auth/application/session_ending.dart'
    show SessionEndingKind, idleSessionEndingState, sessionEndingProvider;
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart'
    show
        AuthRepository,
        UserProviderRecord,
        authRepositoryProvider,
        currentUserProvider,
        linkedProvidersStreamProvider;
import 'package:flutter_starter_kit/features/auth/domain/user.dart' show User;
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/auth_in_progress_overlay.dart'
    show AuthInProgressOverlay;
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/session_ending_overlay.dart'
    show SessionEndingOverlay;
import 'package:flutter_starter_kit/features/notifications/application/notification_settings_notifier.dart'
    show notificationSettingsProvider;
import 'package:flutter_starter_kit/features/onboarding/presentation/onboarding_screen.dart'
    show OnboardingScreen;
import 'package:flutter_starter_kit/features/settings/presentation/account_screen.dart'
    show AccountScreen;
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart'
    show AppLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/router_harness.dart'
    show ProductionApp, pumpProductionApp;

class _MockAuthRepository extends Mock implements AuthRepository {}

/// 사진 출처 stream fixture — 업로드 사진 없음 (설정 화면 테스트와 같은 모양).
const UserProviderRecord _kNoPhotoRecord = (
  linkedProviderIds: <String>[],
  signUpProviderId: null,
  customPhotoUrl: null,
);

/// 계정 화면을 그릴 정식 사용자 fixture (설정 화면 테스트와 같은 모양).
final User _kTestUser = User(
  uid: 'uid-1',
  email: 'me@example.com',
  emailVerified: true,
  displayName: 'Tester',
  createdAt: DateTime.utc(2026),
  providerIds: const <String>['password'],
);

/// 진입 전환이 끝나기에 충분한 시간.
const Duration _transitionDone = Duration(seconds: 1);

/// 진입 전환 도중의 한 시점.
const Duration _midTransition = Duration(milliseconds: 100);

/// production `App()` 을 그리고 계정 화면까지 이동한다.
///
/// 계정 화면이 실 Firebase 에 닿지 않게 `app_router_nesting_test.dart` 와 같은
/// override 5종을 달고, 저장소는 호출자가 스텁한 [repo] 를 쓴다.
Future<ProductionApp> _pumpAccountScreen(
  WidgetTester tester,
  _MockAuthRepository repo,
) async {
  final app = await pumpProductionApp(
    tester,
    extraOverrides: [
      currentUserProvider.overrideWith((ref) => _kTestUser),
      activeStrategiesProvider.overrideWith(
        (ref) => const <AuthStrategy>[GoogleAuthStrategy()],
      ),
      authRepositoryProvider.overrideWithValue(repo),
      notificationSettingsProvider.overrideWithBuild((ref, notifier) => false),
      linkedProvidersStreamProvider(
        _kTestUser.uid,
      ).overrideWith((ref) => Stream.value(_kNoPhotoRecord)),
    ],
  );
  app.router.go(AppRoutes.account);
  await tester.pumpAndSettle();
  expect(find.byType(AccountScreen), findsOneWidget);
  return app;
}

/// 계정 화면의 로그아웃 행을 보이게 스크롤해 누르고 확인 다이얼로그에서 확인한다.
///
/// 확인 뒤에는 오버레이가 떠 있으므로 `pumpAndSettle` 을 쓰지 않는다 — 탭을
/// 처리하는 프레임과 오버레이가 mount 되는 프레임만 그린다.
///
/// [uncaughtErrors] 를 주면 로그아웃 행 탭을 그 목록으로 error 를 모으는 zone
/// 안에서 일으킨다 — 탭 핸들러(`_confirmSignOut`)의 future 가 그 zone 에 속하므로
/// 핸들러가 잡지 않은 예외가 여기에 모인다.
Future<AppLocalizations> _confirmSignOut(
  WidgetTester tester, {
  List<Object>? uncaughtErrors,
}) async {
  final l10n = AppLocalizations.of(tester.element(find.byType(AccountScreen)));
  final signOutRow = find.descendant(
    of: find.byType(AccountScreen),
    matching: find.text(l10n.authAccountSignOut),
  );
  await tester.scrollUntilVisible(
    signOutRow,
    200,
    scrollable: find
        .descendant(
          of: find.byType(AccountScreen),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
  if (uncaughtErrors == null) {
    await tester.tap(signOutRow);
  } else {
    await runZonedGuarded(
      () => tester.tap(signOutRow),
      (Object error, StackTrace stackTrace) => uncaughtErrors.add(error),
    );
  }
  await tester.pumpAndSettle();
  expect(find.text(l10n.authLogoutConfirmMessage), findsOneWidget);

  // 다이얼로그 확인 버튼 — 본문 문구가 든 AlertDialog 안의 마지막 TextButton.
  await tester.tap(
    find
        .descendant(
          of: find.byType(AlertDialog),
          matching: find.text(l10n.authAccountSignOut),
        )
        .last,
  );
  await tester.pump();
  await tester.pump();
  return l10n;
}

/// production `App()` 의 최상위 오버레이가 얹은 [AuthInProgressOverlay] finder.
Finder _findAppOverlay() => find.descendant(
  of: find.descendant(
    of: find.byType(App),
    matching: find.byType(SessionEndingOverlay),
  ),
  matching: find.byType(AuthInProgressOverlay),
);

void main() {
  group('production App() 로그아웃 진행 오버레이 (quick 261011-e6c)', () {
    testWidgets('E6C-FLOW-01: 계정 화면 로그아웃 → 확인 → 오버레이 + 로그아웃 문구 → 저장소 '
        '완료 뒤에도 유지 → 온보딩 전환 중 유지 → 전환 뒤 오버레이 0 · 없음', (tester) async {
      final repo = _MockAuthRepository();
      final repoDone = Completer<void>();
      when(repo.signOutAndResetOnboarding).thenAnswer((_) => repoDone.future);
      final app = await _pumpAccountScreen(tester, repo);
      expect(
        find.descendant(
          of: find.byType(App),
          matching: find.byType(SessionEndingOverlay),
        ),
        findsOneWidget,
        reason: 'App() 의 builder 에 오버레이 자리가 한 번 있다',
      );
      expect(_findAppOverlay(), findsNothing, reason: '진행 중이 아니면 그리지 않는다');

      final l10n = await _confirmSignOut(tester);

      expect(_findAppOverlay(), findsOneWidget);
      expect(
        app.container.read(sessionEndingProvider).kind,
        SessionEndingKind.signOut,
      );
      verify(repo.signOutAndResetOnboarding).called(1);
      await tester.pump(AuthInProgressOverlay.indicatorDelay);
      expect(
        find.descendant(
          of: _findAppOverlay(),
          matching: find.text(l10n.authSigningOut),
        ),
        findsOneWidget,
      );

      // 저장소가 끝나도 route 가 바뀌기 전에는 남는다.
      repoDone.complete();
      await tester.pump();
      await tester.pump(_midTransition);
      expect(_findAppOverlay(), findsOneWidget);
      expect(find.byType(AccountScreen), findsOneWidget);

      // guard 의 redirect 를 대신하는 route 이동 — 전환 중에도 남는다.
      app.router.go(AppRoutes.onboarding);
      await tester.pump();
      expect(_findAppOverlay(), findsOneWidget);
      await tester.pump();
      await tester.pump(_midTransition);
      expect(_findAppOverlay(), findsOneWidget, reason: '전환 도중');
      expect(
        app.container.read(sessionEndingProvider).kind,
        SessionEndingKind.signOut,
      );

      // 전환 종료 → 프레임 뒤 보고 → 다음 프레임에 걷힌다.
      await tester.pump(_transitionDone);
      await tester.pump();
      expect(find.byType(AuthInProgressOverlay), findsNothing);
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.byType(AccountScreen), findsNothing);
      expect(app.container.read(sessionEndingProvider), idleSessionEndingState);
    });

    testWidgets('E6C-FLOW-02: 저장소가 throw → 오버레이 0 · 계정 화면 유지 · 예외는 그대로 '
        '전파된다', (tester) async {
      final repo = _MockAuthRepository();
      final error = StateError('sign-out failed');
      // error 는 저장소 호출 안에서 던진다 — 테스트 zone 에서 만든 실패 future 는
      // error zone 경계를 넘지 못해, 탭 핸들러의 zone 에서 await 할 수 없다.
      final failNow = Completer<void>();
      when(repo.signOutAndResetOnboarding).thenAnswer((_) async {
        await failNow.future;
        throw error;
      });
      final app = await _pumpAccountScreen(tester, repo);
      final uncaughtErrors = <Object>[];

      await _confirmSignOut(tester, uncaughtErrors: uncaughtErrors);
      expect(_findAppOverlay(), findsOneWidget);
      expect(uncaughtErrors, isEmpty);

      failNow.complete();
      await tester.pump();
      await tester.pump();

      // 계정 화면은 예외를 잡지 않는다 — 같은 error 가 그대로 전파된다.
      expect(uncaughtErrors, hasLength(1));
      expect(identical(uncaughtErrors.single, error), isTrue);
      expect(find.byType(AuthInProgressOverlay), findsNothing);
      expect(find.byType(AccountScreen), findsOneWidget);
      expect(app.container.read(sessionEndingProvider), idleSessionEndingState);
      verify(repo.signOutAndResetOnboarding).called(1);
    });
  });
}
