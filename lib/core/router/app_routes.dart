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

  /// Signup 화면 path.
  static const String signup = '/signup';

  /// Signup 화면 name.
  static const String signupName = 'signup';

  /// 이메일 로그인 전용 화면 path (Phase 16.1 D-01).
  static const String emailLogin = '/login/email';

  /// 이메일 로그인 전용 화면 name (Phase 16.1 D-01).
  static const String emailLoginName = 'emailLogin';

  /// Forgot Password 화면 path.
  static const String forgotPassword = '/forgot-password';

  /// Forgot Password 화면 name.
  static const String forgotPasswordName = 'forgotPassword';

  /// Verify Email 화면 path.
  static const String verifyEmail = '/verify-email';

  /// Verify Email 화면 name.
  static const String verifyEmailName = 'verifyEmail';

  /// Onboarding 화면 path (Phase 10 D-01~D-08).
  static const String onboarding = '/onboarding';

  /// Onboarding 화면 name.
  static const String onboardingName = 'onboarding';

  /// 약관(이용약관) 상세 화면 path (Phase 10 D-21).
  static const String termsService = '/terms/service';

  /// 약관(이용약관) 상세 화면 name.
  static const String termsServiceName = 'termsService';

  /// 약관(개인정보처리방침) 상세 화면 path (Phase 10 D-21).
  static const String termsPrivacy = '/terms/privacy';

  /// 약관(개인정보처리방침) 상세 화면 name.
  static const String termsPrivacyName = 'termsPrivacy';

  /// 설정 화면 path (Phase 16 D-05).
  static const String settings = '/settings';

  /// 설정 화면 name (Phase 16 D-05).
  static const String settingsName = 'settings';
}
