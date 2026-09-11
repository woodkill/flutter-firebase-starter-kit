import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/analytics/analytics_service.dart';

class _MockFirebaseAnalytics extends Mock implements FirebaseAnalytics {}

void main() {
  group('AnalyticsService (isEnabled=false)', () {
    late _MockFirebaseAnalytics mockAnalytics;
    late AnalyticsService service;

    setUp(() {
      mockAnalytics = _MockFirebaseAnalytics();
      service = AnalyticsService(mockAnalytics, isEnabled: false);
    });

    test('setGuestMode/setUserId/logEvent/logScreenView 모두 no-op', () async {
      await service.setGuestMode(true);
      await service.setUserId('uid-xyz');
      await service.logEvent('test_event', parameters: {'key': 'val'});
      await service.logScreenView(
        screenName: 'home',
        screenClass: 'HomeScreen',
      );

      verifyNever(
        () => mockAnalytics.setUserProperty(
          name: any(named: 'name'),
          value: any(named: 'value'),
        ),
      );
      verifyNever(() => mockAnalytics.setUserId(id: any(named: 'id')));
      verifyNever(
        () => mockAnalytics.logEvent(
          name: any(named: 'name'),
          parameters: any(named: 'parameters'),
        ),
      );
      verifyNever(
        () => mockAnalytics.logScreenView(
          screenName: any(named: 'screenName'),
          screenClass: any(named: 'screenClass'),
        ),
      );
    });
  });

  group('AnalyticsService (isEnabled=true)', () {
    late _MockFirebaseAnalytics mockAnalytics;
    late AnalyticsService service;

    setUp(() {
      mockAnalytics = _MockFirebaseAnalytics();
      service = AnalyticsService(mockAnalytics, isEnabled: true);

      when(
        () => mockAnalytics.setUserProperty(
          name: any(named: 'name'),
          value: any(named: 'value'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockAnalytics.setUserId(id: any(named: 'id')),
      ).thenAnswer((_) async {});
      when(
        () => mockAnalytics.logEvent(
          name: any(named: 'name'),
          parameters: any(named: 'parameters'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockAnalytics.logScreenView(
          screenName: any(named: 'screenName'),
          screenClass: any(named: 'screenClass'),
        ),
      ).thenAnswer((_) async {});
    });

    test(
      'setGuestMode(true) → setUserProperty(name:"guest_mode", value:"true")',
      () async {
        await service.setGuestMode(true);
        verify(
          () =>
              mockAnalytics.setUserProperty(name: 'guest_mode', value: 'true'),
        ).called(1);
      },
    );

    test('setGuestMode(false) → value:"false"', () async {
      await service.setGuestMode(false);
      verify(
        () => mockAnalytics.setUserProperty(name: 'guest_mode', value: 'false'),
      ).called(1);
    });

    test('setUserId("uid-xyz") → setUserId(id:"uid-xyz")', () async {
      await service.setUserId('uid-xyz');
      verify(() => mockAnalytics.setUserId(id: 'uid-xyz')).called(1);
    });

    test('setUserId(null) → setUserId(id:null)', () async {
      await service.setUserId(null);
      verify(() => mockAnalytics.setUserId(id: null)).called(1);
    });

    test('logEvent("test_event", parameters: {"key":"val"})', () async {
      await service.logEvent('test_event', parameters: {'key': 'val'});
      verify(
        () => mockAnalytics.logEvent(
          name: 'test_event',
          parameters: {'key': 'val'},
        ),
      ).called(1);
    });

    test(
      'logScreenView(screenName:"home", screenClass:"HomeScreen")',
      () async {
        await service.logScreenView(
          screenName: 'home',
          screenClass: 'HomeScreen',
        );
        verify(
          () => mockAnalytics.logScreenView(
            screenName: 'home',
            screenClass: 'HomeScreen',
          ),
        ).called(1);
      },
    );
  });

  group('AnalyticsService 실패 격리 (WR-01)', () {
    late _MockFirebaseAnalytics mockAnalytics;
    late AnalyticsService service;

    setUp(() {
      mockAnalytics = _MockFirebaseAnalytics();
      service = AnalyticsService(mockAnalytics, isEnabled: true);

      // 네 메서드 모두 네이티브 실패를 시뮬레이션한다. 수정 전에는 이 예외가
      // 그대로 호출자에게 전파되어 온보딩 완료 경로를 영구 정지시키고
      // auth_guard 의 `await for` 스트림을 종료시켰다.
      when(
        () => mockAnalytics.setUserProperty(
          name: any(named: 'name'),
          value: any(named: 'value'),
        ),
      ).thenThrow(ArgumentError.value('boom'));
      when(
        () => mockAnalytics.setUserId(id: any(named: 'id')),
      ).thenThrow(ArgumentError.value('boom'));
      when(
        () => mockAnalytics.logEvent(
          name: any(named: 'name'),
          parameters: any(named: 'parameters'),
        ),
      ).thenThrow(ArgumentError.value('boom'));
      when(
        () => mockAnalytics.logScreenView(
          screenName: any(named: 'screenName'),
          screenClass: any(named: 'screenClass'),
        ),
      ).thenThrow(ArgumentError.value('boom'));
    });

    test('네이티브가 throw 해도 4개 메서드 모두 호출자에게 예외를 전파하지 않는다', () async {
      await expectLater(service.setGuestMode(true), completes);
      await expectLater(service.setUserId('uid-xyz'), completes);
      await expectLater(service.logEvent('custom_event'), completes);
      await expectLater(service.logScreenView(screenName: 'home'), completes);

      // 흡수는 했지만 호출 자체는 시도했어야 한다 (조용한 skip 이 아니다).
      verify(() => mockAnalytics.setUserId(id: 'uid-xyz')).called(1);
      verify(
        () => mockAnalytics.logEvent(
          name: 'custom_event',
          parameters: any(named: 'parameters'),
        ),
      ).called(1);
    });

    test('비동기 실패 (Future.error) 도 흡수한다', () async {
      when(
        () => mockAnalytics.logEvent(
          name: any(named: 'name'),
          parameters: any(named: 'parameters'),
        ),
      ).thenAnswer((_) async => throw StateError('async boom'));

      await expectLater(service.logEvent('custom_event'), completes);
    });
  });

  group('AnalyticsService 타입/이름 계약 (WR-02)', () {
    late AnalyticsService service;

    setUp(() {
      final mockAnalytics = _MockFirebaseAnalytics();
      when(
        () => mockAnalytics.logEvent(
          name: any(named: 'name'),
          parameters: any(named: 'parameters'),
        ),
      ).thenAnswer((_) async {});
      service = AnalyticsService(mockAnalytics, isEnabled: true);
    });

    test('bool 파라미터 값은 debug assert 로 즉시 드러난다', () {
      // release 에서는 네이티브로 내려가 조용히 누락되던 조합이다.
      expect(
        () => service.logEvent('custom_event', parameters: {'ok': true}),
        throwsA(
          isA<AssertionError>().having(
            (e) => e.message.toString(),
            'message',
            contains('String 또는 num'),
          ),
        ),
      );
    });

    test('String / num 파라미터 값은 통과한다', () async {
      await expectLater(
        service.logEvent('custom_event', parameters: {'s': 'v', 'n': 42}),
        completes,
      );
    });

    test('GA4 이벤트명 규칙 위반은 debug assert 로 드러난다', () {
      for (final badName in <String>[
        '9leading_digit',
        'has space',
        'has-hyphen',
        '',
      ]) {
        expect(
          () => service.logEvent(badName),
          throwsA(
            isA<AssertionError>().having(
              (e) => e.message.toString(),
              'message',
              contains('GA4 이벤트명 규칙 위반'),
            ),
          ),
          reason: '"$badName" 은 GA4 가 조용히 버리는 이름이다',
        );
      }
    });

    test('40자 경계: 40자는 통과, 41자는 실패', () async {
      final ok = 'a${'b' * 39}'; // 40자
      final tooLong = 'a${'b' * 40}'; // 41자
      await expectLater(service.logEvent(ok), completes);
      expect(() => service.logEvent(tooLong), throwsA(isA<AssertionError>()));
    });
  });
}
