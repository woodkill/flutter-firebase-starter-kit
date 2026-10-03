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

  /// 탈퇴 진행 화면 path (Phase 16.10 D-06).
  static const String withdrawalDisconnect = '/settings/withdraw';

  /// 탈퇴 진행 화면 name (Phase 16.10 D-06).
  static const String withdrawalDisconnectName = 'withdrawalDisconnect';

  /// 계정 정보 화면 path (Phase 17.1 D-02).
  static const String account = '/settings/account';

  /// 계정 정보 화면 name (Phase 17.1 D-02).
  static const String accountName = 'account';

  /// 개발자 · 데모 화면 path — release 빌드에는 등록되지 않는다 (Phase 17.1 D-14).
  static const String developerDemo = '/settings/developer';

  /// 개발자 · 데모 화면 name — release 빌드에는 등록되지 않는다 (Phase 17.1 D-14).
  static const String developerDemoName = 'developerDemo';

  // ---------------------------------------------------------------------------
  // 재인증 진입 표시 (R_EXTRA_G3_REAUTH_LOGIN_BOUNCE, quick 260916-p8d)
  // ---------------------------------------------------------------------------

  /// 재인증 목적 push 를 알리는 URL query key.
  ///
  /// 정식 로그인 완료 사용자가 재인증을 위해 push 로 연 로그인 흐름 화면을
  /// auth guard 분기 (6) 의 홈 되돌림에서 제외하는 데 쓴다. 값 비교는
  /// [hasReauthMarker] 로만 한다.
  static const String reauthQueryKey = 'reauth';

  /// 재인증 목적 push 를 알리는 URL query 값.
  static const String reauthQueryValue = '1';

  /// [path] 에 재인증 표시 query 를 붙인 location 을 만든다.
  ///
  /// 재인증 목적으로 로그인 흐름 화면을 **push** 할 때만 쓴다. 루트를 교체하는
  /// `go` 진입에는 붙이지 않는다. [path] 는 query 가 없는 [AppRoutes] path
  /// 상수여야 한다.
  ///
  /// 표시는 guard 의 "완료 사용자 홈 되돌림" 만 건너뛰게 하며, 이메일 검증 ·
  /// 약관 동의 게이트를 우회하는 수단이 아니다.
  static String buildReauthLocation(String path) {
    assert(!path.contains('?'), 'query 가 없는 path 상수만 허용한다: $path');
    return Uri(
      path: path,
      queryParameters: <String, String>{reauthQueryKey: reauthQueryValue},
    ).toString();
  }

  /// [uri] 에 재인증 표시가 있는지 판정한다.
  ///
  /// key 존재만으로는 참이 아니며, 값이 [reauthQueryValue] 와 정확히 같아야
  /// 한다 (strict equality). guard 와 화면 전달부가 같은 판정을 쓴다.
  static bool hasReauthMarker(Uri uri) =>
      uri.queryParameters[reauthQueryKey] == reauthQueryValue;

  /// [from] 에 재인증 표시가 있으면 [path] 에도 표시를 붙여 반환한다.
  ///
  /// 재인증 표시로 연 로그인 흐름 화면이 다음 화면을 push 할 때 표시를 이어
  /// 붙이는 데 쓴다. [from] 에 표시가 없으면(익명 · 미인증 진입) [path] 를
  /// 그대로 반환한다.
  static String forwardReauthMarker(String path, {required Uri from}) =>
      hasReauthMarker(from) ? buildReauthLocation(path) : path;

  /// [uri] 에서 재인증 표시 key 를 모두 지운 location 을 반환한다.
  ///
  /// auth guard 분기 (2.5) 가 익명 · 미인증 사용자의 로그인 흐름 진입에서
  /// 쓴다 — 정식 사용자가 아닌 사람에게 온 재인증 표시를 제거해 일반 로그인
  /// 화면이 열리게 한다 (quick 260924-phz).
  ///
  /// [reauthQueryKey] 는 값 개수와 무관하게 통째로 지운다. `queryParameters`
  /// 는 중복 key 의 마지막 값을 쓰므로(`reauth=0&reauth=1` → `'1'`) 일부만
  /// 지우면 [hasReauthMarker] 가 여전히 참이 되어 redirect loop 가 난다.
  ///
  /// 남는 query 가 없으면 `queryParameters` 에 null 을 넘긴다 — 빈 map 을
  /// 넘기면 `Uri` 가 `/login?` 처럼 물음표 꼬리를 남긴다.
  ///
  /// 다른 query 는 key 와 다중 값을 그대로 보존한다. 현재 로그인 흐름 경로의
  /// query 는 `reauth` 하나뿐이지만, 템플릿 사용자가 붙일 query 를 정규화가
  /// 조용히 삭제하지 않도록 표시만 뺀다. fragment 는 있을 때만 보존한다.
  /// 표시가 없는 [uri] 는 같은 path · query 그대로 돌려준다.
  static String removeReauthMarker(Uri uri) {
    final remaining = Map<String, List<String>>.of(uri.queryParametersAll)
      ..remove(reauthQueryKey);
    return Uri(
      path: uri.path,
      queryParameters: remaining.isEmpty ? null : remaining,
      fragment: uri.hasFragment ? uri.fragment : null,
    ).toString();
  }
}
