import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/config/auth_retry_config.dart';
import 'package:flutter_starter_kit/core/config/splash_config.dart';
import 'package:flutter_starter_kit/core/crashlytics/crashlytics_service.dart';
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/features/splash/presentation/splash_initializer.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockCrashlytics extends Mock implements CrashlyticsService {}

/// Crashlytics 호출 stub helper (Phase 10.1 D-14).
///
/// setCustomKey / recordError 모두 no-op 응답으로 stub. verify 시 콜 횟수
/// 카운팅 가능.
_MockCrashlytics _buildCrashlyticsMock() {
  final mock = _MockCrashlytics();
  when(() => mock.setCustomKey(any(), any<Object>())).thenAnswer((_) async {});
  when(
    () => mock.recordError(
      any<Object>(),
      any<StackTrace?>(),
      reason: any(named: 'reason'),
      fatal: any(named: 'fatal'),
    ),
  ).thenAnswer((_) async {});
  return mock;
}

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
    // Phase 10.1 D-16: backoff 실대기 9s → 3ms 단축 (1ms × 3).
    AuthRetryConfig.overrideBackoffSteps = const [
      Duration(milliseconds: 1),
      Duration(milliseconds: 1),
      Duration(milliseconds: 1),
    ];
  });

  tearDown(() {
    SplashConfig.overrideMinDuration = null;
    AuthRetryConfig.overrideBackoffSteps = null;
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

    test('Test 5: signInAnonymously 실패 시 Result.failure 반환 '
        '(Phase 10.1 — transient × 4 호출 후 retry 소진)', () async {
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
      // Phase 10.1 D-04: transient 는 retry 3회까지 시도 (총 4 호출).
      verify(mockRepo.signInAnonymously).called(4);
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
    test('Test SLP-S1: isSocialLinkInProgress=true + 다른 조건 모두 sign-in 발동 path '
        '-> signInAnonymously 호출 안 함 (skip 분기) + Failure 가 아닌 정상 반환', () async {
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
    });

    test('Test SLP-S2: isSocialLinkInProgress=false 일 때 기존 분기 5 정상 발동 '
        '(회귀 가드 — Plan 09.1-03 가드의 negative path)', () async {
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
    });
  });

  /// Phase 10.1 retry 매트릭스 — transient/permanent 분류 + Crashlytics emit.
  ///
  /// VALIDATION.md per-task map 의 unit 영역 (I1/I2 invariant + Risk R1 +
  /// AUTH-11 Crashlytics) 8 행을 7 신규 case 로 충족.
  group('Phase 10.1 D-04 retry 매트릭스 + Crashlytics emit', () {
    test('C1: NoInternetConnection × 3 retry 후 소진 → Failure + Crashlytics '
        'emit 1회 (OOS-02 cycle 1 회귀 차단)', () async {
      final mockRepo = _MockAuthRepository();
      when(
        mockRepo.signInAnonymously,
      ).thenAnswer((_) async => const Result.failure(NoInternetConnection()));
      final mockCrashlytics = _buildCrashlyticsMock();

      final initializer = SplashInitializer(
        authRepository: mockRepo,
        isFirebaseInitialized: true,
        currentUserIsNull: true,
        onboardingFuture: Future.value(true),
        isSocialLinkInProgress: false,
        crashlyticsService: mockCrashlytics,
      );

      final result = await initializer.initialize();
      expect(result, isA<Failure<void>>());
      expect((result as Failure<void>).exception, isA<NoInternetConnection>());
      // attempt 1 + retry 3 = 4 호출 (D-04).
      verify(mockRepo.signInAnonymously).called(4);
      // Crashlytics emit 1회 (D-14, T-10.1-04). cause null → WR-02 fallback
      // 으로 AppException 런타임 타입 'NoInternetConnection' 사용.
      verify(
        () => mockCrashlytics.setCustomKey(
          'splash_auto_signin_retry_exhausted',
          'NoInternetConnection',
        ),
      ).called(1);
      verify(
        () => mockCrashlytics.recordError(
          any<Object>(),
          any<StackTrace?>(),
          reason: any(named: 'reason'),
          fatal: false,
        ),
      ).called(1);
    });

    test('C2: ServiceUnavailable(cause=code="unknown") × 3 retry 소진 → '
        'Failure + Crashlytics emit (OOS-02 cycle 2 회귀 차단)', () async {
      final mockRepo = _MockAuthRepository();
      final cause = fb.FirebaseAuthException(
        code: 'unknown',
        message: 'I/O error during system call, Connection reset by peer',
      );
      when(mockRepo.signInAnonymously).thenAnswer(
        (_) async => Result.failure(ServiceUnavailable(cause: cause)),
      );
      final mockCrashlytics = _buildCrashlyticsMock();

      final initializer = SplashInitializer(
        authRepository: mockRepo,
        isFirebaseInitialized: true,
        currentUserIsNull: true,
        onboardingFuture: Future.value(true),
        isSocialLinkInProgress: false,
        crashlyticsService: mockCrashlytics,
      );

      final result = await initializer.initialize();
      expect(result, isA<Failure<void>>());
      expect((result as Failure<void>).exception, isA<ServiceUnavailable>());
      verify(mockRepo.signInAnonymously).called(4);
      // cause.code = 'unknown' 추출 검증 (D-10 PII-safe).
      verify(
        () => mockCrashlytics.setCustomKey(
          'splash_auto_signin_retry_exhausted',
          'unknown',
        ),
      ).called(1);
    });

    test('C3: NoInternetConnection × 1 + Success → Success (retry 1회) + '
        'Crashlytics 0회', () async {
      final mockRepo = _MockAuthRepository();
      var callCount = 0;
      when(mockRepo.signInAnonymously).thenAnswer((_) async {
        callCount += 1;
        if (callCount == 1) {
          return const Result.failure(NoInternetConnection());
        }
        return Result.success(stubUser());
      });
      final mockCrashlytics = _buildCrashlyticsMock();

      final initializer = SplashInitializer(
        authRepository: mockRepo,
        isFirebaseInitialized: true,
        currentUserIsNull: true,
        onboardingFuture: Future.value(true),
        isSocialLinkInProgress: false,
        crashlyticsService: mockCrashlytics,
      );

      final result = await initializer.initialize();
      expect(result, isA<Success<void>>());
      verify(mockRepo.signInAnonymously).called(2);
      // retry 성공 시 Crashlytics emit 안 함 (D-14).
      verifyNever(() => mockCrashlytics.setCustomKey(any(), any<Object>()));
      // IN-01: setCustomKey 와 recordError 양쪽이 함께 0 회 인지 검증
      // (둘 중 하나만 emit 되는 회귀 차단).
      verifyNever(
        () => mockCrashlytics.recordError(
          any<Object>(),
          any<StackTrace?>(),
          reason: any(named: 'reason'),
          fatal: any(named: 'fatal'),
        ),
      );
    });

    test('C4: NoInternetConnection × 2 + Success → Success (retry 2회) + '
        'Crashlytics 0회', () async {
      final mockRepo = _MockAuthRepository();
      var callCount = 0;
      when(mockRepo.signInAnonymously).thenAnswer((_) async {
        callCount += 1;
        if (callCount <= 2) {
          return const Result.failure(NoInternetConnection());
        }
        return Result.success(stubUser());
      });
      final mockCrashlytics = _buildCrashlyticsMock();

      final initializer = SplashInitializer(
        authRepository: mockRepo,
        isFirebaseInitialized: true,
        currentUserIsNull: true,
        onboardingFuture: Future.value(true),
        isSocialLinkInProgress: false,
        crashlyticsService: mockCrashlytics,
      );

      final result = await initializer.initialize();
      expect(result, isA<Success<void>>());
      verify(mockRepo.signInAnonymously).called(3);
      verifyNever(() => mockCrashlytics.setCustomKey(any(), any<Object>()));
      // IN-01: setCustomKey 와 recordError 양쪽이 함께 0 회 인지 검증.
      verifyNever(
        () => mockCrashlytics.recordError(
          any<Object>(),
          any<StackTrace?>(),
          reason: any(named: 'reason'),
          fatal: any(named: 'fatal'),
        ),
      );
    });

    test(
      'C5: UserDisabled × 1 → 즉시 Failure (retry 안 됨, I2 permanent)',
      () async {
        final mockRepo = _MockAuthRepository();
        when(
          mockRepo.signInAnonymously,
        ).thenAnswer((_) async => const Result.failure(UserDisabled()));
        final mockCrashlytics = _buildCrashlyticsMock();

        final initializer = SplashInitializer(
          authRepository: mockRepo,
          isFirebaseInitialized: true,
          currentUserIsNull: true,
          onboardingFuture: Future.value(true),
          isSocialLinkInProgress: false,
          crashlyticsService: mockCrashlytics,
        );

        final result = await initializer.initialize();
        expect(result, isA<Failure<void>>());
        expect((result as Failure<void>).exception, isA<UserDisabled>());
        // permanent — retry 안 함, 1회만 호출.
        verify(mockRepo.signInAnonymously).called(1);
        // WR-02: cause null → AppException 런타임 타입 'UserDisabled' fingerprint.
        verify(
          () => mockCrashlytics.setCustomKey(
            'splash_auto_signin_retry_exhausted',
            'UserDisabled',
          ),
        ).called(1);
        verify(
          () => mockCrashlytics.recordError(
            any<Object>(),
            any<StackTrace?>(),
            reason: any(named: 'reason'),
            fatal: false,
          ),
        ).called(1);
      },
    );

    test(
      'C6: TooManyRequests × 1 → 즉시 Failure (retry 안 됨, I2 permanent)',
      () async {
        final mockRepo = _MockAuthRepository();
        when(
          mockRepo.signInAnonymously,
        ).thenAnswer((_) async => const Result.failure(TooManyRequests()));
        final mockCrashlytics = _buildCrashlyticsMock();

        final initializer = SplashInitializer(
          authRepository: mockRepo,
          isFirebaseInitialized: true,
          currentUserIsNull: true,
          onboardingFuture: Future.value(true),
          isSocialLinkInProgress: false,
          crashlyticsService: mockCrashlytics,
        );

        final result = await initializer.initialize();
        expect(result, isA<Failure<void>>());
        expect((result as Failure<void>).exception, isA<TooManyRequests>());
        verify(mockRepo.signInAnonymously).called(1);
        // WR-02: cause null → AppException 런타임 타입 'TooManyRequests'.
        verify(
          () => mockCrashlytics.setCustomKey(
            'splash_auto_signin_retry_exhausted',
            'TooManyRequests',
          ),
        ).called(1);
      },
    );

    test('C7: ServiceUnavailable(cause=code="operation-not-allowed") × 1 → '
        '즉시 Failure (T-10.1-01 mitigation — cause 검사 검증)', () async {
      final mockRepo = _MockAuthRepository();
      final cause = fb.FirebaseAuthException(code: 'operation-not-allowed');
      when(mockRepo.signInAnonymously).thenAnswer(
        (_) async => Result.failure(ServiceUnavailable(cause: cause)),
      );
      final mockCrashlytics = _buildCrashlyticsMock();

      final initializer = SplashInitializer(
        authRepository: mockRepo,
        isFirebaseInitialized: true,
        currentUserIsNull: true,
        onboardingFuture: Future.value(true),
        isSocialLinkInProgress: false,
        crashlyticsService: mockCrashlytics,
      );

      final result = await initializer.initialize();
      expect(result, isA<Failure<void>>());
      expect((result as Failure<void>).exception, isA<ServiceUnavailable>());
      // operation-not-allowed 는 permanent → retry 안 함.
      verify(mockRepo.signInAnonymously).called(1);
      verify(
        () => mockCrashlytics.setCustomKey(
          'splash_auto_signin_retry_exhausted',
          'operation-not-allowed',
        ),
      ).called(1);
      verify(
        () => mockCrashlytics.recordError(
          any<Object>(),
          any<StackTrace?>(),
          reason: any(named: 'reason'),
          fatal: false,
        ),
      ).called(1);
    });
  });
}
