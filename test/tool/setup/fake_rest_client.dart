import '../../../tool/setup/rest_client.dart';

/// 등록한 응답을 돌려주는 가짜 REST 실행기 — 네트워크에 닿지 않는다.
final class FakeRestClient implements RestClient {
  final Map<String, List<RestResponse>> _responses =
      <String, List<RestResponse>>{};

  final Map<String, List<RestResponse>> _externalResponses =
      <String, List<RestResponse>>{};

  /// 받은 요청(순서대로).
  final List<RestRequest> requests = <RestRequest>[];

  /// 받은 외부 요청(순서대로).
  final List<ExternalRequest> externalRequests = <ExternalRequest>[];

  /// [method] · [url] 요청의 응답 큐에 [response] 를 더한다.
  ///
  /// 큐는 앞에서부터 하나씩 쓰고, 마지막 하나는 계속 되풀이한다.
  void on(String method, String url, RestResponse response) {
    _responses
        .putIfAbsent(buildKey(method, url), () => <RestResponse>[])
        .add(response);
  }

  /// 외부 [method] · [url] 요청의 응답 큐에 [response] 를 더한다.
  ///
  /// 큐 규칙은 [on] 과 같다 — 마지막 하나는 계속 되풀이한다.
  void onExternal(String method, String url, RestResponse response) {
    _externalResponses
        .putIfAbsent(buildKey(method, url), () => <RestResponse>[])
        .add(response);
  }

  /// [method] · [url] 로 받은 요청 수를 센다.
  int countRequests(String method, String url) => requests
      .where(
        (RestRequest request) =>
            buildKey(request.method, request.url.toString()) ==
            buildKey(method, url),
      )
      .length;

  /// 요청을 키 문자열로 바꾼다.
  static String buildKey(String method, String url) => '$method $url';

  @override
  Future<RestResponse> send(RestRequest request) async {
    requests.add(request);
    final String key = buildKey(request.method, request.url.toString());
    final List<RestResponse>? queue = _responses[key];
    if (queue == null || queue.isEmpty) {
      throw StateError('등록하지 않은 요청: $key');
    }
    return queue.length > 1 ? queue.removeAt(0) : queue.first;
  }

  @override
  Future<RestResponse> sendExternal(ExternalRequest request) async {
    externalRequests.add(request);
    final String key = buildKey(request.method, request.url.toString());
    final List<RestResponse>? queue = _externalResponses[key];
    if (queue == null || queue.isEmpty) {
      throw StateError('등록하지 않은 외부 요청: $key');
    }
    return queue.length > 1 ? queue.removeAt(0) : queue.first;
  }
}
