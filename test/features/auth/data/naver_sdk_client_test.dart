// Phase 16.2 — see ROADMAP.md
//
// NaverSdkClient 회귀 테스트 — 플러그인 Future 직결 구조의 성공 · 취소 · 오류
// · 예외 · logout 분기 가드. `16.2-VALIDATION.md` Per-Task 표 — T-16.2-NAVER-SDK-{n}.
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

void main() {
  group('NaverSdkClient (T-16.2-NAVER-SDK)', () {
    test(
      'T-16.2-NAVER-SDK-01 success: loggedIn + 토큰 → accessToken 전달',
      () async {
        var loginCalls = 0;
        final client = NaverSdkClient.forTest(
          login: () async {
            loginCalls++;
            return buildResult(
              status: NaverLoginStatus.loggedIn,
              accessToken: buildToken('valid_token'),
            );
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
        login: () async => buildResult(
          status: NaverLoginStatus.loggedIn,
          accessToken: buildToken(''),
        ),
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

      Object? captured;
      try {
        await client.signIn();
      } on Object catch (e) {
        captured = e;
      }

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

      Object? captured;
      try {
        await client.signIn();
      } on Object catch (e) {
        captured = e;
      }

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
  });
}
