// ignore_for_file: lines_longer_than_80_chars

import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/data/kakao_sdk_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/auth_mocks.dart';

class _MockFbUser extends Mock implements fb.User {}

class _MockHttpsCallable extends Mock implements HttpsCallable {}

class _FakeAuthCredential extends Fake implements fb.AuthCredential {}

class _FakeAuthProvider extends Fake implements fb.AuthProvider {}

void main() {
  late MockFirebaseAuth mockAuth;
  late _MockFbUser mockUser;
  late MockGoogleSignIn mockGoogleSignIn;
  late MockFacebookAuth mockFacebookAuth;
  late MockSocialLinkInProgress mockSocialLinkInProgress;
  late MockKakaoSdkClient mockKakaoSdkClient;
  late MockNaverSdkClient mockNaverSdkClient;
  late MockLineSdkClient mockLineSdkClient;
  late MockFirebaseFunctions mockFunctions;
  late _MockHttpsCallable mockCallable;
  late AuthRepository repository;

  setUpAll(() {
    registerFallbackValue(_FakeAuthCredential());
    registerFallbackValue(_FakeAuthProvider());
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    mockAuth = MockFirebaseAuth();
    mockUser = _MockFbUser();
    mockGoogleSignIn = MockGoogleSignIn();
    mockFacebookAuth = MockFacebookAuth();
    mockSocialLinkInProgress = MockSocialLinkInProgress();
    mockKakaoSdkClient = MockKakaoSdkClient();
    mockNaverSdkClient = MockNaverSdkClient();
    mockLineSdkClient = MockLineSdkClient();
    mockFunctions = MockFirebaseFunctions();
    mockCallable = _MockHttpsCallable();

    repository = buildAuthRepository(
      auth: mockAuth,
      googleSignIn: mockGoogleSignIn,
      facebookAuth: mockFacebookAuth,
      socialLinkInProgress: mockSocialLinkInProgress,
      kakaoSdkClient: mockKakaoSdkClient,
      functions: mockFunctions,
      naverSdkClient: mockNaverSdkClient,
      lineSdkClient: mockLineSdkClient,
    );

    // Pitfall 9 — finally logout default stub (Phase 14 LINE 포함).
    when(() => mockKakaoSdkClient.logout()).thenAnswer((_) async {});
    when(() => mockNaverSdkClient.logout()).thenAnswer((_) async {});
    when(() => mockLineSdkClient.logout()).thenAnswer((_) async {});

    // mockAuth.currentUser 기본 — 비익명 경로.
    when(() => mockAuth.currentUser).thenReturn(null);
    when(() => mockUser.isAnonymous).thenReturn(false);
  });

  group('Phase 9.2 R2 — _mapAuthException + _mapFunctionsException 단일 unknown '
      'fallback path', () {
    test('Test U1: signInWithEmail 가 FirebaseAuthException('
        "'account-exists-with-different-credential') throw 시 → "
        'AccountExistsWithDifferentCredential (userMessage 보존)', () async {
      when(
        () => mockAuth.signInWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(
        fb.FirebaseAuthException(
          code: 'account-exists-with-different-credential',
          email: 'collide@example.com',
        ),
      );

      final result = await repository.signInWithEmail(
        email: 'a@b.com',
        password: 'pw12345678',
      );

      expect(result, isA<Failure<dynamic>>());
      final ex = (result as Failure).exception;
      expect(ex, isA<AccountExistsWithDifferentCredential>());
      // email 필드 보존 — Phase 17 부활 anchor.
      expect(
        (ex as AccountExistsWithDifferentCredential).email,
        'collide@example.com',
      );
      // userMessage = 'errorAccountExistsWithDifferentCredential' 보존 —
      // exception_l10n.dart 의 special-case branch 가 instance type-check
      // 으로 unknown 경로 진입.
      expect(ex.userMessage, 'errorAccountExistsWithDifferentCredential');
    });

    test('Test U2: signInWithKakao 가 FirebaseFunctionsException('
        "'already-exists') throw 시 → AccountExistsWithDifferentCredential "
        '(email null PII 미응답)', () async {
      // KakaoSdkClient 성공 → Cloud Function 가 already-exists throw.
      when(() => mockKakaoSdkClient.signIn()).thenAnswer(
        (_) async => const KakaoSignInResult(idToken: 'IDT', nonce: 'NONCE'),
      );
      when(
        () =>
            mockFunctions.httpsCallable(any(), options: any(named: 'options')),
      ).thenReturn(mockCallable);
      when(() => mockCallable.call<Map<String, dynamic>>(any())).thenThrow(
        FirebaseFunctionsException(
          code: 'already-exists',
          message: 'errorAccountExistsWithDifferentCredential',
        ),
      );

      final result = await repository.signInWithKakao();

      expect(result, isA<Failure<dynamic>>());
      final ex = (result! as Failure).exception;
      expect(ex, isA<AccountExistsWithDifferentCredential>());
      // Cloud Function PII 미응답 invariant — email null 보존
      // (Phase 12.1 R3 정합).
      expect((ex as AccountExistsWithDifferentCredential).email, isNull);
    });
  });
}
