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
          isSocialLinkInProgress: false,
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
        isSocialLinkInProgress: false,
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
          isSocialLinkInProgress: false,
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
        isSocialLinkInProgress: false,
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
        isSocialLinkInProgress: false,
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
        isSocialLinkInProgress: false,
      );

      final result = await initializer.initialize();
      expect(result, isA<Success<void>>());
      verify(mockRepo.signInAnonymously).called(1);
    });
  });

  /// Phase 9.1 D-02-A: SplashInitializer 의 자동 익명 sign-in 분기에 추가된
  /// `!isSocialLinkInProgress` 가드의 회귀 테스트.
  ///
  /// AuthRepository 의 social sign-in 메서드(`signInWith{Google,Apple,Facebook}`)
  /// 가 진행 중이면 splash 의 자동 익명 sign-in 이 정식 사용자 상태를 덮어쓰는
  /// race 를 차단해야 한다 (`09-UAT.md` Gap test 6).
  group('Phase 9.1 D-02-A: socialLinkInProgress 가드', () {
    test(
      'Test SLP-S1: isSocialLinkInProgress=true + 다른 조건 모두 sign-in 발동 path '
      '-> signInAnonymously 호출 안 함 (skip 분기) + Failure 가 아닌 정상 반환',
      () async {
        final mockRepo = _MockAuthRepository();
        // signInAnonymously 가 호출되면 stub 으로 응답하지만, 본 테스트는 호출
        // 자체가 발생하지 않음을 verifyNever 로 검증.
        when(
          mockRepo.signInAnonymously,
        ).thenAnswer((_) async => Result.success(stubUser()));

        final initializer = SplashInitializer(
          authRepository: mockRepo,
          isFirebaseInitialized: true,
          currentUserIsNull: true,
          onboardingFuture: Future.value(true),
          isSocialLinkInProgress: true, // 진행 중 — skip
        );

        final result = await initializer.initialize();

        // splash_initializer.dart 의 정상 skip path:
        //   - 분기 (5) [authFuture 할당] 이 isSocialLinkInProgress=true 로 인해
        //     skip → authFuture = null
        //   - await waitFuture 후 `if (authFuture != null)` 미진입
        //   - `return const Result.success(null);` — Result<void> 의 Success<void>
        //     인스턴스
        //
        // 1차 assertion: 정확한 매칭. Result<T=void> 시그니처 + Success<T>
        // 정의로 런타임 인스턴스는 Success<void> 임이 보장됨.
        expect(
          result,
          isA<Success<void>>(),
          reason:
              'initialize() 의 정상 skip 분기는 const Result.success(null) 를 '
              '반환하며, 시그니처상 Result<void> 이므로 Success<void>.',
        );
        // 2차 fallback assertion: 만약 generic erasure 또는 Result 정의 변경으로
        // Success<void> 매칭이 깨져도 적어도 Failure 가 아님은 보장됨.
        expect(
          result,
          isNot(isA<Failure<void>>()),
          reason:
              'skip 분기는 어떤 경우에도 Failure 를 반환하지 않는다 — '
              'authRepository.signInAnonymously 가 호출되지 않으므로 '
              'Failure 로 가는 유일한 path 가 차단됨.',
        );
        verifyNever(mockRepo.signInAnonymously);
      },
    );

    test(
      'Test SLP-S2: isSocialLinkInProgress=false 일 때 기존 분기 5 정상 발동 '
      '(회귀 가드 — Plan 09.1-03 가드의 negative path)',
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
          isSocialLinkInProgress: false, // 진행 중 아님 — 정상 sign-in
        );

        final result = await initializer.initialize();

        expect(result, isA<Success<void>>());
        verify(mockRepo.signInAnonymously).called(1);
      },
    );
  });
}
