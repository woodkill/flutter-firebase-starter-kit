// Phase 14 — see ROADMAP.md (LineSignInNotifier unit tests)
//
// Pattern: kakao_sign_in_notifier_test.dart / naver_sign_in_notifier_test.dart
// 의 ProviderContainer + Mock AuthRepository 패턴 mirror.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/auth/presentation/line_sign_in_notifier.dart';

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

  group('LineSignInNotifier.signInWithLine', () {
    test('Test 1 (build initial): 초기 state = AsyncData<void>(null)', () {
      final container = makeContainer();
      final state = container.read(lineSignInProvider);
      expect(state, isA<AsyncData<void>>());
      expect(state.hasError, isFalse);
      expect(state.isLoading, isFalse);
    });

    test('Test 2 (성공): repository Result.success → AsyncData(null)',
        () async {
      // Custom Token 흐름: emailVerified=true 자동 부여 (D-LINE-21 docstring).
      final user = User(
        uid: 'line-uid-001',
        email: 'test@line.me',
        emailVerified: true,
        createdAt: DateTime.utc(2026, 5, 19),
        providerIds: const <String>['line'],
      );
      when(
        () => mockRepo.signInWithLine(),
      ).thenAnswer((_) async => Result<User>.success(user));

      final container = makeContainer();
      final notifier = container.read(lineSignInProvider.notifier);

      await notifier.signInWithLine();

      final state = container.read(lineSignInProvider);
      expect(state, isA<AsyncData<void>>());
      expect(state.hasError, isFalse);
    });

    test('Test 3 (cancel silent): repository null → AsyncData(null)',
        () async {
      when(() => mockRepo.signInWithLine()).thenAnswer((_) async => null);

      final container = makeContainer();
      final notifier = container.read(lineSignInProvider.notifier);

      await notifier.signInWithLine();

      final state = container.read(lineSignInProvider);
      expect(state, isA<AsyncData<void>>());
      expect(state.hasError, isFalse);
    });

    test('Test 4 (실패): repository Result.failure → AsyncError', () async {
      when(() => mockRepo.signInWithLine()).thenAnswer(
        (_) async => const Result<User>.failure(ServiceUnavailable()),
      );

      final container = makeContainer();
      final notifier = container.read(lineSignInProvider.notifier);

      await notifier.signInWithLine();

      final state = container.read(lineSignInProvider);
      expect(state, isA<AsyncError<void>>());
      expect(state.error, isA<ServiceUnavailable>());
    });

    test(
      'Test 5 (R7 sibling regression guard — Phase 13 D-42 carry-forward): '
      'build() 반환 후 state.isLoading == false (FutureOr<void> sync 정착)',
      () {
        // R7 contract (Phase 13 D-42 carry-forward): `FutureOr<void> build()`
        // 가 async work 없이 즉시 AsyncData<void>(null) 을 반환해야 한다.
        // 향후 contributor 가 build 본문에 await 또는 `return Future.value();`
        // 를 추가하면 build 가 Future 를 반환 → 초기 state 가 AsyncLoading
        // 으로 변경 → 본 테스트가 RED 로 전환되어 PR review 단계에서 차단된다.
        final container = makeContainer();
        final state = container.read(lineSignInProvider);
        expect(state, const AsyncData<void>(null));
        expect(state.isLoading, isFalse);
      },
    );

    test(
      'Test 6 (dispose race guard): dispose 후 signInWithLine 완료되어도 '
      'state 업데이트 silent (ref.mounted 가드)',
      () async {
        final completer = Completer<Result<User>?>();
        when(
          () => mockRepo.signInWithLine(),
        ).thenAnswer((_) => completer.future);

        final container = makeContainer();
        final notifier = container.read(lineSignInProvider.notifier);

        final future = notifier.signInWithLine();

        // container dispose 로 ref.mounted=false 유도.
        container.dispose();

        final user = User(
          uid: 'line-uid-002',
          email: 'late@line.me',
          emailVerified: true,
          createdAt: DateTime.utc(2026, 5, 19),
        );
        completer.complete(Result<User>.success(user));

        // 예외 없이 완료되어야 한다 (ref.mounted 가드가 state 업데이트 차단).
        await future;
      },
    );
  });
}
