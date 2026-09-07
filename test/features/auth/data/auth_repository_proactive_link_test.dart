// ignore_for_file: lines_longer_than_80_chars
//
// Phase 16 Plan 16-10 Task 3 — proactive account linking (native + Custom Token 재사용).
//
// logged-in user 가 Settings "계정 연결" 섹션 (Surface D) 에서 소셜 provider 를
// proactive 하게 추가하는 흐름의 repository 메서드 검증. native 4 메서드
// (linkGoogle/Apple/Facebook/EmailCredential) + Custom Token wrapper 재사용
// (linkCustomTokenProviderArm — 16-09 산출, 별도 메서드 추가 0).
//
// **email EXCLUDE 계약 (사용자 sign-off 2026-06-02):** linkEmailCredential 은
// reactive(16-08) native 충돌 arm 전용 — Surface D proactive 목록에 call site
// 없음 (mockup §0/§3). 본 테스트는 메서드 mechanics (Test 4) 를 검증하되,
// proactive call site 는 Google/Apple/Facebook 3종.
//
// 9 behavior:
//   T1: linkGoogleCredential() → GoogleSignIn fresh credential →
//       currentUser.linkWithCredential(googleCredential) → success.
//       callable 미호출 (native, UAT A6 invariant).
//   T2: linkAppleCredential() → currentUser.linkWithProvider(AppleAuthProvider) → success
//   T3: linkFacebookCredential() → Facebook credential → linkWithCredential → success
//   T4: linkEmailCredential(email, password) → EmailAuthProvider.credential →
//       linkWithCredential → success (reactive 전용 메서드 mechanics)
//   T5: 사용자 SDK 취소(null) → null (silent, linkedProviders 변경 0)
//   T6: linkWithCredential 'provider-already-linked'/'credential-already-in-use'
//       → AccountAlreadyLinked
//   T7 (reauth boundary): linkWithCredential 'requires-recent-login' →
//       ReauthenticationRequiredException (5분 auth_time boundary)
//   T8 (race-fix): 전 구간 _socialLinkInProgress.begin/finally end (1:1)
//   T9 (proactive Custom Token 재사용): linkCustomTokenProviderArm 재사용
//       (16-09) — 별도 proactive Custom Token 메서드 추가 0 sentinel
//   T10 (PII sentinel, G-16-A6-2 / T-16-15-01): FirebaseAuthException 분기가
//       code 만 담은 debugPrint 1줄을 남기고 email / credential 토큰 본문은
//       남기지 않는다 (실 단말 logcat 원인 특정 가능 + PII 0)

import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
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
import 'package:flutter_starter_kit/features/auth/data/yahoojp_sdk_client.dart';

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockUserCredential extends Mock implements fb.UserCredential {}

class _MockFbUser extends Mock implements fb.User {}

class _MockUserMetadata extends Mock implements fb.UserMetadata {}

class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

class _MockGoogleSignInAccount extends Mock implements GoogleSignInAccount {}

class _MockGoogleSignInAuthentication extends Mock
    implements GoogleSignInAuthentication {}

class _MockFacebookAuth extends Mock implements FacebookAuth {}

class _MockLoginResult extends Mock implements LoginResult {}

class _MockAccessToken extends Mock implements AccessToken {}

class _MockSocialLinkInProgress extends Mock implements SocialLinkInProgress {}

class _MockKakaoSdkClient extends Mock implements KakaoSdkClient {}

class _MockNaverSdkClient extends Mock implements NaverSdkClient {}

class _MockLineSdkClient extends Mock implements LineSdkClient {}

class _MockYahoojpSdkClient extends Mock implements YahoojpSdkClient {}

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class _FakeAuthCredential extends Fake implements fb.AuthCredential {}

class _FakeAppleAuthProvider extends Fake implements fb.AppleAuthProvider {}

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
  late _MockFbUser mockCurrentUser;
  late _MockUserCredential mockLinkResult;
  late _MockUserMetadata mockMetadata;
  late AuthRepository repository;

  setUpAll(() {
    registerFallbackValue(_FakeAuthCredential());
    registerFallbackValue(_FakeAppleAuthProvider());
    registerFallbackValue(fb.AppleAuthProvider());
    registerFallbackValue(LoginTracking.enabled);
    registerFallbackValue(LoginBehavior.nativeWithFallback);
    registerFallbackValue(const <String>[]);
  });

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
    mockCurrentUser = _MockFbUser();
    mockLinkResult = _MockUserCredential();
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

    // _mapFirebaseUser 가 참조하는 fb.User getter default stub.
    when(() => mockCurrentUser.uid).thenReturn('linked-uid');
    when(() => mockCurrentUser.email).thenReturn('user@example.com');
    when(() => mockCurrentUser.emailVerified).thenReturn(true);
    when(() => mockCurrentUser.displayName).thenReturn('User');
    when(() => mockCurrentUser.photoURL).thenReturn(null);
    when(() => mockCurrentUser.isAnonymous).thenReturn(false);
    when(() => mockCurrentUser.metadata).thenReturn(mockMetadata);
    when(() => mockMetadata.creationTime).thenReturn(DateTime.utc(2026, 1, 1));
    when(() => mockCurrentUser.providerData).thenReturn(const []);
    when(() => mockCurrentUser.reload()).thenAnswer((_) async {});

    when(() => mockLinkResult.user).thenReturn(mockCurrentUser);
    when(() => mockAuth.currentUser).thenReturn(mockCurrentUser);
  });

  /// Google SDK fresh credential 획득 stub.
  void stubGoogleFresh() {
    final mockAccount = _MockGoogleSignInAccount();
    final mockGoogleAuth = _MockGoogleSignInAuthentication();
    when(
      () => mockGoogleSignIn.authenticate(),
    ).thenAnswer((_) async => mockAccount);
    when(() => mockAccount.authentication).thenReturn(mockGoogleAuth);
    when(() => mockGoogleAuth.idToken).thenReturn('google-id-token');
  }

  /// Facebook SDK fresh credential 획득 stub.
  void stubFacebookFresh() {
    final mockLoginResult = _MockLoginResult();
    final mockAccessToken = _MockAccessToken();
    when(
      () => mockFacebookAuth.login(
        permissions: any(named: 'permissions'),
        loginTracking: any(named: 'loginTracking'),
      ),
    ).thenAnswer((_) async => mockLoginResult);
    when(() => mockLoginResult.status).thenReturn(LoginStatus.success);
    when(() => mockLoginResult.accessToken).thenReturn(mockAccessToken);
    when(() => mockAccessToken.tokenString).thenReturn('fb-access-token');
  }

  group('T1 — linkGoogleCredential (native, callable 미호출)', () {
    test(
      'GoogleSignIn fresh → currentUser.linkWithCredential → Result.success, callable 미호출',
      () async {
        stubGoogleFresh();
        when(
          () => mockCurrentUser.linkWithCredential(any()),
        ).thenAnswer((_) async => mockLinkResult);

        final result = await repository.linkGoogleCredential();

        expect(result, isA<Success<dynamic>>());
        verify(() => mockCurrentUser.linkWithCredential(any())).called(1);
        // native invariant — Cloud Functions callable 미호출 (A6).
        verifyNever(() => mockFunctions.httpsCallable(any()));
        verifyNever(
          () => mockFunctions.httpsCallable(
            any(),
            options: any(named: 'options'),
          ),
        );
      },
    );
  });

  group('T2 — linkAppleCredential (linkWithProvider)', () {
    test('currentUser.linkWithProvider(AppleAuthProvider) → Result.success', () async {
      when(
        () => mockCurrentUser.linkWithProvider(any()),
      ).thenAnswer((_) async => mockLinkResult);

      final result = await repository.linkAppleCredential();

      expect(result, isA<Success<dynamic>>());
      verify(() => mockCurrentUser.linkWithProvider(any())).called(1);
    });
  });

  group('T3 — linkFacebookCredential', () {
    test('Facebook credential → linkWithCredential → Result.success', () async {
      stubFacebookFresh();
      when(
        () => mockCurrentUser.linkWithCredential(any()),
      ).thenAnswer((_) async => mockLinkResult);

      final result = await repository.linkFacebookCredential();

      expect(result, isA<Success<dynamic>>());
      verify(() => mockCurrentUser.linkWithCredential(any())).called(1);
    });
  });

  group('T4 — linkEmailCredential (reactive 전용 메서드 mechanics)', () {
    test('EmailAuthProvider.credential → linkWithCredential → Result.success', () async {
      when(
        () => mockCurrentUser.linkWithCredential(any()),
      ).thenAnswer((_) async => mockLinkResult);

      final result = await repository.linkEmailCredential(
        email: 'add@example.com',
        password: 'pw12345678',
      );

      expect(result, isA<Success<dynamic>>());
      verify(() => mockCurrentUser.linkWithCredential(any())).called(1);
    });
  });

  group('T5 — 사용자 SDK 취소 → null (no-op)', () {
    test('Google authenticate canceled → null + linkWithCredential 미호출', () async {
      when(() => mockGoogleSignIn.authenticate()).thenThrow(
        const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
      );

      final result = await repository.linkGoogleCredential();

      expect(result, isNull);
      verifyNever(() => mockCurrentUser.linkWithCredential(any()));
    });
  });

  group('T6 — 이미 link 됨 → AccountAlreadyLinked', () {
    test('linkWithCredential provider-already-linked → AccountAlreadyLinked', () async {
      stubGoogleFresh();
      when(() => mockCurrentUser.linkWithCredential(any())).thenThrow(
        fb.FirebaseAuthException(code: 'provider-already-linked'),
      );

      final result = await repository.linkGoogleCredential();

      expect(result, isA<Failure<dynamic>>());
      expect((result! as Failure<dynamic>).exception, isA<AccountAlreadyLinked>());
    });

    test('linkWithCredential credential-already-in-use → AccountAlreadyLinked', () async {
      stubGoogleFresh();
      when(() => mockCurrentUser.linkWithCredential(any())).thenThrow(
        fb.FirebaseAuthException(code: 'credential-already-in-use'),
      );

      final result = await repository.linkGoogleCredential();

      expect(result, isA<Failure<dynamic>>());
      expect((result! as Failure<dynamic>).exception, isA<AccountAlreadyLinked>());
    });
  });

  group('T7 — reauth boundary (requires-recent-login)', () {
    test(
      'linkWithCredential requires-recent-login → ReauthenticationRequiredException',
      () async {
        stubGoogleFresh();
        when(() => mockCurrentUser.linkWithCredential(any())).thenThrow(
          fb.FirebaseAuthException(code: 'requires-recent-login'),
        );

        final result = await repository.linkGoogleCredential();

        expect(result, isA<Failure<dynamic>>());
        expect(
          (result! as Failure<dynamic>).exception,
          isA<ReauthenticationRequiredException>(),
        );
      },
    );

    test(
      'linkWithProvider(Apple) requires-recent-login → ReauthenticationRequiredException',
      () async {
        when(() => mockCurrentUser.linkWithProvider(any())).thenThrow(
          fb.FirebaseAuthException(code: 'requires-recent-login'),
        );

        final result = await repository.linkAppleCredential();

        expect(result, isA<Failure<dynamic>>());
        expect(
          (result! as Failure<dynamic>).exception,
          isA<ReauthenticationRequiredException>(),
        );
      },
    );
  });

  group('T8 — race-fix sentinel (begin/end 1:1)', () {
    test('linkGoogleCredential 전 구간 begin()/end() 1:1', () async {
      stubGoogleFresh();
      when(
        () => mockCurrentUser.linkWithCredential(any()),
      ).thenAnswer((_) async => mockLinkResult);

      await repository.linkGoogleCredential();

      verify(() => mockSocialLinkInProgress.begin()).called(1);
      verify(() => mockSocialLinkInProgress.end()).called(1);
    });

    test('linkAppleCredential 취소 (canceled) 시에도 begin()/end() 1:1', () async {
      when(() => mockCurrentUser.linkWithProvider(any())).thenThrow(
        fb.FirebaseAuthException(code: 'canceled'),
      );

      final result = await repository.linkAppleCredential();

      // Apple 취소 → null (no-op).
      expect(result, isNull);
      verify(() => mockSocialLinkInProgress.begin()).called(1);
      verify(() => mockSocialLinkInProgress.end()).called(1);
    });
  });

  group('T9 — proactive Custom Token = 16-09 wrapper 재사용 (별도 메서드 0)', () {
    test(
      'linkCustomTokenProviderArm 가 proactive 진입에도 동일 메서드 (Test 9 sentinel)',
      () {
        // 16-09 산출 메서드가 proactive arm 의 진입점 — 별도 proactive Custom
        // Token 메서드 추가 0 (재사용). 메서드 tear-off 가 존재함을 컴파일타임에
        // 보장 (linkCustomTokenProviderArm 시그니처 유지).
        final tearOff = repository.linkCustomTokenProviderArm;
        expect(tearOff, isNotNull);
      },
    );
  });

  group('T10 — PII sentinel (G-16-A6-2 / T-16-15-01)', () {
    test(
      'credential-already-in-use 실패 로그에 code 만 남고 email / 토큰 본문은 없다',
      () async {
        final captured = <String>[];
        final originalDebugPrint = debugPrint;
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null) captured.add(message);
        };
        addTearDown(() => debugPrint = originalDebugPrint);

        stubFacebookFresh();
        when(() => mockCurrentUser.linkWithCredential(any())).thenThrow(
          fb.FirebaseAuthException(code: 'credential-already-in-use'),
        );

        final result = await repository.linkFacebookCredential();

        expect(result, isA<Failure<dynamic>>());

        final log = captured.join('\n');
        // 진단성 — 실 단말 logcat 으로 원인 특정이 가능해야 한다.
        expect(log, contains('code='));
        expect(log, contains('credential-already-in-use'));
        // PII 0 — mock email / credential 토큰 문자열이 로그에 없어야 한다.
        expect(log, isNot(contains('user@example.com')));
        expect(log, isNot(contains('fb-access-token')));
      },
    );
  });
}
