// Phase 17 Plan 17-16 — 알림 route 허용 목록 · pending 저장소 (T-17-PUSH-01).
//
// 알림 payload `data.route` 는 서버(콘솔 운영자)가 보낸 값이다. 허용 목록
// 5개(홈 · 설정 · 계정 · 약관 2)만 그대로 쓰고 그 밖은 홈으로 바꾼다 — 흐름
// 전용 화면 직접 진입 · 외부 URL 주입 차단 (D-04 2026-10-01 정정 · T-17-53 · 54).
// Phase 17.1 D-06 — 계정 화면 추가로 4 → 5.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/core/router/app_routes.dart';
import 'package:flutter_starter_kit/features/notifications/application/notification_route.dart';
import 'package:flutter_starter_kit/features/notifications/application/pending_notification_route.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase 17 알림 수신 · 탭 (T-17-PUSH)', () {
    test(
      'T-17-PUSH-01 · T-171-ROUTER-07: 허용 목록 5개 = 홈 · 설정 · 계정 · 이용약관 · 개인정보처리방침',
      () {
        expect(kNotificationRoutableRoutes, <String>{
          AppRoutes.home,
          AppRoutes.settings,
          AppRoutes.account,
          AppRoutes.termsService,
          AppRoutes.termsPrivacy,
        });
        expect(kNotificationChannelId, 'general');
      },
    );

    for (final (raw, expected) in <(Object?, String)>[
      ('/settings', '/settings'),
      ('/terms/service', '/terms/service'),
      ('/terms/privacy', '/terms/privacy'),
      ('/', '/'),
      ('/settings/withdraw', '/'),
      ('/login', '/'),
      ('/onboarding', '/'),
      ('/splash', '/'),
      ('/verify-email', '/'),
      ('https://evil', '/'),
      ('/settings?x=1', '/'),
      (' /settings', '/'),
      ('', '/'),
      (null, '/'),
      (42, '/'),
    ]) {
      test(
        'T-17-PUSH-01: resolveNotificationRoute(${raw is String ? "'$raw'" : raw}) '
        '→ $expected',
        () {
          expect(resolveNotificationRoute(raw), expected);
        },
      );
    }

    // Phase 17.1 D-06 — 계정 화면은 알림으로 연다 · 데모 경로는 release 에
    // 없는 화면이라 알림으로 열지 않는다(→ 홈).
    test('T-171-ROUTER-08: 계정 경로는 그대로 · 데모 경로는 홈', () {
      expect(
        resolveNotificationRoute('/settings/account'),
        '/settings/account',
      );
      expect(resolveNotificationRoute('/settings/developer'), '/');
    });

    test('T-17-PUSH-01: pending — set 은 허용 목록으로 판정해 저장 · consume 은 '
        '값을 돌려주고 비운다', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(
        pendingNotificationRouteProvider.notifier,
      );
      expect(container.read(pendingNotificationRouteProvider), isNull);

      notifier.set('/settings');
      expect(container.read(pendingNotificationRouteProvider), '/settings');
      expect(notifier.consume(), '/settings');
      expect(container.read(pendingNotificationRouteProvider), isNull);
      expect(notifier.consume(), isNull);

      notifier.set('/settings/withdraw');
      expect(container.read(pendingNotificationRouteProvider), AppRoutes.home);
    });
  });
}
