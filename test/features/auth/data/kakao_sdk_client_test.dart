import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/features/auth/data/kakao_sdk_client.dart';

/// Kakao SDK [OAuthToken] fake — `idToken` 값만 통제.
///
/// 실제 [OAuthToken] 은 `accessToken` 등 필수 인자를 강제하므로 테스트 편의를
/// 위해 [OAuthToken] 을 implements 한 fake 를 사용한다.
class _FakeOAuthToken extends Fake implements OAuthToken {
  _FakeOAuthToken({this.idToken});

  @override
  final String? idToken;
}

void main() {
  group('KakaoSdkClient.signIn', () {
    test('KakaoTalk 설치 + loginWithKakaoTalk 성공 → ID Token + nonce 반환', () async {
      final calls = <String>[];
      String? talkNonce;
      List<String>? talkServiceTerms;

      final client = KakaoSdkClient.forTest(
        isInstalled: () async => true,
        loginWithTalk: ({serviceTerms, nonce}) async {
          calls.add('talk');
          talkNonce = nonce;
          talkServiceTerms = serviceTerms;
          return _FakeOAuthToken(idToken: 'IDT-talk');
        },
        loginWithAccount: ({serviceTerms, nonce}) async {
          calls.add('account');
          return _FakeOAuthToken(idToken: 'IDT-account');
        },
      );

      final result = await client.signIn();

      expect(result, isNotNull);
      expect(result!.idToken, 'IDT-talk');
      expect(result.nonce, isNotEmpty);
      expect(calls, ['talk']);
      // SDK 인자에도 같은 nonce 가 전달됐는지 (Pitfall 2 single nonce).
      expect(talkNonce, result.nonce);
      expect(talkServiceTerms, ['openid']);
    });

    test('KakaoTalk 미설치 → loginWithKakaoAccount 호출 + 동일 nonce 전달', () async {
      final calls = <String>[];
      String? accountNonce;
      List<String>? accountServiceTerms;

      final client = KakaoSdkClient.forTest(
        isInstalled: () async => false,
        loginWithTalk: ({serviceTerms, nonce}) async {
          calls.add('talk');
          return _FakeOAuthToken(idToken: 'IDT-talk');
        },
        loginWithAccount: ({serviceTerms, nonce}) async {
          calls.add('account');
          accountNonce = nonce;
          accountServiceTerms = serviceTerms;
          return _FakeOAuthToken(idToken: 'IDT-account');
        },
      );

      final result = await client.signIn();

      expect(result, isNotNull);
      expect(result!.idToken, 'IDT-account');
      expect(calls, ['account']);
      expect(accountNonce, result.nonce);
      expect(accountServiceTerms, ['openid']);
    });

    test('KakaoTalk 설치 + loginWithKakaoTalk throw → loginWithKakaoAccount '
        'fallback (D-01)', () async {
      final calls = <String>[];

      final client = KakaoSdkClient.forTest(
        isInstalled: () async => true,
        loginWithTalk: ({serviceTerms, nonce}) async {
          calls.add('talk');
          throw PlatformException(code: 'NOT_INSTALLED');
        },
        loginWithAccount: ({serviceTerms, nonce}) async {
          calls.add('account');
          return _FakeOAuthToken(idToken: 'IDT-fallback');
        },
      );

      final result = await client.signIn();

      expect(result, isNotNull);
      expect(result!.idToken, 'IDT-fallback');
      expect(calls, ['talk', 'account']);
    });

    test('사용자 취소 (PlatformException CANCELED) → null 반환 (D-05)', () async {
      final client = KakaoSdkClient.forTest(
        isInstalled: () async => false,
        loginWithTalk: ({serviceTerms, nonce}) async =>
            _FakeOAuthToken(idToken: 'IDT'),
        loginWithAccount: ({serviceTerms, nonce}) async {
          throw PlatformException(code: 'CANCELED');
        },
      );

      final result = await client.signIn();

      expect(result, isNull);
    });

    test('사용자 취소 (KakaoClientException cancelled) → null 반환 '
        '(D-05 보조)', () async {
      final client = KakaoSdkClient.forTest(
        isInstalled: () async => false,
        loginWithTalk: ({serviceTerms, nonce}) async =>
            _FakeOAuthToken(idToken: 'IDT'),
        loginWithAccount: ({serviceTerms, nonce}) async {
          throw KakaoClientException(
            ClientErrorCause.cancelled,
            'User cancelled',
          );
        },
      );

      final result = await client.signIn();

      expect(result, isNull);
    });

    test('idToken null (Pitfall 1 OIDC 미활성화) → ServiceUnavailable '
        'throw', () async {
      final client = KakaoSdkClient.forTest(
        isInstalled: () async => false,
        loginWithTalk: ({serviceTerms, nonce}) async =>
            _FakeOAuthToken(idToken: 'IDT'),
        loginWithAccount: ({serviceTerms, nonce}) async =>
            _FakeOAuthToken(),
      );

      await expectLater(client.signIn(), throwsA(isA<ServiceUnavailable>()));
    });

    test('두 번 호출 시 매 호출마다 nonce 가 다름 (Random.secure 검증)', () async {
      final client = KakaoSdkClient.forTest(
        isInstalled: () async => false,
        loginWithTalk: ({serviceTerms, nonce}) async =>
            _FakeOAuthToken(idToken: 'IDT'),
        loginWithAccount: ({serviceTerms, nonce}) async =>
            _FakeOAuthToken(idToken: 'IDT'),
      );

      final r1 = await client.signIn();
      final r2 = await client.signIn();

      expect(r1, isNotNull);
      expect(r2, isNotNull);
      expect(r1!.nonce, isNot(r2!.nonce));
    });

    test('비-CANCELED PlatformException 은 rethrow 된다', () async {
      final client = KakaoSdkClient.forTest(
        isInstalled: () async => false,
        loginWithTalk: ({serviceTerms, nonce}) async =>
            _FakeOAuthToken(idToken: 'IDT'),
        loginWithAccount: ({serviceTerms, nonce}) async {
          throw PlatformException(code: 'NETWORK_ERROR');
        },
      );

      await expectLater(client.signIn(), throwsA(isA<PlatformException>()));
    });
  });
}
