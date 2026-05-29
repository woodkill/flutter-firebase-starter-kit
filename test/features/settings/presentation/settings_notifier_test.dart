// ignore_for_file: lines_longer_than_80_chars
//
// Phase 16 Plan 16-06 Task 6.1 — SettingsNotifier 단위 테스트.
//
// 검증 surface:
// - N1 happy path: requestAccountDeletion → AsyncValue.loading →
//   AsyncValue.data + signOut 호출
// - N2 reauth required: repository throws ReauthenticationRequiredException →
//   AsyncValue.error(ReauthenticationRequiredException), signOut 미호출
// - N3 server fail: repository throws UnknownException →
//   AsyncValue.error(UnknownException), signOut 미호출

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/settings/data/settings_repository.dart';
import 'package:flutter_starter_kit/features/settings/presentation/settings_notifier.dart';

class _MockSettingsRepository extends Mock implements SettingsRepository {}

class _MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late _MockSettingsRepository mockSettingsRepo;
  late _MockAuthRepository mockAuthRepo;
  late ProviderContainer container;

  setUp(() {
    mockSettingsRepo = _MockSettingsRepository();
    mockAuthRepo = _MockAuthRepository();

    when(() => mockAuthRepo.signOut()).thenAnswer((_) async {});

    container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(mockSettingsRepo),
        authRepositoryProvider.overrideWithValue(mockAuthRepo),
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
      // signOut 트리거 검증.
      verify(() => mockAuthRepo.signOut()).called(1);
    });

    test('N2 reauth required — AsyncValue.error(ReauthRequired) + signOut 미호출',
        () async {
      when(
        () => mockSettingsRepo.requestAccountDeletion(),
      ).thenThrow(const ReauthenticationRequiredException());

      final notifier = container.read(settingsProvider.notifier);
      await notifier.requestAccountDeletion();

      final state = container.read(settingsProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isA<ReauthenticationRequiredException>());
      verifyNever(() => mockAuthRepo.signOut());
    });

    test('N3 server fail — AsyncValue.error(UnknownException) + signOut 미호출',
        () async {
      when(
        () => mockSettingsRepo.requestAccountDeletion(),
      ).thenThrow(const UnknownException());

      final notifier = container.read(settingsProvider.notifier);
      await notifier.requestAccountDeletion();

      final state = container.read(settingsProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isA<UnknownException>());
      verifyNever(() => mockAuthRepo.signOut());
    });
  });
}
