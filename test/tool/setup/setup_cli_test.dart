// 설정 위저드 진입점(`bin/setup.dart`)의 명령줄 표면 계약.
//
// T-20-CLI-01: `--help` 는 종료 코드 0 이고, 사용법에 `--providers` · `--flavor`
//   와 flavor 허용 값(`Flavor.values` 이름 전부)이 나온다.
// T-20-CLI-02: 허용 밖 `--flavor qa` 는 종료 코드 1, 표준 오류에 `인자 오류: ` 줄과
//   사용법이 나오고 표준 출력에는 위저드 출력(점검표)이 없다.
// T-20-CLI-03: 모르는 옵션 `--nope` 는 종료 코드 1, 표준 오류에 `인자 오류: ` 줄과
//   사용법이 나온다.
//
// 세 경로 모두 프로젝트 루트 · HOME · 터미널에 닿기 전에 끝난다 — 대화형 경로 ·
// 네트워크 없음.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/setup/flavor.dart';

/// 프로세스 실행 결과 — 종료 코드와 두 출력.
typedef _CliResult = ({int exitCode, String stdout, String stderr});

/// 저장소 루트(`flutter test` 의 CWD).
final String _projectRoot = Directory.current.path;

/// 위저드 진입점 경로.
final String _binPath = '$_projectRoot/bin/setup.dart';

/// 점검표 머리 — 위저드가 시작됐다면 표준 출력에 나오는 말.
const String _checklistWord = '점검표';

/// 프로세스 하나가 끝나기를 기다리는 상한 — 테스트 상한(60초)보다 짧다.
const Duration _cliExitTimeout = Duration(seconds: 50);

/// `bin/setup.dart` 를 [args] 로 실행해 결과를 돌려준다.
///
/// 출력 두 갈래를 종료 대기 전에 모두 비워야 파이프가 막히지 않는다. 상한 안에
/// 끝나지 않으면 프로세스를 끝내고 [TimeoutException] 을 던진다.
Future<_CliResult> _runSetupCli(List<String> args) async {
  final Process process = await Process.start('fvm', <String>[
    'dart',
    'run',
    _binPath,
    ...args,
  ], workingDirectory: _projectRoot);
  final Future<String> out = process.stdout.transform(utf8.decoder).join();
  final Future<String> err = process.stderr.transform(utf8.decoder).join();
  final int code = await process.exitCode.timeout(
    _cliExitTimeout,
    onTimeout: () {
      // 멈춘 위저드 프로세스를 남기지 않는다.
      process.kill();
      throw TimeoutException('bin/setup.dart 가 끝나지 않았다', _cliExitTimeout);
    },
  );
  return (exitCode: code, stdout: await out, stderr: await err);
}

/// [stderr] 에 `인자 오류: ` 가 한 번 나오고 사용법을 담는지 확인한다.
void _expectArgumentError(String stderr) {
  // dart run 의 빌드 안내가 같은 줄 앞에 붙을 수 있어 줄 머리 대신 개수로 본다.
  expect('인자 오류: '.allMatches(stderr), hasLength(1), reason: stderr);
  expect(stderr, contains('사용법: ./setup.sh [옵션]'));
  expect(stderr, contains('--providers'));
  expect(stderr, contains('--flavor'));
}

void main() {
  const cliTimeout = Timeout(Duration(seconds: 60));

  test('T-20-CLI-01: --help 는 0 으로 끝나고 옵션과 flavor 허용 값을 보여 준다', () async {
    final _CliResult r = await _runSetupCli(<String>['--help']);

    expect(r.exitCode, 0, reason: r.stderr);
    expect(r.stdout, contains('사용법: ./setup.sh [옵션]'));
    expect(r.stdout, contains('--providers'));
    expect(r.stdout, contains('--flavor'));
    for (final Flavor flavor in Flavor.values) {
      expect(r.stdout, contains(flavor.name));
    }
    expect(r.stdout, isNot(contains(_checklistWord)));
  }, timeout: cliTimeout);

  test('T-20-CLI-02: 허용 밖 flavor 값은 인자 오류와 사용법을 내고 1 로 끝난다', () async {
    final _CliResult r = await _runSetupCli(<String>['--flavor', 'qa']);

    expect(r.exitCode, 1, reason: r.stderr);
    _expectArgumentError(r.stderr);
    expect(r.stdout, isNot(contains(_checklistWord)));
    expect(r.stdout.trim(), isEmpty);
  }, timeout: cliTimeout);

  test('T-20-CLI-03: 모르는 옵션은 인자 오류와 사용법을 내고 1 로 끝난다', () async {
    final _CliResult r = await _runSetupCli(<String>['--nope']);

    expect(r.exitCode, 1, reason: r.stderr);
    _expectArgumentError(r.stderr);
    expect(r.stdout.trim(), isEmpty);
  }, timeout: cliTimeout);
}
