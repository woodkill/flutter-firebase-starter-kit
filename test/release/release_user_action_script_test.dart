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
//   T-174-UA-04  판정 none · 출력 순서 · 작업 일지 디렉터리 제외 · 읽기 전용
//
// **값 모양 리터럴을 두지 않는다** — fixture 파일 내용은 짧은 평문 한 줄이다. 이 파일도 공개
// 이력에 들어가 같은 스캔을 거친다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 판정 스크립트의 저장소 루트 기준 경로.
const String _scriptRel = 'scripts/release_user_action.sh';

/// fixture 커밋 날짜(고정).
const String _fixedDate = '2026-01-01T00:00:00+0000';

/// 사용자 소유 표면 표의 `낮음` 행 번호 — 스크립트 `LOW_PATTERNS` 의 행 집합과 같다.
const Set<int> _lowRows = <int>{3, 5, 8, 14, 15, 16, 22, 28};

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

/// 작업 일지 디렉터리 이름 — 스크립트 diff 가 이 디렉터리를 뺀다.
const String _workLogDir = '.planning';

/// fixture 의 작업 일지 디렉터리 안 표본 경로.
const String _workLogNote = '$_workLogDir/notes.md';

/// 스크립트가 있으면 `false`, 없으면 건너뛸 사유를 돌려준다.
Object _skipUnlessScript() =>
    File(_scriptRel).existsSync() ? false : '$_scriptRel 이 없는 사본 — 건너뜀';

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

void main() {
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
}
