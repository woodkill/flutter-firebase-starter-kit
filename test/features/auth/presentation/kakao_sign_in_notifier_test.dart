import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/auth/presentation/kakao_sign_in_notifier.dart';

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

  group('KakaoSignInNotifier.signInWithKakao', () {
    test('성공 시 AsyncData(null) 상태로 전환된다', () async {
      // Custom Token 흐름: emailVerified=true 자동 부여 (D-27 docstring).
      final user = User(
        uid: 'kakao-uid-001',
        email: 'test@kakao.com',
        emailVerified: true,
        createdAt: DateTime.utc(2026, 5, 3),
        providerIds: const <String>['kakao'],
      );
      when(
        () => mockRepo.signInWithKakao(),
      ).thenAnswer((_) async => Result<User>.success(user));

      final container = makeContainer();
      final notifier = container.read(kakaoSignInProvider.notifier);

      await notifier.signInWithKakao();

      final state = container.read(kakaoSignInProvider);
      expect(state, isA<AsyncData<void>>());
      expect(state.hasError, isFalse);
    });

    test('취소(null 반환) 시 AsyncData 상태로 유지된다 (D-05)', () async {
      when(() => mockRepo.signInWithKakao()).thenAnswer((_) async => null);

      final container = makeContainer();
      final notifier = container.read(kakaoSignInProvider.notifier);

      await notifier.signInWithKakao();

      final state = container.read(kakaoSignInProvider);
      expect(state, isA<AsyncData<void>>());
      expect(state.hasError, isFalse);
    });

    test('Failure 반환 시 AsyncError 상태로 전환된다', () async {
      when(() => mockRepo.signInWithKakao()).thenAnswer(
        (_) async => const Result<User>.failure(ServiceUnavailable()),
      );

      final container = makeContainer();
      final notifier = container.read(kakaoSignInProvider.notifier);

      await notifier.signInWithKakao();

      final state = container.read(kakaoSignInProvider);
      expect(state, isA<AsyncError<void>>());
      expect(state.error, isA<ServiceUnavailable>());
    });

    test('dispose 후 signInWithKakao이 완료되어도 '
        'state 업데이트가 스킵된다 (ref.mounted 가드)', () async {
      final completer = Completer<Result<User>?>();
      when(
        () => mockRepo.signInWithKakao(),
      ).thenAnswer((_) => completer.future);

      final container = makeContainer();
      final notifier = container.read(kakaoSignInProvider.notifier);

      final future = notifier.signInWithKakao();

      // container dispose로 ref.mounted = false 유도.
      container.dispose();

      final user = User(
        uid: 'kakao-uid-002',
        email: 'late@kakao.com',
        emailVerified: true,
        createdAt: DateTime.utc(2026, 5, 3),
      );
      completer.complete(Result<User>.success(user));

      // 예외 없이 완료되어야 한다 (ref.mounted 가드가 state 업데이트를 차단).
      await future;
    });
  });

  group('KakaoSignInNotifier.build (R7 회귀 가드 — D-42 재정의)', () {
    test(
      '초기 state == AsyncData<void>(null) — R7 회귀 가드 (await/Future.value 추가 시 RED)',
      () {
        // R7 contract: `FutureOr<void> build()` 가 async work 없이 즉시
        // AsyncData<void>(null) 을 반환해야 한다. 향후 contributor 가 build 본문에
        // await 또는 `return Future.value();` 를 추가하면 build 가 Future 를 반환
        // → 초기 state 가 AsyncLoading 으로 변경 → 본 테스트가 RED 로 전환되어
        // PR review 단계에서 차단된다.
        //
        // Note: Riverpod 3.x (riverpod_generator 4.0.3) 의 build inference 규칙상
        // `void build()` 로 변경 시 generator 가 sync $Notifier<void> 가족으로
        // 강등시켜 AsyncNotifier API 자체가 깨진다 (Plan 12.1-11 SUMMARY Rule 4
        // 참조). 따라서 R7 의 "컴파일러 enforced 강화" motivation 은 본질적
        // 불가능 — 회귀 가드 테스트 + docstring 으로 enforce 하는 것이 D-42 의
        // 재정의된 motivation. AsyncNotifier 가족 (`FutureOr<void> build()`) 은
        // sibling Google/Apple/Facebook/login/signup/forgot_password 와 정합.
        final container = makeContainer();
        final state = container.read(kakaoSignInProvider);
        expect(state, const AsyncData<void>(null));
        expect(state.hasError, isFalse);
        expect(state.isLoading, isFalse);
      },
    );
  });
}
