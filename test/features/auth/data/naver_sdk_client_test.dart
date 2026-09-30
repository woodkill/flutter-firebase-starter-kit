// Phase 16.2 — see ROADMAP.md
//
// NaverSdkClient 회귀 테스트 — 플러그인 Future 직결 구조의 성공 · 취소 2분기 ·
// 오류 · 예외 · 로그 리댁션 · PII 차단 · in-flight 가드 · 타이머 부재 가드.
// `16.2-VALIDATION.md` Per-Task 표 — T-16.2-NAVER-SDK-{n}.
//
// Phase 16.11 — iOS 1-tap 취소 표면(A1 · SYSC) · stale 슬롯 재시도 · logout
// 라운드트립 대기(U5) — T-16.11-NAVER-ABANDON-{n}. iOS 게이트 테스트는
// `debugDefaultTargetPlatformOverride` 를 쓰고 tearDown 에서 `null` 로 되돌린다
// (flutter_test 기본값은 android — RESEARCH Pitfall 3).
import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart'
    show
        TargetPlatform,
        VoidCallback,
        debugDefaultTargetPlatformOverride,
        debugPrint;
import 'package:flutter/services.dart'
    show MethodCall, MethodChannel, MissingPluginException, PlatformException;
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:naver_login_flutter/naver_login_flutter.dart';

import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/features/auth/data/naver_host_channel.dart';
import 'package:flutter_starter_kit/features/auth/data/naver_sdk_client.dart';
import 'package:flutter_starter_kit/features/auth/data/naver_sign_in_result.dart';
import 'package:flutter_starter_kit/features/auth/data/naver_web_auth_client.dart';

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

/// 16.11 포기 판정 테스트용 lifecycle 구독 fake.
///
/// `NaverSdkClient.forTest(lifecycleSubscribe:)` 에 [subscribe] 를 넘기고
/// [emitPause] · [emitResume] 으로 background 진입 · 복귀를 밀어 넣는다. 해제된
/// 구독은 더 이상 콜백을 받지 않는다.
class FakeLifecycle {
  final Map<int, (VoidCallback, VoidCallback)> _active =
      <int, (VoidCallback, VoidCallback)>{};
  int _nextId = 0;

  /// [subscribe] 호출 횟수.
  int subscribeCalls = 0;

  /// 해제 함수 호출 횟수.
  int disposeCalls = 0;

  /// `NaverLifecycleSubscribeFn` 구현 — 콜백을 붙들고 해제 함수를 돌려준다.
  void Function() subscribe({
    required VoidCallback onPause,
    required VoidCallback onResume,
  }) {
    subscribeCalls++;
    final id = _nextId++;
    _active[id] = (onPause, onResume);
    return () {
      disposeCalls++;
      _active.remove(id);
    };
  }

  /// 활성 구독 전부에 background 진입(`paused`) 을 알린다.
  void emitPause() {
    for (final (onPause, _) in List.of(_active.values)) {
      onPause();
    }
  }

  /// 활성 구독 전부에 복귀(`resumed`) 를 알린다.
  void emitResume() {
    for (final (_, onResume) in List.of(_active.values)) {
      onResume();
    }
  }
}

/// 16.11 네이티브 콜백 도착 기록 fake — 조회 · 초기화 횟수를 센다.
class CallbackRecordProbe {
  /// [arrived] 는 조회가 돌려줄 값이다.
  CallbackRecordProbe({this.arrived = false});

  /// 조회가 돌려줄 값 — `true` 면 콜백 URL 이 도착한 것으로 본다.
  bool arrived;

  /// [query] 호출 횟수.
  int queries = 0;

  /// [reset] 호출 횟수.
  int resets = 0;

  /// `NaverCallbackArrivedFn` 구현.
  Future<bool> query() async {
    queries++;
    return arrived;
  }

  /// `NaverCallbackResetFn` 구현.
  Future<void> reset() async {
    resets++;
  }
}

/// `fakeAsync` 안에서 `signIn()` 을 시작하고 완료 · 결과 · 오류를 기록한다.
class SignInProbe {
  /// [client] 의 `signIn()` 을 곧바로 시작한다.
  SignInProbe(NaverSdkClient client) {
    unawaited(
      client.signIn().then(
        (value) {
          result = value;
          completed = true;
        },
        onError: (Object e) {
          error = e;
          completed = true;
        },
      ),
    );
  }

  /// `signIn()` 이 끝났는지 (값 · 예외 모두).
  bool completed = false;

  /// `signIn()` 의 결과.
  NaverSignInResult? result;

  /// `signIn()` 이 던진 예외.
  Object? error;
}

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
        expect(
          result,
          isA<NaverAppSignIn>().having(
            (r) => r.accessToken,
            'accessToken',
            'valid_token',
          ),
        );
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
      expect(
        result,
        isA<NaverAppSignIn>().having(
          (r) => r.accessToken,
          'accessToken',
          'trap_access_token',
        ),
      );
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
      expect(
        firstResult,
        isA<NaverAppSignIn>().having(
          (r) => r.accessToken,
          'accessToken',
          'late_token',
        ),
      );
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
        expect(
          captured,
          isA<NaverAppSignIn>().having(
            (r) => r.accessToken,
            'accessToken',
            'slow_token',
          ),
        );
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
        'Completer<NaverLoginResult>',
        'Completer<NaverSignInResult',
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

      // 정밀화 — 포기 신호용 `Completer<void>` 1건만 허용한다.
      const completerReason =
          '16.11 D-01 — 포기 신호용 Completer<void> 1건만 허용 · 로그인 결과를 '
          '감싸는 Completer · timeout 금지(16.2 D-16)';
      expect(
        'Completer<'.allMatches(code),
        hasLength(1),
        reason: completerReason,
      );
      expect(code, contains('Completer<void>('), reason: completerReason);
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
      expect(
        result,
        isA<NaverAppSignIn>().having(
          (r) => r.accessToken,
          'accessToken',
          'token',
        ),
      );
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
      expect(
        result,
        isA<NaverAppSignIn>().having(
          (r) => r.accessToken,
          'accessToken',
          'token',
        ),
      );

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

      // WR-05: happy path 도 로그를 찍는다 (도착 줄은 loggedIn 에서도 나간다).
      // 성공 결과에 sentinel 토큰을 심어 **성공 분기에서도** access token 이 한
      // 글자도 새지 않음을 단언한다 — TokenTrap 은 토큰 **객체**의 문자열화만
      // 막고, `result.accessToken?.accessToken` 평문 String 보간은 잡지 못한다.
      const tokenSentinel = 'TOKEN-SENTINEL-0ff1ce';

      // enum name 은 하드코딩하지 않는다 — 플러그인이 이름을 바꾸면 이 테스트가
      // 스스로 알려줘야 한다.
      final cases = <NaverLoginStatus, NaverLoginResult>{
        NaverLoginStatus.loggedIn: buildSuccessResult(tokenSentinel),
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

        // WR-05 ① 생존 대조군 — 0줄이면 아래 부재 단언이 자동 참이 되어
        // 「redaction 매칭 0줄 = 평문 승격」 을 놓친다.
        expect(
          logs,
          isNotEmpty,
          reason: '${entry.key.name}: 대조군 — 로그 계층이 살아 있다',
        );
        // WR-05 ② happy path 를 포함해 어느 줄에도 access token 이 없다.
        for (final line in logs) {
          expect(
            line,
            isNot(contains(tokenSentinel)),
            reason:
                '${entry.key.name}: 성공 분기에서도 access token 은 '
                '한 글자도 새면 안 된다',
          );
        }
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

  // Phase 16.5 D-01 ~ D-04 — 설치 판정 bool 하나로 1-tap(SDK) 과 킷 웹 흐름을
  // 가른다. 1-tap 경로에서는 웹 흐름이 호출되지 않고, 판정 실패는 웹으로 접힌다.
  group('Phase 16.5 경로 라우팅 (T-16.5-NAVER-ROUTE)', () {
    const webResult = NaverWebSignIn(code: 'FAKE_CODE', state: 'FAKE_STATE');

    test('T-16.5-NAVER-ROUTE-01 설치 → login 1 · web 0 · NaverAppSignIn + '
        '경로 선택 줄 mode=app', () async {
      final logs = captureLogs();
      var loginCalls = 0;
      var webCalls = 0;
      final client = NaverSdkClient.forTest(
        login: () async {
          loginCalls++;
          return buildSuccessResult('app_token');
        },
        logout: () async => buildLoggedOutResult(),
        isNaverAppInstalled: () async => true,
        webSignIn: () async {
          webCalls++;
          return webResult;
        },
      );

      final result = await client.signIn();

      expect(
        result,
        isA<NaverAppSignIn>().having(
          (r) => r.accessToken,
          'accessToken',
          'app_token',
        ),
      );
      expect(loginCalls, 1);
      expect(webCalls, 0, reason: '1-tap 경로는 웹 흐름에 닿지 않는다 (SC2)');
      expect(logs, contains('Naver 경로 선택: mode=app installed=true'));
      expect(logs, contains('Naver logIn 시작'), reason: '앱 앵커 보존');
    });

    test('T-16.5-NAVER-ROUTE-02 미설치 → login 0 · web 1 · NaverWebSignIn + '
        '경로 선택 줄 mode=web · 앱 앵커 0', () async {
      final logs = captureLogs();
      var loginCalls = 0;
      var webCalls = 0;
      final client = NaverSdkClient.forTest(
        login: () async {
          loginCalls++;
          return buildSuccessResult('app_token');
        },
        logout: () async => buildLoggedOutResult(),
        isNaverAppInstalled: () async => false,
        webSignIn: () async {
          webCalls++;
          return webResult;
        },
      );

      final result = await client.signIn();

      expect(result, same(webResult));
      expect(loginCalls, 0, reason: '미설치 단말에서 SDK 커스텀탭을 열지 않는다');
      expect(webCalls, 1);
      expect(logs, contains('Naver 경로 선택: mode=web installed=false'));
      expect(
        logs.where((line) => line.startsWith('Naver logIn 시작')),
        isEmpty,
        reason: '웹 경로는 SDK 앵커를 찍지 않는다 (logcat 계수 분리)',
      );
    });

    test('T-16.5-NAVER-ROUTE-03 판정 예외 → 웹으로 접는다 (D-02)', () async {
      final logs = captureLogs();
      var webCalls = 0;
      final client = NaverSdkClient.forTest(
        login: () async => throw StateError('login 호출 금지'),
        logout: () async => buildLoggedOutResult(),
        isNaverAppInstalled: () async =>
            throw PlatformException(code: 'boom', message: 'HOST-SENTINEL'),
        webSignIn: () async {
          webCalls++;
          return webResult;
        },
      );

      expect(await client.signIn(), same(webResult));
      expect(webCalls, 1);
      expect(logs, contains('Naver 설치 판정 예외(web 으로 접음): PlatformException'));
      expect(logs, contains('Naver 경로 선택: mode=web installed=false'));
      for (final line in logs) {
        expect(line, isNot(contains('HOST-SENTINEL')));
      }
    });

    test('T-16.5-NAVER-ROUTE-04 웹 실패 매핑: ServiceUnavailable 그대로 · '
        'PlatformException → ServiceUnavailable(cause) · 취소 null', () async {
      const direct = ServiceUnavailable();
      final directClient = NaverSdkClient.forTest(
        login: () async => buildSuccessResult('unused'),
        logout: () async => buildLoggedOutResult(),
        isNaverAppInstalled: () async => false,
        webSignIn: () async => throw direct,
      );
      expect(await captureSignInError(directClient), same(direct));

      final platformError = PlatformException(code: 'FAILED');
      final platformClient = NaverSdkClient.forTest(
        login: () async => buildSuccessResult('unused'),
        logout: () async => buildLoggedOutResult(),
        isNaverAppInstalled: () async => false,
        webSignIn: () async => throw platformError,
      );
      expect(
        await captureSignInError(platformClient),
        isA<ServiceUnavailable>().having(
          (e) => e.cause,
          'cause',
          same(platformError),
        ),
      );

      final cancelClient = NaverSdkClient.forTest(
        login: () async => buildSuccessResult('unused'),
        logout: () async => buildLoggedOutResult(),
        isNaverAppInstalled: () async => false,
        webSignIn: () async => null,
      );
      expect(await cancelClient.signIn(), isNull);
    });

    test('T-16.5-NAVER-ROUTE-05 웹 경로도 in-flight 가드 · 지연 logout 배수를 '
        '공유한다', () async {
      final gate = Completer<NaverWebSignIn?>();
      var webCalls = 0;
      var logoutCalls = 0;
      final client = NaverSdkClient.forTest(
        login: () async => buildSuccessResult('unused'),
        logout: () async {
          logoutCalls++;
          return buildLoggedOutResult();
        },
        isNaverAppInstalled: () async => false,
        webSignIn: () {
          webCalls++;
          return gate.future;
        },
      );

      final first = client.signIn();
      await pumpEventQueue();
      expect(await client.signIn(), isNull, reason: '재진입은 세션을 새로 열지 않는다');
      await client.logout();
      expect(logoutCalls, 0, reason: '진행 중 logout 은 지연된다');

      gate.complete(webResult);
      expect(await first, same(webResult));
      expect(webCalls, 1);
      expect(logoutCalls, 1, reason: '지연 logout 은 가드 해제 전 1회 소비');
    });

    test('T-16.5-NAVER-ROUTE-06 prod 배선: 호스트 채널 false → '
        'NaverWebAuthClient 세션 호출 · mode=web 줄', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel(kNaverHostChannelName);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final hostCalls = <String>[];
      messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
        hostCalls.add(call.method);
        return false;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final logs = captureLogs();

      final sessionUrls = <String>[];
      final webClient = NaverWebAuthClient.forTest(
        clientId: 'fake-client-id',
        callbackUrlScheme: 'probe-scheme',
        redirectUri: 'probe-scheme://authorize',
        authenticate:
            ({
              required String url,
              required String callbackUrlScheme,
              required bool preferEphemeral,
            }) async {
              sessionUrls.add(url);
              final state = Uri.parse(url).queryParameters['state'];
              return 'probe-scheme://authorize?code=FAKE_CODE&state=$state';
            },
      );
      final client = NaverSdkClient(webAuthClient: webClient);

      final result = await client.signIn();

      expect(hostCalls, <String>[kNaverHostMethodIsInstalled]);
      expect(sessionUrls, hasLength(1));
      expect(
        result,
        isA<NaverWebSignIn>().having((r) => r.code, 'code', 'FAKE_CODE'),
      );
      expect(logs, contains('Naver 경로 선택: mode=web installed=false'));
      expect(logs, contains('Naver web 시작'));
    });

    test('T-16.5-NAVER-ROUTE-07 source-contract: sdk client 는 웹 세션 패키지를 '
        'import 하지 않는다 (1-tap 경로 격리)', () {
      final code = stripComments(
        File('lib/features/auth/data/naver_sdk_client.dart').readAsStringSync(),
      );
      // 양성 대조군 — 웹 클라는 타입으로는 들어와 있다.
      expect(code, contains('naver_web_auth_client.dart'));
      expect(code, isNot(contains('flutter_web_auth_2')));
    });
  });

  // Phase 16.11 — iOS NAVER 앱 1-tap 의 취소 표면(A1 · SYSC)을 silent 로,
  // plugin stale 슬롯 거부를 1회 재시도로 흡수한다 (EX-03 · EX-04 · C-03 ·
  // C-04). 로그 단언은 전부 errorMessage 원문 부재를 함께 본다 (D-12).
  group('Phase 16.11 취소 표면 · stale 재시도 (T-16.11-NAVER-ABANDON)', () {
    /// 260929-snf A1 실측 문자열 — 상수와 독립으로 다시 적어 원문을 고정한다.
    const a1Message =
        'NID given Error. Error Code: undefined. \n'
        'Error Description: access_denied';

    /// 260929-snf SYSC 실측 문자열(86자) — SDK `naverAppNotInstalled` 문구.
    const syscMessage =
        'Naver app is not installed. \n'
        'Please install Naver App to authenticate using Naver App.';

    /// A1 과 같은 접두어의 다른 NID 오류 — 설정 · 서버 오류는 배너여야 한다.
    const otherNidMessage =
        'NID given Error. Error Code: invalid_request. \n'
        'Error Description: not given';

    /// [message] 를 `status=error` 로 돌려주는 1-tap client.
    NaverSdkClient buildErrorClient(String message) => NaverSdkClient.forTest(
      login: () async =>
          buildResult(status: NaverLoginStatus.error, errorMessage: message),
      logout: () async => buildLoggedOutResult(),
    );

    /// `ServiceUnavailable(cause: NaverSdkError)` — 기존 배너 경로.
    final isBannerError = isA<ServiceUnavailable>().having(
      (e) => e.cause,
      'cause',
      isA<NaverSdkError>(),
    );

    /// iOS 플러그인 stale 슬롯 거부 리터럴 (`FlutterNaverLoginPlugin.swift:124`).
    const rejectMessage = 'Another request is in progress. Please wait';

    /// 플러그인 거부 결과 — `status=error` + [rejectMessage].
    NaverLoginResult buildRejectResult() => buildResult(
      status: NaverLoginStatus.error,
      errorMessage: rejectMessage,
    );

    const staleLogInLine = 'Naver logIn stale 슬롯 재시도: method=logIn';
    const staleLogOutLine = 'Naver logIn stale 슬롯 재시도: method=logOut';

    /// 원문 부재 (D-12) — 생존 대조군(로그 ≥1) 뒤 거부 리터럴 조각이 없다.
    void expectNoRawMessage(List<String> logs) {
      expect(logs, isNotEmpty);
      for (final line in logs) {
        expect(line, isNot(contains('Another request')));
        expect(line, isNot(contains('Please wait')));
      }
    }

    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('T-16.11-NAVER-ABANDON-13 iOS 1-tap A1(access_denied 73자) → '
        'silent null · cancel 줄 1 · error 줄 0', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final logs = captureLogs();
      final client = NaverSdkClient.forTest(
        login: () async => buildResult(
          status: NaverLoginStatus.error,
          errorMessage: a1Message,
        ),
        logout: () async => buildLoggedOutResult(),
      );

      NaverSignInResult? result;
      Object? error;
      try {
        result = await client.signIn();
      } on Object catch (e) {
        error = e;
      }

      expect(a1Message.length, 73);
      expect(kNaverIosAppAccessDeniedMessage, a1Message);
      expect(error, isNull, reason: 'A1 은 사용자 취소 — 배너(throw)가 아니다');
      expect(result, isNull);
      expect(
        logs.where(
          (line) =>
              line ==
              'Naver logIn cancel: status=error '
                  'message=ios_sdk_nid_access_denied length=73',
        ),
        hasLength(1),
      );
      expect(
        logs.where((line) => line.startsWith('Naver logIn error')),
        isEmpty,
      );
      // 생존 대조군 뒤 원문 부재 (D-12).
      expect(logs, isNotEmpty);
      // 로그 이름(`ios_sdk_nid_access_denied`)은 원문이 아니다 — 원문 고유 조각만
      // 본다.
      for (final line in logs) {
        expect(line, isNot(contains('NID given Error')));
        expect(line, isNot(contains('Error Description')));
      }
    });

    test('T-16.11-NAVER-ABANDON-14 C-03 완전 일치 밖 변형 · Android A1 → '
        '기존 오류 경로(ServiceUnavailable)', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      // 양성 대조군 — 같은 iOS 조건에서 원문 그대로는 silent 다.
      expect(await buildErrorClient(a1Message).signIn(), isNull);

      final variants = <String, String>{
        '꼬리 공백': '$a1Message ',
        '대문자 변형': a1Message.replaceFirst('access_denied', 'ACCESS_DENIED'),
        '접두어만': 'NID given Error. Error Code: undefined.',
        '다른 NID 오류': otherNidMessage,
      };
      for (final entry in variants.entries) {
        expect(
          await captureSignInError(buildErrorClient(entry.value)),
          isBannerError,
          reason: '${entry.key}: 완전 일치가 아니면 취소가 아니다 (C-03)',
        );
      }

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(
        await captureSignInError(buildErrorClient(a1Message)),
        isBannerError,
        reason: 'Android 1-tap 은 A1 매핑 대상이 아니다 (C-04)',
      );
    });

    test('T-16.11-NAVER-ABANDON-15 SYSC(86자) — iOS 1-tap 만 silent · '
        'Android 는 오류', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final logs = captureLogs();

      NaverSignInResult? result;
      Object? error;
      try {
        result = await buildErrorClient(syscMessage).signIn();
      } on Object catch (e) {
        error = e;
      }

      expect(syscMessage.length, 86);
      expect(kNaverIosAppNotInstalledMessage, syscMessage);
      expect(error, isNull, reason: 'SYSC 알림 [Cancel] 은 사용자 취소다');
      expect(result, isNull);
      expect(
        logs.where(
          (line) =>
              line.startsWith('Naver logIn cancel:') &&
              line.contains(
                'message=ios_sdk_naver_app_not_installed length=86',
              ),
        ),
        hasLength(1),
      );
      expect(
        logs.where((line) => line.startsWith('Naver logIn error')),
        isEmpty,
      );
      expect(logs, isNotEmpty);
      for (final line in logs) {
        expect(line, isNot(contains('Please install Naver App')));
      }

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(
        await captureSignInError(buildErrorClient(syscMessage)),
        isBannerError,
        reason: 'Android 1-tap 에서 SYSC 문자열은 기존처럼 오류다 (C-04)',
      );
    });

    test('T-16.11-NAVER-ABANDON-16 isNaverUserCancel 매트릭스 · 로그 이름', () {
      for (final isIosOneTap in const <bool>[true, false]) {
        expect(
          isNaverUserCancel(
            NaverLoginStatus.loggedOut,
            null,
            isIosOneTap: isIosOneTap,
          ),
          isTrue,
          reason: 'loggedOut 은 플랫폼 공통 취소',
        );
        expect(
          isNaverUserCancel(
            NaverLoginStatus.error,
            kNaverIosCancelMessage,
            isIosOneTap: isIosOneTap,
          ),
          isTrue,
          reason: '기존 플러그인 취소 리터럴은 플랫폼 공통',
        );
        for (final message in const <String>[a1Message, syscMessage]) {
          expect(
            isNaverUserCancel(
              NaverLoginStatus.error,
              message,
              isIosOneTap: isIosOneTap,
            ),
            isIosOneTap,
            reason: 'A1 · SYSC 는 iOS 1-tap 인자를 그대로 따른다',
          );
        }
      }
      expect(
        isNaverUserCancel(
          NaverLoginStatus.loggedIn,
          a1Message,
          isIosOneTap: true,
        ),
        isFalse,
        reason: 'error 가 아니면 취소가 아니다',
      );
      expect(
        isNaverUserCancel(
          NaverLoginStatus.error,
          otherNidMessage,
          isIosOneTap: true,
        ),
        isFalse,
      );

      expect(a1Message.length, 73);
      expect(syscMessage.length, 86);
      expect(
        describeNaverErrorForLog(a1Message),
        'message=ios_sdk_nid_access_denied length=73',
      );
      expect(
        describeNaverErrorForLog(syscMessage),
        'message=ios_sdk_naver_app_not_installed length=86',
      );
      expect(
        describeNaverErrorForLog(otherNidMessage),
        startsWith('message=ios_sdk_nid_given_error '),
      );
    });

    test('T-16.11-NAVER-ABANDON-07 iOS stale 슬롯 거부 → logIn 1회 재시도 '
        '성공 · 배너 0', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final logs = captureLogs();
      var loginCalls = 0;
      final client = NaverSdkClient.forTest(
        login: () async {
          loginCalls++;
          return loginCalls == 1
              ? buildRejectResult()
              : buildSuccessResult('retry_token');
        },
        logout: () async => buildLoggedOutResult(),
      );

      final result = await client.signIn();

      expect(
        result,
        isA<NaverAppSignIn>().having(
          (r) => r.accessToken,
          'accessToken',
          'retry_token',
        ),
      );
      expect(loginCalls, 2);
      expect(logs.where((line) => line == staleLogInLine), hasLength(1));
      expect(
        logs.where((line) => line.startsWith('Naver logIn error')),
        isEmpty,
      );
      expectNoRawMessage(logs);
    });

    test('T-16.11-NAVER-ABANDON-08 iOS 재시도도 거부 → 기존 오류 경로 · '
        '재시도는 정확히 1회', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final logs = captureLogs();
      var loginCalls = 0;
      final client = NaverSdkClient.forTest(
        login: () async {
          loginCalls++;
          return buildRejectResult();
        },
        logout: () async => buildLoggedOutResult(),
      );

      expect(
        await captureSignInError(client),
        isA<ServiceUnavailable>().having(
          (e) => e.cause,
          'cause',
          isA<NaverSdkError>(),
        ),
      );
      expect(loginCalls, 2, reason: '재시도는 1회뿐 — 3 이면 무한 재시도 회귀');
      expect(logs.where((line) => line == staleLogInLine), hasLength(1));
      expect(
        logs.where(
          (line) =>
              line ==
              'Naver logIn error: '
                  'message=ios_plugin_request_in_progress length=43',
        ),
        hasLength(1),
      );
      expectNoRawMessage(logs);
    });

    test('T-16.11-NAVER-ABANDON-09 iOS logOut 거부 → 1회 재시도 · 두 번 모두 '
        '거부면 graceful 실패 로그', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final logs = captureLogs();

      var logoutCalls = 0;
      final retryOk = NaverSdkClient.forTest(
        login: () async => buildLoggedOutResult(),
        logout: () async {
          logoutCalls++;
          return logoutCalls == 1
              ? buildRejectResult()
              : buildLoggedOutResult();
        },
      );
      await retryOk.logout();

      expect(logoutCalls, 2);
      final staleIndex = logs.indexOf(staleLogOutLine);
      expect(staleIndex, isNonNegative);
      expect(
        logs.indexOf('NaverSdkClient.logout 완료'),
        greaterThan(staleIndex),
        reason: '재시도 줄 뒤에 두 번째 결과로 「완료」 를 판정한다',
      );
      expectNoRawMessage(logs);

      logs.clear();
      var rejectCalls = 0;
      final retryRejected = NaverSdkClient.forTest(
        login: () async => buildLoggedOutResult(),
        logout: () async {
          rejectCalls++;
          return buildRejectResult();
        },
      );
      Object? error;
      try {
        await retryRejected.logout();
      } on Object catch (e) {
        error = e;
      }

      expect(error, isNull, reason: 'logout 은 graceful — throw 0');
      expect(rejectCalls, 2);
      expect(logs.where((line) => line == staleLogOutLine), hasLength(1));
      expect(logs, isNot(contains('NaverSdkClient.logout 완료')));
      expect(
        logs.where(
          (line) =>
              line.startsWith('NaverSdkClient.logout 실패 (무시)') &&
              line.contains('message=ios_plugin_request_in_progress'),
        ),
        hasLength(1),
      );
      expectNoRawMessage(logs);
    });

    test('T-16.11-NAVER-ABANDON-18 C-04 Android 는 같은 거부에 재시도 0', () async {
      // 양성 대조군 — iOS 에서는 같은 fake 로 재시도가 실제로 일어난다.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      var iosLoginCalls = 0;
      final iosClient = NaverSdkClient.forTest(
        login: () async {
          iosLoginCalls++;
          return buildRejectResult();
        },
        logout: () async => buildLoggedOutResult(),
      );
      await captureSignInError(iosClient);
      expect(iosLoginCalls, 2, reason: '대조군 — iOS 는 1회 재시도');

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final logs = captureLogs();
      var loginCalls = 0;
      var logoutCalls = 0;
      final client = NaverSdkClient.forTest(
        login: () async {
          loginCalls++;
          return buildRejectResult();
        },
        logout: () async {
          logoutCalls++;
          return buildRejectResult();
        },
      );

      expect(
        await captureSignInError(client),
        isA<ServiceUnavailable>().having(
          (e) => e.cause,
          'cause',
          isA<NaverSdkError>(),
        ),
      );
      expect(loginCalls, 1);
      await client.logout();
      expect(logoutCalls, 1);
      expect(
        logs.where((line) => line.startsWith('Naver logIn stale 슬롯 재시도')),
        isEmpty,
      );
    });

    test('T-16.11-NAVER-ABANDON-12 U5 logout 라운드트립 중 signIn 은 끝날 때까지 '
        'plugin logIn 을 부르지 않는다', () async {
      final logoutGate = Completer<NaverLoginResult>();
      var loginCalls = 0;
      var logoutCalls = 0;
      final client = NaverSdkClient.forTest(
        login: () async {
          loginCalls++;
          return buildSuccessResult('after_logout');
        },
        logout: () {
          logoutCalls++;
          return logoutGate.future;
        },
      );

      final logoutFuture = client.logout();
      await pumpEventQueue();
      expect(logoutCalls, 1, reason: '대조군 — logout 라운드트립이 진행 중이다');

      final signInFuture = client.signIn();
      await pumpEventQueue();
      expect(
        loginCalls,
        0,
        reason:
            'logOut 이 끝나기 전 logIn 을 부르면 plugin 이 거부하며 logOut 의 '
            '슬롯을 비운다 (DG-3)',
      );

      logoutGate.complete(buildLoggedOutResult());
      await logoutFuture;
      final result = await signInFuture;

      expect(loginCalls, 1);
      expect(
        result,
        isA<NaverAppSignIn>().having(
          (r) => r.accessToken,
          'accessToken',
          'after_logout',
        ),
      );
    });
  });

  // Phase 16.11 — iOS 1-tap 결과 없는 복귀 포기 판정 · 고아 대기 (EX-01 ·
  // EX-02 · EX-03 · D-01 ~ D-07 · C-01 · C-02). 로그 단언은 전부 원문 · 토큰
  // sentinel 부재를 함께 본다 (D-12 · D-21).
  group('Phase 16.11 포기 판정 · 고아 대기 (T-16.11-NAVER-ABANDON)', () {
    const abandonLine = 'Naver logIn 포기: reason=no_callback_after_resume';
    const orphanWaitLine = 'NaverSdkClient.logout 지연 (orphan-wait)';
    const releaseLine = 'Naver logIn 고아 대기 해제: reason=stale_rejected';
    const staleLogInLine = 'Naver logIn stale 슬롯 재시도: method=logIn';

    /// 고아 결과에 실리는 토큰 — 어떤 로그 줄에도 나오면 안 된다 (D-21).
    const tokenSentinel = 'orphan_token_sentinel_7f3a';

    /// iOS 로 고정하고 테스트 끝에 되돌린다 (RESEARCH Pitfall 3).
    void useIos() {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
    }

    /// 판정 재료(lifecycle · 기록)를 fake 로 주입한 client.
    NaverSdkClient buildJudgedClient({
      required NaverLoginFn login,
      required NaverLogoutFn logout,
      required FakeLifecycle lifecycle,
      required CallbackRecordProbe record,
      NaverInstalledFn? isNaverAppInstalled,
      NaverWebSignInFn? webSignIn,
    }) => NaverSdkClient.forTest(
      login: login,
      logout: logout,
      isNaverAppInstalled: isNaverAppInstalled,
      webSignIn: webSignIn,
      lifecycleSubscribe: lifecycle.subscribe,
      callbackArrived: record.query,
      callbackReset: record.reset,
    );

    /// background 진입 → 복귀 → 판정 보류([kNaverResumeSettleDelay]) 경과.
    void driveReturnWithoutResult(FakeAsync async, FakeLifecycle lifecycle) {
      lifecycle
        ..emitPause()
        ..emitResume();
      async.elapse(kNaverResumeSettleDelay);
    }

    /// 생존 대조군(로그 ≥1) 뒤 토큰 · 원문 조각이 어떤 줄에도 없다.
    void expectNoSecrets(List<String> logs) {
      expect(logs, isNotEmpty);
      for (final line in logs) {
        expect(line, isNot(contains(tokenSentinel)));
        expect(line, isNot(contains('Another request')));
        expect(line, isNot(contains('NID given Error')));
      }
    }

    test('T-16.11-NAVER-ABANDON-01 결과 없는 복귀 → 0.3초 뒤 기록 false 면 '
        'silent null · 가드 해제 (D-02 · D-07)', () {
      useIos();
      final logs = captureLogs();
      fakeAsync((async) {
        final lifecycle = FakeLifecycle();
        final record = CallbackRecordProbe();
        final firstGate = Completer<NaverLoginResult>();
        var loginCalls = 0;
        final client = buildJudgedClient(
          login: () {
            loginCalls++;
            return loginCalls == 1
                ? firstGate.future
                : Future<NaverLoginResult>.value(
                    buildSuccessResult('second_token'),
                  );
          },
          logout: () async => buildLoggedOutResult(),
          lifecycle: lifecycle,
          record: record,
        );

        final first = SignInProbe(client);
        async.flushMicrotasks();
        expect(record.resets, 1, reason: '요청 시작 때 기록을 초기화한다');
        expect(lifecycle.subscribeCalls, 1);
        expect(loginCalls, 1);

        lifecycle
          ..emitPause()
          ..emitResume();
        async.elapse(const Duration(milliseconds: 299));
        expect(first.completed, isFalse);
        expect(record.queries, 0, reason: '299ms — 아직 판정 보류 중 (D-02)');

        async.elapse(const Duration(milliseconds: 1));
        expect(first.completed, isTrue, reason: '300ms 에 판정 1');
        expect(first.error, isNull);
        expect(first.result, isNull);
        expect(record.queries, 1);
        expect(lifecycle.disposeCalls, 1, reason: '포기 시 구독 해제');
        expect(logs.where((line) => line == abandonLine), hasLength(1));
        expect(
          logs.where((line) => line.startsWith('Naver logIn error')),
          isEmpty,
        );

        // D-07 — 가드가 풀렸다: 다음 탭이 곧바로 plugin logIn 에 닿는다.
        final second = SignInProbe(client);
        async.flushMicrotasks();
        expect(loginCalls, 2);
        expect(
          second.result,
          isA<NaverAppSignIn>().having(
            (r) => r.accessToken,
            'accessToken',
            'second_token',
          ),
        );
      });
      expect(kNaverResumeSettleDelay, const Duration(milliseconds: 300));
      expectNoSecrets(logs);
    });

    test('T-16.11-NAVER-ABANDON-04 포기 뒤 logout 은 plugin 호출 없이 지연된다 '
        '(D-06)', () {
      useIos();
      final logs = captureLogs();
      fakeAsync((async) {
        final lifecycle = FakeLifecycle();
        final gate = Completer<NaverLoginResult>();
        var logoutCalls = 0;
        final client = buildJudgedClient(
          login: () => gate.future,
          logout: () async {
            logoutCalls++;
            return buildLoggedOutResult();
          },
          lifecycle: lifecycle,
          record: CallbackRecordProbe(),
        );

        final probe = SignInProbe(client);
        async.flushMicrotasks();
        driveReturnWithoutResult(async, lifecycle);
        expect(probe.completed, isTrue, reason: '대조군 — 포기가 일어났다');
        expect(probe.result, isNull);

        unawaited(client.logout());
        async.flushMicrotasks();

        expect(
          logoutCalls,
          0,
          reason: '고아가 슬롯을 점유 중 — plugin 을 부르면 거부가 슬롯을 비운다',
        );
        expect(logs.where((line) => line == orphanWaitLine), hasLength(1));
      });
      expectNoSecrets(logs);
    });

    test('T-16.11-NAVER-ABANDON-05 고아가 늦게 성공하면 결과를 버리고 logout '
        '정확히 1회 (C-02 · D-57)', () {
      useIos();
      final logs = captureLogs();
      fakeAsync((async) {
        final lifecycle = FakeLifecycle();
        final gate = Completer<NaverLoginResult>();
        var logoutCalls = 0;
        final client = buildJudgedClient(
          login: () => gate.future,
          logout: () async {
            logoutCalls++;
            return buildLoggedOutResult();
          },
          lifecycle: lifecycle,
          record: CallbackRecordProbe(),
        );

        final probe = SignInProbe(client);
        async.flushMicrotasks();
        driveReturnWithoutResult(async, lifecycle);
        expect(probe.result, isNull);

        unawaited(client.logout());
        async.flushMicrotasks();
        expect(logoutCalls, 0);

        gate.complete(buildSuccessResult(tokenSentinel));
        async.flushMicrotasks();

        expect(logoutCalls, 1, reason: '지연분과 고아 완료가 1회로 접힌다 (2 아님)');
        expect(
          logs.where(
            (line) => line.startsWith('Naver logIn 고아 결과 도착: status=loggedIn'),
          ),
          hasLength(1),
        );

        unawaited(client.logout());
        async.flushMicrotasks();
        expect(logoutCalls, 2, reason: '고아가 끝났으니 즉시 plugin 을 부른다');
      });
      expectNoSecrets(logs);
    });

    test('T-16.11-NAVER-ABANDON-19 다음 탭의 stale 거부가 고아 대기를 해제하고 '
        '지연 logout 은 새 로그인 finally 가 소비한다 (EX-03)', () {
      useIos();
      final logs = captureLogs();
      fakeAsync((async) {
        final lifecycle = FakeLifecycle();
        // 실제 plugin 처럼 첫 요청은 영영 끝나지 않는다 (거부가 슬롯을 비움).
        final orphanGate = Completer<NaverLoginResult>();
        var loginCalls = 0;
        var logoutCalls = 0;
        final client = buildJudgedClient(
          login: () {
            loginCalls++;
            return switch (loginCalls) {
              1 => orphanGate.future,
              2 => Future<NaverLoginResult>.value(
                buildResult(
                  status: NaverLoginStatus.error,
                  errorMessage: kNaverIosRequestInProgressMessage,
                ),
              ),
              _ => Future<NaverLoginResult>.value(
                buildSuccessResult('fresh_token'),
              ),
            };
          },
          logout: () async {
            logoutCalls++;
            return buildLoggedOutResult();
          },
          lifecycle: lifecycle,
          record: CallbackRecordProbe(),
        );

        final first = SignInProbe(client);
        async.flushMicrotasks();
        driveReturnWithoutResult(async, lifecycle);
        expect(first.result, isNull);

        unawaited(client.logout());
        async.flushMicrotasks();
        expect(logoutCalls, 0, reason: '대조군 — 고아 대기 중 지연');

        final second = SignInProbe(client);
        async.flushMicrotasks();

        expect(second.completed, isTrue);
        expect(
          second.result,
          isA<NaverAppSignIn>().having(
            (r) => r.accessToken,
            'accessToken',
            'fresh_token',
          ),
        );
        expect(loginCalls, 3);
        expect(logs.where((line) => line == releaseLine), hasLength(1));
        expect(logs.where((line) => line == staleLogInLine), hasLength(1));
        expect(logoutCalls, 1, reason: '새 로그인 finally 가 지연분을 소비한다');

        unawaited(client.logout());
        async.flushMicrotasks();
        expect(logoutCalls, 2);
      });
      expectNoSecrets(logs);
    });

    test('T-16.11-NAVER-ABANDON-02 콜백 URL 이 도착했으면 한도 없이 계속 '
        '기다리고 늦은 성공을 보존한다 (C-01 · EX-02)', () {
      useIos();
      final logs = captureLogs();
      fakeAsync((async) {
        final lifecycle = FakeLifecycle();
        final record = CallbackRecordProbe(arrived: true);
        final gate = Completer<NaverLoginResult>();
        final client = buildJudgedClient(
          login: () => gate.future,
          logout: () async => buildLoggedOutResult(),
          lifecycle: lifecycle,
          record: record,
        );

        final probe = SignInProbe(client);
        async.flushMicrotasks();
        driveReturnWithoutResult(async, lifecycle);

        expect(record.queries, 1, reason: '대조군 — 판정은 실제로 돌았다');
        expect(
          logs.where(
            (line) => line == 'Naver logIn 복귀 판정: callback=arrived (계속 대기)',
          ),
          hasLength(1),
        );

        async.elapse(const Duration(minutes: 10));
        expect(probe.completed, isFalse, reason: '0.3초는 대기 한도가 아니다 (D-01)');

        gate.complete(buildSuccessResult('late_token'));
        async.flushMicrotasks();

        expect(
          probe.result,
          isA<NaverAppSignIn>().having(
            (r) => r.accessToken,
            'accessToken',
            'late_token',
          ),
        );
        expect(lifecycle.disposeCalls, 1);
        expect(logs.where((line) => line == abandonLine), isEmpty);
      });
      expectNoSecrets(logs);
    });

    test('T-16.11-NAVER-ABANDON-03 paused 없는 resumed(시스템 알림 · inactive '
        '전용) 는 판정하지 않는다 (OQ2)', () {
      useIos();
      final logs = captureLogs();
      fakeAsync((async) {
        final lifecycle = FakeLifecycle();
        final record = CallbackRecordProbe();
        final gate = Completer<NaverLoginResult>();
        final client = buildJudgedClient(
          login: () => gate.future,
          logout: () async => buildLoggedOutResult(),
          lifecycle: lifecycle,
          record: record,
        );

        final probe = SignInProbe(client);
        async.flushMicrotasks();
        expect(lifecycle.subscribeCalls, 1, reason: '대조군 — 구독은 있다');

        lifecycle.emitResume();
        async.elapse(const Duration(seconds: 1));

        expect(record.queries, 0);
        expect(probe.completed, isFalse);
        expect(logs.where((line) => line == abandonLine), isEmpty);

        gate.complete(
          buildResult(
            status: NaverLoginStatus.error,
            errorMessage: kNaverIosAppNotInstalledMessage,
          ),
        );
        async.flushMicrotasks();

        expect(probe.completed, isTrue);
        expect(probe.error, isNull, reason: 'SYSC [Cancel] 은 silent (plan 02)');
        expect(probe.result, isNull);
        expect(logs.where((line) => line == abandonLine), isEmpty);
      });
      for (final line in logs) {
        expect(line, isNot(contains('Please install Naver App')));
      }
    });

    test('T-16.11-NAVER-ABANDON-06 고아의 예외 · 오류 결과도 버리고 logout '
        '1회 · 미처리 예외 0', () {
      useIos();
      final logs = captureLogs();
      const exceptionSentinel = 'orphan_exception_sentinel_91c2';

      // (a) 예외 — PlatformException 이 고아 Future 로 온다.
      fakeAsync((async) {
        final lifecycle = FakeLifecycle();
        final gate = Completer<NaverLoginResult>();
        var logoutCalls = 0;
        final client = buildJudgedClient(
          login: () => gate.future,
          logout: () async {
            logoutCalls++;
            return buildLoggedOutResult();
          },
          lifecycle: lifecycle,
          record: CallbackRecordProbe(),
        );

        final probe = SignInProbe(client);
        async.flushMicrotasks();
        driveReturnWithoutResult(async, lifecycle);
        expect(probe.result, isNull);

        gate.completeError(
          PlatformException(code: 'x', message: exceptionSentinel),
        );
        async.flushMicrotasks();

        expect(probe.error, isNull);
        expect(logoutCalls, 1);
        expect(
          logs.where(
            (line) =>
                line == 'Naver logIn 고아 결과 도착: exception=PlatformException',
          ),
          hasLength(1),
        );
      });

      // (b) 오류 결과 — A1 문자열이 고아로 온다 (배너 경로에 닿지 않는다).
      fakeAsync((async) {
        final lifecycle = FakeLifecycle();
        final gate = Completer<NaverLoginResult>();
        var logoutCalls = 0;
        final client = buildJudgedClient(
          login: () => gate.future,
          logout: () async {
            logoutCalls++;
            return buildLoggedOutResult();
          },
          lifecycle: lifecycle,
          record: CallbackRecordProbe(),
        );

        final probe = SignInProbe(client);
        async.flushMicrotasks();
        driveReturnWithoutResult(async, lifecycle);

        gate.complete(
          buildResult(
            status: NaverLoginStatus.error,
            errorMessage: kNaverIosAppAccessDeniedMessage,
          ),
        );
        async.flushMicrotasks();

        expect(probe.error, isNull, reason: 'ServiceUnavailable 발생 0');
        expect(probe.result, isNull);
        expect(logoutCalls, 1);
        expect(
          logs.where(
            (line) =>
                line.startsWith('Naver logIn 고아 결과 도착:') &&
                line.contains('status=error message=ios_sdk_nid_access_denied'),
          ),
          hasLength(1),
        );
      });

      expectNoSecrets(logs);
      for (final line in logs) {
        expect(line, isNot(contains(exceptionSentinel)));
      }
    });

    test('T-16.11-NAVER-ABANDON-20 새 signIn in-flight 중 고아가 도착해도 '
        'plugin 호출이 겹치지 않는다 (T-16.11-09)', () {
      useIos();
      final logs = captureLogs();
      fakeAsync((async) {
        final lifecycle = FakeLifecycle();
        final orphanGate = Completer<NaverLoginResult>();
        final installedGate = Completer<bool>();
        final violations = <String>[];
        var loginCalls = 0;
        var logoutCalls = 0;
        var installedCalls = 0;
        var loginsInProgress = 0;
        var logoutsInProgress = 0;

        final client = buildJudgedClient(
          login: () {
            loginCalls++;
            if (logoutsInProgress != 0) violations.add('login#$loginCalls');
            loginsInProgress++;
            final future = loginCalls == 1
                ? orphanGate.future
                : Future<NaverLoginResult>.value(
                    buildSuccessResult('second_token'),
                  );
            return future.whenComplete(() => loginsInProgress--);
          },
          logout: () async {
            logoutCalls++;
            if (loginsInProgress != 0) violations.add('logout#$logoutCalls');
            logoutsInProgress++;
            await Future<void>.value();
            logoutsInProgress--;
            return buildLoggedOutResult();
          },
          isNaverAppInstalled: () {
            installedCalls++;
            return installedCalls == 1
                ? Future<bool>.value(true)
                : installedGate.future;
          },
          lifecycle: lifecycle,
          record: CallbackRecordProbe(),
        );

        final first = SignInProbe(client);
        async.flushMicrotasks();
        driveReturnWithoutResult(async, lifecycle);
        expect(first.result, isNull, reason: '대조군 — 포기했다');

        // 둘째 탭 — 설치 판정에서 멈춘 채 in-flight 다 (plugin logIn 전).
        final second = SignInProbe(client);
        async.flushMicrotasks();
        expect(second.completed, isFalse);
        expect(loginCalls, 1);

        orphanGate.complete(buildSuccessResult(tokenSentinel));
        async.flushMicrotasks();
        expect(logoutCalls, 0, reason: '새 로그인이 in-flight — 고아 logout 도 지연');

        installedGate.complete(true);
        async.flushMicrotasks();

        expect(loginCalls, 2);
        expect(second.completed, isTrue);
        expect(
          second.result,
          isA<NaverAppSignIn>().having(
            (r) => r.accessToken,
            'accessToken',
            'second_token',
          ),
        );
        expect(logoutCalls, 1, reason: '새 로그인 finally 가 소비한다');
        expect(violations, isEmpty, reason: '겹친 plugin 호출: $violations');
      });
      expectNoSecrets(logs);
    });

    test('T-16.11-NAVER-ABANDON-10 Android 1-tap 은 구독 · 초기화 · 조회 0 '
        '(D-03 · D-11 · C-04)', () {
      useIos();
      // 양성 대조군 — 같은 fake 로 iOS 에서는 판정 재료가 실제로 쓰인다.
      fakeAsync((async) {
        final lifecycle = FakeLifecycle();
        final record = CallbackRecordProbe(arrived: true);
        final gate = Completer<NaverLoginResult>();
        final client = buildJudgedClient(
          login: () => gate.future,
          logout: () async => buildLoggedOutResult(),
          lifecycle: lifecycle,
          record: record,
        );

        final probe = SignInProbe(client);
        async.flushMicrotasks();
        driveReturnWithoutResult(async, lifecycle);
        gate.complete(buildSuccessResult('ios_token'));
        async.flushMicrotasks();

        expect(lifecycle.subscribeCalls, 1);
        expect(record.resets, 1);
        expect(record.queries, 1);
        expect(probe.result, isA<NaverAppSignIn>());
      });

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      fakeAsync((async) {
        final lifecycle = FakeLifecycle();
        final record = CallbackRecordProbe();
        final gate = Completer<NaverLoginResult>();
        final client = buildJudgedClient(
          login: () => gate.future,
          logout: () async => buildLoggedOutResult(),
          lifecycle: lifecycle,
          record: record,
        );

        final probe = SignInProbe(client);
        async.flushMicrotasks();
        driveReturnWithoutResult(async, lifecycle);
        expect(probe.completed, isFalse, reason: 'Android 는 포기 판정이 없다');

        gate.complete(buildSuccessResult('android_token'));
        async.flushMicrotasks();

        expect(lifecycle.subscribeCalls, 0);
        expect(record.resets, 0);
        expect(record.queries, 0);
        expect(
          probe.result,
          isA<NaverAppSignIn>().having(
            (r) => r.accessToken,
            'accessToken',
            'android_token',
          ),
        );
      });
    });

    test('T-16.11-NAVER-ABANDON-11 킷 웹 경로는 구독 · 초기화 · 조회 0 '
        '(C-04)', () async {
      useIos();
      const webResult = NaverWebSignIn(code: 'WEB_CODE', state: 'WEB_STATE');
      final lifecycle = FakeLifecycle();
      final record = CallbackRecordProbe();
      var loginCalls = 0;
      final client = buildJudgedClient(
        login: () async {
          loginCalls++;
          return buildSuccessResult('unexpected');
        },
        logout: () async => buildLoggedOutResult(),
        lifecycle: lifecycle,
        record: record,
        isNaverAppInstalled: () async => false,
        webSignIn: () async => webResult,
      );

      final result = await client.signIn();

      expect(result, same(webResult));
      expect(loginCalls, 0);
      expect(lifecycle.subscribeCalls, 0);
      expect(record.resets, 0);
      expect(record.queries, 0);
    });

    test('T-16.11-NAVER-ABANDON-17 production 구독 — 실제 binding 의 paused · '
        'resumed 를 각 1회 받고 해제 뒤 0 (D-03)', () {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      addTearDown(
        () => binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed),
      );
      // 엔진과 같은 순서 — AppLifecycleListener 가 잘못된 전환을 assert 한다.
      const cycle = <AppLifecycleState>[
        AppLifecycleState.resumed,
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ];
      void driveCycle() {
        for (final state in cycle) {
          binding.handleAppLifecycleStateChanged(state);
        }
      }

      // 구독 전 resumed 로 맞춘다 — 초기 null 에서의 첫 resumed 도 onResume
      // 이라 계수가 흐려진다.
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      var pauses = 0;
      var resumes = 0;
      final unsubscribe = subscribeNaverAppLifecycle(
        onPause: () => pauses++,
        onResume: () => resumes++,
      );

      driveCycle();
      expect(pauses, 1);
      expect(resumes, 1);

      unsubscribe();
      driveCycle();
      expect(pauses, 1, reason: '해제 뒤에는 받지 않는다');
      expect(resumes, 1, reason: '해제 뒤에는 받지 않는다');
    });
  });
}
