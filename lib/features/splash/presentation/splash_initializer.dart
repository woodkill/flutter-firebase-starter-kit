import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/config/auth_retry_config.dart';
import '../../../core/config/splash_config.dart';
import '../../../core/crashlytics/crashlytics_service.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/error/result.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../auth/application/social_link_in_progress.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/anonymous_sign_in.dart';
import '../../auth/domain/user.dart';
import '../../onboarding/presentation/onboarding_notifier.dart';
import 'splash_error_code.dart';

part 'splash_initializer.g.dart';

/// 스플래시 초기화 시퀀스 (Phase 10 D-24, Issue #10 Plan 10-14, Phase 10.1).
///
/// 다음 분기로 동작한다:
/// 1. 최소 표시 시간 대기 ([SplashConfig.minDuration], 기본 2초 / 테스트 시
///    [SplashConfig.overrideMinDuration])
/// 2. Firebase 미초기화 시 [signInAnonymously] 호출 스킵 (Phase 1 D-13)
/// 3. `currentUser != null` (익명 또는 정식) -> 대기만, 로그인 호출 안 함
/// 4. `currentUser == null` + `onboardingFuture` resolve 후 false -> 대기만
///    (Onboarding CTA 가 약관 동의 + signInAnonymously 책임, D-14)
/// 5. `currentUser == null` + `onboardingFuture` resolve 후 true ->
///    [signInAnonymously] 호출. 실패 시 transient 분류 (Phase 10.1 D-01/D-02)
///    에 따라 graceful retry loop 진입 — [AuthRetryConfig.effectiveBackoffSteps]
///    1s/2s/4s exponential backoff 직렬 (D-03/D-04). retry 소진 또는 permanent
///    fail (UserDisabled / TooManyRequests / `operation-not-allowed` cause)
///    시점에 [Result.failure] 반환 — 호출자 (SplashScreen) UI 가 재시도/
///    오프라인 다이얼로그 표시 (D-27).
///
/// Issue #10 GC-01/GC-03 — `onboardingFuture` 를 선행 await 하여 prefs
/// 로드 완료 전에 onboardingSeen=false snapshot 으로 signInAnonymously
/// 호출이 스킵되는 race 를 구조적으로 제거한다.
///
/// **Phase 10.1 D-13:** SplashInitializer 자체는 State 가 아니므로 mounted
/// 가드를 보유하지 않는다. 호출자 SplashScreen `_runInit` 의 `if (!mounted)
/// return;` 이 retry loop 완료 후 결과를 흡수한다. retry 백그라운드 진행은
/// 자원 영향 미미 (Risk R4 accept).
///
/// **Phase 10.1 D-14:** retry 소진 또는 permanent fail 시점에 1회만
/// [CrashlyticsService.setCustomKey] + [recordError] (`fatal: false`) 호출.
/// attempt 별 emit 안 함 — Crashlytics dashboard issue grouping 활성 +
/// 관측 노이즈 회피 (T-10.1-04 mitigation).
class SplashInitializer {
  /// 의존성 주입 생성자. Firebase 상태 및 onboarding 시청 Future 를 받는다.
  const SplashInitializer({
    required this.authRepository,
    required this.isFirebaseInitialized,
    required this.currentUserIsNull,
    required this.onboardingFuture,
    required this.isSocialLinkInProgress,
    this.crashlyticsService,
  });

  /// 익명 로그인 호출 위임 대상 (10-REVIEW WR-12).
  ///
  /// 타입이 [AnonymousSignIn] 인 이유는 splash 가 실제로 쓰는 표면이
  /// `signInAnonymously` 1개뿐이기 때문이다. `AuthRepository` 전체를 받으면
  /// Firebase 미초기화 경로의 no-op 구현이 `noSuchMethod` 로 전 메서드를
  /// 가로채야 했고, 그 순간 컴파일러가 인터페이스 누락을 검출하지 못했다.
  final AnonymousSignIn authRepository;

  /// Firebase 초기화 성공 여부.
  final bool isFirebaseInitialized;

  /// 현재 [AuthRepository] 의 `currentUser` 가 null 인지 여부.
  final bool currentUserIsNull;

  /// SharedPreferences 로드 완료 시점에 `onboarding.seen_version >=
  /// [currentVersion]` 여부가 settle 되는 Future (Issue #10 Plan 10-14
  /// — GC-01/GC-03 race 제거).
  ///
  /// [initialize] 의 첫 단계에서 await 하여 prefs 로드 완료 후에만
  /// `signInAnonymously` 분기 평가가 이루어지도록 보장한다.
  final Future<bool> onboardingFuture;

  /// 소셜 IdP linking 진행 여부 (Phase 9.1 D-02-A).
  ///
  /// `true` 인 경우 [initialize] 의 자동 [signInAnonymously] 호출을 스킵한다.
  /// AuthRepository 의 social sign-in 메서드(`signInWith{Google,Apple,Facebook}`)
  /// 가 try-finally 로 [SocialLinkInProgress.begin]/end 를 호출하여 본 신호를
  /// 활성화 — `_safeDelete(anonymous)` 직후 `currentUser=null` 윈도우 동안
  /// splash 의 자동 익명 sign-in 이 정식 사용자 상태를 덮어쓰는 race 를 차단한다
  /// (`09-UAT.md` Gap test 6).
  final bool isSocialLinkInProgress;

  /// Crashlytics observability wrapper (Phase 10.1 D-14, AUTH-11).
  ///
  /// `null` 일 경우 emit 미수행 — 기존 test 호환 (Phase 10 단순 test 들이
  /// crashlyticsService 인자 미주입). dev flavor 빌드에서는
  /// [CrashlyticsService.isEnabled] = false 로 no-op (D-28 wrapper 정책,
  /// T-10.1-05 accept).
  final CrashlyticsService? crashlyticsService;

  /// 스플래시 초기화 시퀀스를 실행한다.
  ///
  /// Issue #10 GC-03: onboardingFuture 를 최소 대기와 병렬 진행하되,
  /// signInAnonymously 호출 여부 판단 전에 먼저 settle 대기한다.
  /// 측정된 prefs 로드 지연 (336~571ms) 이 [SplashConfig.minDuration]
  /// (기본 2s) 안에 수렴하므로 사용자 관찰 지연은 없다.
  ///
  /// **Phase 9.1 D-02-A:** [isSocialLinkInProgress] 가 `true` 인 경우 분기 5번을
  /// 스킵한다. AuthRepository 의 social sign-in 메서드가 진행 중이면 splash 의
  /// 자동 익명 sign-in 이 정식 사용자 상태를 덮어쓰는 race 를 차단한다
  /// (`09-UAT.md` Gap test 6).
  ///
  /// **Phase 10.1 D-04 (retry sequence):**
  /// 1. attempt 1 = minDuration 병렬 (기존 보존) — `await waitFuture` 후
  ///    `await authFuture` 로 첫 결과 확인.
  /// 2. attempt 1 fail + transient (`_isTransient` true) → `for (delay in
  ///    effectiveBackoffSteps) { await delay; retry; }` 직렬 (1s/2s/4s).
  /// 3. attempt 1 fail + permanent → 즉시 [_finalize] (retry 안 함).
  /// 4. retry 소진 또는 permanent → [_finalize] 가 Crashlytics emit 1회 +
  ///    [Result.failure] 반환.
  Future<Result<void>> initialize() async {
    final waitFuture = Future<void>.delayed(SplashConfig.minDuration);
    final onboardingSeen = await onboardingFuture;
    // Phase 9.1 IN-01: signInAnonymously 의 정확한 반환 타입 (`Result<User>`) 으로
    // 명시화 — 미래에 `result.data` 등 generic-bound API 추가 시 타입 안전성 확보.
    Future<Result<User>>? authFuture;
    if (isFirebaseInitialized &&
        currentUserIsNull &&
        onboardingSeen &&
        !isSocialLinkInProgress) {
      authFuture = authRepository.signInAnonymously();
    }
    await waitFuture;
    if (authFuture == null) {
      return const Result.success(null);
    }
    final firstResult = await authFuture;
    if (firstResult is! Failure<User>) {
      return const Result.success(null);
    }
    // Phase 10.1 D-04 — 첫 시도 fail. transient 면 retry, permanent 즉시 fail.
    if (!_isTransient(firstResult.exception)) {
      return _finalize(firstResult.exception);
    }
    // Phase 10.1 D-03 — exponential backoff 직렬 retry loop.
    var lastException = firstResult.exception;
    for (final delay in AuthRetryConfig.effectiveBackoffSteps) {
      await Future<void>.delayed(delay);
      final retryResult = await authRepository.signInAnonymously();
      if (retryResult is! Failure<User>) {
        return const Result.success(null);
      }
      // retry 중 permanent 오류 발견 시 즉시 종료 (정상 분류 흐름).
      if (!_isTransient(retryResult.exception)) {
        return _finalize(retryResult.exception);
      }
      lastException = retryResult.exception;
    }
    // retry 소진 — 마지막 transient fail 을 final 결과로 emit (D-14).
    return _finalize(lastException);
  }

  /// transient (재시도 가능) 분류 여부 (Phase 10.1 D-02, T-10.1-01).
  ///
  /// `NoInternetConnection` 은 항상 transient. `ServiceUnavailable` 은
  /// 기본 transient 이나, `cause` 가 [fb.FirebaseAuthException] 이고 code 가
  /// `'operation-not-allowed'` 인 경우 영구 분류 (Firebase 콘솔 익명 사인인
  /// 비활성화 — 재시도 무의미). 나머지 sealed case (UserDisabled /
  /// TooManyRequests / 기타) 는 permanent 로 간주.
  static bool _isTransient(AppException e) {
    if (e is NoInternetConnection) {
      return true;
    }
    if (e is ServiceUnavailable) {
      final cause = e.cause;
      if (cause is fb.FirebaseAuthException &&
          cause.code == 'operation-not-allowed') {
        return false;
      }
      return true;
    }
    return false;
  }

  /// 최종 실패 처리 (Phase 10.1 D-14, T-10.1-04 mitigation).
  ///
  /// Crashlytics setCustomKey + recordError(fatal: false) 를 1회만 호출하고
  /// [Result.failure] 반환. attempt 별 emit 안 함 — issue grouping 활성 + 관측
  /// 노이즈 회피. crashlyticsService null 또는 isEnabled=false 시 no-op.
  ///
  /// **IN-01:** `cause.stackTrace` 가 null 인 경우 (throw 되지 않은 [Error])
  /// `StackTrace.current` 로 폴백한다 — 스택 없는 리포트를 만들지 않는다.
  ///
  /// **WR-01:** `StackTrace.current` 는 `_finalize` 의 호출 지점 스택일 뿐
  /// 실제 `signInAnonymously` 실패 위치를 가리키지 않는다. cause 가 [Error]
  /// 의 인스턴스이면 그 자체의 `stackTrace` 를 사용해 Crashlytics dashboard
  /// 의 root-cause 드릴-다운을 보존한다. cause 가 [Error] 가 아닌 경우
  /// (예: [fb.FirebaseAuthException] 은 [Exception] 계열) Dart 가 stack 을
  /// 자동 attach 하지 않으므로 fallback 으로 `StackTrace.current` 를 사용한다.
  ///
  /// **WR-03:** 코드 추출은 공통 [extractSplashErrorCode] 사용 — SplashScreen
  /// 의 fingerprint 표시와 동일 값 보장 (drift 방지).
  Future<Result<void>> _finalize(AppException exception) async {
    final crashlytics = crashlyticsService;
    if (crashlytics != null) {
      final code = extractSplashErrorCode(exception);
      final cause = exception.cause;
      // IN-01: `Error.stackTrace` 는 **아직 throw 되지 않은** Error 에 대해
      // null 이다. 그대로 넘기면 recordError(stack: null) 로 스택 없는
      // 리포트가 되어 WR-01 의 원래 의도(root-cause 드릴-다운 보존)와
      // 정반대가 된다.
      final stack = cause is Error
          ? (cause.stackTrace ?? StackTrace.current)
          : StackTrace.current;
      await crashlytics.setCustomKey(
        'splash_auto_signin_retry_exhausted',
        code,
      );
      await crashlytics.recordError(
        exception,
        stack,
        reason: 'splash_auto_signin_retry_exhausted',
        fatal: false,
      );
    }
    return Result.failure(exception);
  }
}

/// Firebase 미초기화 상태에서 [splashInitializerProvider] 가 동작할 때
/// 호출되지 않는 no-op 인스턴스. `isFirebaseInitialized=false` 분기에서
/// [SplashInitializer.initialize] 는 `signInAnonymously` 호출을 스킵하므로
/// 본 인스턴스의 메서드는 실제로 실행되지 않는다.
///
/// **10-REVIEW WR-12:** 이전에는 `implements AuthRepository` +
/// `dynamic noSuchMethod` 로 전 메서드를 가로챘다. 그 구현은 `dynamic` 금지
/// 규칙 위반이면서, 후속 phase 가 미초기화 경로에서 새 메서드를 호출해도
/// 컴파일 타임에 잡히지 않게 만들었다. 계약을 [AnonymousSignIn] 1 메서드로
/// 좁히면 누락이 곧 컴파일 에러다.
class _NoopAnonymousSignIn implements AnonymousSignIn {
  const _NoopAnonymousSignIn();

  @override
  Future<Result<User>> signInAnonymously() => throw UnimplementedError(
    'Firebase 미초기화 상태에서 signInAnonymously 가 호출되어서는 안 된다.',
  );
}

/// [SplashInitializer] Provider.
///
/// `currentUser`, `onboardingFuture`, `isFirebaseInitialized` 를 watch 하여
/// 매 호출 시 최신 상태로 [SplashInitializer] 를 생성한다.
///
/// **Phase 1 D-13 가드:** Firebase 미초기화 시 [firebaseAuthProvider] /
/// [authRepositoryProvider] 접근이 throw 할 수 있으므로 본 Provider 에서도
/// 조건부 watch 로 감싸 스플래시가 Firebase 없이도 정상 렌더되도록 한다.
///
/// **Issue #10 Plan 10-14 GC-02:** `onboardingProvider` 가 AsyncNotifier 로
/// 전환되어 `.future` 게터로 `Future<bool>` 를 얻는다. `ref.watch(.future)` 는
/// AsyncNotifier 가 1회 build 후 settle 되면 resolve 된 Future 를 캐시하므로
/// 재빌드가 불필요하며, keepAlive 덕분에 container 수명 동안 1회만 계산된다.
///
/// **Phase 10.1 D-14:** Firebase 초기화 상태일 때만 [crashlyticsServiceProvider]
/// 를 watch 하여 SplashInitializer 에 주입. 미초기화 시 null 주입 — retry
/// path 자체가 trigger 안 됨 (authFuture 미생성).
@riverpod
SplashInitializer splashInitializer(Ref ref) {
  final isInitialized = ref.watch(isFirebaseInitializedProvider);
  final currentUser = isInitialized
      ? ref.watch(firebaseAuthProvider).currentUser
      : null;
  final onboardingFuture = ref.watch(onboardingProvider.future);
  final authRepository = isInitialized
      ? ref.watch(authRepositoryProvider)
      : const _NoopAnonymousSignIn();
  // Phase 9.1 D-02-A: socialLinkInProgress 가 true 면 자동 익명 sign-in 스킵.
  // Firebase 미초기화 시에는 의미 없으므로 false 로 처리 (signInAnonymously 자체가
  // isInitialized=false 분기에서 이미 스킵됨).
  final isSocialLinkInProgress = isInitialized
      ? ref.watch(socialLinkInProgressProvider)
      : false;
  // Phase 10.1 D-14: Crashlytics 주입 (Firebase 초기화 시에만).
  final crashlytics = isInitialized
      ? ref.watch(crashlyticsServiceProvider)
      : null;
  return SplashInitializer(
    authRepository: authRepository,
    isFirebaseInitialized: isInitialized,
    currentUserIsNull: currentUser == null,
    onboardingFuture: onboardingFuture,
    isSocialLinkInProgress: isSocialLinkInProgress,
    crashlyticsService: crashlytics,
  );
}
