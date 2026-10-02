// Phase 17 리뷰 IN-16 — 포그라운드 로컬 알림 id 가 서로 덮어쓰지 않는다.
//
// 플러그인은 mocktail 로 대체하고, Android 분기만 실행되므로
// `debugDefaultTargetPlatformOverride` 로 Android 를 흉내 낸다.

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_starter_kit/features/notifications/data/local_notifications_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPlugin extends Mock implements FlutterLocalNotificationsPlugin {}

void main() {
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('T-17-PUSH-09: 연달아 온 메시지 3건은 서로 다른 · 증가하는 id 로 '
      '표시된다 (리뷰 IN-16)', () async {
    final plugin = _MockPlugin();
    when(
      () => plugin.show(
        id: any(named: 'id'),
        title: any(named: 'title'),
        body: any(named: 'body'),
        notificationDetails: any(named: 'notificationDetails'),
        payload: any(named: 'payload'),
      ),
    ).thenAnswer((_) async {});
    final service = LocalNotificationsService(plugin);

    // 같은 초(같은 밀리초일 수도 있다) 안에 3건.
    for (var i = 0; i < 3; i++) {
      await service.showRemote(title: 't$i', body: 'b$i', route: null);
    }

    final ids = verify(
      () => plugin.show(
        id: captureAny(named: 'id'),
        title: any(named: 'title'),
        body: any(named: 'body'),
        notificationDetails: any(named: 'notificationDetails'),
        payload: any(named: 'payload'),
      ),
    ).captured.cast<int>();
    expect(ids, hasLength(3));
    expect(ids.toSet(), hasLength(3));
    expect(ids[0], lessThan(ids[1]));
    expect(ids[1], lessThan(ids[2]));
    for (final id in ids) {
      expect(id, inInclusiveRange(0, 0x7FFFFFFE));
    }
  });
}
