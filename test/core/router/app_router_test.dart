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
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/core/theme/app_typography.dart';
import 'package:flutter_starter_kit/features/auth/presentation/email_login_screen.dart';
import 'package:flutter_starter_kit/features/auth/presentation/login_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

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

    testWidgets(
      '3 (IN-01): AppTypography extension override 를 따라간다 (drift 차단)',
      (tester) async {
        // 회귀 대상: `context.textTheme` 은 AppTypography extension override 를
        // 반영하지 않으므로, 사용자가 ThemeData 를 교체하면 404 화면만 나머지
        // 화면과 다르게 drift 한다 (저장소 dominant 규약은 context.appTypography).
        const overrideTitle = TextStyle(fontSize: 29, letterSpacing: 7);
        const overrideBody = TextStyle(fontSize: 17, wordSpacing: 5);
        final base = AppTheme.light();

        await tester.pumpWidget(
          MaterialApp(
            // AppTypography extension 만 교체한다 (나머지 토큰은 ThemeX
            // 접근자의 폴백이 커버하므로 본 검증에 영향이 없다).
            theme: base.copyWith(
              extensions: [
                AppTypography.empty.copyWith(
                  titleLarge: overrideTitle,
                  bodyMedium: overrideBody,
                ),
              ],
            ),
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Builder(builder: buildNotFoundScreen),
          ),
        );
        await tester.pumpAndSettle();

        final title = tester.widget<Text>(
          find.descendant(
            of: find.byType(Column),
            matching: find.text('Page not found'),
          ),
        );
        expect(
          title.style?.fontSize,
          29,
          reason: '제목은 AppTypography override 의 titleLarge 를 따라야 한다',
        );
        expect(title.style?.letterSpacing, 7);

        final body = tester.widget<Text>(
          find.text('The page you requested does not exist.'),
        );
        expect(
          body.style?.fontSize,
          17,
          reason: '본문은 AppTypography override 의 bodyMedium 을 따라야 한다',
        );
        expect(body.style?.wordSpacing, 5);
        expect(
          body.style?.color,
          base.colorScheme.onSurfaceVariant,
          reason: 'copyWith 로 얹는 색 토큰은 유지되어야 한다',
        );

        final icon = tester.widget<Icon>(find.byIcon(Icons.error_outline));
        expect(icon.size, 64, reason: '명명 상수 _notFoundIconSize 값 고정');
      },
    );
  });

  group('404 화면 가로 모드 (Phase 3 D-09 · quick 261003-0fp)', () {
    for (final size in _landscapeSizes) {
      for (final locale in _sweepLocales) {
        final label = '${_formatSize(size)} · ${locale.languageCode}';

        testWidgets('NF ($label): 404 넘침 0 · 홈으로 도달 · 261003-0fp', (
          tester,
        ) async {
          _setLogicalViewport(tester, size);
          await _pumpNotFound(tester, locale: locale);
          expect(tester.takeException(), isNull, reason: '$label 404');

          final goHome = find.widgetWithText(
            FilledButton,
            lookupAppLocalizations(locale).errorNotFoundGoHomeCta,
          );
          await tester.ensureVisible(goHome);
          await tester.pumpAndSettle();
          expect(goHome.hitTestable(), findsOneWidget, reason: '$label 홈으로 도달');
          expect(tester.takeException(), isNull, reason: '$label 마지막');
        });
      }
    }

    testWidgets('P (360x800 · ko): 404 세로 rect 고정 · 261003-0fp', (
      tester,
    ) async {
      _setLogicalViewport(tester, _portraitSize);
      await _pumpNotFound(tester, locale: const Locale('ko'));
      expect(tester.takeException(), isNull);

      final l10n = lookupAppLocalizations(const Locale('ko'));
      final icon = find.byIcon(Icons.error_outline);
      final actual = <Rect>[
        tester.getRect(
          find.ancestor(of: icon, matching: find.byType(Column)).first,
        ),
        tester.getRect(icon),
        tester.getRect(find.text(l10n.errorNotFoundBody)),
        tester.getRect(find.byType(FilledButton)),
      ];
      const expected = _portraitNotFoundRects;
      expect(actual.length, expected.length);
      for (var i = 0; i < expected.length; i++) {
        _expectRectNear(actual[i], expected[i], reason: '#$i');
      }
    });
  });
}

/// 가로 모드 점검 크기 (logical px).
///
/// - 780x360: SM-S942N 가로 실측 w780dp h360dp.
/// - 560x280: 지원 최소 폭 280dp 의 가로 — 최악.
const _landscapeSizes = <Size>[Size(780, 360), Size(560, 280)];

/// 세로 rect 고정 가드(P) 크기 — 일반 세로 폰.
const _portraitSize = Size(360, 800);

/// 점검 언어 — ko 먼저(R2), en, ja.
const _sweepLocales = <Locale>[Locale('ko'), Locale('en'), Locale('ja')];

/// 테스트 view 를 logical [size] 로 맞춘다 (DPR 1.0 · pump 전에 호출).
///
/// `setSurfaceSize` 는 MediaQuery 를 갱신하지 않으므로 쓰지 않는다
/// (quick 260929-pze 선례).
void _setLogicalViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// [size] 를 테스트 이름용 `WxH` 문자열로 만든다.
String _formatSize(Size size) => '${size.width.toInt()}x${size.height.toInt()}';

/// [actual] 의 네 변이 [expected] 와 ±0.5 안인지 단언한다.
void _expectRectNear(Rect actual, Rect expected, {required String reason}) {
  expect(actual.left, closeTo(expected.left, 0.5), reason: '$reason left');
  expect(actual.top, closeTo(expected.top, 0.5), reason: '$reason top');
  expect(actual.right, closeTo(expected.right, 0.5), reason: '$reason right');
  expect(
    actual.bottom,
    closeTo(expected.bottom, 0.5),
    reason: '$reason bottom',
  );
}

/// 360x800 · ko 404 본문의 수정 전 rect — 본문 Column · 아이콘 · 안내 문구 ·
/// 「홈으로」 버튼 (quick 261003-0fp 가 lib 수정 전 트리에서 실측).
const _portraitNotFoundRects = <Rect>[
  Rect.fromLTRB(26, 324, 334, 532),
  Rect.fromLTRB(148, 324, 212, 388),
  Rect.fromLTRB(37.5, 440, 322.5, 460),
  Rect.fromLTRB(125.9, 484, 234.1, 532),
];
