import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/analytics/analytics_observer.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/router/app_router.dart';
import 'package:flutter_starter_kit/core/router/app_routes.dart';
import 'package:flutter_starter_kit/core/router/auth_guard.dart';
import 'package:flutter_starter_kit/core/router/auth_refresh.dart';
import 'package:flutter_starter_kit/features/auth/presentation/email_login_screen.dart';
import 'package:flutter_starter_kit/features/auth/presentation/login_screen.dart';
import 'package:flutter_starter_kit/features/not_found/presentation/not_found_screen.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

/// authRefresh state 를 움직이기 위한 최소 사용자 mock.
User _authUser() {
  final user = _MockUser();
  when(() => user.uid).thenReturn('router-uid');
  when(() => user.email).thenReturn('router@example.com');
  when(() => user.emailVerified).thenReturn(true);
  when(() => user.isAnonymous).thenReturn(false);
  return user;
}

void main() {
  group('appRouterProvider', () {
    late ProviderContainer container;

    setUp(() {
      final mockAuth = _MockFirebaseAuth();
      when(
        () => mockAuth.authStateChanges(),
      ).thenAnswer((_) => const Stream<User?>.empty());

      container = ProviderContainer(
        overrides: [
          isFirebaseInitializedProvider.overrideWithValue(false),
          firebaseAuthProvider.overrideWithValue(mockAuth),
        ],
      );
    });

    tearDown(() => container.dispose());

    test('GoRouter 인스턴스를 반환한다', () {
      final router = container.read(appRouterProvider);
      expect(router, isA<GoRouter>());
    });

    test('keepAlive Provider이다', () {
      final sub = container.listen(appRouterProvider, (_, _) {});
      sub.close();

      // keepAlive이므로 subscription 해제 후에도 읽을 수 있다
      final router = container.read(appRouterProvider);
      expect(router, isA<GoRouter>());
    });
  });

  // debug notification-task-duplication RC1 (2026-10-03) — Android 는 launch
  // intent 의 extra "route" 를 Flutter 초기 경로(defaultRouteName)로 넘긴다.
  // FCM 은 data 키를 그 extra 로 복사하므로 `data.route=/settings` 알림 탭이
  // 플랫폼 기본 경로 `/settings` 가 된다. 초기 위치는 그와 무관하게 D-14
  // 상태머신 시작점 /splash 여야 한다 — 알림 경로 이동은 홈 리스너(D-04)의 몫.
  group('초기 위치 = /splash 고정 (debug notification-task-duplication RC1)', () {
    /// 플랫폼 기본 경로를 [platformRoute] 로 둔 채 만든 라우터의 초기 위치.
    Future<String> readInitialLocation(
      WidgetTester tester,
      String platformRoute,
    ) async {
      tester.platformDispatcher.defaultRouteNameTestValue = platformRoute;
      addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
      final mockAuth = _MockFirebaseAuth();
      when(
        () => mockAuth.authStateChanges(),
      ).thenAnswer((_) => const Stream<User?>.empty());
      final container = ProviderContainer(
        overrides: [
          isFirebaseInitializedProvider.overrideWithValue(false),
          firebaseAuthProvider.overrideWithValue(mockAuth),
        ],
      );
      addTearDown(container.dispose);
      final router = container.read(appRouterProvider);
      return router.routeInformationProvider.value.uri.toString();
    }

    testWidgets('플랫폼 기본 경로 / (런처 실행) → /splash (대조군)', (tester) async {
      expect(await readInitialLocation(tester, '/'), AppRoutes.splash);
    });

    // 알림 data.route 허용 목록 값 · 목록 밖 흐름 화면 · query 붙은 값.
    for (final platformRoute in const [
      '/settings',
      '/terms/service',
      '/login',
      '/settings?from=fcm',
    ]) {
      testWidgets('플랫폼 기본 경로 $platformRoute (알림 탭 extra) → /splash', (
        tester,
      ) async {
        expect(
          await readInitialLocation(tester, platformRoute),
          AppRoutes.splash,
          reason:
              '알림 intent 의 extra "route" 가 초기 위치가 되면 스플래시 · 홈 리스너 · '
              '허용 목록을 건너뛴다',
        );
      });
    }
  });

  // debug reauth-login-auto-merge (2026-09-17) — 재인증 표시가 guard 뿐 아니라
  // 화면 모드까지 결정한다. 표시를 화면에 넘기지 않으면 재인증 push 가 일반
  // 로그인 화면(연결 안 된 provider · 가입 링크 · 새 로그인)을 그린다.
  group('재인증 표시 → 로그인 흐름 화면 모드 배선 (reauth-login-auto-merge)', () {
    testWidgets('/login · /login/email builder 는 표시가 있을 때만 isReauth=true', (
      tester,
    ) async {
      final mockAuth = _MockFirebaseAuth();
      when(
        () => mockAuth.authStateChanges(),
      ).thenAnswer((_) => const Stream<User?>.empty());
      final container = ProviderContainer(
        overrides: [
          isFirebaseInitializedProvider.overrideWithValue(false),
          firebaseAuthProvider.overrideWithValue(mockAuth),
        ],
      );
      addTearDown(container.dispose);
      final router = container.read(appRouterProvider);
      await tester.pumpWidget(const SizedBox());
      final context = tester.element(find.byType(SizedBox));

      /// production [GoRoute.builder] 를 [location] 상태로 호출한다.
      Widget buildAt(String path, String location) {
        final route = router.configuration.routes
            .whereType<GoRoute>()
            .singleWhere((r) => r.path == path);
        final state = GoRouterState(
          router.configuration,
          uri: Uri.parse(location),
          matchedLocation: path,
          fullPath: path,
          pathParameters: const <String, String>{},
          pageKey: ValueKey<String>(location),
        );
        return route.builder!(context, state);
      }

      expect(
        buildAt(
          AppRoutes.login,
          AppRoutes.buildReauthLocation(AppRoutes.login),
        ),
        isA<LoginScreen>().having((w) => w.isReauth, 'isReauth', isTrue),
      );
      expect(
        buildAt(AppRoutes.login, AppRoutes.login),
        isA<LoginScreen>().having((w) => w.isReauth, 'isReauth', isFalse),
      );
      expect(
        buildAt(
          AppRoutes.emailLogin,
          AppRoutes.buildReauthLocation(AppRoutes.emailLogin),
        ),
        isA<EmailLoginScreen>().having((w) => w.isReauth, 'isReauth', isTrue),
      );
      expect(
        buildAt(AppRoutes.emailLogin, AppRoutes.emailLogin),
        isA<EmailLoginScreen>().having((w) => w.isReauth, 'isReauth', isFalse),
      );
    });
  });

  // Phase 17.1 D-18 · IN-05 — 등록되지 않은 경로는 전용 404 화면으로 간다
  // (home 으로 조용히 넘기지 않는다). 실제 라우터의 errorBuilder 를 직접 호출해
  // 배선만 잠근다 — 404 본문 단언은 not_found_screen_test.dart 가 맡는다.
  group('Phase 17.1 404 배선 (T-171-ROUTER)', () {
    testWidgets(
      'T-171-ROUTER-01: 미등록 경로의 errorBuilder 는 NotFoundScreen 을 만든다',
      (tester) async {
        final mockAuth = _MockFirebaseAuth();
        when(
          () => mockAuth.authStateChanges(),
        ).thenAnswer((_) => const Stream<User?>.empty());
        final container = ProviderContainer(
          overrides: [
            isFirebaseInitializedProvider.overrideWithValue(false),
            firebaseAuthProvider.overrideWithValue(mockAuth),
          ],
        );
        addTearDown(container.dispose);
        final router = container.read(appRouterProvider);
        await tester.pumpWidget(const SizedBox());
        final context = tester.element(find.byType(SizedBox));

        const location = '/no-such-path-171';
        final state = GoRouterState(
          router.configuration,
          uri: Uri.parse(location),
          matchedLocation: location,
          fullPath: location,
          pathParameters: const <String, String>{},
          pageKey: const ValueKey<String>(location),
        );
        final errorBuilder = router.routerDelegate.builder.errorBuilder;

        expect(errorBuilder, isNotNull, reason: '404 는 errorBuilder 로 처리한다');
        expect(errorBuilder!(context, state), isA<NotFoundScreen>());
      },
    );
  });

  group('appRouterProvider 생명주기 회귀 가드 (코드 리뷰 05 CR-01)', () {
    /// [authUserObserverProvider] 를 수동 제어 가능한 스트림으로 대체한 컨테이너.
    ///
    /// 실제 Provider 는 Analytics/Crashlytics/Firestore 를 모두 경유하므로,
    /// 여기서는 `AsyncLoading -> AsyncData -> AsyncError` 전이 자체만
    /// 재현하면 충분하다.
    ProviderContainer makeContainer(StreamController<void> controller) {
      final mockAuth = _MockFirebaseAuth();
      when(
        () => mockAuth.authStateChanges(),
      ).thenAnswer((_) => const Stream<User?>.empty());

      return ProviderContainer(
        overrides: [
          isFirebaseInitializedProvider.overrideWithValue(false),
          firebaseAuthProvider.overrideWithValue(mockAuth),
          authUserObserverProvider.overrideWith((ref) => controller.stream),
        ],
      );
    }

    /// 마이크로태스크 큐를 비운다.
    ///
    /// `AutomatedTestWidgetsFlutterBinding` 아래에서는 [Timer] 가 가짜 시계에
    /// 묶여 `pumpEventQueue` / `Future.delayed` 가 `testWidgets` 밖에서 영원히
    /// 완료되지 않는다. [StreamController] 의 이벤트 전달은 마이크로태스크
    /// 기반이므로 마이크로태스크만 비우면 충분하다.
    Future<void> flushMicrotasks() async {
      for (var i = 0; i < 5; i++) {
        await Future<void>.microtask(() {});
      }
    }

    test(
      'authUserObserver 가 Loading->Data 로 전이해도 GoRouter 인스턴스가 재생성되지 않는다',
      () async {
        // 회귀 대상: `ref.watch(authUserObserverProvider)` 는 콜드 스타트마다
        // 확정 발생하는 AsyncLoading->AsyncData 전이에서 appRouterProvider 를
        // rebuild 시켜 GoRouter 를 통째로 교체했다 (내비게이션 위치 소실).
        final controller = StreamController<void>();
        addTearDown(controller.close);
        final container = makeContainer(controller);
        addTearDown(container.dispose);

        // Riverpod 3 은 listener 가 없는 Provider 를 pause 하므로, 실제 앱
        // (`app.dart` 의 `ref.watch(appRouterProvider)`) 과 동일하게 구독을
        // 유지해야 warm-up 구독이 살아 있다.
        var rebuildCount = 0;
        final sub = container.listen(
          appRouterProvider,
          (_, _) => rebuildCount++,
        );
        addTearDown(sub.close);

        final first = sub.read();
        expect(
          container.read(authUserObserverProvider),
          isA<AsyncLoading<void>>(),
          reason: 'appRouter 가 read 되는 시점에 observer 가 활성화되어 있어야 warm-up 이 성립한다',
        );

        controller.add(null);
        await flushMicrotasks();

        expect(
          container.read(authUserObserverProvider),
          isA<AsyncData<void>>(),
          reason: '전이가 실제로 발생했음을 먼저 확인해야 가드가 유효하다',
        );
        expect(
          rebuildCount,
          0,
          reason: 'Loading->Data 전이는 appRouterProvider 를 rebuild 시켜서는 안 된다',
        );
        expect(
          identical(sub.read(), first),
          isTrue,
          reason: 'Loading->Data 전이는 GoRouter 를 재생성해서는 안 된다',
        );
      },
    );

    test(
      'authUserObserver 가 Data->Error 로 전이해도 GoRouter 인스턴스가 재생성되지 않는다',
      () async {
        final controller = StreamController<void>();
        addTearDown(controller.close);
        final container = makeContainer(controller);
        addTearDown(container.dispose);

        var rebuildCount = 0;
        final sub = container.listen(
          appRouterProvider,
          (_, _) => rebuildCount++,
        );
        addTearDown(sub.close);

        final first = sub.read();
        controller.add(null);
        await flushMicrotasks();
        controller.addError(StateError('auth stream failed'));
        await flushMicrotasks();

        expect(
          container.read(authUserObserverProvider),
          isA<AsyncError<void>>(),
          reason: '에러 전이가 실제로 발생했음을 먼저 확인해야 가드가 유효하다',
        );
        expect(
          rebuildCount,
          0,
          reason: 'Data->Error 전이는 appRouterProvider 를 rebuild 시켜서는 안 된다',
        );
        expect(
          identical(sub.read(), first),
          isTrue,
          reason: '세션 중간의 Data->Error 전이가 화면을 초기 위치로 리셋해서는 안 된다',
        );
      },
    );

    test('컨테이너 파기 시 GoRouter 가 dispose 되어 refreshListenable 구독이 해제된다', () {
      // 회귀 대상: ref.onDispose(router.dispose) 부재로 죽은 라우터의
      // routeInformationProvider 가 refresh 어댑터의 listener 로 잔존했다.
      final controller = StreamController<void>();
      addTearDown(controller.close);
      final container = makeContainer(controller);

      final router = container.read(appRouterProvider);
      container.dispose();

      expect(
        () => router.routerDelegate.addListener(() {}),
        throwsA(isA<FlutterError>()),
        reason: 'dispose 된 ChangeNotifier 는 addListener 에서 FlutterError 를 던진다',
      );
    });

    test('CR-01 (CR-01-ROUTER-IDENTITY): authRefresh state 가 여러 번 바뀌어도 '
        'GoRouter 인스턴스가 유지된다', () async {
      // 신규 가드 (quick 260920-b28). 옛 배선은
      // 옛 provider 를 `ref.watch` 하는 배선이었으므로 재생성이 곧
      // appRouterProvider rebuild = GoRouter 교체였다. 새 배선은
      // `ref.listen` 이라 authRefresh 의 state 가 몇 번 바뀌어도 라우터가
      // 그대로여야 한다 — 바뀌면 사용자의 현재 화면이 initialLocation 으로
      // 폐기된다.
      final observerController = StreamController<void>();
      addTearDown(observerController.close);
      final authController = StreamController<User?>();
      addTearDown(authController.close);

      final mockAuth = _MockFirebaseAuth();
      when(
        () => mockAuth.userChanges(),
      ).thenAnswer((_) => authController.stream);
      final container = ProviderContainer(
        overrides: [
          isFirebaseInitializedProvider.overrideWithValue(true),
          firebaseAuthProvider.overrideWithValue(mockAuth),
          // 실제 Firebase App 없이 analyticsObserver 를 만들 수 있도록
          // no-op observer 로 대체한다 (본 가드의 검증 범위 외).
          analyticsObserverProvider.overrideWithValue(NavigatorObserver()),
          authUserObserverProvider.overrideWith(
            (ref) => observerController.stream,
          ),
        ],
      );
      addTearDown(container.dispose);

      var rebuildCount = 0;
      final sub = container.listen(appRouterProvider, (_, _) => rebuildCount++);
      addTearDown(sub.close);

      final first = sub.read();

      // (a) 스트림 emit 2회 + (b) 강제 재평가 1회 = state 변화 3회.
      authController.add(null);
      await flushMicrotasks();
      authController.add(_authUser());
      await flushMicrotasks();
      container.read(authRefreshProvider.notifier).triggerRedirect();
      await flushMicrotasks();

      expect(
        container.read(authRefreshProvider),
        isNot(initialAuthRefreshState),
        reason: 'state 가 실제로 바뀌었음을 먼저 확인해야 가드가 유효하다',
      );
      expect(
        rebuildCount,
        0,
        reason: 'authRefresh state 변화는 appRouterProvider 를 rebuild 시켜서는 안 된다',
      );
      expect(
        identical(sub.read(), first),
        isTrue,
        reason:
            'CR-01 — 인증 상태가 바뀔 때마다 GoRouter 가 재생성되면 내비게이션 '
            '위치가 initialLocation 으로 폐기된다',
      );
    });

    test('WR-04: 초기화 성공 경로에서도 컨테이너 파기 시 라우터가 dispose 되고 구독이 취소된다', () async {
      // WR-04 는 "초기화 실패 분기에서만 정리를 빠뜨렸다" 는 버그였다. 위
      // dispose 테스트가 실패 경로(makeContainer 는 isInitialized=false)를
      // 이미 덮으므로, 여기서는 성공 경로가 같은 계약을 만족함을 고정한다.
      final observerController = StreamController<void>();
      addTearDown(observerController.close);
      final authController = StreamController<User?>();
      addTearDown(authController.close);

      final mockAuth = _MockFirebaseAuth();
      when(
        () => mockAuth.userChanges(),
      ).thenAnswer((_) => authController.stream);
      final container = ProviderContainer(
        overrides: [
          isFirebaseInitializedProvider.overrideWithValue(true),
          firebaseAuthProvider.overrideWithValue(mockAuth),
          // 실제 Firebase App 없이 analyticsObserver 를 만들 수 있도록
          // no-op observer 로 대체한다 (본 가드의 검증 범위 외).
          analyticsObserverProvider.overrideWithValue(NavigatorObserver()),
          authUserObserverProvider.overrideWith(
            (ref) => observerController.stream,
          ),
        ],
      );

      final router = container.read(appRouterProvider);
      expect(authController.hasListener, isTrue);

      container.dispose();

      expect(
        () => router.routerDelegate.addListener(() {}),
        throwsA(isA<FlutterError>()),
        reason: '컨테이너 파기 시 라우터가 dispose 되어야 한다',
      );
      expect(
        authController.hasListener,
        isFalse,
        reason: 'authRefresh 구독도 함께 취소되어야 누수가 없다',
      );
    });

    test('WR-04: refresh 어댑터는 dispose 후 addListener 에서 FlutterError 를 던진다', () {
      // 어댑터는 appRouter 의 구현 세부라 컨테이너 밖에서 인스턴스를 얻을 수
      // 없다. 대신 (a) 타입 자체가 올바른 dispose 계약을 갖는지와
      // (b) appRouter 가 그 dispose 를 라우터 **다음에** 등록하는지를 나누어
      // 잠근다. 두 단언이 함께 "죽은 라우터가 어댑터 listener 로 잔존" 회귀를
      // 막는다.
      final listenable = RouterRefreshListenable()..notifyRefresh();

      listenable.dispose();

      expect(() => listenable.addListener(() {}), throwsA(isA<FlutterError>()));
    });

    test('WR-04: appRouter 가 라우터 → 어댑터 순서로 onDispose 를 등록한다', () async {
      // 등록 순서가 곧 실행 순서다. 뒤집히면 이미 dispose 된 어댑터에 라우터가
      // removeListener 를 호출한다. 소스 검증 (Test 5 INFO #21 패턴).
      final source = await File(
        'lib/core/router/app_router.dart',
      ).readAsString();

      final routerDispose = source.indexOf('ref.onDispose(router.dispose)');
      final adapterDispose = source.indexOf(
        'ref.onDispose(refreshListenable.dispose)',
      );

      expect(routerDispose, greaterThan(-1), reason: '라우터 dispose 등록이 있어야 한다');
      expect(adapterDispose, greaterThan(-1), reason: '어댑터 dispose 등록이 있어야 한다');
      expect(
        routerDispose,
        lessThan(adapterDispose),
        reason: '라우터가 먼저 listener 를 떼고 나서 어댑터가 dispose 되어야 한다',
      );
    });
  });
}
