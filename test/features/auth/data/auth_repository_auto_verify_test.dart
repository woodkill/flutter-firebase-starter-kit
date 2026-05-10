// ignore_for_file: lines_longer_than_80_chars

import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/features/auth/application/social_link_in_progress.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/data/kakao_sdk_client.dart';
import 'package:flutter_starter_kit/features/auth/data/naver_sdk_client.dart';

import 'auth_test_fakes.dart';

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockUserCredential extends Mock implements fb.UserCredential {}

class _MockFbUser extends Mock implements fb.User {}

class _MockUserMetadata extends Mock implements fb.UserMetadata {}

class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

class _MockGoogleSignInAccount extends Mock implements GoogleSignInAccount {}

class _MockFacebookAuth extends Mock implements FacebookAuth {}

class _MockUserInfo extends Mock implements fb.UserInfo {}

class _MockSocialLinkInProgress extends Mock implements SocialLinkInProgress {}

class _MockKakaoSdkClient extends Mock implements KakaoSdkClient {}

class _MockNaverSdkClient extends Mock implements NaverSdkClient {}

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class _MockHttpsCallable extends Mock implements HttpsCallable {}

class _MockHttpsCallableResult extends Mock
    implements HttpsCallableResult<Map<String, dynamic>> {}

/// (Phase 9.2 R4 / Mock 함정 1) `_MockUserCredential.additionalUserInfo` 가
/// nullable 이므로 `_MockAdditionalUserInfo` 를 명시 stub. `isNewUser`
/// thenReturn(true/false) 양쪽 분기 검증용.
class _MockAdditionalUserInfo extends Mock implements fb.AdditionalUserInfo {}

class _FakeAuthCredential extends Fake implements fb.AuthCredential {}

class _FakeAuthProvider extends Fake implements fb.AuthProvider {}

void main() {
  late _MockFirebaseAuth mockAuth;
  late _MockUserCredential mockCredential;
  late _MockFbUser mockUser;
  late _MockUserMetadata mockMetadata;
  late _MockGoogleSignIn mockGoogleSignIn;
  late _MockFacebookAuth mockFacebookAuth;
  late _MockSocialLinkInProgress mockSocialLinkInProgress;
  late _MockKakaoSdkClient mockKakaoSdkClient;
  late _MockNaverSdkClient mockNaverSdkClient;
  late _MockFirebaseFunctions mockFunctions;
  late _MockHttpsCallable mockCallable;
  late _MockAdditionalUserInfo mockAdditionalUserInfo;
  late AuthRepository repository;

  setUpAll(() {
    registerFallbackValue(_FakeAuthCredential());
    registerFallbackValue(_FakeAuthProvider());
    registerFallbackValue(fb.AppleAuthProvider());
    registerFallbackValue(LoginTracking.enabled);
    registerFallbackValue(LoginBehavior.nativeWithFallback);
    registerFallbackValue(const <String>[]);
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    mockAuth = _MockFirebaseAuth();
    mockCredential = _MockUserCredential();
    mockUser = _MockFbUser();
    mockMetadata = _MockUserMetadata();
    mockGoogleSignIn = _MockGoogleSignIn();
    mockFacebookAuth = _MockFacebookAuth();
    mockSocialLinkInProgress = _MockSocialLinkInProgress();
    mockKakaoSdkClient = _MockKakaoSdkClient();
    mockNaverSdkClient = _MockNaverSdkClient();
    mockFunctions = _MockFirebaseFunctions();
    mockCallable = _MockHttpsCallable();
    mockAdditionalUserInfo = _MockAdditionalUserInfo();

    repository = AuthRepository(
      mockAuth,
      mockGoogleSignIn,
      mockFacebookAuth,
      mockSocialLinkInProgress,
      mockKakaoSdkClient,
      mockFunctions,
      mockNaverSdkClient,
    );

    // Pitfall 9 — finally logout default stub.
    when(() => mockKakaoSdkClient.logout()).thenAnswer((_) async {});
    when(() => mockNaverSdkClient.logout()).thenAnswer((_) async {});

    // 기본 User 필드 — 비익명 + email 존재.
    when(() => mockUser.uid).thenReturn('uid-test');
    when(() => mockUser.email).thenReturn('test@example.com');
    when(() => mockUser.displayName).thenReturn('Test');
    when(() => mockUser.photoURL).thenReturn(null);
    when(() => mockUser.metadata).thenReturn(mockMetadata);
    when(() => mockMetadata.creationTime).thenReturn(DateTime.utc(2026));
    when(() => mockUser.providerData).thenReturn(<fb.UserInfo>[]);
    when(() => mockUser.isAnonymous).thenReturn(false);
    when(() => mockCredential.user).thenReturn(mockUser);

    // (Mock 함정 1) additionalUserInfo nullable mock — 기본 isNewUser=true.
    when(
      () => mockCredential.additionalUserInfo,
    ).thenReturn(mockAdditionalUserInfo);
    when(() => mockAdditionalUserInfo.isNewUser).thenReturn(true);

    // sendEmailVerification 기본 stub — Future void.
    when(() => mockUser.sendEmailVerification()).thenAnswer((_) async {});

    when(() => mockAuth.currentUser).thenReturn(null);
  });

  /// Google 성공 fixture — auth_repository_test.dart:462-484 mirror.
  void stubGoogleSuccess() {
    final mockAccount = _MockGoogleSignInAccount();
    when(() => mockAccount.authentication).thenReturn(
      const GoogleSignInAuthentication(idToken: 'id-token-test'),
    );
    when(
      () => mockGoogleSignIn.authenticate(scopeHint: any(named: 'scopeHint')),
    ).thenAnswer((_) async => mockAccount);
    final providerInfo = _MockUserInfo();
    when(() => providerInfo.providerId).thenReturn('google.com');
    when(() => mockUser.providerData).thenReturn([providerInfo]);
    when(
      () => mockAuth.signInWithCredential(any()),
    ).thenAnswer((_) async => mockCredential);
  }

  /// Apple 성공 fixture — auth_repository_test.dart:704-727 mirror.
  void stubAppleSuccess() {
    when(
      () => mockAuth.signInWithProvider(any()),
    ).thenAnswer((_) async => mockCredential);
    final providerInfo = _MockUserInfo();
    when(() => providerInfo.providerId).thenReturn('apple.com');
    when(() => mockUser.providerData).thenReturn([providerInfo]);
    when(() => mockAuth.currentUser).thenReturn(mockUser);
  }

  /// Facebook 성공 fixture — auth_repository_test.dart:805-835 mirror.
  void stubFacebookSuccess() {
    when(
      () => mockFacebookAuth.login(
        permissions: any(named: 'permissions'),
        loginTracking: any(named: 'loginTracking'),
        loginBehavior: any(named: 'loginBehavior'),
        nonce: any(named: 'nonce'),
      ),
    ).thenAnswer(
      (_) async => LoginResult(
        status: LoginStatus.success,
        accessToken: FakeClassicToken(tokenString: 'fb-token'),
      ),
    );
    final providerInfo = _MockUserInfo();
    when(() => providerInfo.providerId).thenReturn('facebook.com');
    when(() => mockUser.providerData).thenReturn([providerInfo]);
    when(
      () => mockAuth.signInWithCredential(any()),
    ).thenAnswer((_) async => mockCredential);
    // (Phase 9.2 R5) Facebook success path 는 _setFacebookPhotoUrl 도 호출 ─
    // Graph API + updatePhotoURL 기본 stub 으로 race-fix verifyInOrder 영향
    // 회피.
    when(
      () => mockFacebookAuth.getUserData(fields: any(named: 'fields')),
    ).thenAnswer(
      (_) async => <String, dynamic>{
        'picture': {
          'data': {
            'url': 'https://platform-lookaside.fbsbx.com/profile.jpg',
          },
        },
      },
    );
    when(() => mockUser.updatePhotoURL(any())).thenAnswer((_) async {});
  }

  /// Kakao 성공 fixture — auth_repository_test.dart:1372-1400 mirror.
  void stubKakaoSuccess() {
    when(() => mockKakaoSdkClient.signIn()).thenAnswer(
      (_) async => const KakaoSignInResult(idToken: 'IDT', nonce: 'NONCE'),
    );
    when(() => mockFunctions.httpsCallable(any())).thenReturn(mockCallable);
    final defaultResult = _MockHttpsCallableResult();
    when(() => defaultResult.data).thenReturn(<String, dynamic>{
      'customToken': 'CT',
      'uid': 'kakao-uid',
      'isNewUser': true,
    });
    when(
      () => mockCallable.call<Map<String, dynamic>>(any()),
    ).thenAnswer((_) async => defaultResult);
    when(
      () => mockAuth.signInWithCustomToken('CT'),
    ).thenAnswer((_) async => mockCredential);
  }

  /// Naver 성공 fixture — auth_repository_test.dart:1582-1608 mirror.
  void stubNaverSuccess() {
    when(() => mockNaverSdkClient.signIn()).thenAnswer(
      (_) async => const NaverSignInResult(accessToken: 'AT_NAVER'),
    );
    when(() => mockFunctions.httpsCallable(any())).thenReturn(mockCallable);
    final defaultResult = _MockHttpsCallableResult();
    when(() => defaultResult.data).thenReturn(<String, dynamic>{
      'customToken': 'CT_NAVER',
      'uid': 'naver-uid',
      'isNewUser': true,
    });
    when(
      () => mockCallable.call<Map<String, dynamic>>(any()),
    ).thenAnswer((_) async => defaultResult);
    when(
      () => mockAuth.signInWithCustomToken('CT_NAVER'),
    ).thenAnswer((_) async => mockCredential);
  }

  group(
    'Phase 9.2 R4 — _autoSendEmailVerification 5 provider no-op + isNewUser '
    '+ graceful + race-fix',
    () {
      // -----------------------------------------------------------------
      // V1~V4: 4 provider no-op (D-19) — emailVerified=true 자연 no-op.
      // Apple/Google idToken 'email_verified=true' claim + Kakao/Naver Cloud
      // Function 'identity_index.ts:225' emailVerified 자동 set 으로 시뮬레이션.
      // -----------------------------------------------------------------

      test(
        'V1: Google emailVerified=true → sendEmailVerification 미호출 (no-op)',
        () async {
          when(() => mockUser.emailVerified).thenReturn(true);
          stubGoogleSuccess();

          await repository.signInWithGoogle();

          verifyNever(() => mockUser.sendEmailVerification());
        },
      );

      test(
        'V2: Apple emailVerified=true → sendEmailVerification 미호출 (no-op)',
        () async {
          when(() => mockUser.emailVerified).thenReturn(true);
          stubAppleSuccess();

          await repository.signInWithApple();

          verifyNever(() => mockUser.sendEmailVerification());
        },
      );

      test(
        'V3: Kakao emailVerified=true (Cloud Function identity_index 자동 set) '
        '→ sendEmailVerification 미호출 (no-op)',
        () async {
          when(() => mockUser.emailVerified).thenReturn(true);
          stubKakaoSuccess();

          await repository.signInWithKakao();

          verifyNever(() => mockUser.sendEmailVerification());
        },
      );

      test(
        'V4: Naver emailVerified=true → sendEmailVerification 미호출 (no-op)',
        () async {
          when(() => mockUser.emailVerified).thenReturn(true);
          stubNaverSuccess();

          await repository.signInWithNaver();

          verifyNever(() => mockUser.sendEmailVerification());
        },
      );

      // -----------------------------------------------------------------
      // V5: Facebook 만 실효 호출 (D-19) — emailVerified=false + isNewUser=true.
      // -----------------------------------------------------------------

      test(
        'V5: Facebook emailVerified=false + isNewUser=true → '
        'sendEmailVerification 1회 호출',
        () async {
          when(() => mockUser.emailVerified).thenReturn(false);
          when(() => mockUser.email).thenReturn('fb@example.com');
          when(() => mockAdditionalUserInfo.isNewUser).thenReturn(true);
          stubFacebookSuccess();

          await repository.signInWithFacebook();

          verify(() => mockUser.sendEmailVerification()).called(1);
        },
      );

      // -----------------------------------------------------------------
      // V6: D-20 spam 가드 — isNewUser=false → 미호출.
      // -----------------------------------------------------------------

      test(
        'V6: Facebook emailVerified=false + isNewUser=false → 미호출 '
        '(재로그인 spam 방지 — D-20)',
        () async {
          when(() => mockUser.emailVerified).thenReturn(false);
          when(() => mockAdditionalUserInfo.isNewUser).thenReturn(false);
          stubFacebookSuccess();

          await repository.signInWithFacebook();

          verifyNever(() => mockUser.sendEmailVerification());
        },
      );

      // -----------------------------------------------------------------
      // V7: D-21 graceful — sendEmailVerification thenThrow 시 로그인 success.
      // -----------------------------------------------------------------

      test(
        'V7: Facebook sendEmailVerification thenThrow → 로그인 success 유지 '
        '(graceful catch — D-21)',
        () async {
          when(() => mockUser.emailVerified).thenReturn(false);
          when(() => mockAdditionalUserInfo.isNewUser).thenReturn(true);
          when(() => mockUser.sendEmailVerification()).thenThrow(
            fb.FirebaseAuthException(code: 'too-many-requests'),
          );
          stubFacebookSuccess();

          final result = await repository.signInWithFacebook();

          expect(result, isA<Success<dynamic>>());
        },
      );

      // -----------------------------------------------------------------
      // V8: D-22 race-fix invariant — begin → sendEmailVerification → end.
      // -----------------------------------------------------------------

      test(
        'V8: Facebook race-fix — begin() → sendEmailVerification → end() 순서 '
        '(D-22 invariant)',
        () async {
          when(() => mockUser.emailVerified).thenReturn(false);
          when(() => mockAdditionalUserInfo.isNewUser).thenReturn(true);
          stubFacebookSuccess();

          await repository.signInWithFacebook();

          verifyInOrder([
            () => mockSocialLinkInProgress.begin(),
            () => mockUser.sendEmailVerification(),
            () => mockSocialLinkInProgress.end(),
          ]);
        },
      );

      // -----------------------------------------------------------------
      // V9 (WR-04 regression — Phase 9.2 review fix):
      // user.email == '' 빈 문자열 가드. 이전 `email == null` 가드는 빈
      // 문자열을 통과시켜 Firebase Auth 가 `auth/missing-email` throw 시
      // graceful catch 가 흡수하지만 이메일 인증 메일이 발송 안 됨. 새
      // 가드 `(user.email ?? '').isEmpty` 가 양쪽 (null + empty) 을 차단.
      // -----------------------------------------------------------------

      test(
        'V9 (WR-04): Facebook user.email == "" → sendEmailVerification 미호출 '
        '(빈 문자열 가드 회귀)',
        () async {
          when(() => mockUser.emailVerified).thenReturn(false);
          when(() => mockUser.email).thenReturn(''); // 빈 문자열
          when(() => mockAdditionalUserInfo.isNewUser).thenReturn(true);
          stubFacebookSuccess();

          await repository.signInWithFacebook();

          verifyNever(() => mockUser.sendEmailVerification());
        },
      );
    },
  );
}
