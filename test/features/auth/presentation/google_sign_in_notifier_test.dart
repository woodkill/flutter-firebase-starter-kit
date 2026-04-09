import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/auth/presentation/google_sign_in_notifier.dart';

/// [AuthRepository]를 mocktail로 대체하기 위한 Mock.
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

  group('GoogleSignInNotifier.signInWithGoogle', () {
    test('성공 시 AsyncData(null) 상태로 전환된다', () async {
      final user = User(
        uid: 'u1',
        email: 'test@google.com',
        emailVerified: true,
        createdAt: DateTime.utc(2026),
      );
      when(() => mockRepo.signInWithGoogle())
          .thenAnswer((_) async => Result.success(user));

      final container = makeContainer();
      final notifier = container.read(googleSignInProvider.notifier);

      await notifier.signInWithGoogle();

      final state = container.read(googleSignInProvider);
      expect(state, isA<AsyncData<void>>());
      expect(state.hasError, isFalse);
    });

    test('취소(null 반환) 시 AsyncData 상태로 유지된다 (D-06)', () async {
      when(() => mockRepo.signInWithGoogle())
          .thenAnswer((_) async => null);

      final container = makeContainer();
      final notifier = container.read(googleSignInProvider.notifier);

      await notifier.signInWithGoogle();

      final state = container.read(googleSignInProvider);
      expect(state, isA<AsyncData<void>>());
      expect(state.hasError, isFalse);
    });

    test('Failure 반환 시 AsyncError 상태로 전환된다', () async {
      when(() => mockRepo.signInWithGoogle()).thenAnswer(
        (_) async => const Result.failure(ServiceUnavailable()),
      );

      final container = makeContainer();
      final notifier = container.read(googleSignInProvider.notifier);

      await notifier.signInWithGoogle();

      final state = container.read(googleSignInProvider);
      expect(state, isA<AsyncError<void>>());
      expect(state.error, isA<ServiceUnavailable>());
    });

    test(
      'AccountExistsWithDifferentCredential 반환 시 '
      'AsyncError이고 에러가 해당 타입이다',
      () async {
        when(() => mockRepo.signInWithGoogle()).thenAnswer(
          (_) async => const Result.failure(
            AccountExistsWithDifferentCredential(email: 'user@email.com'),
          ),
        );

        final container = makeContainer();
        final notifier = container.read(googleSignInProvider.notifier);

        await notifier.signInWithGoogle();

        final state = container.read(googleSignInProvider);
        expect(state, isA<AsyncError<void>>());
        expect(state.error, isA<AccountExistsWithDifferentCredential>());
        final error = state.error! as AccountExistsWithDifferentCredential;
        expect(error.email, 'user@email.com');
      },
    );
  });
}
