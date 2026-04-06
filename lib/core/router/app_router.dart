import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../../features/home/presentation/environment_info_screen.dart';
import '../../features/splash/presentation/splash_screen.dart';
import 'app_routes.dart';
import 'auth_guard.dart';

part 'app_router.g.dart';

/// 루트 Navigator 키.
///
/// 향후 ShellRoute 추가나 모달 표시 시 사용한다. (D-16)
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// 앱의 [GoRouter] 인스턴스를 제공한다.
///
/// [refreshListenable]에 [AuthChangeNotifier]를 연결하여
/// 인증 상태 변경 시 [authRedirect]를 자동 재평가한다.
/// [keepAlive]로 앱 생명주기 동안 단일 인스턴스를 유지한다.
@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  final authGuard = ref.watch(authChangeProvider);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.home,
    debugLogDiagnostics: kDebugMode,
    refreshListenable: authGuard,
    redirect: (context, state) => authRedirect(ref, state),
    errorBuilder: (context, state) => const EnvironmentInfoScreen(),
    routes: [
      GoRoute(
        path: AppRoutes.home,
        name: AppRoutes.homeName,
        builder: (context, state) => const EnvironmentInfoScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        name: AppRoutes.loginName,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.splash,
        name: AppRoutes.splashName,
        builder: (context, state) => const SplashScreen(),
      ),
    ],
  );
}
