// Phase 13 — see ROADMAP.md
//
// NaverSdkClient 회귀 테스트 — Completer race / cancel / leak 가드 + logout 회귀.
// Validation Architecture line 1618 — T-13-NAVER-SDK-{n}.
import 'package:flutter_test/flutter_test.dart';
import 'package:naver_login_sdk/naver_login_sdk.dart';

import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/features/auth/data/naver_sdk_client.dart';

void main() {
  group('NaverSdkClient (T-13-NAVER-SDK)', () {
    test('T-13-NAVER-SDK-01: onSuccess + getAccessToken → '
        'NaverSignInResult', () async {
      OAuthLoginCallback? capturedCallback;
      final client = NaverSdkClient.forTest(
        login: ({required OAuthLoginCallback callback}) {
          capturedCallback = callback;
        },
        getAccessToken: () async => 'valid_token',
        logout: () async {},
      );

      final future = client.signIn();
      // SDK callback 시뮬레이션 — onSuccess 1회 호출.
      await Future<void>.delayed(Duration.zero);
      capturedCallback!.onSuccess?.call();
      final result = await future;

      expect(result, isNotNull);
      expect(result!.accessToken, equals('valid_token'));
    });

    test('T-13-NAVER-SDK-02: onError "user_cancel" → null silent', () async {
      OAuthLoginCallback? capturedCallback;
      final client = NaverSdkClient.forTest(
        login: ({required OAuthLoginCallback callback}) {
          capturedCallback = callback;
        },
        getAccessToken: () async => '',
        logout: () async {},
      );

      final future = client.signIn();
      await Future<void>.delayed(Duration.zero);
      capturedCallback!.onError?.call(-1, 'user_cancel');
      final result = await future;

      expect(result, isNull);
    });

    test('T-13-NAVER-SDK-03: onError "Canceled By User…" → null silent',
        () async {
      OAuthLoginCallback? capturedCallback;
      final client = NaverSdkClient.forTest(
        login: ({required OAuthLoginCallback callback}) {
          capturedCallback = callback;
        },
        getAccessToken: () async => '',
        logout: () async {},
      );

      final future = client.signIn();
      await Future<void>.delayed(Duration.zero);
      capturedCallback!.onError?.call(-1, 'Canceled By User Click Cancel');
      final result = await future;

      expect(result, isNull);
    });

    test('T-13-NAVER-SDK-04: onError "naverapp_not_installed" → callback '
        '재호출 대기 (silent timeout)', () async {
      OAuthLoginCallback? capturedCallback;
      final client = NaverSdkClient.forTest(
        login: ({required OAuthLoginCallback callback}) {
          capturedCallback = callback;
        },
        getAccessToken: () async => '',
        logout: () async {},
      );

      final future = client.signIn();
      await Future<void>.delayed(Duration.zero);
      // naverapp_not_installed → SDK 가 자동 webview fallback 진행 중. 분기 무시.
      capturedCallback!.onError?.call(-1, 'naverapp_not_installed');
      // 그 직후 onSuccess 가 도착하면 정상 결과 반환 (webview fallback 이 성공한 시뮬레이션).
      capturedCallback!.onSuccess?.call();
      final result = await future;

      // getAccessToken 이 빈 문자열을 반환하므로 null 반환 (안전 fallback).
      expect(result, isNull);
    });

    test('T-13-NAVER-SDK-05: onFailure → null silent (D-45)', () async {
      OAuthLoginCallback? capturedCallback;
      final client = NaverSdkClient.forTest(
        login: ({required OAuthLoginCallback callback}) {
          capturedCallback = callback;
        },
        getAccessToken: () async => '',
        logout: () async {},
      );

      final future = client.signIn();
      await Future<void>.delayed(Duration.zero);
      capturedCallback!.onFailure?.call('500', 'Server Error');
      final result = await future;

      expect(result, isNull);
    });

    test('T-13-NAVER-SDK-06: onError 그 외 (network 등) → '
        'ServiceUnavailable throw', () async {
      OAuthLoginCallback? capturedCallback;
      final client = NaverSdkClient.forTest(
        login: ({required OAuthLoginCallback callback}) {
          capturedCallback = callback;
        },
        getAccessToken: () async => '',
        logout: () async {},
      );

      final future = client.signIn();
      await Future<void>.delayed(Duration.zero);
      capturedCallback!.onError?.call(500, 'network_error');

      await expectLater(future, throwsA(isA<ServiceUnavailable>()));
    });

    test('T-13-NAVER-SDK-LEAK-01: Completer 다중 complete 가드 (Pitfall 1)',
        () async {
      OAuthLoginCallback? capturedCallback;
      final client = NaverSdkClient.forTest(
        login: ({required OAuthLoginCallback callback}) {
          capturedCallback = callback;
        },
        getAccessToken: () async => 'first_token',
        logout: () async {},
      );

      final future = client.signIn();
      await Future<void>.delayed(Duration.zero);
      // onSuccess 후 onError 도 도착 — StateError 미발생, 첫 complete 만 effective.
      capturedCallback!.onSuccess?.call();
      // onSuccess 콜백 내부 await getAccessToken() 완료 대기.
      await Future<void>.delayed(Duration.zero);
      // 이중 complete 가드 검증 — onError 에서 throw 시도해도 무시.
      capturedCallback!.onError?.call(-1, 'after_success_user_cancel');
      capturedCallback!.onFailure?.call('400', 'after_success');
      final result = await future;

      // 첫 complete (onSuccess) 만 effective.
      expect(result, isNotNull);
      expect(result!.accessToken, equals('first_token'));
    });

    test('T-13-NAVER-SDK-07: logout 호출 시 NaverLoginSDK.logout 실행',
        () async {
      var logoutCalled = false;
      final client = NaverSdkClient.forTest(
        login: ({required OAuthLoginCallback callback}) {},
        getAccessToken: () async => '',
        logout: () async {
          logoutCalled = true;
        },
      );

      await client.logout();
      expect(logoutCalled, isTrue);
    });

    test('T-13-NAVER-SDK-08: logout 실패 시 graceful (throw 안 함)',
        () async {
      final client = NaverSdkClient.forTest(
        login: ({required OAuthLoginCallback callback}) {},
        getAccessToken: () async => '',
        logout: () async {
          throw Exception('SDK error');
        },
      );

      // throw 안 함 검증 — graceful (debugPrint).
      await client.logout();
    });

    test('T-13-NAVER-SDK-09: getAccessToken 실패 → '
        'ServiceUnavailable throw', () async {
      OAuthLoginCallback? capturedCallback;
      final client = NaverSdkClient.forTest(
        login: ({required OAuthLoginCallback callback}) {
          capturedCallback = callback;
        },
        getAccessToken: () async {
          throw Exception('token fetch failed');
        },
        logout: () async {},
      );

      final future = client.signIn();
      await Future<void>.delayed(Duration.zero);
      capturedCallback!.onSuccess?.call();

      await expectLater(future, throwsA(isA<ServiceUnavailable>()));
    });
  });
}
