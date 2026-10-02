// Phase 17 Plan 17-18 — TestPushClient 단위 테스트 (D-05 · D-35 · D-43 ·
// D-44).
//
// callable `sendTestPush` 응답 · 거부를 [TestPushOutcome] 으로 바꾸는 매퍼를
// 검증한다. FirebaseFunctions · HttpsCallable 은 mocktail mock 이다.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/crashlytics/crashlytics_service.dart';
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/functions/callable_rejection.dart';
import 'package:flutter_starter_kit/features/notifications/data/test_push_client.dart';

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class _MockHttpsCallable extends Mock implements HttpsCallable {}

class _MockHttpsCallableResult extends Mock
    implements HttpsCallableResult<Object?> {}

class _MockCrashlyticsService extends Mock implements CrashlyticsService {}

void main() {
  late _MockFirebaseFunctions functions;
  late _MockHttpsCallable callable;
  late _MockCrashlyticsService crashlytics;
  late TestPushClient client;

  setUpAll(() {
    registerFallbackValue(StackTrace.empty);
  });

  setUp(() {
    functions = _MockFirebaseFunctions();
    callable = _MockHttpsCallable();
    crashlytics = _MockCrashlyticsService();
    when(() => functions.httpsCallable('sendTestPush')).thenReturn(callable);
    when(
      () => crashlytics.recordError(
        any(),
        any(),
        reason: any(named: 'reason'),
        fatal: any(named: 'fatal'),
      ),
    ).thenAnswer((_) async {});
    client = TestPushClient(functions: functions, crashlytics: crashlytics);
  });

  /// callable 이 [code] · [message] · [details] 로 거부하도록 설정한다.
  void stubRejection(String code, {String? message, Object? details}) {
    when(() => callable.call<Object?>()).thenThrow(
      FirebaseFunctionsException(
        code: code,
        message: message ?? code,
        details: details,
      ),
    );
  }

  /// Crashlytics 에 [reason] 으로 기록된 횟수를 단언한다.
  void expectRecorded(String reason, int times) {
    verify(
      () => crashlytics.recordError(
        any(),
        any(),
        reason: reason,
        fatal: any(named: 'fatal'),
      ),
    ).called(times);
  }

  /// Crashlytics 기록이 한 번도 없었음을 단언한다.
  void expectNoRecord() {
    verifyNever(
      () => crashlytics.recordError(
        any(),
        any(),
        reason: any(named: 'reason'),
        fatal: any(named: 'fatal'),
      ),
    );
  }

  /// [outcome] 이 [T] 원인의 [TestPushFailed] 인지 단언한다.
  void expectFailedWith<T extends AppException>(TestPushOutcome outcome) {
    expect(
      outcome,
      isA<TestPushFailed>().having((o) => o.exception, 'exception', isA<T>()),
    );
  }

  /// callable 이 [data] 를 응답 본문으로 돌려주도록 설정한다.
  void stubResponse(Object? data) {
    final result = _MockHttpsCallableResult();
    when(() => result.data).thenReturn(data);
    when(() => callable.call<Object?>()).thenAnswer((_) async => result);
  }

  group('Phase 17 테스트 알림 (T-17-SEND)', () {
    test('T-17-SEND-02 sentCount 2 → TestPushSent(2)', () async {
      stubResponse(<String, Object?>{'sentCount': 2});

      final outcome = await client.send();

      expect(outcome, isA<TestPushSent>().having((o) => o.count, 'count', 2));
      verify(() => functions.httpsCallable('sendTestPush')).called(1);
      verify(() => callable.call<Object?>()).called(1);
    });

    test('T-17-SEND-09 sentCount 0 → TestPushNoDevice', () async {
      stubResponse(<String, Object?>{'sentCount': 0});

      expect(await client.send(), isA<TestPushNoDevice>());
      expectNoRecord();
    });

    test('T-17-SEND-09 failed-precondition + reason test_push_disabled → '
        'TestPushDisabled', () async {
      stubRejection(
        'failed-precondition',
        message: 'errorTestPushDisabled',
        details: const <String, Object?>{'reason': 'test_push_disabled'},
      );

      expect(await client.send(), isA<TestPushDisabled>());
      expectNoRecord();
    });

    test('T-17-SEND-14 failed-precondition + reason anonymous_caller → '
        'TestPushNoDevice', () async {
      stubRejection(
        'failed-precondition',
        message: 'errorAnonymousCallerNotAllowed',
        details: const <String, Object?>{'reason': 'anonymous_caller'},
      );

      expect(await client.send(), isA<TestPushNoDevice>());
      expectNoRecord();
    });

    test('T-17-SEND-09 SDK 계층 거부(App Check) → AppCheckFailedException · '
        '기록 1회', () async {
      stubRejection('unauthenticated', message: kSdkUnauthenticatedMessage);

      expectFailedWith<AppCheckFailedException>(await client.send());
      expectRecorded('app_check_rejected_sendTestPush', 1);
    });

    test('T-17-SEND-09 resource-exhausted → TooManyRequests', () async {
      stubRejection('resource-exhausted', message: 'errorTooManyRequests');

      expectFailedWith<TooManyRequests>(await client.send());
      expectNoRecord();
    });

    test('T-17-SEND-09 unavailable → NoInternetConnection', () async {
      stubRejection('unavailable');

      expectFailedWith<NoInternetConnection>(await client.send());
      expectNoRecord();
    });

    test('T-17-SEND-09 그 밖의 code(internal) → ServiceUnavailable', () async {
      stubRejection('internal', message: 'errorUnknown');

      expectFailedWith<ServiceUnavailable>(await client.send());
      expectNoRecord();
    });

    test(
      'T-17-SEND-09 예상 밖 오류(StateError) → UnknownException · 기록 1회',
      () async {
        when(() => callable.call<Object?>()).thenThrow(StateError('boom'));

        expectFailedWith<UnknownException>(await client.send());
        expectRecorded('test_push_client_send', 1);
      },
    );

    test('T-17-SEND-09 Firebase 미초기화(functions null) → 호출 없이 '
        'ServiceUnavailable', () async {
      final offline = TestPushClient(functions: null, crashlytics: crashlytics);

      expectFailedWith<ServiceUnavailable>(await offline.send());
      verifyNever(() => functions.httpsCallable(any()));
    });
  });
}
