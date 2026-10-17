import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/providers/fingerprints.dart';
import '../../../tool/setup/rest_client.dart';
import '../../../tool/setup/wizard.dart';
import 'fakes.dart';

/// 지문 fixture 의 바이트 — 실제 인증서가 아닌 고정 문자열이다.
final List<int> fixtureCertificateBytes = utf8.encode(
  'starter-kit-fingerprint-fixture',
);

/// fixture 바이트의 SHA-1(`shasum -a 1` 출력).
const String fixtureSha1Hex = 'ab500584b25ed636c9c91b0370546c3831850f16';

/// fixture 바이트의 SHA-256(`shasum -a 256` 출력).
const String fixtureSha256Hex =
    'b0ce9e8e78229e315a330654d756e1be96d50279da5e8403100494af0740d073';

/// fixture 바이트의 키 해시(`openssl dgst -sha1 -binary | openssl base64` 출력).
const String fixtureKeyHash = 'q1AFhLJe1jbJyRsDcFRsODGFDxY=';

/// fixture SHA-1 의 대문자 · 콜론 표시형.
const String fixtureSha1Colon =
    'AB:50:05:84:B2:5E:D6:36:C9:C9:1B:03:70:54:6C:38:31:85:0F:16';

/// 테스트 프로젝트 ID.
const String testProjectId = 'p';

/// 테스트 Android 앱 ID.
const String testAndroidAppId = '1:000:android:fake';

/// [body] 를 인증서 머리 · 꼬리로 감싼 PEM 꼴 문자열을 실행 시점에 조립한다.
String buildFixturePem(String body) => <String>[
  '-----BEGIN',
  ' CERTIFICATE-----\n',
  body,
  '\n-----END',
  ' CERTIFICATE-----\n',
].join();

/// [home] 아래에 빈 디버그 키스토어 자리 파일을 만들고 그 경로를 돌려준다.
///
/// 내용은 비어 있다 — 테스트는 실제 keytool 을 부르지 않고 가짜 실행기를 쓴다.
String createKeystorePlaceholder(String home) {
  final file = File('$home/$debugKeystoreRelativePath')
    ..createSync(recursive: true);
  return file.path;
}

/// [keystorePath] 를 읽는 keytool 명령의 가짜 실행기 키.
String buildExportKey(String keystorePath) =>
    FakeCommandRunner.buildKey(buildExportCertificateCommand(keystorePath));

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('fingerprints_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  /// 임시 디렉터리를 홈으로 쓰는 문맥을 만든다.
  WizardContext buildContext(FakeCommandRunner runner, {String? home}) =>
      buildTestContext(
        projectRoot: tempDir.path,
        runner: runner,
        homeDirectory: home ?? '${tempDir.path}/home',
      );

  test('T-20-FP-01: 고정 바이트 PEM → 소문자 hex 40 · 64자 · 키 해시 28자가 외부 도구 값과 같다', () {
    final String encoded = base64Encode(fixtureCertificateBytes);
    // 줄바꿈 · 앞뒤 경고 줄이 섞여도 인증서 블록만 읽는다.
    final wrapped = '${encoded.substring(0, 10)}\n${encoded.substring(10)}';
    final pem =
        'Warning: 앞 줄\n${buildFixturePem(wrapped)}'
        'Warning: 뒤 줄\n';

    final DebugFingerprints result = parseCertificatePem(pem);

    expect(result, isA<FingerprintsAvailable>());
    final available = result as FingerprintsAvailable;
    expect(available.sha1Hex, fixtureSha1Hex);
    expect(available.sha256Hex, fixtureSha256Hex);
    expect(available.keyHash, fixtureKeyHash);
    expect(available.sha1Hex, matches(RegExp(r'^[0-9a-f]{40}$')));
    expect(available.sha256Hex, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(available.keyHash, hasLength(28));
    expect(available.keyHash, endsWith('='));
  });

  group('디버그 키스토어가 없으면 keytool 을 부르지 않는다', () {
    test('T-20-FP-02: 홈에 키스토어 없음 → 계산할 수 없음 · 호출 0', () async {
      final runner = FakeCommandRunner();
      final DebugFingerprints result = await readDebugFingerprints(
        buildContext(runner),
      );

      expect(result, isA<FingerprintsUnavailable>());
      expect(
        (result as FingerprintsUnavailable).reason,
        contains(debugKeystoreRelativePath),
      );
      expect(runner.calls, isEmpty);
    });

    test('T-20-FP-02: 홈 디렉터리를 모름 → 계산할 수 없음 · 호출 0', () async {
      final runner = FakeCommandRunner();
      final DebugFingerprints result = await readDebugFingerprints(
        buildContext(runner, home: ''),
      );

      expect(result, isA<FingerprintsUnavailable>());
      expect(runner.calls, isEmpty);
    });
  });

  group('keytool 이 실패하면 사유에 종료 코드를 담는다', () {
    test('T-20-FP-03: keytool 없음(127) → 계산할 수 없음', () async {
      final home = '${tempDir.path}/home';
      final String keystorePath = createKeystorePlaceholder(home);
      final runner = FakeCommandRunner()
        ..on(
          buildExportKey(keystorePath),
          const CommandResult(127, '', 'No such file or directory'),
        );

      final DebugFingerprints result = await readDebugFingerprints(
        buildContext(runner),
      );

      expect(result, isA<FingerprintsUnavailable>());
      expect((result as FingerprintsUnavailable).reason, contains('127'));
      expect(runner.calls, hasLength(1));
    });

    test('T-20-FP-03: 자바 없음(1) → 계산할 수 없음 · 키 생성 · 설치 명령 0', () async {
      final home = '${tempDir.path}/home';
      final String keystorePath = createKeystorePlaceholder(home);
      final runner = FakeCommandRunner()
        ..on(
          buildExportKey(keystorePath),
          const CommandResult(
            1,
            '',
            'The operation couldn’t be completed. '
                'Unable to locate a Java Runtime.',
          ),
        );

      final DebugFingerprints result = await readDebugFingerprints(
        buildContext(runner),
      );

      expect(result, isA<FingerprintsUnavailable>());
      expect((result as FingerprintsUnavailable).reason, contains('종료 코드 1'));
      expect(runner.calls.single.key, buildExportKey(keystorePath));
      expect(runner.calls.single.key, startsWith('keytool -exportcert -rfc '));
    });
  });

  group('인증서 블록이 없거나 깨졌으면 계산할 수 없음', () {
    test('T-20-FP-04: 출력에 인증서 블록 없음 → 계산할 수 없음', () async {
      final home = '${tempDir.path}/home';
      final String keystorePath = createKeystorePlaceholder(home);
      final runner = FakeCommandRunner()
        ..on(
          buildExportKey(keystorePath),
          const CommandResult(0, 'Certificate stored in file\n', ''),
        );

      final DebugFingerprints result = await readDebugFingerprints(
        buildContext(runner),
      );

      expect(result, isA<FingerprintsUnavailable>());
    });

    test('T-20-FP-04: base64 가 깨짐 → 계산할 수 없음', () {
      expect(
        parseCertificatePem(buildFixturePem('%%%% not base64 %%%%')),
        isA<FingerprintsUnavailable>(),
      );
    });

    test('T-20-FP-04: 블록 안이 비었음 → 계산할 수 없음', () {
      expect(
        parseCertificatePem(buildFixturePem('')),
        isA<FingerprintsUnavailable>(),
      );
    });
  });

  test('T-20-FP-05: formatSha1Colon → 대문자 · 콜론 · 59자', () {
    final String formatted = formatSha1Colon(fixtureSha1Hex);

    expect(formatted, fixtureSha1Colon);
    expect(formatted, hasLength(59));
  });

  group('한 세션 안에서는 한 번만 계산한다', () {
    test('T-20-FP-06: 두 번 읽음 → keytool 1회 · 같은 값', () async {
      final home = '${tempDir.path}/home';
      final String keystorePath = createKeystorePlaceholder(home);
      final String pem = buildFixturePem(base64Encode(fixtureCertificateBytes));
      final runner = FakeCommandRunner()
        ..on(buildExportKey(keystorePath), CommandResult(0, pem, ''));
      final WizardContext context = buildContext(runner);

      final DebugFingerprints first = await readDebugFingerprints(context);
      final DebugFingerprints second = await readDebugFingerprints(context);

      expect(first, isA<FingerprintsAvailable>());
      expect(identical(first, second), isTrue);
      expect(
        runner.countCalls(RunMode.capture, buildExportKey(keystorePath)),
        1,
      );
      expect(context.session.debugFingerprints, same(first));
    });

    test('T-20-FP-06: 계산할 수 없음도 담아 두고 다시 묻지 않는다', () async {
      final home = '${tempDir.path}/home';
      final String keystorePath = createKeystorePlaceholder(home);
      final runner = FakeCommandRunner()
        ..on(buildExportKey(keystorePath), const CommandResult(1, '', 'x'));
      final WizardContext context = buildContext(runner);

      await readDebugFingerprints(context);
      final DebugFingerprints second = await readDebugFingerprints(context);

      expect(second, isA<FingerprintsUnavailable>());
      expect(runner.calls, hasLength(1));
    });
  });

  group('Firebase Android 앱 SHA 목록 · 등록 요청', () {
    test('T-20-FP-07: 목록 응답(대문자 섞임) → 소문자 집합', () {
      final body = jsonEncode(<String, Object>{
        'certificates': <Map<String, String>>[
          <String, String>{
            'name': 'projects/p/androidApps/a/sha/1',
            'shaHash': fixtureSha1Hex.toUpperCase(),
            'certType': 'SHA_1',
          },
          <String, String>{
            'name': 'projects/p/androidApps/a/sha/2',
            'shaHash': fixtureSha256Hex,
            'certType': 'SHA_256',
          },
        ],
      });

      expect(parseShaHashes(RestResponse(200, body)), <String>{
        fixtureSha1Hex,
        fixtureSha256Hex,
      });
    });

    test('T-20-FP-07: 키 없는 응답 → 빈 집합', () {
      expect(parseShaHashes(const RestResponse(200, '{}')), isEmpty);
      expect(parseShaHashes(const RestResponse(200, '{}')), isNotNull);
    });

    test('T-20-FP-07: 403 · JSON 아님 → null(읽지 못함)', () {
      expect(parseShaHashes(const RestResponse(403, '{}')), isNull);
      expect(parseShaHashes(const RestResponse(200, 'not json')), isNull);
      expect(parseShaHashes(const RestResponse(0, '')), isNull);
    });

    test('T-20-FP-07: 등록 요청 → POST …/sha · 본문 소문자 hex · SHA_256', () {
      final RestRequest request = buildShaCreateRequest(
        testProjectId,
        testAndroidAppId,
        shaHash: fixtureSha256Hex.toUpperCase(),
        certType: shaCertTypeSha256,
      );

      expect(request.method, 'POST');
      expect(
        request.url.toString(),
        'https://firebase.googleapis.com/v1beta1/projects/p/androidApps/'
        '$testAndroidAppId/sha',
      );
      expect(request.url.path, endsWith('/sha'));
      expect(request.quotaProject, testProjectId);
      expect(jsonDecode(request.body!), <String, String>{
        'shaHash': fixtureSha256Hex,
        'certType': 'SHA_256',
      });
    });

    test('T-20-FP-07: 목록 요청 → GET …/sha', () {
      final RestRequest request = buildShaListRequest(
        testProjectId,
        testAndroidAppId,
      );

      expect(request.method, 'GET');
      expect(request.url.path, endsWith('/androidApps/$testAndroidAppId/sha'));
      expect(request.body, isNull);
    });
  });
}
