// 설정 위저드 진입 셸(setup.sh)의 분기를 PATH 스텁으로 실행해 고정한다.
//
// uname · brew · fvm 은 임시 디렉터리의 스텁만 쓴다 — 스텁은 받은 인자를 로그
// 파일에 한 줄씩 덧붙이고 exit 0 이다. PATH 는 `<stub-bin>:/usr/bin:/bin` 으로만
// 두고 부모 환경을 물려받지 않아, 실제 brew · fvm 에 닿지 않는다. 표준 입력은
// 터미널이 아니므로 설치 확인은 언제나 「아니요」 다.

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

const String _scriptRel = 'setup.sh';

/// `.fvmrc` 를 읽지 못했을 때 setup.sh 가 표준 오류에 내는 안내(원문 그대로).
const String _fvmrcMissingLine =
    '.fvmrc 에서 Flutter 판을 읽지 못했습니다 — 저장소 루트의 .fvmrc 에 flutter 판 값이 있어야 합니다.';

/// `sed` 가 없는 파일을 읽으려 할 때의 오류 문구 — 출력에 나오면 안 된다.
const String _missingFileError = 'No such file or directory';

/// 스크립트가 있으면 `false`, 없으면 건너뛸 사유를 돌려준다.
Object _skipUnlessScript() =>
    File(_scriptRel).existsSync() ? false : '$_scriptRel 이 없는 사본 — 건너뜀';

/// 스텁 실행 파일 · 로그를 담는 임시 디렉터리.
final class _Sandbox {
  _Sandbox(this.dir)
    : stubBin = Directory('${dir.path}/stub-bin')..createSync(recursive: true),
      home = Directory('${dir.path}/home')..createSync(recursive: true);

  final Directory dir;
  final Directory stubBin;
  final Directory home;

  File get fvmLog => File('${dir.path}/fvm.log');
  File get brewLog => File('${dir.path}/brew.log');

  /// `uname` 스텁을 만든다 — 인자와 무관하게 [system] 을 출력한다.
  void writeUname(String system) =>
      _writeStub('uname', '#!/bin/sh\necho $system\n');

  /// 받은 인자를 [log] 에 덧붙이고 exit 0 인 [name] 스텁을 만든다.
  void writeRecorder(String name, File log) => _writeStub(
    name,
    '#!/bin/sh\nprintf \'%s\\n\' "\$*" >> \'${log.path}\'\nexit 0\n',
  );

  void _writeStub(String name, String body) {
    final File stub = File('${stubBin.path}/$name')..writeAsStringSync(body);
    Process.runSync('chmod', <String>['+x', stub.path]);
  }

  /// [log] 의 줄 목록 — 파일이 없으면 빈 목록.
  List<String> readLines(File log) =>
      log.existsSync() ? log.readAsLinesSync() : const <String>[];
}

/// [script] 를 zsh 로 실행한다 — PATH 는 스텁 디렉터리와 시스템 기본 경로뿐이다.
ProcessResult _runSetup(_Sandbox sb, {String script = _scriptRel}) {
  return Process.runSync(
    '/bin/zsh',
    <String>[script, '--probe'],
    environment: <String, String>{
      'PATH': '${sb.stubBin.path}:/usr/bin:/bin',
      'HOME': sb.home.path,
    },
    includeParentEnvironment: false,
    workingDirectory: Directory.current.path,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
}

/// 표준 출력 · 표준 오류를 이어 붙인다.
String _combinedOutput(ProcessResult result) =>
    '${result.stdout}\n${result.stderr}';

void main() {
  late _Sandbox sb;

  setUp(() {
    sb = _Sandbox(Directory.systemTemp.createTempSync('setup_sh_test_'));
  });

  tearDown(() {
    sb.dir.deleteSync(recursive: true);
  });

  group('setup.sh 진입 검사', skip: _skipUnlessScript(), () {
    test('T-19-SH-01 macOS 가 아니면 안내하고 1 로 끝나며 fvm 을 부르지 않는다', () {
      sb
        ..writeUname('Linux')
        ..writeRecorder('brew', sb.brewLog)
        ..writeRecorder('fvm', sb.fvmLog);

      final ProcessResult result = _runSetup(sb);

      expect(result.exitCode, 1);
      expect(_combinedOutput(result), contains('macOS'));
      expect(sb.fvmLog.existsSync(), isFalse);
      expect(sb.brewLog.existsSync(), isFalse);
    });

    test('T-19-SH-02 Homebrew 가 PATH 에 없으면 안내하고 1 로 끝난다', () {
      sb
        ..writeUname('Darwin')
        ..writeRecorder('fvm', sb.fvmLog);

      final ProcessResult result = _runSetup(sb);

      expect(result.exitCode, 1);
      expect(_combinedOutput(result), contains('Homebrew'));
      expect(sb.fvmLog.existsSync(), isFalse);
    });

    test('T-19-SH-03 FVM 이 없으면 설치 명령을 보이고 비터미널 입력에서는 설치하지 않는다', () {
      sb
        ..writeUname('Darwin')
        ..writeRecorder('brew', sb.brewLog);

      final ProcessResult result = _runSetup(sb);

      final String output = _combinedOutput(result);
      expect(result.exitCode, 1);
      expect(output, contains('brew install btwld/fvm/fvm'));
      expect(output, contains('설치하지 않았습니다'));
      expect(
        sb
            .readLines(sb.brewLog)
            .where((String line) => line.contains('install')),
        isEmpty,
      );
    });

    test('T-19-SH-04 brew · fvm 이 있으면 .fvmrc 판을 명시해 설치한 뒤 위저드로 넘긴다', () {
      sb
        ..writeUname('Darwin')
        ..writeRecorder('brew', sb.brewLog)
        ..writeRecorder('fvm', sb.fvmLog);
      final Object? fvmrc = jsonDecode(File('.fvmrc').readAsStringSync());
      final String flutterVersion = switch (fvmrc) {
        {'flutter': final String version} => version,
        _ => fail('.fvmrc 에 flutter 판이 없다'),
      };

      final ProcessResult result = _runSetup(sb);

      expect(result.exitCode, 0, reason: _combinedOutput(result));
      final List<String> lines = sb.readLines(sb.fvmLog);
      expect(lines, hasLength(2));
      expect(lines[0], 'install $flutterVersion');
      expect(lines[1], 'dart run bin/setup.dart --probe');
    });

    test('T-19-SH-05 셸 설정 파일로 리다이렉션하는 줄이 없다', () {
      final List<String> codeLines = File(_scriptRel)
          .readAsLinesSync()
          .where((String line) => !line.trimLeft().startsWith('#'))
          .toList();
      final RegExp rcRedirect = RegExp(
        r'''>>?\s*["']?\S*(\.zshrc|\.zprofile|\.bash_profile)''',
      );

      expect(codeLines.where(rcRedirect.hasMatch), isEmpty);
    });

    test('T-19-SH-06 .fvmrc 가 없으면 표준 오류에 안내 한 줄을 내고 설치하지 않는다', () {
      sb
        ..writeUname('Darwin')
        ..writeRecorder('brew', sb.brewLog)
        ..writeRecorder('fvm', sb.fvmLog);
      final Directory copy = Directory('${sb.dir.path}/copy')..createSync();
      final File script = File(_scriptRel).copySync('${copy.path}/setup.sh');

      final ProcessResult result = _runSetup(sb, script: script.path);

      final String stderrText = result.stderr as String;
      expect(result.exitCode, 1);
      expect(_fvmrcMissingLine.allMatches(stderrText).length, 1);
      expect(_combinedOutput(result), isNot(contains(_missingFileError)));
      expect(
        sb
            .readLines(sb.fvmLog)
            .where((String line) => line.contains('install')),
        isEmpty,
      );
    });
  });
}
