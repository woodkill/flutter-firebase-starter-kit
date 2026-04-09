import 'package:flutter/widgets.dart' show Locale;

/// 지원하는 [Locale.languageCode]를 endonym(원어민 표기)으로 매핑하는 상수 맵.
///
/// 새로운 언어를 추가할 때는 이 맵에 항목을 추가하면 된다.
const Map<String, String> kLocaleEndonyms = <String, String>{
  'en': 'English',
  'ko': '한국어',
  'ja': '日本語',
};

/// [Locale]을 사용자 친화적인 endonym 표시 이름으로 반환한다.
///
/// 지원하지 않는 [Locale.languageCode]는 코드 자체를 fallback으로 반환한다.
String localeDisplayName(Locale locale) =>
    kLocaleEndonyms[locale.languageCode] ?? locale.languageCode;
