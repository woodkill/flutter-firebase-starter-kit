import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/auth/presentation/signup_notifier.dart';

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

  group('SignupNotifier.submit', () {
    test('성공 시 AsyncData(null) 상태로 전환된다', () async {
      final user = User(
        uid: 'u1',
        email: 'a@b.com',
        emailVerified: true,
        displayName: 'Name',
        createdAt: DateTime.utc(2026),
      );
      when(
        () => mockRepo.signUpWithEmail(
          email: any(named: 'email'),
          password: any(named: 'password'),
          displayName: any(named: 'displayName'),
        ),
      ).thenAnswer((_) async => Result.success(user));

      final container = makeContainer();
      final notifier = container.read(signupProvider.notifier);

      await notifier.submit(
        email: 'a@b.com',
        password: 'password123',
        displayName: 'Name',
      );

      final state = container.read(signupProvider);
      expect(state, isA<AsyncData<void>>());
      expect(state.hasError, isFalse);
    });

    test('EmailAlreadyInUse 시 AsyncError 상태로 전환된다', () async {
      when(
        () => mockRepo.signUpWithEmail(
          email: any(named: 'email'),
          password: any(named: 'password'),
          displayName: any(named: 'displayName'),
        ),
      ).thenAnswer((_) async => const Result.failure(EmailAlreadyInUse()));

      final container = makeContainer();
      final notifier = container.read(signupProvider.notifier);

      await notifier.submit(
        email: 'a@b.com',
        password: 'password123',
        displayName: 'Name',
      );

      final state = container.read(signupProvider);
      expect(state, isA<AsyncError<void>>());
      expect(state.error, isA<EmailAlreadyInUse>());
    });

    test('Repository 호출 인자가 정확히 전달된다 (displayName 포함)', () async {
      when(
        () => mockRepo.signUpWithEmail(
          email: any(named: 'email'),
          password: any(named: 'password'),
          displayName: any(named: 'displayName'),
        ),
      ).thenAnswer(
        (_) async => Result.success(
          User(
            uid: 'u1',
            email: 'new@example.com',
            emailVerified: true,
            displayName: 'New User',
            createdAt: DateTime.utc(2026),
          ),
        ),
      );

      final container = makeContainer();
      await container
          .read(signupProvider.notifier)
          .submit(
            email: 'new@example.com',
            password: 'password123',
            displayName: 'New User',
          );

      verify(
        () => mockRepo.signUpWithEmail(
          email: 'new@example.com',
          password: 'password123',
          displayName: 'New User',
        ),
      ).called(1);
    });
  });
}
