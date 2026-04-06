/// 앱의 route path와 name 상수를 정의한다.
///
/// 문자열 기반 route 하드코딩을 방지하고, 모든 route를 단일 지점에서 관리한다.
/// 새 route 추가 시 이 클래스에 상수를 먼저 추가한다.
abstract final class AppRoutes {
  /// Home 화면 path.
  static const String home = '/';

  /// Home 화면 name.
  static const String homeName = 'home';

  /// Login 화면 path.
  static const String login = '/login';

  /// Login 화면 name.
  static const String loginName = 'login';

  /// Splash 화면 path.
  static const String splash = '/splash';

  /// Splash 화면 name.
  static const String splashName = 'splash';
}
