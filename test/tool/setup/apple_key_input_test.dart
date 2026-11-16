import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';

import '../../../tool/setup/config_files.dart';
import '../../../tool/setup/flavor.dart';
import '../../../tool/setup/providers/apple_key_input.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/terminal.dart';
import '../../../tool/setup/wizard.dart';
import 'fake_rest_client.dart';
import 'fakes.dart';

/// 가짜 Key ID(대문자 영숫자 10자).
const String keyId = 'ABCDE12345';

/// 두 번째 가짜 Key ID.
const String otherKeyId = 'FGHIJ67890';

/// 가짜 Team ID(대문자 영숫자 10자).
const String teamId = 'TEAMID1234';

/// 터미널이 붙여 넣거나 끌어다 놓은 글 앞에 붙이는 표시(시험 자신의 리터럴).
const String pasteStart = '\x1B[200~';

/// 터미널이 붙여 넣거나 끌어다 놓은 글 뒤에 붙이는 표시(시험 자신의 리터럴).
const String pasteEnd = '\x1B[201~';

/// 빈 경로 까닭 줄(시험 자신의 글자).
const String emptyPathLine = '  경로가 비었습니다';

/// 바꿀 수 없는 주소 까닭 줄(시험 자신의 글자).
const String unconvertibleAddressLine = '  파일 경로로 바꿀 수 없는 주소입니다';

/// [text] 에서 [line] 과 같은 줄의 수를 센다.
int countLines(String text, String line) =>
    text.split('\n').where((String l) => l == line).length;

/// 실행 시점에 조립하는 PEM 개인 키 머리 줄.
String buildPemHeader() =>
    <String>['-----BEGIN', ' PRIVATE', ' KEY-----'].join();

/// 실행 시점에 조립하는 PEM 개인 키 끝 줄.
String buildPemFooter() => <String>['-----END', ' PRIVATE', ' KEY-----'].join();

/// [seed] 글자로 만든 가짜 base64 본문 줄 3개(각 64자).
List<String> buildBodyLines(String seed) => <String>[
  for (var i = 0; i < 3; i++) '${seed * 30}Qz0$i',
];

/// [seed] 본문 줄로 조립한 가짜 `.p8` 내용.
String buildPemContent(String seed) => <String>[
  buildPemHeader(),
  ...buildBodyLines(seed),
  buildPemFooter(),
  '',
].join('\n');

/// [haystack] 에서 [needle] 이 나타나는 횟수를 센다.
int countText(String haystack, String needle) =>
    haystack.split(needle).length - 1;

void main() {
  late Directory repoDir;
  late Directory keyDir;
  late String root;

  /// 첫 번째 가짜 키 파일 경로(저장소 밖).
  String keyPath() => '${keyDir.path}/AuthKey_$keyId.p8';

  /// 두 번째 가짜 키 파일 경로(저장소 밖).
  String otherKeyPath() => '${keyDir.path}/AuthKey_$otherKeyId.p8';

  /// 이름에 공백이 든 폴더 아래의 가짜 키 파일 경로(저장소 밖).
  String spacedKeyPath() => '${keyDir.path}/Apple Keys/AuthKey_$keyId.p8';

  /// dev xcconfig 절대 경로.
  String xcconfigPath() => '$root/${const FlavorPaths(Flavor.dev).xcconfig}';

  /// [inputs] 를 답으로 쓰는 문맥 · 화면 · 기록을 만든다.
  ({WizardContext context, ScriptedTerminal screen, MemoryLogSink log})
  buildHarness(
    List<String?> inputs, {
    WizardSession? session,
    String? homeDirectory,
  }) {
    final screen = ScriptedTerminal(inputs);
    final log = MemoryLogSink(Redactor());
    final WizardContext context = buildTestContext(
      projectRoot: root,
      terminal: screen,
      log: log,
      session: session,
      homeDirectory: homeDirectory,
    );
    return (context: context, screen: screen, log: log);
  }

  /// 화면 · 기록 두 버퍼에 [seed] 키의 PEM 머리 · 본문 · 끝 줄이 없는지 본다.
  void expectNoPem(String screenText, String logText, String seed) {
    for (final buffer in <String>[screenText, logText]) {
      expect(countText(buffer, buildPemHeader()), 0);
      expect(countText(buffer, buildPemFooter()), 0);
      for (final String line in buildBodyLines(seed)) {
        expect(countText(buffer, line), 0);
      }
    }
  }

  setUp(() {
    repoDir = Directory.systemTemp.createTempSync('apple_key_input_repo_');
    keyDir = Directory.systemTemp.createTempSync('apple_key_input_keys_');
    root = repoDir.path;
    const paths = FlavorPaths(Flavor.dev);
    File(xcconfigPath())
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(File(paths.xcconfigExample).readAsStringSync());
    File(keyPath()).writeAsStringSync(buildPemContent('Ab'));
    File(otherKeyPath()).writeAsStringSync(buildPemContent('Cd'));
  });

  tearDown(() {
    repoDir.deleteSync(recursive: true);
    keyDir.deleteSync(recursive: true);
  });

  group('T-20-KEY-01: 경로를 받아 내용을 메모리로 읽고 Key ID 기본값은 파일 '
      '이름에서 온다', () {
    test('절대 경로 · Key ID Enter → 세션 자리에 저장 · 두 버퍼 PEM 0회', () async {
      final h = buildHarness(<String?>[keyPath(), '']);

      final AppleKey? key = await askAppleKey(
        h.context,
        use: AppleKeyUse.signInWithApple,
      );

      expect(key, isNotNull);
      expect(key!.keyId, keyId);
      expect(key.privateKey, buildPemContent('Ab'));
      expect(h.context.session.appleKeys[AppleKeyUse.signInWithApple], key);
      expect(h.context.session.appleKeys[AppleKeyUse.deviceCheck], isNull);
      expect(h.screen.asks, hasLength(2));
      expect(h.log.text, contains('Key ID [$keyId]'));
      expectNoPem(h.screen.output.toString(), h.log.text, 'Ab');
      // 본문 줄이 가림 함수에 등록돼 있다.
      for (final String line in buildBodyLines('Ab')) {
        expect(h.context.redactor.apply(line), Redactor.mask);
      }
      expect(h.context.session.hasEnteredDeviceCheckKey, isFalse);
    });

    test('~ 로 시작하는 경로는 홈 디렉터리로 바꾼다', () async {
      final h = buildHarness(<String?>[
        '  ~/AuthKey_$keyId.p8  ',
        '',
      ], homeDirectory: keyDir.path);

      final AppleKey? key = await askAppleKey(
        h.context,
        use: AppleKeyUse.signInWithApple,
      );

      expect(key?.keyId, keyId);
      expect(key?.privateKey, buildPemContent('Ab'));
    });

    test('파일 이름이 AuthKey_<10자>.p8 가 아니면 Key ID 기본값이 없다', () async {
      final plainPath = '${keyDir.path}/apple.p8';
      File(plainPath).writeAsStringSync(buildPemContent('Ab'));
      final h = buildHarness(<String?>[plainPath, keyId]);

      final AppleKey? key = await askAppleKey(
        h.context,
        use: AppleKeyUse.signInWithApple,
      );

      expect(key?.keyId, keyId);
      expect(h.log.text, isNot(contains('Key ID [')));
    });
  });

  group('T-20-KEY-02: 다른 자리에 키가 있으면 같은 키 · 다른 키를 고르게 '
      '한다', () {
    /// Sign in with Apple 자리에 첫 번째 키를 둔 세션.
    WizardSession buildSessionWithKey() {
      final session = WizardSession();
      session.appleKeys[AppleKeyUse.signInWithApple] = AppleKey(
        keyId: keyId,
        privateKey: buildPemContent('Ab'),
      );
      return session;
    }

    test('1(같은 키) → 경로 · Key ID 질문 0 · 같은 값', () async {
      final h = buildHarness(<String?>['1'], session: buildSessionWithKey());

      final AppleKey? key = await askAppleKey(
        h.context,
        use: AppleKeyUse.deviceCheck,
      );

      final AppleKey? first =
          h.context.session.appleKeys[AppleKeyUse.signInWithApple];
      expect(key, same(first));
      expect(h.context.session.appleKeys[AppleKeyUse.deviceCheck], same(first));
      expect(h.screen.asks, <String>['DeviceCheck 에 쓸 Apple 키']);
      expect(h.screen.output.toString(), contains('1) 같은 키 (Key ID $keyId)'));
      expect(h.screen.output.toString(), contains('2) 다른 키 입력'));
    });

    test('Enter 는 같은 키(기본값)', () async {
      final h = buildHarness(<String?>[''], session: buildSessionWithKey());

      final AppleKey? key = await askAppleKey(
        h.context,
        use: AppleKeyUse.deviceCheck,
      );

      expect(key?.keyId, keyId);
      expect(h.screen.asks, hasLength(1));
    });

    test('2(다른 키 입력) → 경로 · Key ID 를 다시 받는다', () async {
      final h = buildHarness(<String?>[
        '2',
        otherKeyPath(),
        '',
      ], session: buildSessionWithKey());

      final AppleKey? key = await askAppleKey(
        h.context,
        use: AppleKeyUse.deviceCheck,
      );

      expect(key?.keyId, otherKeyId);
      expect(key?.privateKey, buildPemContent('Cd'));
      expect(
        h.context.session.appleKeys[AppleKeyUse.signInWithApple]?.keyId,
        keyId,
      );
      expect(h.context.session.appleKeys[AppleKeyUse.deviceCheck], key);
      expect(h.screen.asks, hasLength(3));
      expectNoPem(h.screen.output.toString(), h.log.text, 'Cd');
    });

    test('이 자리에 이미 키가 있으면 질문 0', () async {
      final h = buildHarness(const <String?>[], session: buildSessionWithKey());

      final AppleKey? key = await askAppleKey(
        h.context,
        use: AppleKeyUse.signInWithApple,
      );

      expect(key?.keyId, keyId);
      expect(h.screen.asks, isEmpty);
    });

    test('고르기에서 입력 끝 → null', () async {
      final h = buildHarness(const <String?>[], session: buildSessionWithKey());

      expect(
        await askAppleKey(h.context, use: AppleKeyUse.deviceCheck),
        isNull,
      );
      expect(h.context.session.appleKeys[AppleKeyUse.deviceCheck], isNull);
    });
  });

  group('T-20-KEY-03: 없는 경로 · PEM 아님 · Key ID 형식 틀림은 그 값만 다시 '
      '묻고 3회면 null', () {
    test('없는 경로 3회 → null · Key ID 질문 0', () async {
      final missing = '${keyDir.path}/missing.p8';
      final h = buildHarness(<String?>[missing, missing, missing]);

      expect(
        await askAppleKey(h.context, use: AppleKeyUse.signInWithApple),
        isNull,
      );
      expect(h.screen.asks, hasLength(3));
      expect(countText(h.screen.output.toString(), '파일이 없습니다'), 3);
      expect(h.context.session.appleKeys, isEmpty);
    });

    test('까닭 줄은 홈 디렉터리를 ~ 로 줄인 경로를 보인다', () async {
      final missing = '${keyDir.path}/missing.p8';
      final h = buildHarness(<String?>[
        missing,
        '~/missing.p8',
        keyPath(),
        '',
      ], homeDirectory: keyDir.path);

      final AppleKey? key = await askAppleKey(
        h.context,
        use: AppleKeyUse.signInWithApple,
      );

      final output = h.screen.output.toString();
      expect(key?.keyId, keyId);
      expect(countText(output, '파일이 없습니다 — ~/missing.p8'), 2);
      expect(output, isNot(contains('파일이 없습니다 — ${keyDir.path}')));
    });

    test('PEM 아님 → 경로만 다시 · 그 뒤 맞는 경로면 통과', () async {
      final textPath = '${keyDir.path}/AuthKey_$keyId.txt';
      File(textPath).writeAsStringSync('not a key file at all\n');
      final h = buildHarness(<String?>[textPath, keyPath(), '']);

      final AppleKey? key = await askAppleKey(
        h.context,
        use: AppleKeyUse.signInWithApple,
      );

      expect(key?.keyId, keyId);
      expect(h.screen.output.toString(), contains('.p8 개인 키 파일이 아닙니다'));
      expect(h.screen.asks, hasLength(3));
      expect(h.screen.output.toString(), isNot(contains('not a key file')));
    });

    test('읽지 못하는 경로(디렉터리) → 경로만 다시', () async {
      final h = buildHarness(<String?>[keyDir.path, keyPath(), '']);

      final AppleKey? key = await askAppleKey(
        h.context,
        use: AppleKeyUse.signInWithApple,
      );

      expect(key?.keyId, keyId);
      expect(h.screen.asks, hasLength(3));
    });

    test('Key ID 형식 틀림 3회 → null · 경로는 한 번만', () async {
      final h = buildHarness(<String?>[
        keyPath(),
        'abc',
        'abcde12345',
        'ABCDE123456',
      ]);

      expect(
        await askAppleKey(h.context, use: AppleKeyUse.signInWithApple),
        isNull,
      );
      final output = h.screen.output.toString();
      expect(
        output,
        contains('  Apple Key ID 형식이 맞지 않습니다 — 3자 · 규칙: 대문자 영문 · 숫자 10자'),
      );
      expect(countText(output, 'Apple Key ID 형식이 맞지 않습니다'), 3);
      expect(h.screen.asks, hasLength(4));
      expect(h.context.session.appleKeys, isEmpty);
    });

    test('Key ID 형식 틀림 뒤 맞는 값 → 통과', () async {
      final h = buildHarness(<String?>[keyPath(), 'abc', otherKeyId]);

      final AppleKey? key = await askAppleKey(
        h.context,
        use: AppleKeyUse.signInWithApple,
      );

      expect(key?.keyId, otherKeyId);
    });

    test('경로 · Key ID 에서 입력 끝 → null', () async {
      final atPath = buildHarness(const <String?>[]);
      expect(
        await askAppleKey(atPath.context, use: AppleKeyUse.signInWithApple),
        isNull,
      );
      final atKeyId = buildHarness(<String?>[keyPath()]);
      expect(
        await askAppleKey(atKeyId.context, use: AppleKeyUse.signInWithApple),
        isNull,
      );
      expect(atKeyId.context.session.appleKeys, isEmpty);
    });
  });

  group('T-20-KEY-04: Team ID 는 xcconfig 값을 쓰고 없으면 한 번 묻고 쓴다', () {
    test('xcconfig 값이 형식에 맞으면 질문 0', () async {
      replaceXcconfigValue(xcconfigPath(), 'DEVELOPMENT_TEAM', teamId);
      final h = buildHarness(const <String?>[]);

      expect(await resolveTeamId(h.context), teamId);
      expect(h.screen.asks, isEmpty);
      expect(h.context.session.appleTeamId, teamId);
    });

    test('비었으면 한 번 묻고 xcconfig 에 쓴다 · 두 번째 호출은 질문 0', () async {
      final h = buildHarness(<String?>[teamId]);

      expect(await resolveTeamId(h.context), teamId);
      expect(h.screen.asks, <String>['Apple Team ID']);
      expect(readXcconfigValue(xcconfigPath(), 'DEVELOPMENT_TEAM'), teamId);
      expect(
        File(xcconfigPath()).readAsStringSync(),
        contains('DEVELOPMENT_TEAM = $teamId\n'),
      );

      expect(await resolveTeamId(h.context), teamId);
      expect(h.screen.asks, hasLength(1));
    });

    test('형식 틀림은 다시 묻고 3회면 null · xcconfig 그대로', () async {
      final h = buildHarness(<String?>['team', 'teamid1234', 'TEAM']);

      expect(await resolveTeamId(h.context), isNull);
      expect(
        countText(h.screen.output.toString(), 'Apple Team ID 형식이 맞지 않습니다'),
        3,
      );
      expect(readXcconfigValue(xcconfigPath(), 'DEVELOPMENT_TEAM'), isEmpty);
      expect(h.context.session.appleTeamId, isNull);
    });

    test('입력 끝 → null', () async {
      final h = buildHarness(const <String?>[]);

      expect(await resolveTeamId(h.context), isNull);
    });

    test('xcconfig 에 DEVELOPMENT_TEAM 변수가 없으면 묻지 않고 예외', () async {
      File(xcconfigPath()).writeAsStringSync('FLAVOR = dev\n');
      final h = buildHarness(<String?>[teamId]);

      await expectLater(
        resolveTeamId(h.context),
        throwsA(isA<ConfigEditException>()),
      );
      expect(h.screen.asks, isEmpty);
    });
  });

  group('T-20-KEY-05: 실행 뒤 저장소 루트 아래에 키 내용 · 파일이 남지 않는다', () {
    test('두 자리 · Team ID 까지 받은 뒤 저장소 파일에 PEM 0회 · .p8 0개', () async {
      // 첫 자리는 경로로 받고, 둘째 자리는 다른 키를 고른다.
      final first = buildHarness(<String?>[keyPath(), '']);
      final AppleKey? sign = await askAppleKey(
        first.context,
        use: AppleKeyUse.signInWithApple,
      );
      expect(sign, isNotNull);
      final second = buildHarness(<String?>[
        '2',
        otherKeyPath(),
        '',
        teamId,
      ], session: first.context.session);
      final AppleKey? device = await askAppleKey(
        second.context,
        use: AppleKeyUse.deviceCheck,
      );
      expect(device?.keyId, otherKeyId);
      expect(await resolveTeamId(second.context), teamId);

      final files = <File>[
        for (final FileSystemEntity entity in repoDir.listSync(recursive: true))
          if (entity is File) entity,
      ];
      expect(files, isNotEmpty);
      for (final file in files) {
        expect(file.path.endsWith('.p8'), isFalse, reason: file.path);
        final String content = file.readAsStringSync();
        expect(countText(content, buildPemHeader()), 0, reason: file.path);
        for (final line in <String>[
          ...buildBodyLines('Ab'),
          ...buildBodyLines('Cd'),
        ]) {
          expect(countText(content, line), 0, reason: file.path);
        }
      }
      expectNoPem(second.screen.output.toString(), second.log.text, 'Cd');
      expectNoPem(first.screen.output.toString(), first.log.text, 'Ab');
    });
  });

  group('T-28-KEYPATH-01: 끌어다 놓기 · 붙여 넣기 꼴 .p8 경로 → 키를 읽는다', () {
    setUp(() {
      File(spacedKeyPath())
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(buildPemContent('Ab'));
    });

    final readableAnswers = <({String name, String Function(String) build})>[
      (name: '큰따옴표', build: (String path) => '"$path"'),
      (name: '작은따옴표', build: (String path) => "'$path'"),
      (
        name: 'file:// 주소',
        build: (String path) => 'file://${path.replaceAll(' ', '%20')}',
      ),
      (name: '큰따옴표로 감싼 file:// 주소', build: (String path) => '"file://$path"'),
      (
        name: '끌어다 놓기 escape',
        build: (String path) => '${path.replaceAll(' ', r'\ ')} ',
      ),
    ];
    for (final item in readableAnswers) {
      test('${item.name} → 키를 읽고 Key ID 는 파일 이름에서 · 까닭 줄 0', () async {
        final h = buildHarness(<String?>[
          item.build(spacedKeyPath()),
          '',
        ], homeDirectory: keyDir.path);

        final AppleKey? key = await askAppleKey(
          h.context,
          use: AppleKeyUse.signInWithApple,
        );

        expect(key?.keyId, keyId);
        expect(key?.privateKey, buildPemContent('Ab'));
        expect(h.screen.asks, hasLength(2));
        final output = h.screen.output.toString();
        for (final reason in <String>[
          '파일이 없습니다',
          '경로가 비었습니다',
          '파일 경로로 바꿀 수 없는 주소입니다',
        ]) {
          expect(output, isNot(contains(reason)));
        }
      });
    }
  });

  group('T-28-KEYPATH-02: 빈 따옴표 · 바꿀 수 없는 주소 · 빈 답은 까닭 한 줄 뒤 '
      '경로만 다시', () {
    setUp(() {
      File(spacedKeyPath())
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(buildPemContent('Ab'));
    });

    final retryAnswers =
        <({String name, String Function(String) build, String line})>[
          (name: '빈 큰따옴표', build: (String _) => '""', line: emptyPathLine),
          (name: '빈 작은따옴표', build: (String _) => "''", line: emptyPathLine),
          (
            name: '조각 안 %2F 주소',
            build: (String dir) => 'file://$dir/a%2Fb.p8',
            line: unconvertibleAddressLine,
          ),
          (
            name: '작은따옴표로 감싼 %2F 주소',
            build: (String dir) => "'file://$dir/a%2Fb.p8'",
            line: unconvertibleAddressLine,
          ),
        ];
    for (final item in retryAnswers) {
      test('${item.name} → 까닭 한 줄 · 답 되풀이 0 · 다음 경로로 키를 읽는다', () async {
        final h = buildHarness(<String?>[
          item.build(keyDir.path),
          spacedKeyPath(),
          '',
        ], homeDirectory: keyDir.path);

        final AppleKey? key = await askAppleKey(
          h.context,
          use: AppleKeyUse.signInWithApple,
        );

        expect(key?.keyId, keyId);
        expect(key?.privateKey, buildPemContent('Ab'));
        expect(h.screen.asks, hasLength(3));
        final output = h.screen.output.toString();
        expect(countLines(output, item.line), 1);
        expect(output, isNot(contains('파일이 없습니다')));
        expect(output, isNot(contains(keyDir.path)));
      });
    }

    test('상한 → 경로 없는 까닭 세 번이면 null · Key ID 질문 0', () async {
      final h = buildHarness(<String?>[
        '""',
        'file://${keyDir.path}/a%2Fb.p8',
        "''",
      ], homeDirectory: keyDir.path);

      final AppleKey? key = await askAppleKey(
        h.context,
        use: AppleKeyUse.signInWithApple,
      );

      expect(key, isNull);
      expect(h.screen.asks, hasLength(3));
      expect(h.screen.asks, isNot(contains(appleKeyIdQuestion)));
      final output = h.screen.output.toString();
      expect(countLines(output, emptyPathLine), 2);
      expect(countLines(output, unconvertibleAddressLine), 1);
      expect(h.context.session.appleKeys[AppleKeyUse.signInWithApple], isNull);
    });

    test('빈 답 → 경로를 입력하라는 한 줄 뒤 다음 경로로 키를 읽는다', () async {
      final h = buildHarness(<String?>[
        '',
        spacedKeyPath(),
        '',
      ], homeDirectory: keyDir.path);

      final AppleKey? key = await askAppleKey(
        h.context,
        use: AppleKeyUse.signInWithApple,
      );

      expect(key?.keyId, keyId);
      final output = h.screen.output.toString();
      expect(countLines(output, '  .p8 파일 경로를 입력하세요'), 1);
      expect(output, isNot(contains(emptyPathLine)));
    });
  });

  group('T-28-KEYPATH-03: 실제 터미널 입력 경계를 지난 .p8 경로 답', () {
    setUp(() {
      File(spacedKeyPath())
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(buildPemContent('Ab'));
    });

    /// 실제 [StdioTerminal] 에 [answer] 와 Key ID Enter 를 넣어 키를 받는다.
    Future<({AppleKey? key, String screen, String log})> askThroughStdio(
      String answer,
    ) async {
      final queue = <String>[answer, ''];
      final screen = StringBuffer();
      final stdio = StdioTerminal(
        readLine: () => queue.isEmpty ? null : queue.removeAt(0),
        output: screen,
      );
      final redactor = Redactor();
      final log = MemoryLogSink(redactor);
      final context = WizardContext(
        projectRoot: root,
        runner: FakeCommandRunner(),
        terminal: RedactingTerminal(stdio, redactor, log),
        redactor: redactor,
        log: log,
        rest: FakeRestClient(),
        homeDirectory: keyDir.path,
        random: Random(fixedTestRandomSeed),
        now: () => fixedTestNow,
      );
      final AppleKey? key = await askAppleKey(
        context,
        use: AppleKeyUse.signInWithApple,
      );
      return (key: key, screen: screen.toString(), log: log.text);
    }

    /// 공백 앞에 `\` 를 붙인 끌어다 놓기 꼴 키 경로.
    String buildDroppedKeyPath() =>
        '${spacedKeyPath().replaceAll(' ', r'\ ')} ';

    final stdioAnswers = <({String name, String Function(String) wrap})>[
      (
        name: '표시로 감싼 .p8 경로',
        wrap: (String dropped) => '$pasteStart$dropped$pasteEnd',
      ),
      (name: '표시 없는 .p8 경로', wrap: (String dropped) => dropped),
    ];
    for (final item in stdioAnswers) {
      test('${item.name} → 키를 읽고 화면 · 기록에 ESC · PEM 0', () async {
        final run = await askThroughStdio(item.wrap(buildDroppedKeyPath()));

        expect(run.key?.keyId, keyId);
        expect(run.key?.privateKey, buildPemContent('Ab'));
        expect(run.screen, isNot(contains('파일이 없습니다')));
        expect(run.screen, isNot(contains('\x1B')));
        expect(run.log, isNot(contains('\x1B')));
        expectNoPem(run.screen, run.log, 'Ab');
      });
    }
  });
}
