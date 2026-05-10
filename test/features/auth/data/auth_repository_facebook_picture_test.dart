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

class _MockFacebookAuth extends Mock implements FacebookAuth {}

class _MockUserInfo extends Mock implements fb.UserInfo {}

class _MockSocialLinkInProgress extends Mock implements SocialLinkInProgress {}

class _MockKakaoSdkClient extends Mock implements KakaoSdkClient {}

class _MockNaverSdkClient extends Mock implements NaverSdkClient {}

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

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
  late _MockAdditionalUserInfo mockAdditionalUserInfo;
  late AuthRepository repository;

  setUpAll(() {
    registerFallbackValue(_FakeAuthCredential());
    registerFallbackValue(_FakeAuthProvider());
    registerFallbackValue(LoginTracking.enabled);
    registerFallbackValue(LoginBehavior.nativeWithFallback);
    registerFallbackValue(const <String>[]);
  });

  /// signInWithFacebook 성공 fixture — auth_repository_test.dart:805-835 mirror.
  void stubFacebookLogin() {
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
    when(
      () => mockAuth.signInWithCredential(any()),
    ).thenAnswer((_) async => mockCredential);
  }

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

    // 기본 User 필드 — emailVerified=true 로 _autoSendEmailVerification 자연
    // no-op (본 파일은 _setFacebookPhotoUrl 만 focus).
    when(() => mockUser.uid).thenReturn('uid-test');
    when(() => mockUser.email).thenReturn('fb@example.com');
    when(() => mockUser.emailVerified).thenReturn(true);
    when(() => mockUser.displayName).thenReturn('Test');
    when(() => mockUser.photoURL).thenReturn(null);
    when(() => mockUser.metadata).thenReturn(mockMetadata);
    when(() => mockMetadata.creationTime).thenReturn(DateTime.utc(2026));
    final providerInfo = _MockUserInfo();
    when(() => providerInfo.providerId).thenReturn('facebook.com');
    when(() => mockUser.providerData).thenReturn([providerInfo]);
    when(() => mockUser.isAnonymous).thenReturn(false);
    when(() => mockCredential.user).thenReturn(mockUser);
    when(
      () => mockCredential.additionalUserInfo,
    ).thenReturn(mockAdditionalUserInfo);
    when(() => mockAdditionalUserInfo.isNewUser).thenReturn(true);

    when(() => mockAuth.currentUser).thenReturn(null);

    // (Mock 함정 3) Graph API default stub — fields verbatim 매치.
    // sentinel facebook id ('999888777') 는 D-27 PII regression anchor.
    when(
      () => mockFacebookAuth.getUserData(fields: 'picture.type(large)'),
    ).thenAnswer(
      (_) async => <String, dynamic>{
        'picture': {
          'data': {
            'url': 'https://platform-lookaside.fbsbx.com/profile.jpg',
            'width': 200,
            'height': 200,
            'is_silhouette': false,
          },
        },
        'id': '999888777',
      },
    );
    // (Mock 함정 4) updatePhotoURL Future void thenAnswer 의무.
    when(() => mockUser.updatePhotoURL(any())).thenAnswer((_) async {});
  });

  group(
    'Phase 9.2 R5 — _setFacebookPhotoUrl Graph API + safe nav + graceful + '
    'race-fix + D-27 PII regression',
    () {
      // -----------------------------------------------------------------
      // F1: Happy path (R5).
      // -----------------------------------------------------------------

      test(
        'F1: Facebook 성공 시 user.updatePhotoURL(picture.data.url) 1회 호출',
        () async {
          stubFacebookLogin();

          await repository.signInWithFacebook();

          verify(
            () => mockUser.updatePhotoURL(
              'https://platform-lookaside.fbsbx.com/profile.jpg',
            ),
          ).called(1);
        },
      );

      // -----------------------------------------------------------------
      // F2~F4: Safe navigation 4단 graceful skip (D-24).
      // -----------------------------------------------------------------

      test(
        'F2: picture path 누락 → updatePhotoURL 미호출 (graceful)',
        () async {
          when(
            () => mockFacebookAuth.getUserData(fields: any(named: 'fields')),
          ).thenAnswer(
            (_) async => <String, dynamic>{'id': '999888777'},
          );
          stubFacebookLogin();

          await repository.signInWithFacebook();

          verifyNever(() => mockUser.updatePhotoURL(any()));
        },
      );

      test(
        'F3: picture.data 타입 mismatch (List) → updatePhotoURL 미호출',
        () async {
          when(
            () => mockFacebookAuth.getUserData(fields: any(named: 'fields')),
          ).thenAnswer(
            (_) async => <String, dynamic>{
              'picture': {'data': <dynamic>[]},
            },
          );
          stubFacebookLogin();

          await repository.signInWithFacebook();

          verifyNever(() => mockUser.updatePhotoURL(any()));
        },
      );

      test(
        'F4: url 빈 문자열 → updatePhotoURL 미호출',
        () async {
          when(
            () => mockFacebookAuth.getUserData(fields: any(named: 'fields')),
          ).thenAnswer(
            (_) async => <String, dynamic>{
              'picture': {
                'data': {'url': ''},
              },
            },
          );
          stubFacebookLogin();

          await repository.signInWithFacebook();

          verifyNever(() => mockUser.updatePhotoURL(any()));
        },
      );

      // -----------------------------------------------------------------
      // F5: getUserData thenThrow → 로그인 success 유지 + verifyNever.
      // -----------------------------------------------------------------

      test(
        'F5: getUserData thenThrow → 로그인 success 유지 + updatePhotoURL '
        '미호출 (graceful)',
        () async {
          when(
            () => mockFacebookAuth.getUserData(fields: any(named: 'fields')),
          ).thenThrow(Exception('Graph API down'));
          stubFacebookLogin();

          final result = await repository.signInWithFacebook();

          expect(result, isA<Success<dynamic>>());
          verifyNever(() => mockUser.updatePhotoURL(any()));
        },
      );

      // -----------------------------------------------------------------
      // F6: updatePhotoURL thenThrow → 로그인 success 유지 (광역 catch).
      // -----------------------------------------------------------------

      test(
        'F6: updatePhotoURL thenThrow → 로그인 success 유지 (광역 catch)',
        () async {
          when(() => mockUser.updatePhotoURL(any())).thenThrow(
            Exception('Auth API down'),
          );
          stubFacebookLogin();

          final result = await repository.signInWithFacebook();

          expect(result, isA<Success<dynamic>>());
        },
      );

      // -----------------------------------------------------------------
      // F7: D-22 race-fix invariant — begin → getUserData → updatePhotoURL
      // → end.
      // -----------------------------------------------------------------

      test(
        'F7: race-fix — begin() → getUserData → updatePhotoURL → end() 순서 '
        '(D-22 invariant)',
        () async {
          stubFacebookLogin();

          await repository.signInWithFacebook();

          verifyInOrder([
            () => mockSocialLinkInProgress.begin(),
            () => mockFacebookAuth.getUserData(fields: 'picture.type(large)'),
            () => mockUser.updatePhotoURL(any()),
            () => mockSocialLinkInProgress.end(),
          ]);
        },
      );

      // -----------------------------------------------------------------
      // F8: D-27 PII regression — sentinel facebook id '999888777' + sentinel
      // CDN URL 'leaktest.cdn' + sentinel email 'leaktest@example.com' 모두
      // Exception message 안에 주입 → graceful skip 보장 (verifyNever
      // updatePhotoURL).
      //
      // 참고 (PATTERNS.md §10 / §11): debugPrint 직접 capture 한계 — helper
      // 의 catch 블록 debugPrint format 이 'e.runtimeType' verbatim 임은 코드
      // 리뷰 회귀 가드 (auth_repository.dart:783). Phase 12.1 D-40 와 동등
      // 한계. 본 테스트는 graceful skip 보장 + sentinel verbatim 매치 (코드
      // 리뷰 anchor) 로 hard verify.
      // -----------------------------------------------------------------

      test(
        "F8: D-27 PII regression — sentinel facebook id '999888777' + sentinel "
        "CDN URL 'leaktest.cdn' graceful skip 보장",
        () async {
          when(
            () => mockFacebookAuth.getUserData(fields: any(named: 'fields')),
          ).thenThrow(
            Exception(
              'Graph error with sentinel email leaktest@example.com '
              'and id 999888777 and url https://leaktest.cdn/profile.jpg',
            ),
          );
          stubFacebookLogin();

          final result = await repository.signInWithFacebook();

          // graceful skip 보장 — sentinel CDN URL 이 user.photoURL 에 반영 0.
          expect(result, isA<Success<dynamic>>());
          verifyNever(() => mockUser.updatePhotoURL(any()));
        },
      );
    },
  );
}
