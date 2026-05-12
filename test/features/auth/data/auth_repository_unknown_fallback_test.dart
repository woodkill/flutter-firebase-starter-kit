// ignore_for_file: lines_longer_than_80_chars

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
import 'package:flutter_starter_kit/features/auth/data/naver_sdk_client.dart';

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockFbUser extends Mock implements fb.User {}

class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

class _MockFacebookAuth extends Mock implements FacebookAuth {}

class _MockSocialLinkInProgress extends Mock implements SocialLinkInProgress {}

class _MockKakaoSdkClient extends Mock implements KakaoSdkClient {}

class _MockNaverSdkClient extends Mock implements NaverSdkClient {}

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class _MockHttpsCallable extends Mock implements HttpsCallable {}

class _FakeAuthCredential extends Fake implements fb.AuthCredential {}

class _FakeAuthProvider extends Fake implements fb.AuthProvider {}

void main() {
  late _MockFirebaseAuth mockAuth;
  late _MockFbUser mockUser;
  late _MockGoogleSignIn mockGoogleSignIn;
  late _MockFacebookAuth mockFacebookAuth;
  late _MockSocialLinkInProgress mockSocialLinkInProgress;
  late _MockKakaoSdkClient mockKakaoSdkClient;
  late _MockNaverSdkClient mockNaverSdkClient;
  late _MockFirebaseFunctions mockFunctions;
  late _MockHttpsCallable mockCallable;
  late AuthRepository repository;

  setUpAll(() {
    registerFallbackValue(_FakeAuthCredential());
    registerFallbackValue(_FakeAuthProvider());
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    mockAuth = _MockFirebaseAuth();
    mockUser = _MockFbUser();
    mockGoogleSignIn = _MockGoogleSignIn();
    mockFacebookAuth = _MockFacebookAuth();
    mockSocialLinkInProgress = _MockSocialLinkInProgress();
    mockKakaoSdkClient = _MockKakaoSdkClient();
    mockNaverSdkClient = _MockNaverSdkClient();
    mockFunctions = _MockFirebaseFunctions();
    mockCallable = _MockHttpsCallable();

    repository = AuthRepository(
      mockAuth,
      mockGoogleSignIn,
      mockFacebookAuth,
      mockSocialLinkInProgress,
      mockKakaoSdkClient,
      mockFunctions,
      mockNaverSdkClient,
      // Phase 10.2 D-A2: onResetOnboarding 콜백 no-op (logout invariant
      // 비검증).
      () async {},
    );

    // Pitfall 9 — finally logout default stub.
    when(() => mockKakaoSdkClient.logout()).thenAnswer((_) async {});
    when(() => mockNaverSdkClient.logout()).thenAnswer((_) async {});

    // mockAuth.currentUser 기본 — 비익명 경로.
    when(() => mockAuth.currentUser).thenReturn(null);
    when(() => mockUser.isAnonymous).thenReturn(false);
  });

  group(
    'Phase 9.2 R2 — _mapAuthException + _mapFunctionsException 단일 unknown '
    'fallback path',
    () {
      test(
        'Test U1: signInWithEmail 가 FirebaseAuthException('
        "'account-exists-with-different-credential') throw 시 → "
        'AccountExistsWithDifferentCredential (userMessage 보존)',
        () async {
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
          expect(
            ex.userMessage,
            'errorAccountExistsWithDifferentCredential',
          );
        },
      );

      test(
        'Test U2: signInWithKakao 가 FirebaseFunctionsException('
        "'already-exists') throw 시 → AccountExistsWithDifferentCredential "
        '(email null PII 미응답)',
        () async {
          // KakaoSdkClient 성공 → Cloud Function 가 already-exists throw.
          when(() => mockKakaoSdkClient.signIn()).thenAnswer(
            (_) async =>
                const KakaoSignInResult(idToken: 'IDT', nonce: 'NONCE'),
          );
          when(
            () => mockFunctions.httpsCallable(any()),
          ).thenReturn(mockCallable);
          when(
            () => mockCallable.call<Map<String, dynamic>>(any()),
          ).thenThrow(
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
          expect(
            (ex as AccountExistsWithDifferentCredential).email,
            isNull,
          );
        },
      );
    },
  );
}
