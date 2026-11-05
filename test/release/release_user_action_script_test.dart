// 릴리스 컷의 사용자 조치 판정 스크립트(scripts/release_user_action.sh)의 판정 동작과
// 사용자 소유 표면 표 대조를 실행해 고정한다.
//
// 동작 시험은 <저장소>/build/test-release-user-action-* 아래 임시 git 저장소(fixture)를
// 만들어 스크립트를 돌린다 — 이 저장소의 작업 트리 · 이력은 읽기만 하고, fixture 는 시험이
// 끝나면 지운다. 스크립트가 없는 사본에서만 건너뛴다.
//
// 킷 사용자 안전 규칙: 킷 사용자가 자기 트리를 고쳐 깰 수 있는 단언(라이브 docs/guide.md 표
// 대조 · 추적 파일 양성 대조)은 유지보수자 트리에서만 돈다. 나머지는 fixture 로 어디서나 돈다.
//
// 시험 ID:
//   T-174-UA-01  라이브 표의 낮음 행 집합 = 스크립트 행 집합 · 기록 행은 낮음 아님(유지보수자 트리)
//   T-174-UA-02  낮음 경로 꼴마다 추적 파일 양성 대조 1개 이상(유지보수자 트리)
//   T-174-UA-03  패턴 블록 꼴 · 행 집합 · fixture 표본 대조
//   T-174-UA-04  판정 none · 출력 순서 · 작업 일지 디렉터리 제외 · 읽기 전용
//   T-174-UA-05  낮음 행 파일 변경 → review · 하위 디렉터리에서 돌려도 같은 출력
//   T-174-UA-06  기록 행 파일 변경 → OTHER_ROW_HIT 만 · 판정 none
//   T-174-UA-07  표의 낮음 행이 중간으로 바뀜 → exit 3 table
//   T-174-UA-08  표의 중간 행이 낮음으로 바뀜 → exit 3 table
//   T-174-UA-09  낮음 행 파일이 TARGET 에 없음 → exit 3 control
//   T-174-UA-10  인자 수 · 빈 인자 → exit 2 · stderr usage · stdout 빈 출력
//   T-174-UA-11  풀 수 없는 커밋 이름 → exit 3 git
//   T-22-UA-01   런처 이름 생성기 경로 = 32행 꼴(킷 전용) · 그 파일만 바뀌면 OTHER_ROW_HIT 만 · 판정 none
//
// **값 모양 리터럴을 두지 않는다** — fixture 파일 내용은 짧은 평문 한 줄이다. 이 파일도 공개
// 이력에 들어가 같은 스캔을 거친다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/planning_docs.dart';
import '../helpers/source_text.dart';

/// 판정 스크립트의 저장소 루트 기준 경로.
const String _scriptRel = 'scripts/release_user_action.sh';

/// fixture 커밋 날짜(고정).
const String _fixedDate = '2026-01-01T00:00:00+0000';

/// 사용자 소유 표면 표의 `낮음` 행 번호 — 스크립트 `LOW_PATTERNS` 의 행 집합과 같다.
const Set<int> _lowRows = <int>{3, 5, 8, 14, 15, 16, 22, 28};

/// 표의 기록만 하는 행 번호 — 스크립트 `INFO_PATTERNS` 의 행 집합과 같다.
const Set<int> _infoRows = <int>{7, 10, 23, 24, 32};

/// 라이브 표가 든 사용자 가이드 경로.
const String _guidePath = 'docs/guide.md';

/// 표의 절 제목(정확한 줄).
const String _sectionHeading = '### 사용자 소유 표면';

/// 표 머리(정확한 줄).
const String _tableHeader = '| # | 파일 | 사용자가 바꾸는 것 | 킷이 고칠 가능성 | 충돌 시 조치 |';

/// 판정 스크립트의 usage 첫 줄.
const String _usageLine =
    'usage: bash scripts/release_user_action.sh <BASE> <TARGET>';

/// fixture 표의 데이터 행 수.
const int _fixtureRowCount = 32;

/// `낮음` 행마다 그 행 경로 꼴에 걸리는 표본 경로(행 · 경로).
const List<(int, String)> _lowSamples = <(int, String)>[
  (3, 'lib/core/firebase/firebase_options_dev.dart'),
  (3, 'ios/config/dev/GoogleService-Info.plist'),
  (3, 'android/app/src/stg/google-services.json'),
  (5, '.firebaserc'),
  (8, 'android/app/src/main/kotlin/com/example/app/MainActivity.kt'),
  (14, 'flutter_native_splash.yaml'),
  (14, 'assets/images/splash/logo.png'),
  (15, 'android/app/src/main/res/drawable/launch_background.xml'),
  (15, 'android/app/src/main/res/values/styles.xml'),
  (15, 'ios/Runner/Assets.xcassets/LaunchImage.imageset/Contents.json'),
  (15, 'ios/Runner/Base.lproj/LaunchScreen.storyboard'),
  (16, 'android/app/src/main/res/mipmap-hdpi/ic_launcher.png'),
  (16, 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json'),
  (22, 'android/app/src/main/res/drawable/ic_notification.xml'),
  (22, 'android/app/src/main/res/values/colors.xml'),
  (22, 'lib/features/notifications/data/local_notifications_service.dart'),
  (28, 'ios/Runner/Runner.entitlements'),
];

/// 기록만 하는 행(`INFO_PATTERNS`)의 표본 경로(행 · 경로).
const (int, String) _infoSample = (7, 'android/app/build.gradle.kts');

/// 어떤 경로 꼴에도 걸리지 않는 표본 경로.
const String _plainPath = 'lib/app.dart';

/// 킷 전용 파일 행(사용자 소유 표면 32행) 번호.
const int _kitOnlyRow = 32;

/// 런처 이름 생성기 경로 — 32행 꼴에 걸린다.
const String _launcherNamesPath = 'tool/launcher_names.dart';

/// 32행 꼴의 `tool/setup/` 디렉터리 안 표본 경로.
const String _setupToolSample = 'tool/setup/flavor.dart';

/// 32행 꼴에 걸리지 않는 `tool/` 바로 아래 표본 경로.
const String _otherToolSample = 'tool/other.dart';

/// 작업 일지 디렉터리 이름 — 스크립트 diff 가 이 디렉터리를 뺀다.
const String _workLogDir = '.planning';

/// fixture 의 작업 일지 디렉터리 안 표본 경로.
const String _workLogNote = '$_workLogDir/notes.md';

/// 스크립트가 있으면 `false`, 없으면 건너뛸 사유를 돌려준다.
Object _skipUnlessScript() =>
    File(_scriptRel).existsSync() ? false : '$_scriptRel 이 없는 사본 — 건너뜀';

/// 유지보수자 트리에서만 도는 표 대조 시험의 `skip:` 값을 돌려준다.
///
/// 스크립트가 없는 사본이면 그 사유를, 있으면 유지보수자 트리 판정 결과를 돌려준다.
Object _skipUnlessMaintainerScript() => File(_scriptRel).existsSync()
    ? skipUnlessMaintainerTree()
    : _skipUnlessScript();

/// 스크립트 문자열 [script] 에서 heredoc 블록 [name] 을 (행 번호 · 정규식) 목록으로 읽는다.
///
/// 줄 전체가 `<name>=$(cat <<'<name>_END'` 인 줄과 `<name>_END` 인 줄이 정확히 하나씩 있어야
/// 하고, 사이 줄은 전부 `<행 번호> <ERE>` 꼴이어야 한다. 스크립트의 ERE 는 `^ $ ( | ) [^/] .* \.
/// ?` 만 쓰므로 Dart [RegExp] 로 그대로 써도 뜻이 같다.
List<(int, RegExp)> _readPatternBlock(String script, String name) {
  final List<String> lines = script.split('\n');
  final open = "$name=\$(cat <<'${name}_END'";
  final close = '${name}_END';
  expect(
    lines.where((String l) => l == open),
    hasLength(1),
    reason: '$name 블록 여는 줄은 하나여야 한다',
  );
  expect(
    lines.where((String l) => l == close),
    hasLength(1),
    reason: '$name 블록 닫는 줄은 하나여야 한다',
  );
  final int start = lines.indexOf(open);
  final int end = lines.indexOf(close);
  expect(end, greaterThan(start + 1), reason: '$name 블록이 비어 있다');
  final entry = RegExp(r'^(\d+) (\S+)$');
  final patterns = <(int, RegExp)>[];
  for (final String line in lines.sublist(start + 1, end)) {
    final RegExpMatch? match = entry.firstMatch(line);
    if (match == null) {
      fail('$name 블록 줄이 <행 번호> <ERE> 꼴이 아니다: $line');
    }
    patterns.add((int.parse(match.group(1)!), RegExp(match.group(2)!)));
  }
  return patterns;
}

/// 판정 스크립트의 `LOW_PATTERNS` 블록을 읽는다.
List<(int, RegExp)> _readLowPatterns() =>
    _readPatternBlock(readTrackedFile(_scriptRel), 'LOW_PATTERNS');

/// 판정 스크립트의 `INFO_PATTERNS` 블록을 읽는다.
List<(int, RegExp)> _readInfoPatterns() =>
    _readPatternBlock(readTrackedFile(_scriptRel), 'INFO_PATTERNS');

/// 패턴 목록 [patterns] 의 행 번호 집합을 돌려준다.
Set<int> _collectRows(List<(int, RegExp)> patterns) =>
    patterns.map(((int, RegExp) p) => p.$1).toSet();

/// 설정 · 훅 · 서명 · 날짜를 고정한 git 환경을 돌려준다.
Map<String, String> _gitEnv() => <String, String>{
  'GIT_CONFIG_GLOBAL': '/dev/null',
  'GIT_CONFIG_NOSYSTEM': '1',
  'GIT_AUTHOR_NAME': 'kit-test',
  'GIT_AUTHOR_EMAIL': 'kit-test@example.invalid',
  'GIT_COMMITTER_NAME': 'kit-test',
  'GIT_COMMITTER_EMAIL': 'kit-test@example.invalid',
  'GIT_AUTHOR_DATE': _fixedDate,
  'GIT_COMMITTER_DATE': _fixedDate,
};

/// 시험 하나가 쓰는 임시 git 저장소(<저장소>/build/test-release-user-action-*).
class _Fixture {
  _Fixture._(this.dir);

  /// 임시 디렉터리를 만들고 빈 저장소(branch main)로 초기화한다.
  factory _Fixture.create() {
    final build = Directory('${Directory.current.path}/build')
      ..createSync(recursive: true);
    final fixture = _Fixture._(
      build.createTempSync('test-release-user-action-').path,
    );
    fixture.runGitChecked(<String>['init', '-q']);
    return fixture;
  }

  /// 임시 저장소 절대경로.
  final String dir;

  /// fixture 저장소에서 git 을 돌린 결과를 돌려준다.
  ProcessResult runGit(List<String> args) => Process.runSync('git', <String>[
    '-c',
    'commit.gpgsign=false',
    '-c',
    'init.defaultBranch=main',
    '-C',
    dir,
    ...args,
  ], environment: _gitEnv());

  /// git 을 돌려 성공을 단언하고 trim 한 stdout 을 돌려준다.
  String runGitChecked(List<String> args) {
    final ProcessResult result = runGit(args);
    expect(
      result.exitCode,
      0,
      reason: 'git ${args.join(' ')} 실패: ${result.stderr}',
    );
    return (result.stdout as String).trim();
  }

  /// [files](저장소 루트 기준 경로 → 내용)를 쓴다.
  void writeFiles(Map<String, String> files) {
    files.forEach((String path, String content) {
      File('$dir/$path')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
    });
  }

  /// [paths](저장소 루트 기준 경로)를 지운다.
  void deleteFiles(List<String> paths) {
    for (final path in paths) {
      File('$dir/$path').deleteSync();
    }
  }

  /// 작업 트리 전부를 커밋하고 커밋 해시를 돌려준다.
  String commitAll(String message) {
    runGitChecked(<String>['add', '-A']);
    runGitChecked(<String>['commit', '-q', '-m', message]);
    return runGitChecked(<String>['rev-parse', 'HEAD']);
  }

  /// 임시 디렉터리를 지운다(자기 산출물 경로일 때만).
  void dispose() {
    if (!dir.contains('/build/test-release-user-action-')) {
      return;
    }
    final d = Directory(dir);
    if (d.existsSync()) {
      d.deleteSync(recursive: true);
    }
  }
}

/// 행 [row] 의 기본 등급(넷째 칸)을 돌려준다.
///
/// `낮음` 행은 `낮음`(행 3 만 `낮음 (자리표시)` — 스크립트의 접두 일치 확인), 그 밖의 짝수 행은
/// `중간`, 홀수 행은 `높음` 이다.
String _readDefaultGrade(int row) {
  if (_lowRows.contains(row)) {
    return row == 3 ? '낮음 (자리표시)' : '낮음';
  }
  return row.isEven ? '중간' : '높음';
}

/// fixture 의 `docs/guide.md` 문자열을 만든다 — [grades] 는 행별 넷째 칸 덮어쓰기다.
///
/// 「### 다른 표」 와 「### 확인 방법」 의 미끼 표는 넷째 칸이 `낮음` 인 번호 행을 담는다.
/// 스크립트가 「### 사용자 소유 표면」 절 범위를 자르지 않으면 `LOW_ROWS` 에 1 · 2 · 40 이 섞여
/// exit 3 이 나도록 둔 장치다.
String _buildGuide({Map<int, String> grades = const <int, String>{}}) {
  final buffer = StringBuffer()
    ..writeln('# 가이드')
    ..writeln()
    ..writeln('## 앞 절')
    ..writeln()
    ..writeln('### 다른 표')
    ..writeln()
    ..writeln('| # | 항목 | 내용 | 등급 | 비고 |')
    ..writeln('|---|---|---|---|---|')
    ..writeln('| 1 | 미끼 | 미끼 | 낮음 | 미끼 |')
    ..writeln('| 2 | 미끼 | 미끼 | 낮음 | 미끼 |')
    ..writeln()
    ..writeln('## 킷 업데이트 반영')
    ..writeln()
    ..writeln('### 사용자 소유 표면')
    ..writeln()
    ..writeln('아래 표는 시험용 사용자 소유 표면 표다.')
    ..writeln()
    ..writeln('| # | 파일 | 사용자가 바꾸는 것 | 킷이 고칠 가능성 | 충돌 시 조치 |')
    ..writeln('|---|---|---|---|---|');
  for (var row = 1; row <= _fixtureRowCount; row++) {
    final String grade = grades[row] ?? _readDefaultGrade(row);
    buffer.writeln('| $row | 파일 $row | 값 $row | $grade | 조치 $row |');
  }
  buffer
    ..writeln()
    ..writeln('### 확인 방법')
    ..writeln()
    ..writeln('| # | 항목 | 내용 | 등급 | 비고 |')
    ..writeln('|---|---|---|---|---|')
    ..writeln('| 1 | 미끼 | 미끼 | 낮음 | 미끼 |')
    ..writeln('| 40 | 미끼 | 미끼 | 낮음 | 미끼 |');
  return buffer.toString();
}

/// fixture 기본 트리(표 · 표본 경로 · 평문 경로 · 작업 일지 표본)를 쓴다.
void _writeBaseTree(_Fixture fixture) {
  fixture.writeFiles(<String, String>{
    'docs/guide.md': _buildGuide(),
    for (final (_, path) in _lowSamples) path: 'sample\n',
    _infoSample.$2: 'sample\n',
    _plainPath: 'sample\n',
    _workLogNote: 'note\n',
  });
}

/// fixture 기본 트리를 커밋하고 그 해시를 돌려준다.
String _commitBase(_Fixture fixture) {
  _writeBaseTree(fixture);
  return fixture.commitAll('base');
}

/// 판정 스크립트를 [cwd] 에서 [args] 로 돌린 결과를 돌려준다.
ProcessResult _runTool(String cwd, List<String> args) => Process.runSync(
  'bash',
  <String>[File(_scriptRel).absolute.path, ...args],
  workingDirectory: cwd,
  environment: _gitEnv(),
);

/// 결과 stdout 을 줄 목록으로 돌려준다(끝 줄바꿈 제외).
List<String> _outLines(ProcessResult result) =>
    (result.stdout as String).trimRight().split('\n');

/// [lines] 가운데 [prefix] 로 시작하는 줄만 돌려준다.
List<String> _selectLines(List<String> lines, String prefix) =>
    lines.where((String line) => line.startsWith(prefix)).toList();

/// fixture 의 기본 커밋 위에 [edit] 를 적용한 커밋을 만들고 (base · target) 해시를 돌려준다.
(String, String) _commitBaseAndTarget(_Fixture fixture, void Function() edit) {
  final String base = _commitBase(fixture);
  edit();
  return (base, fixture.commitAll('target'));
}

/// 표 실패(exit 3 · `LOW_ROW_FAIL table:`)를 단언한다.
void _expectTableFail(ProcessResult result) {
  final List<String> lines = _outLines(result);
  expect(result.exitCode, 3, reason: 'stdout: ${result.stdout}');
  expect(lines.last, startsWith('LOW_ROW_FAIL table:'));
  expect(_selectLines(lines, 'USER_ACTION_VERDICT'), isEmpty);
}

void main() {
  test('T-174-UA-01: 라이브 표의 낮음 행 집합이 스크립트 행 집합과 같고 기록 행은 낮음이 아니다', () {
    final String guide = readTrackedFile(_guidePath);
    final String section = sliceMarkdownSection(
      guide,
      _sectionHeading,
      maxLevel: 3,
    );
    expect(
      section,
      isNotEmpty,
      reason: '$_guidePath 에 「$_sectionHeading」 절이 없다',
    );
    final List<String> table = collectTableLines(section, _tableHeader);
    final List<String> rows = table.length > 2 ? table.sublist(2) : <String>[];
    expect(rows, isNotEmpty, reason: '「$_sectionHeading」 표에 데이터 행이 없다');

    final grades = <int, String>{};
    for (final row in rows) {
      final List<String> cells = row.split('|');
      expect(cells.length, greaterThan(5), reason: '표 행 꼴: $row');
      grades[int.parse(cells[1].trim())] = cells[4].trim();
    }
    final Set<int> tableLowRows = grades.entries
        .where((MapEntry<int, String> e) => e.value.startsWith('낮음'))
        .map((MapEntry<int, String> e) => e.key)
        .toSet();
    const reason = '표가 바뀌었으면 스크립트 경로 꼴 · 이 시험을 함께 고친다';

    expect(
      tableLowRows,
      _collectRows(_readLowPatterns()),
      reason: '표의 낮음 행 ≠ LOW_PATTERNS 행 — $reason',
    );
    for (final int row in _collectRows(_readInfoPatterns())) {
      expect(
        grades.containsKey(row),
        isTrue,
        reason: 'INFO_PATTERNS 행 $row 이 표에 없다 — $reason',
      );
      expect(
        grades[row]!.startsWith('낮음'),
        isFalse,
        reason: 'INFO_PATTERNS 행 $row 이 낮음이다 — $reason',
      );
    }
  }, skip: _skipUnlessMaintainerScript());

  test('T-174-UA-02: 낮음 경로 꼴마다 추적 파일이 1개 이상 걸린다', () {
    final ProcessResult result = Process.runSync('git', <String>[
      '-c',
      'core.quotePath=false',
      'ls-files',
    ]);
    expect(result.exitCode, 0, reason: 'git ls-files 실패: ${result.stderr}');
    final List<String> tracked = (result.stdout as String)
        .split('\n')
        .where((String l) => l.isNotEmpty)
        .toList();
    expect(tracked, isNotEmpty);
    for (final (int row, RegExp pattern) in _readLowPatterns()) {
      expect(
        tracked.any(pattern.hasMatch),
        isTrue,
        reason: '행 $row 꼴 ${pattern.pattern} 이 추적 파일을 하나도 잡지 않는다',
      );
    }
  }, skip: _skipUnlessMaintainerScript());

  test('T-174-UA-03: 패턴 블록 꼴 · 행 집합 · fixture 표본이 스크립트와 맞는다', () {
    final List<(int, RegExp)> low = _readLowPatterns();
    final List<(int, RegExp)> info = _readInfoPatterns();
    expect(low, hasLength(17));
    expect(_collectRows(low), _lowRows);
    expect(info, hasLength(5));
    expect(_collectRows(info), _infoRows);

    for (final (int row, RegExp pattern) in low) {
      expect(
        _lowSamples.any(
          ((int, String) s) => s.$1 == row && pattern.hasMatch(s.$2),
        ),
        isTrue,
        reason: '행 $row 꼴 ${pattern.pattern} 에 걸리는 fixture 표본이 없다',
      );
    }
    for (final (int row, String path) in _lowSamples) {
      expect(
        low.any(((int, RegExp) p) => p.$1 == row && p.$2.hasMatch(path)),
        isTrue,
        reason: 'fixture 표본 $path 이 행 $row 꼴에 걸리지 않는다',
      );
    }
    final (int infoRow, String infoPath) = _infoSample;
    expect(
      info.any(((int, RegExp) p) => p.$1 == infoRow && p.$2.hasMatch(infoPath)),
      isTrue,
    );
    expect(low.any(((int, RegExp) p) => p.$2.hasMatch(infoPath)), isFalse);
    expect(
      <(int, RegExp)>[
        ...low,
        ...info,
      ].any(((int, RegExp) p) => p.$2.hasMatch(_plainPath)),
      isFalse,
    );
  }, skip: _skipUnlessScript());

  test('T-174-UA-04: 낮음 행 밖 변경만 있으면 none · 출력 순서 · 작업 일지 제외 · 읽기 전용', () {
    final fixture = _Fixture.create();
    addTearDown(fixture.dispose);
    final String base = _commitBase(fixture);
    fixture.writeFiles(<String, String>{
      _plainPath: 'changed\n',
      _workLogNote: 'changed note\n',
    });
    final String target = fixture.commitAll('target');

    final ProcessResult result = _runTool(fixture.dir, <String>[base, target]);
    final List<String> lines = _outLines(result);

    expect(result.exitCode, 0, reason: 'stdout: ${result.stdout}');
    expect(result.stderr, '');
    expect(lines.first, 'BASE $base');
    expect(lines[1], 'TARGET $target');
    expect(_selectLines(lines, 'CHANGED '), <String>[
      'CHANGED $_plainPath',
    ], reason: '작업 일지 디렉터리 변경은 CHANGED 에 나오지 않는다');
    expect(
      lines.where((String l) => l == 'LOW_ROWS 3 5 8 14 15 16 22 28'),
      hasLength(1),
    );
    expect(_selectLines(lines, 'LOW_ROW_CONTROL '), hasLength(17));
    expect(_selectLines(lines, 'LOW_ROW_HIT '), isEmpty);
    expect(lines.where((String l) => l == 'LOW_ROW_HITS 0'), hasLength(1));
    expect(lines.last, 'USER_ACTION_VERDICT none low_hits=0');
    expect(
      fixture.runGitChecked(<String>['status', '--porcelain']),
      isEmpty,
      reason: '스크립트는 fixture 트리를 바꾸지 않는다',
    );
  }, skip: _skipUnlessScript());

  test('T-174-UA-05: 낮음 행 파일 변경이면 review · 하위 디렉터리에서도 같은 출력', () {
    final fixture = _Fixture.create();
    addTearDown(fixture.dispose);
    const entitlements = 'ios/Runner/Runner.entitlements';
    final (String base, String target) = _commitBaseAndTarget(
      fixture,
      () => fixture.writeFiles(<String, String>{entitlements: 'changed\n'}),
    );

    final ProcessResult result = _runTool(fixture.dir, <String>[base, target]);
    final List<String> lines = _outLines(result);

    expect(result.exitCode, 0, reason: 'stdout: ${result.stdout}');
    expect(_selectLines(lines, 'LOW_ROW_HIT '), <String>[
      'LOW_ROW_HIT row=28 $entitlements',
    ]);
    expect(lines.where((String l) => l == 'LOW_ROW_HITS 1'), hasLength(1));
    expect(lines.last, 'USER_ACTION_VERDICT review low_hits=1');

    final ProcessResult nested = _runTool('${fixture.dir}/lib', <String>[
      base,
      target,
    ]);
    expect(nested.exitCode, 0);
    expect(nested.stdout, result.stdout, reason: 'pathspec 은 저장소 루트 기준이다');
  }, skip: _skipUnlessScript());

  test('T-174-UA-06: 기록 행 파일만 바뀌면 OTHER_ROW_HIT 만 나오고 판정은 none', () {
    final fixture = _Fixture.create();
    addTearDown(fixture.dispose);
    final (int infoRow, String infoPath) = _infoSample;
    final (String base, String target) = _commitBaseAndTarget(
      fixture,
      () => fixture.writeFiles(<String, String>{infoPath: 'changed\n'}),
    );

    final ProcessResult result = _runTool(fixture.dir, <String>[base, target]);
    final List<String> lines = _outLines(result);

    expect(result.exitCode, 0, reason: 'stdout: ${result.stdout}');
    expect(_selectLines(lines, 'OTHER_ROW_HIT '), <String>[
      'OTHER_ROW_HIT row=$infoRow $infoPath',
    ]);
    expect(_selectLines(lines, 'LOW_ROW_HIT '), isEmpty);
    expect(lines.last, 'USER_ACTION_VERDICT none low_hits=0');
  }, skip: _skipUnlessScript());

  test('T-174-UA-07: 표의 낮음 행이 중간으로 바뀌면 exit 3 table', () {
    final fixture = _Fixture.create();
    addTearDown(fixture.dispose);
    final (String base, String target) = _commitBaseAndTarget(
      fixture,
      () => fixture.writeFiles(<String, String>{
        'docs/guide.md': _buildGuide(grades: <int, String>{22: '중간'}),
      }),
    );

    _expectTableFail(_runTool(fixture.dir, <String>[base, target]));
  }, skip: _skipUnlessScript());

  test('T-174-UA-08: 표의 중간 · 높음 행이 낮음으로 바뀌면 exit 3 table', () {
    final fixture = _Fixture.create();
    addTearDown(fixture.dispose);
    final (String base, String target) = _commitBaseAndTarget(
      fixture,
      () => fixture.writeFiles(<String, String>{
        'docs/guide.md': _buildGuide(grades: <int, String>{7: '낮음'}),
      }),
    );

    _expectTableFail(_runTool(fixture.dir, <String>[base, target]));
  }, skip: _skipUnlessScript());

  test('T-174-UA-09: 낮음 행 파일이 TARGET 에 없으면 exit 3 control', () {
    final fixture = _Fixture.create();
    addTearDown(fixture.dispose);
    final (String base, String target) = _commitBaseAndTarget(
      fixture,
      () => fixture.deleteFiles(<String>['.firebaserc']),
    );

    final ProcessResult result = _runTool(fixture.dir, <String>[base, target]);
    final List<String> lines = _outLines(result);

    expect(result.exitCode, 3, reason: 'stdout: ${result.stdout}');
    expect(lines.last, startsWith('LOW_ROW_FAIL control: row=5 '));
    expect(_selectLines(lines, 'USER_ACTION_VERDICT'), isEmpty);
  }, skip: _skipUnlessScript());

  test(
    'T-174-UA-10: 인자 수가 2가 아니거나 빈 인자면 exit 2 · stderr usage · stdout 빈 출력',
    () {
      final fixture = _Fixture.create();
      addTearDown(fixture.dispose);
      final (String base, String target) = _commitBaseAndTarget(
        fixture,
        () => fixture.writeFiles(<String, String>{_plainPath: 'changed\n'}),
      );
      final cases = <List<String>>[
        <String>[],
        <String>[base],
        <String>[base, target, target],
        <String>['', target],
        <String>[base, ''],
      ];

      for (final args in cases) {
        final ProcessResult result = _runTool(fixture.dir, args);
        expect(result.exitCode, 2, reason: '인자 $args');
        expect(result.stdout, '', reason: '인자 $args');
        expect(result.stderr as String, contains(_usageLine));
      }
    },
    skip: _skipUnlessScript(),
  );

  test('T-174-UA-11: 풀 수 없는 커밋 이름이면 exit 3 git', () {
    final fixture = _Fixture.create();
    addTearDown(fixture.dispose);
    final (String base, String target) = _commitBaseAndTarget(
      fixture,
      () => fixture.writeFiles(<String, String>{_plainPath: 'changed\n'}),
    );

    final ProcessResult badBase = _runTool(fixture.dir, <String>[
      'no-such-ref',
      target,
    ]);
    expect(badBase.exitCode, 3, reason: 'stdout: ${badBase.stdout}');
    expect(_outLines(badBase).last, startsWith('LOW_ROW_FAIL git:'));

    final ProcessResult badTarget = _runTool(fixture.dir, <String>[
      base,
      'no-such-ref',
    ]);
    final List<String> lines = _outLines(badTarget);
    expect(badTarget.exitCode, 3, reason: 'stdout: ${badTarget.stdout}');
    expect(lines.first, 'BASE $base');
    expect(lines.last, startsWith('LOW_ROW_FAIL git:'));
  }, skip: _skipUnlessScript());

  test('T-22-UA-01: 런처 이름 생성기 경로는 32행 꼴에 걸리고 그 파일만 바뀌면 판정은 none', () {
    final List<RegExp> kitOnly = _readInfoPatterns()
        .where(((int, RegExp) p) => p.$1 == _kitOnlyRow)
        .map(((int, RegExp) p) => p.$2)
        .toList();
    expect(kitOnly, hasLength(1), reason: 'INFO_PATTERNS 의 32행 꼴은 하나다');
    final RegExp row32 = kitOnly.single;
    expect(row32.hasMatch(_launcherNamesPath), isTrue);
    expect(row32.hasMatch(_setupToolSample), isTrue);
    expect(row32.hasMatch(_otherToolSample), isFalse);
    expect(
      _readLowPatterns().any(
        ((int, RegExp) p) => p.$2.hasMatch(_launcherNamesPath),
      ),
      isFalse,
      reason: '생성기 경로는 낮음 꼴에 걸리지 않는다',
    );

    final fixture = _Fixture.create();
    addTearDown(fixture.dispose);
    final (String base, String target) = _commitBaseAndTarget(
      fixture,
      () =>
          fixture.writeFiles(<String, String>{_launcherNamesPath: 'sample\n'}),
    );

    final ProcessResult result = _runTool(fixture.dir, <String>[base, target]);
    final List<String> lines = _outLines(result);

    expect(result.exitCode, 0, reason: 'stdout: ${result.stdout}');
    expect(_selectLines(lines, 'OTHER_ROW_HIT '), <String>[
      'OTHER_ROW_HIT row=$_kitOnlyRow $_launcherNamesPath',
    ]);
    expect(_selectLines(lines, 'LOW_ROW_HIT '), isEmpty);
    expect(lines.last, 'USER_ACTION_VERDICT none low_hits=0');
  }, skip: _skipUnlessScript());
}
