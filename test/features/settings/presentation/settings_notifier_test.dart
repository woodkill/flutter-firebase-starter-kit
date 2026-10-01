// ignore_for_file: lines_longer_than_80_chars
//
// Phase 16 Plan 16-06 Task 6.1 — SettingsNotifier 단위 테스트.
//
// 검증 surface (16-07 ec7e13d 이후 성공 path = signOutAndResetOnboarding):
// - N1 happy path: requestAccountDeletion → AsyncValue.loading →
//   AsyncValue.data + signOutAndResetOnboarding 호출
// - N2 reauth required: repository throws ReauthenticationRequiredException →
//   AsyncValue.error(ReauthenticationRequiredException), signOutAndResetOnboarding 미호출
// - N3 server fail: repository throws UnknownException →
//   AsyncValue.error(UnknownException), signOutAndResetOnboarding 미호출
//
// 10-REVIEW CR-01 회귀 가드 (서버 hard delete 확정 이후의 사후 정리 실패가
// 탈퇴 실패로 오보고되지 않는지):
// - N4: repository 성공 + signOutAndResetOnboarding 이 Exception throw →
//   최종 state 는 AsyncValue.data(null) + crashlytics reason=withdrawal_post_signout
// - N5: 같은 시나리오에서 Error 계열 (StateError) throw 에도 data(null)
//
// 10-REVIEW CR-04 회귀 가드 (성공 emit 이 사후 정리에 갇히지 않는지):
// - N6: signOutAndResetOnboarding 이 미완료 상태여도 state 는 이미 data(null)
//
// Phase 16.10 Plan 16.10-08 Task 1 — disconnectAndUnlinkProvider (D-09 · D-11):
// - DU1 재로그인 행 Done → native 해제 1 · 세션 교체 0(reloginForFreshness false)
// - DU2 서버 행 Done → CT 해제 1
// - DU3 신원 불일치 · DU4 끊기 실패 · DU5 네트워크 · DU6 로그인 취소 → 해제 0
// - DU7 password(끊기 행 없음) → 끊기 0 · 해제 1 · DU8 미지 id → failed
// - DU9 step 예상 밖 throw → disconnectFailed · 해제 0
// 16.10 review IN-03 (iteration 3) — 끊기 Done 뒤 킷 해제 부분 실패:
// - DU10 해제 일시 오류(transient) · 미분류(failed) · 예상 밖 throw →
//   unlinkFailedAfterDisconnect
// - DU11 lastCredential · alreadyUnlinked · reauthRequired 는 기존 outcome 그대로
// - DU12 이메일/비밀번호(끊기 step 없음) · unlinkProvider 는 기존 outcome 그대로
// 16.10 review IN-04 (iteration 3):
// - DU13 끊기 Failed(ProviderMisconfigured) → providerConfigFailed · 킷 해제 0
//   (ServiceUnavailable 은 disconnectFailed 그대로)

import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart' show FirebaseFunctions;
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/auth/auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/auth/strategies/google_auth_strategy.dart';
import 'package:flutter_starter_kit/core/crashlytics/crashlytics_service.dart';
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/settings/application/account_link_in_progress.dart';
import 'package:flutter_starter_kit/features/settings/data/disconnect/disconnect_step.dart';
import 'package:flutter_starter_kit/features/settings/data/disconnect/disconnect_steps.dart';
import 'package:flutter_starter_kit/features/settings/data/settings_repository.dart';
import 'package:flutter_starter_kit/features/settings/presentation/settings_notifier.dart';

class _MockSettingsRepository extends Mock implements SettingsRepository {}

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockCrashlyticsService extends Mock implements CrashlyticsService {}

class _FakeStackTrace extends Fake implements StackTrace {}

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

/// 정해 둔 결과를 돌려주는 끊기 step — run 호출 · reloginForFreshness 를 기록한다.
class _FixedStep extends DisconnectStep {
  _FixedStep(this.provider, this.outcome, {this.signInStrategy, this.error});

  @override
  final AccountProvider provider;

  @override
  final AuthStrategy? signInStrategy;

  /// run 이 돌려줄 결과.
  final DisconnectOutcome outcome;

  /// 설정되면 run 이 결과 대신 이 값을 던진다 (계약 위반 흉내).
  final Object? error;

  /// run 호출마다 받은 reloginForFreshness 값.
  final List<bool> relogins = <bool>[];

  /// 마지막 run 의 reloginForFreshness 값.
  bool? get lastRelogin => relogins.lastOrNull;

  @override
  Future<DisconnectOutcome> run(
    DisconnectDeps deps, {
    required bool reloginForFreshness,
  }) async {
    relogins.add(reloginForFreshness);
    final thrown = error;
    if (thrown != null) throw thrown;
    return outcome;
  }
}

/// 실행 의존 묶음 — fake step 은 읽지 않는다 (Firebase 초기화 회피용 dummy).
DisconnectDeps _dummyDeps() => DisconnectDeps(
  auth: _MockFirebaseAuth(),
  functions: _MockFirebaseFunctions(),
  googleSignIn: _MockGoogleSignIn(),
  platform: TargetPlatform.android,
  read: ProviderContainer.test().read,
);

void main() {
  late _MockSettingsRepository mockSettingsRepo;
  late _MockAuthRepository mockAuthRepo;
  late _MockCrashlyticsService mockCrashlytics;
  late ProviderContainer container;

  setUpAll(() {
    registerFallbackValue(AccountProvider.kakao);
    registerFallbackValue(_FakeStackTrace());
  });

  setUp(() {
    mockSettingsRepo = _MockSettingsRepository();
    mockAuthRepo = _MockAuthRepository();
    mockCrashlytics = _MockCrashlyticsService();
    when(
      () => mockCrashlytics.recordError(
        any<Object>(),
        any<StackTrace?>(),
        reason: any(named: 'reason'),
        fatal: any(named: 'fatal'),
      ),
    ).thenAnswer((_) async {});

    // 16-07(ec7e13d) 이후 탈퇴 성공 path 는 signOut() 단독이 아닌
    // signOutAndResetOnboarding() 를 호출한다 (onboardingSeen=false reset).
    when(
      () => mockAuthRepo.signOutAndResetOnboarding(),
    ).thenAnswer((_) async {});

    container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(mockSettingsRepo),
        authRepositoryProvider.overrideWithValue(mockAuthRepo),
        crashlyticsServiceProvider.overrideWithValue(mockCrashlytics),
      ],
    );
    addTearDown(container.dispose);
  });

  group('Phase 16 D-06 — SettingsNotifier.requestAccountDeletion', () {
    test('N1 happy path — loading → data + signOut 트리거', () async {
      when(
        () => mockSettingsRepo.requestAccountDeletion(),
      ).thenAnswer((_) async {});

      // 초기 state.
      expect(
        container.read(settingsProvider),
        const AsyncValue<void>.data(null),
      );

      final notifier = container.read(settingsProvider.notifier);
      final future = notifier.requestAccountDeletion();
      // loading 진입 직후.
      expect(container.read(settingsProvider).isLoading, isTrue);

      await future;

      // 성공 후 data 상태.
      expect(
        container.read(settingsProvider),
        const AsyncValue<void>.data(null),
      );
      // signOutAndResetOnboarding 트리거 검증 (16-07 D-A2).
      verify(() => mockAuthRepo.signOutAndResetOnboarding()).called(1);
    });

    test(
      'N2 reauth required — AsyncValue.error(ReauthRequired) + signOut 미호출',
      () async {
        when(
          () => mockSettingsRepo.requestAccountDeletion(),
        ).thenThrow(const ReauthenticationRequiredException());

        final notifier = container.read(settingsProvider.notifier);
        await notifier.requestAccountDeletion();

        final state = container.read(settingsProvider);
        expect(state.hasError, isTrue);
        expect(state.error, isA<ReauthenticationRequiredException>());
        verifyNever(() => mockAuthRepo.signOutAndResetOnboarding());
      },
    );

    test(
      'N3 server fail — AsyncValue.error(UnknownException) + signOut 미호출',
      () async {
        when(
          () => mockSettingsRepo.requestAccountDeletion(),
        ).thenThrow(const UnknownException());

        final notifier = container.read(settingsProvider.notifier);
        await notifier.requestAccountDeletion();

        final state = container.read(settingsProvider);
        expect(state.hasError, isTrue);
        expect(state.error, isA<UnknownException>());
        verifyNever(() => mockAuthRepo.signOutAndResetOnboarding());
      },
    );

    test(
      'N4 CR-01 — 서버 삭제 성공 후 signOut 이 Exception throw 해도 data(null)',
      () async {
        // 서버 hard delete 는 이미 확정되어 되돌릴 수 없다. 이후의 로컬 정리
        // 실패를 "탈퇴 실패" 로 분류하면 사용자는 삭제된 계정으로 재시도를
        // 반복하게 된다 (10-REVIEW CR-01).
        when(
          () => mockSettingsRepo.requestAccountDeletion(),
        ).thenAnswer((_) async {});
        when(
          () => mockAuthRepo.signOutAndResetOnboarding(),
        ).thenThrow(Exception('signOut failed'));

        final notifier = container.read(settingsProvider.notifier);
        await notifier.requestAccountDeletion();

        final state = container.read(settingsProvider);
        expect(
          state.hasError,
          isFalse,
          reason: '서버 삭제가 확정된 뒤의 사후 정리 실패는 탈퇴 실패가 아니다',
        );
        expect(state, const AsyncValue<void>.data(null));
        verify(() => mockAuthRepo.signOutAndResetOnboarding()).called(1);
        // 흡수한 실패는 telemetry 로만 남는다.
        verify(
          () => mockCrashlytics.recordError(
            any<Object>(),
            any<StackTrace?>(),
            reason: 'withdrawal_post_signout',
            fatal: any(named: 'fatal'),
          ),
        ).called(1);
      },
    );

    test(
      'N5 CR-01 — signOut 이 Error 계열 (StateError) throw 해도 data(null)',
      () async {
        // 사후 정리 catch 의 폭이 Exception 이 아니라 Object 라는 증거.
        when(
          () => mockSettingsRepo.requestAccountDeletion(),
        ).thenAnswer((_) async {});
        when(
          () => mockAuthRepo.signOutAndResetOnboarding(),
        ).thenThrow(StateError('sdk logout in bad state'));

        final notifier = container.read(settingsProvider.notifier);
        await notifier.requestAccountDeletion();

        expect(
          container.read(settingsProvider),
          const AsyncValue<void>.data(null),
        );
      },
    );

    test('N6 CR-04 — 사후 정리(signOut) 가 지연돼도 성공 emit 은 먼저 도달한다', () async {
      // signOutAndResetOnboarding 은 6개 소셜 SDK logout 을 timeout 없이
      // 직렬 await 한다. 성공 emit 이 그 뒤에 있으면 되돌릴 수 없는 삭제가
      // 끝난 뒤에도 다이얼로그가 loading 에 고정된다 (10-REVIEW CR-04).
      final signOutGate = Completer<void>();
      when(
        () => mockSettingsRepo.requestAccountDeletion(),
      ).thenAnswer((_) async {});
      when(
        () => mockAuthRepo.signOutAndResetOnboarding(),
      ).thenAnswer((_) => signOutGate.future);

      final notifier = container.read(settingsProvider.notifier);
      final future = notifier.requestAccountDeletion();
      // repository await 만 해소시킨다 — signOut 은 gate 로 계속 대기 중.
      await pumpEventQueue();

      expect(
        signOutGate.isCompleted,
        isFalse,
        reason: '사후 정리가 아직 끝나지 않은 상태를 검증 대상으로 삼는다',
      );
      expect(
        container.read(settingsProvider).isLoading,
        isFalse,
        reason: '서버 삭제 확정 시점에 loading 이 해제되어야 한다',
      );
      expect(
        container.read(settingsProvider),
        const AsyncValue<void>.data(null),
      );

      signOutGate.complete();
      await future;

      verify(() => mockAuthRepo.signOutAndResetOnboarding()).called(1);
    });
  });

  group('Phase 16 WR-03/WR-04 — SettingsNotifier.linkProvider 결과 매핑', () {
    User stubUser() => User(
      uid: 'u1',
      email: 'user@example.com',
      emailVerified: true,
      createdAt: DateTime.utc(2026, 1, 1),
      providerIds: const ['google.com'],
    );

    test('L1 naver → linkNaverProviderArm 호출 + success (16.9 D-04)', () async {
      when(
        () => mockAuthRepo.linkNaverProviderArm(),
      ).thenAnswer((_) async => Result<User>.success(stubUser()));

      final notifier = container.read(settingsProvider.notifier);
      final outcome = await notifier.linkProvider(AccountProvider.naver);

      expect(outcome, AccountLinkOutcome.success);
      verify(() => mockAuthRepo.linkNaverProviderArm()).called(1);
      verifyNever(
        () => mockAuthRepo.linkCustomTokenProviderArm(
          targetProvider: any(named: 'targetProvider'),
        ),
      );
      verifyNever(() => mockAuthRepo.linkGoogleCredential());
    });

    test('L1b naver 취소(null) → cancelled', () async {
      when(
        () => mockAuthRepo.linkNaverProviderArm(),
      ).thenAnswer((_) async => null);

      final notifier = container.read(settingsProvider.notifier);
      final outcome = await notifier.linkProvider(AccountProvider.naver);

      expect(outcome, AccountLinkOutcome.cancelled);
    });

    test('L1c naver AccountAlreadyLinked → alreadyLinked', () async {
      // callable `already-exists` — Naver 신원이 다른 계정 소유.
      when(() => mockAuthRepo.linkNaverProviderArm()).thenAnswer(
        (_) async => const Result<User>.failure(AccountAlreadyLinked()),
      );

      final notifier = container.read(settingsProvider.notifier);
      final outcome = await notifier.linkProvider(AccountProvider.naver);

      expect(outcome, AccountLinkOutcome.alreadyLinked);
    });

    test('L2 email → unsupported + repository 미호출 (WR-03 단일 진실원)', () async {
      final notifier = container.read(settingsProvider.notifier);
      final outcome = await notifier.linkProvider(AccountProvider.email);

      expect(outcome, AccountLinkOutcome.unsupported);
      verifyNever(() => mockAuthRepo.linkGoogleCredential());
    });

    test('L3 google 성공 → success', () async {
      when(
        () => mockAuthRepo.linkGoogleCredential(),
      ).thenAnswer((_) async => Result<User>.success(stubUser()));

      final notifier = container.read(settingsProvider.notifier);
      final outcome = await notifier.linkProvider(AccountProvider.google);

      expect(outcome, AccountLinkOutcome.success);
      // 종료 후 state 는 data(null) 로 복귀.
      expect(
        container.read(settingsProvider),
        const AsyncValue<void>.data(null),
      );
    });

    test('L4 google reauth 필요 → reauthRequired', () async {
      when(() => mockAuthRepo.linkGoogleCredential()).thenAnswer(
        (_) async =>
            const Result<User>.failure(ReauthenticationRequiredException()),
      );

      final notifier = container.read(settingsProvider.notifier);
      final outcome = await notifier.linkProvider(AccountProvider.google);

      expect(outcome, AccountLinkOutcome.reauthRequired);
    });

    test('L5 google 미분류 실패 → failed (G-16-A6-2 catch-all)', () async {
      // 분류 arm 어디에도 걸리지 않는 실패는 조용히 사라지지 않고 catch-all
      // `failed` 로 보존된다 (기존 alreadyLinkedOrFailed collapse 대체).
      when(
        () => mockAuthRepo.linkGoogleCredential(),
      ).thenAnswer((_) async => const Result<User>.failure(UnknownException()));

      final notifier = container.read(settingsProvider.notifier);
      final outcome = await notifier.linkProvider(AccountProvider.google);

      expect(outcome, AccountLinkOutcome.failed);
    });

    test('L6 사용자 취소 (null) → cancelled', () async {
      when(
        () => mockAuthRepo.linkGoogleCredential(),
      ).thenAnswer((_) async => null);

      final notifier = container.read(settingsProvider.notifier);
      final outcome = await notifier.linkProvider(AccountProvider.google);

      expect(outcome, AccountLinkOutcome.cancelled);
    });

    test(
      'L7 Custom Token (kakao) → linkCustomTokenProviderArm dispatch',
      () async {
        when(
          () => mockAuthRepo.linkCustomTokenProviderArm(
            targetProvider: any(named: 'targetProvider'),
          ),
        ).thenAnswer((_) async => Result<User>.success(stubUser()));

        final notifier = container.read(settingsProvider.notifier);
        final outcome = await notifier.linkProvider(AccountProvider.kakao);

        expect(outcome, AccountLinkOutcome.success);
        verify(
          () => mockAuthRepo.linkCustomTokenProviderArm(
            targetProvider: AccountProvider.kakao,
          ),
        ).called(1);
      },
    );

    test('L8 AccountAlreadyLinked → alreadyLinked (G-16-A6-2)', () async {
      // A6 실측 원인 (credential-already-in-use / provider-already-linked) 이
      // 하류에서 collapse 되지 않고 전용 outcome 으로 보존되는지 검증.
      when(() => mockAuthRepo.linkFacebookCredential()).thenAnswer(
        (_) async => const Result<User>.failure(AccountAlreadyLinked()),
      );

      final notifier = container.read(settingsProvider.notifier);
      final outcome = await notifier.linkProvider(AccountProvider.facebook);

      expect(outcome, AccountLinkOutcome.alreadyLinked);
    });

    test(
      'L8b ProviderAlreadyLinkedToThisAccount → alreadyLinkedHere (WR-04)',
      () async {
        // `provider-already-linked` — 이미 **현재 계정에** 연결된 경우.
        // alreadyLinked ("다른 계정에 연결됨 → 먼저 해제") 로 뭉개면 사실과
        // 반대이면서 수행도 불가능한 안내가 나간다.
        when(() => mockAuthRepo.linkFacebookCredential()).thenAnswer(
          (_) async =>
              const Result<User>.failure(ProviderAlreadyLinkedToThisAccount()),
        );

        final notifier = container.read(settingsProvider.notifier);
        final outcome = await notifier.linkProvider(AccountProvider.facebook);

        expect(outcome, AccountLinkOutcome.alreadyLinkedHere);
        expect(outcome, isNot(AccountLinkOutcome.alreadyLinked));
      },
    );

    test('L9 EmailAlreadyInUse → emailInUse (G-16-A6-2)', () async {
      when(() => mockAuthRepo.linkGoogleCredential()).thenAnswer(
        (_) async => const Result<User>.failure(EmailAlreadyInUse()),
      );

      final notifier = container.read(settingsProvider.notifier);
      final outcome = await notifier.linkProvider(AccountProvider.google);

      expect(outcome, AccountLinkOutcome.emailInUse);
    });

    test('L9b AccountExistsWithDifferentCredential → emailInUse', () async {
      when(() => mockAuthRepo.linkGoogleCredential()).thenAnswer(
        (_) async =>
            const Result<User>.failure(AccountExistsWithDifferentCredential()),
      );

      final notifier = container.read(settingsProvider.notifier);
      final outcome = await notifier.linkProvider(AccountProvider.google);

      expect(outcome, AccountLinkOutcome.emailInUse);
    });

    test('L11 (WR-02) — link 진행 상태는 탈퇴용 state 를 건드리지 않는다', () async {
      // 두 유스케이스가 하나의 AsyncValue 를 공유하면 (a) 탈퇴 진행 중 연결
      // 버튼이 전부 잠기고 (b) 탈퇴 실패 error state 가 Settings 에 살아남고
      // (c) link 실패가 "탈퇴 실패" 로 오표시된다.
      final linkGate = Completer<Result<User>>();
      when(
        () => mockAuthRepo.linkGoogleCredential(),
      ).thenAnswer((_) => linkGate.future);

      final notifier = container.read(settingsProvider.notifier);
      final future = notifier.linkProvider(AccountProvider.google);
      await pumpEventQueue();

      // 진행 표시는 전용 플래그가 보유한다.
      expect(container.read(accountLinkInProgressProvider), isTrue);
      // 탈퇴용 state 는 loading 으로 흔들리지 않는다.
      expect(container.read(settingsProvider).isLoading, isFalse);
      expect(
        container.read(settingsProvider),
        const AsyncValue<void>.data(null),
      );

      linkGate.complete(Result<User>.success(stubUser()));
      expect(await future, AccountLinkOutcome.success);
      // finally 로 항상 해제된다.
      expect(container.read(accountLinkInProgressProvider), isFalse);
    });

    test('L12 (WR-02) — 미분류 예외 경로에서도 진행 플래그가 해제된다', () async {
      when(
        () => mockAuthRepo.linkGoogleCredential(),
      ).thenThrow(StateError('sdk in bad state'));

      final notifier = container.read(settingsProvider.notifier);
      final outcome = await notifier.linkProvider(AccountProvider.google);

      expect(outcome, AccountLinkOutcome.failed);
      expect(container.read(accountLinkInProgressProvider), isFalse);
    });

    test('L10 일시적 오류 3종 → transientFailure (G-16-A6-2)', () async {
      // NetworkException sealed 상위 1 arm 이 NoInternetConnection 을 흡수하고,
      // TooManyRequests / ServiceUnavailable 도 같은 outcome 으로 수렴한다.
      const transientExceptions = <AppException>[
        NoInternetConnection(),
        TooManyRequests(),
        ServiceUnavailable(),
      ];

      for (final exception in transientExceptions) {
        when(
          () => mockAuthRepo.linkGoogleCredential(),
        ).thenAnswer((_) async => Result<User>.failure(exception));

        final notifier = container.read(settingsProvider.notifier);
        final outcome = await notifier.linkProvider(AccountProvider.google);

        expect(
          outcome,
          AccountLinkOutcome.transientFailure,
          reason: '${exception.runtimeType} 은 transientFailure 이어야 한다',
        );
      }
    });

    test(
      'T-17-LINK-01 AppCheckFailedException → appCheckFailed (ServiceUnavailable 은 transientFailure 그대로)',
      () async {
        // Phase 17 D-42 · D-43 — App Check 차단은 일시 오류 · 재로그인과
        // 다른 전용 outcome 이다. 같은 ServerException 계열인
        // ServiceUnavailable 의 기존 매핑은 바뀌지 않는다.
        for (final (exception, expected)
            in <(AppException, AccountLinkOutcome)>[
              (
                const AppCheckFailedException(),
                AccountLinkOutcome.appCheckFailed,
              ),
              (const ServiceUnavailable(), AccountLinkOutcome.transientFailure),
            ]) {
          when(
            () => mockAuthRepo.linkGoogleCredential(),
          ).thenAnswer((_) async => Result<User>.failure(exception));

          final notifier = container.read(settingsProvider.notifier);
          final outcome = await notifier.linkProvider(AccountProvider.google);

          expect(outcome, expected, reason: '${exception.runtimeType}');
        }
      },
    );
  });

  group('Phase 16.8 D-03 · D-19 — SettingsNotifier.unlinkProvider', () {
    // 해제 성공 fixture — L 그룹 stubUser 와 같은 합성 값.
    User unlinkedUser() => User(
      uid: 'u1',
      email: 'user@example.com',
      emailVerified: true,
      createdAt: DateTime.utc(2026, 1, 1),
      providerIds: const ['kakao'],
      signUpProviderId: 'kakao',
    );

    test(
      'UN1: google.com → unlinkNativeProvider 만 · success · Firestore 0 (D-01)',
      () async {
        when(
          () => mockAuthRepo.unlinkNativeProvider('google.com'),
        ).thenAnswer((_) async => Result<User>.success(unlinkedUser()));

        final notifier = container.read(settingsProvider.notifier);
        final outcome = await notifier.unlinkProvider('google.com');

        expect(outcome, AccountUnlinkOutcome.success);
        verify(() => mockAuthRepo.unlinkNativeProvider('google.com')).called(1);
        verifyNever(() => mockAuthRepo.unlinkCustomTokenProvider(any()));
        // D-01 — 해제 dispatch 는 settings repository(Firestore) 를 만지지 않는다.
        verifyZeroInteractions(mockSettingsRepo);
      },
    );

    test(
      'UN2: kakao → unlinkCustomTokenProvider 만 · success · Firestore 0 (D-01)',
      () async {
        when(
          () => mockAuthRepo.unlinkCustomTokenProvider('kakao'),
        ).thenAnswer((_) async => Result<User>.success(unlinkedUser()));

        final notifier = container.read(settingsProvider.notifier);
        final outcome = await notifier.unlinkProvider('kakao');

        expect(outcome, AccountUnlinkOutcome.success);
        verify(() => mockAuthRepo.unlinkCustomTokenProvider('kakao')).called(1);
        verifyNever(() => mockAuthRepo.unlinkNativeProvider(any()));
        verifyZeroInteractions(mockSettingsRepo);
      },
    );

    test('UN3: 미지 id yahoo → failed · repository 미호출 (D-11)', () async {
      final notifier = container.read(settingsProvider.notifier);
      final outcome = await notifier.unlinkProvider('yahoo');

      expect(outcome, AccountUnlinkOutcome.failed);
      verifyNever(() => mockAuthRepo.unlinkNativeProvider(any()));
      verifyNever(() => mockAuthRepo.unlinkCustomTokenProvider(any()));
    });

    test('UN4: UnlinkLastCredentialRejected → lastCredential', () async {
      when(() => mockAuthRepo.unlinkCustomTokenProvider('kakao')).thenAnswer(
        (_) async => const Result<User>.failure(UnlinkLastCredentialRejected()),
      );

      final notifier = container.read(settingsProvider.notifier);
      final outcome = await notifier.unlinkProvider('kakao');

      expect(outcome, AccountUnlinkOutcome.lastCredential);
    });

    test('UN5: ProviderNotLinked → alreadyUnlinked', () async {
      when(() => mockAuthRepo.unlinkNativeProvider('google.com')).thenAnswer(
        (_) async => const Result<User>.failure(ProviderNotLinked()),
      );

      final notifier = container.read(settingsProvider.notifier);
      final outcome = await notifier.unlinkProvider('google.com');

      expect(outcome, AccountUnlinkOutcome.alreadyUnlinked);
    });

    test('UN6: ReauthenticationRequiredException → reauthRequired', () async {
      when(() => mockAuthRepo.unlinkNativeProvider('google.com')).thenAnswer(
        (_) async =>
            const Result<User>.failure(ReauthenticationRequiredException()),
      );

      final notifier = container.read(settingsProvider.notifier);
      final outcome = await notifier.unlinkProvider('google.com');

      expect(outcome, AccountUnlinkOutcome.reauthRequired);
    });

    test('UN7: 일시적 오류 3종 → transientFailure', () async {
      const transientExceptions = <AppException>[
        NoInternetConnection(),
        TooManyRequests(),
        ServiceUnavailable(),
      ];

      for (final exception in transientExceptions) {
        when(
          () => mockAuthRepo.unlinkNativeProvider('google.com'),
        ).thenAnswer((_) async => Result<User>.failure(exception));

        final notifier = container.read(settingsProvider.notifier);
        final outcome = await notifier.unlinkProvider('google.com');

        expect(
          outcome,
          AccountUnlinkOutcome.transientFailure,
          reason: '${exception.runtimeType} 은 transientFailure 이어야 한다',
        );
      }
    });

    test('UN8: UnknownException → failed (catch-all)', () async {
      when(
        () => mockAuthRepo.unlinkCustomTokenProvider('kakao'),
      ).thenAnswer((_) async => const Result<User>.failure(UnknownException()));

      final notifier = container.read(settingsProvider.notifier);
      final outcome = await notifier.unlinkProvider('kakao');

      expect(outcome, AccountUnlinkOutcome.failed);
    });

    test('UN9: repository 미흡수 throw → failed 로 흡수', () async {
      when(
        () => mockAuthRepo.unlinkNativeProvider('google.com'),
      ).thenThrow(StateError('boom'));

      final notifier = container.read(settingsProvider.notifier);
      final outcome = await notifier.unlinkProvider('google.com');

      expect(outcome, AccountUnlinkOutcome.failed);
    });

    test('UN10: (WR-02) 해제 진행 중에도 탈퇴용 state · 연결 진행 플래그 불변', () async {
      final unlinkGate = Completer<Result<User>>();
      when(
        () => mockAuthRepo.unlinkNativeProvider('google.com'),
      ).thenAnswer((_) => unlinkGate.future);

      final before = container.read(settingsProvider);
      final notifier = container.read(settingsProvider.notifier);
      final future = notifier.unlinkProvider('google.com');
      await pumpEventQueue();

      // 진행 표시는 다이얼로그 로컬 스피너 몫 — 두 provider 모두 흔들리지 않는다.
      expect(container.read(settingsProvider), before);
      expect(container.read(settingsProvider).isLoading, isFalse);
      expect(container.read(accountLinkInProgressProvider), isFalse);

      unlinkGate.complete(Result<User>.success(unlinkedUser()));
      expect(await future, AccountUnlinkOutcome.success);

      expect(container.read(settingsProvider), before);
      expect(container.read(accountLinkInProgressProvider), isFalse);
    });
  });
  group('Phase 16.10 D-09 · D-11 — disconnectAndUnlinkProvider', () {
    // 해제 성공 fixture — unlink group 과 같은 합성 값.
    User unlinkedUser() => User(
      uid: 'u1',
      email: 'user@example.com',
      emailVerified: true,
      createdAt: DateTime.utc(2026, 1, 1),
      providerIds: const ['kakao'],
      signUpProviderId: 'kakao',
    );

    /// [steps] 레지스트리 · dummy 실행 의존으로 container 를 만든다.
    ProviderContainer makeContainer(List<DisconnectStep> steps) {
      final scoped = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(mockSettingsRepo),
          authRepositoryProvider.overrideWithValue(mockAuthRepo),
          crashlyticsServiceProvider.overrideWithValue(mockCrashlytics),
          disconnectStepsProvider.overrideWithValue(steps),
          disconnectDepsProvider.overrideWithValue(_dummyDeps()),
        ],
      );
      addTearDown(scoped.dispose);
      return scoped;
    }

    /// Google 재로그인 행 fake — [outcome] 을 돌려준다.
    _FixedStep googleStep(DisconnectOutcome outcome, {Object? error}) =>
        _FixedStep(
          AccountProvider.google,
          outcome,
          signInStrategy: const GoogleAuthStrategy(),
          error: error,
        );

    test(
      'DU1: google.com 재로그인 행 Done → unlinkNativeProvider 1 · success · 세션 교체 0',
      () async {
        final step = googleStep(const DisconnectDone());
        when(
          () => mockAuthRepo.unlinkNativeProvider('google.com'),
        ).thenAnswer((_) async => Result<User>.success(unlinkedUser()));
        final scoped = makeContainer(<DisconnectStep>[step]);

        final outcome = await scoped
            .read(settingsProvider.notifier)
            .disconnectAndUnlinkProvider('google.com');

        expect(outcome, AccountUnlinkOutcome.success);
        expect(step.relogins, hasLength(1));
        // D-09 — 해제는 신선도가 필요 없어 custom token 소비 · 세션 교체 0.
        expect(step.lastRelogin, isFalse);
        verify(() => mockAuthRepo.unlinkNativeProvider('google.com')).called(1);
        verifyNever(() => mockAuthRepo.unlinkCustomTokenProvider(any()));
        verifyZeroInteractions(mockSettingsRepo);
      },
    );

    test(
      'DU2: kakao 서버 행 Done → unlinkCustomTokenProvider 1 · success',
      () async {
        final step = _FixedStep(AccountProvider.kakao, const DisconnectDone());
        when(
          () => mockAuthRepo.unlinkCustomTokenProvider('kakao'),
        ).thenAnswer((_) async => Result<User>.success(unlinkedUser()));
        final scoped = makeContainer(<DisconnectStep>[step]);

        final outcome = await scoped
            .read(settingsProvider.notifier)
            .disconnectAndUnlinkProvider('kakao');

        expect(outcome, AccountUnlinkOutcome.success);
        expect(step.relogins, hasLength(1));
        verify(() => mockAuthRepo.unlinkCustomTokenProvider('kakao')).called(1);
        verifyNever(() => mockAuthRepo.unlinkNativeProvider(any()));
      },
    );

    test('DU3: 신원 불일치 → identityMismatch · 킷 해제 0 (D-08 · 연결 유지)', () async {
      final step = googleStep(const DisconnectIdentityMismatch());
      final scoped = makeContainer(<DisconnectStep>[step]);

      final outcome = await scoped
          .read(settingsProvider.notifier)
          .disconnectAndUnlinkProvider('google.com');

      expect(outcome, AccountUnlinkOutcome.identityMismatch);
      verifyNever(() => mockAuthRepo.unlinkNativeProvider(any()));
      verifyNever(() => mockAuthRepo.unlinkCustomTokenProvider(any()));
    });

    test(
      'DU4: Failed(ServiceUnavailable) → disconnectFailed · 킷 해제 0 (D-11)',
      () async {
        final step = _FixedStep(
          AccountProvider.kakao,
          const DisconnectFailed(ServiceUnavailable()),
        );
        final scoped = makeContainer(<DisconnectStep>[step]);

        final outcome = await scoped
            .read(settingsProvider.notifier)
            .disconnectAndUnlinkProvider('kakao');

        expect(outcome, AccountUnlinkOutcome.disconnectFailed);
        verifyNever(() => mockAuthRepo.unlinkNativeProvider(any()));
        verifyNever(() => mockAuthRepo.unlinkCustomTokenProvider(any()));
      },
    );

    test(
      'DU5: Failed(NoInternetConnection) · Failed(TooManyRequests) → transientFailure · 킷 해제 0',
      () async {
        const failures = <AppException>[
          NoInternetConnection(),
          TooManyRequests(),
        ];
        for (final exception in failures) {
          final step = googleStep(DisconnectFailed(exception));
          final scoped = makeContainer(<DisconnectStep>[step]);

          final outcome = await scoped
              .read(settingsProvider.notifier)
              .disconnectAndUnlinkProvider('google.com');

          expect(
            outcome,
            AccountUnlinkOutcome.transientFailure,
            reason: '${exception.runtimeType} 은 transientFailure 이어야 한다',
          );
        }
        verifyNever(() => mockAuthRepo.unlinkNativeProvider(any()));
        verifyNever(() => mockAuthRepo.unlinkCustomTokenProvider(any()));
      },
    );

    test('DU6: provider 로그인 취소 → cancelled · 킷 해제 0 (D-11)', () async {
      final step = googleStep(const DisconnectCancelled());
      final scoped = makeContainer(<DisconnectStep>[step]);

      final outcome = await scoped
          .read(settingsProvider.notifier)
          .disconnectAndUnlinkProvider('google.com');

      expect(outcome, AccountUnlinkOutcome.cancelled);
      verifyNever(() => mockAuthRepo.unlinkNativeProvider(any()));
      verifyNever(() => mockAuthRepo.unlinkCustomTokenProvider(any()));
    });

    test(
      'DU7: password — 끊기 행 없음 → step 호출 0 · unlinkNativeProvider(password) 1',
      () async {
        final google = googleStep(const DisconnectDone());
        final kakao = _FixedStep(AccountProvider.kakao, const DisconnectDone());
        when(
          () => mockAuthRepo.unlinkNativeProvider('password'),
        ).thenAnswer((_) async => Result<User>.success(unlinkedUser()));
        final scoped = makeContainer(<DisconnectStep>[google, kakao]);

        final outcome = await scoped
            .read(settingsProvider.notifier)
            .disconnectAndUnlinkProvider('password');

        expect(outcome, AccountUnlinkOutcome.success);
        expect(google.relogins, isEmpty);
        expect(kakao.relogins, isEmpty);
        verify(() => mockAuthRepo.unlinkNativeProvider('password')).called(1);
      },
    );

    test('DU8: 미지 id yahoo → failed · step · repository 호출 0', () async {
      final google = googleStep(const DisconnectDone());
      final scoped = makeContainer(<DisconnectStep>[google]);

      final outcome = await scoped
          .read(settingsProvider.notifier)
          .disconnectAndUnlinkProvider('yahoo');

      expect(outcome, AccountUnlinkOutcome.failed);
      expect(google.relogins, isEmpty);
      verifyNever(() => mockAuthRepo.unlinkNativeProvider(any()));
      verifyNever(() => mockAuthRepo.unlinkCustomTokenProvider(any()));
    });

    test('DU9: step 예상 밖 throw → disconnectFailed · 킷 해제 0 (방어)', () async {
      final step = googleStep(
        const DisconnectDone(),
        error: StateError('boom'),
      );
      final scoped = makeContainer(<DisconnectStep>[step]);

      final outcome = await scoped
          .read(settingsProvider.notifier)
          .disconnectAndUnlinkProvider('google.com');

      expect(outcome, AccountUnlinkOutcome.disconnectFailed);
      verifyNever(() => mockAuthRepo.unlinkNativeProvider(any()));
    });

    test(
      'DU10 (review IN-03 iter3): 끊기 Done 뒤 해제 transient · failed → unlinkFailedAfterDisconnect',
      () async {
        // 일시 오류 3종(transientFailure) · 미분류(failed) — 재로그인 행 · 서버 행.
        const failures = <AppException>[
          NoInternetConnection(),
          TooManyRequests(),
          ServiceUnavailable(),
          UnknownException(),
        ];
        for (final exception in failures) {
          final google = googleStep(const DisconnectDone());
          final kakao = _FixedStep(
            AccountProvider.kakao,
            const DisconnectDone(),
          );
          when(
            () => mockAuthRepo.unlinkNativeProvider('google.com'),
          ).thenAnswer((_) async => Result<User>.failure(exception));
          when(
            () => mockAuthRepo.unlinkCustomTokenProvider('kakao'),
          ).thenAnswer((_) async => Result<User>.failure(exception));
          final scoped = makeContainer(<DisconnectStep>[google, kakao]);
          final notifier = scoped.read(settingsProvider.notifier);

          expect(
            await notifier.disconnectAndUnlinkProvider('google.com'),
            AccountUnlinkOutcome.unlinkFailedAfterDisconnect,
            reason: 'google ${exception.runtimeType}',
          );
          expect(
            await notifier.disconnectAndUnlinkProvider('kakao'),
            AccountUnlinkOutcome.unlinkFailedAfterDisconnect,
            reason: 'kakao ${exception.runtimeType}',
          );
          expect(google.relogins, hasLength(1));
          expect(kakao.relogins, hasLength(1));
        }
      },
    );

    test(
      'DU10b (review IN-03 iter3): 끊기 Done 뒤 해제가 예상 밖 throw(failed) → unlinkFailedAfterDisconnect',
      () async {
        final step = googleStep(const DisconnectDone());
        when(
          () => mockAuthRepo.unlinkNativeProvider('google.com'),
        ).thenThrow(StateError('boom'));
        final scoped = makeContainer(<DisconnectStep>[step]);

        final outcome = await scoped
            .read(settingsProvider.notifier)
            .disconnectAndUnlinkProvider('google.com');

        expect(outcome, AccountUnlinkOutcome.unlinkFailedAfterDisconnect);
      },
    );

    test(
      'DU11 (review IN-03 iter3): 끊기 Done 뒤 lastCredential · alreadyUnlinked · reauthRequired 는 기존 outcome',
      () async {
        for (final (exception, expected)
            in <(AppException, AccountUnlinkOutcome)>[
              (
                const UnlinkLastCredentialRejected(),
                AccountUnlinkOutcome.lastCredential,
              ),
              (const ProviderNotLinked(), AccountUnlinkOutcome.alreadyUnlinked),
              (
                const ReauthenticationRequiredException(),
                AccountUnlinkOutcome.reauthRequired,
              ),
            ]) {
          final step = googleStep(const DisconnectDone());
          when(
            () => mockAuthRepo.unlinkNativeProvider('google.com'),
          ).thenAnswer((_) async => Result<User>.failure(exception));
          final scoped = makeContainer(<DisconnectStep>[step]);

          final outcome = await scoped
              .read(settingsProvider.notifier)
              .disconnectAndUnlinkProvider('google.com');

          expect(outcome, expected, reason: '${exception.runtimeType}');
        }
      },
    );

    test(
      'DU12 (review IN-03 iter3): 이메일/비밀번호(끊기 step 없음) · unlinkProvider 는 transient · failed 그대로',
      () async {
        final google = googleStep(const DisconnectDone());
        final scoped = makeContainer(<DisconnectStep>[google]);
        final notifier = scoped.read(settingsProvider.notifier);
        for (final (exception, expected)
            in <(AppException, AccountUnlinkOutcome)>[
              (
                const NoInternetConnection(),
                AccountUnlinkOutcome.transientFailure,
              ),
              (const UnknownException(), AccountUnlinkOutcome.failed),
            ]) {
          when(
            () => mockAuthRepo.unlinkNativeProvider(any()),
          ).thenAnswer((_) async => Result<User>.failure(exception));

          expect(
            await notifier.disconnectAndUnlinkProvider('password'),
            expected,
            reason: 'password ${exception.runtimeType}',
          );
          // 16.8 경로(끊기 없음)도 바뀌지 않는다.
          expect(
            await notifier.unlinkProvider('google.com'),
            expected,
            reason: 'unlinkProvider ${exception.runtimeType}',
          );
        }
        expect(google.relogins, isEmpty);
      },
    );

    test(
      'DU13 (review IN-04 iter3): 끊기 Failed(ProviderMisconfigured) → providerConfigFailed · 킷 해제 0',
      () async {
        for (final provider in <AccountProvider>[
          AccountProvider.kakao,
          AccountProvider.google,
        ]) {
          final step = provider == AccountProvider.google
              ? googleStep(const DisconnectFailed(ProviderMisconfigured()))
              : _FixedStep(
                  provider,
                  const DisconnectFailed(ProviderMisconfigured()),
                );
          final scoped = makeContainer(<DisconnectStep>[step]);

          final outcome = await scoped
              .read(settingsProvider.notifier)
              .disconnectAndUnlinkProvider(
                provider == AccountProvider.google ? 'google.com' : 'kakao',
              );

          expect(
            outcome,
            AccountUnlinkOutcome.providerConfigFailed,
            reason: provider.slug,
          );
        }
        // 일시 · 기타 서버 원인은 기존 outcome 그대로 (DU4 · DU5 와 같은 분류).
        final other = makeContainer(<DisconnectStep>[
          _FixedStep(
            AccountProvider.kakao,
            const DisconnectFailed(ServiceUnavailable()),
          ),
        ]);
        expect(
          await other
              .read(settingsProvider.notifier)
              .disconnectAndUnlinkProvider('kakao'),
          AccountUnlinkOutcome.disconnectFailed,
        );
        verifyNever(() => mockAuthRepo.unlinkNativeProvider(any()));
        verifyNever(() => mockAuthRepo.unlinkCustomTokenProvider(any()));
      },
    );
  });
}
