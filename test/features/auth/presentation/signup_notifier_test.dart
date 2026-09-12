import 'dart:async';

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

  group('SignupNotifier.build '
      '(R7 회귀 가드 — D-42 재정의 / Phase 13 — see ROADMAP.md)', () {
    test('T-13-R7-SIGNUP-01: 초기 state == AsyncData<void>(null) — '
        'R7 회귀 가드 (await/Future.value 추가 시 RED)', () {
      // R7 contract: `FutureOr<void> build()` 가 async work 없이 즉시
      // AsyncData<void>(null) 을 반환해야 한다. 향후 contributor 가 build 본문에
      // await 또는 `return Future.value();` 를 추가하면 build 가 Future 를 반환
      // → 초기 state 가 AsyncLoading 으로 변경 → 본 테스트가 RED 로 전환되어
      // PR review 단계에서 차단된다.
      //
      // Note: Riverpod 3.x 의 build inference 규칙상 `void build()` 로 변경 시
      // generator 가 sync $Notifier<void> 가족으로 강등 — AsyncNotifier 가족
      // 보존을 위해 `FutureOr<void>` 시그니처 유지 (Phase 12.1 Plan 11 SUMMARY
      // Rule 4 참조).
      final container = makeContainer();
      final state = container.read(signupProvider);
      expect(state, const AsyncData<void>(null));
      expect(state.hasError, isFalse);
      expect(state.isLoading, isFalse);
    });
  });

  group('IN-09 — submit 재진입 가드', () {
    test('진행 중 재호출은 무시되어 signUpWithEmail 이 1회만 호출된다', () async {
      final gate = Completer<Result<User>>();
      addTearDown(() {
        if (!gate.isCompleted) {
          gate.complete(const Result<User>.failure(EmailAlreadyInUse()));
        }
      });
      when(
        () => mockRepo.signUpWithEmail(
          email: any(named: 'email'),
          password: any(named: 'password'),
          displayName: any(named: 'displayName'),
        ),
      ).thenAnswer((_) => gate.future);

      final container = makeContainer();
      container.listen(signupProvider, (_, _) {}, fireImmediately: true);
      final notifier = container.read(signupProvider.notifier);

      final first = notifier.submit(
        email: 'a@b.com',
        password: 'pw',
        displayName: 'A',
      );
      await Future<void>.delayed(Duration.zero);
      expect(container.read(signupProvider).isLoading, isTrue);

      await notifier.submit(email: 'a@b.com', password: 'pw', displayName: 'A');

      gate.complete(const Result<User>.failure(EmailAlreadyInUse()));
      await first;

      verify(
        () => mockRepo.signUpWithEmail(
          email: any(named: 'email'),
          password: any(named: 'password'),
          displayName: any(named: 'displayName'),
        ),
      ).called(1);
    });
  });
}
