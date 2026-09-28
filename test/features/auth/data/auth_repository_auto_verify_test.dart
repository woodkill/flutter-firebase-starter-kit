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
import 'package:flutter_starter_kit/features/auth/data/line_sdk_client.dart';
import 'package:flutter_starter_kit/features/auth/data/naver_sdk_client.dart';
import 'package:flutter_starter_kit/features/auth/data/naver_sign_in_result.dart';

import 'auth_test_fakes.dart';

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockUserCredential extends Mock implements fb.UserCredential {}

class _MockFbUser extends Mock implements fb.User {}

/// (Phase 9.2 Gap A close — HUMAN-UAT 2026-05-11) 익명승격 path 의 분리
/// mock. `mockAuth.currentUser` 가 익명 user 를 반환하는 동안 `linkWithCredential`
/// / `linkWithProvider` 를 호출하는 분기를 검증한다. _MockFbUser 와 분리하여
/// `mockUser.isAnonymous=false` (성공 결과 user) 와 `mockAnonymousUser.isAnonymous=true`
/// (호출 시점 currentUser) 가 동시 stub 가능하다.
class _MockFbAnonymousUser extends Mock implements fb.User {}

class _MockUserMetadata extends Mock implements fb.UserMetadata {}

class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

class _MockGoogleSignInAccount extends Mock implements GoogleSignInAccount {}

class _MockFacebookAuth extends Mock implements FacebookAuth {}

class _MockUserInfo extends Mock implements fb.UserInfo {}

class _MockSocialLinkInProgress extends Mock implements SocialLinkInProgress {}

class _MockKakaoSdkClient extends Mock implements KakaoSdkClient {}

class _MockNaverSdkClient extends Mock implements NaverSdkClient {}

class _MockLineSdkClient extends Mock implements LineSdkClient {}

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
  late _MockLineSdkClient mockLineSdkClient;
  late _MockFirebaseFunctions mockFunctions;
  late _MockHttpsCallable mockCallable;
  late _MockAdditionalUserInfo mockAdditionalUserInfo;
  late _MockFbAnonymousUser mockAnonymousUser;
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
    mockLineSdkClient = _MockLineSdkClient();
    mockFunctions = _MockFirebaseFunctions();
    mockCallable = _MockHttpsCallable();
    mockAdditionalUserInfo = _MockAdditionalUserInfo();
    mockAnonymousUser = _MockFbAnonymousUser();

    repository = AuthRepository(
      mockAuth,
      mockGoogleSignIn,
      mockFacebookAuth,
      mockSocialLinkInProgress,
      mockKakaoSdkClient,
      mockFunctions,
      mockNaverSdkClient,
      mockLineSdkClient,
      // Phase 10.2 D-A2: onResetOnboarding 콜백 no-op (logout invariant
      // 비검증).
      () async {},
    );

    // Pitfall 9 — finally logout default stub (Phase 14 LINE 포함).
    when(() => mockKakaoSdkClient.logout()).thenAnswer((_) async {});
    when(() => mockNaverSdkClient.logout()).thenAnswer((_) async {});
    when(() => mockLineSdkClient.logout()).thenAnswer((_) async {});

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
    when(
      () => mockAccount.authentication,
    ).thenReturn(const GoogleSignInAuthentication(idToken: 'id-token-test'));
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
          'data': {'url': 'https://platform-lookaside.fbsbx.com/profile.jpg'},
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
    when(
      () => mockFunctions.httpsCallable(any(), options: any(named: 'options')),
    ).thenReturn(mockCallable);
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
    when(
      () => mockNaverSdkClient.signIn(),
    ).thenAnswer((_) async => const NaverAppSignIn(accessToken: 'AT_NAVER'));
    when(
      () => mockFunctions.httpsCallable(any(), options: any(named: 'options')),
    ).thenReturn(mockCallable);
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

  /// LINE 성공 fixture — [stubKakaoSuccess] mirror (quick 260928-luw V14 · V15).
  void stubLineSuccess() {
    when(() => mockLineSdkClient.signIn()).thenAnswer(
      (_) async => const LineSignInResult(idToken: 'LIDT', nonce: 'LNONCE'),
    );
    when(
      () => mockFunctions.httpsCallable(any(), options: any(named: 'options')),
    ).thenReturn(mockCallable);
    final defaultResult = _MockHttpsCallableResult();
    when(() => defaultResult.data).thenReturn(<String, dynamic>{
      'customToken': 'CT_LINE',
      'uid': 'line-uid',
      'isNewUser': true,
    });
    when(
      () => mockCallable.call<Map<String, dynamic>>(any()),
    ).thenAnswer((_) async => defaultResult);
    when(
      () => mockAuth.signInWithCustomToken('CT_LINE'),
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
      // V14~V15 (quick 260928-luw): LINE — 이메일이 있으면 서버가 verified 로
      // 취급(D-2) → `emailVerified` 가드, 없으면 `email.isEmpty` 가드.
      // -----------------------------------------------------------------

      test('V14: LINE email 있음 + emailVerified=true (서버 D-2 verified 취급) '
          '+ isNewUser=true → sendEmailVerification 미호출', () async {
        when(() => mockUser.email).thenReturn('line-user@line.example');
        when(() => mockUser.emailVerified).thenReturn(true);
        stubLineSuccess();

        await repository.signInWithLine();

        verifyNever(() => mockUser.sendEmailVerification());
      });

      test(
        'V15: LINE email 없음 (채널 email 권한 없음) → sendEmailVerification 미호출',
        () async {
          when(() => mockUser.email).thenReturn(null);
          // 서버 기본값은 true 지만, false 로 두어 `email.isEmpty` 가드만으로
          // 차단됨을 격리해 잠근다.
          when(() => mockUser.emailVerified).thenReturn(false);
          stubLineSuccess();

          await repository.signInWithLine();

          verifyNever(() => mockUser.sendEmailVerification());
        },
      );

      // -----------------------------------------------------------------
      // V5: Facebook 만 실효 호출 (D-19) — emailVerified=false + isNewUser=true.
      // -----------------------------------------------------------------

      test('V5: Facebook emailVerified=false + isNewUser=true → '
          'sendEmailVerification 1회 호출', () async {
        when(() => mockUser.emailVerified).thenReturn(false);
        when(() => mockUser.email).thenReturn('fb@example.com');
        when(() => mockAdditionalUserInfo.isNewUser).thenReturn(true);
        stubFacebookSuccess();

        await repository.signInWithFacebook();

        verify(() => mockUser.sendEmailVerification()).called(1);
      });

      // -----------------------------------------------------------------
      // V6: D-20 spam 가드 — isNewUser=false → 미호출.
      // -----------------------------------------------------------------

      test('V6: Facebook emailVerified=false + isNewUser=false → 미호출 '
          '(재로그인 spam 방지 — D-20)', () async {
        when(() => mockUser.emailVerified).thenReturn(false);
        when(() => mockAdditionalUserInfo.isNewUser).thenReturn(false);
        stubFacebookSuccess();

        await repository.signInWithFacebook();

        verifyNever(() => mockUser.sendEmailVerification());
      });

      // -----------------------------------------------------------------
      // V7: D-21 graceful — sendEmailVerification thenThrow 시 로그인 success.
      // -----------------------------------------------------------------

      test('V7: Facebook sendEmailVerification thenThrow → 로그인 success 유지 '
          '(graceful catch — D-21)', () async {
        when(() => mockUser.emailVerified).thenReturn(false);
        when(() => mockAdditionalUserInfo.isNewUser).thenReturn(true);
        when(
          () => mockUser.sendEmailVerification(),
        ).thenThrow(fb.FirebaseAuthException(code: 'too-many-requests'));
        stubFacebookSuccess();

        final result = await repository.signInWithFacebook();

        expect(result, isA<Success<dynamic>>());
      });

      // -----------------------------------------------------------------
      // V8: D-22 race-fix invariant — begin → sendEmailVerification → end.
      // -----------------------------------------------------------------

      test('V8: Facebook race-fix — begin() → sendEmailVerification → end() 순서 '
          '(D-22 invariant)', () async {
        when(() => mockUser.emailVerified).thenReturn(false);
        when(() => mockAdditionalUserInfo.isNewUser).thenReturn(true);
        stubFacebookSuccess();

        await repository.signInWithFacebook();

        verifyInOrder([
          () => mockSocialLinkInProgress.begin(),
          () => mockUser.sendEmailVerification(),
          () => mockSocialLinkInProgress.end(),
        ]);
      });

      // -----------------------------------------------------------------
      // V9 (WR-04 regression — Phase 9.2 review fix):
      // user.email == '' 빈 문자열 가드. 이전 `email == null` 가드는 빈
      // 문자열을 통과시켜 Firebase Auth 가 `auth/missing-email` throw 시
      // graceful catch 가 흡수하지만 이메일 인증 메일이 발송 안 됨. 새
      // 가드 `(user.email ?? '').isEmpty` 가 양쪽 (null + empty) 을 차단.
      // -----------------------------------------------------------------

      test('V9 (WR-04): Facebook user.email == "" → sendEmailVerification 미호출 '
          '(빈 문자열 가드 회귀)', () async {
        when(() => mockUser.emailVerified).thenReturn(false);
        when(() => mockUser.email).thenReturn(''); // 빈 문자열
        when(() => mockAdditionalUserInfo.isNewUser).thenReturn(true);
        stubFacebookSuccess();

        await repository.signInWithFacebook();

        verifyNever(() => mockUser.sendEmailVerification());
      });
    },
  );

  // ===================================================================
  // (Phase 9.2 Gap A close — HUMAN-UAT 2026-05-11)
  // 익명 → linkWithCredential / linkWithProvider 분기의 `isNewUser=false`
  // Firebase 사양 보강. helper 시그니처 `isLinkedFromAnonymous` named
  // 인자를 호출 측이 명시 전달하면 D-20 spam 가드를 우회한다 — 다른 4
  // 가드 (user==null / isAnonymous / email empty / emailVerified=true)
  // 는 unchanged 동작.
  //
  // V9 ~ V13 매트릭스:
  //   V9  Facebook 익명승격 + isNewUser=false + emailVerified=false → 1회 호출
  //   V10 Google   익명승격 + isNewUser=false + emailVerified=true  → 미호출
  //   V11 Apple    익명승격 + isNewUser=false + emailVerified=true  → 미호출
  //   V12 Facebook 비-익명 + isNewUser=true  + emailVerified=false → 1회 호출
  //   V13 Facebook 비-익명 + isNewUser=false + emailVerified=false → 미호출
  //
  // Naver/Kakao 익명 link 분기는 부재 (signInWithCustomToken 단독 사용)
  // — Cloud Function 이 emailVerified=true 자동 set 으로 D-19 자연
  // no-op (Gap B 의 영역, plan 07/08 책임).
  // ===================================================================

  /// Facebook 익명 분기 fixture — `mockAuth.currentUser` 가 익명 user 반환,
  /// `anonymous.linkWithCredential` 가 성공 mockCredential 반환. Firebase 사양
  /// 으로 `additionalUserInfo.isNewUser=false` 시뮬레이션 (호출 측이
  /// `isLinkedFromAnonymous: true` 로 보강할 때 sendEmailVerification 발송).
  void stubFacebookAnonymousLinkSuccess() {
    when(() => mockAnonymousUser.isAnonymous).thenReturn(true);
    when(() => mockAuth.currentUser).thenReturn(mockAnonymousUser);
    when(
      () => mockAnonymousUser.linkWithCredential(any()),
    ).thenAnswer((_) async => mockCredential);

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
        accessToken: FakeClassicToken(tokenString: 'fb-token-anon'),
      ),
    );
    final providerInfo = _MockUserInfo();
    when(() => providerInfo.providerId).thenReturn('facebook.com');
    when(() => mockUser.providerData).thenReturn([providerInfo]);
    when(
      () => mockFacebookAuth.getUserData(fields: any(named: 'fields')),
    ).thenAnswer(
      (_) async => <String, dynamic>{
        'picture': {
          'data': {'url': 'https://platform-lookaside.fbsbx.com/profile.jpg'},
        },
      },
    );
    when(() => mockUser.updatePhotoURL(any())).thenAnswer((_) async {});
    // (Gap A close) Firebase 가 linkWithCredential 후 isNewUser=false 반환
    // — helper 의 D-20 spam 가드 short-circuit. 호출 측 `isLinkedFromAnonymous:
    // true` 명시 전달이 가드 우회 권한.
    when(() => mockAdditionalUserInfo.isNewUser).thenReturn(false);
  }

  /// Google 익명 분기 fixture — `anonymous.linkWithCredential` 호출 경로.
  void stubGoogleAnonymousLinkSuccess() {
    when(() => mockAnonymousUser.isAnonymous).thenReturn(true);
    when(() => mockAuth.currentUser).thenReturn(mockAnonymousUser);
    when(
      () => mockAnonymousUser.linkWithCredential(any()),
    ).thenAnswer((_) async => mockCredential);

    final mockAccount = _MockGoogleSignInAccount();
    when(
      () => mockAccount.authentication,
    ).thenReturn(const GoogleSignInAuthentication(idToken: 'id-token-anon'));
    when(
      () => mockGoogleSignIn.authenticate(scopeHint: any(named: 'scopeHint')),
    ).thenAnswer((_) async => mockAccount);
    final providerInfo = _MockUserInfo();
    when(() => providerInfo.providerId).thenReturn('google.com');
    when(() => mockUser.providerData).thenReturn([providerInfo]);
    when(() => mockAdditionalUserInfo.isNewUser).thenReturn(false);
  }

  /// Apple 익명 분기 fixture — `anonymous.linkWithProvider` 호출 경로.
  void stubAppleAnonymousLinkSuccess() {
    when(() => mockAnonymousUser.isAnonymous).thenReturn(true);
    when(() => mockAuth.currentUser).thenReturn(mockAnonymousUser);
    when(
      () => mockAnonymousUser.linkWithProvider(any()),
    ).thenAnswer((_) async => mockCredential);

    final providerInfo = _MockUserInfo();
    when(() => providerInfo.providerId).thenReturn('apple.com');
    when(() => mockUser.providerData).thenReturn([providerInfo]);
    when(() => mockAdditionalUserInfo.isNewUser).thenReturn(false);
  }

  group('Phase 9.2 Gap A (HUMAN-UAT 2026-05-11) — 익명 → linkWithCredential '
      'isNewUser=false 보강', () {
    test(
      'V9: Facebook 익명승격 (linkWithCredential) + isNewUser=false + '
      'emailVerified=false → sendEmailVerification 1회 호출 (Gap A close)',
      () async {
        when(() => mockUser.emailVerified).thenReturn(false);
        when(() => mockUser.email).thenReturn('fb-anon@example.com');
        stubFacebookAnonymousLinkSuccess();

        await repository.signInWithFacebook();

        verify(() => mockAnonymousUser.linkWithCredential(any())).called(1);
        verify(() => mockUser.sendEmailVerification()).called(1);
      },
    );

    test('V10: Google 익명승격 (linkWithCredential) + isNewUser=false + '
        'emailVerified=true → sendEmailVerification 미호출 (D-19 emailVerified '
        '가드 우선)', () async {
      when(() => mockUser.emailVerified).thenReturn(true);
      when(() => mockUser.email).thenReturn('g-anon@example.com');
      stubGoogleAnonymousLinkSuccess();

      await repository.signInWithGoogle();

      verify(() => mockAnonymousUser.linkWithCredential(any())).called(1);
      verifyNever(() => mockUser.sendEmailVerification());
    });

    test('V11: Apple 익명승격 (linkWithProvider) + isNewUser=false + '
        'emailVerified=true → sendEmailVerification 미호출 (D-19 emailVerified '
        '가드 우선)', () async {
      when(() => mockUser.emailVerified).thenReturn(true);
      when(() => mockUser.email).thenReturn('a-anon@example.com');
      stubAppleAnonymousLinkSuccess();

      await repository.signInWithApple();

      verify(() => mockAnonymousUser.linkWithProvider(any())).called(1);
      verifyNever(() => mockUser.sendEmailVerification());
    });

    test('V12: Facebook 비-익명 signInWithCredential + isNewUser=true + '
        'emailVerified=false → sendEmailVerification 1회 호출 (기존 V5 mirror '
        '— regression sentinel)', () async {
      when(() => mockUser.emailVerified).thenReturn(false);
      when(() => mockUser.email).thenReturn('fb-direct@example.com');
      when(() => mockAdditionalUserInfo.isNewUser).thenReturn(true);
      stubFacebookSuccess();

      await repository.signInWithFacebook();

      verify(() => mockUser.sendEmailVerification()).called(1);
    });

    test('V13: Facebook 비-익명 signInWithCredential + isNewUser=false '
        '(재로그인) + emailVerified=false → sendEmailVerification 미호출 '
        '(D-20 spam 가드 invariant 보존)', () async {
      when(() => mockUser.emailVerified).thenReturn(false);
      when(() => mockUser.email).thenReturn('fb-relogin@example.com');
      when(() => mockAdditionalUserInfo.isNewUser).thenReturn(false);
      stubFacebookSuccess();

      await repository.signInWithFacebook();

      verifyNever(() => mockUser.sendEmailVerification());
    });
  });
}
