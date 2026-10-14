import 'dart:convert';
import 'dart:io';

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
  final List<String> missing = <String>[
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
  final List<String> addedLines = <String>[
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
/// 넣는다. 키가 없으면 [StateError] 를 던진다. 쓴 뒤 다시 파싱해 실패하면 원본을
/// 되돌리고 [FormatException] 을 던진다.
void replaceJsonString(String path, String key, String value) {
  final String original = File(path).readAsStringSync();
  final RegExpMatch? match = _jsonStringPattern(key).firstMatch(original);
  if (match == null) {
    throw StateError('$path 에 "$key" 문자열 값이 없습니다');
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
  final StringBuffer appended = StringBuffer();
  for (int i = 0; i < exampleLines.length; i++) {
    final RegExpMatch? match = _xcconfigVariablePattern.firstMatch(
      exampleLines[i],
    );
    if (match == null || !missing.contains(match.group(1))) continue;
    int commentStart = i;
    while (commentStart > 0 &&
        exampleLines[commentStart - 1].trimLeft().startsWith('//')) {
      commentStart--;
    }
    for (final String line in exampleLines.sublist(commentStart, i + 1)) {
      appended.writeln(line);
    }
  }

  final String original = File(userPath).readAsStringSync();
  final String separator = original.isEmpty || original.endsWith('\n')
      ? ''
      : '\n';
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
/// (`NAME =`)에는 공백 하나를 두고 쓴다. 변수가 없으면 [StateError], 값에 줄바꿈이
/// 있으면 [ArgumentError] 를 던진다.
void replaceXcconfigValue(String path, String name, String value) {
  if (value.contains('\n') || value.contains('\r')) {
    throw ArgumentError.value(value, 'value', '줄바꿈은 쓸 수 없습니다');
  }
  final String original = File(path).readAsStringSync();
  final RegExpMatch? match = _xcconfigValuePattern(name).firstMatch(original);
  if (match == null) {
    throw StateError('$path 에 $name 변수가 없습니다');
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
  final File temporary = File('$path.setup-tmp');
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
