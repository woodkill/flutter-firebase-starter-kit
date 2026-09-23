// Phase 13 — see ROADMAP.md (T-13-NAVER-NOTIFIER + R7 회귀 가드)

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/auth/presentation/naver_sign_in_notifier.dart';

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

  group('NaverSignInNotifier.signInWithNaver (T-13-NAVER-NOTIFIER)', () {
    test('T-13-NAVER-NOTIFIER-02: 성공 → AsyncData<void>(null)', () async {
      // Custom Token 흐름: emailVerified=true 자동 부여 (D-46/D-47).
      final user = User(
        uid: 'naver-uid-001',
        email: 'test@naver.com',
        emailVerified: true,
        createdAt: DateTime.utc(2026, 5, 5),
        providerIds: const <String>['naver'],
      );
      when(
        () => mockRepo.signInWithNaver(),
      ).thenAnswer((_) async => Result<User>.success(user));

      final container = makeContainer();
      final notifier = container.read(naverSignInProvider.notifier);

      await notifier.signInWithNaver();

      final state = container.read(naverSignInProvider);
      expect(state, isA<AsyncData<void>>());
      expect(state.hasError, isFalse);
    });

    test('T-13-NAVER-NOTIFIER-03: 실패 → AsyncError', () async {
      when(() => mockRepo.signInWithNaver()).thenAnswer(
        (_) async => const Result<User>.failure(ServiceUnavailable()),
      );

      final container = makeContainer();
      final notifier = container.read(naverSignInProvider.notifier);

      await notifier.signInWithNaver();

      final state = container.read(naverSignInProvider);
      expect(state, isA<AsyncError<void>>());
      expect(state.error, isA<ServiceUnavailable>());
    });

    test(
      'T-13-NAVER-NOTIFIER-04: cancel (null) → AsyncData<void>(null) (D-45)',
      () async {
        when(() => mockRepo.signInWithNaver()).thenAnswer((_) async => null);

        final container = makeContainer();
        final notifier = container.read(naverSignInProvider.notifier);

        await notifier.signInWithNaver();

        final state = container.read(naverSignInProvider);
        expect(state, isA<AsyncData<void>>());
        expect(state.hasError, isFalse);
      },
    );

    test('T-13-NAVER-NOTIFIER-05: dispose 후 signInWithNaver 완료 시 '
        'state 미갱신 (ref.mounted 가드)', () async {
      final completer = Completer<Result<User>?>();
      when(
        () => mockRepo.signInWithNaver(),
      ).thenAnswer((_) => completer.future);

      final container = makeContainer();
      final notifier = container.read(naverSignInProvider.notifier);

      final future = notifier.signInWithNaver();

      // container dispose 로 ref.mounted = false 유도.
      container.dispose();

      final user = User(
        uid: 'naver-uid-002',
        email: 'late@naver.com',
        emailVerified: true,
        createdAt: DateTime.utc(2026, 5, 5),
      );
      completer.complete(Result<User>.success(user));

      // 예외 없이 완료되어야 한다 (ref.mounted 가드가 state 업데이트를 차단).
      await future;
    });
  });

  group('NaverSignInNotifier.build '
      '(R7 회귀 가드 — D-42 재정의 / Phase 13 — see ROADMAP.md)', () {
    test('T-13-NAVER-NOTIFIER-R7-01: 초기 state == AsyncData<void>(null) — '
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
      final state = container.read(naverSignInProvider);
      expect(state, const AsyncData<void>(null));
      expect(state.hasError, isFalse);
      expect(state.isLoading, isFalse);
    });
  });
}
