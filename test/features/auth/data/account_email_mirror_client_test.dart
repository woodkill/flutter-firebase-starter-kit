// Phase 17 Plan 17-10 — AccountEmailMirrorClient 단위 테스트 (D-26).
//
// 검증 surface:
// - T-17-MIRROR-02: `mirror()` 가 `httpsCallable('mirrorAccountEmail')` 를
//   인자 없이 1회 부르고, callable 이 [FirebaseFunctionsException] 을 던져도
//   throw 하지 않는다 (fire-and-forget). debugPrint 는 예외 타입 이름만 싣는다.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/features/auth/data/account_email_mirror_client.dart';

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class _MockHttpsCallable extends Mock implements HttpsCallable {}

class _MockHttpsCallableResult extends Mock
    implements HttpsCallableResult<void> {}

void main() {
  late _MockFirebaseFunctions functions;
  late _MockHttpsCallable callable;
  late AccountEmailMirrorClient client;

  setUp(() {
    functions = _MockFirebaseFunctions();
    callable = _MockHttpsCallable();
    client = AccountEmailMirrorClient(functions);
    when(
      () => functions.httpsCallable('mirrorAccountEmail'),
    ).thenReturn(callable);
  });

  group('Phase 17 email mirror (T-17-MIRROR)', () {
    test(
      'T-17-MIRROR-02a: mirror() 는 mirrorAccountEmail 을 인자 없이 1회 부른다',
      () async {
        when(
          () => callable.call<void>(),
        ).thenAnswer((_) async => _MockHttpsCallableResult());

        await client.mirror();

        verify(() => functions.httpsCallable('mirrorAccountEmail')).called(1);
        verify(() => callable.call<void>()).called(1);
        verifyNoMoreInteractions(callable);
      },
    );

    test('T-17-MIRROR-02b: callable 실패는 삼키고 debugPrint 에 타입 이름만 남긴다', () async {
      const sentinelMessage = 'SENTINEL_SERVER_MESSAGE_a@example.com';
      when(() => callable.call<void>()).thenThrow(
        FirebaseFunctionsException(
          code: 'unavailable',
          message: sentinelMessage,
        ),
      );
      final printed = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) printed.add(message);
      };
      addTearDown(() => debugPrint = originalDebugPrint);

      await expectLater(client.mirror(), completes);

      expect(printed, hasLength(1));
      expect(printed.single, contains('FirebaseFunctionsException'));
      expect(printed.single, isNot(contains(sentinelMessage)));
      expect(printed.single, isNot(contains('@')));
    });
  });
}
