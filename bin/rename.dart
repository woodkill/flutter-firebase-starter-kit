// ignore_for_file: avoid_print

import 'dart:io';

import 'package:args/args.dart';

// ---------------------------------------------------------------------------
// 현재 프로젝트의 고정 값 (변경 원본)
// ---------------------------------------------------------------------------

/// Kotlin 소스 디렉터리의 마지막 세그먼트.
///
/// Dart 패키지명(`pubspec.yaml` 의 name)과 같다 — 이 도구는 Dart 패키지명과
/// import 를 바꾸지 않는다(D-34). Kotlin 현재 경로 계산에만 쓴다.
const currentPackageName = 'flutter_starter_kit';

/// 현재 organization (역순 도메인).
const currentOrg = 'com.slimpumpkin';

/// 현재 Android applicationId / namespace.
const currentAndroidPackage = 'com.slimpumpkin.flutter_starter_kit';

/// 현재 iOS Bundle ID (Runner).
const currentIosBundleId = 'com.slimpumpkin.flutterStarterKit';

/// 현재 Firebase 프로젝트 ID prefix (`scripts/firebase-configure.sh`).
///
/// 스크립트가 `<prefix>-dev` · `-stg` · `-prod` 를 Firebase 프로젝트 ID 로 쓴다.
const currentProjectIdPrefix = 'slimpumpkin-starter-kit';

/// 현재 appName 기본값 (config에서 suffix 제거 전 원본).
const currentAppName = 'StarterKit';

/// appName 을 바꾸는 사용자 config 파일 이름 (`config/` 기준).
///
/// gitignored 사용자 config 만 대상이다. 킷 추적 `config/*.example.json` 은
/// 바꾸지 않는다 — 킷이 example 을 고쳐도 사용자 merge 충돌이 없게(D-34).
const List<String> userConfigFileNames = ['dev.json', 'stg.json', 'prod.json'];

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

/// Firebase 프로젝트 ID prefix 형식 정규식.
///
/// 소문자로 시작하고 소문자 · 숫자 · `-` 만 쓰며 `-` 로 끝나지 않는다.
/// 셸 메타문자(따옴표 · `$` · 공백 등)는 들어갈 수 없다.
final _projectPrefixPattern = RegExp(r'^[a-z][a-z0-9-]*[a-z0-9]$');

/// Firebase 프로젝트 ID prefix 최소 길이.
///
/// prefix 뒤에 `-dev` 가 붙어 Firebase 프로젝트 ID 하한 6자를 채운다.
const projectPrefixMinLength = 2;

/// Firebase 프로젝트 ID prefix 최대 길이.
///
/// prefix 뒤에 `-prod` 가 붙어도 Firebase 프로젝트 ID 상한 30자를 넘지 않는다.
const projectPrefixMaxLength = 25;

/// Firebase 프로젝트 ID prefix 를 검증한다.
///
/// [prefix]는 `scripts/firebase-configure.sh` 의 `PROJECT_ID_PREFIX` 값이며
/// `<prefix>-dev` · `-stg` · `-prod` 가 Firebase 프로젝트 ID 가 된다.
/// 소문자 · 숫자 · `-` 만 허용하고(문자로 시작 · `-` 로 끝나지 않음)
/// 길이는 [projectPrefixMinLength]~[projectPrefixMaxLength] 자이다.
ValidateResult validateProjectPrefix(String prefix) {
  final isLengthValid =
      prefix.length >= projectPrefixMinLength &&
      prefix.length <= projectPrefixMaxLength;
  if (!isLengthValid || !_projectPrefixPattern.hasMatch(prefix)) {
    return ValidateResult(
      isValid: false,
      error:
          "Invalid project prefix: '$prefix'\n"
          'Use $projectPrefixMinLength-$projectPrefixMaxLength lowercase '
          'letters, digits, or "-" (start with a letter, no trailing "-"; '
          'e.g., my-company-app)',
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

/// 프로젝트 내 앱 ID 변경 대상을 수집한다.
///
/// [projectRoot]에서 현재 앱 ID(Android package · iOS bundle ID · Firebase
/// 설정 스크립트 상수 · 사용자 config appName)를 [newOrg]과 [newName]으로
/// 변경할 대상 파일과 변경 내용 목록을 반환한다.
/// Dart 패키지명(`pubspec.yaml` 의 name)과 `package:` import 는 수집하지
/// 않는다(D-34 — 바꾸면 킷 업데이트 merge 마다 import 충돌).
/// [projectIdPrefix]가 null 이면 [newName]의 `_` 를 `-` 로 바꾼 값을
/// Firebase 프로젝트 ID prefix 로 쓴다.
/// 실제 파일 수정은 하지 않는다.
List<FileChange> collectChanges(
  String projectRoot,
  String newOrg,
  String newName, {
  String? projectIdPrefix,
}) {
  final changes = <FileChange>[];
  final newAndroidPackage = '$newOrg.$newName';
  final newIosBundleId = '$newOrg.${toLowerCamelCase(newName)}';
  final newAppName = toTitleCase(newName);
  final newProjectIdPrefix = projectIdPrefix ?? newName.replaceAll('_', '-');

  // 1. android/app/build.gradle.kts
  _collectGradleChanges(projectRoot, newAndroidPackage, changes);

  // 2. Kotlin 디렉토리 이동 + package 선언 변경
  _collectKotlinChanges(projectRoot, newOrg, newName, changes);

  // 3. iOS project.pbxproj
  _collectIosChanges(projectRoot, newIosBundleId, changes);

  // 4. config/{dev,stg,prod}.json appName (사용자 파일만)
  _collectConfigChanges(projectRoot, newAppName, changes);

  // 5. scripts/firebase-configure.sh 상수 3줄
  _collectFirebaseConfigureChanges(
    projectRoot,
    newIosBundleId,
    newAndroidPackage,
    newProjectIdPrefix,
    changes,
  );

  // 동일 값 → 동일 값 변경(no-op)은 제외한다. 사용자가 현재 값과 동일한
  // --org/--name을 넘긴 경우 0건 진단 메시지가 정상적으로 노출되도록 한다.
  return changes.where((c) => c.oldValue != c.newValue).toList();
}

/// build.gradle.kts의 namespace와 applicationId 변경을 수집한다.
void _collectGradleChanges(
  String projectRoot,
  String newAndroidPackage,
  List<FileChange> changes,
) {
  final file = File('$projectRoot/android/app/build.gradle.kts');
  if (!file.existsSync()) return;

  // 실제로 치환 대상 문자열이 존재할 때만 변경을 등록한다.
  final content = file.readAsStringSync();
  if (!content.contains(currentAndroidPackage)) return;

  changes.add(
    FileChange(
      filePath: file.path,
      type: ChangeType.replace,
      description: 'Android namespace + applicationId',
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
      description: 'Kotlin source directory move',
      oldValue: '$currentOrgPath/$currentPackageName',
      newValue: '$newOrgPath/$newName',
    ),
  );

  // 패키지 디렉토리 안의 모든 .kt 파일 package 선언 변경.
  // MainActivity.kt 만 바꾸면 같은 패키지의 다른 Kotlin 파일(Phase 16.5
  // NaverHostChannel.kt 등)이 옛 package 에 남아 MainActivity 의 참조가
  // unresolved 로 컴파일이 깨진다.
  final newAndroidPackage = '$newOrg.$newName';
  final kotlinFiles =
      Directory(currentDir)
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.kt'))
          .map((file) => file.uri.pathSegments.last)
          .toList()
        ..sort();
  for (final fileName in kotlinFiles) {
    changes.add(
      FileChange(
        filePath: '$newDir/$fileName',
        type: ChangeType.replace,
        description: 'Kotlin package declaration ($fileName)',
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
        description:
            'Runner PRODUCT_BUNDLE_IDENTIFIER ($runnerMatches occurrences)',
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
            'RunnerTests PRODUCT_BUNDLE_IDENTIFIER '
            '($testsMatches occurrences)',
        oldValue: '$currentIosBundleId.RunnerTests',
        newValue: '$newIosBundleId.RunnerTests',
      ),
    );
  }
}

/// config/{dev,stg,prod}.json 의 appName 필드 변경을 수집한다.
///
/// [userConfigFileNames] 의 사용자 파일만 읽는다. 킷 추적
/// `config/*.example.json` 은 수집하지 않는다.
void _collectConfigChanges(
  String projectRoot,
  String newAppName,
  List<FileChange> changes,
) {
  // appName 패턴: "appName": "..." -- 현재 값에 suffix가 붙을 수 있음
  // JSON 파일마다 공백 유무가 다를 수 있으므로 매칭된 전체 문자열을 사용
  final pattern = RegExp(r'"appName"\s*:\s*"([^"]*)"');

  for (final fileName in userConfigFileNames) {
    final file = File('$projectRoot/config/$fileName');
    if (!file.existsSync()) continue;

    final content = file.readAsStringSync();
    final match = pattern.firstMatch(content);
    if (match == null) continue;

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
        description: 'Flavor appName',
        oldValue: fullMatch,
        newValue: '"appName":"$newAppName$suffix"',
      ),
    );
  }
}

/// `scripts/firebase-configure.sh` 의 앱 ID 상수 3줄 변경을 수집한다.
///
/// `PROJECT_ID_PREFIX` · `IOS_BUNDLE_ID_PREFIX` · `ANDROID_PACKAGE_PREFIX`
/// 각 줄을 따옴표 포함 전체 줄 단위로 바꾼다. 파일이 없거나 현재 줄이
/// 없으면(이미 바뀐 경우) 그 줄은 등록하지 않는다.
void _collectFirebaseConfigureChanges(
  String projectRoot,
  String newIosBundleId,
  String newAndroidPackage,
  String newProjectIdPrefix,
  List<FileChange> changes,
) {
  final file = File('$projectRoot/scripts/firebase-configure.sh');
  if (!file.existsSync()) return;

  final lines = file.readAsLinesSync();
  final targets = <({String description, String oldLine, String newLine})>[
    (
      description: 'Firebase project ID prefix',
      oldLine: 'PROJECT_ID_PREFIX="$currentProjectIdPrefix"',
      newLine: 'PROJECT_ID_PREFIX="$newProjectIdPrefix"',
    ),
    (
      description: 'Firebase iOS bundle ID prefix',
      oldLine: 'IOS_BUNDLE_ID_PREFIX="$currentIosBundleId"',
      newLine: 'IOS_BUNDLE_ID_PREFIX="$newIosBundleId"',
    ),
    (
      description: 'Firebase Android package prefix',
      oldLine: 'ANDROID_PACKAGE_PREFIX="$currentAndroidPackage"',
      newLine: 'ANDROID_PACKAGE_PREFIX="$newAndroidPackage"',
    ),
  ];

  // 실제로 치환 대상 줄이 존재할 때만 변경을 등록한다.
  for (final target in targets) {
    if (!lines.contains(target.oldLine)) continue;
    changes.add(
      FileChange(
        filePath: file.path,
        type: ChangeType.replace,
        description: target.description,
        oldValue: target.oldLine,
        newValue: target.newLine,
      ),
    );
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
    '${_yellow('[DRY RUN]')} App ID rename: '
    '$currentAndroidPackage -> $newOrg.$newName',
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

/// Starter Kit 의 앱 ID(Android package · iOS Bundle ID · Firebase 설정
/// 스크립트 상수 · appName)를 변경하는 CLI 스크립트.
///
/// Dart 패키지명(`flutter_starter_kit`)과 import 는 바꾸지 않는다(D-34).
///
/// 사용법:
///   fvm dart run bin/rename.dart --org com.mycompany --name my_app
///   fvm dart run bin/rename.dart --org com.mycompany --name my_app \
///     --project-prefix my-company-app
///   fvm dart run bin/rename.dart --org com.mycompany --name my_app --apply
///   fvm dart run bin/rename.dart --org com.mycompany --name my_app --apply --yes
void main(List<String> arguments) {
  final parser = ArgParser()
    ..addOption('org', help: 'Organization identifier (e.g., com.mycompany)')
    ..addOption(
      'name',
      help:
          'App ID segment in snake_case (e.g., my_app) — Android package '
          'tail, Kotlin dir, iOS bundle (lowerCamel), appName. '
          'The Dart package name stays flutter_starter_kit.',
    )
    ..addOption(
      'project-prefix',
      help:
          'Firebase project ID prefix (default: --name with "_" -> "-"). '
          'Used as <prefix>-dev / -stg / -prod in '
          'scripts/firebase-configure.sh',
    )
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
    stdout.writeln('Starter Kit App ID Rename Tool');
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

  // Firebase 프로젝트 ID prefix — 옵션이 없으면 name 의 _ 를 - 로 바꾼 값
  final explicitPrefix = results.option('project-prefix');
  final projectIdPrefix = explicitPrefix ?? name.replaceAll('_', '-');
  final prefixValidation = validateProjectPrefix(projectIdPrefix);
  if (!prefixValidation.isValid) {
    if (explicitPrefix == null) {
      stderr.writeln(
        _red(
          'Error: default project prefix "$projectIdPrefix" is invalid '
          '— pass --project-prefix\n'
          '${prefixValidation.error}',
        ),
      );
    } else {
      stderr.writeln(_red('Error: ${prefixValidation.error}'));
    }
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
  final changes = collectChanges(
    projectRoot,
    org,
    name,
    projectIdPrefix: projectIdPrefix,
  );

  if (changes.isEmpty) {
    stdout.writeln('No changes to apply.');
    stdout.writeln('');
    stdout.writeln('Possible reasons:');
    stdout.writeln("  - Project already renamed to '$org/$name'");
    stdout.writeln(
      '  - Wrong --org or --name '
      '(current app ID: $currentAndroidPackage)',
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
