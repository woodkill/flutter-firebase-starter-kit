import 'dart:convert';
import 'dart:io';

import '../launcher_names.dart'
    show GeneratorException, L10nConfig, readL10nConfig;
import 'arb_titles.dart';
import 'command_runner.dart';
import 'git_tree.dart';
import 'gradle_identity.dart';
import 'steps/app_names_step.dart';
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

/// 모든 단계가 끝난 뒤의 끝 요약 — 로그인 수단을 바꾸는 방법 · 커밋 안내 ·
/// golden 갱신 안내를 보인다.
///
/// 빈 줄 · [providersHintLine] 뒤에 [showCommitHint] 와 같은 커밋 안내를 보이고,
/// 이번 실행이 ko ARB 나 영어 ARB 를 바꿔 ko 실효 제목이 커밋된 상태와 다르면 빈
/// 줄 뒤 [AppNamesStep.goldenHintLine] 한 줄을 더한다. 바뀐 추적 파일 목록은 한 번만
/// 읽는다. 위저드는 golden 갱신 명령을 실행하지 않는다.
Future<void> showCompletionSummary(WizardContext context) async {
  context.terminal
    ..writeLine('')
    ..writeLine(providersHintLine);
  await _showChangedFiles(context, withGoldenHint: true);
}

/// 모든 단계가 끝난 뒤 바뀐 추적 파일 목록과 커밋 명령을 보여 준다.
///
/// 목록은 추적 파일의 미커밋 변경(삭제 · 이름 바꾸기 포함)에 앱 정체성 단계가
/// 옮긴 Kotlin 패키지 디렉터리의 새(추적하지 않는) 파일을 더한 것이다 — 그대로
/// 커밋하면 옛 Kotlin 파일 삭제와 새 파일 추가가 함께 들어가 빌드되는 저장소가
/// 된다. 위저드는 스테이징 · 커밋 · push 를 하지 않고 명령을 보이기만 한다. 목록이
/// 비면 아무것도 보이지 않는다. git 이 실패하면 [GitTreeException] 을 던진다.
Future<void> showCommitHint(WizardContext context) =>
    _showChangedFiles(context, withGoldenHint: false);

/// 바뀐 추적 파일 목록을 한 번 읽어 커밋 안내를 보이고, [withGoldenHint] 면
/// golden 갱신 안내도 같은 목록으로 판정해 보인다.
///
/// 목록 읽기는 [listChangedTrackedFiles] 한 번이다 — git 이 실패하면
/// [GitTreeException] 을 던진다.
Future<void> _showChangedFiles(
  WizardContext context, {
  required bool withGoldenHint,
}) async {
  final List<String> changed = await listChangedTrackedFiles(context);
  await _writeCommitHint(context, changed);
  if (withGoldenHint) await _writeGoldenHint(context, changed);
}

/// 바뀐 추적 파일 [changed] 에 옮긴 Kotlin 새 파일을 더해 커밋 안내를 쓴다.
///
/// 합친 목록이 비면 아무것도 쓰지 않는다.
Future<void> _writeCommitHint(
  WizardContext context,
  List<String> changed,
) async {
  final List<String> paths = <String>{
    ...changed,
    ...await _listMovedKotlinFiles(context),
  }.toList()..sort();
  if (paths.isEmpty) return;
  context.terminal
    ..writeLine('')
    ..writeLine(commitHintHeading);
  for (final path in paths) {
    context.terminal.writeLine('  $path');
  }
  context.terminal.writeCommand(
    'git add ${paths.map(quoteForShellDisplay).join(' ')} '
    '&& git commit -m "$commitHintMessage"',
  );
}

/// 바뀐 추적 파일 [changed] 에 ko ARB 나 영어(template) ARB 가 있고 golden 이
/// 다시 찍혀야 하면 빈 줄 뒤 [AppNamesStep.goldenHintLine] 한 줄을 쓴다.
///
/// 두 ARB 경로를 찾지 못하면(ARB 목록을 읽지 못하거나 ko ARB 가 없으면) 쓰지
/// 않는다. 판정은 [AppNamesStep.needsGoldenHint] 를 그대로 쓴다.
Future<void> _writeGoldenHint(
  WizardContext context,
  List<String> changed,
) async {
  final List<String> arbPaths = _findGoldenTitleArbPaths(context);
  if (!arbPaths.any(changed.contains)) return;
  if (!await AppNamesStep.needsGoldenHint(context)) return;
  context.terminal
    ..writeLine('')
    ..writeLine(AppNamesStep.goldenHintLine);
}

/// ko 실효 제목을 정하는 두 ARB — [AppNamesStep.goldenLocale] ARB 와 영어
/// (template) ARB — 의 저장소 상대 경로(git 출력과 같은 꼴).
///
/// ko ARB 가 없거나 목록을 읽지 못하면 빈 목록이다.
List<String> _findGoldenTitleArbPaths(WizardContext context) {
  try {
    final L10nConfig config = readL10nConfig(context.projectRoot);
    for (final LocalizedArb arb in listLocalizedArbs(context.projectRoot)) {
      if (arb.locale == AppNamesStep.goldenLocale) {
        return <String>[
          arb.relativePath,
          normalizeRepoPath(config.templatePath),
        ];
      }
    }
  } on GeneratorException {
    return const <String>[];
  }
  return const <String>[];
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
  final directory = '$kotlinSourceRoot/${applicationId.replaceAll('.', '/')}';
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
