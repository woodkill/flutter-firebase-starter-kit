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

  group('CrashlyticsService 실패 격리 (WR-01)', () {
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
      ).thenThrow(StateError('channel boom'));
      when(
        () => mockCrashlytics.setUserIdentifier(any()),
      ).thenThrow(StateError('channel boom'));
      when(
        () => mockCrashlytics.setCustomKey(any(), any<Object>()),
      ).thenThrow(StateError('channel boom'));
    });

    test('네이티브가 throw 해도 호출자에게 예외를 전파하지 않는다', () async {
      // 수정 전에는 이 예외가 locale_provider / theme_provider 의 catch
      // 블록에서 던져져 **원래 진단하려던 에러를 대체**했고, fire-and-forget
      // 경로에서는 unhandled rejection 으로 zone 까지 올라가 비치명 이벤트가
      // 치명 크래시로 둔갑했다.
      await expectLater(
        service.recordError(Exception('x'), StackTrace.current, reason: 'r1'),
        completes,
      );
      await expectLater(service.setUserId('uid-123'), completes);
      await expectLater(service.setCustomKey('k', 'v'), completes);
      await expectLater(service.setFlavor('dev'), completes);
    });

    test('비동기 실패 (Future.error) 도 흡수한다', () async {
      when(
        () => mockCrashlytics.setUserIdentifier(any()),
      ).thenAnswer((_) async => throw StateError('async boom'));

      await expectLater(service.setUserId('uid-123'), completes);
    });
  });

  group('CrashlyticsService setCustomKey 타입 계약 (WR-02)', () {
    late CrashlyticsService service;

    setUp(() {
      final mockCrashlytics = _MockFirebaseCrashlytics();
      when(
        () => mockCrashlytics.setCustomKey(any(), any<Object>()),
      ).thenAnswer((_) async {});
      service = CrashlyticsService(mockCrashlytics, isEnabled: true);
    });

    test('String / num / bool 은 허용된다', () async {
      await expectLater(service.setCustomKey('s', 'v'), completes);
      await expectLater(service.setCustomKey('i', 42), completes);
      await expectLater(service.setCustomKey('d', 1.5), completes);
      await expectLater(service.setCustomKey('b', true), completes);
    });

    test('임의 객체는 debug assert 로 차단된다 (toString PII 유출 경로)', () {
      expect(
        () => service.setCustomKey('obj', Object()),
        throwsA(
          isA<AssertionError>().having(
            (e) => e.message.toString(),
            'message',
            allOf(contains('String / num / bool'), contains('PII')),
          ),
        ),
      );
    });

    test('isEnabled=false 여도 타입 계약은 먼저 검사한다', () {
      // 미초기화 환경에서만 테스트한 코드가 프로덕션에서 터지는 것을 막는다.
      const disabled = CrashlyticsService(null, isEnabled: false);
      expect(
        () => disabled.setCustomKey('obj', Object()),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
