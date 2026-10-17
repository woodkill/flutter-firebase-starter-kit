// quick 261011-e6c — 도착 표식 [SessionEndingArrival] 위젯 테스트.
//
// GoRouter 2 route(시작 route + 표식으로 감싼 **임의의 다른 route**)와 최상위
// [SessionEndingOverlay] 로 본다. 목적지가 온보딩이 아니어도 그 route 의 builder
// 를 표식으로 감싸면 오버레이가 걷힌다는 것을 함께 확인한다.
//
// - E6C-ARR-01: 저장소 완료 → route 이동 → 전환 중에는 오버레이 유지(route 가
//   offstage 로 그려지는 프레임 포함) → 전환이 끝난 뒤 걷힘
// - E6C-ARR-02: 역순 — route 전환이 먼저 끝나도 저장소가 끝나기 전에는 유지
//
// 스피너가 도는 동안 `pumpAndSettle` 은 끝나지 않는다 — `pump(Duration)` 만 쓴다.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/application/session_ending.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/auth_in_progress_overlay.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/session_ending_arrival.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/session_ending_overlay.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

/// 시작 route 경로 · 화면 문구.
const String _startPath = '/start';
const String _startText = 'start-screen';

/// 표식으로 감싼 목적지 route 경로 · 화면 문구 (온보딩이 아닌 임의의 route).
const String _destinationPath = '/destination';
const String _destinationText = 'destination-screen';

/// 진입 전환이 끝나기에 충분한 시간.
const Duration _transitionDone = Duration(seconds: 1);

/// 진입 전환 도중의 한 시점.
const Duration _midTransition = Duration(milliseconds: 100);

/// 시작 route + 표식으로 감싼 목적지 route 를 가진 라우터.
GoRouter _buildRouter() => GoRouter(
  initialLocation: _startPath,
  routes: <RouteBase>[
    GoRoute(
      path: _startPath,
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text(_startText))),
    ),
    GoRoute(
      path: _destinationPath,
      builder: (context, state) => const SessionEndingArrival(
        child: Scaffold(body: Center(child: Text(_destinationText))),
      ),
    ),
  ],
);

/// 그린 앱 한 벌 — 라우터 · container · 저장소 완료 핸들.
typedef _ArrivalApp = ({
  GoRouter router,
  ProviderContainer container,
  Completer<void> repoDone,
});

/// 끝나지 않는 저장소 로그아웃을 단 앱을 그리고 시작 route 까지 진행한다.
Future<_ArrivalApp> _pumpApp(WidgetTester tester) async {
  final repo = _MockAuthRepository();
  final repoDone = Completer<void>();
  when(repo.signOutAndResetOnboarding).thenAnswer((_) => repoDone.future);
  final router = _buildRouter();
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('ko'),
        theme: AppTheme.light(),
        builder: (context, child) =>
            SessionEndingOverlay(child: child ?? const SizedBox.shrink()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text(_startText), findsOneWidget);

  return (
    router: router,
    container: ProviderScope.containerOf(
      tester.element(find.byType(SessionEndingOverlay)),
    ),
    repoDone: repoDone,
  );
}

void main() {
  group('SessionEndingArrival (quick 261011-e6c)', () {
    testWidgets('E6C-ARR-01: 저장소 완료 → route 이동 전 · 전환 중에는 오버레이 유지 '
        '(옛 화면 · 새 화면이 함께 있음) → 전환이 끝난 뒤 오버레이 0 · 없음', (tester) async {
      final app = await _pumpApp(tester);
      final notifier = app.container.read(sessionEndingProvider.notifier);

      unawaited(notifier.signOut());
      await tester.pump();
      expect(find.byType(AuthInProgressOverlay), findsOneWidget);

      // 저장소가 끝나도 route 가 바뀌기 전에는 남는다.
      app.repoDone.complete();
      await tester.pump();
      await tester.pump(AuthInProgressOverlay.indicatorDelay);
      expect(find.byType(AuthInProgressOverlay), findsOneWidget);
      expect(find.text('로그아웃 처리 중…'), findsOneWidget);
      expect(
        app.container.read(sessionEndingProvider).kind,
        SessionEndingKind.signOut,
      );

      // route 이동 — 전환 첫 프레임들.
      app.router.go(_destinationPath);
      await tester.pump();
      expect(
        find.byType(AuthInProgressOverlay),
        findsOneWidget,
        reason: '새 route 가 push 된 첫 프레임 — 전환이 아직 시작되지 않았다',
      );
      await tester.pump();
      expect(find.byType(AuthInProgressOverlay), findsOneWidget);
      await tester.pump(_midTransition);
      expect(
        find.byType(AuthInProgressOverlay),
        findsOneWidget,
        reason: '전환 도중 — 걷히면 옛 화면이 드러난다',
      );
      expect(find.text(_startText), findsOneWidget, reason: '옛 화면이 아직 아래에 있다');
      expect(find.text(_destinationText), findsOneWidget);
      expect(
        app.container.read(sessionEndingProvider).kind,
        SessionEndingKind.signOut,
      );

      // 이미 그려진 route 가 offstage 가 되는 프레임 (Hero 측정과 같은 모양).
      // 그동안 진입 애니메이션은 `completed` 를 보고하지만 도착이 아니다 —
      // 애니메이션 상태만 보면 여기서 걷힌다.
      final ModalRoute<Object?> destinationRoute = ModalRoute.of(
        tester.element(find.text(_destinationText)),
      )!;
      expect(destinationRoute.animation!.status, AnimationStatus.forward);
      destinationRoute.offstage = true;
      expect(
        destinationRoute.animation!.status,
        AnimationStatus.completed,
        reason: '양성 대조: offstage 동안 애니메이션은 completed 를 보고한다',
      );
      await tester.pump();
      await tester.pump();
      expect(
        find.byType(AuthInProgressOverlay),
        findsOneWidget,
        reason: 'offstage 인 route 는 도착이 아니다',
      );
      expect(
        app.container.read(sessionEndingProvider).kind,
        SessionEndingKind.signOut,
      );
      destinationRoute.offstage = false;
      await tester.pump();
      expect(destinationRoute.animation!.status, AnimationStatus.forward);
      expect(find.byType(AuthInProgressOverlay), findsOneWidget);

      // 전환 종료 → 프레임 뒤 보고 → 다음 프레임에 걷힌다.
      await tester.pump(_transitionDone);
      await tester.pump();
      expect(find.byType(AuthInProgressOverlay), findsNothing);
      expect(find.text(_destinationText), findsOneWidget);
      expect(find.text(_startText), findsNothing);
      expect(app.container.read(sessionEndingProvider), idleSessionEndingState);
    });

    testWidgets('E6C-ARR-02: 역순 — 저장소가 끝나기 전에 route 전환이 끝나도 오버레이 '
        '유지 → 저장소 완료 뒤 없음', (tester) async {
      final app = await _pumpApp(tester);
      final notifier = app.container.read(sessionEndingProvider.notifier);

      unawaited(notifier.signOut());
      await tester.pump();
      expect(find.byType(AuthInProgressOverlay), findsOneWidget);

      app.router.go(_destinationPath);
      await tester.pump();
      await tester.pump();
      await tester.pump(_transitionDone);
      await tester.pump();

      expect(find.text(_destinationText), findsOneWidget);
      expect(find.text(_startText), findsNothing, reason: '전환이 끝났다');
      expect(
        find.byType(AuthInProgressOverlay),
        findsOneWidget,
        reason: '저장소 로그아웃이 아직 끝나지 않았다',
      );
      expect(
        app.container.read(sessionEndingProvider).kind,
        SessionEndingKind.signOut,
      );

      app.repoDone.complete();
      await tester.pump();
      await tester.pump();

      expect(find.byType(AuthInProgressOverlay), findsNothing);
      expect(app.container.read(sessionEndingProvider), idleSessionEndingState);
    });
  });
}
