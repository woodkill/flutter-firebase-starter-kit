// ignore_for_file: lines_longer_than_80_chars
//
// Phase 16 Plan 16-06 Task 6.1 — SettingsRepository.requestAccountDeletion
// 단위 테스트.
//
// 검증 surface:
// - S1 happy path: fresh ID Token 발급 → deleteUserAccount callable invoke
//   → return void
// - S2 no current user: FirebaseAuth.instance.currentUser == null →
//   UnauthenticatedException throw
// - S3 callable unauthenticated (reauth required) →
//   ReauthenticationRequiredException throw
// - S4 callable internal → UnknownException throw
// - S5 PII redaction sentinel — idToken/email 본문 logger 미포함
//
// Phase 16 G-16-A6-2 추가 (_mapDeleteError taxonomy 정렬 —
// auth_repository._mapFunctionsException 과 동일 분류):
// - S6 unavailable → NoInternetConnection
// - S7 deadline-exceeded → NoInternetConnection
// - S8 resource-exhausted → TooManyRequests (Cloud Run 할당량 차단 실측)

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/features/settings/data/settings_repository.dart';

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockFirebaseUser extends Mock implements fb.User {}

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class _MockHttpsCallable extends Mock implements HttpsCallable {}

class _MockHttpsCallableResult extends Mock
    implements HttpsCallableResult<Object?> {}

class _FakeHttpsCallableOptions extends Fake implements HttpsCallableOptions {}

void main() {
  late _MockFirebaseAuth mockAuth;
  late _MockFirebaseUser mockUser;
  late _MockFirebaseFunctions mockFunctions;
  late _MockHttpsCallable mockDeleteCallable;
  late SettingsRepository repository;

  // S5 sentinel — fresh ID Token (의도적 distinct token 패턴 — 본문이
  // logger payload 에 포함되면 즉시 grep detect 가능).
  const freshIdToken = 'eyPII_SENTINEL_TOKEN_DO_NOT_LOG_THIS_PAYLOAD.body.sig';
  const collisionEmail = 's5-sensitive@example.com';

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(_FakeHttpsCallableOptions());
  });

  setUp(() {
    mockAuth = _MockFirebaseAuth();
    mockUser = _MockFirebaseUser();
    mockFunctions = _MockFirebaseFunctions();
    mockDeleteCallable = _MockHttpsCallable();

    repository = SettingsRepository(auth: mockAuth, functions: mockFunctions);

    when(
      () => mockFunctions.httpsCallable(
        'deleteUserAccount',
        options: any(named: 'options'),
      ),
    ).thenReturn(mockDeleteCallable);
  });

  void stubCurrentUserWithFreshToken({String token = freshIdToken}) {
    when(() => mockAuth.currentUser).thenReturn(mockUser);
    when(() => mockUser.uid).thenReturn('uid-s5');
    when(() => mockUser.email).thenReturn(collisionEmail);
    when(() => mockUser.getIdToken(any())).thenAnswer((_) async => token);
  }

  void stubCallableSuccess() {
    final mockResult = _MockHttpsCallableResult();
    when(() => mockResult.data).thenReturn(<String, dynamic>{'ok': true});
    when(
      () => mockDeleteCallable.call<Object?>(any()),
    ).thenAnswer((_) async => mockResult);
  }

  group('Phase 16 D-06 — SettingsRepository.requestAccountDeletion', () {
    test(
      'S1 happy path — fresh ID Token + callable success → return void',
      () async {
        stubCurrentUserWithFreshToken();
        stubCallableSuccess();

        await repository.requestAccountDeletion();

        // fresh ID Token 발급 (forceRefresh=true) 검증.
        verify(() => mockUser.getIdToken(true)).called(1);
        // deleteUserAccount callable 호출 검증 (idToken payload 전달).
        verify(
          () => mockDeleteCallable.call<Object?>(<String, dynamic>{
            'idToken': freshIdToken,
          }),
        ).called(1);
      },
    );

    test(
      'S2 no current user — currentUser==null → UnauthenticatedException',
      () async {
        when(() => mockAuth.currentUser).thenReturn(null);

        await expectLater(
          repository.requestAccountDeletion(),
          throwsA(isA<UnauthenticatedException>()),
        );

        // callable 호출 안 됨.
        verifyNever(() => mockDeleteCallable.call<Object?>(any()));
      },
    );

    test('S3 callable unauthenticated (reauth required) → '
        'ReauthenticationRequiredException', () async {
      stubCurrentUserWithFreshToken();
      when(() => mockDeleteCallable.call<Object?>(any())).thenThrow(
        FirebaseFunctionsException(
          code: 'unauthenticated',
          message: 'errorReauthenticationRequired',
        ),
      );

      await expectLater(
        repository.requestAccountDeletion(),
        throwsA(isA<ReauthenticationRequiredException>()),
      );
    });

    test('S4 callable internal (server fail) → UnknownException', () async {
      stubCurrentUserWithFreshToken();
      when(() => mockDeleteCallable.call<Object?>(any())).thenThrow(
        FirebaseFunctionsException(code: 'internal', message: 'errorUnknown'),
      );

      await expectLater(
        repository.requestAccountDeletion(),
        throwsA(isA<UnknownException>()),
      );
    });

    test(
      'S5 PII invariant — debugPrint payload 가 idToken / email 본문 미포함',
      () async {
        stubCurrentUserWithFreshToken();
        when(() => mockDeleteCallable.call<Object?>(any())).thenThrow(
          FirebaseFunctionsException(code: 'internal', message: 'server boom'),
        );

        final logs = <String>[];
        final originalPrint = debugPrint;
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null) logs.add(message);
        };

        try {
          try {
            await repository.requestAccountDeletion();
          } on UnknownException {
            // expected
          }

          for (final log in logs) {
            // idToken 본문 fragment 미노출 (S5 sentinel).
            expect(log, isNot(contains('PII_SENTINEL_TOKEN')));
            expect(log, isNot(contains(freshIdToken)));
            // email 본문 fragment 미노출 (local-part / 전체 모두).
            expect(log, isNot(contains('s5-sensitive')));
            expect(log, isNot(contains(collisionEmail)));
          }
        } finally {
          debugPrint = originalPrint;
        }
      },
    );
  });

  group('Phase 16 G-16-A6-2 — _mapDeleteError taxonomy 정렬', () {
    /// [code] 로 실패하는 deleteUserAccount callable 을 스텁한다.
    void stubCallableFailure(String code) {
      stubCurrentUserWithFreshToken();
      when(
        () => mockDeleteCallable.call<Object?>(any()),
      ).thenThrow(FirebaseFunctionsException(code: code, message: code));
    }

    test('S6 unavailable → NoInternetConnection', () async {
      stubCallableFailure('unavailable');

      await expectLater(
        repository.requestAccountDeletion(),
        throwsA(isA<NoInternetConnection>()),
      );
    });

    test('S7 deadline-exceeded → NoInternetConnection', () async {
      stubCallableFailure('deadline-exceeded');

      await expectLater(
        repository.requestAccountDeletion(),
        throwsA(isA<NoInternetConnection>()),
      );
    });

    test(
      'S8 resource-exhausted → TooManyRequests (Cloud Run 할당량 차단)',
      () async {
        // 2026-09-07 실측: 할당량 차단이 UnknownException 으로 뭉개져
        // "회원탈퇴에 실패했습니다" 로 표시되었다 — 재시도 가능 오류로 분리.
        stubCallableFailure('resource-exhausted');

        await expectLater(
          repository.requestAccountDeletion(),
          throwsA(isA<TooManyRequests>()),
        );
      },
    );
  });
}
