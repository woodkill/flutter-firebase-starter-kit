// ignore_for_file: avoid_print

import 'dart:io';

import 'package:args/args.dart';

// ---------------------------------------------------------------------------
// 현재 프로젝트의 고정 값 (변경 원본)
// ---------------------------------------------------------------------------

/// 현재 pubspec.yaml의 name 필드.
const currentPackageName = 'flutter_starter_kit';

/// 현재 organization (역순 도메인).
const currentOrg = 'com.slimpumpkin';

/// 현재 Android applicationId / namespace.
const currentAndroidPackage = 'com.slimpumpkin.flutter_starter_kit';

/// 현재 iOS Bundle ID (Runner).
const currentIosBundleId = 'com.slimpumpkin.flutterStarterKit';

/// 현재 appName 기본값 (config에서 suffix 제거 전 원본).
const currentAppName = 'StarterKit';

// ---------------------------------------------------------------------------
// 공개 모델
// ---------------------------------------------------------------------------

/// 변경 타입.
enum ChangeType {
  /// 파일 내 문자열 치환.
  replace,

  /// 파일/디렉토리 이동.
  move,
}

/// 파일 변경 정보를 담는 클래스.
class FileChange {
  /// 파일 변경 정보를 생성한다.
  const FileChange({
    required this.filePath,
    required this.type,
    required this.description,
    required this.oldValue,
    required this.newValue,
  });

  /// 대상 파일 경로.
  final String filePath;

  /// 변경 타입.
  final ChangeType type;

  /// 변경 설명.
  final String description;

  /// 변경 전 값.
  final String oldValue;

  /// 변경 후 값.
  final String newValue;
}

/// 입력 유효성 검증 결과.
class ValidateResult {
  /// 유효성 검증 결과를 생성한다.
  const ValidateResult({required this.isValid, this.error});

  /// 유효한지 여부.
  final bool isValid;

  /// 에러 메시지 (유효하지 않을 때).
  final String? error;
}

// ---------------------------------------------------------------------------
// 유효성 검증
// ---------------------------------------------------------------------------

/// org 역순 도메인 형식 정규식.
///
/// 예: `com.example`, `com.example.subdivision`
final _orgPattern = RegExp(r'^[a-z][a-z0-9]*(\.[a-z][a-z0-9]*)+$');

/// name snake_case 형식 정규식.
///
/// 예: `my_app`, `app`, `cool_app2`
final _namePattern = RegExp(r'^[a-z][a-z0-9]*(_[a-z0-9]+)*$');

/// 입력 유효성을 검증한다.
///
/// [org]는 역순 도메인 형식(예: `com.example`),
/// [name]은 snake_case 형식(예: `my_app`)이어야 한다.
ValidateResult validateInputs(String org, String name) {
  if (!_orgPattern.hasMatch(org)) {
    return ValidateResult(
      isValid: false,
      error:
          "Invalid org format: '$org'\n"
          'Use reverse domain format (e.g., com.example)',
    );
  }

  if (!_namePattern.hasMatch(name)) {
    return ValidateResult(
      isValid: false,
      error:
          "Invalid name format: '$name'\n"
          'Use snake_case format (e.g., my_app)',
    );
  }

  return const ValidateResult(isValid: true);
}

// ---------------------------------------------------------------------------
// 문자열 변환 유틸리티
// ---------------------------------------------------------------------------

/// snake_case를 UpperCamelCase로 변환한다.
///
/// 예: `my_app` -> `MyApp`
String toUpperCamelCase(String snakeCase) {
  return snakeCase.split('_').map(_capitalize).join();
}

/// snake_case를 lowerCamelCase로 변환한다.
///
/// 예: `my_app` -> `myApp`
String toLowerCamelCase(String snakeCase) {
  final parts = snakeCase.split('_');
  if (parts.isEmpty) return snakeCase;
  return parts.first + parts.skip(1).map(_capitalize).join();
}

/// snake_case를 Title Case(공백 구분)로 변환한다.
///
/// 예: `my_app` -> `My App`
String toTitleCase(String snakeCase) {
  return snakeCase.split('_').map(_capitalize).join(' ');
}

/// 문자열의 첫 글자를 대문자로 변환한다.
String _capitalize(String s) {
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1);
}

// ---------------------------------------------------------------------------
// 변경 사항 수집
// ---------------------------------------------------------------------------

/// 프로젝트 내 변경 대상을 수집한다.
///
/// [projectRoot]에서 현재 패키지 정보를 [newOrg]과 [newName]으로 변경할
/// 대상 파일과 변경 내용 목록을 반환한다.
/// 실제 파일 수정은 하지 않는다.
List<FileChange> collectChanges(
  String projectRoot,
  String newOrg,
  String newName,
) {
  final changes = <FileChange>[];
  final newAndroidPackage = '$newOrg.$newName';
  final newIosBundleId = '$newOrg.${toLowerCamelCase(newName)}';
  final newAppName = toTitleCase(newName);

  // 1. pubspec.yaml
  _collectPubspecChanges(projectRoot, newName, changes);

  // 2. android/app/build.gradle.kts
  _collectGradleChanges(projectRoot, newAndroidPackage, changes);

  // 3. Kotlin 디렉토리 이동 + package 선언 변경
  _collectKotlinChanges(projectRoot, newOrg, newName, changes);

  // 4. iOS project.pbxproj
  _collectIosChanges(projectRoot, newIosBundleId, changes);

  // 5. lib/**/*.dart import 경로
  _collectDartImportChanges('$projectRoot/lib', newName, changes);

  // 6. test/**/*.dart import 경로
  _collectDartImportChanges('$projectRoot/test', newName, changes);

  // 7. config/*.json appName
  _collectConfigChanges(projectRoot, newAppName, changes);

  return changes;
}

/// pubspec.yaml의 name 필드 변경을 수집한다.
void _collectPubspecChanges(
  String projectRoot,
  String newName,
  List<FileChange> changes,
) {
  final file = File('$projectRoot/pubspec.yaml');
  if (!file.existsSync()) return;

  changes.add(
    FileChange(
      filePath: file.path,
      type: ChangeType.replace,
      description: 'pubspec.yaml name 필드 변경',
      oldValue: 'name: $currentPackageName',
      newValue: 'name: $newName',
    ),
  );
}

/// build.gradle.kts의 namespace와 applicationId 변경을 수집한다.
void _collectGradleChanges(
  String projectRoot,
  String newAndroidPackage,
  List<FileChange> changes,
) {
  final file = File('$projectRoot/android/app/build.gradle.kts');
  if (!file.existsSync()) return;

  changes.add(
    FileChange(
      filePath: file.path,
      type: ChangeType.replace,
      description: 'namespace + applicationId 변경',
      oldValue: currentAndroidPackage,
      newValue: newAndroidPackage,
    ),
  );
}

/// Kotlin 디렉토리 이동과 package 선언 변경을 수집한다.
void _collectKotlinChanges(
  String projectRoot,
  String newOrg,
  String newName,
  List<FileChange> changes,
) {
  final currentOrgPath = currentOrg.replaceAll('.', '/');
  final newOrgPath = newOrg.replaceAll('.', '/');
  final kotlinBase = '$projectRoot/android/app/src/main/kotlin';
  final currentDir = '$kotlinBase/$currentOrgPath/$currentPackageName';
  final newDir = '$kotlinBase/$newOrgPath/$newName';

  if (!Directory(currentDir).existsSync()) return;

  // 디렉토리 이동
  changes.add(
    FileChange(
      filePath: currentDir,
      type: ChangeType.move,
      description: 'Kotlin 소스 디렉토리 이동',
      oldValue: '$currentOrgPath/$currentPackageName',
      newValue: '$newOrgPath/$newName',
    ),
  );

  // MainActivity.kt package 선언 변경
  final mainActivity = File('$currentDir/MainActivity.kt');
  if (mainActivity.existsSync()) {
    final newAndroidPackage = '$newOrg.$newName';
    changes.add(
      FileChange(
        filePath: '$newDir/MainActivity.kt',
        type: ChangeType.replace,
        description: 'Kotlin package 선언 변경',
        oldValue: 'package $currentAndroidPackage',
        newValue: 'package $newAndroidPackage',
      ),
    );
  }
}

/// iOS project.pbxproj의 PRODUCT_BUNDLE_IDENTIFIER 변경을 수집한다.
void _collectIosChanges(
  String projectRoot,
  String newIosBundleId,
  List<FileChange> changes,
) {
  final file = File('$projectRoot/ios/Runner.xcodeproj/project.pbxproj');
  if (!file.existsSync()) return;

  final content = file.readAsStringSync();

  // Runner 타겟 (suffix 없음)
  final runnerPattern = RegExp(
    r'PRODUCT_BUNDLE_IDENTIFIER = '
    '${RegExp.escape(currentIosBundleId)};',
  );
  final runnerMatches = runnerPattern.allMatches(content).length;

  if (runnerMatches > 0) {
    changes.add(
      FileChange(
        filePath: file.path,
        type: ChangeType.replace,
        description: 'Runner PRODUCT_BUNDLE_IDENTIFIER 변경 ($runnerMatches곳)',
        oldValue: currentIosBundleId,
        newValue: newIosBundleId,
      ),
    );
  }

  // RunnerTests 타겟 (.RunnerTests suffix)
  final testsPattern = RegExp(
    r'PRODUCT_BUNDLE_IDENTIFIER = '
    '${RegExp.escape(currentIosBundleId)}.RunnerTests;',
  );
  final testsMatches = testsPattern.allMatches(content).length;

  if (testsMatches > 0) {
    changes.add(
      FileChange(
        filePath: file.path,
        type: ChangeType.replace,
        description:
            'RunnerTests PRODUCT_BUNDLE_IDENTIFIER 변경 ($testsMatches곳)',
        oldValue: '$currentIosBundleId.RunnerTests',
        newValue: '$newIosBundleId.RunnerTests',
      ),
    );
  }
}

/// Dart 파일의 package import 경로 변경을 수집한다.
void _collectDartImportChanges(
  String directoryPath,
  String newName,
  List<FileChange> changes,
) {
  final dir = Directory(directoryPath);
  if (!dir.existsSync()) return;

  final dartFiles = dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  for (final file in dartFiles) {
    final content = file.readAsStringSync();
    if (content.contains('package:$currentPackageName/')) {
      changes.add(
        FileChange(
          filePath: file.path,
          type: ChangeType.replace,
          description: 'package import 경로 변경',
          oldValue: 'package:$currentPackageName/',
          newValue: 'package:$newName/',
        ),
      );
    }
  }
}

/// config/*.json의 appName 필드 변경을 수집한다.
void _collectConfigChanges(
  String projectRoot,
  String newAppName,
  List<FileChange> changes,
) {
  final configDir = Directory('$projectRoot/config');
  if (!configDir.existsSync()) return;

  final jsonFiles = configDir.listSync().whereType<File>().where(
    (f) => f.path.endsWith('.json'),
  );

  for (final file in jsonFiles) {
    final content = file.readAsStringSync();
    // appName 패턴: "appName": "..." -- 현재 값에 suffix가 붙을 수 있음
    // JSON 파일마다 공백 유무가 다를 수 있으므로 매칭된 전체 문자열을 사용
    final pattern = RegExp(r'"appName"\s*:\s*"([^"]*)"');
    final match = pattern.firstMatch(content);
    if (match != null) {
      final fullMatch = match.group(0)!;
      final currentValue = match.group(1)!;
      // flavor suffix 추출 (예: "StarterKit Dev" -> " Dev")
      final suffix = currentValue.startsWith(currentAppName)
          ? currentValue.substring(currentAppName.length)
          : '';
      changes.add(
        FileChange(
          filePath: file.path,
          type: ChangeType.replace,
          description: 'appName 변경',
          oldValue: fullMatch,
          newValue: '"appName":"$newAppName$suffix"',
        ),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// dry-run 출력
// ---------------------------------------------------------------------------

/// dry-run 결과를 콘솔에 출력한다.
///
/// [projectRoot]는 표시 경로를 상대 경로로 변환하는 기준 디렉토리이다.
void printDryRun(
  List<FileChange> changes,
  String newOrg,
  String newName,
  String projectRoot,
) {
  stdout.writeln(
    '${_yellow('[DRY RUN]')} Package rename: '
    '$currentPackageName -> $newName',
  );
  stdout.writeln(
    '${_yellow('[DRY RUN]')} Organization: $currentOrg -> $newOrg',
  );
  stdout.writeln('');
  stdout.writeln('Changes to apply:');

  for (var i = 0; i < changes.length; i++) {
    final change = changes[i];
    final prefix = '  ${i + 1}. ';
    final indent = ' ' * prefix.length;
    final displayPath = _relPath(change.filePath, projectRoot);
    stdout.writeln('$prefix$displayPath');
    if (change.type == ChangeType.move) {
      stdout.writeln('${indent}Move: ${change.oldValue} -> ${change.newValue}');
    } else {
      stdout.writeln('$indent${change.description}');
      stdout.writeln('$indent  ${change.oldValue}');
      stdout.writeln('$indent  -> ${change.newValue}');
    }
  }

  stdout.writeln('');
  stdout.writeln('Run with --apply to execute these changes.');
}

// ---------------------------------------------------------------------------
// 변경 적용
// ---------------------------------------------------------------------------

/// 변경 사항을 실제로 적용한다.
///
/// [changes]에 포함된 모든 변경을 파일 시스템에 반영한다.
/// [ChangeType.replace]는 파일 내용의 문자열을 치환하고,
/// [ChangeType.move]는 디렉토리를 이동한다.
void applyChanges(List<FileChange> changes) {
  for (final change in changes) {
    switch (change.type) {
      case ChangeType.replace:
        _applyReplace(change);
      case ChangeType.move:
        _applyMove(change);
    }
  }
}

/// 파일 내 문자열 치환을 적용한다.
void _applyReplace(FileChange change) {
  final file = File(change.filePath);
  if (!file.existsSync()) return;

  final content = file.readAsStringSync();
  final updated = content.replaceAll(change.oldValue, change.newValue);
  file.writeAsStringSync(updated);
}

/// 디렉토리 이동을 적용한다.
///
/// 복사 결과를 파일 개수와 총 바이트 수로 검증한 뒤에만 원본을 삭제한다.
/// 검증 실패 시 원본을 보존하고 stderr에 에러를 출력한 뒤 exit 1로 종료한다.
void _applyMove(FileChange change) {
  final sourceDir = Directory(change.filePath);
  if (!sourceDir.existsSync()) return;

  final targetPath = change.filePath.replaceAll(
    change.oldValue.replaceAll('/', Platform.pathSeparator),
    change.newValue.replaceAll('/', Platform.pathSeparator),
  );
  final targetDir = Directory(targetPath);
  targetDir.createSync(recursive: true);

  // 1. 원본 스냅샷 수집 (파일 개수 + 총 바이트)
  final sourceFiles = sourceDir
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .toList();
  final sourceCount = sourceFiles.length;
  final sourceBytes = sourceFiles.fold<int>(
    0,
    (sum, f) => sum + f.lengthSync(),
  );

  // 2. 복사
  for (final file in sourceFiles) {
    final relativePath = file.path.substring(sourceDir.path.length);
    final targetFile = File('$targetPath$relativePath');
    targetFile.parent.createSync(recursive: true);
    file.copySync(targetFile.path);
  }

  // 3. 복사 결과 검증 — 원본 삭제 전
  final targetFiles = targetDir
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .toList();
  final targetCount = targetFiles.length;
  final targetBytes = targetFiles.fold<int>(
    0,
    (sum, f) => sum + f.lengthSync(),
  );

  if (targetCount != sourceCount || targetBytes != sourceBytes) {
    stderr.writeln(
      _red(
        'Error: copy verification failed for ${sourceDir.path}\n'
        '  source: $sourceCount files, $sourceBytes bytes\n'
        '  target: $targetCount files, $targetBytes bytes\n'
        'Source directory was NOT deleted. Run `git status` and\n'
        '`git restore .` to recover, then re-run with corrected '
        '--org/--name.',
      ),
    );
    exit(1);
  }

  // 4. 검증 통과 — 원본 삭제
  sourceDir.deleteSync(recursive: true);
  _cleanEmptyParents(sourceDir.parent);
}

/// 빈 부모 디렉토리를 재귀적으로 삭제한다.
void _cleanEmptyParents(Directory dir) {
  if (!dir.existsSync()) return;
  if (dir.listSync().isEmpty) {
    dir.deleteSync();
    _cleanEmptyParents(dir.parent);
  }
}

// ---------------------------------------------------------------------------
// CLI 출력 helpers
// ---------------------------------------------------------------------------

/// ANSI 색상 출력 가능 여부.
///
/// `NO_COLOR` 환경변수가 설정되어 있으면 false. 그 외에는
/// `stdout.supportsAnsiEscapes` 값을 따른다.
bool get _ansiEnabled {
  if (Platform.environment['NO_COLOR'] != null) return false;
  return stdout.supportsAnsiEscapes;
}

/// [text]를 ANSI [code]로 감싸 색상을 적용한다.
///
/// [_ansiEnabled]가 false면 원본 [text]를 그대로 반환한다.
String _color(String text, String code) =>
    _ansiEnabled ? '\x1B[${code}m$text\x1B[0m' : text;

/// 빨간색 텍스트로 변환한다.
String _red(String s) => _color(s, '31');

/// 초록색 텍스트로 변환한다.
String _green(String s) => _color(s, '32');

/// 노란색 텍스트로 변환한다.
String _yellow(String s) => _color(s, '33');

/// 절대 경로를 [projectRoot] 기준 상대 경로로 변환한다.
///
/// `package:path` 의존성을 도입하지 않고 단순 prefix 제거 방식으로 처리한다.
/// 결과가 비어있으면 `'.'`을 반환한다.
String _relPath(String absolutePath, String projectRoot) {
  if (!absolutePath.startsWith(projectRoot)) return absolutePath;
  final stripped = absolutePath.substring(projectRoot.length);
  final cleaned = stripped.replaceFirst(RegExp(r'^[/\\]'), '');
  return cleaned.isEmpty ? '.' : cleaned;
}

/// `--apply` 실행 직전 사용자에게 확인을 받는다.
///
/// 단일 질문이며 재시도하지 않는다. `y`/`Y`/`yes` 외 모든 입력은 거부.
/// EOF(`null`)도 거부로 처리하여 비대화형 셸에서 안전하게 종료한다.
bool _confirmApply(int changeCount) {
  stdout.write('Apply $changeCount changes? [y/N]: ');
  final answer = stdin.readLineSync();
  if (answer == null) return false;
  final trimmed = answer.trim().toLowerCase();
  return trimmed == 'y' || trimmed == 'yes';
}

// ---------------------------------------------------------------------------
// CLI 진입점
// ---------------------------------------------------------------------------

/// Starter Kit의 Package Name / Bundle ID를 변경하는 CLI 스크립트.
///
/// 사용법:
///   fvm dart run bin/rename.dart --org com.mycompany --name my_app
///   fvm dart run bin/rename.dart --org com.mycompany --name my_app --apply
///   fvm dart run bin/rename.dart --org com.mycompany --name my_app --apply --yes
void main(List<String> arguments) {
  final parser = ArgParser()
    ..addOption('org', help: 'Organization identifier (e.g., com.mycompany)')
    ..addOption('name', help: 'App name in snake_case (e.g., my_app)')
    ..addFlag(
      'apply',
      help: 'Apply changes (default: dry-run)',
      defaultsTo: false,
    )
    ..addFlag(
      'yes',
      help:
          'Skip confirmation prompt for --apply (required in CI / '
          'non-interactive shells).',
      negatable: false,
      defaultsTo: false,
    )
    ..addFlag('help', abbr: 'h', help: 'Show usage', negatable: false);

  final ArgResults results;
  try {
    results = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln(_red('Error: ${e.message}'));
    stderr.writeln('');
    stderr.writeln('Usage: fvm dart run bin/rename.dart [options]');
    stderr.writeln(parser.usage);
    exit(1);
  }

  if (results.flag('help')) {
    stdout.writeln('Starter Kit Package Rename Tool');
    stdout.writeln('');
    stdout.writeln('Usage: fvm dart run bin/rename.dart [options]');
    stdout.writeln('');
    stdout.writeln(parser.usage);
    return;
  }

  // BUG-ARGS 가드: 필수 옵션 누락 시 스택 트레이스 대신 영어 에러 출력
  if (!results.wasParsed('org') || !results.wasParsed('name')) {
    stderr.writeln(_red('Error: --org and --name are required.'));
    stderr.writeln('');
    stderr.writeln('Usage: fvm dart run bin/rename.dart [options]');
    stderr.writeln(parser.usage);
    exit(1);
  }

  final org = results.option('org')!;
  final name = results.option('name')!;
  final shouldApply = results.flag('apply');
  final skipConfirm = results.flag('yes');

  // 입력 유효성 검증
  final validation = validateInputs(org, name);
  if (!validation.isValid) {
    stderr.writeln(_red('Error: ${validation.error}'));
    exit(1);
  }

  // 프로젝트 루트 결정: 현재 작업 디렉토리 + pubspec.yaml 존재 확인
  final projectRoot = Directory.current.path;
  if (!File('$projectRoot${Platform.pathSeparator}pubspec.yaml').existsSync()) {
    stderr.writeln(
      _red(
        'Error: pubspec.yaml not found in current directory.\n'
        '       Run this command from the project root.',
      ),
    );
    exit(1);
  }

  // 변경 대상 수집
  final changes = collectChanges(projectRoot, org, name);

  if (changes.isEmpty) {
    stdout.writeln('No changes to apply.');
    stdout.writeln('');
    stdout.writeln('Possible reasons:');
    stdout.writeln("  - Project already renamed to '$org/$name'");
    stdout.writeln(
      '  - Wrong --org or --name '
      '(current: $currentOrg/$currentPackageName)',
    );
    stdout.writeln('  - Run from wrong directory (expected: project root)');
    return;
  }

  if (!shouldApply) {
    // dry-run (기본 동작)
    printDryRun(changes, org, name, projectRoot);
    return;
  }

  // --apply: 우선 변경 요약을 보여준다
  printDryRun(changes, org, name, projectRoot);
  stdout.writeln('');

  if (!skipConfirm) {
    if (!_confirmApply(changes.length)) {
      stdout.writeln('Aborted by user.');
      return; // exit 0 — 사용자 취소는 에러가 아니다
    }
  }

  stdout.writeln('Applying changes...');
  stdout.writeln('');
  applyChanges(changes);
  stdout.writeln('${_green('Done!')} ${changes.length} changes applied.');
  stdout.writeln('');
  stdout.writeln('Next steps:');
  stdout.writeln('  1. fvm flutter pub get');
  stdout.writeln(
    '  2. fvm dart run build_runner build --delete-conflicting-outputs',
  );
  stdout.writeln('  3. Build verification: fvm flutter build apk --debug');
}
