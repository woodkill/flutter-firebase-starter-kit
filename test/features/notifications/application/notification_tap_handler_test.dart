// Phase 17 Plan 17-16 — 알림 수신 표시 · 탭 핸들러 (T-17-PUSH).
//
// - 포그라운드 수신(`onMessage`)은 Android 에서만 로컬 알림을 띄운다 — iOS 는
//   presentation options 로 OS 가 표시한다(중복 0 · D-01).
// - 로컬 알림 래퍼는 채널 `general` · 아이콘 `ic_notification` · importance
//   high · 색 #673AB7 · payload = `data.route` 로 플러그인을 부른다(UI-SPEC (O)).
//
// SDK 는 래퍼 fake 로 바꾼다 — firebase_messaging 의 수신 스트림은 static
// getter 라 인스턴스 mock 이 불가하다(STATE Wave 4 메모 ①). 로컬 알림
// 플러그인 자체는 mocktail 로 바꿔 래퍼가 넘기는 인자를 단언한다.

import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
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
});

/// fake 를 주입한 container 를 만들고 [notificationTapHandlerProvider] 를 깨운다.
_Harness _startHandler({bool initialized = true}) {
  final messaging = FakeMessagingService();
  final local = FakeLocalNotificationsService();
  final container = ProviderContainer(
    overrides: [
      isFirebaseInitializedProvider.overrideWithValue(initialized),
      messagingServiceProvider.overrideWithValue(messaging),
      localNotificationsServiceProvider.overrideWithValue(local),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(messaging.close);
  container.listen(notificationTapHandlerProvider, (previous, next) {});
  return (container: container, messaging: messaging, local: local);
}

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
