// debug apple-email-merge-profile-loss — signInWithApple 익명 승격 충돌의
// `email-already-in-use` arm 계약.
//
// **서버 계약 (단위 테스트로 재현 불가 — 근거만 기록):**
// Apple 은 Firebase trusted provider 다. 같은 email 의 기존 계정이 있을 때
// **새 로그인**(`signInWithProvider` · `signInWithCredential`)을 하면 서버가
// apple.com 을 그 계정에 자동 연결하면서 displayName · photoUrl 을 IdP
// 응답값으로 덮어쓴다 — 두 번째 Apple 인가에는 이름이 없고 Apple 은 사진을
// 주지 않으므로 기존 프로필이 사라진다.
// - firebase.google.com/docs/auth/users 「Verified email addresses」 — 자동
//   연결 규칙은 "signs in" 대상, Apple = trusted.
// - firebase-tools emulator `operations.js` handleIdpSigninEmailRequired —
//   email 일치 + IdP verified 면 displayName · photoUrl 을 IdP 값으로 대입.
// - iOS 실기기 UAT(quick 260914-wbr) 원장 diff 가 위 예측과 필드 단위로 일치.
//
// 그래서 이 arm 의 불변식은 「새 로그인 호출 0」 이다. mock 은 새 로그인에
// 성공을 돌려줄 수 있지만 production 에선 그 성공이 곧 자동 합류이므로,
// 결과값이 아니라 **호출 자체의 부재**를 단언한다.
//
// **fixture 근거 — Firebase iOS SDK 12.12.0 `AuthBackend.swift`:**
// `case "EMAIL_EXISTS": return AuthErrorUtils.emailAlreadyInUseError(email: nil)`
// → iOS 의 email-already-in-use 는 credential · email 이 모두 null 이다.
// credential 을 동봉하는 것은 `FEDERATED_USER_ID_ALREADY_LINKED`
// (credential-already-in-use) 뿐이며, 그 arm 의 계약은
// auth_repository_test.dart SLP-8a · SLP-8b 와 auth_repository_linking_test.dart
// Test A3 가 고정한다.

import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart' show DebugPrintCallback, debugPrint;
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
import 'package:flutter_starter_kit/features/auth/domain/user.dart';

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockFbUser extends Mock implements fb.User {}

class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

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

void main() {
  late _MockFirebaseAuth mockAuth;
  late _MockFbUser mockAnonymous;
  late _MockSocialLinkInProgress mockSocialLinkInProgress;
  late _MockFirebaseFunctions mockFunctions;
  late _MockHttpsCallable mockLookupCallable;
  late AuthRepository repository;
  late List<String> logs;
  late DebugPrintCallback originalDebugPrint;

  setUpAll(() {
    registerFallbackValue(_FakeAuthCredential());
    registerFallbackValue(fb.AppleAuthProvider());
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(_FakeHttpsCallableOptions());
  });

  setUp(() {
    mockAuth = _MockFirebaseAuth();
    mockAnonymous = _MockFbUser();
    mockSocialLinkInProgress = _MockSocialLinkInProgress();
    mockFunctions = _MockFirebaseFunctions();
    mockLookupCallable = _MockHttpsCallable();

    repository = AuthRepository(
      mockAuth,
      _MockGoogleSignIn(),
      _MockFacebookAuth(),
      mockSocialLinkInProgress,
      _MockKakaoSdkClient(),
      mockFunctions,
      _MockNaverSdkClient(),
      _MockLineSdkClient(),
      () async {},
    );

    when(() => mockAnonymous.isAnonymous).thenReturn(true);
    when(() => mockAuth.currentUser).thenReturn(mockAnonymous);
    // 익명 삭제는 성공 stub, 새 로그인은 StateError stub 이다. 새 로그인이
    // 불리면 흐름이 account-exists 로 끝나지 못해 결과 단언이 먼저 깨지고,
    // verifyNever 가 호출 자체를 한 번 더 잡는다(MissingStubError 로 「호출
    // 안 함」 과 뒤섞이지 않게 모든 경로를 명시 stub 한다).
    when(() => mockAnonymous.delete()).thenAnswer((_) async {});
    when(
      () => mockAuth.signInWithProvider(any()),
    ).thenThrow(StateError('새 로그인 호출 금지 — 자동 합류 경로'));
    when(
      () => mockAuth.signInWithCredential(any()),
    ).thenThrow(StateError('새 로그인 호출 금지 — 자동 합류 경로'));
    when(
      () => mockFunctions.httpsCallable(
        'lookupSignInMethods',
        options: any(named: 'options'),
      ),
    ).thenReturn(mockLookupCallable);

    logs = <String>[];
    originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
  });

  tearDown(() {
    debugPrint = originalDebugPrint;
  });

  /// 링크 실패 예외를 stub 하고 [AuthRepository.signInWithApple] 결과의
  /// [AccountExistsWithDifferentCredential] 을 돌려준다.
  Future<AccountExistsWithDifferentCredential> triggerEmailConflict({
    String? email,
    fb.AuthCredential? credential,
  }) async {
    when(() => mockAnonymous.linkWithProvider(any())).thenThrow(
      fb.FirebaseAuthException(
        code: 'email-already-in-use',
        email: email,
        credential: credential,
      ),
    );

    final result = await repository.signInWithApple();

    expect(result, isA<Failure<User>>());
    final exception = (result! as Failure<User>).exception;
    expect(exception, isA<AccountExistsWithDifferentCredential>());
    return exception as AccountExistsWithDifferentCredential;
  }

  /// 자동 합류 방아쇠(새 로그인) · 익명 손실이 모두 없었음을 단언한다.
  void verifyNoMergeTrigger() {
    verifyNever(() => mockAuth.signInWithProvider(any()));
    verifyNever(() => mockAuth.signInWithCredential(any()));
    verifyNever(() => mockAnonymous.delete());
  }

  group('signInWithApple email-already-in-use — 새 로그인 없이 계정 연결 안내', () {
    test('iOS 실측 fixture(credential · email null): account-exists 로 끝나고 '
        '새 로그인 · 익명 삭제 · lookup callable 이 모두 0회', () async {
      final exception = await triggerEmailConflict();

      expect(exception.email, isNull);
      expect(exception.existingProvider, isNull);
      expect(exception.pendingCredential, isNull);
      verifyNoMergeTrigger();
      // email 이 없으면 기존 provider 를 조회할 입력이 없다 → unknown 배너.
      verifyNever(
        () =>
            mockFunctions.httpsCallable(any(), options: any(named: 'options')),
      );
      verify(() => mockSocialLinkInProgress.begin()).called(1);
      verify(() => mockSocialLinkInProgress.end()).called(1);
    });

    test('email · credential 동봉 fixture: lookup 으로 기존 provider 를 채우고 '
        'pendingCredential 은 넘기지 않는다 (nonce 1회용)', () async {
      final mockLookupResult = _MockHttpsCallableResult();
      when(
        () => mockLookupResult.data,
      ).thenReturn(<String, dynamic>{'existingProvider': 'naver'});
      when(
        () => mockLookupCallable.call<Map<String, dynamic>>(any()),
      ).thenAnswer((_) async => mockLookupResult);

      final exception = await triggerEmailConflict(
        email: 'collision@example.com',
        credential: _FakeAuthCredential(),
      );

      expect(exception.existingProvider, AccountProvider.naver);
      expect(exception.email, 'collision@example.com');
      expect(exception.pendingCredential, isNull);
      verify(
        () => mockLookupCallable.call<Map<String, dynamic>>(<String, dynamic>{
          'email': 'collision@example.com',
        }),
      ).called(1);
      verifyNoMergeTrigger();
    });

    test('debug 로그는 code 와 bool 만 싣는다 (PII invariant)', () async {
      final mockLookupResult = _MockHttpsCallableResult();
      when(
        () => mockLookupResult.data,
      ).thenReturn(<String, dynamic>{'existingProvider': null});
      when(
        () => mockLookupCallable.call<Map<String, dynamic>>(any()),
      ).thenAnswer((_) async => mockLookupResult);

      await triggerEmailConflict(email: 'pii-apple@example.com');

      final appleLogs = logs
          .where((l) => l.startsWith('AuthRepository.signInWithApple: '))
          .toList();
      expect(appleLogs, hasLength(1));
      expect(
        appleLogs.single,
        'AuthRepository.signInWithApple: email-already-in-use — 익명 유지 + '
        '자동 합류 차단 (hasEmail: true, hasCredential: false)',
      );
      for (final log in logs) {
        expect(log, isNot(contains('pii-apple')));
      }
    });
  });
}
