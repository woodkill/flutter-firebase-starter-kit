import '../../l10n/generated/app_localizations.dart';
import '../config/app_config.dart';

/// 앱 표시 제목을 정한다 (Phase 17.1 D-12).
///
/// [App] 의 `onGenerateTitle`(OS 최근 앱 화면 · 접근성 표면)과 홈 AppBar 가
/// 같은 식을 쓴다. dart-define 으로 `appName` 이 주입되면 그 값을(브랜드명
/// 고정 의도), 비어 있으면 로케일을 따르는 ARB `appTitle` 을 돌려준다.
///
/// [appName] 인자는 테스트용이다 — 기본값은 dart-define const
/// [AppConfig.appName] 이다.
String resolveAppTitle(
  AppLocalizations l10n, {
  String appName = AppConfig.appName,
}) => appName.isEmpty ? l10n.appTitle : appName;
