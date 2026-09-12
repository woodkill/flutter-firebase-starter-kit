import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/auth/presentation/email_login_screen.dart';
import '../../features/auth/presentation/email_signup_screen.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/verify_email_screen.dart';
import '../../features/home/presentation/environment_info_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/splash/presentation/splash_screen.dart';
import '../../features/terms/presentation/terms_detail_screen.dart';
import '../analytics/analytics_observer.dart';
import '../l10n/l10n_extensions.dart';
import '../theme/theme_extensions.dart';
import 'app_routes.dart';
import 'auth_guard.dart';

part 'app_router.g.dart';

/// 루트 Navigator 키.
///
/// 향후 ShellRoute 추가나 모달 표시 시 사용한다. (D-16)
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// 앱의 [GoRouter] 인스턴스를 제공한다 (Phase 10 D-14, D-22, D-29, WARNING #14).
///
/// [refreshListenable] 에 [AuthChangeNotifier] 를 연결하여 인증 상태 변경 시
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
  final authGuard = ref.watch(authChangeProvider);
  final observer = ref.watch(analyticsObserverProvider);

  // INFO #21 + BLOCKER #4: authUserObserver 활성화.
  //
  // **CR-01 (코드 리뷰 05):** 여기에 있던 `ref.watch(authUserObserverProvider)`
  // 는 "활성화" 외에 **구독**까지 수행하여, `AsyncLoading -> AsyncData`
  // (모든 콜드 스타트에서 1회 확정) / `AsyncData -> AsyncError` 전이마다 본
  // Provider 를 rebuild 시켰다. rebuild 는 GoRouter 를 통째로 재생성하므로
  // (a) `MaterialApp.router` 가 새 routerDelegate 로 교체되며 그때까지의
  // 내비게이션 위치가 initialLocation 으로 폐기되고, (b) 이전 GoRouter 가
  // dispose 되지 않아 `AuthChangeNotifier` listener 가 영구 누수된다.
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
    debugLogDiagnostics: kDebugMode,
    refreshListenable: authGuard,
    redirect: (context, state) => resolveAuthRedirect(ref, state),
    observers: [observer],
    // TODO: dedicated NotFoundScreen — see .planning/todos/pending/2026-09-09-not-found-screen.md
    // 현재는 EnvironmentInfoScreen 폴백 대신 임시 Scaffold 로 명시적
    // 404 안내를 표시하여, 잘못된 deep link 에서도 home 으로 silent
    // redirect 되지 않도록 한다 (IN-05).
    errorBuilder: (context, state) => buildNotFoundScreen(context),
    routes: [
      GoRoute(
        path: AppRoutes.home,
        name: AppRoutes.homeName,
        builder: (context, state) => const EnvironmentInfoScreen(),
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
        builder: (context, state) => const LoginScreen(),
      ),
      // Phase 16.1 D-01 — 이메일 form 전용 진입 path (최상위 형제 route).
      GoRoute(
        path: AppRoutes.emailLogin,
        name: AppRoutes.emailLoginName,
        builder: (context, state) => const EmailLoginScreen(),
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
      GoRoute(
        path: AppRoutes.termsService,
        name: AppRoutes.termsServiceName,
        builder: (context, state) =>
            const TermsDetailScreen(type: TermsType.service),
      ),
      GoRoute(
        path: AppRoutes.termsPrivacy,
        name: AppRoutes.termsPrivacyName,
        builder: (context, state) =>
            const TermsDetailScreen(type: TermsType.privacy),
      ),
      // Phase 16 D-05 — Settings 진입 path.
      GoRoute(
        path: AppRoutes.settings,
        name: AppRoutes.settingsName,
        builder: (context, state) => const SettingsScreen(),
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
  // `name` 설정은 여전히 필수다 (Pitfall 1, Test 3 이 잠근다).

  // CR-01: Provider 파기(컨테이너 dispose / 예기치 못한 rebuild) 시 GoRouter 를
  // 반드시 dispose 한다. `GoRouteInformationProvider` 는 생성자에서
  // `refreshListenable.addListener` 를 등록하고 오직 `dispose()` 에서만
  // 해제하므로, 이 호출이 없으면 죽은 라우터가 `AuthChangeNotifier` 의
  // listener 목록에 영구히 남는다.
  ref.onDispose(router.dispose);
  return router;
}

/// 404 화면의 안내 아이콘 크기 (IN-01 — 매직 넘버 명명).
///
/// [AppSpacing] 스케일(4px 기반)의 배수가 아닌 독립 illustration 치수이므로
/// spacing 토큰을 재사용하지 않고 전용 상수로 둔다.
const double _notFoundIconSize = 64;

/// 404 errorBuilder 본문 — 잘못된 deep link 진입 시 표시되는 recovery UI.
///
/// [GoRouter.errorBuilder] 에서 호출된다.
/// [visibleForTesting] 으로 노출하여 GoRouter 전체 스택 없이
/// widget test 에서 직접 pump 할 수 있게 한다.
@visibleForTesting
Widget buildNotFoundScreen(BuildContext context) {
  final l10n = context.l10n;
  final spacing = context.appSpacing;
  final colorScheme = context.colorScheme;
  // IN-01: 저장소 dominant 규약인 토큰 접근자를 사용한다. `context.textTheme`
  // 은 AppTypography extension override 를 반영하지 않아, 사용자가 ThemeData
  // 를 교체하면 이 화면만 나머지와 다르게 drift 한다.
  final typography = context.appTypography;
  return Scaffold(
    appBar: AppBar(title: Text(l10n.errorNotFoundTitle)),
    body: Center(
      child: Padding(
        padding: EdgeInsets.all(spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: _notFoundIconSize,
              color: colorScheme.onSurfaceVariant,
            ),
            Gap(spacing.lg),
            Text(
              l10n.errorNotFoundTitle,
              style: typography.titleLarge,
              textAlign: TextAlign.center,
            ),
            Gap(spacing.sm),
            Text(
              l10n.errorNotFoundBody,
              style: typography.bodyMedium.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            Gap(spacing.xl),
            FilledButton.icon(
              onPressed: () => context.go(AppRoutes.home),
              icon: const Icon(Icons.home),
              label: Text(l10n.errorNotFoundGoHomeCta),
            ),
          ],
        ),
      ),
    ),
  );
}
