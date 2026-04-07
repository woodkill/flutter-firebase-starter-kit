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
  String get homeFirebaseConnected => '연결됨';

  @override
  String get homeFirebaseNotConnected => '연결 안 됨';

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
}
