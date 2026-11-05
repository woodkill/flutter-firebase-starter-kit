import 'dart:convert';
import 'dart:io';

/// 설정 파일에서 고칠 자리를 찾지 못해 쓰지 않았음을 알리는 예외.
///
/// 키 · 변수 · 값 자리가 없거나 하나로 정해지지 않으면 파일을 그대로 두고 이
/// 예외를 던진다. 단계는 [message] 를 실패 사유로 그대로 보인다 — 버그로 난
/// [Error] 와 섞이지 않게 [Exception] 으로 둔다.
final class ConfigEditException implements Exception {
  /// [message] 를 사유로 예외를 만든다.
  const ConfigEditException(this.message);

  /// 실패 사유 — 고치려던 파일 경로와 찾지 못한 자리.
  final String message;

  @override
  String toString() => 'ConfigEditException: $message';
}

/// xcconfig 변수 줄을 알아보는 정규식 — group 1 = 변수 이름.
final RegExp _xcconfigVariablePattern = RegExp(
  r'^\s*([A-Z_][A-Z0-9_]*)\s*=',
  multiLine: true,
);

/// example JSON 에는 있고 사용자 JSON 에는 없는 키를 example 순서로 찾는다.
///
/// 두 파일 모두 `jsonDecode` 로 읽어 최상위 키를 비교한다. 사용자 파일이 JSON
/// 객체가 아니면 [FormatException] 을 던진다.
Set<String> findMissingJsonKeys({
  required String examplePath,
  required String userPath,
}) {
  final Map<String, Object?> example = _readJsonObject(examplePath);
  final Map<String, Object?> user = _readJsonObject(userPath);
  return <String>{
    for (final String key in example.keys)
      if (!user.containsKey(key)) key,
  };
}

/// 사용자 JSON 에 빠진 키를 example 값으로 더한다 — 기존 줄의 바이트는 그대로다.
///
/// 닫는 `}` 앞 마지막 값 끝에 쉼표 하나를 붙이고, 그 줄의 들여쓰기로 빠진 키를
/// example 순서대로 `"<키>": <example 값>` 줄로 넣는다. 빈 객체면 2칸 들여쓰기를
/// 쓴다. 빠진 키가 없으면 파일을 쓰지 않는다. 쓴 뒤 다시 파싱해 실패하면 원본을
/// 되돌리고 [FormatException] 을 던진다.
void addMissingJsonKeys({
  required String examplePath,
  required String userPath,
}) {
  final Map<String, Object?> example = _readJsonObject(examplePath);
  final String original = File(userPath).readAsStringSync();
  final Map<String, Object?> user = _decodeJsonObject(original, userPath);
  final missing = <String>[
    for (final String key in example.keys)
      if (!user.containsKey(key)) key,
  ];
  if (missing.isEmpty) return;

  final int closeIndex = original.lastIndexOf('}');
  if (closeIndex < 0) {
    throw FormatException('닫는 } 를 찾지 못했습니다', userPath);
  }
  final int lastValueIndex = _findLastNonSpaceIndex(original, closeIndex);
  final bool isEmptyObject =
      lastValueIndex >= 0 && original[lastValueIndex] == '{';
  final String indent = isEmptyObject
      ? '  '
      : _readLineIndent(original, lastValueIndex);
  final addedLines = <String>[
    for (final String key in missing)
      '\n$indent${jsonEncode(key)}: ${jsonEncode(example[key])}',
  ];

  final String updated;
  if (isEmptyObject) {
    // 빈 객체는 여는 { 뒤에 넣고 닫는 } 를 새 줄로 둔다.
    updated =
        '${original.substring(0, lastValueIndex + 1)}'
        '${addedLines.join(',')}\n'
        '${original.substring(closeIndex)}';
  } else {
    updated =
        '${original.substring(0, lastValueIndex + 1)},'
        '${addedLines.join(',')}'
        '${original.substring(lastValueIndex + 1)}';
  }
  _writeJsonVerified(userPath, updated, original);
}

/// [path] JSON 의 [key] 문자열 값을 읽는다 — 키가 없거나 문자열이 아니면 null.
///
/// `"<key>": "<값>"` 꼴의 첫 일치를 쓴다(값 치환과 같은 정규식).
String? readJsonString(String path, String key) {
  final RegExpMatch? match = _jsonStringPattern(
    key,
  ).firstMatch(File(path).readAsStringSync());
  if (match == null) return null;
  final String body = match.group(2)!;
  try {
    final Object? decoded = jsonDecode('"$body"');
    return decoded is String ? decoded : body;
  } on FormatException {
    return body;
  }
}

/// [path] JSON 의 [key] 문자열 값만 [value] 로 바꾼다 — 나머지 바이트는 그대로다.
///
/// 키 · 구분자 · 따옴표는 원래 글자를 남기고 값 본문만 `jsonEncode` 로 이스케이프해
/// 넣는다. 키가 없으면 [ConfigEditException] 을 던진다. 쓴 뒤 다시 파싱해 실패하면 원본을
/// 되돌리고 [FormatException] 을 던진다.
void replaceJsonString(String path, String key, String value) {
  final String original = File(path).readAsStringSync();
  final RegExpMatch? match = _jsonStringPattern(key).firstMatch(original);
  if (match == null) {
    throw ConfigEditException('$path 에 "$key" 문자열 값이 없습니다');
  }
  final String encoded = jsonEncode(value);
  final String body = encoded.substring(1, encoded.length - 1);
  final String updated = original.replaceRange(
    match.start,
    match.end,
    '${match.group(1)}$body${match.group(3)}',
  );
  _writeJsonVerified(path, updated, original);
}

/// [path] JSON 에 없는 [key] 를 문자열 [value] 로 더한다 — 기존 바이트는 그대로다.
///
/// 넣는 자리는 `"@@locale"` 값의 닫는 따옴표 바로 뒤다. 그 자리에 `,` · 빈 줄 ·
/// `@@locale` 줄과 같은 들여쓰기의 `"<key>": "<값>"` 을 넣으므로, 원래 뒤따르던
/// 쉼표와 글자는 새 줄 끝으로 밀린다(`@@locale` 이 마지막 키였어도 같은 꼴).
/// `@@locale` 이 없으면 [addMissingJsonKeys] 와 같이 닫는 `}` 앞에 넣는다. 값은
/// `jsonEncode` 로 이스케이프한다. 키가 이미 있으면 [ConfigEditException], 파일이
/// JSON 객체가 아니면 [FormatException] 을 던지고 파일은 그대로 둔다. 쓴 뒤 다시
/// 파싱해 실패하면 원본을 되돌리고 [FormatException] 을 던진다.
void insertJsonString(String path, String key, String value) {
  final String original = File(path).readAsStringSync();
  final Map<String, Object?> decoded = _decodeJsonObject(original, path);
  if (decoded.containsKey(key)) {
    throw ConfigEditException('$path 에 "$key" 가 이미 있습니다');
  }
  final entry = '${jsonEncode(key)}: ${jsonEncode(value)}';
  final RegExpMatch? localeMatch = _jsonStringPattern(
    '@@locale',
  ).firstMatch(original);

  final String updated;
  if (localeMatch != null) {
    final String indent = _readLineIndent(original, localeMatch.start);
    updated = original.replaceRange(
      localeMatch.end,
      localeMatch.end,
      ',\n\n$indent$entry',
    );
  } else {
    final int closeIndex = original.lastIndexOf('}');
    if (closeIndex < 0) {
      throw FormatException('닫는 } 를 찾지 못했습니다', path);
    }
    final int lastValueIndex = _findLastNonSpaceIndex(original, closeIndex);
    final bool isEmptyObject =
        lastValueIndex >= 0 && original[lastValueIndex] == '{';
    if (isEmptyObject) {
      updated =
          '${original.substring(0, lastValueIndex + 1)}'
          '\n  $entry\n'
          '${original.substring(closeIndex)}';
    } else {
      final String indent = _readLineIndent(original, lastValueIndex);
      updated =
          '${original.substring(0, lastValueIndex + 1)},'
          '\n$indent$entry'
          '${original.substring(lastValueIndex + 1)}';
    }
  }
  _writeJsonVerified(path, updated, original);
}

/// [path] JSON 의 [key] 값을 그 타입과 무관하게 문자열 [value] 로 바꾼다.
///
/// `"<key>":` 첫 일치 뒤의 JSON 값 토큰 하나(문자열 · 숫자 · 불 · null · 객체 ·
/// 배열)를 끝까지 읽어 통째로 `jsonEncode(value)` 로 바꾼다 — 키 · 구분자 · 다른
/// 바이트는 그대로다. 객체 · 배열은 괄호 깊이를 세되 안의 문자열은 이스케이프를
/// 건너 통째로 넘겨, 문자열 안의 괄호 · 따옴표가 깊이에 끼지 않는다. 키가 없거나
/// 값 끝을 찾지 못하면 [ConfigEditException] 을 던지고 파일은 그대로 둔다. 쓴 뒤
/// 다시 파싱해 실패하면 원본을 되돌리고 [FormatException] 을 던진다.
void replaceJsonValue(String path, String key, String value) {
  final String original = File(path).readAsStringSync();
  final RegExpMatch? match = RegExp(
    '${RegExp.escape(jsonEncode(key))}\\s*:\\s*',
  ).firstMatch(original);
  if (match == null) {
    throw ConfigEditException('$path 에 "$key" 값이 없습니다');
  }
  final int? valueEnd = _findJsonValueEnd(original, match.end);
  if (valueEnd == null) {
    throw ConfigEditException('$path 의 "$key" 값 끝을 찾지 못했습니다');
  }
  final String updated = original.replaceRange(
    match.end,
    valueEnd,
    jsonEncode(value),
  );
  _writeJsonVerified(path, updated, original);
}

/// example xcconfig 에는 있고 사용자 xcconfig 에는 없는 변수를 example 순서로 찾는다.
Set<String> findMissingXcconfigVars({
  required String examplePath,
  required String userPath,
}) {
  final Set<String> userVariables = _readXcconfigVariables(
    File(userPath).readAsStringSync(),
  );
  return <String>{
    for (final String name in _readXcconfigVariables(
      File(examplePath).readAsStringSync(),
    ))
      if (!userVariables.contains(name)) name,
  };
}

/// 사용자 xcconfig 에 빠진 변수를 example 줄 그대로 파일 끝에 붙인다.
///
/// 빠진 변수마다 example 에서 그 변수 줄 바로 위의 `//` 주석 줄 묶음과 변수 줄을
/// example 순서대로 붙인다. 기존 줄은 그대로이고, 끝 개행이 없으면 먼저 하나
/// 붙인다. 빠진 변수가 없으면 파일을 쓰지 않는다.
void addMissingXcconfigVars({
  required String examplePath,
  required String userPath,
}) {
  final Set<String> missing = findMissingXcconfigVars(
    examplePath: examplePath,
    userPath: userPath,
  );
  if (missing.isEmpty) return;

  final List<String> exampleLines = const LineSplitter().convert(
    File(examplePath).readAsStringSync(),
  );
  final appended = StringBuffer();
  for (var i = 0; i < exampleLines.length; i++) {
    final RegExpMatch? match = _xcconfigVariablePattern.firstMatch(
      exampleLines[i],
    );
    if (match == null || !missing.contains(match.group(1))) continue;
    var commentStart = i;
    while (commentStart > 0 &&
        exampleLines[commentStart - 1].trimLeft().startsWith('//')) {
      commentStart--;
    }
    for (final String line in exampleLines.sublist(commentStart, i + 1)) {
      appended.writeln(line);
    }
  }

  final String original = File(userPath).readAsStringSync();
  final separator = original.isEmpty || original.endsWith('\n') ? '' : '\n';
  writeFileAtomically(userPath, '$original$separator$appended');
}

/// [path] xcconfig 의 [name] 변수 값을 읽는다 — 앞뒤 공백을 뗀 값, 없으면 null.
String? readXcconfigValue(String path, String name) {
  final RegExpMatch? match = _xcconfigValuePattern(
    name,
  ).firstMatch(File(path).readAsStringSync());
  if (match == null) return null;
  return match.group(3)!.trim();
}

/// [path] xcconfig 의 [name] 변수 줄 값만 [value] 로 바꾼다 — 다른 줄은 그대로다.
///
/// 변수 이름 · `=` 와 그 뒤 공백은 원래 글자를 남긴다. 값이 비어 있던 줄
/// (`NAME =`)에는 공백 하나를 두고 쓴다. 변수가 없으면 [ConfigEditException], 값에 줄바꿈이
/// 있으면 [ArgumentError] 를 던진다.
void replaceXcconfigValue(String path, String name, String value) {
  if (value.contains('\n') || value.contains('\r')) {
    throw ArgumentError.value(value, 'value', '줄바꿈은 쓸 수 없습니다');
  }
  final String original = File(path).readAsStringSync();
  final RegExpMatch? match = _xcconfigValuePattern(name).firstMatch(original);
  if (match == null) {
    throw ConfigEditException('$path 에 $name 변수가 없습니다');
  }
  final String spacing = match.group(2)!.isEmpty && value.isNotEmpty
      ? ' '
      : match.group(2)!;
  writeFileAtomically(
    path,
    original.replaceRange(
      match.start,
      match.end,
      '${match.group(1)}$spacing$value',
    ),
  );
}

/// [content] 를 같은 디렉터리의 임시 파일에 쓴 뒤 [path] 로 이름을 바꾼다.
///
/// 쓰기 도중 실패해도 [path] 의 원래 내용이 반쯤 쓰인 채 남지 않는다. 실패하면
/// 임시 파일을 지우고 예외를 다시 던진다.
void writeFileAtomically(String path, String content) {
  final temporary = File('$path.setup-tmp');
  try {
    temporary.writeAsStringSync(content, flush: true);
    temporary.renameSync(path);
  } on FileSystemException {
    if (temporary.existsSync()) temporary.deleteSync();
    rethrow;
  }
}

/// `"<key>": "<값>"` 꼴을 찾는 정규식 — group 1 = 키 · 구분자 · 여는 따옴표,
/// group 2 = 값 본문(이스케이프 포함), group 3 = 닫는 따옴표.
RegExp _jsonStringPattern(String key) => RegExp(
  '(${RegExp.escape(jsonEncode(key))}\\s*:\\s*")'
  r'((?:[^"\\]|\\.)*)'
  '(")',
);

/// `NAME = 값` 줄을 찾는 정규식 — group 1 = 이름 · `=`, group 2 = `=` 뒤 공백,
/// group 3 = 값(줄 끝까지).
RegExp _xcconfigValuePattern(String name) => RegExp(
  '^(${RegExp.escape(name)}[ \\t]*=)([ \\t]*)([^\\r\\n]*)',
  multiLine: true,
);

/// xcconfig 본문의 변수 이름을 나오는 순서로 모은다.
Set<String> _readXcconfigVariables(String content) => <String>{
  for (final RegExpMatch match in _xcconfigVariablePattern.allMatches(content))
    match.group(1)!,
};

/// [path] 를 JSON 객체로 읽는다 — 객체가 아니면 [FormatException].
Map<String, Object?> _readJsonObject(String path) =>
    _decodeJsonObject(File(path).readAsStringSync(), path);

/// [content] 를 JSON 객체로 해석한다 — 객체가 아니면 [FormatException].
Map<String, Object?> _decodeJsonObject(String content, String path) {
  final Object? decoded = jsonDecode(content);
  if (decoded is! Map<String, Object?>) {
    throw FormatException('최상위가 JSON 객체가 아닙니다', path);
  }
  return decoded;
}

/// [updated] 를 쓴 뒤 다시 파싱하고, 실패하면 [original] 로 되돌린다.
void _writeJsonVerified(String path, String updated, String original) {
  writeFileAtomically(path, updated);
  try {
    _decodeJsonObject(File(path).readAsStringSync(), path);
  } on FormatException {
    writeFileAtomically(path, original);
    rethrow;
  }
}

/// [text] 의 [start] 에서 시작하는 JSON 값 토큰 바로 뒤 위치를 찾는다 — 없으면 null.
///
/// 문자열은 닫는 따옴표까지, 객체 · 배열은 짝 괄호까지, 그 밖(숫자 · 불 · null)은
/// `,` · `}` · `]` · 공백 앞까지다.
int? _findJsonValueEnd(String text, int start) {
  if (start >= text.length) return null;
  final String first = text[start];
  if (first == '"') return _findJsonStringEnd(text, start);
  if (first == '{' || first == '[') {
    var depth = 0;
    var i = start;
    while (i < text.length) {
      final String char = text[i];
      if (char == '"') {
        final int? stringEnd = _findJsonStringEnd(text, i);
        if (stringEnd == null) return null;
        i = stringEnd;
        continue;
      }
      if (char == '{' || char == '[') depth++;
      if (char == '}' || char == ']') {
        depth--;
        if (depth == 0) return i + 1;
      }
      i++;
    }
    return null;
  }
  var i = start;
  while (i < text.length &&
      !',}]'.contains(text[i]) &&
      text[i].trim().isNotEmpty) {
    i++;
  }
  return i == start ? null : i;
}

/// [text] 의 [start] 에 있는 여는 따옴표의 문자열 바로 뒤 위치 — 닫히지 않으면 null.
int? _findJsonStringEnd(String text, int start) {
  var i = start + 1;
  while (i < text.length) {
    final String char = text[i];
    if (char == r'\') {
      i += 2;
      continue;
    }
    if (char == '"') return i + 1;
    i++;
  }
  return null;
}

/// [end] 앞에서 공백이 아닌 마지막 글자의 위치를 찾는다 — 없으면 -1.
int _findLastNonSpaceIndex(String text, int end) {
  for (int i = end - 1; i >= 0; i--) {
    if (text[i].trim().isNotEmpty) return i;
  }
  return -1;
}

/// [index] 글자가 있는 줄의 앞 들여쓰기를 읽는다.
String _readLineIndent(String text, int index) {
  final int lineStart = text.lastIndexOf('\n', index) + 1;
  final Match? match = RegExp(
    r'[ \t]*',
  ).matchAsPrefix(text.substring(lineStart));
  return match?.group(0) ?? '';
}
