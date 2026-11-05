import 'dart:convert';

import 'command_runner.dart';
import 'wizard.dart';

/// git 작업 트리 상태를 읽지 못했을 때 던지는 예외.
///
/// 저장소가 아니거나 git 이 실패한 경우다. 호출한 단계가 실패로 보일지 정한다.
final class GitTreeException implements Exception {
  /// [message] 와 실패한 명령 결과 [result] 로 예외를 만든다.
  const GitTreeException(this.message, {this.result});

  /// 사용자에게 보일 설명.
  final String message;

  /// 실패한 git 명령의 결과(출력 원문). 없으면 null.
  final CommandResult? result;

  @override
  String toString() => message;
}

/// 추적 파일의 미커밋 변경만 보는 git 명령 — 추적하지 않는 파일은 세지 않는다.
const Command gitStatusCommand = Command('git', <String>[
  'status',
  '--porcelain',
  '--untracked-files=no',
]);

/// 커밋하지 않은 변경이 있는 추적 파일의 저장소 상대 경로를 git 이 보인 순서로 모은다.
///
/// 이름 바꾸기 · 복사 줄은 원래 경로와 새 경로를 모두 넣는다. git 이 실패하면
/// [GitTreeException] 을 던진다.
Future<List<String>> listChangedTrackedFiles(WizardContext context) async {
  final CommandResult result = await context.runner.capture(
    Command(
      gitStatusCommand.executable,
      gitStatusCommand.arguments,
      workingDirectory: context.projectRoot,
    ),
  );
  if (!result.isSuccess) {
    throw GitTreeException(
      'git 작업 트리 상태를 읽지 못했습니다 (종료 코드 ${result.exitCode})',
      result: result,
    );
  }
  final paths = <String>[];
  for (final String line in const LineSplitter().convert(result.stdout)) {
    for (final String path in _parseStatusPaths(line)) {
      if (!paths.contains(path)) paths.add(path);
    }
  }
  return paths;
}

/// [relativePaths] 가운데 커밋하지 않은 변경이 있는 추적 파일을 찾는다.
///
/// 항목이 파일이면 같은 경로를, 디렉터리면(끝 `/` 는 떼고 비교) 그 아래 경로
/// (`<항목>/` 로 시작)를 잡는다 — 앞부분만 같은 형제 경로는 잡지 않는다. 단계가
/// 고칠 파일만 넘기므로 다른 파일의 변경 · 위저드 앞 단계의 변경은 막지 않는다.
/// git 이 실패하면 [GitTreeException] 을 던진다.
Future<List<String>> findDirtyTrackedFiles(
  WizardContext context,
  List<String> relativePaths,
) async {
  final targets = <String>[
    for (final String path in relativePaths)
      if (normalizeRepoPath(path).isNotEmpty) normalizeRepoPath(path),
  ];
  final List<String> changed = await listChangedTrackedFiles(context);
  return <String>[
    for (final String path in changed)
      if (targets.any(
        (String target) => path == target || path.startsWith('$target/'),
      ))
        path,
  ];
}

/// 저장소 상대 경로를 git 출력과 같은 꼴로 맞춘다 — 앞 `./` 와 끝 `/` 를 뗀다.
///
/// `l10n.yaml` 의 `arb-dir: ./lib/l10n` 처럼 사람이 쓴 경로를 git 이 보이는
/// `lib/l10n/…` 와 비교하거나 git 에 넘길 때 쓴다.
String normalizeRepoPath(String path) {
  String normalized = path.trim();
  while (normalized.startsWith('./')) {
    normalized = normalized.substring(2);
  }
  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

/// 커밋된 상태(HEAD)의 [relativePath] 파일 내용을 보이는 git 명령을 만든다.
///
/// 출력은 파일 원문 전체라 실행 기록에는 본문 대신 길이만 남긴다
/// ([Command.isOutputLogged] false) — 비밀 값은 아니므로 민감 표시는 하지 않는다.
Command buildShowCommittedFileCommand(
  String relativePath, {
  String? workingDirectory,
}) => Command(
  'git',
  <String>['show', 'HEAD:${normalizeRepoPath(relativePath)}'],
  workingDirectory: workingDirectory,
  isOutputLogged: false,
);

/// 커밋된 상태(HEAD)의 [relativePath] 파일 내용을 읽는다.
///
/// 저장소가 아니거나 · HEAD 가 없거나 · HEAD 에 그 파일이 없는 등 git 이
/// 실패하면 null 이다 — 부르는 쪽이 「알 수 없음」 으로 다룬다.
Future<String?> readCommittedFile(
  WizardContext context,
  String relativePath,
) async {
  final CommandResult result = await context.runner.capture(
    buildShowCommittedFileCommand(
      relativePath,
      workingDirectory: context.projectRoot,
    ),
  );
  return result.isSuccess ? result.stdout : null;
}

/// `git status --porcelain` 한 줄에서 경로를 꺼낸다 — `XY 경로` 또는 `XY 원래 -> 새`.
List<String> _parseStatusPaths(String line) {
  if (line.length < 4) return const <String>[];
  final String status = line.substring(0, 2);
  final String rest = line.substring(3);
  final bool isRenameOrCopy = status.contains('R') || status.contains('C');
  if (!isRenameOrCopy) return <String>[_unquotePath(rest)];

  const arrow = ' -> ';
  if (rest.startsWith('"')) {
    final int close = _findClosingQuote(rest);
    if (close < 0) return <String>[_unquotePath(rest)];
    final String tail = rest.substring(close + 1);
    return <String>[
      _unquotePath(rest.substring(0, close + 1)),
      _unquotePath(
        tail.startsWith(arrow) ? tail.substring(arrow.length) : tail,
      ),
    ];
  }
  final int arrowIndex = rest.indexOf(arrow);
  if (arrowIndex < 0) return <String>[_unquotePath(rest)];
  return <String>[
    _unquotePath(rest.substring(0, arrowIndex)),
    _unquotePath(rest.substring(arrowIndex + arrow.length)),
  ];
}

/// 여는 따옴표 뒤에서 이스케이프되지 않은 닫는 따옴표의 위치를 찾는다 — 없으면 -1.
int _findClosingQuote(String text) {
  for (var i = 1; i < text.length; i++) {
    if (text[i] == r'\') {
      i++;
    } else if (text[i] == '"') {
      return i;
    }
  }
  return -1;
}

/// git 이 C 문자열로 감싼 경로(`"…"` · `\ooo` 8진 바이트 · `\"` 등)를 푼다.
String _unquotePath(String token) {
  if (token.length < 2 || !token.startsWith('"') || !token.endsWith('"')) {
    return token;
  }
  final String inner = token.substring(1, token.length - 1);
  final bytes = <int>[];
  const escapes = <String, int>{
    'a': 7,
    'b': 8,
    't': 9,
    'n': 10,
    'v': 11,
    'f': 12,
    'r': 13,
    '"': 34,
    r'\': 92,
  };
  for (var i = 0; i < inner.length; i++) {
    final String char = inner[i];
    if (char != r'\' || i + 1 >= inner.length) {
      bytes.addAll(utf8.encode(char));
      continue;
    }
    final String next = inner[i + 1];
    final String octal = i + 3 < inner.length
        ? inner.substring(i + 1, i + 4)
        : '';
    if (RegExp(r'^[0-7]{3}$').hasMatch(octal)) {
      bytes.add(int.parse(octal, radix: 8));
      i += 3;
    } else {
      bytes.add(escapes[next] ?? next.codeUnitAt(0));
      i += 1;
    }
  }
  return utf8.decode(bytes, allowMalformed: true);
}
