// ignore_for_file: lines_longer_than_80_chars
//
// debug reauth-login-auto-merge (2026-09-17) — 재인증 전용 repository 경로.
//
// 재인증 로그인 화면(/login?reauth=1)은 일반 로그인(signInWith… ·
// signInWithEmailAndPassword)을 그대로 호출해 다른 계정 전환 · 같은 email 자동
// 합류 · Custom Token 무동의 연결이 가능했다. 재인증 경로는 **현재 계정 그대로**
// auth_time 만 갱신해야 하므로 다음을 잠근다.
//
//   RA-G*: Google — 선택 계정 ID(sub) 를 현재 계정 google.com 연결과 사전 대조 후
//          reauthenticateWithCredential (signInWithCredential 0)
//   RA-A*: Apple — reauthenticateWithProvider (signInWithProvider 0)
//   RA-F*: Facebook — reauthenticateWithCredential
//   RA-C*: Custom Token 4종 — callable 응답 uid 대조 후 signInWithCustomToken,
//          서버 caller_identity_mismatch → ReauthUserMismatch
//   RA-P*: 비밀번호 — 현재 계정 email 로 reauthenticateWithCredential
//   RA-X*: 공통 가드 (익명 · 미로그인 · email provider 인자 · race-fix 1:1)
//   RA-R*: native 3종 실행 직전 서버 기준 재확인 — SDK 캐시 providerData 가 서버보다
//          오래돼도(앱 밖 해제) IdP 를 부르지 않는다 (실기기 D1 Evidence 21 · 22).
//          fixture 는 SDK reload 계약을 따른다: 기존 fb.User 객체는 갱신되지 않고
//          `FirebaseAuth.currentUser` 가 새 객체로 교체된다.

import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/features/auth/application/social_link_in_progress.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/data/kakao_sdk_client.dart';
import 'package:flutter_starter_kit/features/auth/data/line_sdk_client.dart';
import 'package:flutter_starter_kit/features/auth/data/naver_sdk_client.dart';
import 'package:flutter_starter_kit/features/auth/data/naver_sign_in_result.dart';
import 'package:flutter_starter_kit/features/auth/data/yahoojp_sdk_client.dart';

import 'auth_test_fakes.dart';

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockUserCredential extends Mock implements fb.UserCredential {}

class _MockFbUser extends Mock implements fb.User {}

class _MockUserInfo extends Mock implements fb.UserInfo {}

class _MockUserMetadata extends Mock implements fb.UserMetadata {}

class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

class _MockGoogleSignInAccount extends Mock implements GoogleSignInAccount {}

class _MockGoogleSignInAuthentication extends Mock
    implements GoogleSignInAuthentication {}

class _MockFacebookAuth extends Mock implements FacebookAuth {}

class _MockLoginResult extends Mock implements LoginResult {}

class _MockSocialLinkInProgress extends Mock implements SocialLinkInProgress {}

class _MockKakaoSdkClient extends Mock implements KakaoSdkClient {}

class _MockNaverSdkClient extends Mock implements NaverSdkClient {}

class _MockLineSdkClient extends Mock implements LineSdkClient {}

class _MockYahoojpSdkClient extends Mock implements YahoojpSdkClient {}

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class _MockHttpsCallable extends Mock implements HttpsCallable {}

class _MockHttpsCallableResult extends Mock
    implements HttpsCallableResult<Map<String, dynamic>> {}

class _FakeAuthCredential extends Fake implements fb.AuthCredential {}

const String _currentUid = 'current-uid-U';
const String _currentEmail = 'current-user@example.com';
const String _linkedGoogleSub = 'google-sub-of-U';

void main() {
  late _MockFirebaseAuth mockAuth;
  late _MockGoogleSignIn mockGoogleSignIn;
  late _MockFacebookAuth mockFacebookAuth;
  late _MockSocialLinkInProgress mockSocialLinkInProgress;
  late _MockKakaoSdkClient mockKakaoSdkClient;
  late _MockNaverSdkClient mockNaverSdkClient;
  late _MockLineSdkClient mockLineSdkClient;
  late _MockYahoojpSdkClient mockYahoojpSdkClient;
  late _MockFirebaseFunctions mockFunctions;
  late _MockHttpsCallable mockCallable;
  late _MockFbUser mockCurrentUser;
  late _MockUserMetadata mockMetadata;
  late _MockUserCredential currentCredential;
  late AuthRepository repository;

  /// `FirebaseAuth.currentUser` 가 돌려줄 객체 — SDK `reload()` 는 기존 객체를
  /// 고치지 않고 이 값을 새 객체로 바꾼다 (RA-R stub 이 교체).
  fb.User? authCurrentUser;

  setUpAll(() {
    registerFallbackValue(_FakeAuthCredential());
    registerFallbackValue(fb.AppleAuthProvider());
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(LoginTracking.enabled);
    registerFallbackValue(LoginBehavior.nativeWithFallback);
    registerFallbackValue(const <String>[]);
  });

  /// 현재 계정 [mockCurrentUser] 와 같은 uid 를 돌려주는 UserCredential.
  _MockUserCredential credentialOf(fb.User user) {
    final credential = _MockUserCredential();
    when(() => credential.user).thenReturn(user);
    return credential;
  }

  /// [providerId] · [uid] 를 가진 providerData 항목.
  _MockUserInfo providerInfo(String providerId, String uid) {
    final info = _MockUserInfo();
    when(() => info.providerId).thenReturn(providerId);
    when(() => info.uid).thenReturn(uid);
    return info;
  }

  setUp(() {
    mockAuth = _MockFirebaseAuth();
    mockGoogleSignIn = _MockGoogleSignIn();
    mockFacebookAuth = _MockFacebookAuth();
    mockSocialLinkInProgress = _MockSocialLinkInProgress();
    mockKakaoSdkClient = _MockKakaoSdkClient();
    mockNaverSdkClient = _MockNaverSdkClient();
    mockLineSdkClient = _MockLineSdkClient();
    mockYahoojpSdkClient = _MockYahoojpSdkClient();
    mockFunctions = _MockFirebaseFunctions();
    mockCallable = _MockHttpsCallable();
    mockCurrentUser = _MockFbUser();
    mockMetadata = _MockUserMetadata();

    repository = AuthRepository(
      mockAuth,
      mockGoogleSignIn,
      mockFacebookAuth,
      mockSocialLinkInProgress,
      mockKakaoSdkClient,
      mockFunctions,
      mockNaverSdkClient,
      mockLineSdkClient,
      mockYahoojpSdkClient,
      () async {},
    );

    when(() => mockCurrentUser.uid).thenReturn(_currentUid);
    when(() => mockCurrentUser.email).thenReturn(_currentEmail);
    when(() => mockCurrentUser.emailVerified).thenReturn(true);
    when(() => mockCurrentUser.displayName).thenReturn('Current User');
    when(() => mockCurrentUser.photoURL).thenReturn(null);
    when(() => mockCurrentUser.isAnonymous).thenReturn(false);
    when(() => mockCurrentUser.metadata).thenReturn(mockMetadata);
    when(() => mockMetadata.creationTime).thenReturn(DateTime.utc(2026, 1, 1));
    // mocktail 은 when(...) 진행 중 다른 when 호출을 금지하므로 먼저 만든다.
    final linkedProviders = <fb.UserInfo>[
      providerInfo('google.com', _linkedGoogleSub),
      providerInfo('apple.com', 'apple-sub-of-U'),
      providerInfo('password', _currentEmail),
    ];
    when(() => mockCurrentUser.providerData).thenReturn(linkedProviders);
    authCurrentUser = mockCurrentUser;
    when(() => mockAuth.currentUser).thenAnswer((_) => authCurrentUser);
    // 기본: 서버 상태 == 캐시 (reload 가 목록을 바꾸지 않는다).
    when(() => mockCurrentUser.reload()).thenAnswer((_) async {});
    // stub 응답 안에서 when 을 부르지 않도록 현재 계정 UserCredential 을 미리 만든다.
    currentCredential = credentialOf(mockCurrentUser);

    // 새 로그인 경로는 재인증에서 호출되면 안 된다 — 호출 시 성공처럼 보이게
    // 두어 "호출 0" 단언이 실제로 의미를 갖게 한다.
    when(
      () => mockAuth.signInWithCredential(any()),
    ).thenAnswer((_) async => currentCredential);
    when(
      () => mockAuth.signInWithProvider(any()),
    ).thenAnswer((_) async => currentCredential);
    when(
      () => mockAuth.signInWithEmailAndPassword(
        email: any(named: 'email'),
        password: any(named: 'password'),
      ),
    ).thenAnswer((_) async => currentCredential);

    when(() => mockKakaoSdkClient.logout()).thenAnswer((_) async {});
    when(() => mockNaverSdkClient.logout()).thenAnswer((_) async {});
    when(() => mockLineSdkClient.logout()).thenAnswer((_) async {});
    when(() => mockYahoojpSdkClient.logout()).thenAnswer((_) async {});
  });

  /// reload 뒤 서버 기준 사용자 — 현재 계정과 같은 uid, providerData 만 [infos].
  _MockFbUser reloadedUserWith(List<fb.UserInfo> infos) {
    final user = _MockFbUser();
    when(() => user.uid).thenReturn(_currentUid);
    when(() => user.email).thenReturn(_currentEmail);
    when(() => user.emailVerified).thenReturn(true);
    when(() => user.displayName).thenReturn('Current User');
    when(() => user.photoURL).thenReturn(null);
    when(() => user.isAnonymous).thenReturn(false);
    when(() => user.metadata).thenReturn(mockMetadata);
    when(() => user.providerData).thenReturn(infos);
    return user;
  }

  /// `current.reload()` 가 성공하며 `FirebaseAuth.currentUser` 를 [reloaded] 로
  /// 교체하도록 stub 한다 (firebase_auth_platform_interface 9.1.0
  /// `MethodChannelUser.reload` — 새 객체 대입 + userChanges 재방출).
  void stubReloadTo(fb.User? reloaded) {
    when(() => mockCurrentUser.reload()).thenAnswer((_) async {
      authCurrentUser = reloaded;
    });
  }

  /// Facebook Classic 로그인이 성공하도록 stub 한다.
  void stubFacebookClassicLogin() {
    final loginResult = _MockLoginResult();
    when(() => loginResult.status).thenReturn(LoginStatus.success);
    when(
      () => loginResult.accessToken,
    ).thenReturn(FakeClassicToken(tokenString: 'fb-access-token'));
    when(
      () => mockFacebookAuth.login(
        permissions: any(named: 'permissions'),
        loginTracking: any(named: 'loginTracking'),
        loginBehavior: any(named: 'loginBehavior'),
        nonce: any(named: 'nonce'),
      ),
    ).thenAnswer((_) async => loginResult);
  }

  /// Google 계정 선택기가 [accountId] 계정을 돌려주도록 stub 한다.
  void stubGoogleAccount(String accountId) {
    final account = _MockGoogleSignInAccount();
    final auth = _MockGoogleSignInAuthentication();
    when(
      () => mockGoogleSignIn.authenticate(),
    ).thenAnswer((_) async => account);
    when(() => account.id).thenReturn(accountId);
    when(() => account.authentication).thenReturn(auth);
    when(() => auth.idToken).thenReturn('google-id-token');
  }

  /// [callableName] callable 이 [data] 로 응답하도록 stub 한다.
  void stubCallableResponse(String callableName, Map<String, dynamic> data) {
    when(
      () => mockFunctions.httpsCallable(
        callableName,
        options: any(named: 'options'),
      ),
    ).thenReturn(mockCallable);
    final result = _MockHttpsCallableResult();
    when(() => result.data).thenReturn(data);
    when(
      () => mockCallable.call<Map<String, dynamic>>(any()),
    ).thenAnswer((_) async => result);
  }

  group('RA-G — Google', () {
    test(
      'RA-G1: 연결된 Google 계정 선택 → reauthenticateWithCredential 1회, 새 로그인 0',
      () async {
        stubGoogleAccount(_linkedGoogleSub);
        when(
          () => mockCurrentUser.reauthenticateWithCredential(any()),
        ).thenAnswer((_) async => currentCredential);

        final result = await repository.reauthenticate(AccountProvider.google);

        expect(result, isA<Success<dynamic>>());
        verify(
          () => mockCurrentUser.reauthenticateWithCredential(any()),
        ).called(1);
        verifyNever(() => mockAuth.signInWithCredential(any()));
      },
    );

    test(
      'RA-G2: 다른 Google 계정 선택 → ReauthUserMismatch, Firebase 호출 0 (trusted email 합류 경로 차단)',
      () async {
        stubGoogleAccount('google-sub-of-someone-else');

        final result = await repository.reauthenticate(AccountProvider.google);

        expect(
          (result! as Failure<dynamic>).exception,
          isA<ReauthUserMismatch>(),
        );
        verifyNever(() => mockCurrentUser.reauthenticateWithCredential(any()));
        verifyNever(() => mockAuth.signInWithCredential(any()));
      },
    );

    test('RA-G3: Google 계정 선택 취소 → null (no-op)', () async {
      when(() => mockGoogleSignIn.authenticate()).thenThrow(
        const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
      );

      final result = await repository.reauthenticate(AccountProvider.google);

      expect(result, isNull);
      verifyNever(() => mockAuth.signInWithCredential(any()));
    });
  });

  group('RA-A — Apple', () {
    test(
      'RA-A1: reauthenticateWithProvider 1회, signInWithProvider 0',
      () async {
        when(
          () => mockCurrentUser.reauthenticateWithProvider(any()),
        ).thenAnswer((_) async => currentCredential);

        final result = await repository.reauthenticate(AccountProvider.apple);

        expect(result, isA<Success<dynamic>>());
        verify(
          () => mockCurrentUser.reauthenticateWithProvider(any()),
        ).called(1);
        verifyNever(() => mockAuth.signInWithProvider(any()));
      },
    );

    test('RA-A2: user-mismatch → ReauthUserMismatch (세션 전환 없음)', () async {
      when(
        () => mockCurrentUser.reauthenticateWithProvider(any()),
      ).thenThrow(fb.FirebaseAuthException(code: 'user-mismatch'));

      final result = await repository.reauthenticate(AccountProvider.apple);

      expect(
        (result! as Failure<dynamic>).exception,
        isA<ReauthUserMismatch>(),
      );
      verifyNever(() => mockAuth.signInWithProvider(any()));
    });

    test(
      'RA-A3: user-not-found (연결 안 된 신규 identity) → ReauthUserMismatch',
      () async {
        when(
          () => mockCurrentUser.reauthenticateWithProvider(any()),
        ).thenThrow(fb.FirebaseAuthException(code: 'user-not-found'));

        final result = await repository.reauthenticate(AccountProvider.apple);

        expect(
          (result! as Failure<dynamic>).exception,
          isA<ReauthUserMismatch>(),
        );
      },
    );

    test('RA-A4: 사용자 취소 (canceled) → null', () async {
      when(
        () => mockCurrentUser.reauthenticateWithProvider(any()),
      ).thenThrow(fb.FirebaseAuthException(code: 'canceled'));

      final result = await repository.reauthenticate(AccountProvider.apple);

      expect(result, isNull);
    });
  });

  group('RA-F — Facebook', () {
    test(
      'RA-F1: Classic token → reauthenticateWithCredential 1회, signInWithCredential 0',
      () async {
        // 재인증 화면은 연결된 provider 만 노출한다 — facebook.com 연결 계정.
        final facebookLinked = <fb.UserInfo>[
          providerInfo('facebook.com', 'facebook-id-of-U'),
        ];
        when(() => mockCurrentUser.providerData).thenReturn(facebookLinked);
        stubFacebookClassicLogin();
        when(
          () => mockCurrentUser.reauthenticateWithCredential(any()),
        ).thenAnswer((_) async => currentCredential);

        final result = await repository.reauthenticate(
          AccountProvider.facebook,
        );

        expect(result, isA<Success<dynamic>>());
        verify(
          () => mockCurrentUser.reauthenticateWithCredential(any()),
        ).called(1);
        verifyNever(() => mockAuth.signInWithCredential(any()));
      },
    );
  });

  group('RA-C — Custom Token', () {
    test(
      'RA-C1: Kakao — 응답 uid == 현재 uid → signInWithCustomToken 1회 + SDK logout',
      () async {
        when(() => mockKakaoSdkClient.signIn()).thenAnswer(
          (_) async => const KakaoSignInResult(idToken: 'kakao-id', nonce: 'n'),
        );
        stubCallableResponse('kakaoCustomToken', <String, dynamic>{
          'customToken': 'ct-for-U',
          'uid': _currentUid,
          'isNewUser': false,
        });
        when(
          () => mockAuth.signInWithCustomToken('ct-for-U'),
        ).thenAnswer((_) async => currentCredential);

        final result = await repository.reauthenticate(AccountProvider.kakao);

        expect(result, isA<Success<dynamic>>());
        verify(() => mockAuth.signInWithCustomToken('ct-for-U')).called(1);
        verify(() => mockKakaoSdkClient.logout()).called(1);
      },
    );

    test(
      'RA-C2: Naver — 응답 uid 가 다른 계정 → ReauthUserMismatch, signInWithCustomToken 0 (세션 전환 차단)',
      () async {
        when(() => mockNaverSdkClient.signIn()).thenAnswer(
          (_) async => const NaverAppSignIn(accessToken: 'naver-at'),
        );
        stubCallableResponse('naverCustomToken', <String, dynamic>{
          'customToken': 'ct-for-V',
          'uid': 'other-uid-V',
          'isNewUser': false,
        });

        final result = await repository.reauthenticate(AccountProvider.naver);

        expect(
          (result! as Failure<dynamic>).exception,
          isA<ReauthUserMismatch>(),
        );
        verifyNever(() => mockAuth.signInWithCustomToken(any()));
        verify(() => mockNaverSdkClient.logout()).called(1);
      },
    );

    test('T-16.5-NAVER-REPO-02: Naver 웹 경로 재인증 → naverWebCustomToken '
        '{code, state} · 응답 uid 일치 시 signInWithCustomToken 1회', () async {
      when(() => mockNaverSdkClient.signIn()).thenAnswer(
        (_) async => const NaverWebSignIn(code: 'web-code', state: 'web-st'),
      );
      stubCallableResponse('naverWebCustomToken', <String, dynamic>{
        'customToken': 'ct-web-U',
        'uid': _currentUid,
        'isNewUser': false,
      });
      when(
        () => mockAuth.signInWithCustomToken('ct-web-U'),
      ).thenAnswer((_) async => currentCredential);

      final result = await repository.reauthenticate(AccountProvider.naver);

      expect(result, isA<Success<dynamic>>());
      verifyNever(
        () => mockFunctions.httpsCallable(
          'naverCustomToken',
          options: any(named: 'options'),
        ),
      );
      verify(
        () => mockCallable.call<Map<String, dynamic>>(<String, dynamic>{
          'code': 'web-code',
          'state': 'web-st',
        }),
      ).called(1);
      verify(() => mockAuth.signInWithCustomToken('ct-web-U')).called(1);
      verify(() => mockNaverSdkClient.logout()).called(1);
    });

    test('T-16.5-NAVER-REPO-WR01c: Naver 웹 경로 재인증도 naverWebCustomToken '
        'callable timeout 20초 (로그인과 같은 예산)', () async {
      when(() => mockNaverSdkClient.signIn()).thenAnswer(
        (_) async => const NaverWebSignIn(code: 'web-code', state: 'web-st'),
      );
      stubCallableResponse('naverWebCustomToken', <String, dynamic>{
        'customToken': 'ct-web-U',
        'uid': _currentUid,
        'isNewUser': false,
      });
      when(
        () => mockAuth.signInWithCustomToken('ct-web-U'),
      ).thenAnswer((_) async => currentCredential);

      await repository.reauthenticate(AccountProvider.naver);

      final captured =
          verify(
                () => mockFunctions.httpsCallable(
                  'naverWebCustomToken',
                  options: captureAny(named: 'options'),
                ),
              ).captured.single
              as HttpsCallableOptions;
      expect(captured.timeout, const Duration(seconds: 20));
    });

    test(
      'RA-C3: LINE — 서버 permission-denied + caller_identity_mismatch → ReauthUserMismatch',
      () async {
        when(() => mockLineSdkClient.signIn()).thenAnswer(
          (_) async => const LineSignInResult(idToken: 'line-id', nonce: 'n'),
        );
        when(
          () => mockFunctions.httpsCallable(
            'lineCustomToken',
            options: any(named: 'options'),
          ),
        ).thenReturn(mockCallable);
        when(() => mockCallable.call<Map<String, dynamic>>(any())).thenThrow(
          FirebaseFunctionsException(
            message: 'errorReauthUserMismatch',
            code: 'permission-denied',
            details: const <String, dynamic>{
              'reason': 'caller_identity_mismatch',
            },
          ),
        );

        final result = await repository.reauthenticate(AccountProvider.line);

        expect(
          (result! as Failure<dynamic>).exception,
          isA<ReauthUserMismatch>(),
        );
        verifyNever(() => mockAuth.signInWithCustomToken(any()));
      },
    );

    test('RA-C4: Yahoo!JP — SDK 취소 → null, callable 0', () async {
      when(() => mockYahoojpSdkClient.signIn()).thenAnswer((_) async => null);

      final result = await repository.reauthenticate(AccountProvider.yahoojp);

      expect(result, isNull);
      verifyNever(
        () =>
            mockFunctions.httpsCallable(any(), options: any(named: 'options')),
      );
      verify(() => mockYahoojpSdkClient.logout()).called(1);
    });
  });

  group('RA-P — 비밀번호', () {
    test(
      'RA-P1: 현재 계정 email 로 reauthenticateWithCredential, signInWithEmailAndPassword 0',
      () async {
        when(
          () => mockCurrentUser.reauthenticateWithCredential(any()),
        ).thenAnswer((_) async => currentCredential);

        final result = await repository.reauthenticateWithPassword(
          password: 'correct-password',
        );

        expect(result, isA<Success<dynamic>>());
        final captured = verify(
          () => mockCurrentUser.reauthenticateWithCredential(captureAny()),
        ).captured.single;
        expect(captured, isA<fb.EmailAuthCredential>());
        expect((captured as fb.EmailAuthCredential).email, _currentEmail);
        verifyNever(
          () => mockAuth.signInWithEmailAndPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        );
      },
    );

    test('RA-P2: 틀린 비밀번호 (invalid-credential) → InvalidCredentials', () async {
      when(
        () => mockCurrentUser.reauthenticateWithCredential(any()),
      ).thenThrow(fb.FirebaseAuthException(code: 'invalid-credential'));

      final result = await repository.reauthenticateWithPassword(
        password: 'wrong-password',
      );

      expect((result as Failure<dynamic>).exception, isA<InvalidCredentials>());
    });
  });

  group('RA-R — native 실행 직전 서버 기준 재확인 (stale providerData)', () {
    test(
      'RA-R1: Apple — 캐시 [apple.com] · reload 뒤 서버 [] → ReauthMethodUnavailable, IdP · Firebase 재인증 호출 0',
      () async {
        final reloaded = reloadedUserWith(<fb.UserInfo>[]);
        stubReloadTo(reloaded);
        when(
          () => mockCurrentUser.reauthenticateWithProvider(any()),
        ).thenAnswer((_) async => currentCredential);
        when(
          () => reloaded.reauthenticateWithProvider(any()),
        ).thenAnswer((_) async => currentCredential);

        final result = await repository.reauthenticate(AccountProvider.apple);

        expect(
          (result! as Failure<dynamic>).exception,
          isA<ReauthMethodUnavailable>(),
        );
        verify(() => mockCurrentUser.reload()).called(1);
        verifyNever(() => mockCurrentUser.reauthenticateWithProvider(any()));
        verifyNever(() => reloaded.reauthenticateWithProvider(any()));
        verifyNever(() => mockAuth.signInWithProvider(any()));
      },
    );

    test(
      'RA-R2: Google — 캐시 google.com · reload 뒤 서버 [] → ReauthMethodUnavailable, 계정 선택기 호출 0',
      () async {
        stubGoogleAccount(_linkedGoogleSub);
        final reloaded = reloadedUserWith(<fb.UserInfo>[]);
        stubReloadTo(reloaded);
        when(
          () => mockCurrentUser.reauthenticateWithCredential(any()),
        ).thenAnswer((_) async => currentCredential);

        final result = await repository.reauthenticate(AccountProvider.google);

        expect(
          (result! as Failure<dynamic>).exception,
          isA<ReauthMethodUnavailable>(),
        );
        verifyNever(() => mockGoogleSignIn.authenticate());
        verifyNever(() => mockCurrentUser.reauthenticateWithCredential(any()));
        verifyNever(() => mockAuth.signInWithCredential(any()));
      },
    );

    test(
      'RA-R3: Facebook — 캐시 facebook.com · reload 뒤 서버 [] → ReauthMethodUnavailable, Facebook 로그인 호출 0',
      () async {
        final facebookLinked = <fb.UserInfo>[
          providerInfo('facebook.com', 'facebook-id-of-U'),
        ];
        when(() => mockCurrentUser.providerData).thenReturn(facebookLinked);
        stubFacebookClassicLogin();
        final reloaded = reloadedUserWith(<fb.UserInfo>[]);
        stubReloadTo(reloaded);
        when(
          () => mockCurrentUser.reauthenticateWithCredential(any()),
        ).thenAnswer((_) async => currentCredential);

        final result = await repository.reauthenticate(
          AccountProvider.facebook,
        );

        expect(
          (result! as Failure<dynamic>).exception,
          isA<ReauthMethodUnavailable>(),
        );
        verifyNever(
          () => mockFacebookAuth.login(
            permissions: any(named: 'permissions'),
            loginTracking: any(named: 'loginTracking'),
            loginBehavior: any(named: 'loginBehavior'),
            nonce: any(named: 'nonce'),
          ),
        );
        verifyNever(() => mockCurrentUser.reauthenticateWithCredential(any()));
      },
    );

    // reload 실패 = 서버 기준 확인 불가 → fail-closed. 네트워크 오류도 기존
    // NoInternetConnection 이 아니라 승인된 Q7 문구로 간다 (사용자 결정 A).
    for (final reloadError in <Object>[
      fb.FirebaseAuthException(code: 'network-request-failed'),
      fb.FirebaseAuthException(code: 'user-token-expired'),
      fb.FirebaseAuthException(code: 'user-not-found'),
      fb.FirebaseAuthException(code: 'user-disabled'),
      StateError('platform channel failure'),
    ]) {
      final label = reloadError is fb.FirebaseAuthException
          ? reloadError.code
          : reloadError.runtimeType.toString();
      test(
        'RA-R4 ($label): reload 예외 → ReauthMethodUnavailable, Apple 재인증 호출 0',
        () async {
          // SDK 는 pigeon 비동기 응답의 오류로 전달한다 (Future error).
          when(
            () => mockCurrentUser.reload(),
          ).thenAnswer((_) => Future<void>.error(reloadError));
          when(
            () => mockCurrentUser.reauthenticateWithProvider(any()),
          ).thenAnswer((_) async => currentCredential);

          final result = await repository.reauthenticate(AccountProvider.apple);

          expect(
            (result! as Failure<dynamic>).exception,
            isA<ReauthMethodUnavailable>(),
          );
          verifyNever(() => mockCurrentUser.reauthenticateWithProvider(any()));
          verify(() => mockSocialLinkInProgress.begin()).called(1);
          verify(() => mockSocialLinkInProgress.end()).called(1);
        },
      );
    }

    test(
      'RA-R5: reload 뒤 currentUser 가 없음 (세션 종료) → ReauthMethodUnavailable, IdP 0',
      () async {
        stubReloadTo(null);
        when(
          () => mockCurrentUser.reauthenticateWithProvider(any()),
        ).thenAnswer((_) async => currentCredential);

        final result = await repository.reauthenticate(AccountProvider.apple);

        expect(
          (result! as Failure<dynamic>).exception,
          isA<ReauthMethodUnavailable>(),
        );
        verifyNever(() => mockCurrentUser.reauthenticateWithProvider(any()));
      },
    );

    test(
      'RA-R6: Google — 캐시에는 없고 서버에는 연결 → reload 된 providerData 로 대조해 재인증 성공',
      () async {
        final cacheWithoutGoogle = <fb.UserInfo>[
          providerInfo('apple.com', 'apple-sub-of-U'),
        ];
        when(() => mockCurrentUser.providerData).thenReturn(cacheWithoutGoogle);
        final serverLinked = <fb.UserInfo>[
          providerInfo('google.com', _linkedGoogleSub),
        ];
        final reloaded = reloadedUserWith(serverLinked);
        final reloadedCredential = credentialOf(reloaded);
        stubReloadTo(reloaded);
        stubGoogleAccount(_linkedGoogleSub);
        when(
          () => mockCurrentUser.reauthenticateWithCredential(any()),
        ).thenAnswer((_) async => reloadedCredential);
        when(
          () => reloaded.reauthenticateWithCredential(any()),
        ).thenAnswer((_) async => reloadedCredential);

        final result = await repository.reauthenticate(AccountProvider.google);

        expect(result, isA<Success<dynamic>>());
        verify(() => mockGoogleSignIn.authenticate()).called(1);
        verifyNever(() => mockAuth.signInWithCredential(any()));
      },
    );

    test(
      'RA-R7 (대조군): Custom Token 은 reload 하지 않는다 — 원천은 Firestore linkedProviders + 서버 가드',
      () async {
        when(() => mockKakaoSdkClient.signIn()).thenAnswer(
          (_) async => const KakaoSignInResult(idToken: 'kakao-id', nonce: 'n'),
        );
        stubCallableResponse('kakaoCustomToken', <String, dynamic>{
          'customToken': 'ct-for-U',
          'uid': _currentUid,
          'isNewUser': false,
        });
        when(
          () => mockAuth.signInWithCustomToken('ct-for-U'),
        ).thenAnswer((_) async => currentCredential);

        final result = await repository.reauthenticate(AccountProvider.kakao);

        expect(result, isA<Success<dynamic>>());
        verifyNever(() => mockCurrentUser.reload());
      },
    );
  });

  group('RA-X — 공통 가드', () {
    test('RA-X1: 익명 currentUser → UnknownException, IdP SDK 호출 0', () async {
      when(() => mockCurrentUser.isAnonymous).thenReturn(true);

      final result = await repository.reauthenticate(AccountProvider.kakao);

      expect((result! as Failure<dynamic>).exception, isA<UnknownException>());
      verifyNever(() => mockKakaoSdkClient.signIn());
    });

    test(
      'RA-X2: email provider 는 reauthenticate 인자로 받지 않는다 (ArgumentError)',
      () async {
        await expectLater(
          repository.reauthenticate(AccountProvider.email),
          throwsArgumentError,
        );
      },
    );

    test('RA-X3: race-fix begin/end 1:1 (실패 경로 포함)', () async {
      when(
        () => mockCurrentUser.reauthenticateWithProvider(any()),
      ).thenThrow(fb.FirebaseAuthException(code: 'network-request-failed'));

      final result = await repository.reauthenticate(AccountProvider.apple);

      expect(
        (result! as Failure<dynamic>).exception,
        isA<NoInternetConnection>(),
      );
      verify(() => mockSocialLinkInProgress.begin()).called(1);
      verify(() => mockSocialLinkInProgress.end()).called(1);
    });

    test(
      'RA-X4: 일반 Kakao 로그인도 caller_identity_mismatch 를 ReauthUserMismatch 로 매핑 (App Check permission-denied 는 불변)',
      () async {
        when(() => mockKakaoSdkClient.signIn()).thenAnswer(
          (_) async => const KakaoSignInResult(idToken: 'kakao-id', nonce: 'n'),
        );
        when(
          () => mockFunctions.httpsCallable(
            'kakaoCustomToken',
            options: any(named: 'options'),
          ),
        ).thenReturn(mockCallable);
        when(() => mockCallable.call<Map<String, dynamic>>(any())).thenThrow(
          FirebaseFunctionsException(
            message: 'errorReauthUserMismatch',
            code: 'permission-denied',
            details: const <String, dynamic>{
              'reason': 'caller_identity_mismatch',
            },
          ),
        );
        final mismatch = await repository.signInWithKakao();
        expect(
          (mismatch! as Failure<dynamic>).exception,
          isA<ReauthUserMismatch>(),
        );

        when(() => mockCallable.call<Map<String, dynamic>>(any())).thenThrow(
          FirebaseFunctionsException(
            message: 'app check',
            code: 'permission-denied',
          ),
        );
        final appCheck = await repository.signInWithKakao();
        expect(
          (appCheck! as Failure<dynamic>).exception,
          isA<ServiceUnavailable>(),
        );
      },
    );
  });
}
