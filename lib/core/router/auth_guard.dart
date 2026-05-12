import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/auth/application/social_link_in_progress.dart';
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
  // Issue #10 Plan 10-14 GC-02: onboardingProvider 가 AsyncNotifier<bool>
  // 로 전환되어 AsyncValue 로 소비한다. AsyncLoading 상태면 판단을 유보
  // (null 반환) 하여 prefs 로드 완료 전 stale snapshot 으로 분기를
  // 잘못 평가하지 않도록 한다. GC-04 fail-safe 분기의 전제 조건이기도 함.
  final onboardingAsync = ref.read(onboardingProvider);
  if (onboardingAsync.isLoading) {
    if (kDebugMode) {
      debugPrint(
        'authRedirect: onboardingProvider loading '
        '-> null (await settle) [Issue #10 GC-02]',
      );
    }
    return null;
  }
  final onboardingSeen = onboardingAsync.value ?? false;
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
  // Issue #4 (Plan 10-10): Dev Tools '온보딩 다시 보기' → cold restart 시
  // 익명 세션 복원으로 분기 (2) 가 미발동하므로, 익명 사용자도 동일하게
  // !onboardingSeen + 공개 경로 외 조합에서 /onboarding 으로 리다이렉트한다.
  // 공개 경로 화이트리스트 = _unauthRoutes (login/signup/forgotPassword/
  // onboarding/terms/*) + splash. 익명 사용자는 정식 승격을 위해 /login
  // /signup 등 인증 경로 접근이 필요하므로 _unauthRoutes 전체를 허용한다
  // (D-33 Dev Tools 완결성 + AUTH-11 상태 머신 분기 완전성).
  //
  // Phase 10.2 D-C1 단일 gate 통합: 익명 user 의 `(!onboardingSeen ||
  // !termsAccepted)` → /onboarding 강제. 정식 user 분기 (5) 의 destination
  // `/onboarding` 과 일관. 9.2 HUMAN-UAT cycle 1+2 OOS-01 (Facebook /
  // Kakao / Naver 신규) 회귀 가드 — D-20 자동 익명 재진입 폐기 후 새 익명
  // UID 의 termsAccepted=null 누수 차단.
  // Phase 10.2 D-C2 stale guard 익명 확장 (Plan 10-11 분기 (5)
  // lastReloadedUid 패턴 mirror): 익명 user 의 termsProvider 가 현재 uid
  // 에 대해 reload 완료 전 시점의 평가는 null (현재 location 유지) 을
  // 반환. authUserObserver 의 reloadForUser 완료 후 triggerRedirect 가
  // 재평가한다. 상세: .planning/phases/10.2-auth-state-invariant-cleanup-
  // inserted/10.2-CONTEXT.md D-C1/C2.
  if (isAuthenticated && isAnonymous) {
    if (matchedLocation == AppRoutes.verifyEmail) {
      return AppRoutes.home;
    }
    // (D-C1) 단일 gate: onboardingSeen + termsAccepted 모두 완료 시에만
    // /home 통과. 두 truth 중 하나라도 false 면 trip.
    if ((!onboardingSeen || !termsAccepted) &&
        !isOnUnauthRoute &&
        matchedLocation != AppRoutes.splash) {
      // (D-C2) `!onboardingSeen` 만으로 trip 되는 케이스에는 stale 검사
      // 불필요 (onboardingSeen 은 SharedPreferences AsyncNotifier 의
      // isLoading 가드 (line 142-151) 가 이미 처리 — I4 cold-start
      // invariant + PATTERNS Pitfall 5). 따라서 stale 가드는
      // `onboardingSeen && !termsAccepted` 단독 trip 인 경우에만 발동.
      // Plan 10-11 분기 (5) lastReloadedUid 패턴 익명 확장.
      if (onboardingSeen && !termsAccepted) {
        final reloadedUid = ref.read(termsProvider.notifier).lastReloadedUid;
        if (reloadedUid != currentUser.uid) {
          if (kDebugMode) {
            // WARNING #18: uid 원문 대신 hashCode 로 PII 완화.
            final reloadedHash =
                reloadedUid?.hashCode.toString() ?? 'null';
            final currentHash = currentUser.uid.hashCode.toString();
            debugPrint(
              'authRedirect: stale termsProvider (anon) '
              '(reloadedHash=$reloadedHash, currentHash=$currentHash) '
              '-> null (await reload) [Phase 10.2 D-C2]',
            );
          }
          return null;
        }
      }
      return AppRoutes.onboarding;
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
  //
  // Issue #7 (Plan 10-11) stale 가드: AuthChangeNotifier subscription #1 이
  // authUserObserver subscription #2 의 reloadForUser 완료보다 먼저 발동하여
  // authRedirect 가 stale termsProvider 를 참조하는 race 를 차단한다.
  // termsProvider 가 현재 uid 에 대해 아직 reload 되지 않은 시점의 평가는
  // null (현재 location 유지) 을 반환하여, authUserObserver 가 reloadForUser
  // 완료 후 authChangeProvider.triggerRedirect() 를 호출할 때까지 대기한다.
  // 상세 명세: .planning/debug/relogin-terms-race.md Resolution C-2.
  if (isAuthenticated &&
      !isAnonymous &&
      currentUser.emailVerified &&
      !termsAccepted) {
    final termsReloadedUid = ref.read(termsProvider.notifier).lastReloadedUid;
    if (termsReloadedUid != currentUser.uid) {
      if (kDebugMode) {
        // WARNING #18: uid 원문 대신 hashCode 로 PII 완화.
        final reloadedHash = termsReloadedUid?.hashCode.toString() ?? 'null';
        final currentHash = currentUser.uid.hashCode.toString();
        debugPrint(
          'authRedirect: stale termsProvider '
          '(reloadedHash=$reloadedHash, currentHash=$currentHash) '
          '-> null (await reload) [Issue #7 C-2]',
        );
      }
      return null;
    }
    if (matchedLocation != AppRoutes.onboarding &&
        matchedLocation != AppRoutes.termsService &&
        matchedLocation != AppRoutes.termsPrivacy) {
      return AppRoutes.onboarding;
    }
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

  // (6.4) Phase 9.1 D-02-B: socialLinkInProgress 가드 (Issue #10 GC-04 보류).
  // 미인증 + onboardingSeen=true + !공개경로 + matchedLocation != /splash 는
  // GC-04 fail-safe 가 발동하는 조건과 동일하지만, AuthRepository 의 social
  // sign-in 메서드(`signInWith{Google,Apple,Facebook}`) 가 진행 중이면
  // (`_safeDelete(anonymous)` 직후 currentUser=null 윈도우) /splash redirect
  // 자체를 보류하여 splash 화면 churn + 자동 익명 sign-in race 를 차단한다.
  // Plan 09.1-03 의 SplashInitializer 가드와 함께 defense-in-depth 를 구성한다.
  // 상세 race 시나리오: `09-UAT.md` Gap test 6 root_cause.
  //
  // **invariant 의존성 (WR-02):** `socialLinkInProgressProvider` 를 `ref.read`
  // 로 단발 read 한다 — `ref.watch` 사용 시 GoRouter redirect 의 단발 평가
  // 의미와 충돌하므로 read 가 정해진 패턴이다. 따라서 본 분기의 정확성은
  // 다음 시퀀스 가정에 의존한다:
  //   1. AuthRepository 의 sign-in 메서드 진입 직후 `begin()` 이 동기적으로
  //      state=true 로 전환한다 (try-block 첫 줄, line 168/249/332).
  //   2. `_safeDelete(anonymous)` 가 트리거하는 userChanges emit 은 begin()
  //      이후의 비동기 microtask 로 발행된다 (Firebase SDK 동작).
  //   3. emit 이 `AuthChangeNotifier.notifyListeners()` -> authRedirect 재평가
  //      을 트리거한 시점에 `ref.read(socialLinkInProgressProvider)` 는 이미
  //      true 를 반환한다.
  // 이 시퀀스는 `auth_repository_test.dart` SLP-7/8/9 의
  // `verifyInOrder([begin, user.delete, signInWith*, end])` 가드가 강제하므로,
  // 회귀 방지를 위해 해당 테스트를 절대 약화시키지 말 것. Firebase SDK 가
  // `_safeDelete` 에서 currentUser=null 을 동기적으로 emit 하도록 변경되거나
  // `begin()` 호출이 `authenticate()` await 이후로 이동하면 race 가 재발한다.
  if (!isAuthenticated &&
      onboardingSeen &&
      !isOnUnauthRoute &&
      matchedLocation != AppRoutes.splash &&
      ref.read(socialLinkInProgressProvider)) {
    if (kDebugMode) {
      debugPrint(
        'authRedirect: social link in progress '
        '(currentUser=null, onboardingSeen=true, matchedLocation='
        '$matchedLocation) -> null (await SDK return) [Phase 9.1 D-02-B]',
      );
    }
    // Observability: Crashlytics 신호로 onboarding_race_v1 (Plan 10-14) 과 구분.
    unawaited(
      ref
          .read(crashlyticsServiceProvider)
          .setCustomKey('race_guard_triggered', 'social_link_v1'),
    );
    return null;
  }

  // (6.5) Issue #10 GC-04 fail-safe (Plan 10-14):
  // 미인증 + onboardingSeen=true + !공개경로 + matchedLocation != /splash
  // -> /splash 복귀. 목적: OnboardingNotifier race 가 재발하거나 다른
  // race 가 미인증 상태로 Home 접근을 허용해도, Splash 가 signInAnonymously
  // 재시도 단일 진입점이므로 여기서 fail-safe 로 복귀시킨다. AsyncLoading
  // 은 이미 위에서 null 로 처리되어 여기 도달하지 않는다 (판단 유보 철학).
  //
  // 공개 경로 (_unauthRoutes: login/signup/forgotPassword/onboarding/terms/*)
  // 는 이미 isOnUnauthRoute=true 로 이 분기에서 제외된다. /splash 도
  // 자기 자신 복귀 무한루프를 방지하기 위해 명시적으로 제외한다.
  if (!isAuthenticated &&
      onboardingSeen &&
      !isOnUnauthRoute &&
      matchedLocation != AppRoutes.splash) {
    if (kDebugMode) {
      debugPrint(
        'authRedirect: fail-safe race guard '
        '(currentUser=null, onboardingSeen=true, matchedLocation='
        '$matchedLocation) -> /splash [Issue #10 GC-04]',
      );
    }
    // Observability: Crashlytics custom key 1회 기록. 비용 미미 + UAT
    // 증거로 가치 큼 (Claude 재량 — CONTEXT gap_closure_issue_10 명시).
    unawaited(
      ref
          .read(crashlyticsServiceProvider)
          .setCustomKey('race_guard_triggered', 'onboarding_race_v1'),
    );
    return AppRoutes.splash;
  }

  return null; // (7) AUTH-13 자동 검증 — 인증 완료 사용자 Home 랜딩 허용.
}

/// userChanges 이벤트를 Analytics/Crashlytics setUser + Firestore mirror
/// + termsProvider reload 에 연결한다 (Phase 10 D-30, BLOCKER #4, INFO #21,
/// Issue #6 — Plan 10-09).
///
/// **BLOCKER #4 이행:** 이전 스트림 값이 익명 사용자이고 현재 값이 정식
/// 사용자인 전이를 감지하면, [TermsNotifier.mirrorToFirestore] 를 호출하여
/// 정식 UID 에 약관 동의 기록을 Firestore 에 미러링한다 (Plan 03 T-10-11
/// threat model 이행).
///
/// **Issue #6 (Plan 10-09):** UID 변경 감지 시 [TermsNotifier.reloadForUser]
/// 호출. anonymous→full / full→full(다른 UID) / full→null / full→anonymous
/// 모든 전이를 커버하여 termsProvider 가 사용자 단위로 정확하게 평가되도록
/// 보장한다 (D-15 1회 동의 invariant 의 사용자 단위 평가). 동일 UID 재emit
/// 은 [prevUid] 비교로 무시하여 불필요 Firestore read 를 차단한다.
///
/// **호출 순서 보장:** mirrorToFirestore 가 reloadForUser 보다 **먼저**
/// 호출된다 — anonymous→full 전이 시 Firestore 에 먼저 write 한 후 read
/// 해야 stale read 가 발생하지 않음 (race condition 차단).
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
  String? prevUid;
  bool isFirstEmit = true;

  await for (final user in authStream) {
    final uid = user?.uid;
    final curIsAnonymous = user?.isAnonymous ?? false;

    // Analytics + Crashlytics 사용자 속성 업데이트.
    await analytics.setGuestMode(curIsAnonymous);
    await analytics.setUserId(uid);
    await crashlytics.setUserId(uid);

    // BLOCKER #4: 익명 -> 정식 전이 감지 시 Firestore 미러 호출.
    // (호출 순서: mirror 가 reloadForUser 보다 먼저 — Issue #6 직렬화 보장)
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

    // Issue #6 (Plan 10-09): UID 변경 감지 시 termsProvider reload.
    // - 첫 emit (isFirstEmit=true) 또는 prevUid != uid 인 경우 reload.
    // - 동일 UID 재emit 은 무시 (prevUid 비교 — 불필요 Firestore read 차단).
    if (isFirstEmit || uid != prevUid) {
      await ref
          .read(termsProvider.notifier)
          .reloadForUser(uid: uid, isAnonymous: curIsAnonymous);
      if (kDebugMode) {
        // WARNING #18: uid 원문 대신 hashCode 로 PII 완화.
        final prevHash = prevUid?.hashCode.toString() ?? 'null';
        final curHash = uid?.hashCode.toString() ?? 'null';
        debugPrint(
          'authUserObserver: UID changed (prevHash=$prevHash, '
          'curHash=$curHash, isAnonymous=$curIsAnonymous) '
          '-> termsProvider.reloadForUser',
        );
      }
      // Issue #7 C-3 (Plan 10-11): reloadForUser 가 lastReloadedUid 를
      // 갱신한 뒤, GoRouter 가 authRedirect 분기 (5) 의 stale 가드를 벗어날
      // 수 있도록 명시적으로 redirect 재평가를 트리거한다. authChangeProvider
      // 는 Provider<AuthChangeNotifier> 이므로 `.notifier` 접미어 없이 직접
      // read — auth_guard.g.dart 의 `AuthChangeNotifierProvider` 정의 참조.
      ref.read(authChangeProvider).triggerRedirect();
    }

    prevIsAnonymous = curIsAnonymous;
    prevUid = uid;
    isFirstEmit = false;
    yield null;
  }
}
