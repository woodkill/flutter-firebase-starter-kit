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
//   S6: failed-precondition + provider_config → Failed(ProviderMisconfigured)
//       (review IN-04 iteration 3) · anonymous_caller · reason 없음 → ServiceUnavailable
//   S6m: (review IN-04 iteration 3) disconnectOutcomeFromFunctionsException 직접 —
//        provider_config 는 failed-precondition 에서만 · 그 밖 code · reason → 기존 분류
//   S7: 로그인 사용자 부재 · 익명 → Failed(UnknownException) · callable 0
//   S8: 비-Functions 예외 → Failed(ServiceUnavailable)
//   S9: 레지스트리 — provider 중복 0 · 서버 행 kind · email 조회 null ·
//       Facebook callable 이름 · provider 가 Firebase 없이 읽힘
//   S10: 레지스트리 완결 (plan 06) — 항목 수 · provider 집합 · 서버 행 =
//        Kakao · Facebook · 재로그인 행 strategy non-null · email 없음
//   S11: (review WR-04) 공용 계약 · 레지스트리는 LINE · Naver SDK client 를
//        import 하지 않는다 — step 파일만 import 한다(양성 대조)
//   T-17-WD-04: (Phase 17 D-43 · D-44) SDK 계층 거부 → Failed(AppCheckFailed)
//        · Crashlytics 1회(reason app_check_rejected_disconnectKakaoProvider) ·
//        reason 분기(caller_identity_mismatch · provider_config) 우선 · reason
//        없는 errorUnauthenticated → 기존 ServiceUnavailable

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/crashlytics/crashlytics_service.dart';
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/settings/data/disconnect/disconnect_step.dart';
import 'package:flutter_starter_kit/features/settings/data/disconnect/disconnect_steps.dart';
import 'package:flutter_starter_kit/features/settings/data/disconnect/server_disconnect_step.dart';

import '../../../../helpers/source_text.dart';

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockFbUser extends Mock implements fb.User {}

class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class _MockHttpsCallable extends Mock implements HttpsCallable {}

class _MockHttpsCallableResult extends Mock
    implements HttpsCallableResult<Map<String, dynamic>> {}

class _MockCrashlyticsService extends Mock implements CrashlyticsService {}

/// 기록을 남기지 않는 Crashlytics — 매퍼 직접 호출(S6m)용.
const CrashlyticsService _kNoopCrashlytics = CrashlyticsService(
  null,
  isEnabled: false,
);

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
      platform: TargetPlatform.android,
      read: ProviderContainer.test().read,
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
      'S6: failed-precondition + provider_config → Failed(ProviderMisconfigured) (review IN-04 iter3)',
      () async {
        stubCallableThrows(
          FirebaseFunctionsException(
            message: 'x',
            code: 'failed-precondition',
            details: const <String, dynamic>{'reason': 'provider_config'},
          ),
        );

        final outcome = await runKakao();

        expect(failureOf(outcome), isA<ProviderMisconfigured>());
        expect(failureOf(outcome), isNot(isA<ServiceUnavailable>()));
      },
    );

    test(
      'S6: failed-precondition + anonymous_caller · reason 없음 → Failed(ServiceUnavailable)',
      () async {
        for (final details in <Object?>[
          const <String, dynamic>{'reason': 'anonymous_caller'},
          null,
          const <String, dynamic>{},
        ]) {
          stubCallableThrows(
            FirebaseFunctionsException(
              message: 'x',
              code: 'failed-precondition',
              details: details,
            ),
          );

          final outcome = await runKakao();

          expect(
            failureOf(outcome),
            isA<ServiceUnavailable>(),
            reason: '$details',
          );
        }
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

  group(
    'S6m (review IN-04 iter3): disconnectOutcomeFromFunctionsException 매핑',
    () {
      AppException? failureCause(DisconnectOutcome outcome) =>
          outcome is DisconnectFailed ? outcome.exception : null;

      test(
        'provider_config 는 failed-precondition 일 때만 ProviderMisconfigured',
        () {
          final exception = FirebaseFunctionsException(
            message: 'errorProviderConfig',
            code: 'failed-precondition',
            details: const <String, dynamic>{'reason': 'provider_config'},
          );

          final outcome = disconnectOutcomeFromFunctionsException(
            exception,
            callable: 'disconnectKakaoProvider',
            crashlytics: _kNoopCrashlytics,
          );

          expect(failureCause(outcome), isA<ProviderMisconfigured>());
          // 원인 보존 — 진단 로그용 (UI 노출 0).
          expect(failureCause(outcome)?.cause, same(exception));
        },
      );

      test(
        'anonymous_caller · reason 없음 · 다른 code 의 provider_config → ServiceUnavailable',
        () {
          for (final (code, details) in <(String, Object?)>[
            (
              'failed-precondition',
              const <String, dynamic>{'reason': 'anonymous_caller'},
            ),
            ('failed-precondition', null),
            ('internal', const <String, dynamic>{'reason': 'provider_config'}),
            ('unauthenticated', null),
          ]) {
            final outcome = disconnectOutcomeFromFunctionsException(
              FirebaseFunctionsException(
                message: 'x',
                code: code,
                details: details,
              ),
              callable: 'disconnectKakaoProvider',
              crashlytics: _kNoopCrashlytics,
            );

            expect(
              failureCause(outcome),
              isA<ServiceUnavailable>(),
              reason: '$code $details',
            );
          }
        },
      );
    },
  );

  group('T-17-WD-04 (Phase 17 D-43 · D-44): 끊기 callable App Check 판정', () {
    late _MockCrashlyticsService crashlytics;
    late DisconnectDeps appCheckDeps;

    setUpAll(() {
      registerFallbackValue(StackTrace.empty);
    });

    setUp(() {
      crashlytics = _MockCrashlyticsService();
      when(
        () => crashlytics.recordError(
          any(),
          any(),
          reason: any(named: 'reason'),
          fatal: any(named: 'fatal'),
        ),
      ).thenAnswer((_) async {});
      appCheckDeps = DisconnectDeps(
        auth: mockAuth,
        functions: mockFunctions,
        googleSignIn: _MockGoogleSignIn(),
        platform: TargetPlatform.android,
        read: ProviderContainer.test().read,
        crashlytics: crashlytics,
      );
    });

    Future<DisconnectOutcome> runKakaoWithCrashlytics() =>
        _kakaoStep.run(appCheckDeps, reloginForFreshness: true);

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

    test(
      'T-17-WD-04 SDK 계층 거부 → Failed(AppCheckFailedException) · 기록 1회',
      () async {
        stubCallableThrows(
          FirebaseFunctionsException(
            code: 'unauthenticated',
            message: 'Unauthenticated',
          ),
        );

        final outcome = await runKakaoWithCrashlytics();

        expect(failureOf(outcome), isA<AppCheckFailedException>());
        verify(
          () => crashlytics.recordError(
            any(that: isA<FirebaseFunctionsException>()),
            any(),
            reason: 'app_check_rejected_disconnectKakaoProvider',
            fatal: false,
          ),
        ).called(1);
      },
    );

    test(
      'T-17-WD-04 caller_identity_mismatch 가 먼저 → IdentityMismatch · 기록 0',
      () async {
        stubCallableThrows(
          FirebaseFunctionsException(
            code: 'permission-denied',
            message: 'Unauthenticated',
            details: const <String, dynamic>{
              'reason': 'caller_identity_mismatch',
            },
          ),
        );

        final outcome = await runKakaoWithCrashlytics();

        expect(outcome, isA<DisconnectIdentityMismatch>());
        expectNoRecord();
      },
    );

    test(
      'T-17-WD-04 provider_config → Failed(ProviderMisconfigured) · 기록 0',
      () async {
        stubCallableThrows(
          FirebaseFunctionsException(
            code: 'failed-precondition',
            message: 'errorProviderConfig',
            details: const <String, dynamic>{'reason': 'provider_config'},
          ),
        );

        final outcome = await runKakaoWithCrashlytics();

        expect(failureOf(outcome), isA<ProviderMisconfigured>());
        expectNoRecord();
      },
    );

    test(
      'T-17-WD-04 reason 없는 unauthenticated(errorUnauthenticated) → Failed(ServiceUnavailable) · 기록 0',
      () async {
        stubCallableThrows(
          FirebaseFunctionsException(
            code: 'unauthenticated',
            message: 'errorUnauthenticated',
          ),
        );

        final outcome = await runKakaoWithCrashlytics();

        expect(failureOf(outcome), isA<ServiceUnavailable>());
        expect(failureOf(outcome), isNot(isA<AppCheckFailedException>()));
        expectNoRecord();
      },
    );
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

    test('S10: 레지스트리 완결 — D-01 대상 전부 · 서버 행 = Kakao · Facebook', () {
      expect(kDisconnectSteps.length, 6);
      expect(
        kDisconnectSteps.map((step) => step.provider).toSet(),
        <AccountProvider>{
          AccountProvider.google,
          AccountProvider.apple,
          AccountProvider.facebook,
          AccountProvider.kakao,
          AccountProvider.naver,
          AccountProvider.line,
        },
      );
      expect(
        kDisconnectSteps
            .where((step) => step.kind == DisconnectKind.server)
            .map((step) => step.provider)
            .toSet(),
        <AccountProvider>{AccountProvider.kakao, AccountProvider.facebook},
      );
      for (final step in kDisconnectSteps.where(
        (step) => step.kind == DisconnectKind.relogin,
      )) {
        expect(step.signInStrategy, isNotNull, reason: step.provider.slug);
      }
      expect(
        kDisconnectSteps.any((step) => step.provider == AccountProvider.email),
        isFalse,
      );
    });

    test(
      'S11 (review WR-04): 공용 계약 · 레지스트리는 provider 별 SDK client import 0',
      () {
        const dir = 'lib/features/settings/data/disconnect';
        const sdkImports = <String>[
          "import '../../../auth/data/line_sdk_client.dart';",
          "import '../../../auth/data/naver_sdk_client.dart';",
        ];
        String codeOf(String file) => stripBlockComments(
          stripSlashComments(readTrackedFile('$dir/$file')),
        );

        // 공용 파일 — LINE · Naver 를 지워도 이 두 파일은 편집 0 이어야 한다(C-08).
        for (final file in <String>[
          'disconnect_step.dart',
          'disconnect_steps.dart',
        ]) {
          for (final line in sdkImports) {
            expect(
              countOccurrences(codeOf(file), line),
              0,
              reason: '$file: $line',
            );
          }
        }
        // 양성 대조 — 같은 매칭이 step 파일에서는 실제로 1건을 찾는다.
        expect(
          countOccurrences(codeOf('line_disconnect_step.dart'), sdkImports[0]),
          1,
        );
        expect(
          countOccurrences(codeOf('naver_disconnect_step.dart'), sdkImports[1]),
          1,
        );
      },
    );
  });
}
