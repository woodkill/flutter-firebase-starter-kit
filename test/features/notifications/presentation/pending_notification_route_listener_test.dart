// Phase 17 Plan 17-16 — 홈 리스너 · 탭 이동 관통 (T-17-PUSH-03).
//
// 로컬 알림 탭 응답 → 탭 핸들러 → pending(허용 목록) → 홈에 mount 된
// [PendingNotificationRouteListener] 가 소비 → `context.go(route)`.
// 이동은 홈이 그려진 뒤에만 일어난다 — 인증 redirect 를 통과해 홈에 도달한
// 뒤라는 뜻이다(D-04 · Phase 10.2 invariant).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/features/notifications/application/notification_tap_handler.dart';
import 'package:flutter_starter_kit/features/notifications/application/pending_notification_route.dart';
import 'package:flutter_starter_kit/features/notifications/data/local_notifications_service.dart';
import 'package:flutter_starter_kit/features/notifications/data/messaging_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../notification_test_fakes.dart';

/// 테스트 라우터 · 탭 핸들러를 띄운 앱 한 벌.
typedef _App = ({
  ProviderContainer container,
  GoRouter router,
  FakeLocalNotificationsService local,
});

/// fake 를 주입하고 탭 핸들러를 깨운 앱을 그린다.
Future<_App> _pumpApp(WidgetTester tester) async {
  final messaging = FakeMessagingService();
  final local = FakeLocalNotificationsService();
  final container = ProviderContainer(
    overrides: [
      isFirebaseInitializedProvider.overrideWithValue(true),
      messagingServiceProvider.overrideWithValue(messaging),
      localNotificationsServiceProvider.overrideWithValue(local),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(messaging.close);
  final router = buildNotificationTestRouter();
  addTearDown(router.dispose);
  container.listen(notificationTapHandlerProvider, (previous, next) {});

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return (container: container, router: router, local: local);
}

void main() {
  group('Phase 17 알림 수신 · 탭 (T-17-PUSH)', () {
    testWidgets('T-17-PUSH-03: 관통 — 로컬 알림 탭(payload /settings) → pending → '
        '홈 리스너 consume → /settings 이동 · pending 비움', (tester) async {
      final app = await _pumpApp(tester);
      expect(find.text(kTestHomeLabel), findsOneWidget);

      app.local.onTap!('/settings');
      await tester.pumpAndSettle();

      expect(app.router.state.uri.path, '/settings');
      expect(find.text(kTestSettingsLabel), findsOneWidget);
      expect(app.container.read(pendingNotificationRouteProvider), isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('T-17-PUSH-03: 허용 밖 payload(/settings/withdraw) → 이동 0 · '
        '홈 유지 · pending 비움', (tester) async {
      final app = await _pumpApp(tester);

      app.local.onTap!('/settings/withdraw');
      await tester.pumpAndSettle();

      expect(app.router.state.uri.path, '/');
      expect(find.text(kTestHomeLabel), findsOneWidget);
      expect(app.container.read(pendingNotificationRouteProvider), isNull);
    });

    testWidgets('T-17-PUSH-03: 홈 mount 전에 쌓인 pending → 홈 첫 프레임 뒤 '
        '소비해 이동한다', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(pendingNotificationRouteProvider.notifier)
          .set('/settings');
      final router = buildNotificationTestRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(router.state.uri.path, '/settings');
      expect(container.read(pendingNotificationRouteProvider), isNull);
    });
  });
}
