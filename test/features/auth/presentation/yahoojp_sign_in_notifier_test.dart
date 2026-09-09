// Phase 15 — see ROADMAP.md (YahoojpSignInNotifier unit tests)
//
// Pattern: line_sign_in_notifier_test.dart 의 ProviderContainer + Mock
// AuthRepository 패턴 mirror.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/auth/presentation/yahoojp_sign_in_notifier.dart';

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

  group('YahoojpSignInNotifier.signInWithYahoojp', () {
    test('Test 1 (build initial): 초기 state = AsyncData<void>(null)', () {
      final container = makeContainer();
      final state = container.read(yahoojpSignInProvider);
      expect(state, isA<AsyncData<void>>());
      expect(state.hasError, isFalse);
      expect(state.isLoading, isFalse);
    });

    test('Test 2 (성공): repository Result.success → AsyncData(null)', () async {
      // Custom Token 흐름: emailVerified=true 자동 부여 (D-YJP-09 docstring).
      // Yahoo!JP 는 scope openid+profile 만 → email 빈 문자열 (LINE D-LINE-21
      // 와 동일 mechanism).
      final user = User(
        uid: 'yj-uid-001',
        email: '',
        emailVerified: true,
        createdAt: DateTime.utc(2026, 5, 22),
        providerIds: const <String>['yahoojp'],
      );
      when(
        () => mockRepo.signInWithYahoojp(),
      ).thenAnswer((_) async => Result<User>.success(user));

      final container = makeContainer();
      final notifier = container.read(yahoojpSignInProvider.notifier);

      await notifier.signInWithYahoojp();

      final state = container.read(yahoojpSignInProvider);
      expect(state, isA<AsyncData<void>>());
      expect(state.hasError, isFalse);
    });

    test('Test 3 (cancel silent): repository null → AsyncData(null)', () async {
      when(() => mockRepo.signInWithYahoojp()).thenAnswer((_) async => null);

      final container = makeContainer();
      final notifier = container.read(yahoojpSignInProvider.notifier);

      await notifier.signInWithYahoojp();

      final state = container.read(yahoojpSignInProvider);
      expect(state, isA<AsyncData<void>>());
      expect(state.hasError, isFalse);
    });

    test('Test 4 (실패): repository Result.failure → AsyncError', () async {
      when(() => mockRepo.signInWithYahoojp()).thenAnswer(
        (_) async => const Result<User>.failure(ServiceUnavailable()),
      );

      final container = makeContainer();
      final notifier = container.read(yahoojpSignInProvider.notifier);

      await notifier.signInWithYahoojp();

      final state = container.read(yahoojpSignInProvider);
      expect(state, isA<AsyncError<void>>());
      expect(state.error, isA<ServiceUnavailable>());
    });

    test('Test 5 (R7 sibling regression guard — T-15-YJP-NOTIFIER-R7-01): '
        'build() 반환 후 state.isLoading == false (FutureOr<void> sync 정착)', () {
      // R7 contract (Phase 13 D-42 carry-forward, Phase 14 D-LINE 동일
      // invariant): `FutureOr<void> build()` 가 async work 없이 즉시
      // AsyncData<void>(null) 을 반환해야 한다. 향후 contributor 가 build
      // 본문에 await 또는 `return Future.value();` 를 추가하면 build 가
      // Future 를 반환 → 초기 state 가 AsyncLoading 으로 변경 → 본 테스트
      // 가 RED 로 전환되어 PR review 단계에서 차단된다.
      final container = makeContainer();
      final state = container.read(yahoojpSignInProvider);
      expect(state, const AsyncData<void>(null));
      expect(state.isLoading, isFalse);
    });

    test('Test 6 (dispose race guard): dispose 후 signInWithYahoojp 완료되어도 '
        'state 업데이트 silent (ref.mounted 가드)', () async {
      final completer = Completer<Result<User>?>();
      when(
        () => mockRepo.signInWithYahoojp(),
      ).thenAnswer((_) => completer.future);

      final container = makeContainer();
      final notifier = container.read(yahoojpSignInProvider.notifier);

      final future = notifier.signInWithYahoojp();

      // container dispose 로 ref.mounted=false 유도.
      container.dispose();

      final user = User(
        uid: 'yj-uid-002',
        email: '',
        emailVerified: true,
        createdAt: DateTime.utc(2026, 5, 22),
      );
      completer.complete(Result<User>.success(user));

      // 예외 없이 완료되어야 한다 (ref.mounted 가드가 state 업데이트 차단).
      await future;
    });
  });
}
