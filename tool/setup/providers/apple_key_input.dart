import 'dart:io';

import '../config_files.dart';
import '../wizard.dart';
import 'key_formats.dart';
import 'keyed_provider_step.dart';
import 'path_input.dart';

/// Apple 키(`.p8`)를 쓰는 자리 — 같은 키를 두 자리에 함께 쓸 수 있다.
enum AppleKeyUse {
  /// Sign in with Apple(Firebase Apple 로그인의 코드 흐름 설정).
  signInWithApple('Sign in with Apple'),

  /// App Check 의 DeviceCheck.
  deviceCheck('DeviceCheck');

  /// 화면 이름 [displayName] 으로 자리를 만든다.
  const AppleKeyUse(this.displayName);

  /// 질문 · 안내에 보일 자리 이름.
  final String displayName;
}

/// 한 실행 안에서만 쓰는 Apple 키 — 파일 경로는 담지 않는다.
///
/// [privateKey] 는 읽자마자 가림 함수에 등록한 `.p8` 파일 내용이다. 기본
/// `toString` 은 내용을 보이지 않는다.
final class AppleKey {
  /// Key ID [keyId] 와 `.p8` 내용 [privateKey] 로 만든다.
  const AppleKey({required this.keyId, required this.privateKey});

  /// Apple Key ID(대문자 영숫자 10자).
  final String keyId;

  /// `.p8` 파일 내용 — 화면 · 기록 · 파일로 내보내지 않는다.
  final String privateKey;
}

/// Apple 키를 만드는 할 일 줄 — 기능 · 서비스 이름만 쓴다.
const String appleKeyTodoLine =
    'APNs · DeviceCheck · Sign in with Apple 을 함께 켠 키 하나를 만들고 .p8 을 '
    '내려받기 — .p8 은 한 번만 내려받을 수 있습니다';

/// `.p8` 파일이 시작해야 하는 PEM 개인 키 머리 줄.
///
/// 저장소 스캔이 완형 머리 글자를 비밀 값으로 보지 않게 조각으로 잇는다.
const String pemPrivateKeyHeader =
    '-----BEGIN'
    ' PRIVATE KEY-----';

/// Team ID 를 읽고 쓰는 xcconfig 변수 이름.
const String developmentTeamVariable = 'DEVELOPMENT_TEAM';

/// Key ID 질문 문구.
const String appleKeyIdQuestion = 'Key ID';

/// Team ID 질문 문구.
const String appleTeamIdQuestion = 'Apple Team ID';

/// Apple 내려받기 파일 이름에서 Key ID 를 꺼내는 정규식 — group 1 = Key ID.
final RegExp _authKeyFileName = RegExp(r'^AuthKey_([A-Z0-9]{10})\.p8$');

/// [use] 자리에 쓸 Apple 키를 받는다 — 받지 못하면 null.
///
/// 세션의 이 자리에 이미 키가 있으면 묻지 않고 그 키를 돌려준다. 다른 자리에
/// 키가 있으면 `같은 키 (Key ID <X>)` / `다른 키 입력` 을 고르게 한다(기본은
/// 같은 키). 새로 받을 때는 `.p8` 파일 경로를 묻고(`~` 는 홈 디렉터리), 파일이
/// 있고 읽히며 PEM 개인 키 머리로 시작하면 그 내용을 바로 가림 함수에 등록한 뒤
/// Key ID 를 묻는다(파일 이름이 `AuthKey_<10자>.p8` 이면 그 10자가 기본값). 경로 ·
/// Key ID 는 [maxKeyAttempts] 회까지 그 값만 다시 묻고, 넘거나 입력 끝이면 null
/// 이다.
///
/// 내용은 메모리(세션)에만 두고 경로는 config · 세션에 저장하지 않는다. 경로를
/// 다시 묻는 까닭 줄에는 홈 디렉터리를 `~` 로 줄인 경로를 보인다(입력한 답은
/// 다른 질문의 답처럼 실행 기록에 남는다). DeviceCheck 를 실제로 넣었다는 세션
/// 표시는 DeviceCheck 단계가 켠다.
Future<AppleKey?> askAppleKey(
  WizardContext context, {
  required AppleKeyUse use,
}) async {
  final Map<AppleKeyUse, AppleKey> keys = context.session.appleKeys;
  final AppleKey? existing = keys[use];
  if (existing != null) return existing;
  final AppleKey? other = _findOtherKey(keys, use);
  if (other != null) {
    final int? choice = context.terminal.choose(
      '${use.displayName} 에 쓸 Apple 키',
      <String>['같은 키 (Key ID ${other.keyId})', '다른 키 입력'],
    );
    if (choice == null) return null;
    if (choice == 0) {
      keys[use] = other;
      return other;
    }
  }
  final _KeyFile? file = _askKeyFile(context, use);
  if (file == null) return null;
  final String? keyId = _askKeyId(context, _suggestKeyId(file.name));
  if (keyId == null) return null;
  final key = AppleKey(keyId: keyId, privateKey: file.content);
  keys[use] = key;
  return key;
}

/// Apple Team ID 를 정한다 — 정하지 못하면 null.
///
/// 세션에 있으면 그 값을, 없으면 그 flavor xcconfig 의 [developmentTeamVariable]
/// 이 형식에 맞을 때 그 값을 쓴다(질문 · 쓰기 0). 비었거나 형식이 아니면 한 번
/// 묻고([maxKeyAttempts] 회까지 형식 검사) xcconfig 에 쓴다. 정한 값은 세션에
/// 두어 같은 실행에서 다시 묻지 않는다.
///
/// xcconfig 파일이 없으면 [FileSystemException], 변수 줄이 없으면 묻기 전에
/// [ConfigEditException] 을 던진다 — 위저드가 실행 실패로 보인다.
Future<String?> resolveTeamId(WizardContext context) async {
  final String? known = context.session.appleTeamId;
  if (known != null) return known;
  final String path = context.resolve(context.paths.xcconfig);
  final String? configured = readXcconfigValue(path, developmentTeamVariable);
  if (configured == null) {
    throw ConfigEditException('$path 에 $developmentTeamVariable 변수가 없습니다');
  }
  if (appleTeamId.matches(configured)) {
    context.session.appleTeamId = configured;
    return configured;
  }
  context.terminal.writeLine(
    '  ${context.paths.xcconfig} 의 $developmentTeamVariable 가 비어 있거나 '
    '형식에 맞지 않습니다 — 받은 값을 거기에 씁니다',
  );
  final String? value = _askFormatted(
    context,
    appleTeamIdQuestion,
    appleTeamId,
  );
  if (value == null) return null;
  replaceXcconfigValue(path, developmentTeamVariable, value);
  context.session.appleTeamId = value;
  return value;
}

/// 읽은 `.p8` 파일 — 파일 이름과 내용.
final class _KeyFile {
  const _KeyFile(this.name, this.content);

  /// 경로의 마지막 조각(파일 이름).
  final String name;

  /// 가림 함수에 등록한 파일 내용.
  final String content;
}

/// [keys] 에서 [use] 가 아닌 자리의 키를 찾는다 — 없으면 null.
AppleKey? _findOtherKey(Map<AppleKeyUse, AppleKey> keys, AppleKeyUse use) {
  for (final AppleKeyUse other in AppleKeyUse.values) {
    if (other == use) continue;
    final AppleKey? key = keys[other];
    if (key != null) return key;
  }
  return null;
}

/// `.p8` 파일 경로를 묻고 내용을 읽는다 — 맞지 않으면 까닭 한 줄 뒤 경로만 다시.
///
/// 까닭 줄에는 홈 디렉터리를 `~` 로 줄인 경로만 보이고 내용은 보이지 않는다.
/// 내용은 PEM 개인 키 머리로 시작할 때만 가림 함수에 등록하고 돌려준다.
_KeyFile? _askKeyFile(WizardContext context, AppleKeyUse use) {
  for (var attempt = 0; attempt < maxKeyAttempts; attempt++) {
    final String? answer = context.terminal.ask(
      '${use.displayName} 용 .p8 파일 경로',
    );
    if (answer == null) return null;
    final String path = expandInputPath(context, answer.trim());
    if (path.isEmpty) {
      context.terminal.writeLine('  .p8 파일 경로를 입력하세요');
      continue;
    }
    final file = File(path);
    final String shownPath = describePath(context, path);
    if (!file.existsSync()) {
      context.terminal.writeLine('  파일이 없습니다 — $shownPath');
      continue;
    }
    final String content;
    try {
      content = file.readAsStringSync();
    } on FileSystemException {
      context.terminal.writeLine('  파일을 읽지 못했습니다 — $shownPath');
      continue;
    }
    if (!content.trimLeft().startsWith(pemPrivateKeyHeader)) {
      context.terminal.writeLine('  .p8 개인 키 파일이 아닙니다 — $shownPath');
      continue;
    }
    context.redactor.register(content);
    return _KeyFile(path.substring(path.lastIndexOf('/') + 1), content);
  }
  return null;
}

/// 파일 이름 [fileName] 이 `AuthKey_<Key ID>.p8` 꼴이면 그 Key ID — 아니면 null.
String? _suggestKeyId(String fileName) {
  final String? candidate = _authKeyFileName.firstMatch(fileName)?.group(1);
  return candidate != null && appleKeyId.matches(candidate) ? candidate : null;
}

/// Key ID 를 묻는다 — [suggestion] 은 Enter 기본값.
String? _askKeyId(WizardContext context, String? suggestion) => _askFormatted(
  context,
  appleKeyIdQuestion,
  appleKeyId,
  defaultValue: suggestion,
);

/// [question] 으로 값을 묻고 [format] 에 맞을 때까지 [maxKeyAttempts] 회 다시
/// 묻는다 — 넘거나 입력 끝이면 null.
String? _askFormatted(
  WizardContext context,
  String question,
  KeyFormat format, {
  String? defaultValue,
}) {
  for (var attempt = 0; attempt < maxKeyAttempts; attempt++) {
    final String? answer = context.terminal.ask(
      question,
      defaultValue: defaultValue,
    );
    if (answer == null) return null;
    final String value = answer.trim();
    if (format.matches(value)) return value;
    context.terminal.writeLine(
      '  ${format.label} 형식이 맞지 않습니다 — ${value.length}자 · '
      '규칙: ${format.description}',
    );
  }
  return null;
}
