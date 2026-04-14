import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/config/splash_config.dart';
import '../../../core/error/result.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../auth/data/auth_repository.dart';
import '../../onboarding/presentation/onboarding_notifier.dart';

part 'splash_initializer.g.dart';

/// 스플래시 초기화 시퀀스 (Phase 10 D-24).
///
/// 다음 분기로 동작한다:
/// 1. 최소 표시 시간 대기 ([SplashConfig.minDuration], 기본 2초 / 테스트 시
///    [SplashConfig.overrideMinDuration])
/// 2. Firebase 미초기화 시 [signInAnonymously] 호출 스킵 (Phase 1 D-13)
/// 3. `currentUser != null` (익명 또는 정식) -> 대기만, 로그인 호출 안 함
/// 4. `currentUser == null` + `onboardingSeen=false` -> 대기만 (Onboarding
///    CTA 가 약관 동의 + signInAnonymously 책임, D-14)
/// 5. `currentUser == null` + `onboardingSeen=true` -> [signInAnonymously]
///    호출. 실패 시 [Result.failure] 반환 — 호출자(SplashScreen) UI 가
///    재시도/오프라인 다이얼로그 표시 (D-27).
class SplashInitializer {
  /// 의존성 주입 생성자. Firebase 상태 및 onboarding 시청 여부를 받는다.
  const SplashInitializer({
    required this.authRepository,
    required this.isFirebaseInitialized,
    required this.currentUserIsNull,
    required this.onboardingSeen,
  });

  /// 익명 로그인 호출 위임 대상.
  final AuthRepository authRepository;

  /// Firebase 초기화 성공 여부.
  final bool isFirebaseInitialized;

  /// 현재 [AuthRepository] 의 `currentUser` 가 null 인지 여부.
  final bool currentUserIsNull;

  /// SharedPreferences `onboarding.seen_version` 가 [currentVersion] 이상인지.
  final bool onboardingSeen;

  /// 스플래시 초기화 시퀀스를 실행한다.
  ///
  /// `Future.wait` 패턴으로 최소 대기 시간과 익명 로그인을 병렬로 처리한다.
  Future<Result<void>> initialize() async {
    final waitFuture = Future<void>.delayed(SplashConfig.minDuration);
    Future<Result<dynamic>>? authFuture;
    if (isFirebaseInitialized && currentUserIsNull && onboardingSeen) {
      authFuture = authRepository.signInAnonymously();
    }
    await waitFuture;
    if (authFuture != null) {
      final result = await authFuture;
      if (result is Failure) {
        return Result.failure(result.exception);
      }
    }
    return const Result.success(null);
  }
}

/// Firebase 미초기화 상태에서 [splashInitializerProvider] 가 동작할 때
/// 호출되지 않는 no-op 인스턴스. `isFirebaseInitialized=false` 분기에서
/// [SplashInitializer.initialize] 는 `signInAnonymously` 호출을 스킵하므로
/// 본 인스턴스의 메서드는 실제로 실행되지 않는다.
class _NoopAuthRepository implements AuthRepository {
  const _NoopAuthRepository();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError(
      '_NoopAuthRepository.${invocation.memberName} called — Firebase '
      '미초기화 상태에서 호출되어서는 안 된다.',
    );
  }
}

/// [SplashInitializer] Provider.
///
/// `currentUser`, `onboardingSeen`, `isFirebaseInitialized` 를 watch 하여
/// 매 호출 시 최신 상태로 [SplashInitializer] 를 생성한다.
///
/// **Phase 1 D-13 가드:** Firebase 미초기화 시 [firebaseAuthProvider] /
/// [authRepositoryProvider] 접근이 throw 할 수 있으므로 본 Provider 에서도
/// 조건부 watch 로 감싸 스플래시가 Firebase 없이도 정상 렌더되도록 한다.
@riverpod
SplashInitializer splashInitializer(Ref ref) {
  final isInitialized = ref.watch(isFirebaseInitializedProvider);
  final currentUser =
      isInitialized ? ref.watch(firebaseAuthProvider).currentUser : null;
  final onboardingSeen = ref.watch(onboardingProvider);
  final authRepository = isInitialized
      ? ref.watch(authRepositoryProvider)
      : const _NoopAuthRepository();
  return SplashInitializer(
    authRepository: authRepository,
    isFirebaseInitialized: isInitialized,
    currentUserIsNull: currentUser == null,
    onboardingSeen: onboardingSeen,
  );
}
