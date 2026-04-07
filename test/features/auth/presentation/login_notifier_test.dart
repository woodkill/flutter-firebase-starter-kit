import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/auth/presentation/login_notifier.dart';

/// [AuthRepository] 를 mocktail 로 대체하기 위한 Mock.
class _MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late _MockAuthRepository mockRepo;

  setUp(() {
    mockRepo = _MockAuthRepository();
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(mockRepo),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('LoginNotifier.submit', () {
    test('성공 시 AsyncData(null) 상태로 전환된다', () async {
      final user = User(
        uid: 'u1',
        email: 'a@b.com',
        createdAt: DateTime.utc(2026),
      );
      when(
        () => mockRepo.signInWithEmail(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => Result.success(user));

      final container = makeContainer();
      final notifier = container.read(loginProvider.notifier);

      await notifier.submit(email: 'a@b.com', password: 'password123');

      final state = container.read(loginProvider);
      expect(state, isA<AsyncData<void>>());
      expect(state.hasError, isFalse);
    });

    test('실패 시 AsyncError 상태로 전환된다', () async {
      when(
        () => mockRepo.signInWithEmail(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer(
        (_) async => const Result.failure(InvalidCredentials()),
      );

      final container = makeContainer();
      final notifier = container.read(loginProvider.notifier);

      await notifier.submit(email: 'a@b.com', password: 'wrong');

      final state = container.read(loginProvider);
      expect(state, isA<AsyncError<void>>());
      expect(state.error, isA<InvalidCredentials>());
    });

    test('Repository 호출 인자가 정확히 전달된다', () async {
      when(
        () => mockRepo.signInWithEmail(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer(
        (_) async => Result.success(
          User(
            uid: 'u1',
            email: 'a@b.com',
            createdAt: DateTime.utc(2026),
          ),
        ),
      );

      final container = makeContainer();
      await container.read(loginProvider.notifier).submit(
            email: 'user@example.com',
            password: 'secret123',
          );

      verify(
        () => mockRepo.signInWithEmail(
          email: 'user@example.com',
          password: 'secret123',
        ),
      ).called(1);
    });
  });
}
