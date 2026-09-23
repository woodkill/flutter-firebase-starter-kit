// Phase 16.5 — see ROADMAP.md (NaverWebAuthClient unit tests)
//
// Pattern: Phase 15 yahoojp_sdk_client_test.dart 의 typedef 주입 패턴 mirror.
// `FlutterWebAuth2.authenticate` 를 함수 typedef 로 fake 해 authorize URL 조립 ·
// state 대조 · 취소/오류 분기(D-12a) · 로그 리댁션(WR-05) 을 잠근다.
//
// **Mock 한계 명시 (Phase 14.1 D-14.1-03 §7-C baseline 적용):**
// 본 테스트는 flutter_web_auth_2 의 native 세션(Android Auth Tab / Custom Tab ·
// iOS ASWebAuthenticationSession) 호출을 함수 typedef 주입으로 우회한다. 실
// 단말의 세션 표시 · 콜백 배달(CallbackActivity intent-filter) 은 본 테스트로
// 검증 불가 — plan 16.5-04 Task 3 tracer · plan 06 UAT 가 실 단말 계약의 단일
// 진실원이다.
//
// 테스트 값은 전부 fake 다(`fake-client-id` · `probe-scheme` · `FAKE_CODE`) —
// 실 client_id · scheme 리터럴을 쓰지 않는다 (plan 04 prohibition).
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/features/auth/data/naver_sign_in_result.dart';
import 'package:flutter_starter_kit/features/auth/data/naver_web_auth_client.dart';

const String _fakeClientId = 'fake-client-id';
const String _fakeScheme = 'probe-scheme';
const String _fakeRedirectUri = 'probe-scheme://authorize';
const String _fakeCode = 'FAKE_CODE';

/// authenticate fake 호출 기록 + 응답기.
///
/// [respond] 는 fake 에 넘어온 authorize URL 을 받아 콜백 URL 을 돌려준다 —
/// 정상 흐름 fixture 는 URL 의 `state` 를 그대로 echo 해야 하기 때문이다.
class AuthenticateRecorder {
  /// [respond] 로 콜백 URL 을 만드는 recorder 를 만든다.
  AuthenticateRecorder(this.respond);

  /// authorize URL → 콜백 URL (또는 throw).
  final Future<String> Function(String url) respond;

  /// 호출마다 넘어온 authorize URL.
  final List<String> urls = <String>[];

  /// 호출마다 넘어온 callbackUrlScheme.
  final List<String> schemes = <String>[];

  /// 호출마다 넘어온 preferEphemeral.
  final List<bool> ephemerals = <bool>[];

  /// [NaverWebAuthenticateFn] 시그니처 구현.
  Future<String> authenticate({
    required String url,
    required String callbackUrlScheme,
    required bool preferEphemeral,
  }) {
    urls.add(url);
    schemes.add(callbackUrlScheme);
    ephemerals.add(preferEphemeral);
    return respond(url);
  }
}

/// [url] 의 `state` 쿼리 값을 읽는다.
String stateOf(String url) => Uri.parse(url).queryParameters['state'] ?? '';

/// 정상 콜백 — authorize URL 의 state 를 echo 하고 [code] 를 싣는다.
Future<String> echoCallback(String url, {String code = _fakeCode}) async =>
    '$_fakeScheme://authorize?code=$code&state=${stateOf(url)}';

/// fake 설정으로 [NaverWebAuthClient.forTest] 를 만든다.
NaverWebAuthClient buildClient(
  AuthenticateRecorder recorder, {
  String clientId = _fakeClientId,
  String callbackUrlScheme = _fakeScheme,
  String redirectUri = _fakeRedirectUri,
}) => NaverWebAuthClient.forTest(
  clientId: clientId,
  callbackUrlScheme: callbackUrlScheme,
  redirectUri: redirectUri,
  authenticate: recorder.authenticate,
);

/// [client] 의 `signIn()` 이 던진 예외를 돌려준다 (throw 없으면 null).
Future<Object?> captureError(NaverWebAuthClient client) async {
  try {
    await client.signIn();
    return null;
  } on Object catch (e) {
    return e;
  }
}

/// `debugPrint` 를 가로채 줄 목록을 돌려준다 (tearDown 에서 원복).
List<String> captureLogs() {
  final logs = <String>[];
  final originalDebugPrint = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) logs.add(message);
  };
  addTearDown(() => debugPrint = originalDebugPrint);
  return logs;
}

void main() {
  group('NaverWebAuthClient.signIn (T-16.5-NAVER-WEB)', () {
    test('T-16.5-NAVER-WEB-01 authorize URL: nid.naver.com 4 파라미터 + '
        'state 22자 base64url', () async {
      final recorder = AuthenticateRecorder(echoCallback);

      await buildClient(recorder).signIn();

      expect(recorder.urls, hasLength(1));
      final uri = Uri.parse(recorder.urls.single);
      expect(uri.scheme, 'https');
      expect(uri.host, 'nid.naver.com');
      expect(uri.path, '/oauth2.0/authorize');
      expect(uri.queryParameters.keys.toSet(), <String>{
        'response_type',
        'client_id',
        'redirect_uri',
        'state',
      }, reason: 'probe ② A5 — 부가 파라미터 없이 4개만');
      expect(uri.queryParameters['response_type'], 'code');
      expect(uri.queryParameters['client_id'], _fakeClientId);
      expect(uri.queryParameters['redirect_uri'], _fakeRedirectUri);
      final state = uri.queryParameters['state']!;
      expect(
        state.length,
        22,
        reason: '16 bytes Random.secure() → base64Url padding 제거 = 22 chars',
      );
      expect(
        RegExp(r'^[A-Za-z0-9_-]{22}$').hasMatch(state),
        isTrue,
        reason: 'state 가 base64url 안전 문자 집합만 포함해야 한다',
      );
    });

    test('T-16.5-NAVER-WEB-02 success: 콜백 code + echo state → '
        'NaverWebSignIn(code, state)', () async {
      final recorder = AuthenticateRecorder(echoCallback);

      final result = await buildClient(recorder).signIn();

      expect(result, isA<NaverWebSignIn>());
      expect(result!.code, _fakeCode);
      expect(
        result.state,
        stateOf(recorder.urls.single),
        reason: '반환 state 는 authorize 에 실은 값 그대로 (서버 교환 파라미터)',
      );
    });

    test(
      'T-16.5-NAVER-WEB-03 cancel: CANCELED + '
      "'User canceled authentication' (Android Auth Tab 닫기) → null",
      () async {
        final recorder = AuthenticateRecorder(
          (url) async => throw PlatformException(
            code: 'CANCELED',
            message: 'User canceled authentication',
          ),
        );

        expect(await buildClient(recorder).signIn(), isNull);
        expect(recorder.urls, hasLength(1), reason: '대조군 — 세션은 열렸다');
      },
    );

    test(
      'T-16.5-NAVER-WEB-04 cancel: CANCELED + '
      "'User canceled login' (Android dangling 정리 · iOS 닫기) → null",
      () async {
        final recorder = AuthenticateRecorder(
          (url) async => throw PlatformException(
            code: 'CANCELED',
            message: 'User canceled login',
          ),
        );

        expect(await buildClient(recorder).signIn(), isNull);
      },
    );

    test('T-16.5-NAVER-WEB-05 cancel: CANCELED + 빈 message → null '
        '(message 로 판정하지 않는다)', () async {
      for (final message in const <String?>['', null]) {
        final recorder = AuthenticateRecorder(
          (url) async =>
              throw PlatformException(code: 'CANCELED', message: message),
        );

        expect(
          await buildClient(recorder).signIn(),
          isNull,
          reason: 'message=$message 여도 code 만으로 취소',
        );
      }
    });

    test('T-16.5-NAVER-WEB-06 access_denied: 동의 화면 취소 → null', () async {
      final recorder = AuthenticateRecorder(
        (url) async =>
            '$_fakeScheme://authorize?error=access_denied'
            '&error_description=Canceled+By+User&state=${stateOf(url)}',
      );

      expect(await buildClient(recorder).signIn(), isNull);
    });

    test('T-16.5-NAVER-WEB-07 기타 error: access_denied 외 error → '
        'ServiceUnavailable', () async {
      final recorder = AuthenticateRecorder(
        (url) async =>
            '$_fakeScheme://authorize?error=server_error'
            '&state=${stateOf(url)}',
      );

      expect(
        await captureError(buildClient(recorder)),
        isA<ServiceUnavailable>(),
      );
    });

    test('T-16.5-NAVER-WEB-08 state 불일치: 콜백 state ≠ 생성 state → '
        'ServiceUnavailable + 불일치 로그 (D-14 CSRF)', () async {
      final logs = captureLogs();
      final recorder = AuthenticateRecorder(
        (url) async => '$_fakeScheme://authorize?code=$_fakeCode&state=forged',
      );

      final error = await captureError(buildClient(recorder));

      expect(error, isA<ServiceUnavailable>());
      expect(logs, contains('Naver web state 불일치'));
      expect(
        logs,
        contains(
          predicate<String>(
            (line) =>
                line.startsWith('Naver web 도착: outcome=error') &&
                line.endsWith(' code=state'),
          ),
        ),
      );
    });

    test('T-16.5-NAVER-WEB-09 code 부재 · 빈 문자열 → ServiceUnavailable', () async {
      final callbacks = <Future<String> Function(String url)>[
        (url) async => '$_fakeScheme://authorize?state=${stateOf(url)}',
        (url) async => '$_fakeScheme://authorize?code=&state=${stateOf(url)}',
      ];
      for (final respond in callbacks) {
        final error = await captureError(
          buildClient(AuthenticateRecorder(respond)),
        );
        expect(error, isA<ServiceUnavailable>());
      }
    });

    test('T-16.5-NAVER-WEB-10 PlatformException FAILED → 그대로 rethrow '
        '(호출자가 ServiceUnavailable 로 접는다)', () async {
      final logs = captureLogs();
      final recorder = AuthenticateRecorder(
        (url) async => throw PlatformException(
          code: 'FAILED',
          message: 'Authentication returned no URI',
        ),
      );

      final error = await captureError(buildClient(recorder));

      expect(
        error,
        isA<PlatformException>().having((e) => e.code, 'code', 'FAILED'),
      );
      expect(
        logs,
        contains(
          predicate<String>(
            (line) =>
                line.startsWith('Naver web 도착: outcome=error') &&
                line.endsWith(' code=FAILED'),
          ),
        ),
      );
    });

    test('T-16.5-NAVER-WEB-11 clientId 빈 문자열 → 세션 열기 전 '
        'ServiceUnavailable (authenticate 0회)', () async {
      final logs = captureLogs();
      final recorder = AuthenticateRecorder(echoCallback);

      final error = await captureError(buildClient(recorder, clientId: ''));

      expect(error, isA<ServiceUnavailable>());
      expect(recorder.urls, isEmpty, reason: '설정 오류는 세션을 열지 않는다');
      expect(
        logs,
        contains('Naver web 도착: outcome=error elapsedMs=0 code=config'),
      );

      // 양성 대조군 — 같은 recorder 로 정상 설정이면 세션이 실제로 열린다.
      await buildClient(recorder).signIn();
      expect(recorder.urls, hasLength(1));
    });

    test(
      'T-16.5-NAVER-WEB-12 scheme RFC 3986 위반 · 빈 redirectUri → '
      'ServiceUnavailable (ArgumentError 로 새지 않는다 · authenticate 0회)',
      () async {
        final recorder = AuthenticateRecorder(echoCallback);
        final badClients = <NaverWebAuthClient>[
          buildClient(recorder, callbackUrlScheme: 'Foo_bar'),
          buildClient(recorder, callbackUrlScheme: '1abc'),
          buildClient(recorder, callbackUrlScheme: ''),
          buildClient(recorder, redirectUri: ''),
        ];

        for (final client in badClients) {
          final error = await captureError(client);
          expect(error, isA<ServiceUnavailable>());
          expect(error, isNot(isA<ArgumentError>()));
        }
        expect(recorder.urls, isEmpty);
      },
    );

    // 16.5 review IN-04 — AppConfig.naverWebRedirectUri 는 dart-define 이
    // 없어도 "://authorize" 라 isEmpty 가드가 도달 불가였다. 형태를 본다.
    test('T-16.5-NAVER-WEB-18 redirectUri 형태 불일치 → 세션 열기 전 '
        'ServiceUnavailable(code=config) · https bounce 는 통과', () async {
      final logs = captureLogs();
      final recorder = AuthenticateRecorder(echoCallback);
      final badRedirects = <String>[
        '://authorize', // dart-define 미주입 시 AppConfig 가 만드는 값
        'other-scheme://authorize', // callbackUrlScheme 과 다른 custom scheme
        'http://example.com/naver/callback', // https 아닌 웹 주소
        'https:///naver/callback', // host 없는 https
      ];

      for (final redirectUri in badRedirects) {
        final error = await captureError(
          buildClient(recorder, redirectUri: redirectUri),
        );
        expect(error, isA<ServiceUnavailable>(), reason: redirectUri);
      }
      expect(recorder.urls, isEmpty, reason: '설정 오류는 세션을 열지 않는다');
      expect(
        logs.where(
          (l) => l == 'Naver web 도착: outcome=error elapsedMs=0 code=config',
        ),
        hasLength(badRedirects.length),
      );

      // 양성 대조군 — 매뉴얼 9단계 (6) Hosting bounce 형태는 세션을 연다.
      final result = await buildClient(
        recorder,
        redirectUri: 'https://example.web.app/naver/callback',
      ).signIn();
      expect(result, isA<NaverWebSignIn>());
      expect(recorder.urls, hasLength(1));
    });

    test('T-16.5-NAVER-WEB-13 매 호출 state 가 새로 생성된다', () async {
      final recorder = AuthenticateRecorder(echoCallback);
      final client = buildClient(recorder);

      final first = await client.signIn();
      final second = await client.signIn();

      expect(first!.state, isNot(second!.state));
      expect(stateOf(recorder.urls[0]), isNot(stateOf(recorder.urls[1])));
    });

    test('T-16.5-NAVER-WEB-14 세션 옵션: preferEphemeral=false (D-12) + '
        'callbackUrlScheme 전달', () async {
      final recorder = AuthenticateRecorder(echoCallback);

      await buildClient(recorder).signIn();

      expect(recorder.ephemerals.single, isFalse);
      expect(recorder.schemes.single, _fakeScheme);
    });

    test('T-16.5-NAVER-WEB-15 WR-05 PII 0: 어느 로그 줄에도 state · code · '
        '콜백 URL 이 없다 (양성 대조군 선행)', () async {
      final logs = captureLogs();
      const codeSentinel = 'CODE-SENTINEL-0ff1ce';
      String? callbackUrl;
      final recorder = AuthenticateRecorder((url) async {
        callbackUrl = await echoCallback(url, code: codeSentinel);
        return callbackUrl!;
      });

      final result = await buildClient(recorder).signIn();
      final state = stateOf(recorder.urls.single);

      // ① 양성 대조군 — 비밀 값이 실제로 흐름에 존재했다 (0건 단언이 공허하게
      // 참이 되는 것을 막는다).
      expect(state, isNotEmpty);
      expect(recorder.urls.single, contains(state));
      expect(result!.code, codeSentinel);
      expect(logs, isNotEmpty, reason: '대조군 — 로그 계층이 살아 있다');
      expect(
        logs.where((line) => line.startsWith('Naver web 도착: outcome=code')),
        hasLength(1),
      );

      // ② 어느 줄에도 원문 없음.
      for (final line in logs) {
        expect(line, isNot(contains(state)));
        expect(line, isNot(contains(codeSentinel)));
        expect(line, isNot(contains(callbackUrl!)));
        expect(line, isNot(contains(_fakeScheme)));
      }
    });

    test('T-16.5-NAVER-WEB-16 진단 로그 순서 · 형식: 시작 → 도착 '
        '(outcome=code|cancel, elapsedMs 정수)', () async {
      final logs = captureLogs();

      await buildClient(AuthenticateRecorder(echoCallback)).signIn();
      expect(logs.first, 'Naver web 시작');
      expect(
        RegExp(r'^Naver web 도착: outcome=code elapsedMs=\d+$').hasMatch(logs[1]),
        isTrue,
        reason: 'elapsedMs 는 값이 흔들리므로 정규식으로 본다',
      );

      logs.clear();
      await buildClient(
        AuthenticateRecorder(
          (url) async => throw PlatformException(code: 'CANCELED'),
        ),
      ).signIn();
      expect(logs.first, 'Naver web 시작');
      expect(
        RegExp(
          r'^Naver web 도착: outcome=cancel elapsedMs=\d+$',
        ).hasMatch(logs[1]),
        isTrue,
      );
    });

    test('T-16.5-NAVER-WEB-17 scheme 형태 상수: 소문자 역도메인 · probe-scheme '
        '매칭 / 밑줄 · 숫자 시작 · 대문자 비매칭', () {
      for (final valid in const <String>[
        'com.slimpumpkin.flutterstarterkit',
        _fakeScheme,
        'a+b.c-d',
      ]) {
        expect(kNaverWebCallbackSchemePattern.hasMatch(valid), isTrue);
      }
      for (final invalid in const <String>[
        'Foo_bar',
        '1abc',
        'exampleScheme',
        '',
      ]) {
        expect(kNaverWebCallbackSchemePattern.hasMatch(invalid), isFalse);
      }
    });
  });
}
