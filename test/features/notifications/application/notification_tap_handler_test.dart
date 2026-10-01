// Phase 17 Plan 17-16 — 알림 수신 표시 · 탭 핸들러 (T-17-PUSH).
//
// - 포그라운드 수신(`onMessage`)은 Android 에서만 로컬 알림을 띄운다 — iOS 는
//   presentation options 로 OS 가 표시한다(중복 0 · D-01).
// - 로컬 알림 래퍼는 채널 `general` · 아이콘 `ic_notification` · importance
//   high · 색 #673AB7 · payload = `data.route` 로 플러그인을 부른다(UI-SPEC (O)).
//
// - 탭 3경로(로컬 알림 payload · 백그라운드 `onMessageOpenedApp` · 종료
//   `getInitialMessage` + 로컬 launch details)가 pending 으로 모이고, 홈
//   리스너가 홈이 그려진 뒤 소비한다(D-04).
// - 채널 이름 · 설명은 앱 언어로 등록 · 갱신(D-31) · iOS 는 presentation
//   options 1회(D-01).
//
// SDK 는 래퍼 fake 로 바꾼다 — firebase_messaging 의 수신 스트림은 static
// getter 라 인스턴스 mock 이 불가하다(STATE Wave 4 메모 ①). 로컬 알림
// 플러그인 자체는 mocktail 로 바꿔 래퍼가 넘기는 인자를 단언한다.

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/providers/locale_provider.dart';
import 'package:flutter_starter_kit/features/notifications/application/notification_tap_handler.dart';
import 'package:flutter_starter_kit/features/notifications/application/pending_notification_route.dart';
import 'package:flutter_starter_kit/features/notifications/data/local_notifications_service.dart';
import 'package:flutter_starter_kit/features/notifications/data/messaging_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../notification_test_fakes.dart';

class _MockPlugin extends Mock implements FlutterLocalNotificationsPlugin {}

/// 탭 핸들러를 깨운 container 와 fake 묶음.
typedef _Harness = ({
  ProviderContainer container,
  FakeMessagingService messaging,
  FakeLocalNotificationsService local,
  FixedLocaleNotifier locale,
});

/// fake 를 주입한 container 를 만든다 — 탭 핸들러는 아직 깨우지 않는다.
///
/// [initialMessage] 는 종료 상태 FCM 탭, [launchPayload] 는 로컬 알림 탭으로
/// 앱이 시작된 경우를 흉내 낸다.
_Harness _buildHarness({
  bool initialized = true,
  RemoteMessage? initialMessage,
  String? launchPayload,
}) {
  final messaging = FakeMessagingService(initialMessage: initialMessage);
  final local = FakeLocalNotificationsService(
    launchPayloadValue: launchPayload,
  );
  final locale = FixedLocaleNotifier(const Locale('ko'));
  final container = ProviderContainer(
    overrides: [
      isFirebaseInitializedProvider.overrideWithValue(initialized),
      messagingServiceProvider.overrideWithValue(messaging),
      localNotificationsServiceProvider.overrideWithValue(local),
      localeProvider.overrideWith(() => locale),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(messaging.close);
  return (
    container: container,
    messaging: messaging,
    local: local,
    locale: locale,
  );
}

/// [_buildHarness] 뒤 [notificationTapHandlerProvider] 를 깨운다.
_Harness _startHandler({
  bool initialized = true,
  RemoteMessage? initialMessage,
  String? launchPayload,
}) {
  final h = _buildHarness(
    initialized: initialized,
    initialMessage: initialMessage,
    launchPayload: launchPayload,
  );
  h.container.listen(notificationTapHandlerProvider, (previous, next) {});
  return h;
}

/// route [route] 를 실은 알림 메시지.
RemoteMessage _routeMessage(String? route) => buildRemoteMessage(
  title: 'T',
  body: 'B',
  data: <String, dynamic>{'route': ?route},
);

void main() {
  setUpAll(() {
    registerFallbackValue(const NotificationDetails());
  });

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('Phase 17 알림 수신 · 탭 (T-17-PUSH)', () {
    test('T-17-PUSH-02: 관통 — Android 포그라운드 notification 메시지 → 로컬 '
        '알림 1회(제목 · 본문 그대로 · payload = data.route)', () async {
      final h = _startHandler();
      await pumpEventQueue();

      h.messaging.foreground.add(
        buildRemoteMessage(
          title: 'T',
          body: 'B',
          data: <String, dynamic>{'route': '/settings'},
        ),
      );
      await pumpEventQueue();

      expect(h.local.shown, <ShownNotification>[
        (title: 'T', body: 'B', route: '/settings'),
      ]);
    });

    test('T-17-PUSH-02: iOS 포그라운드 → 로컬 알림 0 (OS 가 표시 · 중복 0)', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final h = _startHandler();
      await pumpEventQueue();

      h.messaging.foreground.add(
        buildRemoteMessage(
          title: 'T',
          body: 'B',
          data: <String, dynamic>{'route': '/settings'},
        ),
      );
      await pumpEventQueue();

      expect(h.local.shown, isEmpty);
    });

    test('T-17-PUSH-02: notification 없는 data-only 메시지 → 로컬 알림 0', () async {
      final h = _startHandler();
      await pumpEventQueue();

      h.messaging.foreground.add(
        buildRemoteMessage(data: <String, dynamic>{'route': '/settings'}),
      );
      await pumpEventQueue();

      expect(h.local.shown, isEmpty);
    });

    test('T-17-PUSH-02: route 없는 메시지 → payload null 로 표시', () async {
      final h = _startHandler();
      await pumpEventQueue();

      h.messaging.foreground.add(buildRemoteMessage(title: 'T', body: 'B'));
      await pumpEventQueue();

      expect(h.local.shown, <ShownNotification>[
        (title: 'T', body: 'B', route: null),
      ]);
    });

    test('T-17-PUSH-02: Firebase 미초기화 → 구독 0 · 로컬 알림 초기화 0 · '
        'throw 0 (Phase 1 D-13)', () async {
      final h = _startHandler(initialized: false);
      await pumpEventQueue();

      expect(h.messaging.foreground.hasListener, isFalse);
      expect(h.messaging.openedApp.hasListener, isFalse);
      expect(h.local.onTap, isNull);
      expect(h.messaging.initialMessageCalls, 0);
    });

    test('T-17-PUSH-02: 로컬 알림 탭 응답 payload → pending 이 허용 목록으로 '
        '판정해 저장한다', () async {
      final h = _startHandler();
      await pumpEventQueue();

      h.local.onTap!('/settings');
      expect(h.container.read(pendingNotificationRouteProvider), '/settings');

      h.local.onTap!('/login');
      expect(h.container.read(pendingNotificationRouteProvider), '/');
    });
  });

  group('Phase 17 알림 탭 3경로 · 채널 언어 (T-17-PUSH)', () {
    test('T-17-PUSH-04: 백그라운드 탭(onMessageOpenedApp · route /settings) → '
        'pending /settings', () async {
      final h = _startHandler();
      await pumpEventQueue();

      h.messaging.openedApp.add(_routeMessage('/settings'));
      await pumpEventQueue();

      expect(h.container.read(pendingNotificationRouteProvider), '/settings');
    });

    test('T-17-PUSH-04: 백그라운드 탭 허용 밖 route → pending 홈', () async {
      final h = _startHandler();
      await pumpEventQueue();

      h.messaging.openedApp.add(_routeMessage('/settings/withdraw'));
      await pumpEventQueue();

      expect(h.container.read(pendingNotificationRouteProvider), '/');
    });

    test('T-17-PUSH-05: 종료 탭 — getInitialMessage(route /settings) → '
        'pending /settings · 로컬 launch details 조회 0', () async {
      final h = _startHandler(initialMessage: _routeMessage('/settings'));
      await pumpEventQueue();

      expect(h.container.read(pendingNotificationRouteProvider), '/settings');
      expect(h.messaging.initialMessageCalls, 1);
      expect(h.local.launchPayloadCalls, 0);
    });

    test('T-17-PUSH-05: 종료 탭 — 로컬 알림 launch payload /settings → '
        'pending /settings', () async {
      final h = _startHandler(launchPayload: '/settings');
      await pumpEventQueue();

      expect(h.container.read(pendingNotificationRouteProvider), '/settings');
      expect(h.local.launchPayloadCalls, 1);
    });

    test(
      'T-17-PUSH-05: 초기 메시지 · launch payload 둘 다 없음 → pending null',
      () async {
        final h = _startHandler();
        await pumpEventQueue();

        expect(h.container.read(pendingNotificationRouteProvider), isNull);
        expect(h.messaging.initialMessageCalls, 1);
        expect(h.local.launchPayloadCalls, 1);
      },
    );

    testWidgets('T-17-PUSH-05: 스플래시 단계에서는 pending 유지 → 홈 mount 뒤 '
        '소비해 /settings 로 이동', (tester) async {
      final h = _buildHarness(initialMessage: _routeMessage('/settings'));
      final router = buildNotificationTestRouter(initialLocation: '/splash');
      addTearDown(router.dispose);
      h.container.listen(notificationTapHandlerProvider, (previous, next) {});

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: h.container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(kTestSplashLabel), findsOneWidget);
      expect(h.container.read(pendingNotificationRouteProvider), '/settings');

      router.go('/');
      await tester.pumpAndSettle();

      expect(router.state.uri.path, '/settings');
      expect(find.text(kTestSettingsLabel), findsOneWidget);
      expect(h.container.read(pendingNotificationRouteProvider), isNull);
      expect(tester.takeException(), isNull);
    });

    test('T-17-PUSH-06: 시작 때 채널을 앱 언어(ko)로 1회 등록 · ja 로 바꾸면 같은 '
        'id 로 ja 이름 1회 더', () async {
      final h = _startHandler();
      await pumpEventQueue();

      expect(h.local.channels, <RegisteredChannel>[
        (name: '일반 알림', description: '이 앱에서 보내는 알림입니다.'),
      ]);

      h.locale.select(const Locale('ja'));
      await pumpEventQueue();

      expect(h.local.channels, <RegisteredChannel>[
        (name: '일반 알림', description: '이 앱에서 보내는 알림입니다.'),
        (name: '一般の通知', description: 'このアプリから送信される通知です。'),
      ]);
    });

    test('T-17-PUSH-06: iOS → 포그라운드 표시 옵션 1회 · Android → 0', () async {
      final android = _startHandler();
      await pumpEventQueue();
      expect(android.messaging.presentationOptionsCalls, 0);

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final ios = _startHandler();
      await pumpEventQueue();
      expect(ios.messaging.presentationOptionsCalls, 1);
    });

    test('T-17-PUSH-06: Firebase 미초기화 → 채널 등록 · 초기 메시지 조회 · '
        '표시 옵션 0', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final h = _startHandler(initialized: false);
      await pumpEventQueue();

      expect(h.local.channels, isEmpty);
      expect(h.local.launchPayloadCalls, 0);
      expect(h.messaging.initialMessageCalls, 0);
      expect(h.messaging.presentationOptionsCalls, 0);
    });
  });

  group('Phase 17 로컬 알림 래퍼 (T-17-PUSH)', () {
    late _MockPlugin plugin;
    late LocalNotificationsService service;

    setUp(() {
      plugin = _MockPlugin();
      service = LocalNotificationsService(plugin);
      when(
        () => plugin.show(
          id: any(named: 'id'),
          title: any(named: 'title'),
          body: any(named: 'body'),
          notificationDetails: any(named: 'notificationDetails'),
          payload: any(named: 'payload'),
        ),
      ).thenAnswer((_) async {});
    });

    test('T-17-PUSH-02: showRemote → 채널 general · 아이콘 ic_notification · '
        'importance high · 색 #673AB7 · payload route', () async {
      await service.showRemote(title: 'T', body: 'B', route: '/settings');

      final captured = verify(
        () => plugin.show(
          id: any(named: 'id'),
          title: 'T',
          body: 'B',
          notificationDetails: captureAny(named: 'notificationDetails'),
          payload: '/settings',
        ),
      ).captured;
      expect(captured, hasLength(1));
      final android = (captured.single as NotificationDetails).android!;
      expect(android.channelId, 'general');
      expect(android.icon, 'ic_notification');
      expect(android.importance, Importance.high);
      expect(android.priority, Priority.high);
      expect(android.color, const Color(0xFF673AB7));
    });

    test('T-17-PUSH-02: iOS 에서 showRemote → 플러그인 호출 0', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await service.showRemote(title: 'T', body: 'B', route: '/settings');

      verifyNever(
        () => plugin.show(
          id: any(named: 'id'),
          title: any(named: 'title'),
          body: any(named: 'body'),
          notificationDetails: any(named: 'notificationDetails'),
          payload: any(named: 'payload'),
        ),
      );
    });

    test('T-17-PUSH-02: 플러그인 show 실패 → throw 0 (best-effort)', () async {
      when(
        () => plugin.show(
          id: any(named: 'id'),
          title: any(named: 'title'),
          body: any(named: 'body'),
          notificationDetails: any(named: 'notificationDetails'),
          payload: any(named: 'payload'),
        ),
      ).thenThrow(StateError('boom'));

      await expectLater(
        service.showRemote(title: 'T', body: 'B', route: null),
        completes,
      );
    });
  });
}
