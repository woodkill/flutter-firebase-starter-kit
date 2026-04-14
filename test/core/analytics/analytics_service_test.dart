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

    test('setGuestMode(true) → setUserProperty(name:"guest_mode", value:"true")', () async {
      await service.setGuestMode(true);
      verify(
        () => mockAnalytics.setUserProperty(
          name: 'guest_mode',
          value: 'true',
        ),
      ).called(1);
    });

    test('setGuestMode(false) → value:"false"', () async {
      await service.setGuestMode(false);
      verify(
        () => mockAnalytics.setUserProperty(
          name: 'guest_mode',
          value: 'false',
        ),
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

    test('logScreenView(screenName:"home", screenClass:"HomeScreen")', () async {
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
    });
  });
}
