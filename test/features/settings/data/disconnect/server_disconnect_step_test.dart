// ignore_for_file: lines_longer_than_80_chars
//
// Phase 16.10 plan 05 Task 1 — 서버 행 끊기 step (Kakao · Facebook) 과 공용
// callable 거부 매핑 · 레지스트리 계약.
//
//   S1: callable 이름 · 입력 `{}` · timeout alias · `{ok: true}` → Done
//   S2: `ok` 부재 → Failed(UnknownException)
//   S3: permission-denied + caller_identity_mismatch → IdentityMismatch
//   S4: unavailable · deadline-exceeded → Failed(NoInternetConnection)
//   S5: resource-exhausted → Failed(TooManyRequests)
//   S6: failed-precondition + provider_config → Failed(ServiceUnavailable)
//   S7: 로그인 사용자 부재 · 익명 → Failed(UnknownException) · callable 0
//   S8: 비-Functions 예외 → Failed(ServiceUnavailable)
//   S9: 레지스트리 — provider 중복 0 · 서버 행 kind · email 조회 null ·
//       Facebook callable 이름 · provider 가 Firebase 없이 읽힘

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/data/line_sdk_client.dart';
import 'package:flutter_starter_kit/features/auth/data/naver_sdk_client.dart';
import 'package:flutter_starter_kit/features/settings/data/disconnect/disconnect_step.dart';
import 'package:flutter_starter_kit/features/settings/data/disconnect/disconnect_steps.dart';
import 'package:flutter_starter_kit/features/settings/data/disconnect/server_disconnect_step.dart';

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockFbUser extends Mock implements fb.User {}

class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

class _MockLineSdkClient extends Mock implements LineSdkClient {}

class _MockNaverSdkClient extends Mock implements NaverSdkClient {}

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class _MockHttpsCallable extends Mock implements HttpsCallable {}

class _MockHttpsCallableResult extends Mock
    implements HttpsCallableResult<Map<String, dynamic>> {}

const ServerDisconnectStep _kakaoStep = ServerDisconnectStep(
  provider: AccountProvider.kakao,
  callableName: 'disconnectKakaoProvider',
);

void main() {
  late _MockFirebaseAuth mockAuth;
  late _MockFbUser mockUser;
  late _MockFirebaseFunctions mockFunctions;
  late _MockHttpsCallable mockCallable;
  late DisconnectDeps deps;

  setUp(() {
    mockAuth = _MockFirebaseAuth();
    mockUser = _MockFbUser();
    mockFunctions = _MockFirebaseFunctions();
    mockCallable = _MockHttpsCallable();
    when(() => mockAuth.currentUser).thenReturn(mockUser);
    when(() => mockUser.isAnonymous).thenReturn(false);
    when(
      () => mockFunctions.httpsCallable(any(), options: any(named: 'options')),
    ).thenReturn(mockCallable);
    deps = DisconnectDeps(
      auth: mockAuth,
      functions: mockFunctions,
      googleSignIn: _MockGoogleSignIn(),
      lineSdkClient: _MockLineSdkClient(),
      naverSdkClient: _MockNaverSdkClient(),
      platform: TargetPlatform.android,
    );
  });

  void stubCallableData(Map<String, dynamic> data) {
    final result = _MockHttpsCallableResult();
    when(() => result.data).thenReturn(data);
    when(
      () => mockCallable.call<Map<String, dynamic>>(any()),
    ).thenAnswer((_) async => result);
  }

  void stubCallableThrows(Object error) {
    when(() => mockCallable.call<Map<String, dynamic>>(any())).thenThrow(error);
  }

  Future<DisconnectOutcome> runKakao() =>
      _kakaoStep.run(deps, reloginForFreshness: true);

  AppException failureOf(DisconnectOutcome outcome) {
    expect(outcome, isA<DisconnectFailed>());
    return (outcome as DisconnectFailed).exception;
  }

  group('ServerDisconnectStep', () {
    test(
      'S1: Kakao — callable 이름 · 입력 {} · timeout alias · {ok: true} → Done',
      () async {
        stubCallableData(<String, dynamic>{'ok': true, 'disconnectedCount': 1});

        final outcome = await runKakao();

        expect(outcome, isA<DisconnectDone>());
        final options =
            verify(
                  () => mockFunctions.httpsCallable(
                    'disconnectKakaoProvider',
                    options: captureAny(named: 'options'),
                  ),
                ).captured.single
                as HttpsCallableOptions;
        expect(options.timeout, AuthRepository.customTokenCallableTimeout);
        final payload = verify(
          () => mockCallable.call<Map<String, dynamic>>(captureAny()),
        ).captured.single;
        expect(payload, <String, dynamic>{});
      },
    );

    test('S2: 응답에 ok 부재 → Failed(UnknownException)', () async {
      stubCallableData(<String, dynamic>{'disconnectedCount': 0});

      final outcome = await runKakao();

      expect(failureOf(outcome), isA<UnknownException>());
    });

    test(
      'S3: permission-denied + caller_identity_mismatch → IdentityMismatch',
      () async {
        stubCallableThrows(
          FirebaseFunctionsException(
            message: 'x',
            code: 'permission-denied',
            details: const <String, dynamic>{
              'reason': 'caller_identity_mismatch',
            },
          ),
        );

        final outcome = await runKakao();

        expect(outcome, isA<DisconnectIdentityMismatch>());
      },
    );

    test(
      'S4: unavailable · deadline-exceeded → Failed(NoInternetConnection)',
      () async {
        for (final code in <String>['unavailable', 'deadline-exceeded']) {
          stubCallableThrows(
            FirebaseFunctionsException(message: 'x', code: code),
          );

          final outcome = await runKakao();

          expect(failureOf(outcome), isA<NoInternetConnection>(), reason: code);
        }
      },
    );

    test('S5: resource-exhausted → Failed(TooManyRequests)', () async {
      stubCallableThrows(
        FirebaseFunctionsException(message: 'x', code: 'resource-exhausted'),
      );

      final outcome = await runKakao();

      expect(failureOf(outcome), isA<TooManyRequests>());
    });

    test(
      'S6: failed-precondition + provider_config → Failed(ServiceUnavailable)',
      () async {
        stubCallableThrows(
          FirebaseFunctionsException(
            message: 'x',
            code: 'failed-precondition',
            details: const <String, dynamic>{'reason': 'provider_config'},
          ),
        );

        final outcome = await runKakao();

        expect(failureOf(outcome), isA<ServiceUnavailable>());
      },
    );

    test(
      'S6: reason 없는 permission-denied 도 신원 불일치가 아니다 → Failed(ServiceUnavailable)',
      () async {
        stubCallableThrows(
          FirebaseFunctionsException(message: 'x', code: 'permission-denied'),
        );

        final outcome = await runKakao();

        expect(failureOf(outcome), isA<ServiceUnavailable>());
      },
    );

    test(
      'S7: 로그인 사용자 부재 · 익명 → Failed(UnknownException) · callable 0',
      () async {
        when(() => mockAuth.currentUser).thenReturn(null);
        expect(failureOf(await runKakao()), isA<UnknownException>());

        when(() => mockAuth.currentUser).thenReturn(mockUser);
        when(() => mockUser.isAnonymous).thenReturn(true);
        expect(failureOf(await runKakao()), isA<UnknownException>());

        verifyNever(
          () => mockFunctions.httpsCallable(
            any(),
            options: any(named: 'options'),
          ),
        );
      },
    );

    test('S8: 비-Functions 예외 → Failed(ServiceUnavailable)', () async {
      stubCallableThrows(StateError('boom'));

      final outcome = await runKakao();

      expect(failureOf(outcome), isA<ServiceUnavailable>());
    });
  });

  group('kDisconnectSteps 레지스트리', () {
    test(
      'S9: provider 중복 0 · 서버 행 kind · email 조회 null · Facebook callable 이름',
      () {
        final providers = kDisconnectSteps
            .map((step) => step.provider)
            .toList();
        expect(providers.toSet().length, providers.length);

        for (final provider in <AccountProvider>[
          AccountProvider.kakao,
          AccountProvider.facebook,
        ]) {
          final step = disconnectStepFor(kDisconnectSteps, provider);
          expect(step, isNotNull, reason: provider.slug);
          expect(step!.kind, DisconnectKind.server, reason: provider.slug);
          expect(step.signInStrategy, isNull, reason: provider.slug);
        }

        expect(
          disconnectStepFor(kDisconnectSteps, AccountProvider.email),
          isNull,
        );

        final facebook = disconnectStepFor(
          kDisconnectSteps,
          AccountProvider.facebook,
        );
        expect(facebook, isA<ServerDisconnectStep>());
        expect(
          (facebook! as ServerDisconnectStep).callableName,
          'disconnectFacebookProvider',
        );
      },
    );

    test('S9: disconnectStepsProvider 는 Firebase 없이 const 레지스트리를 준다', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        identical(container.read(disconnectStepsProvider), kDisconnectSteps),
        isTrue,
      );
    });
  });
}
