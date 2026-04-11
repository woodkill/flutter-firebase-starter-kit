// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get commonOk => '확인';

  @override
  String get commonCancel => '취소';

  @override
  String get commonRetry => '재시도';

  @override
  String get commonClose => '닫기';

  @override
  String get commonSave => '저장';

  @override
  String get commonDelete => '삭제';

  @override
  String get commonEdit => '편집';

  @override
  String get commonLoading => '불러오는 중';

  @override
  String get homeEnvironmentInfo => '환경 정보';

  @override
  String get homeThemeMode => '테마 모드';

  @override
  String get homeLanguage => '언어';

  @override
  String get homeThemeLight => '라이트';

  @override
  String get homeThemeSystem => '시스템';

  @override
  String get homeThemeDark => '다크';

  @override
  String get homeColorPalette => '컬러 팔레트';

  @override
  String get homeTypography => '타이포그래피';

  @override
  String get homeSpacing => '간격';

  @override
  String get homeBuildEnvironment => '빌드 환경';

  @override
  String get homeEnvFlavor => '플레이버';

  @override
  String get homeEnvAppName => '앱 이름';

  @override
  String get homeEnvFirebase => 'Firebase';

  @override
  String get homeEnvFirebaseProjectId => 'Firebase 프로젝트 ID';

  @override
  String get homeFirebaseConnected => '연결됨';

  @override
  String get homeFirebaseNotConnected => '연결 안 됨';

  @override
  String get homeFirebaseStatusConnected => 'Firebase 연결됨';

  @override
  String get homeFirebaseStatusNotConnected => 'Firebase 연결되지 않음';

  @override
  String get languageChanged => '언어가 변경되었습니다';

  @override
  String get errorNetworkTimeout => '연결 시간이 초과되었습니다. 다시 시도해 주세요.';

  @override
  String get errorNoInternet => '인터넷 연결이 없습니다.';

  @override
  String get errorRequestTimeout => '요청 시간이 초과되었습니다. 다시 시도해 주세요.';

  @override
  String get errorInvalidCredentials => '이메일 또는 비밀번호가 올바르지 않습니다.';

  @override
  String get errorUserNotFound => '사용자를 찾을 수 없습니다.';

  @override
  String get errorEmailAlreadyInUse => '이미 사용 중인 이메일입니다.';

  @override
  String get errorWeakPassword => '비밀번호가 너무 약합니다.';

  @override
  String get errorSessionExpired => '세션이 만료되었습니다. 다시 로그인해 주세요.';

  @override
  String get errorInternalServer => '문제가 발생했습니다. 나중에 다시 시도해 주세요.';

  @override
  String get errorServiceUnavailable => '서비스를 일시적으로 사용할 수 없습니다.';

  @override
  String get errorInvalidEmail => '올바른 이메일 주소가 아닙니다.';

  @override
  String get errorUserDisabled => '비활성화된 계정입니다. 관리자에게 문의해 주세요.';

  @override
  String get errorTooManyRequests => '요청이 너무 많습니다. 잠시 후 다시 시도해 주세요.';

  @override
  String get errorUnknown => '알 수 없는 오류가 발생했습니다.';

  @override
  String get errorEmailRequired => '이메일을 입력해 주세요.';

  @override
  String get errorInvalidEmailFormat => '올바른 이메일 형식을 입력해 주세요.';

  @override
  String get errorPasswordTooShort => '비밀번호는 8자 이상이어야 합니다.';

  @override
  String get errorDisplayNameRequired => '이름을 입력해 주세요.';

  @override
  String get errorDisplayNameTooLong => '이름은 32자 이하로 입력해 주세요.';

  @override
  String get errorNotFoundTitle => '페이지를 찾을 수 없습니다';

  @override
  String get errorNotFoundBody => '요청하신 페이지가 존재하지 않습니다.';

  @override
  String get errorNotFoundGoHomeCta => '홈으로';

  @override
  String get authLoginTitle => '로그인';

  @override
  String get authSignupTitle => '계정 만들기';

  @override
  String get authForgotTitle => '비밀번호 재설정';

  @override
  String get authLoginEmailLabel => '이메일';

  @override
  String get authLoginPasswordLabel => '비밀번호';

  @override
  String get authSignupDisplayNameLabel => '이름';

  @override
  String get authForgotDescription => '가입하신 이메일로 비밀번호 재설정 메일을 보내드립니다.';

  @override
  String get authLoginCta => '로그인';

  @override
  String get authSignupCta => '가입하기';

  @override
  String get authForgotCta => '재설정 메일 보내기';

  @override
  String get authLoginForgotPassword => '비밀번호를 잊으셨나요?';

  @override
  String get authLoginNoAccount => '계정이 없으신가요? 가입하기';

  @override
  String get authSignupHasAccount => '이미 계정이 있으신가요? 로그인';

  @override
  String get authForgotSent => '재설정 메일이 발송되었습니다. 받은편지함을 확인해 주세요.';

  @override
  String get authAccountSectionTitle => '계정';

  @override
  String get authAccountDisplayName => '표시 이름';

  @override
  String get authAccountEmail => '이메일';

  @override
  String get authAccountPhotoUrl => '프로필 사진';

  @override
  String get authAccountUid => '사용자 ID';

  @override
  String get authAccountCreatedAt => '가입일';

  @override
  String get authAccountProviders => '로그인 수단';

  @override
  String get authAccountProviderEmailPassword => '이메일 / 비밀번호';

  @override
  String get authAccountCopyToken => 'ID 토큰 복사';

  @override
  String get authAccountCopied => '클립보드에 복사되었습니다.';

  @override
  String get authAccountSignOut => '로그아웃';

  @override
  String get debugAuthTokenUnavailable => 'ID 토큰을 사용할 수 없음 (debug)';

  @override
  String get authLogoutConfirmTitle => '로그아웃';

  @override
  String get authLogoutConfirmMessage => '로그아웃 하시겠습니까?';

  @override
  String get authShowPassword => '비밀번호 표시';

  @override
  String get authHidePassword => '비밀번호 숨기기';

  @override
  String get authVerifyEmailTitle => '이메일 인증';

  @override
  String authVerifyEmailDescription(String email) {
    return '인증 메일을 $email(으)로 보냈습니다. 메일의 링크를 클릭하여 인증을 완료해 주세요.';
  }

  @override
  String get authVerifyEmailSpamHint => '메일이 보이지 않으면 스팸함을 확인해 주세요.';

  @override
  String get authVerifyEmailCheck => '인증 확인';

  @override
  String get authVerifyEmailResend => '인증 메일 재전송';

  @override
  String authVerifyEmailResendCooldown(int seconds) {
    return '재전송 가능 ($seconds초 후)';
  }

  @override
  String get authVerifyEmailLogout => '다른 계정으로 로그인';

  @override
  String get authVerifyEmailSuccess => '이메일 인증이 완료되었습니다.';

  @override
  String get splashPlaceholderTitle => '스플래시';

  @override
  String get splashPlaceholderStub => 'Phase 10 플레이스홀더';

  @override
  String showcaseItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count개 항목',
      one: '1개 항목',
      zero: '항목 없음',
    );
    return '$_temp0';
  }

  @override
  String get showcaseDateFormat => '날짜 형식';

  @override
  String get showcaseNumberFormat => '숫자 형식';

  @override
  String get showcaseCurrentLocale => '현재 로케일';

  @override
  String get showcaseDateShort => '짧은 형식';

  @override
  String get showcaseDateLong => '긴 형식';

  @override
  String get showcaseDateTime => '시간';

  @override
  String get showcaseNumberCompact => '축약';

  @override
  String get showcaseNumberDecimal => '소수 구분';

  @override
  String get authOrDivider => '또는';

  @override
  String get authGoogleSignIn => 'Google로 로그인';

  @override
  String get errorAccountExistsWithDifferentCredential =>
      '이 이메일은 다른 방식으로 가입되어 있습니다. 비밀번호로 로그인해 주세요.';

  @override
  String get authAccountProviderGoogle => 'Google';

  @override
  String get authAppleSignIn => 'Apple로 로그인';

  @override
  String get authAccountProviderApple => 'Apple';
}
