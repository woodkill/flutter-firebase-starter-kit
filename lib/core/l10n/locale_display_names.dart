import 'package:flutter/widgets.dart' show Locale;

/// 지원하는 [Locale.languageCode]를 endonym(원어민 표기)으로 매핑하는 상수 맵.
///
/// 새로운 언어를 추가할 때는 이 맵에 항목을 추가하면 된다. 누락은
/// `test/core/l10n/locale_display_names_test.dart` 가
/// `AppLocalizations.supportedLocales` 와 대조해 RED 로 잡는다 (WR-04) —
/// [localeDisplayName] 의 폴백이 누락을 조용히 감추기 때문이다.
const Map<String, String> kLocaleEndonyms = <String, String>{
  'en': 'English',
  'ko': '한국어',
  'ja': '日本語',
};

/// [Locale]을 사용자 친화적인 endonym 표시 이름으로 반환한다.
///
/// 매핑은 [Locale.languageCode] 축에서만 이뤄진다 — script/country 변형은
/// 구분하지 않으므로 `Locale('fr', 'CA')` 도 `Locale('fr')` 과 같은 라벨을
/// 받는다. `zh_Hans` / `zh_Hant` 처럼 변형을 구분해야 하는 언어를 추가한다면
/// 키를 `toLanguageTag()` 축으로 올릴 것 — 그러지 않으면 언어 선택 UI 에
/// 동일 라벨이 중복된다 (그 드리프트는 테스트가 RED 로 잡는다).
///
/// 미등록 코드는 [Locale] 표기 전체가 아니라 [Locale.languageCode] 자체를
/// fallback 으로 반환한다 (`Locale('fr', 'CA')` → `'fr'`).
String localeDisplayName(Locale locale) =>
    kLocaleEndonyms[locale.languageCode] ?? locale.languageCode;
