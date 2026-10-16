import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'command_runner.dart';
import 'log_sink.dart';
import 'redactor.dart';
import 'terminal.dart';

/// 화면에 보일 토큰 자리 — 값 대신 값을 얻는 식을 보인다.
const String accessTokenExpression = r'$(gcloud auth print-access-token)';

/// REST 요청 하나 — 화면에는 [displayCurl] 만 보인다.
final class RestRequest {
  /// [method] 로 [url] 을 부르는 요청을 만든다.
  ///
  /// [quotaProject] 는 사용자 자격 증명으로 부를 때 사용량을 매길 프로젝트다
  /// (`x-goog-user-project` 헤더). [bodyDisplay] 가 있으면 화면 · 기록에는
  /// [body] 대신 그 값을 보인다.
  const RestRequest({
    required this.method,
    required this.url,
    required this.quotaProject,
    this.body,
    this.bodyDisplay,
    this.isResponseSensitive = false,
  });

  /// HTTP 메서드(`GET` · `POST` · `PATCH` 등).
  final String method;

  /// 요청 주소.
  final Uri url;

  /// 사용량을 매길 프로젝트 ID.
  final String quotaProject;

  /// JSON 요청 본문. null 이면 본문 없음.
  final String? body;

  /// 화면 · 기록에 보일 본문. null 이면 [body] 를 보인다.
  final String? bodyDisplay;

  /// 응답 본문에 사용자 정보 · 비밀 값이 섞일 수 있으면 true.
  final bool isResponseSensitive;

  /// 같은 요청을 터미널에서 다시 실행할 수 있는 curl 표시형을 만든다.
  ///
  /// 토큰 자리에는 [accessTokenExpression] 을 쓰고 `x-goog-user-project` 헤더를
  /// 항상 붙인다. 본문의 작은따옴표는 셸 관례대로 `'\''` 로 바꾼다.
  String displayCurl() {
    final StringBuffer buffer = StringBuffer()
      ..write('curl -s -X $method "$url"')
      ..write(' -H "Authorization: Bearer $accessTokenExpression"')
      ..write(' -H "x-goog-user-project: $quotaProject"');
    final String? shownBody = bodyDisplay ?? body;
    if (shownBody != null) {
      final String quoted = shownBody.replaceAll("'", r"'\''");
      buffer
        ..write(' -H "Content-Type: application/json"')
        ..write(" -d '$quoted'");
    }
    return buffer.toString();
  }
}

/// REST 응답 — 상태 코드 0 은 요청하지 못했다는 뜻이다.
final class RestResponse {
  /// 상태 코드와 본문으로 응답을 만든다.
  const RestResponse(this.statusCode, this.body);

  /// HTTP 상태 코드. 요청하지 못했으면 0.
  final int statusCode;

  /// 응답 본문 원문.
  final String body;

  /// 상태 코드가 2xx 면 true.
  bool get isOk => statusCode >= 200 && statusCode < 300;

  /// 본문을 JSON 으로 해석한다 — 비었거나 JSON 이 아니면 null.
  Object? decodeJson() {
    if (body.trim().isEmpty) return null;
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }
}

/// [response] 의 상태를 한 줄로 적는다 — 상태 코드 0 은 요청하지 못한 경우다.
String describeRestStatus(RestResponse response) =>
    response.statusCode == 0 ? '요청하지 못했습니다' : 'HTTP ${response.statusCode}';

/// 실패 응답 본문을 위저드가 원문으로 보일 결과 모양으로 바꾼다.
///
/// 본문이 비었으면 null. [redactor] 를 주면 본문을 가린 뒤 담는다 — 화면 ·
/// 기록은 가림 터미널을 거치지만, 결과 자체에 등록 값이 남지 않아야 하는
/// 단계가 쓴다.
CommandResult? toFailureResult(RestResponse response, {Redactor? redactor}) {
  if (response.body.isEmpty) return null;
  final String body = redactor == null
      ? response.body
      : redactor.apply(response.body);
  return CommandResult(1, '', body);
}

/// REST 요청 실행기 — 테스트는 가짜 구현을 주입한다.
abstract interface class RestClient {
  /// [request] 를 보내고 응답을 돌려준다.
  Future<RestResponse> send(RestRequest request);
}

/// gcloud 의 액세스 토큰을 읽는다 — 값은 프로세스 안에만 둔다.
final class AccessTokenSource {
  /// [runner] 로 토큰을 읽고 [redactor] 에 등록하는 토큰 출처를 만든다.
  AccessTokenSource(this.runner, this.redactor);

  /// 토큰을 읽을 실행기.
  final CommandRunner runner;

  /// 읽은 토큰을 등록할 가림 함수.
  final Redactor redactor;

  /// 토큰을 읽는 명령 — 출력이 비밀 값이라 민감 출력으로 실행한다.
  static const Command tokenCommand = Command('gcloud', <String>[
    'auth',
    'print-access-token',
  ], isOutputSensitive: true);

  /// 토큰을 읽는다 — 명령이 실패했거나 값이 비었으면 null.
  ///
  /// 로그인 계정이 있어도 토큰 갱신이 실패할 수 있으므로 이 명령의 성공 여부를
  /// 로그인 판정으로 쓴다. 읽은 토큰은 화면 · 기록에서 가리도록 등록한다.
  Future<String?> read() async {
    final CommandResult result = await runner.capture(tokenCommand);
    if (!result.isSuccess) return null;
    final String token = result.stdout.trim();
    if (token.isEmpty) return null;
    redactor.register(token);
    return token;
  }
}

/// `dart:io` [HttpClient] 로 REST 를 부르는 실행기.
///
/// 토큰은 요청 헤더에만 싣는다 — 외부 프로세스 인자 · 환경 변수 · 화면 · 기록에
/// 원문이 나가지 않는다. 화면에는 [RestRequest.displayCurl] 을 보이고, 기록에는
/// `<METHOD> <url> → <status>` 줄과 응답 본문(민감 응답이면 생략 표시)을 남긴다.
final class HttpRestClient implements RestClient {
  /// [tokens] 로 토큰을 읽고 [terminal] · [log] 에 요청을 남기는 실행기를 만든다.
  ///
  /// [httpClient] 를 주지 않으면 연결 제한 시간 [connectionTimeout] 의 새
  /// 클라이언트를 쓴다. [responseTimeout] 은 연결 뒤 응답 머리를 기다리는
  /// 상한이자 본문 조각 사이 간격의 상한이다.
  HttpRestClient({
    required this.tokens,
    required this.terminal,
    required this.log,
    HttpClient? httpClient,
    this.responseTimeout = defaultResponseTimeout,
  }) : _http =
           httpClient ?? (HttpClient()..connectionTimeout = connectionTimeout);

  /// 토큰 출처.
  final AccessTokenSource tokens;

  /// 표시형 · 안내를 쓸 터미널.
  final Terminal terminal;

  /// 실행 기록.
  final LogSink log;

  /// 연결 뒤 응답 머리를 기다리는 상한이자 본문 조각 사이 간격의 상한.
  ///
  /// 본문은 전체 시간이 아니라 조각이 올 때마다 다시 잰다 — 느리게라도 계속
  /// 오는 본문은 끊지 않고, 조각이 이 시간만큼 오지 않으면 끊는다.
  final Duration responseTimeout;

  final HttpClient _http;

  /// 기본 클라이언트의 연결 제한 시간.
  static const Duration connectionTimeout = Duration(seconds: 30);

  /// 응답 대기 상한의 기본값 — 연결 제한 시간은 TCP 연결까지만 막는다.
  static const Duration defaultResponseTimeout = Duration(minutes: 2);

  /// 응답 대기 상한을 넘겼을 때의 안내 머리.
  static const String responseTimeoutMessage =
      '  응답이 없어 요청을 중단했습니다 — 네트워크를 확인한 뒤 다시 시도하세요.';

  /// 민감 응답의 본문 대신 기록에 남기는 문구.
  static const String sensitiveResponseNotice = '(민감 응답 생략)';

  /// 토큰을 읽지 못했을 때의 안내.
  static const String tokenUnavailableMessage =
      '  gcloud 액세스 토큰을 읽지 못했습니다 — gcloud auth login 으로 다시 로그인한 '
      '뒤 다시 시도하세요.';

  @override
  Future<RestResponse> send(RestRequest request) async {
    final String target = '${request.method} ${request.url}';
    final String? token = await tokens.read();
    if (token == null) {
      terminal.writeLine(tokenUnavailableMessage);
      log.write('rest', '$target → 토큰 없음');
      return const RestResponse(0, '');
    }

    terminal.writeCommand(request.displayCurl());
    HttpClientRequest? openedRequest;
    // 머리를 받은 뒤에만 채운다 — 상한에 걸린 단계를 기록에서 가른다.
    int? statusCode;
    try {
      final HttpClientRequest httpRequest = await _http.openUrl(
        request.method,
        request.url,
      );
      openedRequest = httpRequest;
      httpRequest.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
        ..set('x-goog-user-project', request.quotaProject);
      final String? body = request.body;
      if (body != null) {
        final List<int> bytes = utf8.encode(body);
        httpRequest.headers.contentType = ContentType.json;
        httpRequest.contentLength = bytes.length;
        httpRequest.add(bytes);
      }
      // 연결 뒤 서버가 응답을 멈춰도 안내 없이 무한 대기하지 않게 상한을 건다.
      final HttpClientResponse response = await httpRequest.close().timeout(
        responseTimeout,
      );
      statusCode = response.statusCode;
      // 본문 상한은 스트림에 건다 — 상한에서 들어온 오류로 join 이 구독을
      // 취소해 응답 연결이 닫힌다. 머리를 받은 뒤라 abort() 는 효과가 없다.
      final String text = await response
          .transform(const Utf8Decoder(allowMalformed: true))
          .timeout(responseTimeout)
          .join();
      log
        ..write('rest', '$target → ${response.statusCode}')
        ..write(
          'rest',
          request.isResponseSensitive ? sensitiveResponseNotice : text,
        );
      return RestResponse(response.statusCode, text);
    } on IOException catch (e) {
      terminal.writeLine('  요청하지 못했습니다 — $e');
      log.write('rest', '$target → 요청 실패 $e');
      return const RestResponse(0, '');
    } on TimeoutException {
      // 머리 단계 상한이면 연결을 끊는다 — 본문 단계는 구독 취소로 이미 닫혔다.
      openedRequest?.abort();
      terminal.writeLine(responseTimeoutMessage);
      final String limit = '${responseTimeout.inMilliseconds}ms';
      log.write(
        'rest',
        statusCode == null
            ? '$target → 응답 없음 ($limit)'
            : '$target → $statusCode 뒤 본문 끊김 ($limit)',
      );
      return const RestResponse(0, '');
    }
  }

  /// 클라이언트를 닫는다 — 진행 중인 연결도 끊는다.
  void close() => _http.close(force: true);
}
