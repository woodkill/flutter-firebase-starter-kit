// Phase 17 Plan 17-18 — TestPushClient 단위 테스트 (D-05 · D-35 · D-43 ·
// D-44).
//
// callable `sendTestPush` 응답 · 거부를 [TestPushOutcome] 으로 바꾸는 매퍼를
// 검증한다. FirebaseFunctions · HttpsCallable 은 mocktail mock 이다.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/crashlytics/crashlytics_service.dart';
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
  });
}
