// 「앱이 지원하지 않는 언어」 예시를 지원 언어 목록에서 고르는 시험 도우미.
//
// 시험이 미지원 언어 예시를 글자로 박아 두면(예: 프랑스어), 앱이 그 언어를
// 더하는 순간 예시가 지원 언어가 되어 시험이 실패한다. 이 도우미는 후보
// 가운데 지금 지원하지 않는 첫 언어를 고르므로 앱 언어를 더해도 예시를 잃지
// 않는다.

import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

/// 미지원 언어 예시 후보 — 앞에서부터 지원 여부를 본다.
const List<String> _candidateLanguageCodes = <String>[
  'fr',
  'de',
  'it',
  'nl',
  'sv',
  'pl',
];

/// 앱이 지원하지 않는 언어 코드를 고른다.
///
/// 앱이 언어를 더해도 「미지원 언어」 예시를 잃지 않게
/// [AppLocalizations.supportedLocales] 의 languageCode 에 없는 첫 후보를
/// 돌려준다. 후보가 모두 지원 언어면 [StateError] 를 던진다.
String pickUnsupportedLanguageCode() {
  final Set<String> supported = AppLocalizations.supportedLocales
      .map((locale) => locale.languageCode)
      .toSet();
  for (final String code in _candidateLanguageCodes) {
    if (!supported.contains(code)) return code;
  }
  throw StateError(
    '미지원 언어 후보(${_candidateLanguageCodes.join(', ')})가 모두 지원 '
    '언어다 — test/helpers/unsupported_locale.dart 의 후보 목록에 지원하지 '
    '않는 언어 코드를 더한다.',
  );
}
