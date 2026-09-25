import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/features/auth/application/social_link_in_progress.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/data/kakao_sdk_client.dart';
import 'package:flutter_starter_kit/features/auth/data/line_sdk_client.dart';
import 'package:flutter_starter_kit/features/auth/data/naver_sdk_client.dart';

import 'auth_test_fakes.dart';

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockUserCredential extends Mock implements fb.UserCredential {}

class _MockFbUser extends Mock implements fb.User {}

class _MockUserMetadata extends Mock implements fb.UserMetadata {}

class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

class _MockFacebookAuth extends Mock implements FacebookAuth {}

class _MockGoogleSignInAccount extends Mock implements GoogleSignInAccount {}

class _MockSocialLinkInProgress extends Mock implements SocialLinkInProgress {}

class _MockKakaoSdkClient extends Mock implements KakaoSdkClient {}

class _MockNaverSdkClient extends Mock implements NaverSdkClient {}

class _MockLineSdkClient extends Mock implements LineSdkClient {}

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class _FakeAuthCredential extends Fake implements fb.AuthCredential {}

void main() {
  late _MockFirebaseAuth mockAuth;
  late _MockUserCredential mockLinkedCred;
  late _MockUserCredential mockSignInCred;
  late _MockFbUser mockAnonUser;
  late _MockFbUser mockResultUser;
  late _MockUserMetadata mockMetadata;
  late _MockGoogleSignIn mockGoogleSignIn;
  late _MockFacebookAuth mockFacebookAuth;
  late _MockSocialLinkInProgress mockSocialLinkInProgress;
  late _MockKakaoSdkClient mockKakaoSdkClient;
  late _MockNaverSdkClient mockNaverSdkClient;
  late _MockLineSdkClient mockLineSdkClient;
  late _MockFirebaseFunctions mockFunctions;
  late AuthRepository repository;

  setUpAll(() {
    // mocktail 의 `any(named: ...)` 매처는 named parameter 의 정적 타입에 대해
    // fallback value 를 요구한다. 아래 group 의 `mockFacebookAuth.login(...)`
    // stub 이 모든 named param 에 `any(named: ...)` 를 사용하므로,
    // `FacebookAuth.login` 시그니처의 non-nullable typed param 별로 1회씩
    // fallback 을 등록해야 한다:
    //   - permissions: List<String>          → const <String>[]
    //   - loginBehavior: LoginBehavior        → LoginBehavior.nativeWithFallback
    //   - loginTracking: LoginTracking        → LoginTracking.enabled
    // (`nonce` 는 String? 이라 fallback 불필요.)
    registerFallbackValue(_FakeAuthCredential());
    registerFallbackValue(fb.AppleAuthProvider());
    registerFallbackValue(LoginTracking.enabled);
    registerFallbackValue(LoginBehavior.nativeWithFallback);
    registerFallbackValue(const <String>[]);
  });

  setUp(() {
    mockAuth = _MockFirebaseAuth();
    mockLinkedCred = _MockUserCredential();
    mockSignInCred = _MockUserCredential();
    mockAnonUser = _MockFbUser();
    mockResultUser = _MockFbUser();
    mockMetadata = _MockUserMetadata();
    mockGoogleSignIn = _MockGoogleSignIn();
    mockFacebookAuth = _MockFacebookAuth();
    mockSocialLinkInProgress = _MockSocialLinkInProgress();
    mockKakaoSdkClient = _MockKakaoSdkClient();
    mockNaverSdkClient = _MockNaverSdkClient();
    mockLineSdkClient = _MockLineSdkClient();
    mockFunctions = _MockFirebaseFunctions();
    // Phase 9.1 D-03 / D-04 + Phase 12 D-28 + Phase 13 D-43 + Phase 14 D-LINE-17
    // + Phase 10.2 D-A2: AuthRepository 9-arg ctor.
    repository = AuthRepository(
      mockAuth,
      mockGoogleSignIn,
      mockFacebookAuth,
      mockSocialLinkInProgress,
      mockKakaoSdkClient,
      mockFunctions,
      mockNaverSdkClient,
      mockLineSdkClient,
      () async {},
    );

    // 익명 currentUser 기본 stub.
    when(() => mockAnonUser.uid).thenReturn('anon-uid');
    when(() => mockAnonUser.isAnonymous).thenReturn(true);
    when(() => mockAnonUser.delete()).thenAnswer((_) async {});

    // 정식 결과 User 기본 stub.
    when(() => mockResultUser.uid).thenReturn('reg-uid');
    when(() => mockResultUser.isAnonymous).thenReturn(false);
    when(() => mockResultUser.email).thenReturn('reg@example.com');
    when(() => mockResultUser.emailVerified).thenReturn(true);
    when(() => mockResultUser.displayName).thenReturn(null);
    when(() => mockResultUser.photoURL).thenReturn(null);
    when(() => mockResultUser.providerData).thenReturn([]);
    when(() => mockResultUser.metadata).thenReturn(mockMetadata);
    when(() => mockMetadata.creationTime).thenReturn(DateTime.utc(2026, 4, 14));

    // linking / signIn 결과 credential.user 가 정식 결과 user 를 반환.
    when(() => mockLinkedCred.user).thenReturn(mockResultUser);
    when(() => mockSignInCred.user).thenReturn(mockResultUser);
  });

  group('signInWithGoogle — 익명 linking 분기 (Phase 10 BLOCKER #4)', () {
    late _MockGoogleSignInAccount mockAccount;

    setUp(() {
      mockAccount = _MockGoogleSignInAccount();
      when(
        () => mockAccount.authentication,
      ).thenReturn(const GoogleSignInAuthentication(idToken: 'mock-id-token'));
      when(
        () => mockGoogleSignIn.authenticate(scopeHint: any(named: 'scopeHint')),
      ).thenAnswer((_) async => mockAccount);
    });

    test('Test G1: 익명 currentUser 존재 시 linkWithCredential 호출, '
        'signInWithCredential 미호출, uid 유지', () async {
      when(() => mockAuth.currentUser).thenReturn(mockAnonUser);
      when(
        () => mockAnonUser.linkWithCredential(any()),
      ).thenAnswer((_) async => mockLinkedCred);
      // 결과 User uid 는 익명 uid 유지 (linking semantics).
      when(() => mockResultUser.uid).thenReturn('anon-uid');

      final result = await repository.signInWithGoogle();

      expect(result, isA<Success<dynamic>>());
      verify(() => mockAnonUser.linkWithCredential(any())).called(1);
      verifyNever(() => mockAuth.signInWithCredential(any()));
      expect((result! as Success).data.uid, 'anon-uid');
    });

    test('Test G2: 익명 currentUser 없음 시 signInWithCredential 호출, '
        'linkWithCredential 미호출', () async {
      when(() => mockAuth.currentUser).thenReturn(null);
      when(
        () => mockAuth.signInWithCredential(any()),
      ).thenAnswer((_) async => mockSignInCred);

      final result = await repository.signInWithGoogle();

      expect(result, isA<Success<dynamic>>());
      verify(() => mockAuth.signInWithCredential(any())).called(1);
      verifyNever(() => mockAnonUser.linkWithCredential(any()));
    });

    test('Test G3: credential-already-in-use 시 익명 delete + '
        'signInWithCredential fallback', () async {
      when(() => mockAuth.currentUser).thenReturn(mockAnonUser);
      when(
        () => mockAnonUser.linkWithCredential(any()),
      ).thenThrow(fb.FirebaseAuthException(code: 'credential-already-in-use'));
      when(
        () => mockAuth.signInWithCredential(any()),
      ).thenAnswer((_) async => mockSignInCred);

      final result = await repository.signInWithGoogle();

      expect(result, isA<Success<dynamic>>());
      verifyInOrder([
        () => mockAnonUser.linkWithCredential(any()),
        () => mockAnonUser.delete(),
        () => mockAuth.signInWithCredential(any()),
      ]);
    });
  });

  group('signInWithApple — 익명 linking 분기 (Blocker #2 — 재조회 없음)', () {
    test('Test A1: 익명 linking 성공 — linkWithProvider 결과 직접 반환', () async {
      // Blocker #2: currentUser 재조회 제거 구현에 맞춰 단일 stub.
      when(() => mockAuth.currentUser).thenReturn(mockAnonUser);
      when(
        () => mockAnonUser.linkWithProvider(any()),
      ).thenAnswer((_) async => mockLinkedCred);

      final result = await repository.signInWithApple();

      expect(result, isA<Success<dynamic>>());
      verify(() => mockAnonUser.linkWithProvider(any())).called(1);
      verifyNever(() => mockAuth.signInWithProvider(any()));
      // mockLinkedCred.user == mockResultUser 가 _mapFirebaseUser 로 전달됨.
      expect((result! as Success).data.uid, 'reg-uid');
    });

    test('Test A2: 비익명 경로 — signInWithProvider 호출', () async {
      when(() => mockAuth.currentUser).thenReturn(null);
      when(
        () => mockAuth.signInWithProvider(any()),
      ).thenAnswer((_) async => mockSignInCred);

      final result = await repository.signInWithApple();

      expect(result, isA<Success<dynamic>>());
      verify(() => mockAuth.signInWithProvider(any())).called(1);
      verifyNever(() => mockAnonUser.linkWithProvider(any()));
    });

    test('Test A3: credential-already-in-use fallback — '
        '_safeDelete + signInWithProvider', () async {
      when(() => mockAuth.currentUser).thenReturn(mockAnonUser);
      when(
        () => mockAnonUser.linkWithProvider(any()),
      ).thenThrow(fb.FirebaseAuthException(code: 'credential-already-in-use'));
      when(
        () => mockAuth.signInWithProvider(any()),
      ).thenAnswer((_) async => mockSignInCred);

      final result = await repository.signInWithApple();

      expect(result, isA<Success<dynamic>>());
      verifyInOrder([
        () => mockAnonUser.linkWithProvider(any()),
        () => mockAnonUser.delete(),
        () => mockAuth.signInWithProvider(any()),
      ]);
    });
  });

  group('signInWithFacebook — 익명 linking 분기', () {
    setUp(() {
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
          accessToken: FakeClassicToken(tokenString: 'fb-access-token'),
        ),
      );
    });

    test('Test F1: 익명 currentUser 존재 시 linkWithCredential 호출, '
        'signInWithCredential 미호출', () async {
      when(() => mockAuth.currentUser).thenReturn(mockAnonUser);
      when(
        () => mockAnonUser.linkWithCredential(any()),
      ).thenAnswer((_) async => mockLinkedCred);

      final result = await repository.signInWithFacebook();

      expect(result, isA<Success<dynamic>>());
      verify(
        () => mockFacebookAuth.login(
          permissions: any(named: 'permissions'),
          loginTracking: any(named: 'loginTracking'),
          loginBehavior: any(named: 'loginBehavior'),
          nonce: any(named: 'nonce'),
        ),
      ).called(1);
      verify(() => mockAnonUser.linkWithCredential(any())).called(1);
      verifyNever(() => mockAuth.signInWithCredential(any()));
    });

    test('Test F2: 비익명 경로 — signInWithCredential 호출, '
        'linkWithCredential 미호출', () async {
      when(() => mockAuth.currentUser).thenReturn(null);
      when(
        () => mockAuth.signInWithCredential(any()),
      ).thenAnswer((_) async => mockSignInCred);

      final result = await repository.signInWithFacebook();

      expect(result, isA<Success<dynamic>>());
      verify(() => mockAuth.signInWithCredential(any())).called(1);
      verifyNever(() => mockAnonUser.linkWithCredential(any()));
    });

    test('Test F3: credential-already-in-use fallback — '
        '_safeDelete + signInWithCredential', () async {
      when(() => mockAuth.currentUser).thenReturn(mockAnonUser);
      when(
        () => mockAnonUser.linkWithCredential(any()),
      ).thenThrow(fb.FirebaseAuthException(code: 'credential-already-in-use'));
      when(
        () => mockAuth.signInWithCredential(any()),
      ).thenAnswer((_) async => mockSignInCred);

      final result = await repository.signInWithFacebook();

      expect(result, isA<Success<dynamic>>());
      verifyInOrder([
        () => mockAnonUser.linkWithCredential(any()),
        () => mockAnonUser.delete(),
        () => mockAuth.signInWithCredential(any()),
      ]);
    });
  });

  group('signUpWithEmail — 익명 linking 분기', () {
    setUp(() {
      // displayName + reload + sendEmailVerification 체이닝 기본 stub.
      when(
        () => mockResultUser.updateDisplayName(any()),
      ).thenAnswer((_) async {});
      when(() => mockResultUser.reload()).thenAnswer((_) async {});
      when(
        () => mockResultUser.sendEmailVerification(),
      ).thenAnswer((_) async {});
    });

    test('Test E1: 익명 linking 성공 — EmailAuthProvider.credential 사용, '
        'createUserWithEmailAndPassword 미호출', () async {
      // Blocker #1-E1: signUpWithEmail 은 _auth.currentUser 를 linking
      // 분기 진입 체크 + sendEmailVerification 대상 refresh 에서 2회 이상
      // 조회한다. 단일 thenReturn 은 두 번째 호출이 첫 호출을 덮어쓰므로
      // callback 기반 sequential stub 으로 호출 횟수에 따라 다른 user 를
      // 반환한다.
      //
      // 주의 (유지보수): 이 stub 은 signUpWithEmail 내부의
      // _auth.currentUser 조회 순서/횟수에 강하게 결합되어 있다.
      // 현재 구현 기준:
      //   - 1회차: linking 분기 진입 체크 (auth_repository.dart line 80
      //     부근) → mockAnonUser (isAnonymous=true) 반환으로 linking
      //     분기로 진입.
      //   - 2회차 이후: linking 성공 후 refresh fallback
      //     (`_auth.currentUser ?? fbUser`, auth_repository.dart line 117
      //     부근) → mockResultUser 반환으로 sendEmailVerification 대상
      //     정식 user 를 공급.
      // signUpWithEmail 구현에서 currentUser 조회 위치/횟수가 변경되면
      // 이 테스트가 잘못된 분기를 검증하거나 의도와 무관하게 실패할 수
      // 있으므로, 구현 리팩터링 시 본 stub 도 함께 조정해야 한다.
      var currentUserCallCount = 0;
      when(() => mockAuth.currentUser).thenAnswer((_) {
        currentUserCallCount++;
        // 1회차: linking 분기 진입 체크 → 익명 user 반환 (isAnonymous=true).
        // 2회차 이후: linking 성공 후 refresh → 정식 user 반환.
        return currentUserCallCount == 1 ? mockAnonUser : mockResultUser;
      });
      when(
        () => mockAnonUser.linkWithCredential(any()),
      ).thenAnswer((_) async => mockLinkedCred);

      final result = await repository.signUpWithEmail(
        email: 'new@example.com',
        password: 'pw12345678',
        displayName: 'Newbie',
      );

      expect(result, isA<Success<dynamic>>());
      expect((result as Success).data.uid, mockResultUser.uid);
      verify(() => mockAnonUser.linkWithCredential(any())).called(1);
      verifyNever(
        () => mockAuth.createUserWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      );
      verify(() => mockResultUser.sendEmailVerification()).called(1);
    });

    test('Test E2: 비익명 경로 — createUserWithEmailAndPassword 호출', () async {
      // 1회차: linking 분기 진입 체크 → null (익명 없음 → 비익명 경로).
      // 2회차 이후: displayName/sendEmailVerification 대상 refresh → 정식 user.
      var currentUserCallCount = 0;
      when(() => mockAuth.currentUser).thenAnswer((_) {
        currentUserCallCount++;
        return currentUserCallCount == 1 ? null : mockResultUser;
      });
      when(
        () => mockAuth.createUserWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => mockSignInCred);

      final result = await repository.signUpWithEmail(
        email: 'new@example.com',
        password: 'pw12345678',
        displayName: 'Newbie',
      );

      expect(result, isA<Success<dynamic>>());
      verify(
        () => mockAuth.createUserWithEmailAndPassword(
          email: 'new@example.com',
          password: 'pw12345678',
        ),
      ).called(1);
      verifyNever(() => mockAnonUser.linkWithCredential(any()));
    });

    test('Test E3: email-already-in-use — 익명 delete 미호출 + '
        'EmailAlreadyInUse Failure', () async {
      when(() => mockAuth.currentUser).thenReturn(mockAnonUser);
      when(
        () => mockAnonUser.linkWithCredential(any()),
      ).thenThrow(fb.FirebaseAuthException(code: 'email-already-in-use'));

      final result = await repository.signUpWithEmail(
        email: 'exists@example.com',
        password: 'pw12345678',
        displayName: 'Exists',
      );

      expect(result, isA<Failure<dynamic>>());
      expect((result as Failure).exception, isA<EmailAlreadyInUse>());
      verifyNever(() => mockAnonUser.delete());
    });
  });
}
