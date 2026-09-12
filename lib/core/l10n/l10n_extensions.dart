import 'package:flutter/widgets.dart';

import '../../l10n/generated/app_localizations.dart';

/// [BuildContext]에서 [AppLocalizations]에 편리하게 접근하기 위한 확장.
///
/// `AppLocalizations.of(context)` 대신 `context.l10n`으로 간결하게 사용한다.
/// `ThemeX`(`lib/core/theme/theme_extensions.dart`)의 `context.appColors` 와
/// 같은 호출 형태를 제공하지만, **폴백 동작까지 같지는 않다** — 테마 토큰은
/// 기본값으로 대체할 수 있는 반면 번역 문자열은 대체할 데이터가 없다.
extension L10nX on BuildContext {
  /// 현재 로케일의 [AppLocalizations] 인스턴스를 반환한다.
  ///
  /// 상위 위젯에 `AppLocalizations.localizationsDelegates` 가 없으면
  /// `l10n.yaml` 의 `nullable-getter: false` 설정 때문에 생성 코드가
  /// `Null check operator used on a null value` 로 죽는다 — 원인도 해법도
  /// 스택에 드러나지 않으므로, debug 빌드에서는 [assert] 로 원인을 지목한다
  /// (WR-05). 폴백은 불가능하다: 번역 데이터 자체가 없다.
  AppLocalizations get l10n {
    assert(
      Localizations.of<AppLocalizations>(this, AppLocalizations) != null,
      'context.l10n 사용처 상위에 AppLocalizations delegate 가 없다. '
      'MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, '
      'supportedLocales: AppLocalizations.supportedLocales) 를 설정할 것.',
    );
    return AppLocalizations.of(this);
  }
}
