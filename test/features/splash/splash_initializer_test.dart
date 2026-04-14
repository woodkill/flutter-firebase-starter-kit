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

  group('SplashInitializer (Phase 10 D-24)', () {
    test('Test 1: currentUser=null + onboardingSeen=true -> signInAnonymously '
        '호출 + 최소 대기', () async {
      final mockRepo = _MockAuthRepository();
      when(mockRepo.signInAnonymously)
          .thenAnswer((_) async => Result.success(stubUser()));

      final initializer = SplashInitializer(
        authRepository: mockRepo,
        isFirebaseInitialized: true,
        currentUserIsNull: true,
        onboardingSeen: true,
      );

      final result = await initializer.initialize();
      expect(result, isA<Success<void>>());
      verify(mockRepo.signInAnonymously).called(1);
    });

    test('Test 2: currentUser != null -> signInAnonymously 호출 안 함', () async {
      final mockRepo = _MockAuthRepository();

      final initializer = SplashInitializer(
        authRepository: mockRepo,
        isFirebaseInitialized: true,
        currentUserIsNull: false, // 이미 로그인됨
        onboardingSeen: true,
      );

      final result = await initializer.initialize();
      expect(result, isA<Success<void>>());
      verifyNever(mockRepo.signInAnonymously);
    });

    test(
      'Test 3: currentUser=null + onboardingSeen=false -> signInAnonymously 호출 안 함 '
      '(Onboarding CTA 가 책임, D-14)',
      () async {
        final mockRepo = _MockAuthRepository();

        final initializer = SplashInitializer(
          authRepository: mockRepo,
          isFirebaseInitialized: true,
          currentUserIsNull: true,
          onboardingSeen: false,
        );

        final result = await initializer.initialize();
        expect(result, isA<Success<void>>());
        verifyNever(mockRepo.signInAnonymously);
      },
    );

    test(
      'Test 4: isFirebaseInitialized=false -> signInAnonymously 호출 안 함 '
      '(Phase 1 D-13)',
      () async {
        final mockRepo = _MockAuthRepository();

        final initializer = SplashInitializer(
          authRepository: mockRepo,
          isFirebaseInitialized: false,
          currentUserIsNull: true,
          onboardingSeen: true,
        );

        final result = await initializer.initialize();
        expect(result, isA<Success<void>>());
        verifyNever(mockRepo.signInAnonymously);
      },
    );

    test('Test 5: signInAnonymously 실패 시 Result.failure 반환', () async {
      final mockRepo = _MockAuthRepository();
      when(mockRepo.signInAnonymously).thenAnswer(
        (_) async => const Result.failure(NoInternetConnection()),
      );

      final initializer = SplashInitializer(
        authRepository: mockRepo,
        isFirebaseInitialized: true,
        currentUserIsNull: true,
        onboardingSeen: true,
      );

      final result = await initializer.initialize();
      expect(result, isA<Failure<void>>());
      expect(
        (result as Failure<void>).exception,
        isA<NoInternetConnection>(),
      );
    });
  });
}
