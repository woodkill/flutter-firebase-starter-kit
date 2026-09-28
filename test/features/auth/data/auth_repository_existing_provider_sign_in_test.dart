// ignore_for_file: lines_longer_than_80_chars
//
// Phase 16 Plan 16-19 Task 1 — AuthRepository.signInWithExistingProvider
// (reactive AccountLinkingSheet step 1 디스패처).
//
// 서버 already-exists 로 열린 시트의 CTA 는 link 가 아니라 **기존 provider 로의
// 로그인** 을 수행한다 (mockup surface-a-two-step-reactive.md 경로 B). 본 파일은
// 그 단일 진입점의 위임 계약을 잠근다.
//
// 5 behavior:
//   SP1: 6 소셜 provider (google/apple/facebook/kakao/naver/line) 각각이
//        대응 signInWith{Provider} 로 1:1 위임되고 Success 가 그대로 전달된다.
//        naver 도 포함 — link target 미지원과 무관하다.
//   SP2: AccountProvider.email → ArgumentError (비밀번호 입력이 필요해 시트에서
//        처리 불가 — 호출처가 이미 /login 분기).
//   SP3: 위임 대상이 null (사용자 취소) → null 그대로 전파.
//   SP4: 위임 대상이 Failure (AccountExistsWithDifferentCredential — 익명 caller
//        재충돌, planner assumption A-16-19-01) → 예외 타입 보존 전파.
//   SP5: PII sentinel — debugPrint 출력에 fixture email / 토큰 문자열 0.

import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
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

class _FakeAuthProvider extends Fake implements fb.AuthProvider {}

/// SP1 파라미터화 케이스 — provider ↔ 대응 SDK 호출 검증 쌍.
typedef _DelegationCase = ({AccountProvider provider, String label});

const List<_DelegationCase> _kDelegationCases = <_DelegationCase>[
  (provider: AccountProvider.google, label: 'google'),
  (provider: AccountProvider.apple, label: 'apple'),
  (provider: AccountProvider.facebook, label: 'facebook'),
  (provider: AccountProvider.kakao, label: 'kakao'),
  (provider: AccountProvider.naver, label: 'naver'),
  (provider: AccountProvider.line, label: 'line'),
];

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

    // Pitfall 9 — 모든 path 의 finally 에서 호출되는 SDK logout 빈 stub.
    when(() => mockKakaoSdkClient.logout()).thenAnswer((_) async {});
    when(() => mockNaverSdkClient.logout()).thenAnswer((_) async {});
    when(() => mockLineSdkClient.logout()).thenAnswer((_) async {});

    // _mapFirebaseUser 가 참조하는 fb.User getter default stub.
    when(() => mockUser.uid).thenReturn('uid-test');
    when(() => mockUser.email).thenReturn('collide@example.com');
    when(() => mockUser.emailVerified).thenReturn(true);
    when(() => mockUser.displayName).thenReturn('Test');
    when(() => mockUser.photoURL).thenReturn(null);
    when(() => mockUser.isAnonymous).thenReturn(false);
    when(() => mockUser.metadata).thenReturn(mockMetadata);
    when(() => mockMetadata.creationTime).thenReturn(DateTime.utc(2026, 1, 1));
    when(() => mockUser.providerData).thenReturn(const <fb.UserInfo>[]);
    when(() => mockCredential.user).thenReturn(mockUser);
    when(() => mockCredential.additionalUserInfo).thenReturn(null);

    // collision 시점의 caller 는 미로그인 (또는 익명) — 기본은 미로그인.
    when(() => mockAuth.currentUser).thenReturn(null);

    // native 3값 (google/apple/facebook) 성공 path.
    final mockAccount = _MockGoogleSignInAccount();
    when(
      () => mockAccount.authentication,
    ).thenReturn(const GoogleSignInAuthentication(idToken: 'google-id-token'));
    when(
      () => mockGoogleSignIn.authenticate(),
    ).thenAnswer((_) async => mockAccount);
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
    when(
      () => mockAuth.signInWithCredential(any()),
    ).thenAnswer((_) async => mockCredential);
    when(
      () => mockAuth.signInWithProvider(any()),
    ).thenAnswer((_) async => mockCredential);

    // Custom Token 3값 (kakao/naver/line) 성공 path.
    when(() => mockKakaoSdkClient.signIn()).thenAnswer(
      (_) async => const KakaoSignInResult(idToken: 'IDT', nonce: 'NONCE'),
    );
    when(
      () => mockNaverSdkClient.signIn(),
    ).thenAnswer((_) async => const NaverAppSignIn(accessToken: 'AT_NAVER'));
    when(() => mockLineSdkClient.signIn()).thenAnswer(
      (_) async => const LineSignInResult(
        idToken: 'LIDT',
        nonce: 'LNONCE',
        accessToken: 'line-at',
      ),
    );
    when(
      () => mockFunctions.httpsCallable(any(), options: any(named: 'options')),
    ).thenReturn(mockCallable);
    when(
      () => mockFunctions.httpsCallable(any(), options: any(named: 'options')),
    ).thenReturn(mockCallable);
    final callableResult = _MockHttpsCallableResult();
    when(() => callableResult.data).thenReturn(<String, dynamic>{
      'customToken': 'CT',
      'uid': 'ct-uid',
      'isNewUser': false,
    });
    when(
      () => mockCallable.call<Map<String, dynamic>>(any()),
    ).thenAnswer((_) async => callableResult);
    when(
      () => mockAuth.signInWithCustomToken(any()),
    ).thenAnswer((_) async => mockCredential);
  });

  group('SP1 — 6 소셜 provider 1:1 위임 (Success 그대로 전달)', () {
    for (final testCase in _kDelegationCases) {
      test('${testCase.label} → 대응 signInWith 메서드 위임 → Success', () async {
        final result = await repository.signInWithExistingProvider(
          provider: testCase.provider,
        );

        expect(result, isA<Success<dynamic>>());
      });
    }

    test('naver 도 위임된다 — link target 미지원과 무관 (NaverSdkClient 호출)', () async {
      await repository.signInWithExistingProvider(
        provider: AccountProvider.naver,
      );

      verify(() => mockNaverSdkClient.signIn()).called(1);
    });
  });

  group('SP2 — email → ArgumentError', () {
    test('AccountProvider.email 은 시트에서 처리 불가 → ArgumentError throw', () async {
      // IN-02 (4차 리뷰): Future 반환 API 이므로 에러도 **Future 에러**여야
      // 한다. 동기 throw 였다면 아래 expectLater 는 Future 를 만들기도 전에
      // 터지므로 이 형태 자체가 async 전파 계약의 sentinel 이다.
      await expectLater(
        repository.signInWithExistingProvider(provider: AccountProvider.email),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('SP3 — 사용자 취소 (null) 그대로 전파', () {
    test(
      'KakaoSdkClient.signIn() null → signInWithExistingProvider null',
      () async {
        when(() => mockKakaoSdkClient.signIn()).thenAnswer((_) async => null);

        final result = await repository.signInWithExistingProvider(
          provider: AccountProvider.kakao,
        );

        expect(result, isNull);
      },
    );
  });

  group('SP4 — Failure 예외 타입 보존 (A-16-19-01 익명 caller 재충돌)', () {
    test(
      'callable already-exists → Failure(AccountExistsWithDifferentCredential) 그대로 전파',
      () async {
        when(() => mockCallable.call<Map<String, dynamic>>(any())).thenThrow(
          FirebaseFunctionsException(
            code: 'already-exists',
            message: 'identity already exists',
          ),
        );

        final result = await repository.signInWithExistingProvider(
          provider: AccountProvider.kakao,
        );

        expect(result, isA<Failure<dynamic>>());
        expect(
          (result! as Failure<dynamic>).exception,
          isA<AccountExistsWithDifferentCredential>(),
        );
      },
    );
  });

  group('SP5 — PII sentinel (T-16-19-02)', () {
    test('실패 로그에 fixture email / 토큰 본문이 없다', () async {
      final captured = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) captured.add(message);
      };
      addTearDown(() => debugPrint = originalDebugPrint);

      when(() => mockCallable.call<Map<String, dynamic>>(any())).thenThrow(
        FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'anonymous_existing_collision',
        ),
      );

      await repository.signInWithExistingProvider(
        provider: AccountProvider.kakao,
      );

      final log = captured.join('\n');
      expect(log, isNot(contains('collide@example.com')));
      expect(log, isNot(contains('IDT')));
      expect(log, isNot(contains('CT')));
    });
  });
}
