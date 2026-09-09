// Phase 14 — see ROADMAP.md (LineSdkClient unit tests)
//
// Pattern: Phase 12 kakao_sdk_client_test.dart + Phase 13 naver_sdk_client_test.dart
// 의 typedef 주입 패턴 mirror. mocktail 대신 함수 typedef stub 으로 LINE SDK
// 의 static singleton (`LineSDK.instance.login` / `logout`) 격리.
import 'dart:convert';

import 'package:flutter/services.dart' show MethodChannel, PlatformException;
import 'package:flutter_line_sdk/flutter_line_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/features/auth/data/line_sdk_client.dart';

/// LoginResult 는 private ctor (`LoginResult._`) 이라 직접 생성 불가 →
/// `LineLoginFn` stub 이 [Future<LoginResult>] 를 합성하려면 SDK 가 실제로
/// 호출하는 platform-channel binding 을 mock 해야 한다.
///
/// SDK 의 [LineSDK.login] 본문은 `channel.invokeMethod('login', ...)` 결과를
/// `_decodeJson(value)` 로 통과한 뒤 [LoginResult._] 에 전달한다
/// (`line_sdk.dart` line 99-105). `_decodeJson` 가 `json.decode(source)` 를
/// 호출하므로 platform channel 응답은 **JSON String** 이어야 한다 (Map 직접
/// 반환 시 `'_Map<Object?, Object?>' is not a subtype of type 'String?'`
/// TypeError 발생 — line_sdk.dart line 179-182).
///
/// 본 helper 는 SDK 의 method channel 을 JSON String 으로 mock 한 뒤
/// `LineSDK.instance.login()` 을 호출해 정상 LoginResult 를 합성한다.
Future<LoginResult> _buildLoginResult({
  required String? idTokenRaw,
  String? nonce,
}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.linecorp/flutter_line_sdk');
  final payload = <String, Object?>{
    'accessToken': <String, Object?>{
      'access_token': 'AT',
      'expires_in': 3600,
      'id_token': idTokenRaw,
      'scope': 'openid profile',
      'token_type': 'Bearer',
    },
    'IDTokenNonce': nonce,
    'scope': 'openid profile',
  };
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'login') {
          return jsonEncode(payload);
        }
        return null;
      });
  return LineSDK.instance.login();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LineSdkClient.signIn — nonce + idToken contract', () {
    test('Test 1: nonce 는 base64url 형식 (length >= 22, regex 부합)', () async {
      String? capturedNonce;
      final client = LineSdkClient.forTest(
        login: ({required scopes, required option}) async {
          capturedNonce = option.idTokenNonce;
          return _buildLoginResult(
            idTokenRaw: 'JWT',
            nonce: option.idTokenNonce,
          );
        },
        logout: () async {},
      );

      final result = await client.signIn();

      expect(result, isNotNull);
      expect(capturedNonce, isNotNull);
      // base64url 의 padding-stripped 형식 — A-Z / a-z / 0-9 / - / _.
      expect(
        RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(capturedNonce!),
        isTrue,
        reason: 'nonce 가 base64url 안전 문자 집합만 포함해야 한다',
      );
      // 16 bytes → base64 = 22 chars (padding 제거).
      expect(capturedNonce!.length, greaterThanOrEqualTo(22));
    });

    test(
      'Test 2: fake login 의 LoginResult.idToken + 호출 nonce 가 정확 매핑',
      () async {
        const idToken = 'JWT_HEADER.JWT_PAYLOAD.JWT_SIG';
        String? generatedNonce;
        final client = LineSdkClient.forTest(
          login: ({required scopes, required option}) async {
            generatedNonce = option.idTokenNonce;
            return _buildLoginResult(
              idTokenRaw: idToken,
              nonce: option.idTokenNonce,
            );
          },
          logout: () async {},
        );

        final result = await client.signIn();

        expect(result, isNotNull);
        expect(result!.idToken, idToken);
        expect(result.nonce, generatedNonce);
      },
    );

    test(
      'Test 3: PlatformException("CANCEL") (iOS LINE app-to-app 취소) → null',
      () async {
        final client = LineSdkClient.forTest(
          login: ({required scopes, required option}) async {
            throw PlatformException(code: 'CANCEL');
          },
          logout: () async {},
        );

        final result = await client.signIn();

        expect(result, isNull);
      },
    );

    test('Test 4: PlatformException("AUTHENTICATION_CANCELLED") (Android LINE '
        '취소) → null', () async {
      final client = LineSdkClient.forTest(
        login: ({required scopes, required option}) async {
          throw PlatformException(code: 'AUTHENTICATION_CANCELLED');
        },
        logout: () async {},
      );

      final result = await client.signIn();

      expect(result, isNull);
    });

    test('Test 5: 비-cancel PlatformException → rethrow', () async {
      final client = LineSdkClient.forTest(
        login: ({required scopes, required option}) async {
          throw PlatformException(code: 'NETWORK_ERROR');
        },
        logout: () async {},
      );

      await expectLater(client.signIn(), throwsA(isA<PlatformException>()));
    });

    test('Test 6: idTokenRaw null (Pitfall 1 — OIDC scope 누락) → '
        'ServiceUnavailable throw', () async {
      final client = LineSdkClient.forTest(
        login: ({required scopes, required option}) async {
          return _buildLoginResult(idTokenRaw: null);
        },
        logout: () async {},
      );

      await expectLater(client.signIn(), throwsA(isA<ServiceUnavailable>()));
    });

    // WR-03 (Phase 14 review): null 만이 아닌 빈 문자열도 client-side 가드.
    // flutter_line_sdk native 측이 사실상 null 만 반환하지만 방어적 회귀
    // 가드로 ServiceUnavailable 분기 일관성 보장.
    test(
      'Test 6.5: idTokenRaw 빈 문자열 → ServiceUnavailable throw (WR-03)',
      () async {
        final client = LineSdkClient.forTest(
          login: ({required scopes, required option}) async {
            return _buildLoginResult(idTokenRaw: '');
          },
          logout: () async {},
        );

        await expectLater(client.signIn(), throwsA(isA<ServiceUnavailable>()));
      },
    );
  });

  group('LineSdkClient.logout — D-LINE-57 1회성 토큰 + graceful', () {
    test('Test 7: logout() 호출 시 _logout fake 정확히 1회 호출', () async {
      var logoutCallCount = 0;
      final client = LineSdkClient.forTest(
        login: ({required scopes, required option}) async {
          throw UnimplementedError('login 미호출');
        },
        logout: () async {
          logoutCallCount += 1;
        },
      );

      await client.logout();

      expect(logoutCallCount, 1);
    });

    test(
      'Test 8: _logout throw 해도 logout() 가 silent swallow (graceful)',
      () async {
        final client = LineSdkClient.forTest(
          login: ({required scopes, required option}) async {
            throw UnimplementedError('login 미호출');
          },
          logout: () async {
            throw Exception('logout 실패 시뮬레이션');
          },
        );

        // 예외 0 — graceful.
        await client.logout();
      },
    );
  });
}
