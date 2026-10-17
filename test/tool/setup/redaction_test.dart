import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/log_sink.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/terminal.dart';
import '../../../tool/setup/wizard.dart';
import 'fakes.dart';

// 비밀 값 모양 문자열은 tracked 소스에 완형으로 두지 않는다 — 공개 저장소의 치환 ·
// 스캔 규칙이 그 모양을 지우거나 막으므로 실행 시점에 조각으로 조립한다.

/// 가짜 액세스 토큰(`ya29.` 모양)을 조립한다.
String buildFakeAccessToken() => 'ya29.${'A' * 40}';

/// 가짜 API 키(`AIza` + 35자 모양)를 조립한다.
String buildFakeApiKey() => 'AIza${'x' * 35}';

/// 등록해서 가릴 App Check 디버그 토큰 모양 값.
const String fakeDebugToken = '0f1e2d3c-4b5a-4968-8776-a5b4c3d2e1f0';

/// [haystack] 에서 [needle] 이 나타나는 횟수를 센다.
int countText(String haystack, String needle) =>
    haystack.split(needle).length - 1;

/// 가짜 PEM 개인 키의 머리 · 끝 줄을 조각으로 조립한다.
///
/// [edge] 는 `BEGIN` · `END`, [kind] 는 `EC ` 처럼 앞에 붙는 키 종류다.
String buildPemLine(String edge, {String kind = ''}) =>
    <String>['-----', edge, ' ', kind, 'PRIVATE', ' KEY-----'].join();

/// 머리 · 본문 두 줄 · 끝 줄을 [separator] 로 이은 가짜 PEM 개인 키를 만든다.
String buildFakePem({String kind = '', String separator = '\n'}) => <String>[
  buildPemLine('BEGIN', kind: kind),
  'A' * 64,
  'B' * 20,
  buildPemLine('END', kind: kind),
].join(separator);

/// 검사는 할 일 · 실행은 비밀 값이 담긴 실패 결과를 돌려주는 단계.
final class SecretFailureStep implements Step {
  /// [checkReason] 을 검사 사유로, [result] 를 실패 원문으로 쓰는 단계를 만든다.
  SecretFailureStep({required this.checkReason, required this.result});

  /// 검사 결과 사유.
  final String checkReason;

  /// 실패한 명령의 결과.
  final CommandResult result;

  @override
  String get id => 'secret';

  @override
  String get title => '비밀 값 단계';

  @override
  List<String> get dependsOn => const <String>[];

  @override
  bool get isCostlyOrIrreversible => false;

  @override
  Future<CheckResult> check(WizardContext context) async => Todo(checkReason);

  @override
  List<String> plannedCommandLines(WizardContext context) => const <String>[
    'demo run',
  ];

  @override
  Future<StepOutcome> apply(WizardContext context) async =>
      Failed('명령이 실패했습니다', result: result);
}

void main() {
  late Redactor redactor;
  late MemoryLogSink log;
  late ScriptedTerminal screen;
  late RedactingTerminal terminal;

  setUp(() {
    redactor = Redactor();
    log = MemoryLogSink(redactor);
    screen = ScriptedTerminal(const <String?>[]);
    terminal = RedactingTerminal(screen, redactor, log);
  });

  test('T-19-REDACT-01: capture 출력의 액세스 토큰은 화면 · 로그에서 가려진다', () async {
    final String token = buildFakeAccessToken();
    final ProcessCommandRunner runner = ProcessCommandRunner(
      terminal,
      log: log,
    );

    final CommandResult result = await runner.capture(
      Command('cat', const <String>[], stdinText: '$token\n'),
    );

    // 호출자는 원문을 받는다 — 가림은 화면 · 로그 경로에만 적용된다.
    expect(result.stdout.trim(), token);
    expect(countText(screen.output.toString(), token), 0);
    expect(countText(log.text, token), 0);
    expect(log.lines, contains('[cmd] cat'));
    expect(log.lines, contains('[exit] 0'));
    expect(log.lines, contains('[stdout] ${Redactor.mask}'));
  });

  test('T-19-REDACT-02: 등록한 값은 stream 줄 · 명령 줄에서 가려진다', () async {
    final String registered = 'kit${'Q' * 10}';
    redactor
      ..register(fakeDebugToken)
      ..register(registered);
    final ProcessCommandRunner runner = ProcessCommandRunner(
      terminal,
      log: log,
    );

    final CommandResult result = await runner.stream(
      Command('printf', <String>[
        'token %s\nvalue %s\n',
        fakeDebugToken,
        registered,
      ]),
    );

    expect(result.exitCode, 0);
    final String shown = screen.output.toString();
    for (final String secret in <String>[fakeDebugToken, registered]) {
      expect(countText(shown, secret), 0, reason: '화면: $secret');
      expect(countText(log.text, secret), 0, reason: '로그: $secret');
    }
    expect(countText(shown, Redactor.mask), greaterThanOrEqualTo(1));
    expect(countText(log.text, Redactor.mask), greaterThanOrEqualTo(1));
    expect(shown, contains('token ${Redactor.mask}'));
    expect(shown, contains('value ${Redactor.mask}'));
  });

  test('T-19-REDACT-03: 실패 원문 경로의 API 키 · 토큰도 화면 · 로그에서 가려진다', () async {
    final String apiKey = buildFakeApiKey();
    final String token = buildFakeAccessToken();
    final ScriptedTerminal answers = ScriptedTerminal(const <String?>['y']);

    final int code = await runWizard(
      buildTestContext(
        projectRoot: Directory.systemTemp.path,
        terminal: answers,
        redactor: redactor,
        log: log,
      ),
      <Step>[
        SecretFailureStep(
          checkReason: '토큰 $token 이 만료됐습니다',
          result: CommandResult(1, 'key=$apiKey\n', 'bearer $token\n'),
        ),
      ],
    );

    expect(code, wizardExitStopped);
    final String shown = answers.output.toString();
    for (final String secret in <String>[apiKey, token]) {
      expect(countText(shown, secret), 0, reason: '화면: $secret');
      expect(countText(log.text, secret), 0, reason: '로그: $secret');
    }
    expect(shown, contains('key=${Redactor.mask}'));
    expect(shown, contains('bearer ${Redactor.mask}'));
    expect(
      log.lines,
      contains('[check] secret ✗ 토큰 ${Redactor.mask} 이 만료됐습니다'),
    );
  });

  test('T-19-REDACT-04: 민감 capture 는 로그에 본문 대신 생략 표시 · 화면 출력 0', () async {
    // 패턴에도 걸리지 않고 등록하지도 않은 값 — 생략 표시만이 본문을 막는다.
    final String secret = 'plain-${'s' * 12}-value';
    final ProcessCommandRunner runner = ProcessCommandRunner(
      terminal,
      log: log,
    );

    final CommandResult result = await runner.capture(
      Command(
        'cat',
        const <String>[],
        stdinText: secret,
        isOutputSensitive: true,
      ),
    );

    expect(result.stdout.trim(), secret);
    expect(screen.output.toString(), isEmpty);
    expect(countText(log.text, secret), 0);
    expect(
      log.lines,
      contains('[stdout] ${ProcessCommandRunner.sensitiveOutputNotice}'),
    );
    expect(ProcessCommandRunner.sensitiveOutputNotice, '(민감 출력 생략)');
  });

  group('T-19-REDACT-05: FileLogSink', () {
    late Directory root;
    final DateTime fixedNow = DateTime(2030, 1, 2, 3, 4, 5);

    setUp(() {
      root = Directory.systemTemp.createTempSync('redaction_test_');
    });

    tearDown(() {
      root.deleteSync(recursive: true);
    });

    test('.setup/logs 아래 0600 파일 · 0700 디렉터리 · 비밀 값 0', () async {
      final String token = buildFakeAccessToken();
      redactor.register(fakeDebugToken);

      final FileLogSink sink = await FileLogSink.open(
        projectRoot: root.path,
        now: fixedNow,
        redactor: redactor,
      );
      sink
        ..write('out', '토큰 $token')
        ..write('stdout', 'debug $fakeDebugToken\n두 번째 줄\n');
      await sink.close();

      expect(sink.path, startsWith('${root.path}/.setup/logs/setup-'));
      expect(sink.path, endsWith('.log'));
      expect(sink.path, '${root.path}/.setup/logs/setup-20300102-030405.log');
      expect(FileStat.statSync(sink.path).modeString(), 'rw-------');
      expect(
        FileStat.statSync('${root.path}/.setup/logs').modeString(),
        'rwx------',
      );
      final String written = File(sink.path).readAsStringSync();
      expect(countText(written, token), 0);
      expect(countText(written, fakeDebugToken), 0);
      expect(
        written,
        '[out] 토큰 ${Redactor.mask}\n'
        '[stdout] debug ${Redactor.mask}\n'
        '[stdout] 두 번째 줄\n',
      );
    });

    test('같은 초에 다시 열면 기존 파일을 덮어쓰지 않고 새 파일을 만든다', () async {
      final FileLogSink first = await FileLogSink.open(
        projectRoot: root.path,
        now: fixedNow,
        redactor: redactor,
      );
      first.write('out', '첫 실행');
      await first.close();

      final FileLogSink second = await FileLogSink.open(
        projectRoot: root.path,
        now: fixedNow,
        redactor: redactor,
      );
      second.write('out', '둘째 실행');
      await second.close();

      expect(second.path, isNot(first.path));
      final String name = second.path.split('/').last;
      expect(name, startsWith('setup-'));
      expect(name, endsWith('.log'));
      expect(File(first.path).readAsStringSync(), '[out] 첫 실행\n');
      expect(File(second.path).readAsStringSync(), '[out] 둘째 실행\n');
      expect(FileStat.statSync(second.path).modeString(), 'rw-------');
    });
  });

  test('T-19-REDACT-06: 8자 미만 값은 등록되지 않아 일반 문장을 가리지 않는다', () {
    redactor
      ..register('')
      ..register('dev')
      ..register('abc1234');
    const String sentence = 'dev 프로젝트 abc1234 를 검사합니다';
    expect(redactor.apply(sentence), sentence);

    redactor.register('abcd1234');
    expect(redactor.apply('값 abcd1234 끝'), '값 ${Redactor.mask} 끝');
  });

  test('RedactingTerminal 은 사용자 답을 가린 뒤 로그에 남긴다', () {
    final String token = buildFakeAccessToken();
    final ScriptedTerminal answers = ScriptedTerminal(<String?>['y', token]);
    final RedactingTerminal wrapped = RedactingTerminal(answers, redactor, log);

    expect(wrapped.confirm('계속할까요?'), isTrue);
    expect(wrapped.ask('값을 입력하세요'), token);

    expect(answers.asks, <String>['계속할까요?', '값을 입력하세요']);
    expect(log.lines, contains('[in] y'));
    expect(log.lines, contains('[in] ${Redactor.mask}'));
    expect(countText(log.text, token), 0);
  });

  test('T-20-SECRET-06: 숨김 입력은 기록에 글자 수 판정만 남기고 값을 가림에 등록한다', () {
    final String secret = 'k' * 32;
    final ScriptedTerminal answers = ScriptedTerminal(<String?>[secret]);
    final RedactingTerminal wrapped = RedactingTerminal(answers, redactor, log);

    expect(wrapped.askSecret('어드민 키를 붙여 넣으세요'), secret);
    wrapped.writeLine('받은 값 $secret');

    expect(answers.secretAsks, <String>['어드민 키를 붙여 넣으세요']);
    expect(log.lines, contains('[out] 어드민 키를 붙여 넣으세요'));
    expect(log.lines, contains('[in] (비밀 값 32자)'));
    expect(log.lines, contains('[out] 받은 값 ${Redactor.mask}'));
    expect(countText(answers.output.toString(), secret), 0);
    expect(countText(log.text, secret), 0);
    expect(countText(answers.output.toString(), '받은 값 ${Redactor.mask}'), 1);

    final ScriptedTerminal ended = ScriptedTerminal(const <String?>[]);
    final RedactingTerminal endedWrapped = RedactingTerminal(
      ended,
      redactor,
      log,
    );

    expect(endedWrapped.askSecret('어드민 키를 붙여 넣으세요'), isNull);
    expect(log.lines.last, '[in] ${RedactingTerminal.endOfInputRecord}');
  });

  test('T-20-PEM-01: 등록하지 않은 PEM 개인 키 블록은 머리부터 끝 줄까지 가려진다', () {
    for (final String kind in <String>['', 'EC ']) {
      final String header = buildPemLine('BEGIN', kind: kind);
      // 줄바꿈 그대로인 블록과 JSON 응답처럼 `\n` 이 글자로 든 블록 둘 다.
      for (final String separator in <String>['\n', r'\n']) {
        final String pem = buildFakePem(kind: kind, separator: separator);
        final String shown = redactor.apply('응답 {"privateKey":"$pem"} 끝');

        expect(shown, '응답 {"privateKey":"${Redactor.mask}"} 끝');
        expect(countText(shown, header), 0, reason: kind);
        expect(countText(shown, 'A' * 64), 0, reason: kind);
      }
    }

    // 화면 · 기록 두 버퍼에도 머리가 남지 않는다.
    terminal.writeLine(buildFakePem());
    expect(countText(screen.output.toString(), buildPemLine('BEGIN')), 0);
    expect(countText(log.text, buildPemLine('BEGIN')), 0);
  });

  test('T-20-PEM-02: 머리 줄만 있는 문자열도 머리가 가려진다', () {
    for (final String kind in <String>['', 'EC ']) {
      final String header = buildPemLine('BEGIN', kind: kind);
      final String shown = redactor.apply('키 파일 첫 줄: $header');

      expect(shown, '키 파일 첫 줄: ${Redactor.mask}');
      expect(countText(shown, header), 0);
    }
  });

  test('T-20-PEM-03: 여러 줄 값을 등록하면 8자 이상인 각 줄도 따로 가려진다', () {
    final String bodyLine = 'C' * 64;
    redactor.register('short\n  $bodyLine  \r\n${'D' * 8}\nabc');

    expect(redactor.apply('출력 줄 $bodyLine'), '출력 줄 ${Redactor.mask}');
    expect(redactor.apply('D' * 8), Redactor.mask);
    expect(redactor.apply('short'), 'short');
    expect(redactor.apply('abc'), 'abc');
  });
}
