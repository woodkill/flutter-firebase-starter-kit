// `scripts/firebase-configure.sh` 의 Firebase 프로젝트 ID 출처 계약 — DRY_RUN 실제 실행.
//
// 스크립트는 `config/<flavor>.json` 의 `firebaseProjectId` 를 먼저 쓰고, 그 값이
// 비었거나 example 자리표시(`your-project-<flavor>`)거나 config 파일이 없을 때만
// `PROJECT_ID_PREFIX` 상수로 프로젝트 ID 를 정한다. 어느 출처를 썼는지는 식별자
// 블록의 `project source:` 한 줄로 남는다.
//
// **실행 위치:** DRY_RUN 실행도 tracked 산출물에 `git update-index --skip-worktree` 를
// 실제로 건다. 그래서 이 테스트는 실제 저장소에서 스크립트를 돌리지 않는다 — 임시
// 디렉터리에 `git init` 한 저장소를 만들고 스크립트 사본과 config fixture 만 둔 뒤
// 그 안에서 실행한다. 산출물 파일을 커밋하지 않으므로 skip-worktree 단계는 아무 것도
// 하지 않는다.
//
// **환경:** 부모 환경을 물려받지 않는다(`includeParentEnvironment: false`). PATH 는
// 임시 도구 디렉터리 하나이고, 그 안에 스크립트가 DRY_RUN 경로에서 부르는 외부 명령
// (`git` · `cat` · `jq`)의 심볼릭 링크만 둔다. 다른 명령(flutterfire · fvm · ruby)을
// 부르는 회귀가 생기면 「명령 없음」 으로 바로 드러난다.
//
// **fallback 기대값:** 킷 기본 prefix 를 테스트에 적지 않는다 — 복사한 사본의
// `PROJECT_ID_PREFIX="…"` 줄에서 읽는다. 앱 정체성을 바꿔 그 상수가 달라진 저장소
// 에서도 이 테스트가 그대로 통과한다.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _scriptPath = 'scripts/firebase-configure.sh';
const String _completeLine = '✓ Firebase configure complete for dev';
const String _noJqReason = 'PATH 에 jq 가 없어 config 를 읽는 경우는 건너뜀';

/// 사본에서 prefix 상수 줄을 찾는 정규식(줄 단독 일치).
final RegExp _prefixLinePattern = RegExp(
  r'^PROJECT_ID_PREFIX="([^"]+)"$',
  multiLine: true,
);

/// [tool] 의 절대경로를 부모 PATH 에서 찾아 돌려준다. 없으면 `null`.
String? findToolOnPath(String tool) {
  final ProcessResult result = Process.runSync('which', <String>[tool]);
  if (result.exitCode != 0) {
    return null;
  }
  final String found = (result.stdout as String).trim();
  return found.isEmpty ? null : found;
}

/// 임시 git 저장소 하나 — 스크립트 사본 · config fixture · 도구 디렉터리를 담는다.
class ConfigureSandbox {
  ConfigureSandbox._(this.root);

  /// 임시 디렉터리에 git 저장소를 만들고 스크립트 사본을 둔다.
  factory ConfigureSandbox.create() {
    final Directory dir = Directory.systemTemp.createTempSync(
      'firebase-configure-source-',
    );
    final ProcessResult init = Process.runSync('git', <String>[
      'init',
      '-q',
    ], workingDirectory: dir.path);
    expect(init.exitCode, 0, reason: 'git init 실패: ${init.stderr}');
    Directory('${dir.path}/scripts').createSync();
    File(_scriptPath).copySync('${dir.path}/$_scriptPath');
    return ConfigureSandbox._(dir.path);
  }

  /// 임시 저장소 루트 절대경로.
  final String root;

  /// 스크립트 사본 파일.
  File get scriptCopy => File('$root/$_scriptPath');

  /// 사본의 `PROJECT_ID_PREFIX` 상수 값을 읽는다 — 그 줄이 정확히 1개여야 한다.
  String readPrefixFromCopy() {
    final List<RegExpMatch> matches = _prefixLinePattern
        .allMatches(scriptCopy.readAsStringSync())
        .toList();
    expect(
      matches.length,
      1,
      reason: '사본에 PROJECT_ID_PREFIX="…" 줄이 정확히 1개여야 한다',
    );
    return matches.single.group(1)!;
  }

  /// 사본의 `PROJECT_ID_PREFIX` 상수 줄을 [prefix] 로 바꾼다(앱 정체성을 바꾼 저장소 모양).
  void replacePrefixInCopy(String prefix) {
    final String source = scriptCopy.readAsStringSync();
    expect(_prefixLinePattern.allMatches(source).length, 1);
    final String replaced = source.replaceFirst(
      _prefixLinePattern,
      'PROJECT_ID_PREFIX="$prefix"',
    );
    scriptCopy.writeAsStringSync(replaced);
    expect(readPrefixFromCopy(), prefix);
  }

  /// `config/dev.json` 을 `firebaseProjectId` 값 [projectId] 로 쓴다.
  void writeDevConfig(String projectId) {
    Directory('$root/config').createSync(recursive: true);
    File('$root/config/dev.json').writeAsStringSync(
      jsonEncode(<String, String>{
        'appName': 'Acme',
        'firebaseProjectId': projectId,
      }),
    );
  }

  /// 도구 디렉터리를 만들고 경로를 돌려준다 — [tools] 의 심볼릭 링크만 담는다.
  ///
  /// 부모 PATH 에서 찾지 못한 도구가 있으면 테스트를 실패시킨다.
  String createToolDir(List<String> tools, {required String name}) {
    final bin = Directory('$root/$name')..createSync();
    for (final tool in tools) {
      final String? target = findToolOnPath(tool);
      expect(target, isNotNull, reason: '부모 PATH 에 $tool 이 있어야 한다');
      Link('${bin.path}/$tool').createSync(target!);
    }
    return bin.path;
  }

  /// `DRY_RUN=1 bash scripts/firebase-configure.sh dev` 를 [toolDir] 만 PATH 로 실행한다.
  ProcessResult runDryRun(String toolDir) {
    final home = Directory('$root/home')..createSync();
    return Process.runSync(
      '/bin/bash',
      <String>[_scriptPath, 'dev'],
      workingDirectory: root,
      environment: <String, String>{
        'PATH': toolDir,
        'HOME': home.path,
        'DRY_RUN': '1',
      },
      includeParentEnvironment: false,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
  }

  /// 임시 디렉터리를 지운다.
  void dispose() {
    final dir = Directory(root);
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  }
}

/// [output] 에서 `<label>:` 줄의 값을 돌려준다(앞뒤 공백 제거). 없으면 `null`.
String? readLabeledValue(String output, String label) {
  final pattern = RegExp(
    '^\\s*${RegExp.escape(label)}:\\s*(.*?)\\s*\$',
    multiLine: true,
  );
  return pattern.firstMatch(output)?.group(1);
}

/// [output] 의 마지막 비어 있지 않은 줄을 돌려준다.
String readLastLine(String output) {
  final List<String> lines = const LineSplitter()
      .convert(output)
      .where((String line) => line.trim().isNotEmpty)
      .toList();
  return lines.isEmpty ? '' : lines.last;
}

void main() {
  final hasJq = findToolOnPath('jq') != null;
  late ConfigureSandbox sandbox;

  setUp(() {
    sandbox = ConfigureSandbox.create();
  });

  tearDown(() {
    sandbox.dispose();
  });

  group('firebase-configure.sh 프로젝트 ID 출처 (DRY_RUN 실행)', () {
    test('T-19-CONFIGURE-01: config 의 firebaseProjectId 를 프로젝트 ID 로 쓴다', () {
      sandbox.writeDevConfig('acme-app-dev');
      final String toolDir = sandbox.createToolDir(<String>[
        'git',
        'cat',
        'jq',
      ], name: 'tools');

      final ProcessResult result = sandbox.runDryRun(toolDir);
      final stdout = result.stdout as String;

      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      expect(readLabeledValue(stdout, 'project'), 'acme-app-dev');
      expect(
        readLabeledValue(stdout, 'project source'),
        startsWith('config/dev.json'),
      );
      expect(readLastLine(stdout), _completeLine);
    }, skip: hasJq ? false : _noJqReason);

    test('T-19-CONFIGURE-02: 자리표시 값이면 PROJECT_ID_PREFIX 상수로 정한다', () {
      sandbox.writeDevConfig('your-project-dev');
      final String prefix = sandbox.readPrefixFromCopy();
      final String toolDir = sandbox.createToolDir(<String>[
        'git',
        'cat',
        'jq',
      ], name: 'tools');

      final ProcessResult result = sandbox.runDryRun(toolDir);
      final stdout = result.stdout as String;

      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      expect(readLabeledValue(stdout, 'project'), '$prefix-dev');
      expect(
        readLabeledValue(stdout, 'project source'),
        startsWith('PROJECT_ID_PREFIX'),
      );
      expect(readLastLine(stdout), _completeLine);
    }, skip: hasJq ? false : _noJqReason);

    test('T-19-CONFIGURE-03: config 파일이 없으면 바뀐 상수로 정하고 jq 없이 끝난다', () {
      // 앱 정체성을 바꾼 저장소 모양 — 상수 줄이 킷 기본값이 아니다.
      sandbox.replacePrefixInCopy('acme-renamed');
      // config 가 없으면 jq 를 부르지 않는다 — 도구 디렉터리에 jq 를 두지 않는다.
      final String toolDir = sandbox.createToolDir(<String>[
        'git',
        'cat',
      ], name: 'tools-no-jq');

      final ProcessResult result = sandbox.runDryRun(toolDir);
      final stdout = result.stdout as String;

      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      expect(readLabeledValue(stdout, 'project'), 'acme-renamed-dev');
      expect(
        readLabeledValue(stdout, 'project source'),
        startsWith('PROJECT_ID_PREFIX'),
      );
      expect(readLastLine(stdout), _completeLine);
    });

    test('T-19-CONFIGURE-04: 형식이 잘못된 firebaseProjectId 는 거부한다', () {
      final String toolDir = sandbox.createToolDir(<String>[
        'git',
        'cat',
        'jq',
      ], name: 'tools');

      for (final invalid in <String>['-oops', 'Acme-Dev']) {
        sandbox.writeDevConfig(invalid);

        final ProcessResult result = sandbox.runDryRun(toolDir);
        final stderr = result.stderr as String;

        expect(result.exitCode, 1, reason: '값 $invalid 는 거부해야 한다');
        expect(stderr, contains('firebaseProjectId'));
        expect(stderr, contains('형식'));
        expect(result.stdout as String, isNot(contains(_completeLine)));
      }
    }, skip: hasJq ? false : _noJqReason);

    test('T-19-CONFIGURE-05: config 가 있는데 jq 가 없으면 상수로 넘어가지 않고 거부한다', () {
      sandbox.writeDevConfig('acme-app-dev');
      final String toolDir = sandbox.createToolDir(<String>[
        'git',
        'cat',
      ], name: 'tools-no-jq');

      final ProcessResult result = sandbox.runDryRun(toolDir);

      expect(result.exitCode, 1);
      expect(result.stderr as String, contains('jq'));
      expect(result.stdout as String, isNot(contains(_completeLine)));
    });
  });
}
