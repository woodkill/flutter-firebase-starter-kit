import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/setup/command_runner.dart';
import '../../../tool/setup/redactor.dart';
import '../../../tool/setup/rest_client.dart';
import '../../../tool/setup/terminal.dart';
import 'fake_rest_client.dart';
import 'fakes.dart';

// 토큰 모양 문자열은 실행 시점에 조립한다 — tracked 소스에 완형으로 두지 않는다.

/// 가짜 액세스 토큰(`ya29.` 모양)을 조립한다.
String buildFakeAccessToken() => 'ya29.${'B' * 40}';

/// 토큰을 읽는 명령의 가짜 실행기 키.
const String tokenCommandKey = 'gcloud auth print-access-token';

/// 화면에 보여야 하는 토큰 표시형.
const String tokenExpression = r'$(gcloud auth print-access-token)';

/// [haystack] 에서 [needle] 이 나타나는 횟수를 센다.
int countText(String haystack, String needle) =>
    haystack.split(needle).length - 1;

/// 머리와 본문 앞 조각(chunked)만 보내고 나머지를 멈춘 응답 원문.
const String stalledBodyResponse =
    'HTTP/1.1 200 OK\r\n'
    'content-type: application/json\r\n'
    'transfer-encoding: chunked\r\n'
    '\r\n'
    '5\r\n'
    '{"a":\r\n';

/// 로컬 서버가 받은 요청 한 건.
final class ReceivedRequest {
  /// 받은 요청의 값으로 만든다.
  const ReceivedRequest({
    required this.method,
    required this.path,
    required this.authorization,
    required this.quotaProject,
    required this.contentType,
    required this.body,
  });

  /// HTTP 메서드.
  final String method;

  /// 요청 경로.
  final String path;

  /// `authorization` 헤더 값.
  final String? authorization;

  /// `x-goog-user-project` 헤더 값.
  final String? quotaProject;

  /// `content-type` 헤더 값.
  final String? contentType;

  /// 요청 본문.
  final String body;
}

void main() {
  late HttpServer server;
  late List<ReceivedRequest> received;
  late int responseStatus;
  late String responseBody;
  late bool isResponseHeld;
  late Redactor redactor;
  late MemoryLogSink log;
  late ScriptedTerminal screen;
  late RedactingTerminal terminal;
  late FakeCommandRunner runner;
  late HttpRestClient client;

  setUp(() async {
    received = <ReceivedRequest>[];
    responseStatus = 200;
    responseBody = '{"ok":true}';
    isResponseHeld = false;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((HttpRequest request) async {
      final String body = await utf8.decodeStream(request);
      received.add(
        ReceivedRequest(
          method: request.method,
          path: request.uri.path,
          authorization: request.headers.value('authorization'),
          quotaProject: request.headers.value('x-goog-user-project'),
          contentType: request.headers.value('content-type'),
          body: body,
        ),
      );
      // 응답을 멈춘 서버를 흉내 낸다 — tearDown 의 강제 종료가 연결을 끊는다.
      if (isResponseHeld) return;
      request.response
        ..statusCode = responseStatus
        ..headers.contentType = ContentType.json
        ..write(responseBody);
      await request.response.close();
    });

    redactor = Redactor();
    log = MemoryLogSink(redactor);
    screen = ScriptedTerminal(const <String?>[]);
    terminal = RedactingTerminal(screen, redactor, log);
    runner = FakeCommandRunner();
    client = HttpRestClient(
      tokens: AccessTokenSource(runner, redactor),
      terminal: terminal,
      log: log,
    );
  });

  tearDown(() async {
    client.close();
    await server.close(force: true);
  });

  /// 로컬 서버의 [path] 주소를 만든다.
  Uri buildLocalUrl(String path) =>
      Uri.parse('http://${server.address.address}:${server.port}$path');

  test('T-19-REST-01: 토큰은 요청 헤더에만 실리고 화면에는 표시형만 보인다', () async {
    final String token = buildFakeAccessToken();
    runner.on(tokenCommandKey, CommandResult(0, '$token\n', ''));
    final Uri url = buildLocalUrl('/admin/v2/projects/demo-p/config');

    final RestResponse response = await client.send(
      RestRequest(method: 'GET', url: url, quotaProject: 'demo-p'),
    );

    expect(response.statusCode, 200);
    expect(response.isOk, isTrue);
    expect(response.decodeJson(), <String, Object?>{'ok': true});
    expect(received, hasLength(1));
    expect(received.single.method, 'GET');
    expect(received.single.authorization, 'Bearer $token');
    expect(received.single.quotaProject, 'demo-p');

    // 토큰은 민감 capture 한 번으로만 읽는다.
    expect(runner.countCalls(RunMode.capture, tokenCommandKey), 1);
    expect(runner.calls.single.isOutputSensitive, isTrue);

    final String shown = screen.output.toString();
    expect(countText(shown, tokenExpression), 1);
    expect(shown, contains('-H "x-goog-user-project: demo-p"'));
    expect(countText(shown, token), 0);
    expect(countText(log.text, token), 0);
    expect(log.lines, contains('[rest] GET $url → 200'));
  });

  test('T-19-REST-02: 민감 응답은 기록에 본문 대신 생략 표시 · 반환 본문은 원문', () async {
    runner.on(tokenCommandKey, CommandResult(0, buildFakeAccessToken(), ''));
    responseBody = '{"users":[{"email":"someone@example.com"}]}';
    final Uri url = buildLocalUrl('/v1/projects/demo-p/accounts:batchGet');

    final RestResponse response = await client.send(
      RestRequest(
        method: 'GET',
        url: url,
        quotaProject: 'demo-p',
        isResponseSensitive: true,
      ),
    );

    expect(response.body, responseBody);
    expect(countText(log.text, 'someone@example.com'), 0);
    expect(countText(screen.output.toString(), 'someone@example.com'), 0);
    expect(log.lines, contains('[rest] GET $url → 200'));
    expect(
      log.lines,
      contains('[rest] ${HttpRestClient.sensitiveResponseNotice}'),
    );
    expect(HttpRestClient.sensitiveResponseNotice, '(민감 응답 생략)');
  });

  test('T-19-REST-03: 화면 · 기록에는 bodyDisplay 만, 서버는 body 를 받는다', () async {
    runner.on(tokenCommandKey, CommandResult(0, buildFakeAccessToken(), ''));
    const String body = '{"value":"real-value-0123456789"}';
    const String bodyDisplay = '{"value":"<새 값>"}';
    final Uri url = buildLocalUrl('/v1/projects/demo-p/things');

    await client.send(
      RestRequest(
        method: 'POST',
        url: url,
        quotaProject: 'demo-p',
        body: body,
        bodyDisplay: bodyDisplay,
      ),
    );

    expect(received.single.method, 'POST');
    expect(received.single.body, body);
    expect(received.single.contentType, startsWith('application/json'));
    final String shown = screen.output.toString();
    expect(shown, contains("-d '$bodyDisplay'"));
    expect(shown, contains('-H "Content-Type: application/json"'));
    expect(countText(shown, 'real-value-0123456789'), 0);
    expect(countText(log.text, 'real-value-0123456789'), 0);
  });

  test('T-19-REST-04: 토큰을 읽지 못하면 요청하지 않고 안내 한 줄과 빈 응답', () async {
    runner.on(
      tokenCommandKey,
      const CommandResult(
        1,
        '',
        'ERROR: (gcloud.auth.print-access-token) Reauthentication failed. '
            'cannot prompt during non-interactive execution.\n',
      ),
    );
    final Uri url = buildLocalUrl('/admin/v2/projects/demo-p/config');

    final RestResponse response = await client.send(
      RestRequest(method: 'GET', url: url, quotaProject: 'demo-p'),
    );

    expect(received, isEmpty);
    expect(response.statusCode, 0);
    expect(response.body, isEmpty);
    expect(response.isOk, isFalse);
    final String shown = screen.output.toString();
    expect(countText(shown, HttpRestClient.tokenUnavailableMessage), 1);
    expect(countText(shown, 'curl '), 0);
  });

  test('T-19-REST-06: 연결 뒤 응답이 없으면 상한에서 끊고 안내 한 줄과 빈 응답', () async {
    isResponseHeld = true;
    runner.on(
      tokenCommandKey,
      CommandResult(0, '${buildFakeAccessToken()}\n', ''),
    );
    final HttpRestClient slowClient = HttpRestClient(
      tokens: AccessTokenSource(runner, redactor),
      terminal: terminal,
      log: log,
      responseTimeout: const Duration(milliseconds: 200),
    );
    addTearDown(slowClient.close);
    final Uri url = buildLocalUrl('/v1/projects/demo-p/stalled');

    final RestResponse response = await slowClient.send(
      RestRequest(method: 'GET', url: url, quotaProject: 'demo-p'),
    );

    expect(response.statusCode, 0);
    expect(response.body, isEmpty);
    expect(received, hasLength(1));
    expect(
      screen.output.toString(),
      contains(HttpRestClient.responseTimeoutMessage),
    );
    expect(log.lines, contains('[rest] GET $url → 응답 없음 (200ms)'));
  });

  test('T-19-REST-07: 머리 뒤 본문이 멈추면 상한에서 끊고 응답 연결을 닫는다', () async {
    // HttpServer 는 응답을 쥔 처리기가 있으면 클라이언트 쪽 닫힘을 연결 수에
    // 바로 반영하지 않는다 — 원시 소켓 서버로 연결이 닫히는 순간을 직접 본다.
    final ServerSocket rawServer = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final Completer<void> clientClosed = Completer<void>();
    final List<Socket> accepted = <Socket>[];
    rawServer.listen((Socket socket) {
      accepted.add(socket);
      socket.done.ignore();
      bool isResponseSent = false;
      socket.listen(
        (List<int> data) {
          if (isResponseSent) return;
          isResponseSent = true;
          socket.write(stalledBodyResponse);
        },
        onDone: () {
          if (!clientClosed.isCompleted) clientClosed.complete();
        },
        onError: (Object error) {
          if (!clientClosed.isCompleted) clientClosed.complete();
        },
      );
    });
    addTearDown(() async {
      for (final Socket socket in accepted) {
        socket.destroy();
      }
      await rawServer.close();
    });
    runner.on(
      tokenCommandKey,
      CommandResult(0, '${buildFakeAccessToken()}\n', ''),
    );
    final HttpRestClient slowClient = HttpRestClient(
      tokens: AccessTokenSource(runner, redactor),
      terminal: terminal,
      log: log,
      responseTimeout: const Duration(milliseconds: 200),
    );
    addTearDown(slowClient.close);
    final String host = '${rawServer.address.address}:${rawServer.port}';
    final Uri url = Uri.parse('http://$host/v1/projects/demo-p/stalled-body');

    final RestResponse response = await slowClient.send(
      RestRequest(method: 'GET', url: url, quotaProject: 'demo-p'),
    );

    expect(response.statusCode, 0);
    expect(response.body, isEmpty);
    expect(
      screen.output.toString(),
      contains(HttpRestClient.responseTimeoutMessage),
    );
    expect(log.lines, contains('[rest] GET $url → 응답 없음 (200ms)'));
    // 클라이언트를 닫기 전에 연결이 닫혀야 한다 — 상한 뒤에도 본문 구독이
    // 남으면 연결은 클라이언트를 닫을 때까지 열려 있다.
    await expectLater(
      clientClosed.future.timeout(const Duration(seconds: 2)),
      completes,
    );
  });

  test('T-19-REST-05: FakeRestClient 는 등록 안 된 요청에 StateError', () async {
    final FakeRestClient fake = FakeRestClient()
      ..on(
        'GET',
        'https://example.test/v1/a',
        const RestResponse(200, '{"a":1}'),
      );

    final RestResponse response = await fake.send(
      RestRequest(
        method: 'GET',
        url: Uri.parse('https://example.test/v1/a'),
        quotaProject: 'demo-p',
      ),
    );
    expect(response.body, '{"a":1}');
    expect(fake.requests, hasLength(1));

    await expectLater(
      fake.send(
        RestRequest(
          method: 'PATCH',
          url: Uri.parse('https://example.test/v1/a'),
          quotaProject: 'demo-p',
        ),
      ),
      throwsStateError,
    );
  });

  test('RestRequest.displayCurl 은 quota 헤더를 항상 붙이고 작은따옴표를 이스케이프한다', () {
    final RestRequest request = RestRequest(
      method: 'PATCH',
      url: Uri.parse('https://example.test/v2/p?updateMask=a,b'),
      quotaProject: 'demo-p',
      body: '{"name":"it\'s"}',
    );

    expect(
      request.displayCurl(),
      'curl -s -X PATCH "https://example.test/v2/p?updateMask=a,b" '
      '-H "Authorization: Bearer $tokenExpression" '
      '-H "x-goog-user-project: demo-p" '
      '-H "Content-Type: application/json" '
      "-d '{\"name\":\"it'\\''s\"}'",
    );
  });

  test('RestResponse.decodeJson 은 JSON 이 아니면 null', () {
    expect(const RestResponse(200, '').decodeJson(), isNull);
    expect(const RestResponse(200, 'not json').decodeJson(), isNull);
    expect(const RestResponse(200, '[1,2]').decodeJson(), <Object?>[1, 2]);
    expect(const RestResponse(299, '').isOk, isTrue);
    expect(const RestResponse(300, '').isOk, isFalse);
  });
}
