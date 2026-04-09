import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/router/auth_guard.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/presentation/verify_email_notifier.dart';
import 'package:flutter_starter_kit/features/auth/presentation/verify_email_state.dart';

// --- Mocks ---

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockUser extends Mock implements fb.User {}

class _MockAuthChangeNotifier extends Mock implements AuthChangeNotifier {}

void main() {
  late _MockAuthRepository mockRepo;
  late _MockFirebaseAuth mockAuth;
  late _MockUser mockUser;
  late _MockAuthChangeNotifier mockChangeNotifier;

  setUp(() {
    mockRepo = _MockAuthRepository();
    mockAuth = _MockFirebaseAuth();
    mockUser = _MockUser();
    mockChangeNotifier = _MockAuthChangeNotifier();

    // 기본 stub: reloadUser 성공, emailVerified false
    when(() => mockRepo.reloadUser())
        .thenAnswer((_) async => const Result.success(null));
    when(() => mockAuth.currentUser).thenReturn(mockUser);
    when(() => mockUser.emailVerified).thenReturn(false);
  });

  /// fakeAsync 환경에서 ProviderContainer를 생성한다.
  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(mockRepo),
        firebaseAuthProvider.overrideWithValue(mockAuth),
        authChangeProvider.overrideWithValue(mockChangeNotifier),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('VerifyEmailNotifier', () {
    test('Test 1: build() 시 초기 상태가 올바르다', () {
      fakeAsync((async) {
        final container = makeContainer();

        // build()를 트리거하여 notifier 초기화
        final state = container.read(verifyEmailProvider);

        // AsyncData여야 하고, 초기 상태값 검증
        expect(state, isA<AsyncData<VerifyEmailState>>());
        final value = state.requireValue;
        expect(value.isPolling, isTrue);
        expect(value.cooldownRemaining, 0);
        expect(value.isChecking, isFalse);
        expect(value.error, isNull);

        // Timer 정리를 위해 dispose 전에 남은 timer를 flush
        async.flushTimers();
      });
    });

    test('Test 2: 폴링이 시작되고 3초 후 reloadUser가 호출된다', () {
      fakeAsync((async) {
        final container = makeContainer();
        container.read(verifyEmailProvider);

        // 3초 경과 시 reloadUser 1회 호출
        async.elapse(const Duration(seconds: 3));
        verify(() => mockRepo.reloadUser()).called(1);

        // 6초 경과 시 총 2회
        async.elapse(const Duration(seconds: 3));
        verify(() => mockRepo.reloadUser()).called(1);

        async.flushTimers();
      });
    });

    test('Test 3: emailVerified==true 감지 시 폴링 중지 + redirect 트리거',
        () {
      fakeAsync((async) {
        final container = makeContainer();
        container.read(verifyEmailProvider);

        // 첫 번째 폴링에서 emailVerified=true 반환
        when(() => mockUser.emailVerified).thenReturn(true);

        async.elapse(const Duration(seconds: 3));

        // authChangeNotifier.notifyListeners() 호출로 redirect 재평가
        verify(() => mockChangeNotifier.notifyListeners()).called(greaterThan(0));

        // 추가 폴링이 없어야 한다 (timer가 cancel됨)
        reset(mockRepo);
        when(() => mockRepo.reloadUser())
            .thenAnswer((_) async => const Result.success(null));
        async.elapse(const Duration(seconds: 6));
        verifyNever(() => mockRepo.reloadUser());

        async.flushTimers();
      });
    });

    test('Test 4: 300초(5분) 후 폴링 자동 중지, isPolling이 false', () {
      fakeAsync((async) {
        final container = makeContainer();
        container.read(verifyEmailProvider);

        // 300초 경과
        async.elapse(const Duration(seconds: 300));

        final state = container.read(verifyEmailProvider);
        expect(state.requireValue.isPolling, isFalse);

        // 추가 폴링이 없어야 한다
        reset(mockRepo);
        when(() => mockRepo.reloadUser())
            .thenAnswer((_) async => const Result.success(null));
        async.elapse(const Duration(seconds: 6));
        verifyNever(() => mockRepo.reloadUser());

        async.flushTimers();
      });
    });

    test(
      'Test 5: resendVerification 성공 시 cooldownRemaining이 '
      '60으로 설정되고 1초마다 감소',
      () {
        fakeAsync((async) {
          when(() => mockRepo.sendEmailVerification())
              .thenAnswer((_) async => const Result.success(null));

          final container = makeContainer();
          container.read(verifyEmailProvider);

          // resendVerification 호출
          container
              .read(verifyEmailProvider.notifier)
              .resendVerification();
          async.elapse(Duration.zero); // Future 처리

          var state = container.read(verifyEmailProvider);
          expect(state.requireValue.cooldownRemaining, 60);
          expect(state.requireValue.error, isNull);

          // 10초 경과 후 50초 남아야 한다
          async.elapse(const Duration(seconds: 10));
          state = container.read(verifyEmailProvider);
          expect(state.requireValue.cooldownRemaining, 50);

          // 50초 더 경과 후 0이어야 한다
          async.elapse(const Duration(seconds: 50));
          state = container.read(verifyEmailProvider);
          expect(state.requireValue.cooldownRemaining, 0);

          async.flushTimers();
        });
      },
    );

    test('Test 6: resendVerification 실패 시 error에 AppException 설정', () {
      fakeAsync((async) {
        when(() => mockRepo.sendEmailVerification()).thenAnswer(
          (_) async => const Result.failure(TooManyRequests()),
        );

        final container = makeContainer();
        container.read(verifyEmailProvider);

        container
            .read(verifyEmailProvider.notifier)
            .resendVerification();
        async.elapse(Duration.zero);

        final state = container.read(verifyEmailProvider);
        expect(state.requireValue.error, isA<TooManyRequests>());
        // 실패 시 쿨다운 시작하지 않는다
        expect(state.requireValue.cooldownRemaining, 0);

        async.flushTimers();
      });
    });

    test(
      'Test 7: checkManually 호출 시 isChecking 전환 + '
      'emailVerified==true면 redirect 트리거',
      () {
        fakeAsync((async) {
          final container = makeContainer();
          container.read(verifyEmailProvider);

          // emailVerified=true로 설정
          when(() => mockUser.emailVerified).thenReturn(true);

          container
              .read(verifyEmailProvider.notifier)
              .checkManually();
          async.elapse(Duration.zero);

          // redirect 트리거 확인
          verify(() => mockChangeNotifier.notifyListeners())
              .called(greaterThan(0));

          async.flushTimers();
        });
      },
    );

    test(
      'Test 7b: checkManually 호출 시 emailVerified==false면 '
      'isChecking=false 복귀',
      () {
        fakeAsync((async) {
          final container = makeContainer();
          container.read(verifyEmailProvider);

          // emailVerified는 기본 false
          container
              .read(verifyEmailProvider.notifier)
              .checkManually();
          async.elapse(Duration.zero);

          final state = container.read(verifyEmailProvider);
          expect(state.requireValue.isChecking, isFalse);

          async.flushTimers();
        });
      },
    );

    test('Test 8: logout 호출 시 signOut + redirect 트리거', () {
      fakeAsync((async) {
        when(() => mockRepo.signOut()).thenAnswer((_) async {});

        final container = makeContainer();
        container.read(verifyEmailProvider);

        container.read(verifyEmailProvider.notifier).logout();
        async.elapse(Duration.zero);

        verify(() => mockRepo.signOut()).called(1);

        async.flushTimers();
      });
    });
  });
}
