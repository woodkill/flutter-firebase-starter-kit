// Phase 16.7 Plan 01 · 03 — 가입 수단 기록 hook 의 D-14 이벤트 경계 (D-18).
//
// `AuthRepository` 의 named optional `recordSignUpMethod` 콜백에 기록 목록을
// 주입해, 「가입」 이벤트(D-14)에서만 정확히 1회 기록되고 재로그인 · 충돌
// fallback · 연결 · Custom Token 경로에서는 0회임을 고정한다. 한 번 쓴 값이
// 이후 경로에서 덮어써지지 않는 보장(D-18)은 이 이벤트 경계 + 회귀 테스트로
// 지킨다 (쓰기 전 존재 확인 가드는 두지 않는다).
//
// 이메일 (plan 01)
// E1 익명 → linkWithCredential 성공 → 1회 password
// E2 비익명 → createUserWithEmailAndPassword 성공 → 1회 password
// E3 email-already-in-use → 0회 + Result.failure
// E4 signInWithEmail(재로그인) 성공 → 0회
// E5 콜백 미주입(positional 9 인자만) → signUpWithEmail 성공 · throw 0
//
// 소셜 native (plan 03) — 가입 = 익명 link 정상 반환 또는 비익명 isNewUser
// G1 익명 link 성공(isNewUser=false stub) → 1회 google.com
// G2 credential-already-in-use → 익명 폐기 + 기존 계정 로그인 → 0회
// G3 email-already-in-use → Result.failure → 0회
// G4 비익명 isNewUser=true → 1회 · G5 비익명 isNewUser=false → 0회
// A1 익명 linkWithProvider 성공 → 1회 apple.com
// A2 credential-already-in-use(서버 credential 재사용) → 0회
// A3 비익명 signInWithProvider isNewUser=true → 1회
// F1 익명 link 성공 → 1회 facebook.com · F2 Classic 충돌 fallback → 0회
// F3 비익명 isNewUser=true → 1회 · F4 비익명 isNewUser=false → 0회
//
// 연결 · Custom Token (plan 03) — 전부 0회 (isNewUser=true stub 이어도)
// L1 linkGoogleCredential · L2 linkPendingNativeCredential ·
// L3 linkCustomTokenProviderArm(callable 성공)
// C1 signInWithKakao · C2 signInWithNaver · C3 signInWithLine
// (CT 가입 수단은 서버 resolveIdentity 신규 등록 tx 가 기록한다 — plan 02)
//
// 충돌 fallback 케이스(G2 · A2 · F2)는 익명 delete 호출을 함께 단언해 실제로
// fallback 분기를 탔음을 증명한다. 콜백은 `unawaited` 로 호출되므로 단언 전에
// microtask 를 비운다.

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

import 'auth_test_fakes.dart';

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockUserCredential extends Mock implements fb.UserCredential {}

class _MockAdditionalUserInfo extends Mock implements fb.AdditionalUserInfo {}

class _MockFbUser extends Mock implements fb.User {}

class _MockUserMetadata extends Mock implements fb.UserMetadata {}

class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

class _MockGoogleSignInAccount extends Mock implements GoogleSignInAccount {}

class _MockFacebookAuth extends Mock implements FacebookAuth {}

class _MockSocialLinkInProgress extends Mock implements SocialLinkInProgress {}

class _MockKakaoSdkClient extends Mock implements KakaoSdkClient {}

class _MockNaverSdkClient extends Mock implements NaverSdkClient {}

class _MockLineSdkClient extends Mock implements LineSdkClient {}

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class _MockHttpsCallable extends Mock implements HttpsCallable {}

class _MockHttpsCallableResult extends Mock
    implements HttpsCallableResult<Map<String, dynamic>> {}

class _FakeAuthCredential extends Fake implements fb.AuthCredential {}

class _FakeHttpsCallableOptions extends Fake implements HttpsCallableOptions {}

/// 익명 사용자 uid — link 성공 뒤에도 같은 uid 로 정식 승격된다.
const _anonUid = 'ANON';

/// 충돌 fallback · 재로그인으로 로그인되는 기존 계정 uid.
const _existingUid = 'EXISTING';

/// 비익명 신규 가입으로 새로 만들어지는 계정 uid.
const _newUid = 'NEW';

/// Custom Token callable 이 돌려주는 토큰 (fixture).
const _customToken = 'CT';

/// `unawaited` 콜백이 실행될 때까지 microtask 를 비운다.
Future<void> _flushMicrotasks() async {
  for (var i = 0; i < 3; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _MockFirebaseAuth mockAuth;
  late _MockGoogleSignIn mockGoogleSignIn;
  late _MockFacebookAuth mockFacebookAuth;
  late _MockSocialLinkInProgress mockSocialLinkInProgress;
  late _MockKakaoSdkClient mockKakaoSdkClient;
  late _MockNaverSdkClient mockNaverSdkClient;
  late _MockLineSdkClient mockLineSdkClient;
  late _MockFirebaseFunctions mockFunctions;
  late _MockUserCredential mockCredential;
  late _MockFbUser mockUser;
  late _MockUserMetadata mockMetadata;
  late List<(String, String)> recorded;
  late AuthRepository repository;

  setUpAll(() {
    registerFallbackValue(_FakeAuthCredential());
    registerFallbackValue(fb.AppleAuthProvider());
    registerFallbackValue(LoginTracking.enabled);
    registerFallbackValue(LoginBehavior.nativeWithFallback);
    registerFallbackValue(const <String>[]);
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(_FakeHttpsCallableOptions());
  });

  /// 기록 콜백을 주입한 repository 를 만든다 (positional 9 인자 불변).
  AuthRepository buildRepository({bool injectRecorder = true}) {
    if (!injectRecorder) {
      return AuthRepository(
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
    }
    return AuthRepository(
      mockAuth,
      mockGoogleSignIn,
      mockFacebookAuth,
      mockSocialLinkInProgress,
      mockKakaoSdkClient,
      mockFunctions,
      mockNaverSdkClient,
      mockLineSdkClient,
      () async {},
      recordSignUpMethod: (uid, id) async => recorded.add((uid, id)),
    );
  }

  /// `_mapFirebaseUser` 가 읽는 getter 를 합성값으로 채운 [fb.User] 를 만든다.
  ///
  /// `emailVerified` 는 true 라 자동 인증 메일 helper 가 즉시 no-op 이다.
  _MockFbUser buildFbUser(String uid, {bool isAnonymous = false}) {
    final user = _MockFbUser();
    when(() => user.uid).thenReturn(uid);
    when(() => user.isAnonymous).thenReturn(isAnonymous);
    when(() => user.email).thenReturn('$uid@example.com');
    when(() => user.emailVerified).thenReturn(true);
    when(() => user.displayName).thenReturn(uid);
    when(() => user.photoURL).thenReturn(null);
    when(() => user.metadata).thenReturn(mockMetadata);
    when(() => user.providerData).thenReturn(<fb.UserInfo>[]);
    return user;
  }

  /// [user] 를 담고 `additionalUserInfo.isNewUser` 가 [isNewUser] 인
  /// credential 을 만든다 (Mock 함정 1 — additionalUserInfo nullable).
  _MockUserCredential buildCredential(fb.User user, {required bool isNewUser}) {
    final credential = _MockUserCredential();
    final info = _MockAdditionalUserInfo();
    when(() => credential.user).thenReturn(user);
    when(() => credential.additionalUserInfo).thenReturn(info);
    when(() => info.isNewUser).thenReturn(isNewUser);
    return credential;
  }

  /// 익명 사용자를 currentUser 로 두고 돌려준다 (delete 는 성공 stub).
  _MockFbUser stubAnonymousCurrentUser() {
    final anonymous = buildFbUser(_anonUid, isAnonymous: true);
    when(() => anonymous.delete()).thenAnswer((_) async {});
    when(() => mockAuth.currentUser).thenReturn(anonymous);
    return anonymous;
  }

  /// Google 계정 선택 성공 stub — idToken 이 있는 로컬 credential 을 만든다.
  void stubGoogleAccount() {
    final account = _MockGoogleSignInAccount();
    when(() => account.authentication).thenReturn(
      const GoogleSignInAuthentication(idToken: 'google-id-token-fixture'),
    );
    when(() => account.email).thenReturn('google-fixture@example.com');
    when(
      () => mockGoogleSignIn.authenticate(),
    ).thenAnswer((_) async => account);
  }

  /// Facebook Classic 로그인 성공 stub + 사진 갱신 Graph 응답(사진 없음).
  void stubFacebookClassicLogin() {
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
        accessToken: FakeClassicToken(tokenString: 'facebook-token-fixture'),
      ),
    );
    when(
      () => mockFacebookAuth.getUserData(fields: 'picture.type(large)'),
    ).thenAnswer((_) async => <String, dynamic>{});
  }

  /// Custom Token callable 성공 stub — 서버가 신규 가입(isNewUser=true)으로
  /// 응답하고 `signInWithCustomToken` 도 isNewUser=true credential 을 준다.
  void stubCustomTokenSignIn(fb.User user) {
    final callable = _MockHttpsCallable();
    final response = _MockHttpsCallableResult();
    final credential = buildCredential(user, isNewUser: true);
    when(
      () => mockFunctions.httpsCallable(any(), options: any(named: 'options')),
    ).thenReturn(callable);
    when(() => response.data).thenReturn(<String, dynamic>{
      'customToken': _customToken,
      'isNewUser': true,
    });
    when(
      () => callable.call<Map<String, dynamic>>(any()),
    ).thenAnswer((_) async => response);
    when(
      () => mockAuth.signInWithCustomToken(_customToken),
    ).thenAnswer((_) async => credential);
  }

  setUp(() {
    mockAuth = _MockFirebaseAuth();
    mockGoogleSignIn = _MockGoogleSignIn();
    mockFacebookAuth = _MockFacebookAuth();
    mockSocialLinkInProgress = _MockSocialLinkInProgress();
    mockKakaoSdkClient = _MockKakaoSdkClient();
    mockNaverSdkClient = _MockNaverSdkClient();
    mockLineSdkClient = _MockLineSdkClient();
    mockFunctions = _MockFirebaseFunctions();
    mockCredential = _MockUserCredential();
    mockUser = _MockFbUser();
    mockMetadata = _MockUserMetadata();
    recorded = <(String, String)>[];
    repository = buildRepository();

    // _mapFirebaseUser 가 참조하는 fb.User getter — 합성값만 쓴다.
    when(() => mockUser.uid).thenReturn('U1');
    when(() => mockUser.email).thenReturn('u1@example.com');
    when(() => mockUser.emailVerified).thenReturn(false);
    when(() => mockUser.displayName).thenReturn('U One');
    when(() => mockUser.photoURL).thenReturn(null);
    when(() => mockUser.metadata).thenReturn(mockMetadata);
    when(() => mockUser.providerData).thenReturn(<fb.UserInfo>[]);
    when(() => mockMetadata.creationTime).thenReturn(DateTime.utc(2026, 1, 1));
    when(() => mockCredential.user).thenReturn(mockUser);

    // signUpWithEmail 후속 단계 (displayName · reload · 인증 메일).
    when(() => mockUser.updateDisplayName(any())).thenAnswer((_) async {});
    when(() => mockUser.reload()).thenAnswer((_) async {});
    when(() => mockUser.sendEmailVerification()).thenAnswer((_) async {});

    // Custom Token SDK 는 모든 경로에서 finally logout 한다 (1회성 토큰).
    when(() => mockKakaoSdkClient.logout()).thenAnswer((_) async {});
    when(() => mockNaverSdkClient.logout()).thenAnswer((_) async {});
    when(() => mockLineSdkClient.logout()).thenAnswer((_) async {});

    // 기본은 비익명 경로 — 개별 테스트가 익명 사용자로 override 한다.
    when(() => mockAuth.currentUser).thenReturn(null);
  });

  group('signUpWithEmail 가입 수단 기록 경계 (D-14)', () {
    test('E1 익명 → linkWithCredential 성공 → password 1회 기록', () async {
      // 익명 사용자가 link 성공 뒤 같은 uid 의 정식 사용자가 된다.
      when(() => mockUser.isAnonymous).thenReturn(true);
      when(() => mockAuth.currentUser).thenReturn(mockUser);
      when(
        () => mockUser.linkWithCredential(any()),
      ).thenAnswer((_) async => mockCredential);

      final result = await repository.signUpWithEmail(
        email: 'u1@example.com',
        password: 'password123',
        displayName: 'U One',
      );
      await _flushMicrotasks();

      expect(result, isA<Success<dynamic>>());
      verify(() => mockUser.linkWithCredential(any())).called(1);
      verifyNever(
        () => mockAuth.createUserWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      );
      expect(recorded, <(String, String)>[('U1', 'password')]);
    });

    test('E2 비익명 → createUser 성공 → password 1회 기록', () async {
      when(
        () => mockAuth.createUserWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => mockCredential);

      final result = await repository.signUpWithEmail(
        email: 'u1@example.com',
        password: 'password123',
        displayName: 'U One',
      );
      await _flushMicrotasks();

      expect(result, isA<Success<dynamic>>());
      expect(recorded, <(String, String)>[('U1', 'password')]);
    });

    test('E3 email-already-in-use → 기록 0회 + Result.failure', () async {
      when(
        () => mockAuth.createUserWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(fb.FirebaseAuthException(code: 'email-already-in-use'));

      final result = await repository.signUpWithEmail(
        email: 'u1@example.com',
        password: 'password123',
        displayName: 'U One',
      );
      await _flushMicrotasks();

      expect(result, isA<Failure<dynamic>>());
      expect((result as Failure).exception, isA<EmailAlreadyInUse>());
      expect(recorded, isEmpty);
    });
  });

  group('재로그인 · 미주입 경계', () {
    test('E4 signInWithEmail(재로그인) 성공 → 기록 0회', () async {
      when(
        () => mockAuth.signInWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => mockCredential);

      final result = await repository.signInWithEmail(
        email: 'u1@example.com',
        password: 'password123',
      );
      await _flushMicrotasks();

      expect(result, isA<Success<dynamic>>());
      expect(recorded, isEmpty);
    });

    test('E5 콜백 미주입(positional 9 인자만) → signUpWithEmail 성공 · '
        'throw 0 (no-op 기본값)', () async {
      final plainRepository = buildRepository(injectRecorder: false);
      when(
        () => mockAuth.createUserWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => mockCredential);

      final result = await plainRepository.signUpWithEmail(
        email: 'u1@example.com',
        password: 'password123',
        displayName: 'U One',
      );
      await _flushMicrotasks();

      expect(result, isA<Success<dynamic>>());
      expect(recorded, isEmpty);
    });
  });

  group('Google 가입 수단 기록 경계 (D-14)', () {
    setUp(stubGoogleAccount);

    test('G1 익명 link 성공(isNewUser=false) → google.com 1회', () async {
      // Firebase 는 link 분기에서 isNewUser=false 를 돌려준다 (Gap A) —
      // link 정상 반환 자체가 가입이다.
      final anonymous = stubAnonymousCurrentUser();
      final promoted = buildFbUser(_anonUid);
      final linked = buildCredential(promoted, isNewUser: false);
      when(
        () => anonymous.linkWithCredential(any()),
      ).thenAnswer((_) async => linked);

      final result = await repository.signInWithGoogle();
      await _flushMicrotasks();

      expect(result, isA<Success<dynamic>>());
      verifyNever(() => mockAuth.signInWithCredential(any()));
      expect(recorded, <(String, String)>[(_anonUid, 'google.com')]);
    });

    test('G2 credential-already-in-use → 익명 폐기 + 기존 계정 → 0회', () async {
      final anonymous = stubAnonymousCurrentUser();
      when(
        () => anonymous.linkWithCredential(any()),
      ).thenThrow(fb.FirebaseAuthException(code: 'credential-already-in-use'));
      final existing = buildFbUser(_existingUid);
      final signedIn = buildCredential(existing, isNewUser: false);
      when(
        () => mockAuth.signInWithCredential(any()),
      ).thenAnswer((_) async => signedIn);

      final result = await repository.signInWithGoogle();
      await _flushMicrotasks();

      expect(result, isA<Success<dynamic>>());
      // fallback 분기를 실제로 탔다 — 익명 폐기 뒤 기존 계정 로그인.
      verify(() => anonymous.delete()).called(1);
      verify(() => mockAuth.signInWithCredential(any())).called(1);
      expect(recorded, isEmpty);
    });

    test('G3 email-already-in-use → Result.failure · 0회', () async {
      final anonymous = stubAnonymousCurrentUser();
      when(
        () => anonymous.linkWithCredential(any()),
      ).thenThrow(fb.FirebaseAuthException(code: 'email-already-in-use'));
      // 기존 provider 조회 실패 → graceful null (이 케이스 scope 밖).
      when(
        () =>
            mockFunctions.httpsCallable(any(), options: any(named: 'options')),
      ).thenThrow(Exception('callable unavailable'));

      final result = await repository.signInWithGoogle();
      await _flushMicrotasks();

      expect(result, isA<Failure<dynamic>>());
      expect(
        (result! as Failure<dynamic>).exception,
        isA<AccountExistsWithDifferentCredential>(),
      );
      verifyNever(() => anonymous.delete());
      verifyNever(() => mockAuth.signInWithCredential(any()));
      expect(recorded, isEmpty);
    });

    test('G4 비익명 isNewUser=true → google.com 1회', () async {
      final created = buildFbUser(_newUid);
      final signedIn = buildCredential(created, isNewUser: true);
      when(
        () => mockAuth.signInWithCredential(any()),
      ).thenAnswer((_) async => signedIn);

      final result = await repository.signInWithGoogle();
      await _flushMicrotasks();

      expect(result, isA<Success<dynamic>>());
      expect(recorded, <(String, String)>[(_newUid, 'google.com')]);
    });

    test('G5 비익명 재로그인 isNewUser=false → 0회', () async {
      final existing = buildFbUser(_existingUid);
      final signedIn = buildCredential(existing, isNewUser: false);
      when(
        () => mockAuth.signInWithCredential(any()),
      ).thenAnswer((_) async => signedIn);

      final result = await repository.signInWithGoogle();
      await _flushMicrotasks();

      expect(result, isA<Success<dynamic>>());
      expect(recorded, isEmpty);
    });
  });

  group('Apple 가입 수단 기록 경계 (D-14)', () {
    test('A1 익명 linkWithProvider 성공 → apple.com 1회', () async {
      final anonymous = stubAnonymousCurrentUser();
      final promoted = buildFbUser(_anonUid);
      final linked = buildCredential(promoted, isNewUser: false);
      when(
        () => anonymous.linkWithProvider(any()),
      ).thenAnswer((_) async => linked);

      final result = await repository.signInWithApple();
      await _flushMicrotasks();

      expect(result, isA<Success<dynamic>>());
      expect(recorded, <(String, String)>[(_anonUid, 'apple.com')]);
    });

    test('A2 credential-already-in-use(서버 credential 재사용) → 0회', () async {
      final anonymous = stubAnonymousCurrentUser();
      final pending = _FakeAuthCredential();
      when(() => anonymous.linkWithProvider(any())).thenThrow(
        fb.FirebaseAuthException(
          code: 'credential-already-in-use',
          credential: pending,
        ),
      );
      final existing = buildFbUser(_existingUid);
      final signedIn = buildCredential(existing, isNewUser: false);
      when(
        () => mockAuth.signInWithCredential(any()),
      ).thenAnswer((_) async => signedIn);

      final result = await repository.signInWithApple();
      await _flushMicrotasks();

      expect(result, isA<Success<dynamic>>());
      // fallback 분기를 실제로 탔다 — 익명 폐기 뒤 서버 credential 로 로그인.
      verify(() => anonymous.delete()).called(1);
      verify(() => mockAuth.signInWithCredential(pending)).called(1);
      verifyNever(() => mockAuth.signInWithProvider(any()));
      expect(recorded, isEmpty);
    });

    test('A3 비익명 signInWithProvider isNewUser=true → 1회', () async {
      final created = buildFbUser(_newUid);
      final signedIn = buildCredential(created, isNewUser: true);
      when(
        () => mockAuth.signInWithProvider(any()),
      ).thenAnswer((_) async => signedIn);

      final result = await repository.signInWithApple();
      await _flushMicrotasks();

      expect(result, isA<Success<dynamic>>());
      expect(recorded, <(String, String)>[(_newUid, 'apple.com')]);
    });
  });

  group('Facebook 가입 수단 기록 경계 (D-14)', () {
    setUp(stubFacebookClassicLogin);

    test('F1 익명 link 성공 → facebook.com 1회', () async {
      final anonymous = stubAnonymousCurrentUser();
      final promoted = buildFbUser(_anonUid);
      final linked = buildCredential(promoted, isNewUser: false);
      when(
        () => anonymous.linkWithCredential(any()),
      ).thenAnswer((_) async => linked);

      final result = await repository.signInWithFacebook();
      await _flushMicrotasks();

      expect(result, isA<Success<dynamic>>());
      expect(recorded, <(String, String)>[(_anonUid, 'facebook.com')]);
    });

    test('F2 Classic credential-already-in-use fallback → 0회', () async {
      final anonymous = stubAnonymousCurrentUser();
      when(
        () => anonymous.linkWithCredential(any()),
      ).thenThrow(fb.FirebaseAuthException(code: 'credential-already-in-use'));
      final existing = buildFbUser(_existingUid);
      final signedIn = buildCredential(existing, isNewUser: false);
      when(
        () => mockAuth.signInWithCredential(any()),
      ).thenAnswer((_) async => signedIn);

      final result = await repository.signInWithFacebook();
      await _flushMicrotasks();

      expect(result, isA<Success<dynamic>>());
      // fallback 분기를 실제로 탔다 — 익명 폐기 뒤 같은 credential 로 로그인.
      verify(() => anonymous.delete()).called(1);
      verify(() => mockAuth.signInWithCredential(any())).called(1);
      expect(recorded, isEmpty);
    });

    test('F3 비익명 isNewUser=true → facebook.com 1회', () async {
      final created = buildFbUser(_newUid);
      final signedIn = buildCredential(created, isNewUser: true);
      when(
        () => mockAuth.signInWithCredential(any()),
      ).thenAnswer((_) async => signedIn);

      final result = await repository.signInWithFacebook();
      await _flushMicrotasks();

      expect(result, isA<Success<dynamic>>());
      expect(recorded, <(String, String)>[(_newUid, 'facebook.com')]);
    });

    test('F4 비익명 재로그인 isNewUser=false → 0회', () async {
      final existing = buildFbUser(_existingUid);
      final signedIn = buildCredential(existing, isNewUser: false);
      when(
        () => mockAuth.signInWithCredential(any()),
      ).thenAnswer((_) async => signedIn);

      final result = await repository.signInWithFacebook();
      await _flushMicrotasks();

      expect(result, isA<Success<dynamic>>());
      expect(recorded, isEmpty);
    });
  });

  group('연결 · CT 경로 0회 (D-14)', () {
    // 연결 · CT 경로는 isNewUser=true 를 돌려받아도 클라이언트가 기록하지
    // 않는다 — 가입 수단은 가입 순간 한 번만 쓰인다 (D-18).
    test('L1 linkGoogleCredential 성공 → 0회', () async {
      stubGoogleAccount();
      final existing = buildFbUser(_existingUid);
      when(() => mockAuth.currentUser).thenReturn(existing);
      final linked = buildCredential(existing, isNewUser: true);
      when(
        () => existing.linkWithCredential(any()),
      ).thenAnswer((_) async => linked);

      final result = await repository.linkGoogleCredential();
      await _flushMicrotasks();

      expect(result, isA<Success<dynamic>>());
      verify(() => existing.linkWithCredential(any())).called(1);
      expect(recorded, isEmpty);
    });

    test('L2 linkPendingNativeCredential 성공 → 0회', () async {
      stubGoogleAccount();
      final existing = buildFbUser(_existingUid);
      when(() => mockAuth.currentUser).thenReturn(existing);
      final pending = _FakeAuthCredential();
      final linked = buildCredential(existing, isNewUser: true);
      when(
        () => existing.linkWithCredential(any()),
      ).thenAnswer((_) async => linked);

      final result = await repository.linkPendingNativeCredential(
        existingProvider: AccountProvider.google,
        pendingCredential: pending,
      );
      await _flushMicrotasks();

      expect(result, isA<Success<dynamic>>());
      verify(() => existing.linkWithCredential(pending)).called(1);
      expect(recorded, isEmpty);
    });

    test('L3 linkCustomTokenProviderArm(callable 성공) → 0회', () async {
      final existing = buildFbUser(_existingUid);
      when(() => mockAuth.currentUser).thenReturn(existing);
      when(() => existing.reload()).thenAnswer((_) async {});
      when(
        () => existing.getIdToken(true),
      ).thenAnswer((_) async => 'caller-fresh-id-token');
      when(() => mockLineSdkClient.signIn()).thenAnswer(
        (_) async => const LineSignInResult(
          idToken: 'line-id-token',
          nonce: 'nonce',
          accessToken: 'line-at',
        ),
      );
      final callable = _MockHttpsCallable();
      final response = _MockHttpsCallableResult();
      when(
        () => mockFunctions.httpsCallable(
          'linkCustomTokenProvider',
          options: any(named: 'options'),
        ),
      ).thenReturn(callable);
      when(() => response.data).thenReturn(<String, dynamic>{'ok': true});
      when(
        () => callable.call<Map<String, dynamic>>(any()),
      ).thenAnswer((_) async => response);

      final result = await repository.linkCustomTokenProviderArm(
        targetProvider: AccountProvider.line,
      );
      await _flushMicrotasks();

      expect(result, isA<Success<dynamic>>());
      verify(() => callable.call<Map<String, dynamic>>(any())).called(1);
      expect(recorded, isEmpty);
    });

    test('C1 signInWithKakao(isNewUser=true) → 0회', () async {
      when(() => mockKakaoSdkClient.signIn()).thenAnswer(
        (_) async => const KakaoSignInResult(idToken: 'IDT', nonce: 'NONCE'),
      );
      stubCustomTokenSignIn(buildFbUser(_newUid));

      final result = await repository.signInWithKakao();
      await _flushMicrotasks();

      expect(result, isA<Success<dynamic>>());
      verify(() => mockAuth.signInWithCustomToken(_customToken)).called(1);
      expect(recorded, isEmpty);
    });

    test('C2 signInWithNaver(isNewUser=true) → 0회', () async {
      when(
        () => mockNaverSdkClient.signIn(),
      ).thenAnswer((_) async => const NaverAppSignIn(accessToken: 'AT'));
      stubCustomTokenSignIn(buildFbUser(_newUid));

      final result = await repository.signInWithNaver();
      await _flushMicrotasks();

      expect(result, isA<Success<dynamic>>());
      verify(() => mockAuth.signInWithCustomToken(_customToken)).called(1);
      expect(recorded, isEmpty);
    });

    test('C3 signInWithLine(isNewUser=true) → 0회', () async {
      when(() => mockLineSdkClient.signIn()).thenAnswer(
        (_) async => const LineSignInResult(
          idToken: 'line-id-token',
          nonce: 'nonce',
          accessToken: 'line-at',
        ),
      );
      stubCustomTokenSignIn(buildFbUser(_newUid));

      final result = await repository.signInWithLine();
      await _flushMicrotasks();

      expect(result, isA<Success<dynamic>>());
      verify(() => mockAuth.signInWithCustomToken(_customToken)).called(1);
      expect(recorded, isEmpty);
    });
  });
}
