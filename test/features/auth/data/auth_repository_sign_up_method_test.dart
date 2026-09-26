// Phase 16.7 Plan 01 — 가입 수단 기록 hook 의 이메일 경로 경계 (D-14 · D-18).
//
// `AuthRepository` 의 named optional `recordSignUpMethod` 콜백에 기록 목록을
// 주입해, 「가입」 이벤트(D-14)에서만 정확히 1회 기록되고 재로그인 · 이메일
// 충돌에서는 0회임을 고정한다. 한 번 쓴 값이 이후 경로에서 덮어써지지 않는
// 보장(D-18)은 이 이벤트 경계 + 회귀 테스트로 지킨다.
//
// E1 익명 → linkWithCredential 성공 → 1회 'password'
// E2 비익명 → createUserWithEmailAndPassword 성공 → 1회 'password'
// E3 email-already-in-use → 0회 + Result.failure
// E4 signInWithEmail(재로그인) 성공 → 0회
// E5 콜백 미주입(positional 9 인자만) → signUpWithEmail 성공 · throw 0
//
// 콜백은 `unawaited` 로 호출되므로 단언 전에 microtask 를 비운다.
// plan 03 에서 소셜 · 연결 · credential-already-in-use 경로로 확장된다.

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

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockUserCredential extends Mock implements fb.UserCredential {}

class _MockFbUser extends Mock implements fb.User {}

class _MockUserMetadata extends Mock implements fb.UserMetadata {}

class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

class _MockFacebookAuth extends Mock implements FacebookAuth {}

class _MockSocialLinkInProgress extends Mock implements SocialLinkInProgress {}

class _MockKakaoSdkClient extends Mock implements KakaoSdkClient {}

class _MockNaverSdkClient extends Mock implements NaverSdkClient {}

class _MockLineSdkClient extends Mock implements LineSdkClient {}

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class _FakeAuthCredential extends Fake implements fb.AuthCredential {}

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
}
