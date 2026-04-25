import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/presentation/forgot_password_notifier.dart';

/// [AuthRepository] 를 mocktail 로 대체하기 위한 Mock.
class _MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late _MockAuthRepository mockRepo;

  setUp(() {
    mockRepo = _MockAuthRepository();
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(mockRepo)],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('ForgotPasswordNotifier.submit', () {
    test('성공 시 AsyncData(null) 상태로 전환된다', () async {
      when(
        () => mockRepo.sendPasswordReset(email: any(named: 'email')),
      ).thenAnswer((_) async => const Result.success(null));

      final container = makeContainer();
      await container
          .read(forgotPasswordProvider.notifier)
          .submit(email: 'a@b.com');

      expect(container.read(forgotPasswordProvider), isA<AsyncData<void>>());
    });

    test('InvalidEmail 에러 시 AsyncError 상태로 전환된다', () async {
      when(
        () => mockRepo.sendPasswordReset(email: any(named: 'email')),
      ).thenAnswer((_) async => const Result.failure(InvalidEmail()));

      final container = makeContainer();
      await container
          .read(forgotPasswordProvider.notifier)
          .submit(email: 'bad');

      final state = container.read(forgotPasswordProvider);
      expect(state, isA<AsyncError<void>>());
      expect(state.error, isA<InvalidEmail>());
    });

    test('Repository 호출 인자가 정확히 전달된다', () async {
      when(
        () => mockRepo.sendPasswordReset(email: any(named: 'email')),
      ).thenAnswer((_) async => const Result.success(null));

      final container = makeContainer();
      await container
          .read(forgotPasswordProvider.notifier)
          .submit(email: 'user@example.com');

      verify(
        () => mockRepo.sendPasswordReset(email: 'user@example.com'),
      ).called(1);
    });
  });
}
