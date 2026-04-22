import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/config/splash_config.dart';
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/splash/presentation/splash_initializer.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

User stubUser({String uid = 'anon-uid'}) {
  return User(
    uid: uid,
    email: '',
    emailVerified: false,
    displayName: null,
    photoUrl: null,
    createdAt: DateTime.utc(2026, 4, 14),
    providerIds: const <String>[],
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(StackTrace.empty);
  });

  setUp(() {
    // WARNING #13: 실대기 1ms 로 단축 (피드백 레이턴시 < 100ms).
    SplashConfig.overrideMinDuration = const Duration(milliseconds: 1);
  });

  tearDown(() {
    SplashConfig.overrideMinDuration = null;
  });

  group('SplashInitializer (Phase 10 D-24 / Issue #10 Plan 10-14 GC-03)', () {
    test(
      'Test 1: currentUser=null + onboardingFuture=true -> signInAnonymously '
      '호출 + 최소 대기',
      () async {
        final mockRepo = _MockAuthRepository();
        when(
          mockRepo.signInAnonymously,
        ).thenAnswer((_) async => Result.success(stubUser()));

        final initializer = SplashInitializer(
          authRepository: mockRepo,
          isFirebaseInitialized: true,
          currentUserIsNull: true,
          onboardingFuture: Future.value(true),
        );

        final result = await initializer.initialize();
        expect(result, isA<Success<void>>());
        verify(mockRepo.signInAnonymously).called(1);
      },
    );

    test('Test 2: currentUser != null -> signInAnonymously 호출 안 함', () async {
      final mockRepo = _MockAuthRepository();

      final initializer = SplashInitializer(
        authRepository: mockRepo,
        isFirebaseInitialized: true,
        currentUserIsNull: false, // 이미 로그인됨
        onboardingFuture: Future.value(true),
      );

      final result = await initializer.initialize();
      expect(result, isA<Success<void>>());
      verifyNever(mockRepo.signInAnonymously);
    });

    test(
      'Test 3: currentUser=null + onboardingFuture=false -> signInAnonymously '
      '호출 안 함 (Onboarding CTA 가 책임, D-14)',
      () async {
        final mockRepo = _MockAuthRepository();

        final initializer = SplashInitializer(
          authRepository: mockRepo,
          isFirebaseInitialized: true,
          currentUserIsNull: true,
          onboardingFuture: Future.value(false),
        );

        final result = await initializer.initialize();
        expect(result, isA<Success<void>>());
        verifyNever(mockRepo.signInAnonymously);
      },
    );

    test('Test 4: isFirebaseInitialized=false -> signInAnonymously 호출 안 함 '
        '(Phase 1 D-13)', () async {
      final mockRepo = _MockAuthRepository();

      final initializer = SplashInitializer(
        authRepository: mockRepo,
        isFirebaseInitialized: false,
        currentUserIsNull: true,
        onboardingFuture: Future.value(true),
      );

      final result = await initializer.initialize();
      expect(result, isA<Success<void>>());
      verifyNever(mockRepo.signInAnonymously);
    });

    test('Test 5: signInAnonymously 실패 시 Result.failure 반환', () async {
      final mockRepo = _MockAuthRepository();
      when(
        mockRepo.signInAnonymously,
      ).thenAnswer((_) async => const Result.failure(NoInternetConnection()));

      final initializer = SplashInitializer(
        authRepository: mockRepo,
        isFirebaseInitialized: true,
        currentUserIsNull: true,
        onboardingFuture: Future.value(true),
      );

      final result = await initializer.initialize();
      expect(result, isA<Failure<void>>());
      expect((result as Failure<void>).exception, isA<NoInternetConnection>());
    });

    test('Test 6 (Issue #10 Plan 10-14 GC-03): onboardingFuture 가 minDuration '
        '보다 오래 걸려도 settle 후 signInAnonymously 가 호출된다 '
        '(race 구조적 제거 — 실측 prefs 로드 지연 336~571ms 경계 재현)', () async {
      final mockRepo = _MockAuthRepository();
      when(
        mockRepo.signInAnonymously,
      ).thenAnswer((_) async => Result.success(stubUser()));

      // minDuration 1ms << onboardingFuture 지연 700ms.
      // 이전 race 구조에서는 minDuration 만 대기하고 onboardingSeen=false
      // snapshot 으로 분기를 미발동했으나, Plan 10-14 는 onboardingFuture
      // 를 선행 await 하므로 signInAnonymously 가 정상 호출됨.
      final initializer = SplashInitializer(
        authRepository: mockRepo,
        isFirebaseInitialized: true,
        currentUserIsNull: true,
        onboardingFuture: Future<bool>.delayed(
          const Duration(milliseconds: 700),
          () => true,
        ),
      );

      final result = await initializer.initialize();
      expect(result, isA<Success<void>>());
      verify(mockRepo.signInAnonymously).called(1);
    });
  });
}
