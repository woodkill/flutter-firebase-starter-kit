import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/auth/presentation/email_login_screen.dart';
import '../../features/auth/presentation/email_signup_screen.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/verify_email_screen.dart';
import '../../features/demo/presentation/demo_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/not_found/presentation/not_found_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/settings/presentation/account_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/settings/presentation/withdrawal_disconnect_screen.dart';
import '../../features/splash/presentation/splash_screen.dart';
import '../../features/terms/presentation/terms_detail_screen.dart';
import '../analytics/analytics_observer.dart';
import 'app_routes.dart';
import 'auth_guard.dart';
import 'auth_refresh.dart';

part 'app_router.g.dart';

/// 루트 Navigator 키.
///
/// 향후 ShellRoute 추가나 모달 표시 시 사용한다. (D-16)
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// GoRouter 의 `refreshListenable` 요구를 만족시키는 router 소유 어댑터
/// (quick 260920-b28).
///
/// GoRouter 가 요구하는 것은 [Listenable] 뿐이고, Riverpod provider 는
/// [Listenable] 같은 가변 객체를 값으로 반환해서는 안 된다
/// (riverpod_lint `unsupported_provider_value`). 그래서 이 객체는 **소비하는
/// 쪽**인 [appRouter] 가 만들어 소유 · dispose 하는 구현 세부이며,
/// [authRefreshProvider] 의 state 변화를 `ref.listen` 이 여기로 중계한다.
@visibleForTesting
class RouterRefreshListenable extends ChangeNotifier {
  /// GoRouter 에 redirect 재평가를 1회 요청한다.
  void notifyRefresh() => notifyListeners();
}

/// 앱의 [GoRouter] 인스턴스를 제공한다 (Phase 10 D-14, D-22, D-29, WARNING #14).
///
/// [GoRouter.refreshListenable] 에 [RouterRefreshListenable] 을 연결하고
/// [authRefreshProvider] 의 state 변화를 그리로 중계하여 인증 상태 변경 시
/// [resolveAuthRedirect] 를 자동 재평가한다. [keepAlive] 로 앱 생명주기 동안 단일
/// 인스턴스를 유지한다.
///
/// **observers (D-29):** [analyticsObserverProvider] 를 등록하여
/// `FirebaseAnalyticsObserver` 가 화면 전환을 자동 추적하도록 한다.
///
/// **screen_view 발신 주체는 observer 단 하나다 (코드 리뷰 CR-01).** 과거
/// WARNING #14 (Pitfall 1) 는 *"observer 는 `didPush` 시점에만 동작하므로
/// `context.go()` same-level 전환을 놓친다"* 를 전제로
/// `routerDelegate.addListener` 수동 발신을 덧붙였으나, 그 전제가 패키지
/// 소스와 달랐다 — `firebase_analytics` 의 `FirebaseAnalyticsObserver` 는
/// `didPush` / `didReplace` / `didPop` 3콜백 모두에서 `_sendScreenView` 를
/// 호출한다 (`firebase_analytics/lib/observer.dart`). 두 경로가 동시에
/// 살아 있어 모든 전환이 GA4 에 2회 적재됐고, 교차 dedup 은 없었다.
/// 수동 경로를 제거해 "한 번의 전환 = `screen_view` 1건" 을 복구한다.
/// 회귀는 `app_router_observers_test.dart` 의 런타임 계측 테스트가 잠근다.
///
/// **authUserObserver warm-up (BLOCKER #4 + INFO #21, 코드 리뷰 CR-01 정정):**
/// Plan 05 Task 1 에서 추가한 `authUserObserverProvider` 는 구독되지 않으면
/// 동작하지 않으므로 본 Provider 에서 1회 구독하여 활성화한다. 단 구독 수단은
/// [Ref.listen] 이어야 하며 `ref.watch` 를 쓰면 안 된다 — 상세는 아래
/// [appRouter] 본문 주석 참조.
@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  final observer = ref.watch(analyticsObserverProvider);

  // CR-01 (quick 260920-b28): 인증 변화는 `watch` 가 아니라 `listen` 으로 받는다.
  // 옛 `ref.watch` 배선은 provider 가 재생성될 때마다 본 Provider
  // 를 rebuild 시켜 GoRouter 를 통째로 교체했다 (내비게이션 위치 소실 +
  // 이전 라우터의 listener 누수). `ref.listen` 은 Provider 를 초기화(=구독
  // 활성화)하되 rebuild 를 유발하지 않으므로, authRefresh 의 state 가 몇 번
  // 바뀌어도 GoRouter 인스턴스는 동일하게 유지된다.
  final refreshListenable = RouterRefreshListenable();
  ref.listen(authRefreshProvider, (_, _) => refreshListenable.notifyRefresh());

  // INFO #21 + BLOCKER #4: authUserObserver 활성화.
  //
  // **CR-01 (코드 리뷰 05):** 여기에 있던 `ref.watch(authUserObserverProvider)`
  // 는 "활성화" 외에 **구독**까지 수행하여, `AsyncLoading -> AsyncData`
  // (모든 콜드 스타트에서 1회 확정) / `AsyncData -> AsyncError` 전이마다 본
  // Provider 를 rebuild 시켰다. rebuild 는 GoRouter 를 통째로 재생성하므로
  // (a) `MaterialApp.router` 가 새 routerDelegate 로 교체되며 그때까지의
  // 내비게이션 위치가 initialLocation 으로 폐기되고, (b) 이전 GoRouter 가
  // dispose 되지 않아 refresh 어댑터의 listener 가 영구 누수된다.
  // `ref.listen` 은 Provider 를 초기화(=활성화)하되 rebuild 를 유발하지
  // 않으므로 warm-up 의 원래 의도에 정확히 부합한다.
  //
  // `onError` 는 필수다 — 생략하면 observer 스트림 에러가 listener 미처리로
  // 간주되어 zone uncaught error 로 승격된다. 에러 기록 책임은 observer 본체
  // (`authUserObserver` 의 Crashlytics 기록) 에 있으므로 여기서는 흡수만 한다.
  ref.listen(authUserObserverProvider, (_, _) {}, onError: (_, _) {});

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.splash, // D-14 상태머신 시작점
    // 플랫폼 기본 경로(defaultRouteName)를 무시하고 항상 /splash 에서 시작한다
    // (debug notification-task-duplication RC1). Android Flutter 엔진은 launch
    // intent 의 extra "route"(EXTRA_INITIAL_ROUTE)를 초기 경로로 넘기는데,
    // FCM 은 알림 data 를 그 intent 의 extra 로 복사한다 — 킷 알림 payload 키가
    // 마침 `route` 다. 이 값을 끄지 않으면 알림 콜드 탭 · 최근 앱 재실행이
    // 스플래시 · 홈 리스너(D-04) · 허용 목록(T-17-53)을 건너뛰고 그 경로로
    // 바로 열린다. 알림 경로 이동은 홈 리스너만 한다.
    // 대가: 콜드 시작 deep link 의 경로도 무시된다. MainActivity 에 VIEW
    // intent-filter(App Links)를 붙이는 앱은 이 줄과 함께 다시 설계한다.
    overridePlatformDefaultLocation: true,
    debugLogDiagnostics: kDebugMode,
    refreshListenable: refreshListenable,
    redirect: (context, state) => resolveAuthRedirect(ref, state),
    observers: [observer],
    // Phase 17.1 D-18 — 잘못된 경로는 전용 404 화면 (IN-05 — home silent redirect 금지 · state 미사용)
    errorBuilder: (context, state) => const NotFoundScreen(),
    routes: [
      GoRoute(
        path: AppRoutes.home,
        name: AppRoutes.homeName,
        builder: (context, state) => const HomeScreen(),
        // Phase 17.2 todo 결정 1 — 알림 허용 목록의 홈 아닌 4경로는 홈 하위 route.
        // `go` 로 열어도 홈이 스택 맨 아래에 남아 ← · 시스템 뒤로 · iOS 스와이프로
        // 홈까지 돌아오고 홈 리스너(17.1 D-17)도 트리에 남는다.
        routes: [
          // Phase 16 D-05 — Settings 진입 path.
          GoRoute(
            path: AppRoutes.settingsSegment,
            name: AppRoutes.settingsName,
            builder: (context, state) => const SettingsScreen(),
            routes: [
              // Phase 17.1 D-02 — 계정 정보 화면(설정 계정 행에서 push · 탈퇴 진행은 여기서 push).
              GoRoute(
                path: AppRoutes.accountSegment,
                name: AppRoutes.accountName,
                builder: (context, state) => const AccountScreen(),
              ),
              // Phase 16.10 D-06 — 탈퇴 진행 화면 (탈퇴 다이얼로그 확인 뒤 push).
              GoRoute(
                path: AppRoutes.withdrawalDisconnectSegment,
                name: AppRoutes.withdrawalDisconnectName,
                builder: (context, state) => const WithdrawalDisconnectScreen(),
              ),
              // Phase 17.1 D-14 — 데모는 release 가 아닌 빌드에서만 등록한다(const 분기 →
              // release 바이너리에서 DemoScreen 참조가 빠진다). release 는 이 경로가 404(D-18).
              if (!kReleaseMode)
                GoRoute(
                  path: AppRoutes.developerDemoSegment,
                  name: AppRoutes.developerDemoName,
                  builder: (context, state) => const DemoScreen(),
                ),
            ],
          ),
          GoRoute(
            path: AppRoutes.termsServiceSegment,
            name: AppRoutes.termsServiceName,
            builder: (context, state) =>
                const TermsDetailScreen(type: TermsType.service),
          ),
          GoRoute(
            path: AppRoutes.termsPrivacySegment,
            name: AppRoutes.termsPrivacyName,
            builder: (context, state) =>
                const TermsDetailScreen(type: TermsType.privacy),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.splash,
        name: AppRoutes.splashName,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        name: AppRoutes.onboardingName,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        name: AppRoutes.loginName,
        // 재인증 표시는 guard 뿐 아니라 화면 모드도 결정한다
        // (debug reauth-login-auto-merge — 표시가 있으면 현재 계정 재인증 화면).
        builder: (context, state) =>
            LoginScreen(isReauth: AppRoutes.hasReauthMarker(state.uri)),
      ),
      // Phase 16.1 D-01 — 이메일 form 전용 진입 path (최상위 형제 route).
      GoRoute(
        path: AppRoutes.emailLogin,
        name: AppRoutes.emailLoginName,
        builder: (context, state) =>
            EmailLoginScreen(isReauth: AppRoutes.hasReauthMarker(state.uri)),
      ),
      GoRoute(
        path: AppRoutes.signup,
        name: AppRoutes.signupName,
        builder: (context, state) => const EmailSignupScreen(),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        name: AppRoutes.forgotPasswordName,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: AppRoutes.verifyEmail,
        name: AppRoutes.verifyEmailName,
        builder: (context, state) => const VerifyEmailScreen(),
      ),
    ],
  );

  // CR-01: 여기에 있던 `routerDelegate.addListener` 수동 screen_view 발신을
  // 제거했다. observer 가 push/replace/pop 을 모두 커버하므로 수동 경로는
  // 보완이 아니라 중복 발신이었다.
  //
  // T-10-20 PII 보호는 observer 의 `nameExtractor` 가 계속 담당한다 —
  // `settings.name` (= go_router 가 page 에 심는 `GoRoute.name`) 만 읽으므로
  // 쿼리 파라미터가 screenName 에 섞이지 않는다. 따라서 모든 `GoRoute` 에
  // `name` 설정은 여전히 필수다 (Pitfall 1, Test 3 이 잠근다)
  // (하위 route 포함 — Test 3 은 재귀로 센다 · Phase 17.2).

  // CR-01: Provider 파기(컨테이너 dispose / 예기치 못한 rebuild) 시 GoRouter 를
  // 반드시 dispose 한다. `GoRouteInformationProvider` 는 생성자에서
  // `refreshListenable.addListener` 를 등록하고 오직 `dispose()` 에서만
  // 해제하므로, 이 호출이 없으면 죽은 라우터가 어댑터의 listener 목록에
  // 영구히 남는다.
  //
  // WR-04: 등록 순서가 곧 실행 순서다 — 라우터를 먼저 정리해 listener 를 뗀
  // 뒤에 어댑터를 dispose 한다. 뒤집으면 이미 dispose 된 ChangeNotifier 에
  // 라우터가 `removeListener` 를 호출한다.
  ref.onDispose(router.dispose);
  ref.onDispose(refreshListenable.dispose);
  return router;
}
