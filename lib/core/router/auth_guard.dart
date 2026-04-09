import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../providers/firebase_providers.dart';
import 'app_routes.dart';

part 'auth_guard.g.dart';

/// authStateChanges 스트림을 GoRouter [refreshListenable]용
/// [ChangeNotifier]로 래핑한다.
///
/// 스트림이 이벤트를 emit할 때마다 [notifyListeners]를 호출하여
/// GoRouter가 redirect를 재평가하도록 트리거한다.
/// [GoRouterRefreshStream]이 go_router v5.0.0에서 제거되었으므로
/// 이 클래스가 동일한 역할을 수행한다.
class AuthChangeNotifier extends ChangeNotifier {
  /// [stream]의 이벤트를 수신하여 [notifyListeners]를 호출하는
  /// [ChangeNotifier]를 생성한다.
  AuthChangeNotifier(Stream<fb.User?> stream) {
    _subscription = stream.listen((user) {
      if (kDebugMode) {
        debugPrint(
          'AuthChangeNotifier: authStateChanges emit '
          '(user=${user?.uid ?? "null"}) -> notifyListeners',
        );
      }
      notifyListeners();
    });
  }

  /// authStateChanges 구독. nullable 로 선언하여 향후 [stream] 이
  /// lazy-initialized 되어 [Stream.listen] 자체가 throw 하더라도
  /// [dispose] 가 LateInitializationError 없이 안전하게 동작하도록 한다.
  /// (flutter.md "late 사용 최소화" 규칙)
  StreamSubscription<fb.User?>? _subscription;

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
  final notifier = AuthChangeNotifier(auth.authStateChanges());
  ref.onDispose(notifier.dispose);
  return notifier;
}

/// 미인증 사용자가 접근 가능한 화이트리스트 경로 집합.
///
/// 본 집합에 포함된 경로는 [authRedirect]가 미인증 상태에서도
/// /login 으로 강제 이동시키지 않는다. 신규 unauth 경로 추가 시
/// 명시적으로 본 Set 에 포함해야 하며, 그 외 모든 경로는 default-deny
/// 정책에 따라 차단된다 (T-06.03-01 대응).
const Set<String> _unauthRoutes = <String>{
  AppRoutes.login,
  AppRoutes.signup,
  AppRoutes.forgotPassword,
  AppRoutes.verifyEmail, // 인증됐지만 emailVerified==false인 사용자도 접근 가능
};

/// 인증 상태에 따른 redirect 로직.
///
/// 판단 우선순위 (D-06):
/// 1. Firebase 미초기화 시: redirect 우회 (null 반환, Home 직행)
/// 2. 미인증 + unauth 화이트리스트 외 경로: [AppRoutes.login]으로 redirect
/// 3. 인증 + emailVerified==false + /verify-email 외 경로:
///    [AppRoutes.verifyEmail]로 redirect
/// 4. 인증 + emailVerified==true + unauth 화이트리스트 경로:
///    [AppRoutes.home]으로 redirect
/// 5. 그 외: null (redirect 없음)
///
/// 인증 전환(Login<->Home)은 [go]로 스택 교체,
/// 일반 화면 이동은 [push]로 스택 추가를 권장한다. (D-19)
///
/// **인증 판정 소스:** [fb.FirebaseAuth.currentUser]를 직접 읽는다.
/// `authStateProvider`를 사용하지 않는 이유는, [AuthChangeNotifier]가
/// `authStateChanges()`에 먼저 구독하기 때문에 (subscription #1),
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
  final isOnUnauthRoute = _unauthRoutes.contains(state.matchedLocation);

  if (kDebugMode) {
    debugPrint(
      'authRedirect: matchedLocation=${state.matchedLocation}, '
      'isAuthenticated=$isAuthenticated '
      '(uid=${currentUser?.uid ?? "null"}, '
      'emailVerified=${currentUser?.emailVerified}), '
      'isOnUnauthRoute=$isOnUnauthRoute',
    );
  }

  if (!isAuthenticated && !isOnUnauthRoute) {
    return AppRoutes.login; // (2)
  }

  // emailVerified 체크: 인증됐지만 이메일 미인증 사용자 차단 (D-04, D-06).
  // currentUser.emailVerified는 Firebase SDK가 reload() 후
  // 동기적으로 업데이트하므로 stale value 위험 없음.
  if (isAuthenticated &&
      !currentUser.emailVerified &&
      state.matchedLocation != AppRoutes.verifyEmail) {
    return AppRoutes.verifyEmail; // (3)
  }

  if (isAuthenticated &&
      currentUser.emailVerified &&
      isOnUnauthRoute) {
    return AppRoutes.home; // (4)
  }

  return null; // (5)
}
