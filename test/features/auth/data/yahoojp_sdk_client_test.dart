// Phase 15 — see ROADMAP.md (YahoojpSdkClient unit tests)
//
// Pattern: Phase 14 line_sdk_client_test.dart 의 typedef 주입 패턴 mirror.
// mocktail 대신 함수 typedef stub 으로 flutter_appauth 의 stateless wrapper
// (`FlutterAppAuth.authorizeAndExchangeCode` / `endSession`) 격리.
//
// **Mock 한계 명시 (Phase 14.1 D-14.1-03 §7-C baseline 적용):**
// 본 테스트는 flutter_appauth 의 native AppAuth-iOS/Android binding 호출을
// 함수 typedef 주입으로 우회한다. 실 단말의 ASWebAuthenticationSession (iOS) /
// Custom Tabs (Android) flow 는 본 테스트로 검증 불가 — Plan 15-06 UAT
// A1~A8 가 실 단말 contract 검증의 single source.
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/features/auth/data/yahoojp_sdk_client.dart';

/// 정상 ID Token 응답을 합성하는 helper.
///
/// flutter_appauth 의 [AuthorizationTokenResponse] 는 8 positional 인자 ctor
/// (accessToken/refreshToken/expirationDate/idToken/tokenType/scopes/
/// authAdditionalParams/tokenAdditionalParams) — 본 테스트는 idToken 만
/// 검증에 사용하므로 나머지 인자는 placeholder.
AuthorizationTokenResponse _buildTokenResponse({required String? idToken}) {
  return AuthorizationTokenResponse(
    'AT', // accessToken
    null, // refreshToken
    null, // accessTokenExpirationDateTime
    idToken, // idToken
    'Bearer', // tokenType
    const <String>['openid', 'profile'], // scopes
    null, // authorizationAdditionalParameters
    null, // tokenAdditionalParameters
  );
}

/// 사용자 취소 예외 합성 helper — Phase 15 deviation #2 (LINE
/// PlatformException 'CANCEL'/'AUTHENTICATION_CANCELLED' 이원 분기 대비
/// flutter_appauth 가 단일 예외 타입 노출).
FlutterAppAuthUserCancelledException _userCancelledException() {
  return FlutterAppAuthUserCancelledException(
    code: 'user_cancelled',
    message: 'User cancelled the authorization request',
    platformErrorDetails: FlutterAppAuthPlatformErrorDetails(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ==========================================================================
  // Test 1: nonce 22 char base64Url + idToken 정확 매핑 (D-YJP-04)
  // ==========================================================================
  group('YahoojpSdkClient.signIn — nonce + idToken contract', () {
    test('Test 1: 정상 응답 — fake authorize 의 idToken + 생성 nonce 매핑 + '
        'nonce 22 char base64url 검증', () async {
      const idToken = 'JWT_HEADER.JWT_PAYLOAD.JWT_SIG';
      String? capturedNonce;
      final client = YahoojpSdkClient.forTest(
        clientId: 'test-client-id',
        redirectUrl: 'com.example.app:/oauth2redirect',
        authorize: (request) async {
          capturedNonce = request.nonce;
          return _buildTokenResponse(idToken: idToken);
        },
        endSession: (request) async {
          throw UnimplementedError('endSession 미호출');
        },
      );

      final result = await client.signIn();

      expect(result, isNotNull);
      expect(result!.idToken, idToken);
      expect(result.nonce, capturedNonce);
      expect(capturedNonce, isNotNull);
      // 16 bytes → base64url padding 제거 = 22 chars.
      expect(
        capturedNonce!.length,
        22,
        reason: '16 bytes Random.secure() → base64Url padding 제거 = 22 chars',
      );
      // base64url 의 padding-stripped 형식 — A-Z / a-z / 0-9 / - / _.
      expect(
        RegExp(r'^[A-Za-z0-9_-]{22}$').hasMatch(capturedNonce!),
        isTrue,
        reason: 'nonce 가 base64url 안전 문자 집합만 포함해야 한다',
      );
    });

    test('Test 2: 사용자 취소 silent — FlutterAppAuthUserCancelledException → null '
        '(D-YJP-09)', () async {
      final client = YahoojpSdkClient.forTest(
        clientId: 'test-client-id',
        redirectUrl: 'com.example.app:/oauth2redirect',
        authorize: (request) async {
          throw _userCancelledException();
        },
        endSession: (request) async {
          throw UnimplementedError('endSession 미호출');
        },
      );

      final result = await client.signIn();

      expect(
        result,
        isNull,
        reason:
            'FlutterAppAuthUserCancelledException 는 D-YJP-09 정정 lock '
            'silent cancel — null 반환 (deviation #2: LINE PlatformException '
            "'CANCEL'/'AUTHENTICATION_CANCELLED' 이원 분기 대비 단일 예외 타입)",
      );
    });

    test(
      'Test 3: 비-cancel 예외 → rethrow (race-fix invariant — '
      'AuthRepository.signInWithYahoojp 가 _mapAuthException 으로 흡수)',
      () async {
        final client = YahoojpSdkClient.forTest(
          clientId: 'test-client-id',
          redirectUrl: 'com.example.app:/oauth2redirect',
          authorize: (request) async {
            throw Exception('network error');
          },
          endSession: (request) async {
            throw UnimplementedError('endSession 미호출');
          },
        );

        await expectLater(client.signIn(), throwsA(isA<Exception>()));
      },
    );

    test(
      'Test 4: idToken null (Pitfall 1 — OIDC scope 누락) → ServiceUnavailable '
      'throw',
      () async {
        final client = YahoojpSdkClient.forTest(
          clientId: 'test-client-id',
          redirectUrl: 'com.example.app:/oauth2redirect',
          authorize: (request) async {
            return _buildTokenResponse(idToken: null);
          },
          endSession: (request) async {
            throw UnimplementedError('endSession 미호출');
          },
        );

        await expectLater(client.signIn(), throwsA(isA<ServiceUnavailable>()));
      },
    );

    test(
      'Test 4.5: idToken 빈 문자열 → ServiceUnavailable throw (Pitfall 1 보강)',
      () async {
        final client = YahoojpSdkClient.forTest(
          clientId: 'test-client-id',
          redirectUrl: 'com.example.app:/oauth2redirect',
          authorize: (request) async {
            return _buildTokenResponse(idToken: '');
          },
          endSession: (request) async {
            throw UnimplementedError('endSession 미호출');
          },
        );

        await expectLater(client.signIn(), throwsA(isA<ServiceUnavailable>()));
      },
    );

    test(
      'Test 5: clientId 빈 문자열 → ServiceUnavailable throw '
      '(T-15-15 mitigation — --dart-define-from-file 미주입 silent failure 회피)',
      () async {
        final client = YahoojpSdkClient.forTest(
          clientId: '',
          redirectUrl: 'com.example.app:/oauth2redirect',
          authorize: (request) async {
            throw UnimplementedError('signIn 진입 차단 — clientId empty');
          },
          endSession: (request) async {
            throw UnimplementedError('endSession 미호출');
          },
        );

        await expectLater(client.signIn(), throwsA(isA<ServiceUnavailable>()));
      },
    );

    test('Test 6: AuthorizationTokenRequest 인자 검증 — clientId/redirectUrl/'
        'scopes openid+profile (D-YJP-09)', () async {
      AuthorizationTokenRequest? captured;
      final client = YahoojpSdkClient.forTest(
        clientId: 'yj-client-001',
        redirectUrl: 'jp.example.yahoojp:/oauth2redirect',
        authorize: (request) async {
          captured = request;
          return _buildTokenResponse(idToken: 'JWT');
        },
        endSession: (request) async {
          throw UnimplementedError('endSession 미호출');
        },
      );

      await client.signIn();

      expect(captured, isNotNull);
      expect(captured!.clientId, 'yj-client-001');
      expect(captured!.redirectUrl, 'jp.example.yahoojp:/oauth2redirect');
      // D-YJP-09 정정 lock — email scope 미채택.
      expect(
        captured!.scopes,
        const <String>['openid', 'profile'],
        reason:
            'D-YJP-09 정정 lock — Yahoo!JP UserInfo API 審査 회피, '
            'email scope 미채택. _autoSendEmailVerification 자연 no-op.',
      );
    });
  });

  // ==========================================================================
  // Test 7-8: logout — WR-03 정정. Yahoo!JP 는 RP-Initiated Logout endpoint 를
  // 공개하지 않으므로 logout() 은 구조적 no-op 이며 Kakao/LINE/Naver 의 D-57
  // 실효 토큰 폐기와 동등하지 않다. 이전 계약 ("endSession 정확히 1회 호출")
  // 은 `endSessionEndpoint = null` config 때문에 매번 예외로 끝나는, 성공할 수
  // 없는 호출이었다.
  // ==========================================================================
  group('YahoojpSdkClient.logout — WR-03 구조적 no-op + graceful', () {
    test('Test 7 (WR-03): endSessionEndpoint 미공개 → _endSession 호출 0건 '
        '(도달 불가능한 platform 왕복 제거)', () async {
      var endSessionCallCount = 0;
      final client = YahoojpSdkClient.forTest(
        clientId: 'test-client-id',
        redirectUrl: 'com.example.app:/oauth2redirect',
        authorize: (request) async {
          throw UnimplementedError('signIn 미호출');
        },
        endSession: (request) async {
          endSessionCallCount += 1;
          return EndSessionResponse(null);
        },
      );

      await client.logout();

      expect(endSessionCallCount, 0);
    });

    test('Test 8: logout() 은 어떤 경우에도 throw 하지 않는다 (graceful) — '
        'finally 블록의 outer 흐름 차단 0 (T-15-14 mitigation)', () async {
      final client = YahoojpSdkClient.forTest(
        clientId: 'test-client-id',
        redirectUrl: 'com.example.app:/oauth2redirect',
        authorize: (request) async {
          throw UnimplementedError('signIn 미호출');
        },
        endSession: (request) async {
          throw Exception('endSession endpoint missing');
        },
      );

      // 예외 0 — graceful (outer 흐름 차단 안 함).
      await client.logout();
    });
  });

  // ==========================================================================
  // Test 9-11: nonce 통계 — 100 회 generate 후 모두 22 char base64url 부합
  //          (T-15-11 mitigation — Spoofing nonce 예측 가능)
  // ==========================================================================
  group('YahoojpSdkClient — nonce 통계 회귀 (T-15-11)', () {
    test('Test 9: 100 회 signIn 호출 — 모든 nonce 가 22 char base64Url 부합 + '
        '모두 unique (Random.secure 검증)', () async {
      final nonces = <String>{};
      for (var i = 0; i < 100; i++) {
        final client = YahoojpSdkClient.forTest(
          clientId: 'test-client-id',
          redirectUrl: 'com.example.app:/oauth2redirect',
          authorize: (request) async {
            nonces.add(request.nonce ?? '');
            return _buildTokenResponse(idToken: 'JWT');
          },
          endSession: (request) async {
            throw UnimplementedError('endSession 미호출');
          },
        );
        await client.signIn();
      }
      expect(
        nonces.length,
        100,
        reason:
            '100 회 generate → 100 unique nonce (Random.secure 16 bytes '
            '→ 2^128 entropy 로 collision 사실상 0)',
      );
      // 모든 nonce 가 22 char base64Url 부합 검증.
      final pattern = RegExp(r'^[A-Za-z0-9_-]{22}$');
      for (final n in nonces) {
        expect(
          pattern.hasMatch(n),
          isTrue,
          reason: '$n 가 22 char base64url 부합해야 한다',
        );
      }
    });
  });
}
