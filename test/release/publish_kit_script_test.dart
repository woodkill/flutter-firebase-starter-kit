// 공개 mirror 발행 스크립트(scripts/publish_kit.sh)의 동작을 실행해 고정한다 (Phase 17.4
// D-16 · D-29 — see ROADMAP.md).
//
// 인자 처리 · WORK 가드 · 무인자 status · scan 불변식 · check · push · release 의 안전
// 게이트를 Process.run 으로 돌려 본다. 모든 실행은 로컬 임시 저장소만 쓴다 — 실제 원격 ·
// gh · mirror · verify · `--apply` 는 한 번도 부르지 않는다(`_runKit` 이 4개 환경변수를
// 항상 로컬 경로로 채우고, 금지 인자를 단언한다). 임시 디렉터리는 <저장소>/build/ 아래에만
// 만들고(스크립트 WORK 가드 조건) 테스트가 끝나면 지운다. build/publish 와 build/uat-* 는
// 건드리지 않는다.
//
// 규칙 파일(.planning/release/)이 있어야 도는 케이스는 공개 mirror 에서 건너뛴다(D-08 skip
// 형). 인자 오류 · WORK 가드 · 공개 트리 모사 케이스는 두 트리 모두에서 돈다.
//
// **값 모양 리터럴을 두지 않는다** — 키 · 세션 트레일러 모양은 실행 시점에 조각으로
// 조립한다. 이 파일도 공개 이력에 들어가 같은 스캔을 거친다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/planning_docs.dart';

const String _scriptRel = 'scripts/publish_kit.sh';
const List<String> _rulesFiles = <String>[
  '.planning/release/mirror-exclude-paths.txt',
  '.planning/release/mirror-replace-text.txt',
  '.planning/release/mirror-replace-message.txt',
];
const String _fixedDate = '2026-01-01T00:00:00+0000';
const String _noStatus =
    'status: mirror=- scan=- verify=- check=- push=- main=none';
const String _version = '1.0.0-rc.9';

/// 스크립트가 있으면 `false`, 없으면 건너뛸 사유를 돌려준다.
Object _skipUnlessScript() =>
    File(_scriptRel).existsSync() ? false : '$_scriptRel 이 없는 사본 — 건너뜀';

/// [tool] 의 절대경로를 PATH 에서 찾아 돌려준다. 없으면 `null`.
String? _findToolOnPath(String tool) {
  final ProcessResult result = Process.runSync('which', <String>[tool]);
  if (result.exitCode != 0) {
    return null;
  }
  final String path = (result.stdout as String).trim();
  return path.isEmpty ? null : path;
}

/// [tools] 가 모두 PATH 에 있으면 `false`, 하나라도 없으면 건너뛸 사유를 돌려준다.
///
/// gitleaks 는 stub 으로 격리하지만 jq · git 같은 나머지 도구는 실행 환경의 것을 쓴다 —
/// 없는 환경에서는 RED 대신 건너뛴다는 사실을 선언 시점에 드러낸다(WR-07).
Object _skipUnlessToolsOnPath(List<String> tools) {
  for (final String tool in tools) {
    if (_findToolOnPath(tool) == null) {
      return '$tool 이 PATH 에 없는 환경 — 건너뜀';
    }
  }
  return false;
}

/// 테스트 하나가 쓰는 임시 작업 공간(<저장소>/build/test-publish-kit-*).
class _Sandbox {
  _Sandbox._(this.dir);

  /// 임시 디렉터리를 만든다.
  factory _Sandbox.create() {
    final Directory build = Directory('${Directory.current.path}/build')
      ..createSync(recursive: true);
    return _Sandbox._(build.createTempSync('test-publish-kit-').path);
  }

  /// 임시 디렉터리 절대경로.
  final String dir;

  /// 스크립트 WORK(아직 만들지 않는다).
  String get work => '$dir/work';

  /// 스크립트 mirror 위치.
  String get mirror => '$work/mirror';

  /// private origin 대역 — 이름만 실제와 같고 디스크에는 없다.
  String get origin => '$dir/origin/flutter_starter_kit.git';

  /// 공개 저장소 대역 bare 경로.
  String get publicRepo => '$dir/public/public-kit.git';

  /// 임시 디렉터리를 지운다(자기 산출물만).
  void dispose() {
    final Directory d = Directory(dir);
    if (d.existsSync()) {
      d.deleteSync(recursive: true);
    }
  }
}

/// 설정 · 훅 · 서명 · 날짜를 고정한 git 환경.
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

ProcessResult _gitRaw(String repo, List<String> args) =>
    Process.runSync('git', <String>[
      '-c',
      'commit.gpgsign=false',
      '-c',
      'tag.gpgsign=false',
      '-c',
      'init.defaultBranch=main',
      '-C',
      repo,
      ...args,
    ], environment: _gitEnv());

/// git 을 돌려 성공을 단언하고 trim 한 stdout 을 돌려준다.
String _git(String repo, List<String> args) {
  final ProcessResult result = _gitRaw(repo, args);
  expect(
    result.exitCode,
    0,
    reason: 'git ${args.join(' ')} 실패: ${result.stderr}',
  );
  return (result.stdout as String).trim();
}

/// 빈 저장소(branch main)를 만든다.
void _initRepo(String path) {
  Directory(path).createSync(recursive: true);
  _git(path, <String>['init', '-q']);
}

/// 빈 bare 저장소를 만든다.
void _initBare(String path) {
  Directory(path).createSync(recursive: true);
  _git(path, <String>['init', '--bare', '-q']);
}

/// [files] 를 쓰고 커밋해 해시를 돌려준다. [extra] 는 메시지 추가 문단이다.
String _commit(
  String repo,
  Map<String, String> files,
  String message, {
  List<String> extra = const <String>[],
}) {
  files.forEach((String rel, String content) {
    File('$repo/$rel')
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  });
  _git(repo, <String>['add', '-A']);
  _git(repo, <String>[
    'commit',
    '-q',
    '-m',
    message,
    for (final String paragraph in extra) ...<String>['-m', paragraph],
  ]);
  return _git(repo, <String>['rev-parse', 'HEAD']);
}

/// [repo] 의 [sha] 를 로컬 bare [bare] 의 [ref] 로 보낸다(로컬 경로 push).
void _pushRef(String repo, String bare, String sha, String ref) {
  _git(repo, <String>['push', '-q', bare, '$sha:$ref']);
}

/// `$work/<step>.ok` 단계 표시 파일을 쓴다.
void _writeStamp(_Sandbox sb, String step, String hash) {
  Directory(sb.work).createSync(recursive: true);
  File('${sb.work}/$step.ok').writeAsStringSync('$hash\n');
}

/// 가짜 gitleaks 를 [sb] 의 stub-bin 에 만들고 그 디렉터리를 돌려준다.
String _writeGitleaksStub(_Sandbox sb, {required bool findings}) {
  final Directory bin = Directory('${sb.dir}/stub-bin')
    ..createSync(recursive: true);
  final File stub = File('${bin.path}/gitleaks');
  if (findings) {
    stub.writeAsStringSync(
      '#!/bin/sh\n'
      'while [ "\$#" -gt 0 ]; do\n'
      '  if [ "\$1" = "--report-path" ]; then printf \'[{}]\' > "\$2"; fi\n'
      '  shift\n'
      'done\n'
      'exit 1\n',
    );
  } else {
    stub.writeAsStringSync('#!/bin/sh\nexit 0\n');
  }
  Process.runSync('chmod', <String>['+x', stub.path]);
  return bin.path;
}

/// publish_kit.sh 를 실행한다 — 4개 환경변수를 항상 로컬 값으로 채우는 유일한 경로다.
///
/// 허용 서브커맨드는 무인자 · scan · check · push · release 뿐이고 `--apply` 는
/// 금지다. [argErrorOnly] 는 인자 파서가 exit 2 로 거부해야 하는 호출(알 수 없는
/// 서브커맨드 · 잘못된 인자)에만 쓴다. mirror · verify 는 어떤 경우에도 막는다.
/// `--apply` 는 [argErrorOnly] 호출에서도 인자 3개 이상(파서가 인자 수로 거부하는
/// 모양)일 때만 넘긴다 — 가드가 스크립트 동작이 아니라 테스트 자신에 있게 한다(IN-09).
/// [stubBin] 은 PATH 앞에 붙이고, [pathOverride] 는 PATH 를 통째로 그 값으로 바꾼다
/// (도구 부재 시나리오용 — 둘 다 주면 [pathOverride] 가 이긴다).
ProcessResult _runKit(
  List<String> args,
  _Sandbox sb, {
  String? work,
  String? origin,
  String? publicRepo,
  String repo = 'example-owner/public-kit',
  String? script,
  String? stubBin,
  String? pathOverride,
  bool argErrorOnly = false,
}) {
  final String? first = args.isEmpty ? null : args.first;
  expect(<String?>['mirror', 'verify'].contains(first), isFalse);
  if (!argErrorOnly) {
    expect(
      first == null ||
          <String>['scan', 'check', 'push', 'release'].contains(first),
      isTrue,
      reason: '허용되지 않은 서브커맨드: $first',
    );
  }
  if (args.contains('--apply')) {
    // 스크립트는 push · release 의 인자가 2개를 넘으면 실행 전에 exit 2 로 거부한다.
    expect(
      argErrorOnly && args.length > 2,
      isTrue,
      reason: '--apply 는 인자 파서가 인자 수로 거부하는 모양으로만 넘긴다: $args',
    );
  }
  final Map<String, String> env = <String, String>{
    ..._gitEnv(),
    'KIT_PUBLISH_ORIGIN': origin ?? sb.origin,
    'KIT_PUBLISH_PUBLIC': publicRepo ?? sb.publicRepo,
    'KIT_PUBLISH_WORK': work ?? sb.work,
    'KIT_PUBLISH_REPO': repo,
  };
  for (final String key in <String>[
    'KIT_PUBLISH_ORIGIN',
    'KIT_PUBLISH_PUBLIC',
    'KIT_PUBLISH_WORK',
    'KIT_PUBLISH_REPO',
  ]) {
    expect(env[key], isNotEmpty, reason: '$key 가 비어 있다');
  }
  for (final String key in <String>[
    'KIT_PUBLISH_ORIGIN',
    'KIT_PUBLISH_PUBLIC',
  ]) {
    final String value = env[key]!;
    expect(value.startsWith('/'), isTrue, reason: '$key 는 로컬 절대경로여야 한다');
    expect(value.contains('@') || value.contains('://'), isFalse);
  }
  if (stubBin != null) {
    env['PATH'] = '$stubBin:${Platform.environment['PATH']}';
  }
  if (pathOverride != null) {
    env['PATH'] = pathOverride;
  }
  return Process.runSync(
    'bash',
    <String>[script ?? _scriptRel, ...args],
    environment: env,
    workingDirectory: Directory.current.path,
  );
}

List<String> _outLines(ProcessResult result) =>
    (result.stdout as String).trimRight().split('\n');

String _err(ProcessResult result) => result.stderr as String;

/// 마지막 stdout 줄이 [expected] 인지 단언한다.
void _expectLastLine(ProcessResult result, String expected) {
  expect(
    _outLines(result).last,
    expected,
    reason: 'stdout=${result.stdout} stderr=${result.stderr}',
  );
}

/// 최소 mirror(lib/ 경로 1개)를 만들고 첫 커밋 해시를 돌려준다.
String _initMirror(_Sandbox sb) {
  _initRepo(sb.mirror);
  return _commit(sb.mirror, <String, String>{
    'lib/main.dart': 'void main() {}\n',
  }, 'chore: 초기 커밋');
}

String _defaultChangelog(String version) =>
    '# Changelog\n\n## [$version] - 2026-01-01\n\n### Added\n- 첫 항목\n\n'
    '[$version]: https://example.invalid/releases/$version\n';

/// KIT_VERSION · CHANGELOG 를 담은 커밋을 mirror main 에 얹고 [stamps] 를 쓴다.
String _buildKitMirror(
  _Sandbox sb, {
  String versionFile = '$_version\n',
  String? changelog,
  List<String> stamps = const <String>['mirror', 'scan', 'verify', 'check'],
}) {
  if (!Directory('${sb.mirror}/.git').existsSync()) {
    _initMirror(sb);
  }
  final String hash = _commit(sb.mirror, <String, String>{
    'KIT_VERSION': versionFile,
    'CHANGELOG.md': changelog ?? _defaultChangelog(_version),
  }, 'chore: 릴리스 컷 ${DateTime.now().microsecondsSinceEpoch}');
  for (final String step in stamps) {
    _writeStamp(sb, step, hash);
  }
  return hash;
}

String _refsInMirror(_Sandbox sb) => _git(sb.mirror, <String>[
  'for-each-ref',
  '--format=%(refname)',
  'refs/public',
  'refs/public-tags',
]);

void main() {
  late _Sandbox sb;
  setUp(() => sb = _Sandbox.create());
  tearDown(() => sb.dispose());

  final Object skipScript = _skipUnlessScript();
  final Object skipRules = _skipUnlessScript() == false
      ? skipUnlessPlanningDocsExist(_rulesFiles)
      : _skipUnlessScript();

  group('인자 처리 · WORK 가드 (D-29, 두 트리 공통)', () {
    test('T-174-PUB-01: 알 수 없는 서브커맨드 · 잘못된 인자는 exit 2 + stderr usage', () {
      for (final List<String> args in <List<String>>[
        <String>['bogus'],
        <String>['scan', 'extra'],
        <String>['push', '--force'],
        <String>['push', '--apply', 'extra'],
      ]) {
        final ProcessResult result = _runKit(args, sb, argErrorOnly: true);
        expect(result.exitCode, 2, reason: '${args.join(' ')} → exit 2');
        expect(_err(result), contains('usage:'), reason: args.join(' '));
      }
      expect(Directory(sb.work).existsSync(), isFalse, reason: '부작용 0');
    }, skip: skipScript);

    test('T-174-PUB-02: WORK 가 build/ 밖이거나 .. 를 품으면 exit 1 FAIL', () {
      final String outside = Directory.systemTemp.path;
      final ProcessResult out = _runKit(
        <String>['scan'],
        sb,
        work: '$outside/kit-publish-outside-work',
      );
      expect(out.exitCode, 1);
      expect(_err(out), contains('FAIL:'));
      expect(
        Directory('$outside/kit-publish-outside-work').existsSync(),
        false,
      );

      final ProcessResult dots = _runKit(
        <String>['scan'],
        sb,
        work: '${sb.dir}/x/../work',
      );
      expect(dots.exitCode, 1);
      expect(_err(dots), contains('FAIL:'));
      expect(_err(dots), contains('..'));
    }, skip: skipScript);

    test('T-174-PUB-03: 무인자 + 없는 WORK 는 status 한 줄만 내고 WORK 를 만들지 않는다', () {
      final ProcessResult result = _runKit(<String>[], sb);
      expect(result.exitCode, 0, reason: _err(result));
      _expectLastLine(result, _noStatus);
      expect(Directory(sb.work).existsSync(), isFalse);
      expect(Directory(sb.dir).listSync().length, 0, reason: '아무것도 만들지 않는다');
    }, skip: skipScript);

    test('T-174-PUB-04: 공개 트리 모사 — 무인자는 안내, scan 은 유지보수자 전용 FAIL', () {
      final String tree = '${sb.dir}/tree';
      Directory('$tree/scripts').createSync(recursive: true);
      File(_scriptRel).copySync('$tree/scripts/publish_kit.sh');
      final String work = '$tree/build/work';
      final String script = '$tree/scripts/publish_kit.sh';

      final ProcessResult status = _runKit(
        <String>[],
        sb,
        work: work,
        script: script,
      );
      expect(status.exitCode, 0, reason: _err(status));
      expect(status.stdout as String, contains('규칙 파일이 없는 트리'));
      _expectLastLine(status, _noStatus);
      expect(Directory(work).existsSync(), isFalse);

      final ProcessResult scan = _runKit(
        <String>['scan'],
        sb,
        work: work,
        script: script,
      );
      expect(scan.exitCode, 1);
      expect(_err(scan), contains('FAIL:'));
      expect(_err(scan), contains('유지보수자 전용'));
    }, skip: skipScript);
  });

  group('무인자 status 와 단계 표시 (D-29, 유지보수자 트리)', () {
    test('T-174-PUB-05: mirror main 해시와 같은 표시만 ok, 다른 해시는 - 로 남는다', () {
      final String main = _initMirror(sb);
      _writeStamp(sb, 'mirror', main);
      _writeStamp(sb, 'scan', main);
      _writeStamp(sb, 'verify', 'a' * 40);
      final ProcessResult result = _runKit(<String>[], sb);
      expect(result.exitCode, 0, reason: _err(result));
      _expectLastLine(
        result,
        'status: mirror=ok scan=ok verify=- check=- push=- main=$main',
      );
      expect(result.stdout as String, contains('[할 일] verify'));
    }, skip: skipRules);
  });

  group('scan 불변식 (D-16, 유지보수자 트리)', () {
    final String secret = '${<String>['AI', 'za'].join()}${'x' * 35}';
    final String sessionLine = <String>[
      'Claude',
      '-Session: https://example.invalid/s',
    ].join();

    // gitleaks 보고서 건수를 세는 도구(T-174-PUB-10) · jq 없는 PATH 를 꾸릴 도구(T-174-PUB-26).
    const List<String> skipJqTools = <String>['jq'];
    const List<String> jqlessTools = <String>['bash', 'git', 'dirname', 'rm'];

    ProcessResult runScan({bool findings = false}) => _runKit(
      <String>['scan'],
      sb,
      stubBin: _writeGitleaksStub(sb, findings: findings),
    );

    void expectNoLeak(ProcessResult result) {
      for (final String stream in <String>[
        result.stdout as String,
        _err(result),
      ]) {
        expect(stream.contains(secret), isFalse, reason: '키 모양 값이 출력됐다');
        expect(stream.contains('example.invalid/s'), isFalse);
      }
    }

    test(
      'T-174-PUB-06: 깨끗한 이력은 control 8 · invariant 10 · SCAN OK + scan.ok',
      () {
        final String main = _initMirror(sb);
        final ProcessResult result = runScan();
        expect(result.exitCode, 0, reason: _err(result));
        final List<String> lines = _outLines(result);
        expect(
          lines.where(
            (String l) => RegExp(r'^control: [a-z-]+=1$').hasMatch(l),
          ),
          hasLength(8),
        );
        expect(
          lines.where(
            (String l) =>
                RegExp(r'^invariant: (?!gitleaks)[a-z-]+=0$').hasMatch(l),
          ),
          hasLength(10),
        );
        expect(lines.last, 'SCAN OK main=$main gitleaks=0 invariants=10');
        expect(File('${sb.work}/scan.ok').readAsStringSync().trim(), main);
      },
      skip: skipRules,
    );

    test('T-174-PUB-07: 나중에 지워진 .planning 경로도 이력에 있으면 planning-paths FAIL', () {
      _initMirror(sb);
      _commit(sb.mirror, <String, String>{
        '.planning/x.md': 'x\n',
      }, 'docs: 계획 추가');
      _git(sb.mirror, <String>['rm', '-q', '.planning/x.md']);
      _commit(sb.mirror, <String, String>{}, 'docs: 계획 제거');
      final ProcessResult result = runScan();
      expect(result.exitCode, 1);
      expect(_err(result), contains('FAIL:'));
      expect(_err(result), contains('planning-paths'));
      expect(File('${sb.work}/scan.ok').existsSync(), isFalse);
      expectNoLeak(result);
    }, skip: skipRules);

    test('T-174-PUB-08: merge 충돌 해소에서만 들어온 키 모양 값도 aiza-blob FAIL (WR-01)', () {
      _initMirror(sb);
      _commit(sb.mirror, <String, String>{'f.txt': 'base\n'}, 'base');
      _git(sb.mirror, <String>['checkout', '-q', '-b', 'side']);
      _commit(sb.mirror, <String, String>{'f.txt': 'side\n'}, 'side');
      _git(sb.mirror, <String>['checkout', '-q', 'main']);
      _commit(sb.mirror, <String, String>{'f.txt': 'main\n'}, 'main');
      final ProcessResult merge = _gitRaw(sb.mirror, <String>[
        'merge',
        '--no-ff',
        '--no-commit',
        'side',
      ]);
      expect(merge.exitCode, isNot(0), reason: '충돌이 나야 시나리오가 성립한다');
      File('${sb.mirror}/f.txt').writeAsStringSync('key=$secret\n');
      _git(sb.mirror, <String>['add', 'f.txt']);
      _git(sb.mirror, <String>['commit', '-q', '-m', 'merge side']);
      // 두 부모 어디에도 값이 없다 — 병합 결과에만 있다.
      for (final String parent in <String>['HEAD^1', 'HEAD^2']) {
        expect(
          _git(sb.mirror, <String>['show', '$parent:f.txt']),
          isNot(contains(secret)),
        );
      }
      final ProcessResult result = runScan();
      expect(result.exitCode, 1);
      expect(_err(result), contains('aiza-blob'));
      expect(File('${sb.work}/scan.ok').existsSync(), isFalse);
      expectNoLeak(result);
    }, skip: skipRules);

    test('T-174-PUB-09: 커밋 메시지의 세션 트레일러 줄은 claude-session-message FAIL', () {
      _initMirror(sb);
      _commit(
        sb.mirror,
        <String, String>{'a.txt': 'a\n'},
        'feat: 기능',
        extra: <String>[sessionLine],
      );
      final ProcessResult result = runScan();
      expect(result.exitCode, 1);
      expect(_err(result), contains('claude-session-message'));
      expectNoLeak(result);
    }, skip: skipRules);

    test(
      'T-174-PUB-10: gitleaks 가 찾으면 건수만 말하고 FAIL, scan.ok 는 없다',
      () {
        _initMirror(sb);
        final ProcessResult result = runScan(findings: true);
        expect(result.exitCode, 1);
        expect(_err(result), contains('gitleaks 가 1건을'));
        expect(File('${sb.work}/scan.ok').existsSync(), isFalse);
      },
      skip: skipRules == false
          ? _skipUnlessToolsOnPath(skipJqTools)
          : skipRules,
    );

    test(
      'T-174-PUB-26: jq 가 PATH 에 없으면 검사 전에 jq 부재를 사유로 FAIL (WR-07)',
      () {
        _initMirror(sb);
        // PATH 를 이 디렉터리 하나로 좁힌다 — jq 확인까지 스크립트가 쓰는 도구만 링크하고
        // jq 는 두지 않는다. 가짜 gitleaks 는 결과를 내므로, jq 확인이 없으면 jq length
        // 단계까지 가서 다른 사유로 멈춘다.
        final String bin = _writeGitleaksStub(sb, findings: true);
        for (final String tool in jqlessTools) {
          Link('$bin/$tool').createSync(_findToolOnPath(tool)!);
        }
        expect(
          Directory(
            bin,
          ).listSync().map((FileSystemEntity e) => e.uri.pathSegments.last),
          isNot(contains('jq')),
        );
        final ProcessResult result = _runKit(
          <String>['scan'],
          sb,
          pathOverride: bin,
        );
        expect(result.exitCode, 1, reason: _err(result));
        expect(
          _err(result).trimRight().split('\n').last,
          startsWith('FAIL: jq 가 PATH 에 없다'),
        );
        expect(result.stdout as String, isNot(contains('control:')));
        expect(File('${sb.work}/scan.ok').existsSync(), isFalse);
      },
      skip: skipRules == false
          ? _skipUnlessToolsOnPath(jqlessTools)
          : skipRules,
    );
  });

  group('check 안전 게이트 (D-29, 유지보수자 트리)', () {
    test('T-174-PUB-11: ORIGIN 과 PUBLIC 이 같으면 FAIL', () {
      _initMirror(sb);
      final ProcessResult result = _runKit(
        <String>['check'],
        sb,
        publicRepo: sb.origin,
      );
      expect(result.exitCode, 1);
      expect(_err(result), contains('이 같다'));
    }, skip: skipRules);

    test('T-174-PUB-12: PUBLIC 저장소 이름이 ORIGIN 과 같으면 경로가 달라도 FAIL (WR-03)', () {
      _initMirror(sb);
      final String clone = '${sb.dir}/other/flutter_starter_kit.git';
      _initBare(clone);
      final ProcessResult result = _runKit(
        <String>['check'],
        sb,
        publicRepo: clone,
      );
      expect(result.exitCode, 1);
      expect(_err(result), contains('저장소 이름'));
      expect(File('${sb.work}/check.ok').existsSync(), isFalse);
    }, skip: skipRules);

    test('T-174-PUB-13: 빈 공개 저장소는 first-publish 로 통과하고 check.ok 를 쓴다', () {
      final String main = _initMirror(sb);
      _initBare(sb.publicRepo);
      final ProcessResult result = _runKit(<String>['check'], sb);
      expect(result.exitCode, 0, reason: _err(result));
      _expectLastLine(result, 'CHECK OK first-publish main=$main');
      expect(File('${sb.work}/check.ok').readAsStringSync().trim(), main);
    }, skip: skipRules);

    test('T-174-PUB-14: main 없이 다른 ref(master)만 있으면 빈 저장소가 아니라 FAIL', () {
      final String main = _initMirror(sb);
      _initBare(sb.publicRepo);
      _pushRef(sb.mirror, sb.publicRepo, main, 'refs/heads/master');
      final ProcessResult result = _runKit(<String>['check'], sb);
      expect(result.exitCode, 1);
      expect(_err(result), contains('빈 저장소가 아니다'));
      expect(File('${sb.work}/check.ok').existsSync(), isFalse);
    }, skip: skipRules);

    test('T-174-PUB-15: 공개 main · v* 태그가 조상이면 통과하고 비교용 ref 를 걷어낸다', () {
      final String c1 = _initMirror(sb);
      final String c2 = _commit(sb.mirror, <String, String>{
        'lib/b.dart': 'b\n',
      }, 'feat: 둘째');
      _initBare(sb.publicRepo);
      _pushRef(sb.mirror, sb.publicRepo, c1, 'refs/heads/main');
      _pushRef(sb.mirror, sb.publicRepo, c1, 'refs/tags/v0.1.0');
      final ProcessResult result = _runKit(<String>['check'], sb);
      expect(result.exitCode, 0, reason: _err(result));
      _expectLastLine(result, 'CHECK OK main=$c2 public-main=$c1 tags=1');
      expect(File('${sb.work}/check.ok').readAsStringSync().trim(), c2);
      expect(_refsInMirror(sb), isEmpty, reason: 'refs/public* 가 남았다');
    }, skip: skipRules);

    test('T-174-PUB-16: 공개 main 이 조상이 아니면 FAIL · 낡은 check.ok 삭제 · ref 정리', () {
      final String main = _initMirror(sb);
      _writeStamp(sb, 'check', main);
      final String other = '${sb.dir}/unrelated';
      _initRepo(other);
      final String foreign = _commit(other, <String, String>{
        'z.txt': 'z\n',
      }, 'unrelated');
      _initBare(sb.publicRepo);
      _pushRef(other, sb.publicRepo, foreign, 'refs/heads/main');
      final ProcessResult result = _runKit(<String>['check'], sb);
      expect(result.exitCode, 1);
      expect(_err(result), contains('재생성 이력에 없다'));
      expect(File('${sb.work}/check.ok').existsSync(), isFalse);
      expect(_refsInMirror(sb), isEmpty);
    }, skip: skipRules);

    test('T-174-PUB-17: 공개 v* 태그가 조상이 아닌 커밋이면 FAIL', () {
      final String c1 = _initMirror(sb);
      _commit(sb.mirror, <String, String>{'lib/b.dart': 'b\n'}, 'feat: 둘째');
      final String other = '${sb.dir}/unrelated';
      _initRepo(other);
      final String foreign = _commit(other, <String, String>{
        'z.txt': 'z\n',
      }, 'unrelated');
      _initBare(sb.publicRepo);
      _pushRef(sb.mirror, sb.publicRepo, c1, 'refs/heads/main');
      _pushRef(other, sb.publicRepo, foreign, 'refs/tags/v9.9.9');
      final ProcessResult result = _runKit(<String>['check'], sb);
      expect(result.exitCode, 1);
      expect(_err(result), contains('v9.9.9'));
      expect(File('${sb.work}/check.ok').existsSync(), isFalse);
      expect(_refsInMirror(sb), isEmpty);
    }, skip: skipRules);
  });

  group('push dry-run 게이트 (D-29, 유지보수자 트리)', () {
    String lsRemote() => _git(sb.dir, <String>['ls-remote', sb.publicRepo]);

    test('T-174-PUB-18: 단계 표시가 없거나 낡으면 먼저 통과해야 한다 FAIL', () {
      _buildKitMirror(sb, stamps: const <String>[]);
      _initBare(sb.publicRepo);
      final ProcessResult none = _runKit(<String>['push'], sb);
      expect(none.exitCode, 1);
      expect(_err(none), contains('먼저 통과해야'));

      for (final String step in <String>['mirror', 'scan', 'verify']) {
        _writeStamp(sb, step, _git(sb.mirror, <String>['rev-parse', 'HEAD']));
      }
      _writeStamp(sb, 'check', 'b' * 40);
      final ProcessResult stale = _runKit(<String>['push'], sb);
      expect(stale.exitCode, 1);
      expect(_err(stale), contains('check'));
      expect(_err(stale), contains('먼저 통과해야'));
    }, skip: skipRules);

    test('T-174-PUB-19: 표시 4개가 모두 맞으면 dry-run 만 — 공개 저장소 · mirror 태그 불변', () {
      final String c1 = _initMirror(sb);
      _initBare(sb.publicRepo);
      _pushRef(sb.mirror, sb.publicRepo, c1, 'refs/heads/main');
      final String main = _buildKitMirror(sb);
      final String before = lsRemote();
      final ProcessResult result = _runKit(<String>['push'], sb);
      expect(result.exitCode, 0, reason: _err(result));
      _expectLastLine(result, 'DRY-RUN OK push tag=v$_version main=$main');
      expect(result.stdout as String, contains('push --atomic'));
      expect(lsRemote(), before, reason: '공개 저장소가 바뀌었다');
      expect(_git(sb.mirror, <String>['tag', '--list']), isEmpty);
      expect(File('${sb.work}/push.ok').existsSync(), isFalse);
    }, skip: skipRules);

    test('T-174-PUB-20: KIT_VERSION 모양이 틀리거나 한 줄이 아니면 FAIL', () {
      _initBare(sb.publicRepo);
      for (final String bad in <String>[
        '1.0\n',
        'v1.0.0\n',
        '1.0.0\n2.0.0\n',
      ]) {
        _buildKitMirror(sb, versionFile: bad);
        final ProcessResult result = _runKit(<String>['push'], sb);
        expect(result.exitCode, 1, reason: bad);
        expect(_err(result), contains('KIT_VERSION'), reason: bad);
      }
    }, skip: skipRules);

    test('T-174-PUB-21: CHANGELOG 에 그 판 절이 없으면 FAIL', () {
      _initBare(sb.publicRepo);
      _buildKitMirror(sb, changelog: _defaultChangelog('1.0.0-rc.8'));
      final ProcessResult result = _runKit(<String>['push'], sb);
      expect(result.exitCode, 1);
      expect(_err(result), contains('CHANGELOG.md'));
    }, skip: skipRules);

    test('T-174-PUB-22: 공개 저장소의 같은 태그가 다른 커밋이면 FAIL, 같은 커밋이면 건너뛴다', () {
      final String c1 = _initMirror(sb);
      _initBare(sb.publicRepo);
      _pushRef(sb.mirror, sb.publicRepo, c1, 'refs/heads/main');
      final String main = _buildKitMirror(sb);

      _pushRef(sb.mirror, sb.publicRepo, c1, 'refs/tags/v$_version');
      final ProcessResult moved = _runKit(<String>['push'], sb);
      expect(moved.exitCode, 1);
      expect(_err(moved), contains('다른 커밋'));

      _git(sb.mirror, <String>[
        'push',
        '-q',
        '-f',
        sb.publicRepo,
        '$main:refs/tags/v$_version',
      ]);
      final ProcessResult same = _runKit(<String>['push'], sb);
      expect(same.exitCode, 0, reason: _err(same));
      expect(same.stdout as String, contains('이미 같은 커밋에 있다'));
    }, skip: skipRules);
  });

  group('release dry-run 게이트 (D-22 · D-29, 유지보수자 트리)', () {
    test('T-174-PUB-23: push 표시가 없으면 FAIL', () {
      _buildKitMirror(sb);
      final ProcessResult result = _runKit(<String>['release'], sb);
      expect(result.exitCode, 1);
      expect(_err(result), contains('push'));
      expect(_err(result), contains('먼저 통과해야'));
    }, skip: skipRules);

    test('T-174-PUB-24: push 표시가 있으면 pre-release 명령 + notes 에 링크 정의가 없다', () {
      _buildKitMirror(
        sb,
        stamps: const <String>['mirror', 'scan', 'verify', 'check', 'push'],
      );
      final ProcessResult result = _runKit(<String>['release'], sb);
      expect(result.exitCode, 0, reason: _err(result));
      final String out = result.stdout as String;
      expect(out, contains('command: gh release create v$_version'));
      expect(out, contains('--prerelease'));
      expect(out, contains('--repo example-owner/public-kit'));
      _expectLastLine(result, 'DRY-RUN OK release tag=v$_version');

      final String notes = File(
        '${sb.work}/release-notes-$_version.md',
      ).readAsStringSync();
      expect(notes, contains('### Added'));
      expect(notes, contains('첫 항목'));
      expect(
        notes
            .split('\n')
            .where((String l) => RegExp(r'^\[[^\]]+\]: ').hasMatch(l)),
        isEmpty,
        reason: '링크 정의 줄이 notes 에 들어갔다',
      );
    }, skip: skipRules);

    test('T-174-PUB-25: Release 저장소 이름이 private 와 같으면 FAIL', () {
      _buildKitMirror(
        sb,
        stamps: const <String>['mirror', 'scan', 'verify', 'check', 'push'],
      );
      final ProcessResult result = _runKit(
        <String>['release'],
        sb,
        repo: 'someone/flutter_starter_kit',
      );
      expect(result.exitCode, 1);
      expect(_err(result), contains('KIT_PUBLISH_REPO'));
    }, skip: skipRules);
  });
}
