// 설정 위저드 진입 셸(setup.sh)의 분기를 PATH 스텁으로 실행해 고정한다.
//
// uname · brew · fvm 은 임시 디렉터리의 스텁만 쓴다 — 스텁은 받은 인자를 로그
// 파일에 한 줄씩 덧붙이고 exit 0 이다(실패 스텁은 정한 인자에서만 원문 한 줄을
// 표준 오류에 쓰고 정한 코드로 끝난다). PATH 는 `<stub-bin>:/usr/bin:/bin` 으로만
// 두고 부모 환경을 물려받지 않아, 실제 brew · fvm 에 닿지 않는다. 표준 입력은
// 터미널이 아니므로 설치 확인은 언제나 「아니요」 다.
//
// 터미널 상태 저장 · 복원 시험은 stty 스텁을 쓴다 — 받은 인자를 fvm 스텁과 같은
// 호출 기록 파일에 덧붙여 호출 순서를 한 파일로 본다. stty 를 스텁하지 않은
// 시험은 실제 `/bin/stty` 가 터미널 아닌 입력에서 실패하므로 저장 · 복원 없이
// 진행한다. 신호 시험의 fvm 스텁은 위저드 단계에서 부모가 zsh 일 때만 그 부모에
// 신호를 보낸다 — 부모가 시험 실행기면 신호 없이 실패해 시험 실행기를 지킨다.

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

const String _scriptRel = 'setup.sh';

/// `.fvmrc` 를 읽지 못했을 때 setup.sh 가 표준 오류에 내는 안내(원문 그대로).
const String _fvmrcMissingLine =
    '.fvmrc 에서 Flutter 판을 읽지 못했습니다 — 저장소 루트의 .fvmrc 에 flutter 판 값이 있어야 합니다.';

/// `sed` 가 없는 파일을 읽으려 할 때의 오류 문구 — 출력에 나오면 안 된다.
const String _missingFileError = 'No such file or directory';

/// 패키지 받기가 실패했을 때 setup.sh 가 표준 오류에 더하는 안내(원문 그대로).
const String _pubGetFailedLine = '패키지를 받지 못했습니다 — 위 출력을 확인한 뒤 같은 명령을 다시 실행하세요.';

/// 실패 스텁이 패키지 받기에서 표준 오류에 쓰는 원문 한 줄.
const String _pubGetErrorLine = 'stub pub error: 패키지 저장소에 닿지 못했습니다';

/// 실패 스텁이 패키지 받기에서 돌려주는 종료 코드.
const int _pubGetExitCode = 69;

/// stty 스텁의 `-g` 가 출력하는 저장 상태 — 복원 호출의 인자로 돌아와야 한다.
const String _savedSttyState = 'gfmt1:stub-state';

/// stty 스텁이 저장(`-g`)에 실패할 때 표준 오류에 쓰는 원문 한 줄.
const String _sttySaveErrorLine = 'stub stty error: 상태를 읽지 못했습니다';

/// stty 스텁이 복원에 실패할 때 표준 오류에 쓰는 원문 한 줄.
const String _sttyRestoreErrorLine = 'stub stty error: 상태를 되돌리지 못했습니다';

/// 신호 스텁의 부모가 zsh 가 아닐 때 표준 오류에 쓰는 원문 한 줄.
const String _notZshParentLine = 'stub signal error: 부모가 zsh 가 아닙니다';

/// 신호 스텁이 부모가 zsh 가 아닐 때 돌려주는 종료 코드.
const int _notZshParentExitCode = 97;

/// 위저드 스텁이 표준 오류에 쓰는 줄의 머리 — 뒤에 종료 코드가 붙는다.
const String _wizardStderrPrefix = 'stub wizard exit ';

/// 위저드 스텁이 끝날 때 쓸 종료 코드(완료 · 멈춤 · 밖 작업 안내 · Ctrl-C).
const List<int> _wizardExitCodes = <int>[0, 1, 3, 130];

/// 위저드 자식이 부모 셸에 보낼 신호와 setup.sh 가 끝날 종료 코드.
const Map<String, int> _signalExitCodes = <String, int>{
  'INT': 130,
  'TERM': 143,
};

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

  /// fvm · stty 스텁이 같은 순서로 덧붙이는 호출 기록.
  File get callLog => File('${dir.path}/calls.log');

  /// `uname` 스텁을 만든다 — 인자와 무관하게 [system] 을 출력한다.
  void writeUname(String system) =>
      _writeStub('uname', '#!/bin/sh\necho $system\n');

  /// 받은 인자를 [log] 에 덧붙이고 exit 0 인 [name] 스텁을 만든다.
  void writeRecorder(String name, File log) => _writeStub(
    name,
    '#!/bin/sh\nprintf \'%s\\n\' "\$*" >> \'${log.path}\'\nexit 0\n',
  );

  /// 받은 인자를 [log] 에 덧붙이는 [name] 스텁을 만든다 — 앞 두 인자가
  /// [failWhenArgsStartWith] 와 같으면 표준 오류에 [stderrLine] 을 쓰고
  /// [exitCode] 로 끝나며, 그 밖에는 exit 0 이다.
  void writeFailingRecorder(
    String name,
    File log, {
    required String failWhenArgsStartWith,
    required int exitCode,
    required String stderrLine,
  }) => _writeStub(
    name,
    '#!/bin/sh\n'
    'printf \'%s\\n\' "\$*" >> \'${log.path}\'\n'
    'if [ "\$1 \$2" = \'$failWhenArgsStartWith\' ]; then\n'
    '  printf \'%s\\n\' \'$stderrLine\' >&2\n'
    '  exit $exitCode\n'
    'fi\n'
    'exit 0\n',
  );

  /// 받은 인자를 `stty <인자>` 꼴로 [log] 에 덧붙이는 stty 스텁을 만든다.
  ///
  /// `-g` 는 [canSave] 면 [_savedSttyState] 를 출력하고 0, 아니면
  /// [_sttySaveErrorLine] 을 표준 오류에 쓰고 1 이다. 그 밖(복원)은
  /// [canRestore] 면 0, 아니면 [_sttyRestoreErrorLine] 을 쓰고 1 이다.
  void writeStty(File log, {bool canSave = true, bool canRestore = true}) {
    final saveBranch = canSave
        ? "  printf '%s\\n' '$_savedSttyState'\n  exit 0\n"
        : "  printf '%s\\n' '$_sttySaveErrorLine' >&2\n  exit 1\n";
    final restoreBranch = canRestore
        ? 'exit 0\n'
        : "printf '%s\\n' '$_sttyRestoreErrorLine' >&2\nexit 1\n";
    _writeStub(
      'stty',
      '#!/bin/sh\n'
          "printf 'stty %s\\n' \"\$*\" >> '${log.path}'\n"
          'if [ "\$1" = \'-g\' ]; then\n'
          '$saveBranch'
          'fi\n'
          '$restoreBranch',
    );
  }

  /// 받은 인자를 [log] 에 덧붙이는 [name] 스텁을 만든다 — 앞 두 인자가
  /// `dart run` 이면 부모가 zsh 일 때만 그 부모에 [signal] 을 보내고 0 으로
  /// 끝나며, 아니면 [_notZshParentLine] 을 표준 오류에 쓰고
  /// [_notZshParentExitCode] 로 끝난다. 그 밖의 인자는 exit 0 이다.
  void writeParentSignaler(String name, File log, {required String signal}) =>
      _writeStub(
        name,
        '#!/bin/sh\n'
        'printf \'%s\\n\' "\$*" >> \'${log.path}\'\n'
        'if [ "\$1 \$2" = \'dart run\' ]; then\n'
        '  case "\$(ps -o comm= -p "\$PPID")" in\n'
        '    *zsh)\n'
        '      kill -$signal "\$PPID"\n'
        '      exit 0\n'
        '      ;;\n'
        '  esac\n'
        '  printf \'%s\\n\' \'$_notZshParentLine\' >&2\n'
        '  exit $_notZshParentExitCode\n'
        'fi\n'
        'exit 0\n',
      );

  void _writeStub(String name, String body) {
    final stub = File('${stubBin.path}/$name')..writeAsStringSync(body);
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

/// 저장소 루트 `.fvmrc` 가 고정한 Flutter 판을 읽는다.
String _readFlutterVersion() {
  final Object? fvmrc = jsonDecode(File('.fvmrc').readAsStringSync());
  return switch (fvmrc) {
    {'flutter': final String version} => version,
    _ => fail('.fvmrc 에 flutter 판이 없다'),
  };
}

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

    test(
      'T-19-SH-04 brew · fvm 이 있으면 .fvmrc 판을 명시해 설치하고 패키지를 받은 뒤 위저드로 넘긴다',
      () {
        sb
          ..writeUname('Darwin')
          ..writeRecorder('brew', sb.brewLog)
          ..writeRecorder('fvm', sb.fvmLog);
        final String flutterVersion = _readFlutterVersion();

        final ProcessResult result = _runSetup(sb);

        expect(result.exitCode, 0, reason: _combinedOutput(result));
        final List<String> lines = sb.readLines(sb.fvmLog);
        expect(lines, hasLength(3));
        expect(lines[0], 'install $flutterVersion');
        expect(lines[1], 'flutter pub get');
        expect(lines[2], 'dart run bin/setup.dart --probe');
      },
    );

    test('T-19-SH-05 셸 설정 파일로 리다이렉션하는 줄이 없다', () {
      final List<String> codeLines = File(_scriptRel)
          .readAsLinesSync()
          .where((String line) => !line.trimLeft().startsWith('#'))
          .toList();
      final rcRedirect = RegExp(
        r'''>>?\s*["']?\S*(\.zshrc|\.zprofile|\.bash_profile)''',
      );

      expect(codeLines.where(rcRedirect.hasMatch), isEmpty);
    });

    test('T-19-SH-06 .fvmrc 가 없으면 표준 오류에 안내 한 줄을 내고 설치하지 않는다', () {
      sb
        ..writeUname('Darwin')
        ..writeRecorder('brew', sb.brewLog)
        ..writeRecorder('fvm', sb.fvmLog);
      final copy = Directory('${sb.dir.path}/copy')..createSync();
      final File script = File(_scriptRel).copySync('${copy.path}/setup.sh');

      final ProcessResult result = _runSetup(sb, script: script.path);

      final stderrText = result.stderr as String;
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

    test('T-19-SH-07 패키지 받기가 실패하면 원문과 안내를 보이고 그 종료 코드로 끝나며 위저드를 부르지 않는다', () {
      sb
        ..writeUname('Darwin')
        ..writeRecorder('brew', sb.brewLog)
        ..writeFailingRecorder(
          'fvm',
          sb.fvmLog,
          failWhenArgsStartWith: 'flutter pub',
          exitCode: _pubGetExitCode,
          stderrLine: _pubGetErrorLine,
        );
      final String flutterVersion = _readFlutterVersion();

      final ProcessResult result = _runSetup(sb);

      final stderrText = result.stderr as String;
      expect(result.exitCode, _pubGetExitCode, reason: _combinedOutput(result));
      expect(_pubGetErrorLine.allMatches(_combinedOutput(result)).length, 1);
      expect(_pubGetFailedLine.allMatches(stderrText).length, 1);
      final List<String> lines = sb.readLines(sb.fvmLog);
      expect(
        lines,
        containsAllInOrder(<String>[
          'install $flutterVersion',
          'flutter pub get',
        ]),
      );
      expect(
        lines.where((String line) => line.startsWith('dart run')),
        isEmpty,
      );
    });

    for (final int code in _wizardExitCodes) {
      test('T-20-SH-01 위저드가 $code 로 끝나면 터미널 상태를 저장 · 복원하고 같은 코드로 끝난다', () {
        sb
          ..writeUname('Darwin')
          ..writeRecorder('brew', sb.brewLog)
          ..writeFailingRecorder(
            'fvm',
            sb.callLog,
            failWhenArgsStartWith: 'dart run',
            exitCode: code,
            stderrLine: '$_wizardStderrPrefix$code',
          )
          ..writeStty(sb.callLog);
        final String flutterVersion = _readFlutterVersion();

        final ProcessResult result = _runSetup(sb);

        expect(result.exitCode, code, reason: _combinedOutput(result));
        expect(sb.readLines(sb.callLog), <String>[
          'install $flutterVersion',
          'flutter pub get',
          'stty -g',
          'dart run bin/setup.dart --probe',
          'stty $_savedSttyState',
        ]);
        expect(
          '$_wizardStderrPrefix$code'
              .allMatches(_combinedOutput(result))
              .length,
          1,
        );
      });
    }

    test('T-20-SH-02 입력이 터미널이 아니면 복원하지 않고 잡음 없이 위저드의 코드로 끝난다', () {
      sb
        ..writeUname('Darwin')
        ..writeRecorder('brew', sb.brewLog)
        ..writeFailingRecorder(
          'fvm',
          sb.callLog,
          failWhenArgsStartWith: 'dart run',
          exitCode: 3,
          stderrLine: '${_wizardStderrPrefix}3',
        )
        ..writeStty(sb.callLog, canSave: false);
      final String flutterVersion = _readFlutterVersion();

      final ProcessResult result = _runSetup(sb);

      expect(result.exitCode, 3, reason: _combinedOutput(result));
      expect(sb.readLines(sb.callLog), <String>[
        'install $flutterVersion',
        'flutter pub get',
        'stty -g',
        'dart run bin/setup.dart --probe',
      ]);
      expect(_combinedOutput(result), isNot(contains(_sttySaveErrorLine)));
    });

    test('T-20-SH-03 복원이 실패해도 오류 줄을 보이고 위저드의 코드로 끝난다', () {
      sb
        ..writeUname('Darwin')
        ..writeRecorder('brew', sb.brewLog)
        ..writeFailingRecorder(
          'fvm',
          sb.callLog,
          failWhenArgsStartWith: 'dart run',
          exitCode: 3,
          stderrLine: '${_wizardStderrPrefix}3',
        )
        ..writeStty(sb.callLog, canRestore: false);

      final ProcessResult result = _runSetup(sb);

      final stderrText = result.stderr as String;
      expect(result.exitCode, 3, reason: _combinedOutput(result));
      expect(sb.readLines(sb.callLog).last, 'stty $_savedSttyState');
      expect(_sttyRestoreErrorLine.allMatches(stderrText).length, 1);
    });

    for (final MapEntry<String, int> entry in _signalExitCodes.entries) {
      final String signal = entry.key;
      final int expectedCode = entry.value;
      test(
        'T-20-SH-04 setup.sh 가 $signal 을 받으면 터미널 상태를 되돌리고 $expectedCode 로 끝난다',
        () {
          sb
            ..writeUname('Darwin')
            ..writeRecorder('brew', sb.brewLog)
            ..writeParentSignaler('fvm', sb.callLog, signal: signal)
            ..writeStty(sb.callLog);

          final ProcessResult result = _runSetup(sb);

          final List<String> lines = sb.readLines(sb.callLog);
          expect(
            result.exitCode,
            expectedCode,
            reason: _combinedOutput(result),
          );
          expect(
            lines,
            containsAllInOrder(<String>[
              'stty -g',
              'dart run bin/setup.dart --probe',
              'stty $_savedSttyState',
            ]),
          );
          expect(lines.last, 'stty $_savedSttyState');
          expect(_combinedOutput(result), isNot(contains(_notZshParentLine)));
        },
      );
    }
  });
}
