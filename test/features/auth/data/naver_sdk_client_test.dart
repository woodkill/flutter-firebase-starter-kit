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
}
