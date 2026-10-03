// quick 261003-kgc — Apple 가입 때 이름을 Auth top-level `displayName` 에
// 1회 복사하는 계약 (`AuthRepository._copyAppleNameToTopLevel`).
//
// **배경 (R_08_4E · 2026-10-03 iPhone Air 실측):** Apple 은 이름을 최초
// 인가에만 준다. 같은 Apple 로 다시 로그인하면 서버가
// `providerUserInfo(apple.com).displayName` 을 빈 값으로 갱신하고, 익명 link 로
// 만든 사용자는 top-level `displayName` 도 비어 있어 재로그인 뒤 이름이 원장
// 어디에도 남지 않는다(홈 「-」).
//
// **복사 조건:** 가입(익명 link 정상 반환 또는 isNewUser=true) · top-level 이
// null · 빈 값 · 공백만 · `providerData` 의 apple.com 항목 이름이 값이 있음 →
// 그 이름 원문(가공 · trim 없음)을 `updateDisplayName` 으로 1회.
// **실패 처리:** 5초 timeout · 모든 예외 흡수 · 로그인 Success 유지 · race-fix
// 순서 begin → link → updateDisplayName → end.
// **PII:** 로그에 이름 원문 0 — sentinel `Kgcleak` 부재 + 고정 문구 대조군.
//
// K1 익명 link 성공 · top-level null → 1회 · 반환 displayName = 복사값 ·
//    currentUser 조회 1회 · reload 0
// K2 비익명 isNewUser=true · top-level '' → 1회
// K3 비익명 isNewUser=true · top-level 공백만 → 1회
// K4 가입 · top-level 값 있음 → 0회 · 반환 displayName 기존값
// K5 가입 · apple.com 이름 null → 0회 · 반환 displayName null
// K6 가입 · apple.com 이름 공백만 → 0회
// K7 가입 · apple.com 항목 없음(google.com 이름만) → 0회
// K8 비익명 isNewUser=false(재로그인) → 0회
// K9 credential-already-in-use fallback 로그인 → 0회 · 익명 delete 1회
// K10 updateDisplayName throw → Success · displayName null · end 1회 ·
//     실패 고정 문구 1줄 · sentinel 0
// K11 updateDisplayName 미완료 → 4.9초 미완료 · 5.1초 Success · end 1회
// K12 순서 begin → linkWithProvider → updateDisplayName → end
// K13 성공 → 「복사 완료」 고정 문구 1줄 · sentinel 0

import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:fake_async/fake_async.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart' show DebugPrintCallback, debugPrint;
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/features/auth/application/social_link_in_progress.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/data/kakao_sdk_client.dart';
import 'package:flutter_starter_kit/features/auth/data/line_sdk_client.dart';
import 'package:flutter_starter_kit/features/auth/data/naver_sdk_client.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockUserCredential extends Mock implements fb.UserCredential {}

class _MockAdditionalUserInfo extends Mock implements fb.AdditionalUserInfo {}

class _MockFbUser extends Mock implements fb.User {}

class _MockUserMetadata extends Mock implements fb.UserMetadata {}

class _MockUserInfo extends Mock implements fb.UserInfo {}

class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

class _MockFacebookAuth extends Mock implements FacebookAuth {}

class _MockSocialLinkInProgress extends Mock implements SocialLinkInProgress {}

class _MockKakaoSdkClient extends Mock implements KakaoSdkClient {}

class _MockNaverSdkClient extends Mock implements NaverSdkClient {}

class _MockLineSdkClient extends Mock implements LineSdkClient {}

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class _FakeAuthCredential extends Fake implements fb.AuthCredential {}

/// Apple 이 최초 인가에 준 이름 sentinel (공백 포함 원문).
const _appleName = 'Kgcleak Sentinel';

/// 로그 부재 검사 키 — 어떤 로그 줄에도 나오면 안 된다.
const _sentinelKey = 'Kgcleak';

/// 익명 사용자 uid — link 성공 뒤에도 같은 uid 로 정식 승격된다.
const _anonUid = 'ANON';

/// 비익명 신규 가입 · 재로그인 · 충돌 fallback 으로 로그인되는 계정 uid.
const _appleUid = 'APPLE';

/// 복사 성공 로그 고정 문구.
const _copiedLog = '_copyAppleNameToTopLevel: 복사 완료';

/// 복사 실패 로그 고정 문구 접두어.
const _failedLogPrefix = '_copyAppleNameToTopLevel 실패 (graceful skip): ';

void main() {
  late _MockFirebaseAuth mockAuth;
  late _MockSocialLinkInProgress mockSocialLinkInProgress;
  late _MockUserMetadata mockMetadata;
  late AuthRepository repository;
  late List<String> logs;
  late DebugPrintCallback originalDebugPrint;

  setUpAll(() {
    registerFallbackValue(_FakeAuthCredential());
    registerFallbackValue(fb.AppleAuthProvider());
  });

  setUp(() {
    mockAuth = _MockFirebaseAuth();
    mockSocialLinkInProgress = _MockSocialLinkInProgress();
    mockMetadata = _MockUserMetadata();
    when(() => mockMetadata.creationTime).thenReturn(DateTime(2026, 10, 3));
    when(() => mockAuth.currentUser).thenReturn(null);

    repository = AuthRepository(
      mockAuth,
      _MockGoogleSignIn(),
      _MockFacebookAuth(),
      mockSocialLinkInProgress,
      _MockKakaoSdkClient(),
      _MockFirebaseFunctions(),
      _MockNaverSdkClient(),
      _MockLineSdkClient(),
      () async {},
    );

    logs = <String>[];
    originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
  });

  tearDown(() {
    debugPrint = originalDebugPrint;
  });

  /// `providerId` · `displayName` 만 채운 `providerData` 항목을 만든다.
  _MockUserInfo buildUserInfo(String providerId, String? displayName) {
    final info = _MockUserInfo();
    when(() => info.providerId).thenReturn(providerId);
    when(() => info.displayName).thenReturn(displayName);
    return info;
  }

  /// `_mapFirebaseUser` · 자동 인증 메일 helper · 이름 복사 helper 가 읽는
  /// getter 를 채운 [fb.User] 를 만든다.
  ///
  /// [providers] 는 `providerData` 항목(providerId, displayName) 목록이다.
  /// `emailVerified` 는 true 라 자동 인증 메일 helper 가 즉시 no-op 이고,
  /// `updateDisplayName` 은 기본 성공 stub 이다.
  _MockFbUser buildFbUser(
    String uid, {
    String? displayName,
    List<(String, String?)> providers = const [],
    bool isAnonymous = false,
  }) {
    final user = _MockFbUser();
    when(() => user.uid).thenReturn(uid);
    when(() => user.isAnonymous).thenReturn(isAnonymous);
    when(() => user.email).thenReturn('$uid@privaterelay.appleid.com');
    when(() => user.emailVerified).thenReturn(true);
    when(() => user.displayName).thenReturn(displayName);
    when(() => user.photoURL).thenReturn(null);
    when(() => user.metadata).thenReturn(mockMetadata);
    final infos = <fb.UserInfo>[
      for (final (providerId, name) in providers)
        buildUserInfo(providerId, name),
    ];
    when(() => user.providerData).thenReturn(infos);
    when(() => user.updateDisplayName(any())).thenAnswer((_) async {});
    return user;
  }

  /// [user] 를 담고 `additionalUserInfo.isNewUser` 가 [isNewUser] 인
  /// credential 을 만든다.
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

  /// K1 경로 — 익명 link 가 정상 반환하고 결과 사용자 top-level 이 비어 있으며
  /// apple.com 이름이 sentinel 이다. (익명, 결과 사용자) 를 돌려준다.
  (_MockFbUser, _MockFbUser) stubAnonymousLinkSignUp() {
    final anonymous = stubAnonymousCurrentUser();
    final promoted = buildFbUser(
      _anonUid,
      providers: [(fb.AppleAuthProvider.PROVIDER_ID, _appleName)],
    );
    final linked = buildCredential(promoted, isNewUser: false);
    when(
      () => anonymous.linkWithProvider(any()),
    ).thenAnswer((_) async => linked);
    return (anonymous, promoted);
  }

  /// 비익명 `signInWithProvider` 결과 사용자를 stub 하고 돌려준다.
  _MockFbUser stubProviderSignIn({
    required bool isNewUser,
    String? displayName,
    List<(String, String?)> providers = const [('apple.com', _appleName)],
  }) {
    final user = buildFbUser(
      _appleUid,
      displayName: displayName,
      providers: providers,
    );
    final credential = buildCredential(user, isNewUser: isNewUser);
    when(
      () => mockAuth.signInWithProvider(any()),
    ).thenAnswer((_) async => credential);
    return user;
  }

  /// 성공 결과의 도메인 [User] 를 꺼낸다 (Success 가 아니면 테스트 실패).
  User userOf(Result<User>? result) {
    expect(result, isA<Success<User>>());
    return (result! as Success<User>).data;
  }

  /// 로그 전체에 sentinel 키가 없음을 단언한다.
  void expectNoSentinelInLogs() {
    expect(logs.where((line) => line.contains(_sentinelKey)), isEmpty);
  }

  group('quick 261003-kgc Apple 가입 이름 top-level 복사', () {
    test('K1: 익명 link 가입 · top-level null → 원문 1회 복사 · '
        '반환 displayName = 복사값 · 재조회 · reload 없음', () async {
      final (anonymous, promoted) = stubAnonymousLinkSignUp();

      final result = await repository.signInWithApple();

      expect(userOf(result).displayName, _appleName);
      verify(() => promoted.updateDisplayName(_appleName)).called(1);
      verifyNever(() => anonymous.updateDisplayName(any()));
      verifyNever(() => promoted.reload());
      // Blocker #2 — 진입 시 익명 판별 1회만 읽는다(복사 뒤 재조회 없음).
      verify(() => mockAuth.currentUser).called(1);
    });

    test('K2: 비익명 isNewUser=true · top-level 빈 문자열 → 1회 복사', () async {
      final user = stubProviderSignIn(isNewUser: true, displayName: '');

      final result = await repository.signInWithApple();

      expect(userOf(result).displayName, _appleName);
      verify(() => user.updateDisplayName(_appleName)).called(1);
    });

    test('K3: 비익명 isNewUser=true · top-level 공백만 → 1회 복사', () async {
      final user = stubProviderSignIn(isNewUser: true, displayName: '   ');

      final result = await repository.signInWithApple();

      expect(userOf(result).displayName, _appleName);
      verify(() => user.updateDisplayName(_appleName)).called(1);
    });

    test('K4: 가입 · top-level 값 있음 → 복사 0 · 반환 기존값', () async {
      final user = stubProviderSignIn(
        isNewUser: true,
        displayName: 'Existing Name',
      );

      final result = await repository.signInWithApple();

      expect(userOf(result).displayName, 'Existing Name');
      verifyNever(() => user.updateDisplayName(any()));
    });

    test('K5: 가입 · apple.com 이름 null → 복사 0 · 반환 null', () async {
      final user = stubProviderSignIn(
        isNewUser: true,
        providers: const [('apple.com', null)],
      );

      final result = await repository.signInWithApple();

      expect(userOf(result).displayName, isNull);
      verifyNever(() => user.updateDisplayName(any()));
    });

    test('K6: 가입 · apple.com 이름 공백만 → 복사 0', () async {
      final user = stubProviderSignIn(
        isNewUser: true,
        providers: const [('apple.com', '  ')],
      );

      final result = await repository.signInWithApple();

      expect(userOf(result).displayName, isNull);
      verifyNever(() => user.updateDisplayName(any()));
    });

    test('K7: 가입 · apple.com 항목 없음(google.com 이름만) → 복사 0 '
        '(Apple 만 원천)', () async {
      final user = stubProviderSignIn(
        isNewUser: true,
        providers: const [('google.com', _appleName)],
      );

      final result = await repository.signInWithApple();

      expect(userOf(result).displayName, isNull);
      verifyNever(() => user.updateDisplayName(any()));
    });

    test('K8: 비익명 isNewUser=false(재로그인) → 복사 0', () async {
      final user = stubProviderSignIn(isNewUser: false);

      final result = await repository.signInWithApple();

      expect(userOf(result).displayName, isNull);
      verifyNever(() => user.updateDisplayName(any()));
    });

    test('K9: credential-already-in-use fallback 로그인 → 복사 0 · '
        '익명 delete 1회', () async {
      final anonymous = stubAnonymousCurrentUser();
      final pending = _FakeAuthCredential();
      when(() => anonymous.linkWithProvider(any())).thenThrow(
        fb.FirebaseAuthException(
          code: 'credential-already-in-use',
          credential: pending,
        ),
      );
      final existing = buildFbUser(
        _appleUid,
        providers: [(fb.AppleAuthProvider.PROVIDER_ID, _appleName)],
      );
      final signedIn = buildCredential(existing, isNewUser: false);
      when(
        () => mockAuth.signInWithCredential(any()),
      ).thenAnswer((_) async => signedIn);

      final result = await repository.signInWithApple();

      expect(userOf(result).displayName, isNull);
      // fallback 분기를 실제로 탔다 — 익명 폐기 뒤 서버 credential 로 로그인.
      verify(() => anonymous.delete()).called(1);
      verify(() => mockAuth.signInWithCredential(pending)).called(1);
      verifyNever(() => existing.updateDisplayName(any()));
      verifyNever(() => anonymous.updateDisplayName(any()));
    });

    test('K10: updateDisplayName throw → Success 유지 · displayName null · '
        'end 1회 · 실패 고정 문구만 · 이름 0', () async {
      final (_, promoted) = stubAnonymousLinkSignUp();
      when(() => promoted.updateDisplayName(any())).thenThrow(
        fb.FirebaseAuthException(
          code: 'internal-error',
          message: 'boom $_appleName',
        ),
      );

      final result = await repository.signInWithApple();

      expect(userOf(result).displayName, isNull);
      verify(() => mockSocialLinkInProgress.end()).called(1);
      final failureLines = logs.where(
        (line) => line.startsWith('${_failedLogPrefix}FirebaseAuthException'),
      );
      expect(failureLines, hasLength(1));
      expectNoSentinelInLogs();
    });

    test('K11: updateDisplayName 미완료 → 4.9초 미완료 · 5.1초 Success · '
        'end 1회', () {
      fakeAsync((async) {
        final (_, promoted) = stubAnonymousLinkSignUp();
        final pending = Completer<void>();
        when(
          () => promoted.updateDisplayName(any()),
        ).thenAnswer((_) => pending.future);
        Result<User>? result;
        var isDone = false;
        repository.signInWithApple().then<void>((value) {
          result = value;
          isDone = true;
        });

        async.elapse(const Duration(milliseconds: 4900));
        expect(isDone, isFalse);
        verifyNever(() => mockSocialLinkInProgress.end());

        async.elapse(const Duration(milliseconds: 200));
        expect(isDone, isTrue);
        expect(userOf(result).displayName, isNull);
        verify(() => mockSocialLinkInProgress.end()).called(1);
      });
    });

    test('K12: 순서 begin → linkWithProvider → updateDisplayName → '
        'end', () async {
      final (anonymous, promoted) = stubAnonymousLinkSignUp();

      await repository.signInWithApple();

      verifyInOrder([
        () => mockSocialLinkInProgress.begin(),
        () => anonymous.linkWithProvider(any()),
        () => promoted.updateDisplayName(_appleName),
        () => mockSocialLinkInProgress.end(),
      ]);
    });

    test('K13: 복사 성공 → 「복사 완료」 고정 문구 1줄 · 이름 0', () async {
      stubAnonymousLinkSignUp();

      await repository.signInWithApple();

      expect(logs.where((line) => line == _copiedLog), hasLength(1));
      expectNoSentinelInLogs();
    });
  });
}
