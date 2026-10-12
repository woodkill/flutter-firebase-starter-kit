// Riverpod notifier 를 시험하는 unit 테스트 예제다.
//
// `ProviderContainer` 에 provider override 를 넘겨 notifier 가 읽는 의존성을
// mock 으로 바꾸고, 메서드를 부른 뒤 상태(`AsyncValue`)를 단언한다.
// 이 파일을 복사해 내 notifier 테스트를 만드는 방법은 `test/README.md` 에 있다.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/auth/presentation/login_notifier.dart';

/// 로그인 notifier 가 읽는 [AuthRepository] 를 대신하는 mock.
class _MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late _MockAuthRepository mockRepo;

  setUp(() {
    mockRepo = _MockAuthRepository();
  });

  // AuthRepository 를 mock 으로 바꾼 컨테이너를 만든다. 테스트가 끝나면 닫힌다.
  ProviderContainer createContainer() {
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(mockRepo)],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('LoginNotifier 예제', () {
    test('올바른 이메일과 비밀번호로 로그인하면 상태가 AsyncData 가 된다', () async {
      final user = User(
        uid: 'user-1',
        email: 'user@example.com',
        emailVerified: true,
        createdAt: DateTime.utc(2024),
      );
      when(
        () => mockRepo.signInWithEmail(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => Result.success(user));

      final container = createContainer();
      await container
          .read(loginProvider.notifier)
          .submit(email: 'user@example.com', password: 'password123');

      expect(container.read(loginProvider), isA<AsyncData<void>>());
      verify(
        () => mockRepo.signInWithEmail(
          email: 'user@example.com',
          password: 'password123',
        ),
      ).called(1);
    });

    test('잘못된 비밀번호면 상태가 AsyncError 이고 오류는 InvalidCredentials 다', () async {
      when(
        () => mockRepo.signInWithEmail(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => const Result.failure(InvalidCredentials()));

      final container = createContainer();
      await container
          .read(loginProvider.notifier)
          .submit(email: 'user@example.com', password: 'wrong-password');

      final state = container.read(loginProvider);
      expect(state, isA<AsyncError<void>>());
      expect(state.error, isA<InvalidCredentials>());
    });
  });
}
