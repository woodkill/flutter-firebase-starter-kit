import 'package:flutter/widgets.dart';

import '../../l10n/generated/app_localizations.dart';

/// [BuildContext]에서 [AppLocalizations]에 편리하게 접근하기 위한 확장.
///
/// `AppLocalizations.of(context)` 대신 `context.l10n`으로 간결하게 사용한다.
/// [ThemeX]의 `context.appColors` 패턴과 동일한 UX를 제공한다.
extension L10nX on BuildContext {
  /// 현재 로케일의 [AppLocalizations] 인스턴스를 반환한다.
  AppLocalizations get l10n => AppLocalizations.of(this);
}
