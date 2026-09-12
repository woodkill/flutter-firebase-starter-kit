import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/router/app_router.dart';
import 'package:flutter_starter_kit/core/router/auth_guard.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

/// 404 [buildNotFoundScreen] 본문을 지정한 [locale] 로 pump 한다.
///
/// GoRouter 전체 스택 없이 errorBuilder 의 본문 위젯만 직접 검증한다.
Future<void> _pumpNotFound(
  WidgetTester tester, {
  required Locale locale,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Builder(builder: buildNotFoundScreen),
    ),
  );
  await tester.pumpAndSettle();
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
      // routeInformationProvider 가 AuthChangeNotifier listener 로 잔존했다.
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
  });

  group('errorBuilder (buildNotFoundScreen)', () {
    testWidgets('1. en 로케일에서 l10n 제목/본문/CTA + error_outline 렌더', (
      tester,
    ) async {
      await _pumpNotFound(tester, locale: const Locale('en'));

      // AppBar title 과 body title 두 곳에 동일 텍스트가 노출될 수 있다.
      expect(find.text('Page not found'), findsAtLeastNWidgets(1));
      expect(
        find.text('The page you requested does not exist.'),
        findsOneWidget,
      );
      expect(find.text('Go home'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.widgetWithIcon(FilledButton, Icons.home), findsOneWidget);
    });

    testWidgets('2. ko 로케일에서 한글 l10n 제목/본문/CTA 렌더', (tester) async {
      await _pumpNotFound(tester, locale: const Locale('ko'));

      expect(find.text('페이지를 찾을 수 없습니다'), findsAtLeastNWidgets(1));
      expect(find.text('요청하신 페이지가 존재하지 않습니다.'), findsOneWidget);
      expect(find.text('홈으로'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
    });
  });
}
