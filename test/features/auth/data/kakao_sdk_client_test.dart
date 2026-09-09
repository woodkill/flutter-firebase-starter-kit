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
    test(
      'KakaoTalk 설치 + loginWithKakaoTalk 성공 → ID Token + nonce 반환',
      () async {
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
          logout: () async {},
        );

        final result = await client.signIn();

        expect(result, isNotNull);
        expect(result!.idToken, 'IDT-talk');
        expect(result.nonce, isNotEmpty);
        expect(calls, ['talk']);
        // SDK 인자에도 같은 nonce 가 전달됐는지 (Pitfall 2 single nonce).
        expect(talkNonce, result.nonce);
        expect(talkServiceTerms, ['openid']);
      },
    );

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
        logout: () async {},
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
        logout: () async {},
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
        logout: () async {},
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
        logout: () async {},
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
        loginWithAccount: ({serviceTerms, nonce}) async => _FakeOAuthToken(),
        logout: () async {},
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
        logout: () async {},
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
        logout: () async {},
      );

      await expectLater(client.signIn(), throwsA(isA<PlatformException>()));
    });
  });

  group(
    'KakaoSdkClient D-56 profile_image retroactive (T-13-KAKAO-RETRO-D56)',
    () {
      // Phase 13 Decision #6 채택 = 대안 1 (Console only) — Kakao Console 의
      // 동의 항목 활성화만으로 ID Token 의 `picture` claim 자동 포함 (Kakao
      // Developers RestAPI ID Token Payload spec 인용:
      // https://developers.kakao.com/docs/ko/kakaologin/rest-api — picture
      // 필드 = "URL of the user's profile picture. Requires consent for
      // profile information or profile picture").
      //
      // 따라서 kakao_sdk_client.dart 의 `signIn()` 본문 `serviceTerms` 인자에
      // 'profile_image' 추가 불필요. 본 group 은 serviceTerms 가 'openid' 한
      // 토큰만 유지되는 회귀 가드 (Decision #6 대안 1 fix point).

      test(
        'T-13-KAKAO-RETRO-D56-SCOPE-CONSOLE-ONLY-01: serviceTerms = '
        "['openid'] 만 유지 (profile_image 추가 인자 없음 — Console only 정책)",
        () async {
          List<String>? capturedTalkServiceTerms;
          List<String>? capturedAccountServiceTerms;

          final clientInstalled = KakaoSdkClient.forTest(
            isInstalled: () async => true,
            loginWithTalk: ({serviceTerms, nonce}) async {
              capturedTalkServiceTerms = serviceTerms;
              return _FakeOAuthToken(idToken: 'IDT');
            },
            loginWithAccount: ({serviceTerms, nonce}) async =>
                _FakeOAuthToken(idToken: 'IDT'),
            logout: () async {},
          );
          await clientInstalled.signIn();
          expect(capturedTalkServiceTerms, ['openid']);
          // profile_image / picture 등 추가 인자 부재 검증 (D-56 대안 1 정책).
          expect(capturedTalkServiceTerms, isNot(contains('profile_image')));
          expect(capturedTalkServiceTerms, isNot(contains('picture')));

          final clientNotInstalled = KakaoSdkClient.forTest(
            isInstalled: () async => false,
            loginWithTalk: ({serviceTerms, nonce}) async =>
                _FakeOAuthToken(idToken: 'IDT'),
            loginWithAccount: ({serviceTerms, nonce}) async {
              capturedAccountServiceTerms = serviceTerms;
              return _FakeOAuthToken(idToken: 'IDT');
            },
            logout: () async {},
          );
          await clientNotInstalled.signIn();
          expect(capturedAccountServiceTerms, ['openid']);
          expect(capturedAccountServiceTerms, isNot(contains('profile_image')));
        },
      );

      test(
        'T-13-KAKAO-RETRO-D56-PROFILE-FALLBACK-01: idToken 만 반환 — picture '
        'claim 부재 시에도 정상 처리 (Phase 13 사용처 0, Phase 17/18 deferred)',
        () async {
          // KakaoSdkClient 의 signIn() 은 idToken + nonce 만 반환하고 picture
          // claim 을 직접 다루지 않는다 (response 단위 PII 금지 정책 일관 —
          // D-51). Console 동의 항목 retroactive 갱신은 ID Token claim 에 picture
          // 추가될 뿐, 본 wrapper 의 코드 변경 0건. 회귀 가드는 idToken 단일
          // 인터페이스 보존 검증.
          final client = KakaoSdkClient.forTest(
            isInstalled: () async => false,
            loginWithTalk: ({serviceTerms, nonce}) async =>
                _FakeOAuthToken(idToken: 'IDT'),
            loginWithAccount: ({serviceTerms, nonce}) async =>
                _FakeOAuthToken(idToken: 'IDT-no-picture-claim'),
            logout: () async {},
          );

          final result = await client.signIn();

          expect(result, isNotNull);
          expect(result!.idToken, 'IDT-no-picture-claim');
          // KakaoSignInResult 는 idToken + nonce 만 노출 — picture claim 파싱
          // 책임 부재 (Phase 13 단계 미사용, Phase 17/18 forward).
          expect(result.nonce, isNotEmpty);
        },
      );
    },
  );

  group('KakaoSdkClient.logout D-57 retroactive (T-13-KAKAO-RETRO)', () {
    test('T-13-KAKAO-RETRO-LOGOUT-CLIENT-01: logout → '
        'UserApi.instance.logout 호출', () async {
      var logoutCalled = false;
      final client = KakaoSdkClient.forTest(
        isInstalled: () async => false,
        loginWithTalk: ({serviceTerms, nonce}) async =>
            _FakeOAuthToken(idToken: 'IDT'),
        loginWithAccount: ({serviceTerms, nonce}) async =>
            _FakeOAuthToken(idToken: 'IDT'),
        logout: () async {
          logoutCalled = true;
        },
      );

      await client.logout();
      expect(logoutCalled, isTrue);
    });

    test('T-13-KAKAO-RETRO-LOGOUT-CLIENT-02: logout 실패 → '
        'graceful (throw 안 함)', () async {
      final client = KakaoSdkClient.forTest(
        isInstalled: () async => false,
        loginWithTalk: ({serviceTerms, nonce}) async =>
            _FakeOAuthToken(idToken: 'IDT'),
        loginWithAccount: ({serviceTerms, nonce}) async =>
            _FakeOAuthToken(idToken: 'IDT'),
        logout: () async {
          throw Exception('SDK error');
        },
      );

      // throw 안 함 검증 — graceful (debugPrint).
      await client.logout();
    });
  });
}
