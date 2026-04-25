import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/auth/presentation/apple_sign_in_notifier.dart';

/// [AuthRepository]를 mocktail로 대체하기 위한 Mock.
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

  group('AppleSignInNotifier.signInWithApple', () {
    test('AUTH-03-08: 성공 시 AsyncData(null) 상태로 전환된다', () async {
      final user = User(
        uid: 'apple-uid-123',
        email: 'test@privaterelay.appleid.com',
        emailVerified: true,
        createdAt: DateTime.utc(2026, 4, 11),
        providerIds: const <String>['apple.com'],
      );
      when(
        () => mockRepo.signInWithApple(),
      ).thenAnswer((_) async => Result<User>.success(user));

      final container = makeContainer();
      final notifier = container.read(appleSignInProvider.notifier);

      await notifier.signInWithApple();

      final state = container.read(appleSignInProvider);
      expect(state, isA<AsyncData<void>>());
      expect(state.hasError, isFalse);
    });

    test('AUTH-03-09: 취소(null 반환) 시 AsyncData 상태로 유지된다 (D-09)', () async {
      when(() => mockRepo.signInWithApple()).thenAnswer((_) async => null);

      final container = makeContainer();
      final notifier = container.read(appleSignInProvider.notifier);

      await notifier.signInWithApple();

      final state = container.read(appleSignInProvider);
      expect(state, isA<AsyncData<void>>());
      expect(state.hasError, isFalse);
    });

    test('AUTH-03-10: Failure 반환 시 AsyncError 상태로 전환되고 '
        '예외 타입이 보존된다', () async {
      when(() => mockRepo.signInWithApple()).thenAnswer(
        (_) async => const Result<User>.failure(ServiceUnavailable()),
      );

      final container = makeContainer();
      final notifier = container.read(appleSignInProvider.notifier);

      await notifier.signInWithApple();

      final state = container.read(appleSignInProvider);
      expect(state, isA<AsyncError<void>>());
      expect(state.error, isA<ServiceUnavailable>());
    });

    test('AccountExistsWithDifferentCredential 반환 시 AsyncError이고 '
        'email 필드가 보존된다 (D-10 이메일 자동 채움 전제)', () async {
      when(() => mockRepo.signInWithApple()).thenAnswer(
        (_) async => const Result<User>.failure(
          AccountExistsWithDifferentCredential(email: 'user@example.com'),
        ),
      );

      final container = makeContainer();
      final notifier = container.read(appleSignInProvider.notifier);

      await notifier.signInWithApple();

      final state = container.read(appleSignInProvider);
      expect(state, isA<AsyncError<void>>());
      expect(state.error, isA<AccountExistsWithDifferentCredential>());
      final error = state.error! as AccountExistsWithDifferentCredential;
      expect(error.email, 'user@example.com');
    });
  });
}
