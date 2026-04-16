import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/onboarding/presentation/onboarding_notifier.dart';
import '../../features/terms/presentation/terms_notifier.dart';
import '../analytics/analytics_service.dart';
import '../crashlytics/crashlytics_service.dart';
import '../error/result.dart';
import '../providers/firebase_providers.dart';
import 'app_routes.dart';

part 'auth_guard.g.dart';

/// 사용자 변경 스트림을 GoRouter [refreshListenable]용
/// [ChangeNotifier]로 래핑한다.
///
/// [FirebaseAuth.userChanges] 스트림이 이벤트를 emit할 때마다
/// [notifyListeners]를 호출하여 GoRouter가 redirect를 재평가하도록
/// 트리거한다. `authStateChanges()` 대신 `userChanges()`를 사용하여
/// credential linking(익명→정식 승격)에도 redirect가 재평가된다.
/// [GoRouterRefreshStream]이 go_router v5.0.0에서 제거되었으므로
/// 이 클래스가 동일한 역할을 수행한다.
class AuthChangeNotifier extends ChangeNotifier {
  /// [stream]의 이벤트를 수신하여 [notifyListeners]를 호출하는
  /// [ChangeNotifier]를 생성한다.
  AuthChangeNotifier(Stream<fb.User?> stream) {
    _subscription = stream.listen((user) {
      if (kDebugMode) {
        // WARNING #18: uid 원문 대신 hashCode 로 PII 완화.
        final uidHash = user?.uid.hashCode.toString() ?? 'null';
        debugPrint(
          'AuthChangeNotifier: userChanges emit '
          '(uidHash=$uidHash) -> notifyListeners',
        );
      }
      notifyListeners();
    });
  }

  /// userChanges 구독. nullable 로 선언하여 향후 [stream] 이
  /// lazy-initialized 되어 [Stream.listen] 자체가 throw 하더라도
  /// [dispose] 가 LateInitializationError 없이 안전하게 동작하도록 한다.
  /// (flutter.md "late 사용 최소화" 규칙)
  StreamSubscription<fb.User?>? _subscription;

  /// GoRouter redirect 재평가를 강제 트리거한다.
  ///
  /// Firebase SDK의 authStateChanges() 스트림이 reload() 후
  /// emailVerified 변경을 emit하지 않는 제한(FlutterFire Issue #8777)을
  /// 우회하기 위해, 외부에서 명시적으로 redirect 재평가를 요청할 때 사용한다.
  void triggerRedirect() {
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

/// [AuthChangeNotifier] 인스턴스를 제공한다.
///
/// Firebase 미초기화 시 빈 스트림으로 생성하여 이벤트 없는
/// ChangeNotifier를 반환한다.
@Riverpod(keepAlive: true)
AuthChangeNotifier authChangeNotifier(Ref ref) {
  final isInitialized = ref.watch(isFirebaseInitializedProvider);
  if (!isInitialized) {
    return AuthChangeNotifier(const Stream<fb.User?>.empty());
  }
  final auth = ref.watch(firebaseAuthProvider);
  final notifier = AuthChangeNotifier(auth.userChanges());
  ref.onDispose(notifier.dispose);
  return notifier;
}

/// 미인증 사용자가 접근 가능한 화이트리스트 경로 집합 (Phase 10 D-18 확장).
///
/// 본 집합에 포함된 경로는 [authRedirect]가 미인증 상태에서도
/// /onboarding 으로 강제 이동시키지 않는다. 신규 unauth 경로 추가 시
/// 명시적으로 본 Set 에 포함해야 하며, 그 외 모든 경로는 default-deny
/// 정책에 따라 차단된다 (T-06.03-01 대응).
///
/// [AppRoutes.verifyEmail]은 미포함: 인증된 사용자만 접근 가능하며,
/// 로그아웃 후에는 /onboarding 또는 /login 으로 redirect 되어야 한다.
const Set<String> _unauthRoutes = <String>{
  AppRoutes.login,
  AppRoutes.signup,
  AppRoutes.forgotPassword,
  AppRoutes.onboarding, // Phase 10 D-18 — 게스트 진입 경로
  AppRoutes.termsService, // Phase 10 — 공개 약관 경로
  AppRoutes.termsPrivacy,
};

/// 인증 상태에 따른 redirect 로직 (Phase 10 D-14 / D-18 / D-19 / BLOCKER #3
/// / BLOCKER #7 / WARNING #18).
///
/// 판단 우선순위:
/// 1. Firebase 미초기화: redirect 우회 (null 반환, Phase 1 D-13)
/// 2. 미인증 + onboarding 미시청 + 공개 경로 외: [AppRoutes.onboarding] 으로
///    redirect (D-14 상태 머신)
/// 3. 익명 사용자: 대부분 route 허용. 단 [AppRoutes.verifyEmail] 은 정식
///    사용자 전용이므로 [AppRoutes.home] 으로 redirect.
/// 4. 정식 인증 + emailVerified=false + /verify-email 외: [AppRoutes.verifyEmail]
/// 5. **BLOCKER #3 / BLOCKER #7 / D-14 / D-15 (1회 동의 invariant):**
///    정식 인증 + emailVerified + termsAccepted=null + 공개 경로 외:
///    [AppRoutes.onboarding] 으로 강제 리다이렉트. 이 분기가 이메일 직접
///    가입 경로(`/signup` -> 가입 -> Home) 사용자도 약관 미동의면
///    Home 바이패스를 차단한다.
/// 6. 정식 인증 + emailVerified + termsAccepted + (unauth 또는 verifyEmail
///    또는 onboarding): [AppRoutes.home]
/// 7. 그 외: null (Home 랜딩 허용 — AUTH-13 / Test 9, WARNING #19)
///
/// **인증 판정 소스:** [fb.FirebaseAuth.currentUser]를 직접 읽는다.
/// `authStateProvider`를 사용하지 않는 이유는, [AuthChangeNotifier]가
/// `userChanges()`에 먼저 구독하기 때문에 (subscription #1),
/// Riverpod StreamProvider의 구독 (#2)이 같은 이벤트를 처리하기 전에
/// `notifyListeners`가 GoRouter의 redirect 재평가를 트리거한다. 그
/// 시점에 `ref.read(authStateProvider).value`는 stale 값이다.
/// `currentUser`는 Firebase SDK가 auth state 변경 시 동기적으로
/// 업데이트하므로, 어떤 listener가 먼저 호출되더라도 일관되게 최신
/// 값을 반환한다. (T-06.07-01)
FutureOr<String?> authRedirect(Ref ref, GoRouterState state) {
  final isInitialized = ref.read(isFirebaseInitializedProvider);
  if (!isInitialized) return null; // (1)

  final currentUser = ref.read(firebaseAuthProvider).currentUser;
  final isAuthenticated = currentUser != null;
  final isAnonymous = currentUser?.isAnonymous ?? false;
  final matchedLocation = state.matchedLocation;
  final isOnUnauthRoute = _unauthRoutes.contains(matchedLocation);
  final onboardingSeen = ref.read(onboardingProvider);
  final termsAcceptance = ref.read(termsProvider);
  final termsAccepted = termsAcceptance != null;

  if (kDebugMode) {
    // WARNING #18: uid 원문 대신 hashCode 로 PII 완화.
    final uidHash = currentUser?.uid.hashCode.toString() ?? 'null';
    debugPrint(
      'authRedirect: matchedLocation=$matchedLocation, '
      'isAuthenticated=$isAuthenticated (uidHash=$uidHash, '
      'isAnonymous=$isAnonymous, '
      'emailVerified=${currentUser?.emailVerified}), '
      'onboardingSeen=$onboardingSeen, '
      'termsAccepted=$termsAccepted, '
      'isOnUnauthRoute=$isOnUnauthRoute',
    );
  }

  // (2) 미인증 + 온보딩 미시청 + 온보딩/약관/스플래시 외 경로 -> /onboarding.
  // splash 는 unauth 화이트리스트가 아니지만, 앱 시작 직후 splash 에서
  // initializer 가 작동하는 동안에는 redirect 를 발동시키지 않는다.
  if (!isAuthenticated &&
      !onboardingSeen &&
      matchedLocation != AppRoutes.onboarding &&
      matchedLocation != AppRoutes.termsService &&
      matchedLocation != AppRoutes.termsPrivacy &&
      matchedLocation != AppRoutes.splash) {
    return AppRoutes.onboarding;
  }

  // (3) 익명 사용자: 대부분 route 허용 (게스트 모드, AuthRequired 가 보호).
  // 단 /verify-email 은 정식 사용자 전용 — 익명은 Home 으로 보낸다.
  if (isAuthenticated && isAnonymous) {
    if (matchedLocation == AppRoutes.verifyEmail) {
      return AppRoutes.home;
    }
    return null;
  }

  // (4) 정식 인증 + emailVerified==false + /verify-email 외 -> /verify-email
  if (isAuthenticated &&
      !isAnonymous &&
      !currentUser.emailVerified &&
      matchedLocation != AppRoutes.verifyEmail) {
    return AppRoutes.verifyEmail;
  }

  // (5) BLOCKER #3 / BLOCKER #7 / D-14 / D-15 (1회 동의 invariant):
  // 정식 인증 + emailVerified + termsAccepted=null -> /onboarding.
  // 이메일 직접 가입 경로(`/signup` -> 가입 -> Home)에서 termsAccepted=null
  // 상태의 Home 바이패스를 차단한다. /onboarding, /terms/* 공개 경로는 허용.
  if (isAuthenticated &&
      !isAnonymous &&
      currentUser.emailVerified &&
      !termsAccepted &&
      matchedLocation != AppRoutes.onboarding &&
      matchedLocation != AppRoutes.termsService &&
      matchedLocation != AppRoutes.termsPrivacy) {
    return AppRoutes.onboarding;
  }

  // (6) 정식 인증 + emailVerified + termsAccepted + (unauth/verifyEmail/
  // onboarding) -> /home (완료된 사용자가 진입 화면 재방문 차단).
  if (isAuthenticated &&
      !isAnonymous &&
      currentUser.emailVerified &&
      termsAccepted &&
      (isOnUnauthRoute || matchedLocation == AppRoutes.verifyEmail)) {
    return AppRoutes.home;
  }

  return null; // (7) AUTH-13 자동 검증 — 인증 완료 사용자 Home 랜딩 허용.
}

/// userChanges 이벤트를 Analytics/Crashlytics setUser + Firestore mirror
/// 에 연결한다 (Phase 10 D-30, BLOCKER #4, INFO #21).
///
/// **BLOCKER #4 이행:** 이전 스트림 값이 익명 사용자이고 현재 값이 정식
/// 사용자인 전이를 감지하면, [TermsNotifier.mirrorToFirestore] 를 호출하여
/// 정식 UID 에 약관 동의 기록을 Firestore 에 미러링한다 (Plan 03 T-10-11
/// threat model 이행).
///
/// **INFO #21 이행:** [Ref.keepAlive] 로 appRouter rebuild 시 구독이 churn
/// 하지 않도록 보장한다.
///
/// **활성화:** 본 Provider 는 watch 되지 않으면 동작하지 않으므로,
/// `appRouterProvider` 내부에서 `ref.watch(authUserObserverProvider)` 로
/// 1회 warm-up 한다.
///
/// **Phase 1 D-13:** Firebase 미초기화 시 빈 스트림 emit 후 즉시 종료.
@Riverpod(keepAlive: true)
Stream<void> authUserObserver(Ref ref) async* {
  // INFO #21: appRouter rebuild 시 구독 churn 방지.
  ref.keepAlive();

  final isInitialized = ref.watch(isFirebaseInitializedProvider);
  if (!isInitialized) return;

  final analytics = ref.watch(analyticsServiceProvider);
  final crashlytics = ref.watch(crashlyticsServiceProvider);
  // authStateProvider 는 Stream<User?> 를 반환하지만 riverpod_generator 3.x
  // 에서는 `.stream` 게터가 노출되지 않으므로, firebaseAuthProvider 에서
  // userChanges() 를 직접 구독한다 (테스트에서는 firebaseAuthProvider
  // override 만으로 동일 흐름을 시뮬레이션 가능).
  final auth = ref.watch(firebaseAuthProvider);
  final authStream = auth.userChanges();

  bool? prevIsAnonymous;

  await for (final user in authStream) {
    final uid = user?.uid;
    final curIsAnonymous = user?.isAnonymous ?? false;

    // Analytics + Crashlytics 사용자 속성 업데이트.
    await analytics.setGuestMode(curIsAnonymous);
    await analytics.setUserId(uid);
    await crashlytics.setUserId(uid);

    // BLOCKER #4: 익명 -> 정식 전이 감지 시 Firestore 미러 호출.
    if (user != null && !curIsAnonymous && prevIsAnonymous == true) {
      final mirrorResult = await ref
          .read(termsProvider.notifier)
          .mirrorToFirestore(uid: user.uid);
      // 미러 실패 시 termsNotifier 내부에서 crashlytics.recordError 가
      // 처리되며, 여기서는 결과를 무시하고 계속 진행 (UX 단절 방지).
      if (kDebugMode && mirrorResult is Failure) {
        debugPrint(
          'authUserObserver: mirrorToFirestore failed '
          '(이전 익명 -> 정식 전이)',
        );
      }
    }

    prevIsAnonymous = curIsAnonymous;
    yield null;
  }
}
