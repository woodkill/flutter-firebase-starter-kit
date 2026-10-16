import 'dart:convert';
import 'dart:io';

import 'command_runner.dart';
import 'git_tree.dart';
import 'gradle_identity.dart';
import 'steps/identity_step.dart';
import 'wizard.dart';

/// 끝 요약의 머리 줄.
const String commitHintHeading = '위저드 실행으로 바뀐 추적 파일이 있습니다 — 확인한 뒤 직접 커밋하세요:';

/// 끝 요약이 안내하는 커밋 메시지.
const String commitHintMessage = 'chore: 설정 위저드 결과 반영';

/// Kotlin 소스 디렉터리의 앞부분 — 뒤에 패키지 경로가 붙는다.
const String kotlinSourceRoot = 'android/app/src/main/kotlin';

/// 끝 요약에서 로그인 수단을 바꾸는 방법을 알리는 줄.
const String providersHintLine = '로그인 수단을 바꾸려면: ./setup.sh --providers';

/// 모든 단계가 끝난 뒤의 끝 요약 — 로그인 수단을 바꾸는 방법과 커밋 안내를 보인다.
///
/// 빈 줄 · [providersHintLine] 뒤에 [showCommitHint] 를 부른다.
Future<void> showCompletionSummary(WizardContext context) async {
  context.terminal
    ..writeLine('')
    ..writeLine(providersHintLine);
  await showCommitHint(context);
}

/// 모든 단계가 끝난 뒤 바뀐 추적 파일 목록과 커밋 명령을 보여 준다.
///
/// 목록은 추적 파일의 미커밋 변경(삭제 · 이름 바꾸기 포함)에 앱 정체성 단계가
/// 옮긴 Kotlin 패키지 디렉터리의 새(추적하지 않는) 파일을 더한 것이다 — 그대로
/// 커밋하면 옛 Kotlin 파일 삭제와 새 파일 추가가 함께 들어가 빌드되는 저장소가
/// 된다. 위저드는 스테이징 · 커밋 · push 를 하지 않고 명령을 보이기만 한다. 목록이
/// 비면 아무것도 보이지 않는다. git 이 실패하면 [GitTreeException] 을 던진다.
Future<void> showCommitHint(WizardContext context) async {
  final List<String> paths = <String>{
    ...await listChangedTrackedFiles(context),
    ...await _listMovedKotlinFiles(context),
  }.toList()..sort();
  if (paths.isEmpty) return;
  context.terminal
    ..writeLine('')
    ..writeLine(commitHintHeading);
  for (final String path in paths) {
    context.terminal.writeLine('  $path');
  }
  context.terminal.writeCommand(
    'git add ${paths.map(quoteForShellDisplay).join(' ')} '
    '&& git commit -m "$commitHintMessage"',
  );
}

/// 앱 정체성이 옮긴 Kotlin 패키지 디렉터리의 추적하지 않는 파일을 모은다.
///
/// 디렉터리는 Gradle 의 `applicationId` 를 `.` → `/` 로 바꾼 경로다. 파일 ·
/// 줄 · 디렉터리가 없으면 빈 목록이다.
Future<List<String>> _listMovedKotlinFiles(WizardContext context) async {
  final String? applicationId = readGradleApplicationId(
    context.resolve(IdentityStep.gradlePath),
  );
  if (applicationId == null) return const <String>[];
  final String directory =
      '$kotlinSourceRoot/${applicationId.replaceAll('.', '/')}';
  if (!Directory(context.resolve(directory)).existsSync()) {
    return const <String>[];
  }
  final CommandResult result = await context.runner.capture(
    buildUntrackedFilesCommand(
      directory,
      workingDirectory: context.projectRoot,
    ),
  );
  if (!result.isSuccess) {
    throw GitTreeException(
      '$directory 의 새 파일 목록을 읽지 못했습니다 (종료 코드 ${result.exitCode})',
      result: result,
    );
  }
  return <String>[
    for (final String line in const LineSplitter().convert(result.stdout))
      if (line.startsWith('?? ')) _unquote(line.substring(3)),
  ];
}

/// [directory] 아래 추적하지 않는 파일을 하나씩 보이는 git 명령을 만든다.
Command buildUntrackedFilesCommand(
  String directory, {
  String? workingDirectory,
}) => Command('git', <String>[
  'status',
  '--porcelain',
  '--untracked-files=all',
  '--',
  directory,
], workingDirectory: workingDirectory);

/// git 이 큰따옴표로 감싼 경로의 따옴표만 뗀다(Kotlin 경로는 이스케이프가 없다).
String _unquote(String path) =>
    path.length >= 2 && path.startsWith('"') && path.endsWith('"')
    ? path.substring(1, path.length - 1)
    : path;
