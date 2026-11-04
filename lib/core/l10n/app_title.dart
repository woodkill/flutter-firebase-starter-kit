import '../../l10n/generated/app_localizations.dart';
import '../config/app_config.dart';

/// flavor 이름 → 앱 표시 이름 접미사(prod 는 빈 문자열).
///
/// 설정 위저드의 `tool/setup/flavor.dart` `Flavor.displayNameSuffix` 와 빌드
/// 때 홈 화면 이름을 만드는 생성기의 표와 같은 값이다 — 시험이 세 표를
/// 대조한다.
const Map<String, String> kFlavorDisplayNameSuffixes = <String, String>{
  'dev': ' Dev',
  'stg': ' Stg',
  'prod': '',
};

/// 앱 안 제목을 정한다.
///
/// [App] 의 `onGenerateTitle`(OS 최근 앱 화면 · 접근성 표면)과 홈 AppBar 가
/// 같은 식을 쓴다. 제목 글자는 앱 언어의 ARB `appTitle` 이다. config 이름
/// [appName] 이 [flavor] 의 접미사([kFlavorDisplayNameSuffixes])로 끝날 때만
/// 같은 접미사를 붙인다 — 홈 화면 이름이 다른 언어 이름에 접미사를 붙이는
/// 조건과 같아서, 표시 이름에서 접미사를 지운 앱은 앱 안 제목에도 붙지 않는다.
/// [appName] 이 비었거나(시험) [flavor] 가 비었거나 모르는 값이면 접미사 없이
/// `appTitle` 이다. config 이름 글자 자체는 제목이 되지 않는다.
///
/// 홈 화면 이름(OS)은 기기 언어를 따르므로, 앱 안에서 기기와 다른 언어를
/// 고르면 앱 안 제목 · 최근 앱은 고른 언어, 홈 화면 이름은 기기 언어가 된다.
///
/// [appName] · [flavor] 인자는 시험용이다 — 기본값은 dart-define const
/// [AppConfig.appName] · [AppConfig.flavor] 다.
String resolveAppTitle(
  AppLocalizations l10n, {
  String appName = AppConfig.appName,
  String flavor = AppConfig.flavor,
}) {
  final String suffix = kFlavorDisplayNameSuffixes[flavor] ?? '';
  if (suffix.isNotEmpty && appName.endsWith(suffix)) {
    return '${l10n.appTitle}$suffix';
  }
  return l10n.appTitle;
}
