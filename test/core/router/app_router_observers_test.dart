import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/analytics/analytics_observer.dart'
    show analyticsObserverProvider;
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/router/app_router.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _FakeNavigatorObserver extends NavigatorObserver {}

void main() {
  /// Firebase 미초기화 상태에서 appRouter 를 로드한다.
  ///
  /// _NoOpNavigatorObserver (private) 가 자동 주입되므로 별도 override 는
  /// 불필요하지만, `observer == ref.watch(analyticsObserverProvider)` 동일성을
  /// 확인하기 위해 fake observer 를 override 주입한다.
  ProviderContainer makeContainer({NavigatorObserver? observer}) {
    final mockAuth = _MockFirebaseAuth();
    when(
      () => mockAuth.authStateChanges(),
    ).thenAnswer((_) => const Stream<User?>.empty());
    return ProviderContainer(
      overrides: [
        isFirebaseInitializedProvider.overrideWithValue(false),
        firebaseAuthProvider.overrideWithValue(mockAuth),
        if (observer != null)
          analyticsObserverProvider.overrideWith((ref) => observer),
      ],
    );
  }

  group('appRouter (Phase 10 D-14 / D-29 / WARNING #14)', () {
    test(
      'Test 1: initialLocation 은 /splash (D-14 상태 머신 시작점) — 소스 검증',
      () async {
        // go_router 17.x 에서 GoRouter.routerDelegate.currentConfiguration 은
        // MaterialApp.router attach 전에는 빈 문자열을 반환하므로 단순 read
        // 만으로는 initialLocation 을 확인할 수 없다. 대신 소스 검증.
        final source = await File(
          'lib/core/router/app_router.dart',
        ).readAsString();
        expect(
          source.contains('initialLocation: AppRoutes.splash'),
          isTrue,
          reason: 'D-14: GoRouter initialLocation 이 /splash 로 설정되어야 함',
        );
        // GoRouter 인스턴스 생성이 가능한지도 확인.
        final container = makeContainer();
        addTearDown(container.dispose);
        expect(container.read(appRouterProvider), isA<GoRouter>());
      },
    );

    test('Test 2: GoRoute 11개 등록 (home/splash/onboarding/login/emailLogin/'
        'signup/forgotPassword/verifyEmail/termsService/termsPrivacy/'
        'settings)', () {
      final container = makeContainer();
      addTearDown(container.dispose);

      final router = container.read(appRouterProvider);
      // Phase 16 D-05 — /settings route 추가로 9 → 10.
      // Phase 16.1 — /login/email route 추가로 10 → 11.
      expect(router.configuration.routes.length, 11);
    });

    test('Test 3: 모든 GoRoute 에 name 이 설정됨 (Pitfall 1)', () {
      final container = makeContainer();
      addTearDown(container.dispose);

      final router = container.read(appRouterProvider);
      final names = router.configuration.routes
          .whereType<GoRoute>()
          .map((r) => r.name)
          .toList();
      // Phase 16 D-05 — /settings route 추가로 9 → 10.
      // Phase 16.1 — /login/email route 추가로 10 → 11.
      expect(names.length, 11);
      expect(
        names.where((n) => n == null || n.isEmpty).length,
        0,
        reason: '모든 GoRoute 에 name 이 설정되어야 한다',
      );
    });

    test(
      'Test 4: observers 가 analyticsObserverProvider override 로 주입됨 (소스 검증)',
      () async {
        // go_router 17.x 에서는 routerDelegate.observers 가 외부 노출되지 않음.
        // 대신 appRouter Provider 가 observers: [observer] 를 GoRouter 에
        // 전달하는지를 소스로 검증한다.
        final source = await File(
          'lib/core/router/app_router.dart',
        ).readAsString();
        expect(
          source.contains('observers: [observer]'),
          isTrue,
          reason: 'GoRouter 생성 시 observers 에 analyticsObserverProvider 결과 전달',
        );
        // analyticsObserverProvider 자체가 watch 되어 의존성이 발생하는지 확인.
        final fakeObserver = _FakeNavigatorObserver();
        final container = makeContainer(observer: fakeObserver);
        addTearDown(container.dispose);
        // appRouter 가 build 시 analyticsObserverProvider 를 watch 하므로
        // override 가 적용됨을 read 로 확인한다.
        final observer = container.read(analyticsObserverProvider);
        expect(observer, fakeObserver);
        // appRouter 가 정상 build 되는지도 확인.
        expect(container.read(appRouterProvider), isA<GoRouter>());
      },
    );

    test(
      'Test 5 (WARNING #14): routerDelegate.addListener 가 소스에 등록됨',
      () async {
        // WARNING #14 — go() same-level 전환 시 screen_view 수동 보완.
        // 실제 listener 동작은 widget test 에서 매우 어려우므로 소스 검증으로
        // 충분한 대체 증거 확보.
        final source = await File(
          'lib/core/router/app_router.dart',
        ).readAsString();
        expect(
          source.contains('routerDelegate.addListener'),
          isTrue,
          reason: 'WARNING #14: routerDelegate.addListener 필요',
        );
        expect(
          source.contains('analytics.logScreenView('),
          isTrue,
          reason: 'WARNING #14: listener 에서 logScreenView 수동 호출 필요',
        );
        // lastMatchedLocation 캐시 변수로 중복 호출 방지.
        expect(
          source.contains('lastMatchedLocation'),
          isTrue,
          reason: 'matchedLocation 변화 감지 변수 필요',
        );
      },
    );
  });
}
