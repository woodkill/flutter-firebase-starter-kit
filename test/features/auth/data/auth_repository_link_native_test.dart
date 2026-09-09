// ignore_for_file: lines_longer_than_80_chars
//
// Phase 16 Plan 16-08 Task 1 — native reactive account linking.
//
// pendingCredential 보존 (`_mapAuthException` arm) + `linkPendingNativeCredential`
// 메서드 (reauth → linkWithCredential) 검증. native 3값 (google/apple/facebook)
// 만 실제 link, email-existing 은 reactive link arm 미적용 (sheet → /login redirect).
//
// 6 behavior:
//   T1: account-exists FirebaseAuthException(credential != null) → pendingCredential 보존
//   T2: linkPendingNativeCredential(google) → reauth + linkWithCredential 1회 → success
//   T3: pendingCredential == null → Result.failure(ServiceUnavailable) (재로그인 유도)
//   T4: reauth 단계 사용자 취소(null) → null (no-op, linkedProviders 변경 0)
//   T5: linkWithCredential 가 provider-already-linked/credential-already-in-use
//       throw → AccountAlreadyLinked 매핑 (회귀 안전)
//   T6 (race-fix sentinel): begin()/end() 1:1 (D-22 invariant)

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

class _MockSocialLinkInProgress extends Mock implements SocialLinkInProgress {}

class _MockKakaoSdkClient extends Mock implements KakaoSdkClient {}

class _MockNaverSdkClient extends Mock implements NaverSdkClient {}

class _MockLineSdkClient extends Mock implements LineSdkClient {}

class _MockYahoojpSdkClient extends Mock implements YahoojpSdkClient {}

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class _FakeAuthCredential extends Fake implements fb.AuthCredential {}

class _FakeAppleAuthProvider extends Fake implements fb.AppleAuthProvider {}

/// 테스트가 직접 인스턴스화 가능한 pendingCredential 토큰 — `Object?` 보유
/// 경계 검증용 (실제 cast 는 repository boundary 에서만).
class _FakePendingCredential extends Fake implements fb.AuthCredential {}

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

    when(() => mockLinkResult.user).thenReturn(mockCurrentUser);
  });

  /// reauth (signInWithGoogle 경로) 성공 stub — Google credential 획득 +
  /// 비익명 signInWithCredential.
  void stubGoogleReauthSuccess() {
    final mockAccount = _MockGoogleSignInAccount();
    final mockGoogleAuth = _MockGoogleSignInAuthentication();
    when(
      () => mockGoogleSignIn.authenticate(),
    ).thenAnswer((_) async => mockAccount);
    when(() => mockAccount.authentication).thenReturn(mockGoogleAuth);
    when(() => mockGoogleAuth.idToken).thenReturn('google-id-token');
    // 재인증 컨텍스트: currentUser 는 이미 존재 (비익명), signInWithCredential.
    final mockReauthCred = _MockUserCredential();
    when(() => mockReauthCred.user).thenReturn(mockCurrentUser);
    when(
      () => mockAuth.signInWithCredential(any()),
    ).thenAnswer((_) async => mockReauthCred);
    when(() => mockAuth.currentUser).thenReturn(mockCurrentUser);
  }

  group('T1 — pendingCredential 보존 (_mapAuthException arm)', () {
    test(
      'account-exists FirebaseAuthException(credential != null) → '
      'AccountExistsWithDifferentCredential.pendingCredential == 원본 e.credential',
      () async {
        final pending = _FakePendingCredential();
        when(
          () => mockAuth.signInWithEmailAndPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        ).thenThrow(
          fb.FirebaseAuthException(
            code: 'account-exists-with-different-credential',
            email: 'collide@example.com',
            credential: pending,
          ),
        );
        // lookupSignInMethods enrichment 은 본 테스트 scope 밖 — callable 미stub
        // 시 graceful null fallback 이지만, enrichment 가 pendingCredential 을
        // carry-forward 하는지 검증한다.
        when(
          () => mockFunctions.httpsCallable(
            any(),
            options: any(named: 'options'),
          ),
        ).thenThrow(Exception('callable unavailable'));

        final result = await repository.signInWithEmail(
          email: 'collide@example.com',
          password: 'pw12345678',
        );

        final failure = result as Failure<dynamic>;
        final ex = failure.exception as AccountExistsWithDifferentCredential;
        expect(ex.pendingCredential, same(pending));
      },
    );
  });

  group('T2 — linkPendingNativeCredential(google) 실제 link', () {
    test(
      'reauth 성공 → currentUser.linkWithCredential(pending) 1회 → Result.success',
      () async {
        stubGoogleReauthSuccess();
        final pending = _FakePendingCredential();
        when(
          () => mockCurrentUser.linkWithCredential(any()),
        ).thenAnswer((_) async => mockLinkResult);

        final result = await repository.linkPendingNativeCredential(
          existingProvider: AccountProvider.google,
          pendingCredential: pending,
        );

        expect(result, isNotNull);
        expect(result, isA<Success<dynamic>>());
        verify(() => mockCurrentUser.linkWithCredential(pending)).called(1);
      },
    );
  });

  group('T3 — pendingCredential == null → ServiceUnavailable', () {
    test(
      'null pendingCredential → Result.failure(ServiceUnavailable)',
      () async {
        final result = await repository.linkPendingNativeCredential(
          existingProvider: AccountProvider.google,
          pendingCredential: null,
        );

        expect(result, isA<Failure<dynamic>>());
        final failure = result! as Failure<dynamic>;
        expect(failure.exception, isA<ServiceUnavailable>());
      },
    );
  });

  group('T4 — reauth 사용자 취소 → null (no-op)', () {
    test('Google reauth canceled → null + linkWithCredential 미호출', () async {
      // GoogleSignIn.authenticate canceled.
      when(() => mockGoogleSignIn.authenticate()).thenThrow(
        const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
      );
      when(() => mockAuth.currentUser).thenReturn(mockCurrentUser);
      final pending = _FakePendingCredential();

      final result = await repository.linkPendingNativeCredential(
        existingProvider: AccountProvider.google,
        pendingCredential: pending,
      );

      expect(result, isNull);
      verifyNever(() => mockCurrentUser.linkWithCredential(any()));
    });
  });

  group('T5 — link 충돌 → AccountAlreadyLinked 매핑 (회귀 안전)', () {
    // WR-04 (2차 리뷰): `provider-already-linked` (이미 **현재 계정에**
    // 연결) 와 `credential-already-in-use` (해당 자격증명이 **다른 계정에**
    // 연결) 는 의미가 정반대라 서로 다른 타입으로 갈린다.
    test(
      'linkWithCredential throws provider-already-linked → ProviderAlreadyLinkedToThisAccount (WR-04)',
      () async {
        stubGoogleReauthSuccess();
        final pending = _FakePendingCredential();
        when(
          () => mockCurrentUser.linkWithCredential(any()),
        ).thenThrow(fb.FirebaseAuthException(code: 'provider-already-linked'));

        final result = await repository.linkPendingNativeCredential(
          existingProvider: AccountProvider.google,
          pendingCredential: pending,
        );

        expect(result, isA<Failure<dynamic>>());
        final failure = result! as Failure<dynamic>;
        expect(failure.exception, isA<ProviderAlreadyLinkedToThisAccount>());
        expect(failure.exception, isNot(isA<AccountAlreadyLinked>()));
      },
    );

    test(
      'linkWithCredential throws credential-already-in-use → AccountAlreadyLinked',
      () async {
        stubGoogleReauthSuccess();
        final pending = _FakePendingCredential();
        when(() => mockCurrentUser.linkWithCredential(any())).thenThrow(
          fb.FirebaseAuthException(code: 'credential-already-in-use'),
        );

        final result = await repository.linkPendingNativeCredential(
          existingProvider: AccountProvider.google,
          pendingCredential: pending,
        );

        expect(result, isA<Failure<dynamic>>());
        final failure = result! as Failure<dynamic>;
        expect(failure.exception, isA<AccountAlreadyLinked>());
      },
    );
  });

  group('T6 — race-fix sentinel (begin/end 1:1)', () {
    test('linkPendingNativeCredential 전 구간 begin()/end() 1:1', () async {
      stubGoogleReauthSuccess();
      final pending = _FakePendingCredential();
      when(
        () => mockCurrentUser.linkWithCredential(any()),
      ).thenAnswer((_) async => mockLinkResult);

      await repository.linkPendingNativeCredential(
        existingProvider: AccountProvider.google,
        pendingCredential: pending,
      );

      verify(() => mockSocialLinkInProgress.begin()).called(1);
      verify(() => mockSocialLinkInProgress.end()).called(1);
    });

    test(
      'email existing → reactive link arm 미적용 (ServiceUnavailable 유도)',
      () async {
        final pending = _FakePendingCredential();

        final result = await repository.linkPendingNativeCredential(
          existingProvider: AccountProvider.email,
          pendingCredential: pending,
        );

        // email-existing 은 pendingCredential link 대상이 아님 (Task 1 정책):
        // sheet 에서 /login redirect 이므로 repository 는 Result.failure 로
        // 재로그인 유도 신호.
        expect(result, isA<Failure<dynamic>>());
        verifyNever(() => mockCurrentUser.linkWithCredential(any()));
        // race-fix invariant 보존.
        verify(() => mockSocialLinkInProgress.begin()).called(1);
        verify(() => mockSocialLinkInProgress.end()).called(1);
      },
    );
  });
}
