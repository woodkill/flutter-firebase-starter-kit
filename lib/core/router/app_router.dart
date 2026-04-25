import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/signup_screen.dart';
import '../../features/auth/presentation/verify_email_screen.dart';
import '../../features/home/presentation/environment_info_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/splash/presentation/splash_screen.dart';
import '../../features/terms/presentation/terms_detail_screen.dart';
import '../analytics/analytics_observer.dart';
import '../analytics/analytics_service.dart';
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
/// [authRedirect] 를 자동 재평가한다. [keepAlive] 로 앱 생명주기 동안 단일
/// 인스턴스를 유지한다.
///
/// **observers (D-29):** [analyticsObserverProvider] 를 등록하여
/// [FirebaseAnalyticsObserver] 가 화면 전환을 자동 추적하도록 한다.
///
/// **WARNING #14 (Pitfall 1):** [FirebaseAnalyticsObserver] 는
/// `didPush` 시점에만 동작하지만, `context.go()` same-level 전환은 push 대신
/// replace 동작이라 observer 가 이벤트를 놓칠 수 있다. 이를 보완하기 위해
/// `routerDelegate.addListener` 로 matchedLocation 변경을 감지하여
/// [AnalyticsService.logScreenView] 를 수동 호출한다.
///
/// **authUserObserver warm-up (BLOCKER #4 + INFO #21):** Plan 05 Task 1 에서
/// 추가한 `authUserObserverProvider` 는 watch 되지 않으면 동작하지 않으므로,
/// 본 Provider 에서 1회 watch 하여 활성화한다.
@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  final authGuard = ref.watch(authChangeProvider);
  final observer = ref.watch(analyticsObserverProvider);
  final analytics = ref.watch(analyticsServiceProvider);

  // INFO #21 + BLOCKER #4: authUserObserver 활성화 (1회 watch 로 충분).
  ref.watch(authUserObserverProvider);

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.splash, // D-14 상태머신 시작점
    debugLogDiagnostics: kDebugMode,
    refreshListenable: authGuard,
    redirect: (context, state) => authRedirect(ref, state),
    observers: [observer],
    // TODO: production home 분리 시 dedicated NotFoundScreen 으로 교체.
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
      GoRoute(
        path: AppRoutes.signup,
        name: AppRoutes.signupName,
        builder: (context, state) => const SignupScreen(),
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
    ],
  );

  // WARNING #14 (Pitfall 1): go_router go() same-level 전환은 push 대신
  // replace 동작이므로 FirebaseAnalyticsObserver 가 screen_view 를 놓칠 수
  // 있다. routerDelegate.addListener 로 matchedLocation 변경을 감지하여
  // analytics.logScreenView 를 수동 호출한다.
  //
  // T-10-20 PII 보호: screenName 에 쿼리 파라미터(`?focus=email` 등) 를
  // 포함하지 않고, route name 또는 matchedLocation (path) 만 사용한다.
  String? lastMatchedLocation;
  void onRouterChange() {
    final config = router.routerDelegate.currentConfiguration;
    if (config.matches.isEmpty) return;
    final lastMatch = config.matches.last;
    final currentLocation = lastMatch.matchedLocation;
    final route = lastMatch.route;
    final currentName = route is GoRoute ? route.name : null;
    if (currentLocation != lastMatchedLocation) {
      lastMatchedLocation = currentLocation;
      analytics.logScreenView(screenName: currentName ?? currentLocation);
    }
  }

  router.routerDelegate.addListener(onRouterChange);
  ref.onDispose(() {
    router.routerDelegate.removeListener(onRouterChange);
  });

  return router;
}

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
  final textTheme = context.textTheme;
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
              size: 64,
              color: colorScheme.onSurfaceVariant,
            ),
            Gap(spacing.lg),
            Text(
              l10n.errorNotFoundTitle,
              style: textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            Gap(spacing.sm),
            Text(
              l10n.errorNotFoundBody,
              style: textTheme.bodyMedium?.copyWith(
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
