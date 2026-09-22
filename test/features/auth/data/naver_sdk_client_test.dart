// Phase 16.2 — see ROADMAP.md
//
// NaverSdkClient 회귀 테스트 — 플러그인 Future 직결 구조의 성공 · 취소 2분기 ·
// 오류 · 예외 · 로그 리댁션 · PII 차단 · in-flight 가드 · 타이머 부재 가드.
// `16.2-VALIDATION.md` Per-Task 표 — T-16.2-NAVER-SDK-{n}.
import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_test/flutter_test.dart';
import 'package:naver_login_flutter/naver_login_flutter.dart';

import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/features/auth/data/naver_sdk_client.dart';

/// 테스트용 [NaverToken] — [accessToken] 만 통제하고 나머지는 빈 문자열.
NaverToken buildToken(String accessToken) => NaverToken(
  accessToken: accessToken,
  refreshToken: '',
  expiresAt: '',
  tokenType: '',
);

/// 테스트용 [NaverLoginResult] 조립 helper.
NaverLoginResult buildResult({
  required NaverLoginStatus status,
  NaverToken? accessToken,
  String? errorMessage,
}) => NaverLoginResult(
  status: status,
  accessToken: accessToken,
  errorMessage: errorMessage,
);

/// logout fake 가 돌려주는 기본 결과.
NaverLoginResult buildLoggedOutResult() =>
    buildResult(status: NaverLoginStatus.loggedOut);

/// 성공 결과 — [accessToken] 만 채운다.
NaverLoginResult buildSuccessResult(String token) => buildResult(
  status: NaverLoginStatus.loggedIn,
  accessToken: buildToken(token),
);

/// [client] 의 `signIn()` 이 던진 예외를 돌려준다 (throw 없으면 null).
Future<Object?> captureSignInError(NaverSdkClient client) async {
  try {
    await client.signIn();
    return null;
  } on Object catch (e) {
    return e;
  }
}

/// D-21 trap — `account`(프로필) 에 닿는 순간 [StateError] 를 던지는 결과 객체.
class ProfileTrapResult extends Fake implements NaverLoginResult {
  ProfileTrapResult({required this.status, this.accessToken});

  @override
  final NaverLoginStatus status;

  @override
  final NaverToken? accessToken;

  @override
  String? get errorMessage => null;

  @override
  NaverAccountResult? get account =>
      throw StateError('D-21: account(프로필) 참조 금지');
}

/// D-21 trap — `accessToken` 외 멤버 · 문자열화에 닿으면 던지는 토큰 객체.
class TokenTrap extends Fake implements NaverToken {
  TokenTrap(this.accessToken);

  @override
  final String accessToken;

  @override
  String get refreshToken => throw StateError('D-21: refreshToken 참조 금지');

  @override
  String get expiresAt => throw StateError('D-21: expiresAt 참조 금지');

  @override
  String get tokenType => throw StateError('D-21: tokenType 참조 금지');

  @override
  String toString() => throw StateError('D-21: 토큰 객체 문자열화 금지');
}

/// 주석·문서 라인을 제거한 [raw] 를 반환한다
/// (`test/core/config/app_config_test.dart` 의 `stripComments` 선례).
String stripComments(String raw) => raw
    .split('\n')
    .where((line) {
      final trimmed = line.trimLeft();
      return !trimmed.startsWith('//') && !trimmed.startsWith('///');
    })
    .join('\n');

void main() {
  group('NaverSdkClient (T-16.2-NAVER-SDK)', () {
    test(
      'T-16.2-NAVER-SDK-01 success: loggedIn + 토큰 → accessToken 전달',
      () async {
        var loginCalls = 0;
        final client = NaverSdkClient.forTest(
          login: () async {
            loginCalls++;
            return buildSuccessResult('valid_token');
          },
          logout: () async => buildLoggedOutResult(),
        );

        final result = await client.signIn();

        expect(result, isNotNull);
        expect(result!.accessToken, equals('valid_token'));
        expect(loginCalls, equals(1));
      },
    );

    test('T-16.2-NAVER-SDK-02 empty-token: 토큰 null · 빈 문자열 둘 다 null', () async {
      final nullTokenClient = NaverSdkClient.forTest(
        login: () async => buildResult(status: NaverLoginStatus.loggedIn),
        logout: () async => buildLoggedOutResult(),
      );
      expect(await nullTokenClient.signIn(), isNull);

      final emptyTokenClient = NaverSdkClient.forTest(
        login: () async => buildSuccessResult(''),
        logout: () async => buildLoggedOutResult(),
      );
      expect(await emptyTokenClient.signIn(), isNull);
    });

    test(
      'T-16.2-NAVER-SDK-03 cancel-android: loggedOut → null silent',
      () async {
        final client = NaverSdkClient.forTest(
          login: () async => buildResult(status: NaverLoginStatus.loggedOut),
          logout: () async => buildLoggedOutResult(),
        );

        // D-45 — throw 없이 null.
        expect(await client.signIn(), isNull);
      },
    );

    test('T-16.2-NAVER-SDK-04 service-unavailable: error → cause 가 '
        'NaverSdkError', () async {
      final client = NaverSdkClient.forTest(
        login: () async => buildResult(
          status: NaverLoginStatus.error,
          errorMessage: 'some backend failure',
        ),
        logout: () async => buildLoggedOutResult(),
      );

      final captured = await captureSignInError(client);

      expect(captured, isA<ServiceUnavailable>());
      expect((captured! as ServiceUnavailable).cause, isA<NaverSdkError>());
    });

    test('T-16.2-NAVER-SDK-05 missing-plugin: MissingPluginException → '
        'ServiceUnavailable', () async {
      final missingPlugin = MissingPluginException(
        'No implementation found for method logIn',
      );
      final client = NaverSdkClient.forTest(
        login: () async => throw missingPlugin,
        logout: () async => buildLoggedOutResult(),
      );

      final captured = await captureSignInError(client);

      expect(captured, isA<ServiceUnavailable>());
      expect((captured! as ServiceUnavailable).cause, same(missingPlugin));
    });

    test('T-16.2-NAVER-SDK-06 logout: 플러그인 logOut 을 정확히 1회 호출', () async {
      var logoutCalls = 0;
      final client = NaverSdkClient.forTest(
        login: () async => buildLoggedOutResult(),
        logout: () async {
          logoutCalls++;
          return buildLoggedOutResult();
        },
      );

      await client.logout();

      expect(logoutCalls, equals(1));
    });

    test('T-16.2-NAVER-SDK-07 logout graceful: 실패해도 throw 하지 않는다', () async {
      final client = NaverSdkClient.forTest(
        login: () async => buildLoggedOutResult(),
        logout: () async => throw Exception('SDK error'),
      );

      // throw 안 함 검증 — graceful (debugPrint).
      await client.logout();
    });

    // `1c884c73` 회귀 잠금 — iOS 취소는 status error 로 오므로 error 를 곧장
    // 배너로 보내면 취소가 오류로 보인다.
    test('T-16.2-NAVER-SDK-08 cancel-ios: error + 플러그인 고정 리터럴 완전 일치 '
        '→ null silent', () async {
      final client = NaverSdkClient.forTest(
        login: () async => buildResult(
          status: NaverLoginStatus.error,
          // 플러그인 iOS sendError(message:) 고정 리터럴 (RESEARCH §2).
          errorMessage: 'Login cancelled by user',
        ),
        logout: () async => buildLoggedOutResult(),
      );

      expect(await client.signIn(), isNull);
    });

    // D-12 — 부분 문자열 · 휴리스틱으로 취소를 넓히지 않는다. 실제 오류를
    // 조용히 삼키면 사용자가 실패를 알 수 없다.
    test('T-16.2-NAVER-SDK-09 cancel-exact: cancel 을 포함해도 완전 일치가 '
        '아니면 ServiceUnavailable', () async {
      const nonCancelMessages = <String>[
        // iOS SDK 원문 — 플러그인이 감싸기 전의 문자열.
        'User canceled the request.',
        // 네트워크 오류(-999 cancelled) 가 섞여 들어오는 경로.
        'Network error. Detailed error description: '
            'Error Domain=NSURLErrorDomain Code=-999 "cancelled"',
      ];

      for (final message in nonCancelMessages) {
        final client = NaverSdkClient.forTest(
          login: () async => buildResult(
            status: NaverLoginStatus.error,
            errorMessage: message,
          ),
          logout: () async => buildLoggedOutResult(),
        );

        expect(
          await captureSignInError(client),
          isA<ServiceUnavailable>(),
          reason: '부분 문자열 취소 매칭 금지 (D-12): $message',
        );
      }
    });

    // Pitfall 6 — 구 구조의 「무시하고 후속 콜백 대기」 분기를 옮겨오면 Future 가
    // 영원히 미완료가 된다. 종단 실패로 완료되어야 한다.
    test('T-16.2-NAVER-SDK-10 need-app-update: 대기 없이 ServiceUnavailable '
        '로 완료', () async {
      final client = NaverSdkClient.forTest(
        login: () async => buildResult(
          status: NaverLoginStatus.error,
          errorMessage:
              'errorCode:need_app_update, errorDesc:네이버앱 업데이트가 필요합니다.',
        ),
        logout: () async => buildLoggedOutResult(),
      );

      final captured = await captureSignInError(
        client,
      ).timeout(const Duration(seconds: 5));

      expect(captured, isA<ServiceUnavailable>());
    });

    test('T-16.2-NAVER-SDK-11 WR-05 exact: 완전 일치 집합은 이름 + 길이만', () {
      const message = 'Another request is in progress. Please wait';

      expect(
        describeNaverErrorForLog(message),
        equals(
          'message=ios_plugin_request_in_progress '
          'length=${message.length}',
        ),
      );
    });

    test('T-16.2-NAVER-SDK-12 WR-05 prefix: 접두어 매칭이어도 꼬리를 출력하지 '
        '않는다', () {
      const message =
          'Network error. Detailed error description: user@example.com '
          'https://openapi.naver.com/v1/nid/me?token=abc';

      final described = describeNaverErrorForLog(message);

      expect(
        described,
        equals('message=ios_sdk_network_error length=${message.length}'),
      );
      // 음성 단언 — 꼬리의 PII · URL 이 새지 않는다.
      expect(described, isNot(contains('user@example.com')));
      expect(described, isNot(contains('openapi.naver.com')));
      // 양성 단언 — 리댁션이 실제로 동작했다 (빈 출력이 PASS 하지 못하게).
      expect(described, contains('length='));
    });

    test('T-16.2-NAVER-SDK-13 WR-05 android-code: 닫힌 집합 code 만 그대로, '
        '자유 문자열은 비출력', () {
      const known = 'errorCode:server_error, errorDesc:내부 오류 user@example.com';
      expect(
        describeNaverErrorForLog(known),
        equals(
          'message=android_plugin_error_code errorCode=server_error '
          'length=${known.length}',
        ),
      );
      expect(
        describeNaverErrorForLog(known),
        isNot(contains('user@example.com')),
      );

      const unknown = 'errorCode:totally_unknown_code, errorDesc:무엇이든';
      expect(
        describeNaverErrorForLog(unknown),
        equals(
          'message=android_plugin_error_code errorCode=other '
          'length=${unknown.length}',
        ),
      );
    });

    test('T-16.2-NAVER-SDK-14 WR-05 other: 자유 문자열과 null', () {
      const freeText = 'user@example.com 인증 실패';

      expect(
        describeNaverErrorForLog(freeText),
        equals('message=other length=${freeText.length}'),
      );
      expect(describeNaverErrorForLog(null), equals('message=null length=0'));
    });

    test('T-16.2-NAVER-SDK-15 WR-05 toString: NaverSdkError 도 같은 리댁션을 '
        '거친다', () {
      const error = NaverSdkError('user@example.com 인증 실패');

      final described = error.toString();

      expect(described, isNot(contains('user@example.com')));
      expect(described, contains('message=other'));
    });

    test('T-16.2-NAVER-SDK-16 pii: 프로필 · refresh token · 객체 문자열화에 '
        '닿지 않는다', () async {
      final client = NaverSdkClient.forTest(
        login: () async => ProfileTrapResult(
          status: NaverLoginStatus.loggedIn,
          accessToken: TokenTrap('trap_access_token'),
        ),
        logout: () async => buildLoggedOutResult(),
      );

      final result = await client.signIn();

      expect(result, isNotNull);
      expect(result!.accessToken, equals('trap_access_token'));
    });

    test('T-16.2-NAVER-SDK-17 in-flight: 재진입은 plugin 을 호출하지 않고 '
        'null', () async {
      final gate = Completer<NaverLoginResult>();
      var loginCalls = 0;
      final client = NaverSdkClient.forTest(
        login: () {
          loginCalls++;
          return gate.future;
        },
        logout: () async => buildLoggedOutResult(),
      );

      final first = client.signIn();
      // 첫 호출이 미완료인 동안의 재진입.
      expect(await client.signIn(), isNull);
      expect(loginCalls, equals(1));

      gate.complete(buildSuccessResult('late_token'));
      final firstResult = await first;

      expect(firstResult, isNotNull);
      expect(firstResult!.accessToken, equals('late_token'));
      expect(loginCalls, equals(1));
    });

    test('T-16.2-NAVER-SDK-18 in-flight reset: 성공 · 취소 · error · 예외 '
        '뒤에 다음 호출이 plugin 에 도달한다', () async {
      final outcomes = <String, Future<NaverLoginResult> Function()>{
        '성공': () async => buildSuccessResult('t'),
        '취소': () async => buildResult(status: NaverLoginStatus.loggedOut),
        'error': () async =>
            buildResult(status: NaverLoginStatus.error, errorMessage: 'boom'),
        '예외': () async => throw Exception('boom'),
      };

      for (final entry in outcomes.entries) {
        var loginCalls = 0;
        final client = NaverSdkClient.forTest(
          login: () {
            loginCalls++;
            return entry.value();
          },
          logout: () async => buildLoggedOutResult(),
        );

        await captureSignInError(client);
        expect(loginCalls, equals(1), reason: '선행 호출 (${entry.key})');

        await captureSignInError(client);
        expect(loginCalls, equals(2), reason: '${entry.key} 뒤에 가드가 해제돼야 한다');
      }
    });

    test('T-16.2-NAVER-SDK-19 in-flight logout: 진행 중에는 plugin logOut 을 '
        '호출하지 않는다', () async {
      final gate = Completer<NaverLoginResult>();
      var logoutCalls = 0;
      final client = NaverSdkClient.forTest(
        login: () => gate.future,
        logout: () async {
          logoutCalls++;
          return buildLoggedOutResult();
        },
      );

      final first = client.signIn();
      await client.logout();
      expect(logoutCalls, equals(0));

      gate.complete(buildSuccessResult('token'));
      await first;

      // WR-01: 진행 중 요청은 「생략」 이 아니라 「지연」 이므로 가드 해제
      // 직후 1회 소비된다 (T-16.2-NAVER-SDK-22 가 이 계약을 단독으로 잠근다).
      expect(logoutCalls, equals(1));

      await client.logout();
      expect(logoutCalls, equals(2));
    });

    // D-16 — 앱 쪽 타이머가 되살아나면 늦게 끝난 성공이 버려진다.
    test('T-16.2-NAVER-SDK-20 no-timeout: 가상 시간 10분 뒤 완료도 결과 보존', () {
      fakeAsync((async) {
        final gate = Completer<NaverLoginResult>();
        final client = NaverSdkClient.forTest(
          login: () => gate.future,
          logout: () async => buildLoggedOutResult(),
        );

        NaverSignInResult? captured;
        var completed = false;
        unawaited(
          client.signIn().then((value) {
            captured = value;
            completed = true;
          }),
        );
        async.flushMicrotasks();

        async.elapse(const Duration(minutes: 10));
        async.flushMicrotasks();
        expect(completed, isFalse, reason: '타이머가 있으면 이미 완료됐을 것이다');

        gate.complete(buildSuccessResult('slow_token'));
        async.flushMicrotasks();

        expect(completed, isTrue);
        expect(captured, isNotNull);
        expect(captured!.accessToken, equals('slow_token'));
      });
    });

    test('T-16.2-NAVER-SDK-21 source-contract: 타이머 · revoke · 로그 스위치 · '
        '프로필 접근이 소스에 없다', () {
      final source = File(
        'lib/features/auth/data/naver_sdk_client.dart',
      ).readAsStringSync();
      final code = stripComments(source);

      // 양성 단언 — 주석 제거 후에도 실제 구현이 남아 있다 (빈 문자열 PASS 방지).
      expect(code, contains('FlutterNaverLogin.logIn()'));
      expect(code, contains('FlutterNaverLogin.logOut()'));

      for (final forbidden in const <String>[
        'Completer',
        '.timeout(',
        'logOutAndDeleteToken',
        'setLogEnabled',
        '.account',
      ]) {
        expect(
          code,
          isNot(contains(forbidden)),
          reason: 'production 소스에 $forbidden 가 있으면 안 된다',
        );
      }
    });

    // WR-01 — 진행 중 logout 을 버리면 `signOut` · 재인증 finally 경로에서
    // D-57 (매 로그인 finally 로 기기 토큰 제거) 이 소리 없이 깨진다.
    test('T-16.2-NAVER-SDK-22 WR-01 in-flight logout 지연: 진행 중 요청이 '
        '버려지지 않고 signIn 완료 뒤 1회 소비된다', () async {
      final gate = Completer<NaverLoginResult>();
      final calls = <String>[];
      final client = NaverSdkClient.forTest(
        login: () {
          calls.add('login');
          return gate.future;
        },
        logout: () async {
          calls.add('logout');
          return buildLoggedOutResult();
        },
      );

      final first = client.signIn();
      // `signOut` · 재인증 finally 가 진행 중에 들어온 상황 — 2회 요청도
      // 1회로 접힌다 (기기 토큰 제거는 멱등).
      await client.logout();
      await client.logout();
      expect(
        calls,
        equals(<String>['login']),
        reason: '진행 중에는 plugin logOut 을 호출하지 않는다',
      );

      gate.complete(buildSuccessResult('token'));
      final result = await first;

      expect(
        calls,
        equals(<String>['login', 'logout']),
        reason: 'D-57: 생략이 아니라 지연 — 완료 직후 실제로 1회 호출된다',
      );
      expect(result, isNotNull);
      expect(result!.accessToken, equals('token'));
    });

    test('T-16.2-NAVER-SDK-23 WR-01 지연 소비 실패는 signIn 의 결과를 바꾸지 '
        '않는다 (logout graceful 계약)', () async {
      final gate = Completer<NaverLoginResult>();
      var logoutCalls = 0;
      final client = NaverSdkClient.forTest(
        login: () => gate.future,
        logout: () async {
          logoutCalls++;
          throw Exception('logout boom');
        },
      );

      final captured = captureSignInError(client);
      await client.logout();
      gate.complete(
        buildResult(status: NaverLoginStatus.error, errorMessage: 'boom'),
      );

      final error = await captured;

      expect(error, isA<ServiceUnavailable>());
      expect(logoutCalls, equals(1), reason: '지연 소비는 실행된다');
    });

    // WR-09 — 지연 logout 을 소비하는 **동안에도** in-flight 가드가 유지돼야
    // 클래스 doc 의 「킷이 만들어내는 동시 plugin 호출이 0」 보장이 성립한다.
    // 가드를 먼저 내리고 소비하면 그 await 구간에서 재진입 signIn 이 가드를
    // 통과해 plugin logIn 을 때린다 (= 킷이 스스로 동시 호출을 만든다).
    test('T-16.2-NAVER-SDK-24 WR-09 지연 소비 중에도 in-flight 가드가 '
        '유지된다', () async {
      final loginGate = Completer<NaverLoginResult>();
      final logoutGate = Completer<NaverLoginResult>();
      var loginCalls = 0;
      var logoutCalls = 0;
      final client = NaverSdkClient.forTest(
        login: () {
          loginCalls++;
          return loginGate.future;
        },
        logout: () {
          logoutCalls++;
          return logoutGate.future;
        },
      );

      final first = client.signIn();
      await client.logout();
      expect(logoutCalls, equals(0), reason: '진행 중에는 지연된다');

      loginGate.complete(buildSuccessResult('token'));
      await pumpEventQueue();

      // 여기서 지연 소비가 **시작됐고** plugin logOut 은 아직 미완료다.
      expect(logoutCalls, equals(1), reason: '대조군 — 소비가 실제로 시작됐다');
      expect(
        await client.signIn(),
        isNull,
        reason: 'WR-09: 소비 중 재진입은 plugin 을 호출하지 않는다',
      );
      expect(loginCalls, equals(1), reason: 'WR-09: 킷이 만드는 동시 plugin 호출 0');

      logoutGate.complete(buildLoggedOutResult());
      final result = await first;

      expect(result, isNotNull);
      expect(result!.accessToken, equals('token'));

      // 대조군 — 배수가 끝나면 가드는 실제로 풀린다 (영구 잠김이 아니다).
      await client.signIn();
      expect(loginCalls, equals(2), reason: '배수 완료 뒤에는 가드가 풀린다');
    });

    // WR-11 — 플러그인은 logout 실패를 예외가 아니라 **결과 객체**
    // (status: error + errorMessage) 로 돌려준다. status 를 읽지 않으면 거부된
    // logout 도 「완료」 로 기록돼 `16.2-HUMAN-UAT.md` 5번 줄을 근거로 쓰는
    // D-57 판정이 위양성이 된다 (iOS busy 경로가 실재한다).
    test('T-16.2-NAVER-SDK-25 WR-11 logout 결과 status 판정: loggedOut 만 '
        '「완료」 로 기록한다', () async {
      final logs = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      addTearDown(() => debugPrint = originalDebugPrint);

      const successLine = 'NaverSdkClient.logout 완료';

      // 생존 대조군 — 성공 경로에서는 그 문자열이 실제로 나온다. 아래 부재
      // 단언이 「아무 로그도 안 나와서」 PASS 하는 위음성을 막는다.
      final okClient = NaverSdkClient.forTest(
        login: () async => buildLoggedOutResult(),
        logout: () async => buildLoggedOutResult(),
      );
      await okClient.logout();
      expect(logs, contains(successLine), reason: '대조군 — 성공은 「완료」 로 남는다');

      // iOS 가 busy 일 때 plugin 이 돌려주는 실제 거부 결과
      // (`FlutterNaverLoginPlugin.swift:122-126`).
      logs.clear();
      final busyClient = NaverSdkClient.forTest(
        login: () async => buildLoggedOutResult(),
        logout: () async => buildResult(
          status: NaverLoginStatus.error,
          errorMessage: 'Another request is in progress. Please wait',
        ),
      );
      await busyClient.logout();

      expect(
        logs,
        isNot(contains(successLine)),
        reason: 'WR-11: 거부된 logout 을 성공으로 기록하면 UAT 증거가 위양성이 된다',
      );
      expect(
        logs.single,
        allOf(
          contains('NaverSdkClient.logout 실패 (무시)'),
          contains('status=error'),
          contains('message=ios_plugin_request_in_progress'),
        ),
      );

      // 자유 문자열 errorMessage 도 리댁션을 거친다 — 원문은 한 글자도
      // 출력하지 않는다 (D-14 / WR-05).
      logs.clear();
      final piiClient = NaverSdkClient.forTest(
        login: () async => buildLoggedOutResult(),
        logout: () async => buildResult(
          status: NaverLoginStatus.error,
          errorMessage: 'user@example.com 토큰 삭제 실패',
        ),
      );
      await piiClient.logout();

      expect(logs.single, isNot(contains('user@example.com')));
      expect(logs.single, contains('message=other'));
    });
  });

  // Phase 16.4 D-18 — 「대기 구간에 앱 로그가 전무」(16.2 UAT A2 / WR-02(b)) 를
  // 없애는 시작 · 도착 2줄. 접두어는 plan 02~06 의 logcat 단언이 쓰는 grep
  // 앵커이므로 문구를 바꾸면 그쪽 단언도 함께 바꿔야 한다.
  group('Phase 16.4 D-18 진단 로그 (T-16.4-NAVER-LOG)', () {
    test('T-16.4-NAVER-LOG-01 순서 · 3 status: 시작 줄 뒤에 도착 줄이 오고 '
        'loggedIn · loggedOut · error 가 각각 기록된다', () async {
      final logs = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      addTearDown(() => debugPrint = originalDebugPrint);

      // enum name 은 하드코딩하지 않는다 — 플러그인이 이름을 바꾸면 이 테스트가
      // 스스로 알려줘야 한다.
      final cases = <NaverLoginStatus, NaverLoginResult>{
        NaverLoginStatus.loggedIn: buildSuccessResult('valid_token'),
        NaverLoginStatus.loggedOut: buildLoggedOutResult(),
        NaverLoginStatus.error: buildResult(
          status: NaverLoginStatus.error,
          errorMessage: 'errorCode:no_app_for_authentication, errorDesc:x',
        ),
      };

      for (final entry in cases.entries) {
        logs.clear();
        final client = NaverSdkClient.forTest(
          login: () async => entry.value,
          logout: () async => buildLoggedOutResult(),
        );
        await captureSignInError(client);

        final startIndex = logs.indexWhere(
          (line) => line.startsWith('Naver logIn 시작'),
        );
        final arrivalIndex = logs.indexWhere(
          (line) => line.startsWith('Naver logIn 도착:'),
        );

        expect(
          startIndex,
          isNonNegative,
          reason: '${entry.key.name}: 시작 줄이 있어야 대기 구간이 보인다',
        );
        expect(
          arrivalIndex,
          greaterThan(startIndex),
          reason: '${entry.key.name}: 도착 줄은 시작 줄 뒤에 와야 한다',
        );
        expect(
          logs[arrivalIndex],
          contains('status=${entry.key.name}'),
          reason: '${entry.key.name}: 도착 줄이 status 를 실어야 분기를 가를 수 있다',
        );
      }
    });

    test('T-16.4-NAVER-LOG-02 WR-05: 도착 줄에 SDK errorMessage 원문이 '
        '한 글자도 없다 (양성 대조군 선행)', () async {
      final logs = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      addTearDown(() => debugPrint = originalDebugPrint);

      // 자유 문자열 errorMessage — 실제 SDK 는 요청 URL 을 그대로 싣는다.
      const sentinel = 'RAW-SENTINEL-0ff1ce';
      const rawMessage = 'https://nid.naver.com/?q=$sentinel';

      final client = NaverSdkClient.forTest(
        login: () async => buildResult(
          status: NaverLoginStatus.error,
          errorMessage: rawMessage,
        ),
        logout: () async => buildLoggedOutResult(),
      );

      final error = await captureSignInError(client);
      expect(
        error,
        isA<ServiceUnavailable>(),
        reason: '기존 계약 — error status 는 ServiceUnavailable 로 매핑된다',
      );

      final arrivalLines = logs
          .where((line) => line.startsWith('Naver logIn 도착:'))
          .toList();

      // ① 생존 대조군 먼저 — 0줄이면 아래 부재 단언이 자동 참이 되어 「로그가
      // 통째로 사라진 회귀」 를 놓친다.
      expect(
        arrivalLines.length,
        greaterThanOrEqualTo(1),
        reason: '대조군 — 도착 줄이 실제로 찍혔다',
      );

      // ② 도착 줄에 원문 없음
      for (final line in arrivalLines) {
        expect(
          line,
          isNot(contains(sentinel)),
          reason: 'WR-05: 도착 줄은 status · elapsedMs 만 싣는다',
        );
      }

      // ③ 캡처된 모든 줄에 원문 없음 — 기존 error 줄도 describeNaverErrorForLog
      // 로 `message=other length=<n>` 만 찍는다는 계약의 재확인.
      for (final line in logs) {
        expect(
          line,
          isNot(contains(sentinel)),
          reason: 'WR-05: 어느 줄에도 SDK 원문이 새면 안 된다',
        );
      }
    });

    test('T-16.4-NAVER-LOG-03 elapsedMs 정규식 매칭 + 재진입은 시작 줄을 '
        '추가로 찍지 않는다', () async {
      final logs = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      addTearDown(() => debugPrint = originalDebugPrint);

      final gate = Completer<NaverLoginResult>();
      final client = NaverSdkClient.forTest(
        login: () => gate.future,
        logout: () async => buildLoggedOutResult(),
      );

      final first = client.signIn();
      await pumpEventQueue();

      int startLineCount() =>
          logs.where((line) => line.startsWith('Naver logIn 시작')).length;

      expect(startLineCount(), equals(1), reason: '대조군 — 첫 호출이 시작 줄을 찍었다');

      expect(
        await client.signIn(),
        isNull,
        reason: '기존 계약 — in-flight 재진입은 plugin 을 호출하지 않는다',
      );
      expect(
        logs,
        contains('Naver logIn 재진입 무시 (in-flight)'),
        reason: '재진입은 기존 가드 줄로만 보인다',
      );
      expect(
        startLineCount(),
        equals(1),
        reason: '재진입이 시작 줄을 추가로 찍으면 logcat 의 왕복 계수가 틀어진다',
      );

      gate.complete(buildSuccessResult('token'));
      await first;

      final arrival = logs.firstWhere(
        (line) => line.startsWith('Naver logIn 도착:'),
      );
      expect(
        RegExp(r'elapsedMs=\d+$').hasMatch(arrival),
        isTrue,
        reason: '경과 ms 는 값이 흔들리므로 정규식으로 본다 (하드코딩 금지)',
      );
    });
  });

  // Phase 16.4 D-19 — 재개방이 일어난 `loggedOut` 은 사용자 취소가 아니라
  // 실패다. 구분 신호는 Dart 밖(Android 호스트 Activity 생성 계수)에서 오며,
  // 레버 선택 근거는 `16.4-AB-RESULT.md` 의 `LEVER5_SIGNAL: ABSENT` 다.
  group('Phase 16.4 D-19 재개방 구분 (T-16.4-NAVER-DISCRIM)', () {
    /// [debugPrint] 를 가로채 [logs] 에 쌓는다 (16.2 선례와 동형).
    void captureLogs(List<String> logs) {
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      addTearDown(() => debugPrint = originalDebugPrint);
    }

    /// [prefix] 로 시작하는 줄만 고른다.
    List<String> linesStartingWith(List<String> logs, String prefix) =>
        logs.where((line) => line.startsWith(prefix)).toList();

    test('T-16.4-NAVER-DISCRIM-01 재개방(createCount=2) 은 취소가 아니라 '
        'ServiceUnavailable(cause: NaverCustomTabReopened) 로 승격된다', () async {
      final logs = <String>[];
      captureLogs(logs);

      // IN-01: 임계는 리터럴이 아니라 명명 상수를 참조한다 — plan 04 실측으로
      // 임계가 바뀌면 이 테스트가 따라 움직여야 한다.
      final client = NaverSdkClient.forTest(
        login: () async => buildLoggedOutResult(),
        logout: () async => buildLoggedOutResult(),
        customTabCount: () async => kNaverCustomTabReopenThreshold,
      );

      final error = await captureSignInError(client);

      expect(
        error,
        isA<ServiceUnavailable>(),
        reason: 'D-19: 재개방은 기존 errorServiceUnavailable 배너 경로를 타야 한다',
      );
      final cause = (error! as ServiceUnavailable).cause;
      expect(cause, isA<NaverCustomTabReopened>());
      expect(
        (cause! as NaverCustomTabReopened).count,
        equals(kNaverCustomTabReopenThreshold),
      );
      expect(
        cause.toString(),
        equals('NaverCustomTabReopened(count=$kNaverCustomTabReopenThreshold)'),
        reason: 'WR-05: cause 가 문자열화돼도 정수만 나간다',
      );

      // 도착 줄은 그대로 1줄 (대조군 — 로그 계층이 살아 있다).
      expect(linesStartingWith(logs, 'Naver logIn 도착:').length, equals(1));
      expect(
        linesStartingWith(logs, 'Naver logIn 재개방 감지: '),
        equals(<String>[
          'Naver logIn 재개방 감지: '
              'createCount=$kNaverCustomTabReopenThreshold',
        ]),
        reason: 'C-01: 구분 신호 로그는 정수만 담고 정확히 1줄이다',
      );
      expect(
        linesStartingWith(logs, 'Naver logIn cancel:'),
        isEmpty,
        reason: '재개방은 취소가 아니므로 cancel 줄을 찍으면 안 된다',
      );
    });

    test('T-16.4-NAVER-DISCRIM-02 정상 취소(1회)는 종전대로 silent null 이고 '
        '성공 결과는 카운트와 무관하게 성공이다 (D-45 · 회귀 0)', () async {
      final logs = <String>[];
      captureLogs(logs);

      // ① 임계 미만(= 1회 생성) 은 진짜 취소 → silent null.
      final cancelClient = NaverSdkClient.forTest(
        login: () async => buildLoggedOutResult(),
        logout: () async => buildLoggedOutResult(),
        customTabCount: () async => kNaverCustomTabReopenThreshold - 1,
      );
      expect(await cancelClient.signIn(), isNull);
      expect(linesStartingWith(logs, 'Naver logIn cancel:').length, equals(1));
      expect(linesStartingWith(logs, 'Naver logIn 재개방 감지: '), isEmpty);

      // ② 재개방 카운트가 있어도 성공은 절대 실패로 바뀌지 않는다.
      logs.clear();
      final successClient = NaverSdkClient.forTest(
        login: () async => buildSuccessResult('token'),
        logout: () async => buildLoggedOutResult(),
        customTabCount: () async => kNaverCustomTabReopenThreshold,
      );
      final result = await successClient.signIn();
      expect(result, isNotNull);
      expect(result!.accessToken, equals('token'));
      expect(
        linesStartingWith(logs, 'Naver logIn 재개방 감지: '),
        isEmpty,
        reason: 'D-45: 성공 분기는 카운트를 보지 않는다',
      );

      // ③ 기존 21+ 호출처 모양 (login · logout 만) 도 그대로 컴파일 · 동작한다.
      logs.clear();
      final legacyClient = NaverSdkClient.forTest(
        login: () async => buildLoggedOutResult(),
        logout: () async => buildLoggedOutResult(),
      );
      expect(
        await legacyClient.signIn(),
        isNull,
        reason: '새 인자는 optional — 기본값 0 이라 재개방 분기가 발동하지 않는다',
      );
      expect(linesStartingWith(logs, 'Naver logIn 재개방 감지: '), isEmpty);
    });

    test('T-16.4-NAVER-DISCRIM-03 호출 순서는 reset → login → count 다 '
        '(직전 시도의 계수가 남으면 오판이 난다)', () async {
      final order = <String>[];

      final client = NaverSdkClient.forTest(
        login: () async {
          order.add('login');
          return buildLoggedOutResult();
        },
        logout: () async => buildLoggedOutResult(),
        customTabReset: () async => order.add('reset'),
        customTabCount: () async {
          order.add('count');
          return 1;
        },
      );

      await client.signIn();

      expect(order, equals(<String>['reset', 'login', 'count']));
    });
  });
}
