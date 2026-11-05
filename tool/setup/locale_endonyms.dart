// 위저드가 언어 표시(`ko (한국어)`)에 쓰는 원어 이름을 lib 의 표에서 읽는다.
//
// 그 표(`kLocaleEndonyms`)는 Flutter 를 import 하는 앱 소스라 위저드가 import 할
// 수 없다. 그래서 소스 글자를 정규식으로 읽는다 — 원어 이름의 원본은 lib 표
// 한 곳이고, 언어를 더할 때 위저드 쪽 파일은 고치지 않는다.
import 'dart:io';

/// 원어 이름 표가 있는 lib 소스 경로(프로젝트 루트 기준).
const String localeEndonymsPath = 'lib/core/l10n/locale_display_names.dart';

/// 표 선언의 시작 — `kLocaleEndonyms` 다음 `=`.
final RegExp _declarationPattern = RegExp(r'\bkLocaleEndonyms\s*=');

/// 표 안 항목 하나 — group 1 = 코드, group 2 = 원어 이름(작은따옴표 안 글자).
final RegExp _entryPattern = RegExp(r"'([^']*)'\s*:\s*'([^']*)'");

/// [projectRoot] 의 [localeEndonymsPath] 에서 코드 → 원어 이름 표를 읽는다.
///
/// `kLocaleEndonyms` 선언부터 다음 `};` 까지의 `'<코드>': '<이름>'` 항목을 모은다.
/// 값에 작은따옴표가 든 항목은 다루지 않는다. 파일이 없거나 · 선언이 없거나 ·
/// 읽다 실패하면 빈 맵이다 — 언어 표시가 코드만으로 바뀔 뿐 단계를 막지 않는다.
Map<String, String> readLocaleEndonyms(String projectRoot) {
  final String source;
  try {
    source = File('$projectRoot/$localeEndonymsPath').readAsStringSync();
  } on FileSystemException {
    return <String, String>{};
  }
  final RegExpMatch? declaration = _declarationPattern.firstMatch(source);
  if (declaration == null) return <String, String>{};
  final int end = source.indexOf('};', declaration.end);
  if (end < 0) return <String, String>{};
  return <String, String>{
    for (final RegExpMatch entry in _entryPattern.allMatches(
      source.substring(declaration.end, end),
    ))
      entry.group(1)!: entry.group(2)!,
  };
}

/// [locale] 의 언어 표시를 만든다 — 원어 이름이 있으면 `ko (한국어)`, 없으면 `ko`.
///
/// 찾는 순서는 `pt-BR` 꼴 → [locale] 그대로(`pt_BR`) → 언어 부분(`pt`)이다. 그래서
/// 표에 변형 항목이 없으면 `pt_BR (Português)` · `zh_Hant (中文)` 처럼 언어 부분의
/// 이름을 쓴다.
String formatLocaleLabel(String locale, Map<String, String> endonyms) {
  final String? name =
      endonyms[locale.replaceAll('_', '-')] ??
      endonyms[locale] ??
      endonyms[locale.split('_').first];
  return name == null ? locale : '$locale ($name)';
}
