import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/features/notifications/data/messaging_service.dart';

class _MockFirebaseMessaging extends Mock implements FirebaseMessaging {}

class _MockNotificationSettings extends Mock implements NotificationSettings {}

/// 테스트에서 토큰 자리에 쓰는 표식 — 로그에 새면 안 된다.
const _secretToken = 'secret-device-token-123';

void main() {
  group('Phase 17 FCM 토큰 저장소 (T-17-FCM)', () {
    test('T-17-FCM-06: no-op 래퍼(null · isEnabled=false)는 권한 notDetermined · '
        '토큰 null · 스트림 즉시 done · 초기 메시지 null · throw 0', () async {
      const service = MessagingService(null, isEnabled: false);

      expect(
        await service.getAuthorizationStatus(),
        AuthorizationStatus.notDetermined,
      );
      expect(
        await service.requestPermission(),
        AuthorizationStatus.notDetermined,
      );
      expect(await service.getToken(), isNull);
      await expectLater(service.onTokenRefresh, emitsDone);
      await expectLater(service.onMessage, emitsDone);
      await expectLater(service.onMessageOpenedApp, emitsDone);
      expect(await service.getInitialMessage(), isNull);
      await expectLater(service.setForegroundPresentationOptions(), completes);
      expect(await service.deleteToken(), isFalse);
    });

    test('T-17-FCM-06: isEnabled=false 면 SDK 인스턴스가 있어도 호출 0', () async {
      final messaging = _MockFirebaseMessaging();
      final service = MessagingService(messaging, isEnabled: false);

      await service.getAuthorizationStatus();
      await service.requestPermission();
      await service.getToken();
      await service.getInitialMessage();
      await service.setForegroundPresentationOptions();
      await service.deleteToken();
      await expectLater(service.onTokenRefresh, emitsDone);

      verifyZeroInteractions(messaging);
    });
  });

  group('Phase 17 FCM 토큰 저장소 (T-17-FCM) — enabled', () {
    late _MockFirebaseMessaging messaging;
    late MessagingService service;
    late List<String> logs;
    DebugPrintCallback? originalDebugPrint;

    setUp(() {
      messaging = _MockFirebaseMessaging();
      service = MessagingService(messaging, isEnabled: true);
      logs = <String>[];
      originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
    });

    tearDown(() {
      final restore = originalDebugPrint;
      if (restore != null) debugPrint = restore;
    });

    test('T-17-FCM-07: getNotificationSettings 의 authorizationStatus 를 '
        '그대로 돌려준다', () async {
      final settings = _MockNotificationSettings();
      when(
        () => settings.authorizationStatus,
      ).thenReturn(AuthorizationStatus.authorized);
      when(
        () => messaging.getNotificationSettings(),
      ).thenAnswer((_) async => settings);

      expect(
        await service.getAuthorizationStatus(),
        AuthorizationStatus.authorized,
      );
      verify(() => messaging.getNotificationSettings()).called(1);
    });

    test('T-17-FCM-07: requestPermission · getToken · setForeground 옵션이 '
        'SDK 로 그대로 전달된다', () async {
      final settings = _MockNotificationSettings();
      when(
        () => settings.authorizationStatus,
      ).thenReturn(AuthorizationStatus.denied);
      when(
        () => messaging.requestPermission(),
      ).thenAnswer((_) async => settings);
      when(() => messaging.getToken()).thenAnswer((_) async => _secretToken);
      when(
        () => messaging.setForegroundNotificationPresentationOptions(
          alert: any(named: 'alert'),
          badge: any(named: 'badge'),
          sound: any(named: 'sound'),
        ),
      ).thenAnswer((_) async {});

      expect(await service.requestPermission(), AuthorizationStatus.denied);
      expect(await service.getToken(), _secretToken);
      await service.setForegroundPresentationOptions();

      verify(
        () => messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        ),
      ).called(1);
      expect(logs, isEmpty);
    });

    test('T-17-FCM-07: SDK 가 throw 하면 notDetermined · null 로 접고 '
        '진단 로그에는 예외 타입 이름만 남긴다', () async {
      final leak = StateError('leak $_secretToken');
      when(() => messaging.getNotificationSettings()).thenThrow(leak);
      when(() => messaging.requestPermission()).thenThrow(leak);
      when(() => messaging.getToken()).thenThrow(leak);
      when(() => messaging.getInitialMessage()).thenThrow(leak);
      when(
        () => messaging.setForegroundNotificationPresentationOptions(
          alert: any(named: 'alert'),
          badge: any(named: 'badge'),
          sound: any(named: 'sound'),
        ),
      ).thenThrow(leak);
      when(() => messaging.onTokenRefresh).thenThrow(leak);

      expect(
        await service.getAuthorizationStatus(),
        AuthorizationStatus.notDetermined,
      );
      expect(
        await service.requestPermission(),
        AuthorizationStatus.notDetermined,
      );
      expect(await service.getToken(), isNull);
      expect(await service.getInitialMessage(), isNull);
      await expectLater(service.setForegroundPresentationOptions(), completes);
      await expectLater(service.onTokenRefresh, emitsDone);

      expect(logs, hasLength(6));
      for (final line in logs) {
        expect(line, contains('StateError'));
        expect(line, isNot(contains(_secretToken)));
        expect(line, isNot(contains('leak')));
      }
    });

    test('T-17-FCM-07: onTokenRefresh 스트림 오류는 흡수하고 값은 그대로 '
        '흘린다', () async {
      final controller = StreamController<String>();
      when(() => messaging.onTokenRefresh).thenAnswer((_) => controller.stream);

      final emitted = expectLater(
        service.onTokenRefresh,
        emitsInOrder(<Object>['t-new', emitsDone]),
      );
      controller
        ..addError(StateError('leak $_secretToken'))
        ..add('t-new');
      await controller.close();
      await emitted;

      expect(logs, hasLength(1));
      expect(logs.single, contains('StateError'));
      expect(logs.single, isNot(contains(_secretToken)));
    });

    // Phase 17 리뷰 WR-03 — 로그아웃 정리가 못 지운 이전 계정 문서를 무효
    // 토큰으로 만드는 폐기 래퍼.
    test('T-17-FCM-08: deleteToken 이 끝나면 true · SDK 1회', () async {
      when(() => messaging.deleteToken()).thenAnswer((_) async {});

      expect(await service.deleteToken(), isTrue);
      verify(() => messaging.deleteToken()).called(1);
      expect(logs, isEmpty);
    });

    test('T-17-FCM-08: deleteToken 이 throw 하면 false · 진단 로그는 예외 '
        '타입 이름만', () async {
      when(
        () => messaging.deleteToken(),
      ).thenThrow(StateError('leak $_secretToken'));

      expect(await service.deleteToken(), isFalse);
      expect(logs, hasLength(1));
      expect(logs.single, contains('StateError'));
      expect(logs.single, isNot(contains(_secretToken)));
    });

    test('T-17-FCM-08: deleteToken 이 상한(kFcmDeleteTokenTimeout)을 넘으면 '
        'false', () {
      fakeAsync((async) {
        when(
          () => messaging.deleteToken(),
        ).thenAnswer((_) => Completer<void>().future);
        bool? result;
        unawaited(service.deleteToken().then((value) => result = value));

        async.elapse(kFcmDeleteTokenTimeout - const Duration(seconds: 1));
        expect(result, isNull);
        async.elapse(const Duration(seconds: 2));
        expect(result, isFalse);
        expect(logs.single, contains('TimeoutException'));
      });
    });
  });
}
