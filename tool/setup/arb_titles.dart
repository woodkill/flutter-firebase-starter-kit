// 위저드가 ARB 파일의 `appTitle`(언어별 앱 이름)을 다루는 도우미.
//
// 어느 ARB 를 어떤 locale 로 읽는가는 빌드 생성기(`tool/launcher_names.dart`)의
// 공개 함수를 그대로 쓴다 — 위저드가 묻는 파일 집합과 빌드가 읽는 집합이 같다.
import 'dart:convert';
import 'dart:io';

import '../launcher_names.dart'
    show
        L10nConfig,
        appTitleKey,
        listArbFiles,
        localeFromArbFileName,
        readL10nConfig;
import 'config_files.dart';
import 'git_tree.dart' show normalizeRepoPath;

/// template(영어) 밖 ARB 파일 하나 — locale 과 두 경로.
final class LocalizedArb {
  /// [locale] · [relativePath] · [absolutePath] 로 ARB 파일 하나를 나타낸다.
  const LocalizedArb(this.locale, this.relativePath, this.absolutePath);

  /// 파일 이름에서 읽은 locale(`ko` · `pt_BR` · `zh_Hant`).
  final String locale;

  /// 프로젝트 루트 기준 경로(`lib/l10n/app_ko.arb`) — 화면 문구에 쓴다.
  ///
  /// `arb-dir` 앞의 `./` 는 떼어 git 이 보이는 경로와 같은 꼴이다.
  final String relativePath;

  /// 읽기 · 쓰기에 쓰는 절대 경로.
  final String absolutePath;
}

/// [projectRoot] 의 `l10n.yaml` 이 가리키는 ARB 가운데 template 밖 파일을 돌려준다.
///
/// 순서는 파일 경로 순(ja → ko → pt → pt_BR → zh_Hant)이다. `l10n.yaml` 이
/// 없거나 · 파일 이름 꼴이 어긋나면 생성기와 같은 `GeneratorException` 을 그대로
/// 올린다 — 부르는 쪽이 그 문구를 사유로 보인다.
List<LocalizedArb> listLocalizedArbs(String projectRoot) {
  final L10nConfig config = readL10nConfig(projectRoot);
  return <LocalizedArb>[
    for (final file in listArbFiles(projectRoot, config))
      if (file.uri.pathSegments.last != config.templateArbFile)
        LocalizedArb(
          localeFromArbFileName(
            file.uri.pathSegments.last,
            config.arbFilePrefix,
            config.arbDir,
          ),
          normalizeRepoPath('${config.arbDir}/${file.uri.pathSegments.last}'),
          file.path,
        ),
  ];
}

/// [path] 가 JSON 객체로 읽히지 않으면 [displayPath] 를 적은 사유를 돌려준다 —
/// 읽히면 null.
///
/// 값 쓰기는 쓴 뒤 다시 파싱해 실패하면 되돌리므로, 깨진 파일은 쓰기 전에 걸러
/// 앞서 다른 파일만 바뀐 상태를 남기지 않는다. 문구에는 파일 내용을 싣지 않는다.
String? findInvalidJson(String path, String displayPath) {
  try {
    if (jsonDecode(File(path).readAsStringSync()) is Map<String, Object?>) {
      return null;
    }
    return '$displayPath 의 최상위가 JSON 객체가 아닙니다';
  } on FormatException catch (error) {
    return '$displayPath 이 올바른 JSON 이 아닙니다(${error.message}) — '
        '따옴표 · 쉼표 · 괄호를 고친 뒤 다시 실행하세요';
  }
}

/// ARB [absolutePath] 에 `appTitle` 을 쓸 수 없는 사유를 돌려준다 — 쓸 수 있으면 null.
///
/// 파일이 JSON 객체로 읽히지 않으면 [findInvalidJson] 의 사유를, `appTitle` 값이
/// 문자열이 아니면 그 사실을 [displayPath] 와 함께 돌려준다. 키가 없거나 값이
/// null 이면(생성기도 이름 없음으로 본다) 쓸 수 있다.
String? findInvalidArbTitle(String absolutePath, String displayPath) {
  final String? invalidJson = findInvalidJson(absolutePath, displayPath);
  if (invalidJson != null) return invalidJson;
  final Object? decoded = jsonDecode(File(absolutePath).readAsStringSync());
  if (decoded is Map<String, Object?>) {
    final Object? title = decoded[appTitleKey];
    if (title != null && title is! String) {
      return '$displayPath 의 $appTitleKey 이 문자열이 아닙니다';
    }
  }
  return null;
}

/// ARB [absolutePath] 의 `appTitle` 문자열 값을 읽는다.
///
/// 파일이 없거나 · 올바른 JSON 객체가 아니거나 · 키가 없거나 · 값이 문자열이
/// 아니면 null 이다.
String? readArbTitle(String absolutePath) {
  try {
    return parseArbTitle(File(absolutePath).readAsStringSync());
  } on FileSystemException {
    return null;
  }
}

/// ARB 본문 [source] 의 최상위 `appTitle` 문자열 값을 읽는다.
///
/// 올바른 JSON 객체가 아니거나 · 키가 없거나 · 값이 문자열이 아니면 null 이다.
String? parseArbTitle(String source) {
  try {
    final Object? decoded = jsonDecode(source);
    if (decoded is Map<String, Object?>) {
      final Object? title = decoded[appTitleKey];
      if (title is String) return title;
    }
    return null;
  } on FormatException {
    return null;
  }
}

/// ARB [absolutePath] 의 `appTitle` 을 [value] 로 쓴다 — 다른 키의 바이트는 그대로다.
///
/// 키가 없으면 [insertJsonString] 으로 `@@locale` 뒤에 넣고, 있으면 값의 타입과
/// 무관하게 [replaceJsonValue] 로 값을 바꾼다. 두 경로 모두 쓴 뒤 다시 파싱해
/// 실패하면 원본으로 되돌린다. 깨진 파일은 [findInvalidArbTitle] 로 먼저 거른다.
///
/// 값 교체는 원문에서 처음 나오는 같은 이름 키를 바꾸므로, 앞선 placeholder
/// 정의 안의 같은 이름 키나 겹친 최상위 키를 만나면 최상위 값이 그대로 남는다.
/// 그래서 쓴 뒤 최상위 값이 [value] 가 아니면 원본으로 되돌리고
/// [ConfigEditException] 을 던진다.
void writeArbTitle(String absolutePath, String value) {
  final String original = File(absolutePath).readAsStringSync();
  final Object? decoded = jsonDecode(original);
  if (decoded is Map<String, Object?> && decoded.containsKey(appTitleKey)) {
    replaceJsonValue(absolutePath, appTitleKey, value);
  } else {
    insertJsonString(absolutePath, appTitleKey, value);
  }
  if (readArbTitle(absolutePath) != value) {
    writeFileAtomically(absolutePath, original);
    throw ConfigEditException(
      '$absolutePath 의 최상위 $appTitleKey 을 바꾸지 못했습니다 — 같은 이름의 '
      '중첩 키(placeholder 정의 등)나 겹친 최상위 키를 정리한 뒤 다시 실행하세요',
    );
  }
}

/// ARB 상대 경로들을 화면 한 줄로 잇는다 — 첫 경로는 그대로, 나머지는 파일 이름만.
///
/// `['lib/l10n/app_ja.arb', 'lib/l10n/app_ko.arb']` →
/// `lib/l10n/app_ja.arb · app_ko.arb`.
String formatArbPaths(Iterable<String> relativePaths) {
  final List<String> paths = relativePaths.toList();
  if (paths.isEmpty) return '';
  return <String>[
    paths.first,
    for (final path in paths.skip(1)) path.substring(path.lastIndexOf('/') + 1),
  ].join(' · ');
}
