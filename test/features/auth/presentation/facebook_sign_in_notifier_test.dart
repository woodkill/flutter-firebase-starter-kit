import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/auth/presentation/facebook_sign_in_notifier.dart';

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

  group('FacebookSignInNotifier.signInWithFacebook', () {
    test('성공 시 AsyncData(null) 상태로 전환된다', () async {
      final user = User(
        uid: 'fb-uid-001',
        email: 'test@facebook.com',
        emailVerified: true,
        createdAt: DateTime.utc(2026, 4, 13),
        providerIds: const <String>['facebook.com'],
      );
      when(
        () => mockRepo.signInWithFacebook(),
      ).thenAnswer((_) async => Result<User>.success(user));

      final container = makeContainer();
      final notifier = container.read(facebookSignInProvider.notifier);

      await notifier.signInWithFacebook();

      final state = container.read(facebookSignInProvider);
      expect(state, isA<AsyncData<void>>());
      expect(state.hasError, isFalse);
    });

    test('취소(null 반환) 시 AsyncData 상태로 유지된다 (D-09)', () async {
      when(() => mockRepo.signInWithFacebook()).thenAnswer((_) async => null);

      final container = makeContainer();
      final notifier = container.read(facebookSignInProvider.notifier);

      await notifier.signInWithFacebook();

      final state = container.read(facebookSignInProvider);
      expect(state, isA<AsyncData<void>>());
      expect(state.hasError, isFalse);
    });

    test('Failure 반환 시 AsyncError 상태로 전환된다', () async {
      when(() => mockRepo.signInWithFacebook()).thenAnswer(
        (_) async => const Result<User>.failure(ServiceUnavailable()),
      );

      final container = makeContainer();
      final notifier = container.read(facebookSignInProvider.notifier);

      await notifier.signInWithFacebook();

      final state = container.read(facebookSignInProvider);
      expect(state, isA<AsyncError<void>>());
      expect(state.error, isA<ServiceUnavailable>());
    });

    test('dispose 후 signInWithFacebook이 완료되어도 '
        'state 업데이트가 스킵된다 (ref.mounted 가드)', () async {
      final completer = Completer<Result<User>?>();
      when(
        () => mockRepo.signInWithFacebook(),
      ).thenAnswer((_) => completer.future);

      final container = makeContainer();
      final notifier = container.read(facebookSignInProvider.notifier);

      final future = notifier.signInWithFacebook();

      // container dispose로 ref.mounted = false 유도.
      container.dispose();

      final user = User(
        uid: 'fb-uid-002',
        email: 'late@facebook.com',
        emailVerified: true,
        createdAt: DateTime.utc(2026, 4, 13),
      );
      completer.complete(Result<User>.success(user));

      // 예외 없이 완료되어야 한다 (ref.mounted 가드가 state 업데이트를 차단).
      await future;
    });
  });
}
