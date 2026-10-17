import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';

import '../../../tool/setup/providers/idp_config.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/rest_client.dart';
import '../../../tool/setup/terminal.dart';
import '../../../tool/setup/wizard.dart';
import 'fake_rest_client.dart';
import 'fakes.dart';

/// 테스트 프로젝트 ID.
const String projectId = 'idp-p';

/// 가짜 Apple Services ID.
const String fakeServicesId = 'com.example.idp.signin-service';

/// 실행 시점에 조립하는 PEM 개인 키 머리 줄.
String buildPemHead() => <String>['-----BEGIN', ' PRIVATE', ' KEY-----'].join();

/// 실행 시점에 조립하는 PEM 개인 키 끝 줄.
String buildPemTail() => <String>['-----END', ' PRIVATE', ' KEY-----'].join();

/// 가짜 PEM 본문 줄.
String buildPemBodyLine() => 'B' * 64;

/// 실행 시점에 조립하는 명백한 가짜 PEM 개인 키(여러 줄).
String buildFakePem() =>
    '${buildPemHead()}\n${buildPemBodyLine()}\n${buildPemTail()}\n';

/// 실행 시점에 조립하는 가짜 client secret.
String buildFakeClientSecret([String letter = 's']) =>
    'fake-client-secret-${letter * 16}';

/// [haystack] 에서 [needle] 이 나타나는 횟수를 센다.
int countText(String haystack, String needle) =>
    haystack.split(needle).length - 1;

/// 실제 REST 실행기처럼 요청 · 응답 줄을 기록에 남기는 REST 실행기.
///
/// 민감 응답이면 생략 표시를, 아니면 응답 본문을 그대로 기록한다.
final class _LoggingRest implements RestClient {
  _LoggingRest(this.inner, this.log);

  final FakeRestClient inner;
  final MemoryLogSink log;

  @override
  Future<RestResponse> send(RestRequest request) async {
    final RestResponse response = await inner.send(request);
    _writeResponse(
      request.method,
      request.url,
      request.isResponseSensitive,
      response,
    );
    return response;
  }

  @override
  Future<RestResponse> sendExternal(ExternalRequest request) async {
    final RestResponse response = await inner.sendExternal(request);
    _writeResponse(
      request.method,
      request.url,
      request.isResponseSensitive,
      response,
    );
    return response;
  }

  /// 요청 줄과 (민감 응답이 아니면) 응답 본문을 기록한다.
  void _writeResponse(
    String method,
    Uri url,
    bool isSensitive,
    RestResponse response,
  ) {
    log.write('rest', '$method $url → ${response.statusCode}');
    if (response.body.isEmpty) return;
    log.write(
      'rest',
      isSensitive ? HttpRestClient.sensitiveResponseNotice : response.body,
    );
  }
}

/// IdP 시험 한 번에 쓰는 가짜 REST · 화면 · 기록 묶음.
final class _Harness {
  _Harness()
    : rest = FakeRestClient(),
      screen = ScriptedTerminal(const <String?>[]),
      log = MemoryLogSink(Redactor());

  final FakeRestClient rest;
  final ScriptedTerminal screen;
  final MemoryLogSink log;

  /// 화면 출력 전체.
  String get output => screen.output.toString();

  /// 가림 터미널 · 기록을 남기는 REST 로 문맥을 만든다.
  WizardContext buildContext(String root) => WizardContext(
    projectRoot: root,
    runner: FakeCommandRunner(),
    terminal: RedactingTerminal(screen, log.redactor, log),
    redactor: log.redactor,
    log: log,
    rest: _LoggingRest(rest, log),
    homeDirectory: noKeystoreTestHome,
    random: Random(fixedTestRandomSeed),
    now: () => fixedTestNow,
  );
}

/// [idpId] 의 GET 주소.
String buildGetUrl(String idpId) =>
    '$idpConfigUrlPrefix$projectId/defaultSupportedIdpConfigs/$idpId';

void main() {
  late Directory tempDir;
  late String root;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('idp_config_test_');
    root = tempDir.path;
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('T-20-IDP-01: 빌더 셋은 민감 응답 · 주소 · updateMask · 표시형 본문을 쓴다', () {
    final RestRequest get = buildIdpGetRequest(projectId, 'facebook.com');
    expect(get.method, 'GET');
    expect(get.url.toString(), buildGetUrl('facebook.com'));
    expect(get.quotaProject, projectId);
    expect(get.isResponseSensitive, isTrue);
    expect(get.body, isNull);

    final String secret = buildFakeClientSecret();
    final String body = jsonEncode(<String, Object?>{
      'enabled': true,
      'clientId': '1' * 15,
      'clientSecret': secret,
    });
    final String display = jsonEncode(<String, Object?>{
      'enabled': true,
      'clientId': '1' * 15,
      'clientSecret': '<Facebook App Secret>',
    });
    final RestRequest create = buildIdpCreateRequest(
      projectId,
      'facebook.com',
      body: body,
      bodyDisplay: display,
    );
    expect(create.method, 'POST');
    expect(
      create.url.toString(),
      '$idpConfigUrlPrefix$projectId/defaultSupportedIdpConfigs'
      '?idpId=facebook.com',
    );
    expect(create.quotaProject, projectId);
    expect(create.isResponseSensitive, isTrue);
    expect(create.body, body);
    expect(countText(create.displayCurl(), secret), 0);
    expect(countText(create.displayCurl(), '<Facebook App Secret>'), 1);

    final RestRequest patch = buildIdpPatchRequest(
      projectId,
      'facebook.com',
      updateMask: 'enabled,clientId,clientSecret',
      body: body,
      bodyDisplay: display,
    );
    expect(patch.method, 'PATCH');
    expect(
      patch.url.toString(),
      '${buildGetUrl('facebook.com')}?updateMask=enabled,clientId,clientSecret',
    );
    expect(patch.quotaProject, projectId);
    expect(patch.isResponseSensitive, isTrue);
    expect(countText(patch.displayCurl(), secret), 0);
  });

  test('T-20-IDP-02: GET 응답의 중첩 clientSecret · privateKey 는 화면 · 기록 '
      '두 곳에 0회다', () async {
    final h = _Harness();
    final String secret = buildFakeClientSecret();
    final String pem = buildFakePem();
    final String body = jsonEncode(<String, Object?>{
      'name': 'projects/$projectId/defaultSupportedIdpConfigs/apple.com',
      'enabled': true,
      'clientId': fakeServicesId,
      'clientSecret': secret,
      'appleSignInConfig': <String, Object?>{
        'codeFlowConfig': <String, Object?>{
          'teamId': 'TEAMFIXTUR',
          'keyId': 'KEYFIXTURE',
          'privateKey': pem,
        },
        'bundleIds': <String>['com.example.idp.dev'],
      },
    });
    h.rest.on('GET', buildGetUrl('apple.com'), RestResponse(200, body));
    final WizardContext context = h.buildContext(root);

    final IdpRead read = await readIdpConfig(context, projectId, 'apple.com');

    expect(read, isA<IdpFound>());
    final Map<String, Object?> config = (read as IdpFound).config;
    expect(config['clientId'], fakeServicesId);
    // 받은 값을 어떤 모양으로 흘려도 가려지는지 본다.
    context.terminal
      ..writeLine(body)
      ..writeLine('$config');
    for (final String line in const LineSplitter().convert(pem)) {
      context.terminal.writeLine(line);
    }
    for (final buffer in <String>[h.output, h.log.text]) {
      expect(countText(buffer, secret), 0);
      expect(countText(buffer, buildPemBodyLine()), 0);
      expect(countText(buffer, buildPemHead()), 0);
      expect(countText(buffer, buildPemTail()), 0);
    }
    expect(countText(h.output, fakeServicesId), greaterThanOrEqualTo(1));
    expect(
      countText(h.log.text, HttpRestClient.sensitiveResponseNotice),
      greaterThanOrEqualTo(1),
    );
  });

  test('T-20-IDP-03: 목록 모양 응답의 clientSecret · privateKey 를 모두 '
      '등록한다', () {
    final redactor = Redactor();
    final String secret = buildFakeClientSecret('f');
    final String pem = buildFakePem();
    final Object? decoded = jsonDecode(
      jsonEncode(<String, Object?>{
        'defaultSupportedIdpConfigs': <Object?>[
          <String, Object?>{
            'name':
                'projects/$projectId/defaultSupportedIdpConfigs/'
                'facebook.com',
            'clientId': '1' * 15,
            'clientSecret': secret,
          },
          <String, Object?>{
            'name': 'projects/$projectId/defaultSupportedIdpConfigs/apple.com',
            'clientId': fakeServicesId,
            'clientSecret': 12345678901,
            'appleSignInConfig': <String, Object?>{
              'codeFlowConfig': <String, Object?>{'privateKey': pem},
            },
          },
        ],
      }),
    );

    registerIdpSecrets(redactor, decoded);

    expect(redactor.apply(secret), Redactor.mask);
    expect(redactor.apply(buildPemBodyLine()), Redactor.mask);
    expect(redactor.apply(pem), Redactor.mask);
    expect(countText(redactor.apply(pem.trim()), buildPemBodyLine()), 0);
    // 비밀 키가 아닌 값은 등록하지 않는다.
    expect(redactor.apply(fakeServicesId), fakeServicesId);
    expect(redactor.apply('1' * 15), '1' * 15);
    expect(redactor.apply('12345678901'), '12345678901');
  });

  test('T-20-IDP-04: 오류 응답 본문의 clientSecret 은 실패 원문을 보여도 '
      '0회다', () async {
    final h = _Harness();
    final String secret = buildFakeClientSecret('e');
    final String body = jsonEncode(<String, Object?>{
      'error': <String, Object?>{
        'code': 400,
        'message': 'INVALID_CONFIG',
        'details': <Object?>[
          <String, Object?>{'clientSecret': secret},
        ],
      },
    });
    h.rest.on('GET', buildGetUrl('facebook.com'), RestResponse(400, body));
    final WizardContext context = h.buildContext(root);

    final IdpRead read = await readIdpConfig(
      context,
      projectId,
      'facebook.com',
    );

    expect(read, isA<IdpReadFailed>());
    final failed = read as IdpReadFailed;
    expect(failed.reason, contains('HTTP 400'));
    expect(failed.result, isNotNull);
    expect(countText(failed.result!.stderr, secret), 0);
    expect(failed.result!.stderr, contains('INVALID_CONFIG'));
    context.terminal
      ..writeLine(failed.reason)
      ..writeRaw(failed.result!.stderr)
      ..writeLine(body);
    for (final buffer in <String>[h.output, h.log.text]) {
      expect(countText(buffer, secret), 0);
    }
  });

  test('T-20-IDP-05: 404 는 설정 없음 · 403 · 상태 0 · 객체가 아닌 200 은 '
      '읽기 실패다', () async {
    final h = _Harness();
    h.rest
      ..on('GET', buildGetUrl('facebook.com'), const RestResponse(404, ''))
      ..on(
        'GET',
        buildGetUrl('apple.com'),
        const RestResponse(403, '{"error":{"code":403}}'),
      )
      ..on('GET', buildGetUrl('google.com'), const RestResponse(0, ''))
      ..on('GET', buildGetUrl('example.com'), const RestResponse(200, '[]'));
    final WizardContext context = h.buildContext(root);

    expect(
      await readIdpConfig(context, projectId, 'facebook.com'),
      isA<IdpMissing>(),
    );
    final IdpRead forbidden = await readIdpConfig(
      context,
      projectId,
      'apple.com',
    );
    expect(forbidden, isA<IdpReadFailed>());
    expect((forbidden as IdpReadFailed).reason, contains('HTTP 403'));
    expect(forbidden.result, isNotNull);
    final IdpRead offline = await readIdpConfig(
      context,
      projectId,
      'google.com',
    );
    expect(offline, isA<IdpReadFailed>());
    expect((offline as IdpReadFailed).reason, contains('요청하지 못했습니다'));
    expect(offline.result, isNull);
    final IdpRead notObject = await readIdpConfig(
      context,
      projectId,
      'example.com',
    );
    expect(notObject, isA<IdpReadFailed>());
    expect((notObject as IdpReadFailed).reason, contains('HTTP 200'));
  });
}
