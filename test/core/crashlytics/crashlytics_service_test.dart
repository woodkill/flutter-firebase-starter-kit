import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/crashlytics/crashlytics_service.dart';

class _MockFirebaseCrashlytics extends Mock implements FirebaseCrashlytics {}

class _FakeStackTrace extends Fake implements StackTrace {}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeStackTrace());
  });

  group('CrashlyticsService (isEnabled=false)', () {
    late _MockFirebaseCrashlytics mockCrashlytics;
    late CrashlyticsService service;

    setUp(() {
      mockCrashlytics = _MockFirebaseCrashlytics();
      service = CrashlyticsService(mockCrashlytics, isEnabled: false);
    });

    test('recordError/setUserId/setCustomKey/setFlavor 모두 no-op', () async {
      await service.recordError(
        Exception('boom'),
        StackTrace.current,
        reason: 'r1',
        fatal: true,
      );
      await service.setUserId('uid-123');
      await service.setCustomKey('mykey', 42);
      await service.setFlavor('dev');

      verifyNever(
        () => mockCrashlytics.recordError(
          any<Object>(),
          any<StackTrace?>(),
          reason: any(named: 'reason'),
          fatal: any(named: 'fatal'),
        ),
      );
      verifyNever(() => mockCrashlytics.setUserIdentifier(any()));
      verifyNever(() => mockCrashlytics.setCustomKey(any(), any<Object>()));
    });

    test('_crashlytics=null + isEnabled=false 조합도 안전하게 no-op', () async {
      const nullService = CrashlyticsService(null, isEnabled: false);
      await nullService.recordError(Exception('x'), null);
      await nullService.setUserId('u');
      await nullService.setCustomKey('k', 'v');
      await nullService.setFlavor('dev');
      // 예외 없이 완료되면 성공.
      expect(nullService.isEnabled, isFalse);
    });
  });

  group('CrashlyticsService (isEnabled=true)', () {
    late _MockFirebaseCrashlytics mockCrashlytics;
    late CrashlyticsService service;

    setUp(() {
      mockCrashlytics = _MockFirebaseCrashlytics();
      service = CrashlyticsService(mockCrashlytics, isEnabled: true);

      when(
        () => mockCrashlytics.recordError(
          any<Object>(),
          any<StackTrace?>(),
          reason: any(named: 'reason'),
          fatal: any(named: 'fatal'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockCrashlytics.setUserIdentifier(any()),
      ).thenAnswer((_) async {});
      when(
        () => mockCrashlytics.setCustomKey(any(), any<Object>()),
      ).thenAnswer((_) async {});
    });

    test(
      'recordError(err, stack, reason: "r1", fatal: true)는 fake에 동일 인자로 1회 전파',
      () async {
        final error = Exception('boom');
        final stack = StackTrace.current;

        await service.recordError(error, stack, reason: 'r1', fatal: true);

        verify(
          () => mockCrashlytics.recordError(
            error,
            stack,
            reason: 'r1',
            fatal: true,
          ),
        ).called(1);
      },
    );

    test('setUserId("uid-123") → setUserIdentifier("uid-123") 1회', () async {
      await service.setUserId('uid-123');
      verify(() => mockCrashlytics.setUserIdentifier('uid-123')).called(1);
    });

    test('setUserId(null) → setUserIdentifier("") 1회 (clear 정책)', () async {
      await service.setUserId(null);
      verify(() => mockCrashlytics.setUserIdentifier('')).called(1);
    });

    test('setFlavor("dev") → setCustomKey("flavor", "dev") 1회', () async {
      await service.setFlavor('dev');
      verify(() => mockCrashlytics.setCustomKey('flavor', 'dev')).called(1);
    });

    test('setCustomKey("mykey", 42) → 동일 인자 1회', () async {
      await service.setCustomKey('mykey', 42);
      verify(() => mockCrashlytics.setCustomKey('mykey', 42)).called(1);
    });
  });
}
