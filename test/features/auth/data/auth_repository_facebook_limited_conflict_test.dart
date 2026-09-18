// debug ios-facebook-limited-login stage 2 — iOS Limited Login 익명 승격
// 충돌 fallback 의 nonce credential 재제출 회귀 가드 (D6 A+B · D7 b · D8 a ·
// D9 · D10 a).
//
// 한계: Firebase 서버의 실제 nonce 판정 · needConfirmation 응답 ·
// lookupSignInMethods 인증 판정은 단위 테스트로 검증할 수 없다. 아래 fake 는
// 관측(run-02) · SDK 소스 · 서버 소스에서 가져온 규칙만 흉내낸다 — iOS 실기기
// R_09_T4 (T1 이메일 겹침 · T2 겹침 없음) 가 계약 테스트다.

import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart' show debugPrint;
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
import 'package:flutter_starter_kit/features/auth/domain/user.dart';

import 'auth_test_fakes.dart';

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

class _MockYahoojpSdkClient extends Mock implements YahoojpSdkClient {}

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class _MockHttpsCallable extends Mock implements HttpsCallable {}

class _MockHttpsCallableResult extends Mock
    implements HttpsCallableResult<Map<String, dynamic>> {}

class _FakeAuthCredential extends Fake implements fb.AuthCredential {}

class _FakeHttpsCallableOptions extends Fake implements HttpsCallableOptions {}

/// 이메일 겹침 기존 계정의 이메일 픽스처 (PII 부재 단언 대상).
const _overlapEmail = 'overlap-fixture@example.com';

/// SHA-256 소문자 hex — 앱 헬퍼(`hashNonceSha256Hex`)와 독립된 `crypto` 직접
/// 호출. 서버의 해시 비교를 흉내낼 때 구현 코드를 재사용하지 않기 위함이다.
String _sha256Hex(String input) =>
    sha256.convert(utf8.encode(input)).toString();

/// Firebase Auth 서버의 nonce 규칙을 흉내내는 요청 원장 (state-machine fake).
///
/// 규칙의 출처는 구현이 아니라 관측과 외부 근거다:
/// 1. **요청 1회용** — iOS 실기기 run-02 로그 159-170행: 익명
///    `linkWithCredential` 에 제출한 Limited OIDC credential (idToken +
///    rawNonce) 을 같은 시도에서 `signInWithCredential` 로 다시 제출하자
///    서버가 `missing-or-invalid-nonce` 로 거부했다. firebase-ios-sdk #4434
///    renkelvin (CONTRIBUTOR): "linking then sign in are actually 2 separate
///    requests, so to be OIDC compliant, the nonce has to be different ...
///    it would be the same for other OAuth requests with nonce."
///    소비는 요청 결과와 무관하다 — run-02 첫 요청(link)은 계정 충돌로
///    실패했는데도 두 번째 요청이 거부됐다.
/// 2. **해시 짝** — Firebase iOS 문서 "Firebase validates the response by
///    hashing the original nonce and comparing it to the value passed by
///    Facebook." → 로그인 요청에 넘긴 해시 nonce 가 발급 JWT 에 묶이고,
///    `rawNonce` 의 SHA-256 hex 가 그 값과 다르면 거부한다.
///
/// rawNonce 가 없는 credential (Classic access token · 서버 updatedCredential)
/// 은 nonce 규칙 대상이 아니므로 기록만 한다.
class _NonceLedger {
  /// Facebook 로그인이 발급한 JWT → 그 로그인 요청에 넘긴 해시 nonce.
  final Map<String, String?> _issuedNonceByIdToken = {};

  /// 이미 제출된 (idToken, rawNonce) 짝.
  final Set<(String?, String)> _consumed = {};

  /// Firebase 에 제출된 모든 credential (호출 순서).
  final List<fb.AuthCredential> submissions = [];

  /// 서버가 nonce 오류로 거부한 횟수.
  int nonceRejections = 0;

  /// 로그인 1회가 발급한 [idToken] 에 그 요청의 [hashedNonce] 를 묶는다.
  void recordIssued(String idToken, String? hashedNonce) {
    _issuedNonceByIdToken[idToken] = hashedNonce;
  }

  /// Firebase 요청 1건을 제출한다. nonce 규칙 위반이면 서버처럼 throw 한다.
  void submit(fb.AuthCredential credential) {
    submissions.add(credential);
    if (credential is! fb.OAuthCredential) return;
    final rawNonce = credential.rawNonce;
    if (rawNonce == null) return;
    final isFirstUse = _consumed.add((credential.idToken, rawNonce));
    final issuedNonce = _issuedNonceByIdToken[credential.idToken];
    if (!isFirstUse || issuedNonce != _sha256Hex(rawNonce)) {
      nonceRejections++;
      throw fb.FirebaseAuthException(code: 'missing-or-invalid-nonce');
    }
  }
}

/// iOS link 가 `EMAIL_EXISTS` 로 거부될 때의 Dart 예외 모양.
///
/// firebase-ios-sdk 12.12.0 `AuthBackend.swift:341-342` —
/// `emailAlreadyInUseError(email: nil)`, `AuthErrorUtils.swift:294-300` 은
/// updatedCredential 키를 넣지 않는다 → `email` · `credential` 모두 null.
fb.FirebaseAuthException _emailAlreadyInUseFromLink() {
  return fb.FirebaseAuthException(code: 'email-already-in-use');
}

/// 서버가 충돌 오류에 실어 보내는 updatedCredential 의 Dart 모양.
///
/// firebase_auth 6.7.0 iOS `FLTFirebaseAuthPlugin.swift:90-98`
/// (`storeAuthCredentialIfPresent`) 가 native credential 을 hash 로 보관하고,
/// `PigeonParser.swift:84-103` 가 `signInMethod: authCredential.provider` ·
/// `nativeId` 로 직렬화하며, firebase_auth_platform_interface 9.1.0
/// `method_channel/utils/exception.dart:66-77` 가 `AuthCredential(providerId,
/// signInMethod, token: nativeId, accessToken)` 로 만든다 — idToken · rawNonce
/// 필드 없음. native 원본도 firebase-ios-sdk 12.19.0
/// `OAuthCredential.swift:72-84` `rawNonce: nil` + pendingToken 이다.
/// [nativeId] 는 native 보관 hash 자리. accessToken 은 native 에서
/// `accessToken ?? IDToken` 으로 채워질 수 있으나 단언 대상이 아니다.
fb.AuthCredential _updatedCredentialFromServer(int nativeId) {
  return fb.AuthCredential(
    providerId: 'facebook.com',
    signInMethod: 'facebook.com',
    token: nativeId,
  );
}

/// iOS link 가 `FEDERATED_USER_ID_ALREADY_LINKED` 로 거부될 때의 모양.
///
/// `AuthBackend.swift:447-456` → `credentialAlreadyInUseError(credential:)`
/// (`AuthErrorUtils.swift:302-316` updatedCredential 키). [updated] 가 null
/// 이면 `OAuthCredential(withVerifyAssertionResponse:)` 가 nil 인 경우다.
fb.FirebaseAuthException _credentialAlreadyInUseFromLink(
  fb.AuthCredential? updated,
) {
  return fb.FirebaseAuthException(
    code: 'credential-already-in-use',
    credential: updated,
  );
}

/// 새 credential signIn 이 `needConfirmation` 으로 거부될 때의 모양.
///
/// `Auth.swift:2121-2127` — `accountExistsWithDifferentCredentialError(email:,
/// updatedCredential:)` → email + credential 동봉. Facebook 은 untrusted
/// provider 라 같은 이메일 계정이 있으면 "throws an error requiring account
/// linking" (Firebase users 문서).
fb.FirebaseAuthException _accountExistsFromSignIn(fb.AuthCredential updated) {
  return fb.FirebaseAuthException(
    code: 'account-exists-with-different-credential',
    email: _overlapEmail,
    credential: updated,
  );
}

/// mocktail [Invocation] 의 단일 positional credential 인자를 꺼낸다.
fb.AuthCredential _credentialArgOf(Invocation invocation) {
  final Object? argument = invocation.positionalArguments.single;
  if (argument is! fb.AuthCredential) {
    fail('credential 인자가 AuthCredential 이 아님: $argument');
  }
  return argument;
}

void main() {
  late _MockFirebaseAuth mockAuth;
  late _MockFacebookAuth mockFacebookAuth;
  late _MockSocialLinkInProgress mockSocialLinkInProgress;
  late _MockFirebaseFunctions mockFunctions;
  late _MockHttpsCallable mockLookupCallable;
  late _MockHttpsCallableResult lookupResult;
  late _MockFbUser anonymousUser;
  late _MockFbUser facebookUser;
  late _MockUserCredential signInResult;
  late _NonceLedger ledger;
  late AuthRepository repository;

  // FirebaseAuth 상태 머신 — currentUser · delete 대상 · 로그인 순번.
  fb.User? signedInUser;
  late List<fb.User?> deletedUsers;
  late int loginCount;
  late List<String?> requestNonces;
  late List<String> logs;

  setUpAll(() {
    registerFallbackValue(_FakeAuthCredential());
    registerFallbackValue(fb.AppleAuthProvider());
    registerFallbackValue(LoginTracking.enabled);
    registerFallbackValue(LoginBehavior.nativeWithFallback);
    registerFallbackValue(const <String>[]);
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(_FakeHttpsCallableOptions());
  });

  setUp(() {
    mockAuth = _MockFirebaseAuth();
    mockFacebookAuth = _MockFacebookAuth();
    mockSocialLinkInProgress = _MockSocialLinkInProgress();
    mockFunctions = _MockFirebaseFunctions();
    mockLookupCallable = _MockHttpsCallable();
    lookupResult = _MockHttpsCallableResult();
    ledger = _NonceLedger();
    deletedUsers = [];
    loginCount = 0;
    requestNonces = [];
    logs = [];

    repository = AuthRepository(
      mockAuth,
      _MockGoogleSignIn(),
      mockFacebookAuth,
      mockSocialLinkInProgress,
      _MockKakaoSdkClient(),
      mockFunctions,
      _MockNaverSdkClient(),
      _MockLineSdkClient(),
      _MockYahoojpSdkClient(),
      () async {},
    );

    final originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
    addTearDown(() => debugPrint = originalDebugPrint);

    // 익명 사용자. delete 는 plugin 과 같이 "현재 로그인 사용자" 를 지운다 —
    // firebase_auth 6.3.0 iOS `[currentUser deleteWithCompletion:]`
    // (orchestrator 확인) · User.swift:953 "also signs out the user".
    anonymousUser = _MockFbUser();
    when(() => anonymousUser.uid).thenReturn('anonymous-uid');
    when(() => anonymousUser.isAnonymous).thenReturn(true);
    when(() => anonymousUser.delete()).thenAnswer((_) async {
      deletedUsers.add(signedInUser);
      signedInUser = null;
    });
    signedInUser = anonymousUser;
    when(() => mockAuth.currentUser).thenAnswer((_) => signedInUser);

    // 로그인 성공 시 결과 사용자 (facebook.com).
    final metadata = _MockUserMetadata();
    when(() => metadata.creationTime).thenReturn(DateTime.utc(2026, 9, 16));
    facebookUser = _MockFbUser();
    when(() => facebookUser.uid).thenReturn('facebook-uid');
    when(() => facebookUser.isAnonymous).thenReturn(false);
    when(() => facebookUser.email).thenReturn(null);
    when(() => facebookUser.emailVerified).thenReturn(true);
    when(() => facebookUser.displayName).thenReturn(null);
    when(() => facebookUser.photoURL).thenReturn(null);
    when(() => facebookUser.providerData).thenReturn([]);
    when(() => facebookUser.metadata).thenReturn(metadata);
    when(() => facebookUser.updatePhotoURL(any())).thenAnswer((_) async {});
    signInResult = _MockUserCredential();
    when(() => signInResult.user).thenReturn(facebookUser);
    when(() => signInResult.additionalUserInfo).thenReturn(null);
    when(
      () => mockFacebookAuth.getUserData(fields: any(named: 'fields')),
    ).thenAnswer((_) async => <String, dynamic>{});

    // lookupSignInMethods — 서버 규칙 mirror:
    // functions/src/auth/lookup_sign_in_methods.ts:158-159 는 request.auth 가
    // 없으면 unauthenticated. 익명 사용자는 인증 caller 로 통과한다 (:58-59).
    when(
      () => mockFunctions.httpsCallable(
        'lookupSignInMethods',
        options: any(named: 'options'),
      ),
    ).thenReturn(mockLookupCallable);
    when(
      () => lookupResult.data,
    ).thenReturn(<String, dynamic>{'existingProvider': 'apple'});
    when(() => mockLookupCallable.call<Map<String, dynamic>>(any())).thenAnswer(
      (_) async {
        if (signedInUser == null) {
          throw FirebaseFunctionsException(
            code: 'unauthenticated',
            message: 'errorUnauthenticated',
          );
        }
        return lookupResult;
      },
    );
  });

  /// Facebook 로그인을 stub 한다.
  ///
  /// 호출마다 새 토큰을 발급한다 (IdP 는 로그인마다 새 JWT — Facebook 문서
  /// "This is a JSON web token (JWT) containing your nonce"). Limited 이면
  /// 그 로그인 요청에 넘긴 해시 nonce 를 JWT 에 묶어 [ledger] 에 기록한다.
  /// [cancelFromCall] 이상 순번의 로그인은 사용자 취소다.
  void stubFacebookLogin({required bool limited, int? cancelFromCall}) {
    when(
      () => mockFacebookAuth.login(
        permissions: any(named: 'permissions'),
        loginTracking: any(named: 'loginTracking'),
        loginBehavior: any(named: 'loginBehavior'),
        nonce: any(named: 'nonce'),
      ),
    ).thenAnswer((invocation) async {
      loginCount++;
      final Object? nonceArgument = invocation.namedArguments[#nonce];
      final hashedNonce = nonceArgument is String ? nonceArgument : null;
      requestNonces.add(hashedNonce);
      if (cancelFromCall != null && loginCount >= cancelFromCall) {
        return LoginResult(status: LoginStatus.cancelled);
      }
      if (!limited) {
        return LoginResult(
          status: LoginStatus.success,
          accessToken: FakeClassicToken(
            tokenString: 'classic-access-token-$loginCount',
          ),
        );
      }
      final jwt = 'limited-oidc-jwt-$loginCount';
      ledger.recordIssued(jwt, hashedNonce);
      return LoginResult(
        status: LoginStatus.success,
        accessToken: buildLimitedToken(tokenString: jwt),
      );
    });
  }

  /// 익명 link 요청 — 원장에 제출(nonce 소비) 후 [conflict] 로 거부한다.
  void stubLinkConflict(fb.FirebaseAuthException conflict) {
    when(() => anonymousUser.linkWithCredential(any())).thenAnswer((
      invocation,
    ) async {
      ledger.submit(_credentialArgOf(invocation));
      throw conflict;
    });
  }

  /// signInWithCredential 요청 — 원장에 제출 후 성공 또는 [rejectWith] 거부.
  ///
  /// 거부는 `Auth.swift:2121-2127` 처럼 completeSignIn(:2132) 이전 throw 라
  /// currentUser 를 바꾸지 않는다.
  void stubSignIn({fb.FirebaseAuthException? rejectWith}) {
    when(() => mockAuth.signInWithCredential(any())).thenAnswer((
      invocation,
    ) async {
      ledger.submit(_credentialArgOf(invocation));
      if (rejectWith != null) throw rejectWith;
      signedInUser = facebookUser;
      return signInResult;
    });
  }

  /// [ledger] 제출 목록에서 index 번째 credential 을 OAuthCredential 로 꺼낸다.
  fb.OAuthCredential oauthSubmissionAt(int index) {
    final submission = ledger.submissions[index];
    if (submission is! fb.OAuthCredential) {
      fail('submissions[$index] 가 OAuthCredential 이 아님: $submission');
    }
    return submission;
  }

  group('_NonceLedger fake 자기 검증 (규칙이 실제로 거부하는지)', () {
    test('같은 (idToken, rawNonce) 재제출 · 해시 불일치 → missing-or-invalid-nonce', () {
      final probe = _NonceLedger();
      const rawNonce = 'raw-nonce-probe';
      probe.recordIssued('jwt-probe', _sha256Hex(rawNonce));
      final credential = fb.OAuthProvider(
        'facebook.com',
      ).credential(idToken: 'jwt-probe', rawNonce: rawNonce);
      final mismatched = fb.OAuthProvider(
        'facebook.com',
      ).credential(idToken: 'jwt-probe', rawNonce: 'other-raw-nonce');
      final nonceError = isA<fb.FirebaseAuthException>().having(
        (e) => e.code,
        'code',
        'missing-or-invalid-nonce',
      );

      probe.submit(credential);

      expect(() => probe.submit(credential), throwsA(nonceError));
      expect(() => probe.submit(mismatched), throwsA(nonceError));
      expect(probe.nonceRejections, 2);
    });
  });

  group('signInWithFacebook — iOS Limited 익명 승격 충돌 (stage 2)', () {
    // 전역 invariant: nonce 가 붙은 (idToken, rawNonce) 짝은 한 번만 제출된다.
    tearDown(() {
      final pairs = ledger.submissions
          .whereType<fb.OAuthCredential>()
          .where((c) => c.rawNonce != null)
          .map((c) => (c.idToken, c.rawNonce))
          .toList();
      expect(pairs.toSet(), hasLength(pairs.length));
      expect(ledger.nonceRejections, 0);
    });

    test('email-already-in-use (D6 A): 새 nonce 로 재로그인 → 두 요청 nonce 상이, '
        'signIn 성공 뒤에도 delete 0 (D7 b)', () async {
      stubFacebookLogin(limited: true);
      stubLinkConflict(_emailAlreadyInUseFromLink());
      stubSignIn();

      final result = await repository.signInWithFacebook();

      expect(result, isA<Success<User>>());
      expect(loginCount, 2);
      expect(requestNonces, hasLength(2));
      expect(requestNonces.toSet(), hasLength(2));
      expect(ledger.submissions, hasLength(2));
      final linked = oauthSubmissionAt(0);
      final signedIn = oauthSubmissionAt(1);
      expect(linked.idToken, 'limited-oidc-jwt-1');
      expect(signedIn.idToken, 'limited-oidc-jwt-2');
      expect(signedIn.rawNonce, isNot(linked.rawNonce));
      // plugin delete 는 currentUser(=새 Facebook 계정)를 지운다 — 호출 0.
      verifyNever(() => anonymousUser.delete());
      expect(deletedUsers, isEmpty);
      expect(signedInUser, same(facebookUser));
    });

    test('email-already-in-use → 새 credential signIn 이 account-exists: '
        '익명 보존 · pendingCredential 보존 · existingProvider 식별 (시트 입력)', () async {
      stubFacebookLogin(limited: true);
      stubLinkConflict(_emailAlreadyInUseFromLink());
      final updated = _updatedCredentialFromServer(101);
      stubSignIn(rejectWith: _accountExistsFromSignIn(updated));

      final result = await repository.signInWithFacebook();

      expect(
        result,
        isA<Failure<User>>().having(
          (f) => f.exception,
          'exception',
          isA<AccountExistsWithDifferentCredential>()
              .having((e) => e.email, 'email', _overlapEmail)
              .having(
                (e) => e.existingProvider,
                'existingProvider',
                AccountProvider.apple,
              )
              .having(
                (e) => e.pendingCredential,
                'pendingCredential',
                same(updated),
              ),
        ),
      );
      verifyNever(() => anonymousUser.delete());
      expect(signedInUser, same(anonymousUser));
      // mocktail 은 verify 로 매칭한 호출을 VERIFIED 처리해 후속 verifyInOrder
      // 가 찾지 못한다 (SLP-8a 선례) — verifyInOrder 뒤 verifyNever 로
      // "callable 정확히 1회" 를 보장한다.
      verifyInOrder([
        () => anonymousUser.linkWithCredential(any()),
        () => mockAuth.signInWithCredential(any()),
        () => mockLookupCallable.call<Map<String, dynamic>>(any()),
      ]);
      verifyNever(() => mockLookupCallable.call<Map<String, dynamic>>(any()));
    });

    test('email-already-in-use + 두 번째 Facebook 창 취소 → null, '
        'delete 0 · signIn 0 · 익명 유지', () async {
      stubFacebookLogin(limited: true, cancelFromCall: 2);
      stubLinkConflict(_emailAlreadyInUseFromLink());
      stubSignIn();

      final result = await repository.signInWithFacebook();

      expect(result, isNull);
      expect(loginCount, 2);
      verifyNever(() => anonymousUser.delete());
      verifyNever(() => mockAuth.signInWithCredential(any()));
      expect(signedInUser, same(anonymousUser));
      verify(() => mockSocialLinkInProgress.begin()).called(1);
      verify(() => mockSocialLinkInProgress.end()).called(1);
    });

    test('credential-already-in-use + updatedCredential (D6 B): 재로그인 0, '
        'e.credential 로 signIn — 삭제는 signIn 직전 (D-09 순서 유지)', () async {
      stubFacebookLogin(limited: true);
      final updated = _updatedCredentialFromServer(202);
      stubLinkConflict(_credentialAlreadyInUseFromLink(updated));
      stubSignIn();

      final result = await repository.signInWithFacebook();

      expect(result, isA<Success<User>>());
      expect(loginCount, 1);
      expect(ledger.submissions, hasLength(2));
      expect(ledger.submissions[1], same(updated));
      verifyInOrder([
        () => anonymousUser.linkWithCredential(any()),
        () => anonymousUser.delete(),
        () => mockAuth.signInWithCredential(any()),
      ]);
      expect(deletedUsers, [same(anonymousUser)]);
      expect(signedInUser, same(facebookUser));
    });

    test('credential-already-in-use + updatedCredential 없음 (D6 A): '
        '새 nonce 재로그인을 삭제보다 먼저 확보', () async {
      stubFacebookLogin(limited: true);
      stubLinkConflict(_credentialAlreadyInUseFromLink(null));
      stubSignIn();

      final result = await repository.signInWithFacebook();

      expect(result, isA<Success<User>>());
      expect(loginCount, 2);
      expect(oauthSubmissionAt(1).idToken, 'limited-oidc-jwt-2');
      verifyInOrder([
        () => anonymousUser.linkWithCredential(any()),
        () => mockFacebookAuth.login(
          permissions: any(named: 'permissions'),
          loginTracking: any(named: 'loginTracking'),
          loginBehavior: any(named: 'loginBehavior'),
          nonce: any(named: 'nonce'),
        ),
        () => anonymousUser.delete(),
        () => mockAuth.signInWithCredential(any()),
      ]);
    });

    test('credential-already-in-use + updatedCredential 없음 + 두 번째 창 취소 '
        '→ null, delete 0', () async {
      stubFacebookLogin(limited: true, cancelFromCall: 2);
      stubLinkConflict(_credentialAlreadyInUseFromLink(null));
      stubSignIn();

      final result = await repository.signInWithFacebook();

      expect(result, isNull);
      verifyNever(() => anonymousUser.delete());
      verifyNever(() => mockAuth.signInWithCredential(any()));
      expect(signedInUser, same(anonymousUser));
    });

    /// debug android-classic-anon-conflict — 종전 D8 a 는 Classic 의 두 link
    /// code 를 뭉쳐 항상 삭제 선행이었다. email arm 만 「익명 유지 signIn」 으로
    /// 분리한다 (Limited arm `_signInAfterLimitedLinkConflict` 와 같은 구분).
    test('Classic (Android) email-already-in-use: 익명 유지 signIn — '
        '재로그인 0 · delete 0 · 같은 credential 재제출', () async {
      stubFacebookLogin(limited: false);
      stubLinkConflict(_emailAlreadyInUseFromLink());
      stubSignIn();

      final result = await repository.signInWithFacebook();

      expect(result, isA<Success<User>>());
      expect(loginCount, 1);
      // Classic 은 nonce 가 없어 같은 credential 재제출이 허용된다 (불변).
      expect(ledger.submissions, hasLength(2));
      expect(ledger.submissions[1], same(ledger.submissions[0]));
      verifyInOrder([
        () => anonymousUser.linkWithCredential(any()),
        () => mockAuth.signInWithCredential(any()),
      ]);
      // 핵심 회귀 가드 — 삭제가 signIn 보다 먼저 일어나면 currentUser 가 null 이
      // 되어 lookupSignInMethods 가 unauthenticated 로 실패하고, 계정 연결 시트
      // 대신 unknown-provider 배너 + 익명 손실로 끝난다.
      verifyNever(() => anonymousUser.delete());
      expect(deletedUsers, isEmpty);
      // signedInUser 는 단언하지 않는다 — stubSignIn() 이 signIn 성공을 흉내내
      // facebookUser 로 전환되기 때문이다. 실제 충돌에서는 서버가 account-exists
      // 로 거부해 익명이 유지되며, 그 경로는 위 Limited D7 b 테스트가 고정한다.
    });

    test('Classic (Android) credential-already-in-use: D-09 순서 유지 — '
        'delete → 같은 credential 로 signIn', () async {
      stubFacebookLogin(limited: false);
      stubLinkConflict(_credentialAlreadyInUseFromLink(null));
      stubSignIn();

      final result = await repository.signInWithFacebook();

      expect(result, isA<Success<User>>());
      expect(loginCount, 1);
      expect(ledger.submissions, hasLength(2));
      expect(ledger.submissions[1], same(ledger.submissions[0]));
      verifyInOrder([
        () => anonymousUser.linkWithCredential(any()),
        () => anonymousUser.delete(),
        () => mockAuth.signInWithCredential(any()),
      ]);
      expect(deletedUsers, [same(anonymousUser)]);
    });

    test('D9: link 실패 로그 1줄 — code · hasCredential 만, 충돌 로그는 실제 code, '
        'PII 0', () async {
      stubFacebookLogin(limited: true);
      stubLinkConflict(_emailAlreadyInUseFromLink());
      stubSignIn(
        rejectWith: _accountExistsFromSignIn(_updatedCredentialFromServer(303)),
      );

      await repository.signInWithFacebook();

      // 매칭 ≥ 1 을 먼저 단언한다 (redaction 문자열 불일치 → 0줄 통과 함정).
      expect(
        logs,
        contains(
          'AuthRepository.signInWithFacebook: link 실패 '
          'code=email-already-in-use, hasCredential=false',
        ),
      );
      expect(logs.where((l) => l.contains('link 실패 code=')), hasLength(1));
      final log = logs.join('\n');
      // 옛 오표기 — email-already-in-use 인데 credential-already-in-use 로 출력.
      expect(
        log,
        isNot(contains('signInWithFacebook: credential-already-in-use')),
      );

      final fixture = buildLimitedToken(tokenString: 'unused');
      final sensitiveValues = <String?>[
        'limited-oidc-jwt-1',
        'limited-oidc-jwt-2',
        oauthSubmissionAt(0).rawNonce,
        oauthSubmissionAt(1).rawNonce,
        ...requestNonces,
        fixture.userEmail,
        fixture.userId,
        fixture.userName,
        fixture.nonce,
        _overlapEmail,
      ].whereType<String>().toList();
      expect(sensitiveValues, hasLength(11));
      for (final value in sensitiveValues) {
        expect(log, isNot(contains(value)));
      }
    });

    test(
      'D9: credential-already-in-use + updatedCredential → hasCredential=true',
      () async {
        stubFacebookLogin(limited: true);
        stubLinkConflict(
          _credentialAlreadyInUseFromLink(_updatedCredentialFromServer(404)),
        );
        stubSignIn();

        await repository.signInWithFacebook();

        expect(
          logs,
          contains(
            'AuthRepository.signInWithFacebook: link 실패 '
            'code=credential-already-in-use, hasCredential=true',
          ),
        );
      },
    );

    test('익명 link 성공 (T2 모양): D9 줄 없음 · signIn 0 · delete 0', () async {
      stubFacebookLogin(limited: true);
      when(() => anonymousUser.linkWithCredential(any())).thenAnswer((
        invocation,
      ) async {
        ledger.submit(_credentialArgOf(invocation));
        return signInResult;
      });

      final result = await repository.signInWithFacebook();

      expect(result, isA<Success<User>>());
      expect(logs.where((l) => l.contains('link 실패 code=')), isEmpty);
      verifyNever(() => mockAuth.signInWithCredential(any()));
      verifyNever(() => anonymousUser.delete());
    });
  });

  group('D10: missing-or-invalid-nonce → UnknownException (소셜 매핑)', () {
    setUp(() => signedInUser = null);

    test('signInWithFacebook — ServiceUnavailable 폴백이 아닌 UnknownException '
        '+ code 로그', () async {
      stubFacebookLogin(limited: true);
      when(
        () => mockAuth.signInWithCredential(any()),
      ).thenThrow(fb.FirebaseAuthException(code: 'missing-or-invalid-nonce'));

      final result = await repository.signInWithFacebook();

      expect(
        result,
        isA<Failure<User>>().having(
          (f) => f.exception,
          'exception',
          isA<UnknownException>(),
        ),
      );
      expect(
        logs,
        contains(
          'AuthRepository: 소셜 로그인 거부 → UnknownException: '
          'code=missing-or-invalid-nonce',
        ),
      );
      expect(logs.where((l) => l.contains('ServiceUnavailable 폴백')), isEmpty);
    });

    test('signInWithApple — 같은 소셜 매핑 공유', () async {
      when(
        () => mockAuth.signInWithProvider(any()),
      ).thenThrow(fb.FirebaseAuthException(code: 'missing-or-invalid-nonce'));

      final result = await repository.signInWithApple();

      expect(
        result,
        isA<Failure<User>>().having(
          (f) => f.exception,
          'exception',
          isA<UnknownException>(),
        ),
      );
    });
  });
}
