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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/crashlytics/crashlytics_service.dart';
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/settings/data/settings_repository.dart';
import 'package:flutter_starter_kit/features/settings/presentation/settings_notifier.dart';

class _MockSettingsRepository extends Mock implements SettingsRepository {}

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockCrashlyticsService extends Mock implements CrashlyticsService {}

class _FakeStackTrace extends Fake implements StackTrace {}

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
  });

  group('Phase 16 WR-03/WR-04 — SettingsNotifier.linkProvider 결과 매핑', () {
    User stubUser() => User(
      uid: 'u1',
      email: 'user@example.com',
      emailVerified: true,
      createdAt: DateTime.utc(2026, 1, 1),
      providerIds: const ['google.com'],
    );

    test('L1 naver → unsupported + repository 미호출 (WR-03 단일 진실원)', () async {
      final notifier = container.read(settingsProvider.notifier);
      final outcome = await notifier.linkProvider(AccountProvider.naver);

      expect(outcome, AccountLinkOutcome.unsupported);
      verifyNever(() => mockAuthRepo.linkGoogleCredential());
      verifyNever(() => mockAuthRepo.linkAppleCredential());
      verifyNever(() => mockAuthRepo.linkFacebookCredential());
      verifyNever(
        () => mockAuthRepo.linkCustomTokenProviderArm(
          targetProvider: any(named: 'targetProvider'),
        ),
      );
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
  });
}
