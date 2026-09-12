import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/services.dart' show PlatformException;
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
import 'package:flutter_starter_kit/features/auth/domain/user.dart';

import 'auth_test_fakes.dart';

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockUserCredential extends Mock implements fb.UserCredential {}

class _MockFbUser extends Mock implements fb.User {}

class _MockUserMetadata extends Mock implements fb.UserMetadata {}

class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

class _MockFacebookAuth extends Mock implements FacebookAuth {}

class _MockGoogleSignInAccount extends Mock implements GoogleSignInAccount {}

class _MockUserInfo extends Mock implements fb.UserInfo {}

class _MockSocialLinkInProgress extends Mock implements SocialLinkInProgress {}

class _MockFacebookLoginResult extends Mock implements LoginResult {}

class _MockFacebookAccessToken extends Mock implements AccessToken {}

class _MockKakaoSdkClient extends Mock implements KakaoSdkClient {}

class _MockNaverSdkClient extends Mock implements NaverSdkClient {}

class _MockLineSdkClient extends Mock implements LineSdkClient {}

class _MockYahoojpSdkClient extends Mock implements YahoojpSdkClient {}

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class _MockHttpsCallable extends Mock implements HttpsCallable {}

class _MockHttpsCallableResult extends Mock
    implements HttpsCallableResult<Map<String, dynamic>> {}

class _FakeAuthCredential extends Fake implements fb.AuthCredential {}

class _FakeAuthProvider extends Fake implements fb.AuthProvider {}

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
  late _MockYahoojpSdkClient mockYahoojpSdkClient;
  late _MockFirebaseFunctions mockFunctions;
  late AuthRepository repository;

  setUpAll(() {
    registerFallbackValue(_FakeAuthCredential());
    registerFallbackValue(_FakeAuthProvider());
    registerFallbackValue(fb.AppleAuthProvider());
    registerFallbackValue(LoginTracking.enabled);
    registerFallbackValue(LoginBehavior.nativeWithFallback);
    registerFallbackValue(const <String>[]);
    // Phase 12 — `_MockHttpsCallable.call(...)` 의 named 인자 fallback.
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
    mockYahoojpSdkClient = _MockYahoojpSdkClient();
    mockFunctions = _MockFirebaseFunctions();
    // Phase 9.1 D-03 / D-04 + Phase 12 D-28 + Phase 13 D-43 + Phase 14 D-LINE-17
    // + Phase 15 D-YJP-03 + Phase 10.2 D-A2: AuthRepository ctor 가 10-arg 로
    // 확장됨 (10번째 = onResetOnboarding 콜백). 본 group 의 단위 테스트는
    // logout invariant 가 아닌 다른 메서드를 검증하므로 10번째 인자는 no-op
    // closure 로 충분하다.
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

    // Pitfall 9 회귀 가드 — 모든 path 의 finally 블록에서 호출되는
    // SDK logout 을 빈 stub 으로 등록 (D-57 + D-57 retroactive + D-LINE-57 +
    // D-YJP-08).
    // 누락 시 MissingStubError 발생.
    when(() => mockKakaoSdkClient.logout()).thenAnswer((_) async {});
    when(() => mockNaverSdkClient.logout()).thenAnswer((_) async {});
    when(() => mockLineSdkClient.logout()).thenAnswer((_) async {});
    when(() => mockYahoojpSdkClient.logout()).thenAnswer((_) async {});

    // 기본 User 필드 stub
    when(() => mockUser.uid).thenReturn('uid-test');
    when(() => mockUser.email).thenReturn('test@example.com');
    when(() => mockUser.emailVerified).thenReturn(true);
    when(() => mockUser.displayName).thenReturn('Test');
    when(() => mockUser.photoURL).thenReturn(null);
    when(() => mockUser.metadata).thenReturn(mockMetadata);
    when(() => mockMetadata.creationTime).thenReturn(DateTime.utc(2026, 1, 1));
    when(() => mockCredential.user).thenReturn(mockUser);
    // (Phase 9.2 R4 — IN-03 회귀 가드 sparsity 보강) grand suite 의
    // `_autoSendEmailVerification` 진입 시 항상 `isNewUser=false` 가드로
    // 흡수 (helper 본체 진입 0 — sendEmailVerification side-effect 격리).
    // 본 helper 의 실효 검증은 `auth_repository_auto_verify_test.dart`
    // V1~V9 에 위임. 누군가 helper 의 default 동작을 (`?? true` 등으로)
    // 뒤집을 경우 본 stub 이 명시적 contract 로 회귀 surface.
    when(() => mockCredential.additionalUserInfo).thenReturn(null);
    when(() => mockUser.providerData).thenReturn([]);

    // Plan 10-06 Task 3 Step 4: `AuthRepository` 의 4개 로그인/가입 메서드가
    // Plan 10-06 에서 익명 분기 진입 체크를 위해 `_auth.currentUser` 를 직접
    // 조회한다. 기존 테스트는 "비익명 경로" (시나리오 B) 를 검증하므로 기본값을
    // null 로 stub 하여 signInWithCredential / createUserWithEmailAndPassword
    // 경로로 유도한다. 개별 테스트가 필요 시 override 한다 (e.g., signUpWithEmail
    // 성공 테스트는 후속 refresh 를 위해 mockUser 로 override).
    when(() => mockAuth.currentUser).thenReturn(null);

    // `mockUser.isAnonymous` 기본값 — 개별 그룹의 setUp 이
    // `mockAuth.currentUser` 를 `mockUser` 로 override 할 때, Plan 10-06 의
    // 익명 분기 `isAnonymous == true` 체크에서 `MissingStubError` 가 발생하지
    // 않도록 false 로 stub. 기존 테스트는 "비익명 경로" 를 검증하므로 false 가
    // 올바른 기본값.
    when(() => mockUser.isAnonymous).thenReturn(false);

    // WR-02 (Phase 9.2 review fix) — Phase 9.2 R5 가 signInWithFacebook
    // success path 에 `_setFacebookPhotoUrl(fbUser)` 를 추가했다. 본 grand
    // suite 의 기존 Facebook 테스트들은 `getUserData` / `updatePhotoURL`
    // stub 을 등록하지 않아 mocktail 이 `MissingStubError` (extends Error
    // extends Object) 를 throw 했고, helper 의 광역 `on Object catch` 가
    // 이를 silent 흡수 → 테스트가 통과하나 실 production 의 R5 wiring 회귀
    // 가드로 작동하지 않는다 (잘못된 green). 본 default stub 이 happy path
    // 응답을 모사하여 (1) MissingStubError surface 차단 + (2) 기존
    // verifyInOrder/Result.success 검증의 의도된 의미 회복.
    // (BL-01 fix 와 정합 — `is Map` guard 가 typed Map 응답도 흡수.)
    when(
      () => mockFacebookAuth.getUserData(fields: any(named: 'fields')),
    ).thenAnswer((_) async => <String, dynamic>{});
    when(() => mockUser.updatePhotoURL(any())).thenAnswer((_) async {});
  });

  group('_mapFirebaseUser via signInWithEmail (BLOCKER #1 통합 검증)', () {
    test('모든 필드가 채워진 fb.User 가 도메인 User 로 매핑된다', () async {
      when(() => mockUser.uid).thenReturn('uid-full');
      when(() => mockUser.email).thenReturn('full@example.com');
      when(() => mockUser.emailVerified).thenReturn(true);
      when(() => mockUser.displayName).thenReturn('Full User');
      when(() => mockUser.photoURL).thenReturn('https://example.com/photo.png');
      when(
        () => mockMetadata.creationTime,
      ).thenReturn(DateTime.utc(2026, 1, 15, 10, 30));
      when(
        () => mockAuth.signInWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => mockCredential);

      final result = await repository.signInWithEmail(
        email: 'full@example.com',
        password: 'pw12345678',
      );

      expect(result, isA<Success<dynamic>>());
      final user = (result as Success).data;
      expect(user.uid, 'uid-full');
      expect(user.email, 'full@example.com');
      expect(user.emailVerified, isTrue);
      expect(user.displayName, 'Full User');
      expect(user.photoUrl, 'https://example.com/photo.png');
      expect(user.createdAt, DateTime.utc(2026, 1, 15, 10, 30));
    });

    test('email 이 null 인 경우 빈 문자열로 fallback', () async {
      when(() => mockUser.uid).thenReturn('uid-no-email');
      when(() => mockUser.email).thenReturn(null);
      when(() => mockUser.emailVerified).thenReturn(false);
      when(() => mockUser.displayName).thenReturn(null);
      when(() => mockUser.photoURL).thenReturn(null);
      when(
        () => mockMetadata.creationTime,
      ).thenReturn(DateTime.utc(2026, 1, 1));
      when(
        () => mockAuth.signInWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => mockCredential);

      final result = await repository.signInWithEmail(
        email: 'a@b.com',
        password: 'pw12345678',
      );

      final user = (result as Success).data;
      expect(user.email, '');
      expect(user.displayName, isNull);
      expect(user.photoUrl, isNull);
    });

    test('creationTime 이 null 이면 현재 시각으로 fallback', () async {
      when(() => mockUser.uid).thenReturn('uid-no-time');
      when(() => mockUser.email).thenReturn('a@b.com');
      when(() => mockUser.emailVerified).thenReturn(true);
      when(() => mockUser.displayName).thenReturn(null);
      when(() => mockUser.photoURL).thenReturn(null);
      when(() => mockMetadata.creationTime).thenReturn(null);
      when(
        () => mockAuth.signInWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => mockCredential);

      final before = DateTime.now();
      final result = await repository.signInWithEmail(
        email: 'a@b.com',
        password: 'pw12345678',
      );
      final after = DateTime.now();

      final user = (result as Success).data;
      expect(
        user.createdAt.isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(
        user.createdAt.isBefore(after.add(const Duration(seconds: 1))),
        isTrue,
      );
    });
  });

  group('signInWithEmail', () {
    test('성공 시 Result.success(User)를 반환한다', () async {
      when(
        () => mockAuth.signInWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => mockCredential);

      final result = await repository.signInWithEmail(
        email: 'test@example.com',
        password: 'password123',
      );

      expect(result, isA<Success<dynamic>>());
      final user = (result as Success).data;
      expect(user.uid, 'uid-test');
      expect(user.email, 'test@example.com');
    });

    test('credential.user가 null이면 InvalidCredentials Failure 반환', () async {
      when(() => mockCredential.user).thenReturn(null);
      when(
        () => mockAuth.signInWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => mockCredential);

      final result = await repository.signInWithEmail(
        email: 'a@b.com',
        password: 'pw',
      );

      expect(result, isA<Failure<dynamic>>());
      expect((result as Failure).exception, isA<InvalidCredentials>());
    });

    // WR-06 (Phase 7 review): 비-Auth 예외가 그대로 전파되면
    // LoginNotifier.submit 이 `state = switch (result)` 에 도달하지 못해
    // CTA 가 영구 스피너로 고정된다 (소셜 경로가 이미 막고 있던 증상).
    test('WR-06: 비-Auth 예외 (PlatformException) → ServiceUnavailable Failure '
        '(throw 전파 안 함)', () async {
      when(
        () => mockAuth.signInWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(PlatformException(code: 'channel-error'));

      final result = await repository.signInWithEmail(
        email: 'a@b.com',
        password: 'pw',
      );

      expect(result, isA<Failure<dynamic>>());
      expect((result as Failure).exception, isA<ServiceUnavailable>());
    });
  });

  group('signUpWithEmail', () {
    test('성공 시 updateDisplayName/reload 호출 후 User 반환', () async {
      when(
        () => mockAuth.createUserWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => mockCredential);
      when(() => mockUser.updateDisplayName(any())).thenAnswer((_) async {});
      when(() => mockUser.reload()).thenAnswer((_) async {});
      when(() => mockAuth.currentUser).thenReturn(mockUser);
      when(() => mockUser.sendEmailVerification()).thenAnswer((_) async {});

      final result = await repository.signUpWithEmail(
        email: 'new@example.com',
        password: 'password123',
        displayName: 'Newbie',
      );

      expect(result, isA<Success<dynamic>>());
      verify(() => mockUser.updateDisplayName('Newbie')).called(1);
      verify(() => mockUser.reload()).called(1);
    });

    test(
      'updateDisplayName 실패해도 가입은 성공 처리된다 + currentUser fallback (D-10)',
      () async {
        when(
          () => mockAuth.createUserWithEmailAndPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        ).thenAnswer((_) async => mockCredential);
        when(
          () => mockUser.updateDisplayName(any()),
        ).thenThrow(fb.FirebaseAuthException(code: 'unknown'));
        when(() => mockAuth.currentUser).thenReturn(mockUser);
        when(() => mockUser.sendEmailVerification()).thenAnswer((_) async {});

        final result = await repository.signUpWithEmail(
          email: 'a@b.com',
          password: 'password123',
          displayName: 'Name',
        );

        expect(result, isA<Success<dynamic>>());
        // WARNING #3: updateDisplayName 실패 경로에서도 _auth.currentUser
        // 재획득이 호출되어 graceful fallback 동작이 보장됨을 검증.
        verify(() => mockAuth.currentUser).called(greaterThan(0));
      },
    );
  });

  group('signOut', () {
    test('firebaseAuth.signOut()을 호출한다', () async {
      when(() => mockGoogleSignIn.signOut()).thenAnswer((_) async {});
      when(() => mockFacebookAuth.logOut()).thenAnswer((_) async {});
      when(() => mockAuth.signOut()).thenAnswer((_) async {});

      await repository.signOut();

      verify(() => mockAuth.signOut()).called(1);
    });
  });

  group('sendPasswordReset', () {
    test('성공 시 Result.success(null) 반환', () async {
      when(
        () => mockAuth.sendPasswordResetEmail(email: any(named: 'email')),
      ).thenAnswer((_) async {});

      final result = await repository.sendPasswordReset(email: 'a@b.com');

      expect(result, isA<Success<dynamic>>());
    });

    test(
      'FirebaseAuthException invalid-email 시 InvalidEmail Failure',
      () async {
        when(
          () => mockAuth.sendPasswordResetEmail(email: any(named: 'email')),
        ).thenThrow(fb.FirebaseAuthException(code: 'invalid-email'));

        final result = await repository.sendPasswordReset(email: 'bad');

        expect(result, isA<Failure<dynamic>>());
        expect((result as Failure).exception, isA<InvalidEmail>());
      },
    );

    // WR-06: 비-Auth 예외 방어 (소셜 경로 / reloadUser mirror).
    test('WR-06: 비-Auth 예외 → ServiceUnavailable Failure', () async {
      when(
        () => mockAuth.sendPasswordResetEmail(email: any(named: 'email')),
      ).thenThrow(PlatformException(code: 'channel-error'));

      final result = await repository.sendPasswordReset(email: 'a@b.com');

      expect(result, isA<Failure<dynamic>>());
      expect((result as Failure).exception, isA<ServiceUnavailable>());
    });
  });

  group('sendEmailVerification', () {
    test('성공 시 Result.success(null)을 반환한다', () async {
      when(() => mockAuth.currentUser).thenReturn(mockUser);
      when(() => mockUser.sendEmailVerification()).thenAnswer((_) async {});

      final result = await repository.sendEmailVerification();

      expect(result, isA<Success<dynamic>>());
    });

    test('실패 시 _mapAuthException으로 변환된 Result.failure를 반환한다', () async {
      when(() => mockAuth.currentUser).thenReturn(mockUser);
      when(
        () => mockUser.sendEmailVerification(),
      ).thenThrow(fb.FirebaseAuthException(code: 'too-many-requests'));

      final result = await repository.sendEmailVerification();

      expect(result, isA<Failure<dynamic>>());
      expect((result as Failure).exception, isA<TooManyRequests>());
    });

    // WR-06: 비-Auth 예외 방어 (소셜 경로 / reloadUser mirror).
    test('WR-06: 비-Auth 예외 → ServiceUnavailable Failure', () async {
      when(() => mockAuth.currentUser).thenReturn(mockUser);
      when(
        () => mockUser.sendEmailVerification(),
      ).thenThrow(PlatformException(code: 'channel-error'));

      final result = await repository.sendEmailVerification();

      expect(result, isA<Failure<dynamic>>());
      expect((result as Failure).exception, isA<ServiceUnavailable>());
    });
  });

  group('reloadUser', () {
    test('성공 시 Result.success(null)을 반환한다', () async {
      when(() => mockAuth.currentUser).thenReturn(mockUser);
      when(() => mockUser.reload()).thenAnswer((_) async {});

      final result = await repository.reloadUser();

      expect(result, isA<Success<dynamic>>());
    });

    test('실패 시 _mapAuthException으로 변환된 Result.failure를 반환한다', () async {
      when(() => mockAuth.currentUser).thenReturn(mockUser);
      when(
        () => mockUser.reload(),
      ).thenThrow(fb.FirebaseAuthException(code: 'network-request-failed'));

      final result = await repository.reloadUser();

      expect(result, isA<Failure<dynamic>>());
      expect((result as Failure).exception, isA<NoInternetConnection>());
    });
  });

  group('signUpWithEmail sendEmailVerification 체이닝', () {
    test('가입 성공 후 sendEmailVerification이 호출된다', () async {
      when(
        () => mockAuth.createUserWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => mockCredential);
      when(() => mockUser.updateDisplayName(any())).thenAnswer((_) async {});
      when(() => mockUser.reload()).thenAnswer((_) async {});
      when(() => mockAuth.currentUser).thenReturn(mockUser);
      when(() => mockUser.sendEmailVerification()).thenAnswer((_) async {});

      await repository.signUpWithEmail(
        email: 'new@example.com',
        password: 'password123',
        displayName: 'Newbie',
      );

      verify(() => mockUser.sendEmailVerification()).called(1);
    });

    test('sendEmailVerification 실패해도 가입은 성공 유지된다 (D-01, D-11)', () async {
      when(
        () => mockAuth.createUserWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => mockCredential);
      when(() => mockUser.updateDisplayName(any())).thenAnswer((_) async {});
      when(() => mockUser.reload()).thenAnswer((_) async {});
      when(() => mockAuth.currentUser).thenReturn(mockUser);
      when(
        () => mockUser.sendEmailVerification(),
      ).thenThrow(fb.FirebaseAuthException(code: 'too-many-requests'));

      final result = await repository.signUpWithEmail(
        email: 'new@example.com',
        password: 'password123',
        displayName: 'Newbie',
      );

      expect(result, isA<Success<dynamic>>());
    });
  });

  group('signInWithGoogle', () {
    late _MockGoogleSignInAccount mockAccount;

    setUp(() {
      mockAccount = _MockGoogleSignInAccount();
      when(
        () => mockAccount.authentication,
      ).thenReturn(const GoogleSignInAuthentication(idToken: 'mock-id-token'));
    });

    test(
      '성공 시 Result.success(User)를 반환하고 providerIds에 google.com 포함',
      () async {
        when(
          () =>
              mockGoogleSignIn.authenticate(scopeHint: any(named: 'scopeHint')),
        ).thenAnswer((_) async => mockAccount);

        final mockProviderInfo = _MockUserInfo();
        when(() => mockProviderInfo.providerId).thenReturn('google.com');
        when(() => mockUser.providerData).thenReturn([mockProviderInfo]);

        when(
          () => mockAuth.signInWithCredential(any()),
        ).thenAnswer((_) async => mockCredential);

        final result = await repository.signInWithGoogle();

        expect(result, isA<Success<dynamic>>());
        final user = (result! as Success).data;
        expect(user.uid, 'uid-test');
        expect(user.providerIds, ['google.com']);
      },
    );

    test('사용자 취소(canceled) 시 null을 반환한다', () async {
      when(
        () => mockGoogleSignIn.authenticate(scopeHint: any(named: 'scopeHint')),
      ).thenThrow(
        const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
      );

      final result = await repository.signInWithGoogle();

      expect(result, isNull);
    });

    // WR-01 (Phase 7 review): idToken 은 nullable 이며 Android serverClientId
    // 미설정 등 설정 오류 시 null 로 도착한다. 가드 없이 넘기면 release 에서
    // assert 가 제거되어 빈 credential 로 Firebase 를 호출한다.
    test('WR-01: idToken null → ServiceUnavailable + Firebase 호출 0건', () async {
      when(
        () => mockAccount.authentication,
      ).thenReturn(const GoogleSignInAuthentication(idToken: null));
      when(
        () => mockGoogleSignIn.authenticate(scopeHint: any(named: 'scopeHint')),
      ).thenAnswer((_) async => mockAccount);

      final result = await repository.signInWithGoogle();

      expect(result, isA<Failure<dynamic>>());
      expect((result! as Failure).exception, isA<ServiceUnavailable>());
      verifyNever(() => mockAuth.signInWithCredential(any()));
    });

    test(
      'WR-01: idToken 빈 문자열 → ServiceUnavailable + Firebase 호출 0건',
      () async {
        when(
          () => mockAccount.authentication,
        ).thenReturn(const GoogleSignInAuthentication(idToken: ''));
        when(
          () =>
              mockGoogleSignIn.authenticate(scopeHint: any(named: 'scopeHint')),
        ).thenAnswer((_) async => mockAccount);

        final result = await repository.signInWithGoogle();

        expect(result, isA<Failure<dynamic>>());
        expect((result! as Failure).exception, isA<ServiceUnavailable>());
        verifyNever(() => mockAuth.signInWithCredential(any()));
      },
    );

    test('account-exists-with-different-credential 시 '
        'AccountExistsWithDifferentCredential 반환', () async {
      when(
        () => mockGoogleSignIn.authenticate(scopeHint: any(named: 'scopeHint')),
      ).thenAnswer((_) async => mockAccount);

      when(() => mockAuth.signInWithCredential(any())).thenThrow(
        fb.FirebaseAuthException(
          code: 'account-exists-with-different-credential',
          email: 'existing@example.com',
        ),
      );

      final result = await repository.signInWithGoogle();

      expect(result, isA<Failure<dynamic>>());
      final exception = (result! as Failure).exception;
      expect(exception, isA<AccountExistsWithDifferentCredential>());
      expect(
        (exception as AccountExistsWithDifferentCredential).email,
        'existing@example.com',
      );
    });

    test(
      '기타 GoogleSignInException 시 Result.failure(ServiceUnavailable) 반환',
      () async {
        when(
          () =>
              mockGoogleSignIn.authenticate(scopeHint: any(named: 'scopeHint')),
        ).thenThrow(
          const GoogleSignInException(
            code: GoogleSignInExceptionCode.unknownError,
            description: 'Something went wrong',
          ),
        );

        final result = await repository.signInWithGoogle();

        expect(result, isA<Failure<dynamic>>());
        expect((result! as Failure).exception, isA<ServiceUnavailable>());
      },
    );

    test('signInWithCredential에서 user가 null이면 ServiceUnavailable 반환', () async {
      when(
        () => mockGoogleSignIn.authenticate(scopeHint: any(named: 'scopeHint')),
      ).thenAnswer((_) async => mockAccount);

      when(() => mockCredential.user).thenReturn(null);
      when(
        () => mockAuth.signInWithCredential(any()),
      ).thenAnswer((_) async => mockCredential);

      final result = await repository.signInWithGoogle();

      expect(result, isA<Failure<dynamic>>());
      expect((result! as Failure).exception, isA<ServiceUnavailable>());
    });
  });

  group('signOut (GoogleSignIn + FacebookAuth 병행 호출)', () {
    test('GoogleSignIn.signOut()과 FacebookAuth.logOut()과 '
        'FirebaseAuth.signOut() 모두 호출된다', () async {
      when(() => mockGoogleSignIn.signOut()).thenAnswer((_) async {});
      when(() => mockFacebookAuth.logOut()).thenAnswer((_) async {});
      when(() => mockAuth.signOut()).thenAnswer((_) async {});

      await repository.signOut();

      verify(() => mockGoogleSignIn.signOut()).called(1);
      verify(() => mockFacebookAuth.logOut()).called(1);
      verify(() => mockAuth.signOut()).called(1);
    });

    test('GoogleSignIn.signOut() 실패 시에도 FirebaseAuth.signOut() 호출된다', () async {
      when(
        () => mockGoogleSignIn.signOut(),
      ).thenThrow(Exception('Google signOut failed'));
      when(() => mockFacebookAuth.logOut()).thenAnswer((_) async {});
      when(() => mockAuth.signOut()).thenAnswer((_) async {});

      await repository.signOut();

      verify(() => mockGoogleSignIn.signOut()).called(1);
      verify(() => mockAuth.signOut()).called(1);
    });

    // (Phase 9.2 R6 — D-26) Phase 9.2 add-only — 5 SDK 순차 logout invariant
    // 검증. signOut() 본체 가 Google → Facebook → Kakao → Naver →
    // FirebaseAuth 순차 호출 + 각 SDK logout 실패 시에도 후속 SDK + Auth
    // 호출 보장 (try/catch 무시 패턴).
    test('Phase 9.2 R6 — signOut: 5 SDK logout 순차 호출 (Google → Facebook → '
        'Kakao → Naver → FirebaseAuth)', () async {
      when(() => mockGoogleSignIn.signOut()).thenAnswer((_) async {});
      when(() => mockFacebookAuth.logOut()).thenAnswer((_) async {});
      when(() => mockKakaoSdkClient.logout()).thenAnswer((_) async {});
      when(() => mockNaverSdkClient.logout()).thenAnswer((_) async {});
      when(() => mockAuth.signOut()).thenAnswer((_) async {});

      await repository.signOut();

      // VALIDATION Mock 함정 6 — 명시 verifyInOrder 5 SDK 순차 invariant.
      verifyInOrder([
        () => mockGoogleSignIn.signOut(),
        () => mockFacebookAuth.logOut(),
        () => mockKakaoSdkClient.logout(),
        () => mockNaverSdkClient.logout(),
        () => mockAuth.signOut(),
      ]);
    });

    test('Phase 9.2 R6 — signOut: Kakao SDK logout 실패 시에도 Naver + '
        'FirebaseAuth 호출 보장', () async {
      when(() => mockGoogleSignIn.signOut()).thenAnswer((_) async {});
      when(() => mockFacebookAuth.logOut()).thenAnswer((_) async {});
      when(
        () => mockKakaoSdkClient.logout(),
      ).thenThrow(Exception('Kakao logout failed'));
      when(() => mockNaverSdkClient.logout()).thenAnswer((_) async {});
      when(() => mockAuth.signOut()).thenAnswer((_) async {});

      await repository.signOut();

      verify(() => mockNaverSdkClient.logout()).called(1);
      verify(() => mockAuth.signOut()).called(1);
    });

    test('Phase 9.2 R6 — signOut: Naver SDK logout 실패 시에도 FirebaseAuth '
        '호출 보장', () async {
      when(() => mockGoogleSignIn.signOut()).thenAnswer((_) async {});
      when(() => mockFacebookAuth.logOut()).thenAnswer((_) async {});
      when(() => mockKakaoSdkClient.logout()).thenAnswer((_) async {});
      when(
        () => mockNaverSdkClient.logout(),
      ).thenThrow(Exception('Naver logout failed'));
      when(() => mockAuth.signOut()).thenAnswer((_) async {});

      await repository.signOut();

      verify(() => mockAuth.signOut()).called(1);
    });
  });

  group('_mapFirebaseUser providerIds 매핑', () {
    test('providerData가 providerIds로 매핑된다', () async {
      final mockProvider1 = _MockUserInfo();
      when(() => mockProvider1.providerId).thenReturn('google.com');
      final mockProvider2 = _MockUserInfo();
      when(() => mockProvider2.providerId).thenReturn('password');
      when(
        () => mockUser.providerData,
      ).thenReturn([mockProvider1, mockProvider2]);

      when(
        () => mockAuth.signInWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => mockCredential);

      final result = await repository.signInWithEmail(
        email: 'test@example.com',
        password: 'password123',
      );

      final user = (result as Success).data;
      expect(user.providerIds, ['google.com', 'password']);
    });

    test('providerData가 비어 있으면 providerIds도 빈 리스트', () async {
      when(() => mockUser.providerData).thenReturn([]);

      when(
        () => mockAuth.signInWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => mockCredential);

      final result = await repository.signInWithEmail(
        email: 'test@example.com',
        password: 'password123',
      );

      final user = (result as Success).data;
      expect(user.providerIds, isEmpty);
    });
  });

  group('FirebaseAuthException 매핑 (10종 코드 → AppException)', () {
    Future<AppException> mapViaSignIn(String code) async {
      when(
        () => mockAuth.signInWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(fb.FirebaseAuthException(code: code));

      final result = await repository.signInWithEmail(
        email: 'a@b.com',
        password: 'pw',
      );
      return (result as Failure).exception;
    }

    test('invalid-credential → InvalidCredentials', () async {
      expect(
        await mapViaSignIn('invalid-credential'),
        isA<InvalidCredentials>(),
      );
    });
    test('wrong-password → InvalidCredentials', () async {
      expect(await mapViaSignIn('wrong-password'), isA<InvalidCredentials>());
    });
    test('user-not-found → InvalidCredentials', () async {
      expect(await mapViaSignIn('user-not-found'), isA<InvalidCredentials>());
    });
    test('email-already-in-use → EmailAlreadyInUse', () async {
      expect(
        await mapViaSignIn('email-already-in-use'),
        isA<EmailAlreadyInUse>(),
      );
    });
    test('weak-password → WeakPassword', () async {
      expect(await mapViaSignIn('weak-password'), isA<WeakPassword>());
    });
    test('invalid-email → InvalidEmail', () async {
      expect(await mapViaSignIn('invalid-email'), isA<InvalidEmail>());
    });
    test('user-disabled → UserDisabled', () async {
      expect(await mapViaSignIn('user-disabled'), isA<UserDisabled>());
    });
    test('network-request-failed → NoInternetConnection', () async {
      expect(
        await mapViaSignIn('network-request-failed'),
        isA<NoInternetConnection>(),
      );
    });
    test('too-many-requests → TooManyRequests', () async {
      expect(await mapViaSignIn('too-many-requests'), isA<TooManyRequests>());
    });
    test('operation-not-allowed → ServiceUnavailable '
        '(Firebase Console 인증 방식 비활성 설정 오류)', () async {
      // 회귀 방지: dev Firebase Console에서 Email/Password 가입이 꺼져 있을 때
      // 던져지는 코드를 명시적으로 매핑한다. fallback과 동일한 결과지만,
      // 의도가 코드에 드러나며 향후 다른 매핑으로 분리할 여지를 남긴다.
      expect(
        await mapViaSignIn('operation-not-allowed'),
        isA<ServiceUnavailable>(),
      );
    });
    test('알 수 없는 코드 → ServiceUnavailable (fallback)', () async {
      expect(
        await mapViaSignIn('some-unknown-code'),
        isA<ServiceUnavailable>(),
      );
    });
  });

  group('signInWithApple (signInWithProvider 기반)', () {
    setUp(() {
      // signInWithProvider 기본 stub.
      when(
        () => mockAuth.signInWithProvider(any()),
      ).thenAnswer((_) async => mockCredential);

      // Firebase User 기본 필드 — Apple 로그인 성공 시나리오.
      when(() => mockUser.uid).thenReturn('apple-uid-123');
      when(() => mockUser.email).thenReturn('test@privaterelay.appleid.com');
      when(() => mockUser.emailVerified).thenReturn(true);
      when(() => mockUser.displayName).thenReturn(null);
      when(() => mockUser.photoURL).thenReturn(null);
      when(
        () => mockMetadata.creationTime,
      ).thenReturn(DateTime.utc(2026, 4, 11));

      final appleProvider = _MockUserInfo();
      when(() => appleProvider.providerId).thenReturn('apple.com');
      when(() => mockUser.providerData).thenReturn([appleProvider]);

      when(() => mockCredential.user).thenReturn(mockUser);
      when(() => mockAuth.currentUser).thenReturn(mockUser);
    });

    test('AUTH-03-01: 성공 시 Result.success(User)를 반환하고 '
        'providerIds에 apple.com 포함', () async {
      final result = await repository.signInWithApple();

      expect(result, isA<Success<User>>());
      final user = (result! as Success<User>).data;
      expect(user.providerIds, contains('apple.com'));
      expect(user.emailVerified, isTrue);
      verify(() => mockAuth.signInWithProvider(any())).called(1);
    });

    test('AUTH-03-02: 사용자 취소 시 null을 반환한다 (D-09)', () async {
      when(() => mockAuth.signInWithProvider(any())).thenThrow(
        fb.FirebaseAuthException(
          code: 'web-context-canceled',
          message: 'The web operation was canceled by the user.',
        ),
      );

      final result = await repository.signInWithApple();

      expect(result, isNull);
    });

    test('AUTH-03-03: account-exists-with-different-credential 시 '
        'AccountExistsWithDifferentCredential 반환', () async {
      when(() => mockAuth.signInWithProvider(any())).thenThrow(
        fb.FirebaseAuthException(
          code: 'account-exists-with-different-credential',
          email: 'user@example.com',
          message: 'account exists',
        ),
      );

      final result = await repository.signInWithApple();

      expect(result, isA<Failure<User>>());
      final err = (result! as Failure<User>).exception;
      expect(err, isA<AccountExistsWithDifferentCredential>());
      expect(
        (err as AccountExistsWithDifferentCredential).email,
        'user@example.com',
      );
    });

    test('AUTH-03-04: 기타 FirebaseAuthException은 '
        'ServiceUnavailable로 매핑된다', () async {
      when(() => mockAuth.signInWithProvider(any())).thenThrow(
        fb.FirebaseAuthException(
          code: 'network-request-failed',
          message: 'network error',
        ),
      );

      final result = await repository.signInWithApple();

      expect(result, isA<Failure<User>>());
      expect((result! as Failure<User>).exception, isA<NoInternetConnection>());
    });

    test('AUTH-03-02b: web-context-cancelled (영국식 스펠링)도 '
        'null을 반환한다', () async {
      when(() => mockAuth.signInWithProvider(any())).thenThrow(
        fb.FirebaseAuthException(
          code: 'web-context-cancelled',
          message: 'cancelled',
        ),
      );

      final result = await repository.signInWithApple();

      expect(result, isNull);
    });
  });

  group('signInWithFacebook', () {
    test('성공 시 Result.success(User)를 반환하고 providerIds에 '
        'facebook.com 포함', () async {
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
          accessToken: FakeClassicToken(tokenString: 'fb-token-123'),
        ),
      );

      final mockProviderInfo = _MockUserInfo();
      when(() => mockProviderInfo.providerId).thenReturn('facebook.com');
      when(() => mockUser.providerData).thenReturn([mockProviderInfo]);

      when(
        () => mockAuth.signInWithCredential(any()),
      ).thenAnswer((_) async => mockCredential);

      final result = await repository.signInWithFacebook();

      expect(result, isA<Success<dynamic>>());
      final user = (result! as Success).data;
      expect(user.uid, 'uid-test');
      expect(user.providerIds, ['facebook.com']);
    });

    test('사용자 취소 (LoginStatus.cancelled) 시 null을 반환한다', () async {
      when(
        () => mockFacebookAuth.login(
          permissions: any(named: 'permissions'),
          loginTracking: any(named: 'loginTracking'),
          loginBehavior: any(named: 'loginBehavior'),
          nonce: any(named: 'nonce'),
        ),
      ).thenAnswer((_) async => LoginResult(status: LoginStatus.cancelled));

      final result = await repository.signInWithFacebook();

      expect(result, isNull);
    });

    // WR-02 (Phase 7 review): status=success 인데 accessToken 이 없는 상태는
    // 취소가 아니므로 silent no-op 이 아니라 실패로 승격한다.
    test('WR-02: accessToken 이 null 이면 ServiceUnavailable 을 반환한다', () async {
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
          // accessToken을 null로 유지
        ),
      );

      final result = await repository.signInWithFacebook();

      expect(result, isA<Failure<dynamic>>());
      expect((result! as Failure).exception, isA<ServiceUnavailable>());
    });

    // WR-02: failed / operationInProgress 는 "사용자 취소" 가 아니다 —
    // 이전 구현은 화면에 아무 일도 일어나지 않게 흡수했다.
    for (final status in <LoginStatus>[
      LoginStatus.failed,
      LoginStatus.operationInProgress,
    ]) {
      test('WR-02: LoginStatus.${status.name} → ServiceUnavailable (silent '
          'no-op 아님)', () async {
        when(
          () => mockFacebookAuth.login(
            permissions: any(named: 'permissions'),
            loginTracking: any(named: 'loginTracking'),
            loginBehavior: any(named: 'loginBehavior'),
            nonce: any(named: 'nonce'),
          ),
        ).thenAnswer((_) async => LoginResult(status: status, message: 'boom'));

        final result = await repository.signInWithFacebook();

        expect(result, isA<Failure<dynamic>>());
        expect((result! as Failure).exception, isA<ServiceUnavailable>());
      });
    }

    test(
      'FirebaseAuthException 시 Result.failure(AppException)를 반환한다',
      () async {
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
            accessToken: FakeClassicToken(tokenString: 'fb-token'),
          ),
        );

        when(
          () => mockAuth.signInWithCredential(any()),
        ).thenThrow(fb.FirebaseAuthException(code: 'network-request-failed'));

        final result = await repository.signInWithFacebook();

        expect(result, isA<Failure<dynamic>>());
        expect((result! as Failure).exception, isA<NoInternetConnection>());
      },
    );

    test('account-exists-with-different-credential 시 '
        'AccountExistsWithDifferentCredential를 반환한다', () async {
      when(
        () => mockFacebookAuth.login(
          permissions: any(named: 'permissions'),
          loginTracking: any(named: 'loginTracking'),
        ),
      ).thenAnswer(
        (_) async => LoginResult(
          status: LoginStatus.success,
          accessToken: FakeClassicToken(tokenString: 'fb-token'),
        ),
      );

      when(() => mockAuth.signInWithCredential(any())).thenThrow(
        fb.FirebaseAuthException(
          code: 'account-exists-with-different-credential',
          email: 'existing@example.com',
        ),
      );

      final result = await repository.signInWithFacebook();

      expect(result, isA<Failure<dynamic>>());
      final exception = (result! as Failure).exception;
      expect(exception, isA<AccountExistsWithDifferentCredential>());
      expect(
        (exception as AccountExistsWithDifferentCredential).email,
        'existing@example.com',
      );
    });

    test('비-Auth 예외 (PlatformException 등) 시 '
        'Result.failure(ServiceUnavailable)를 반환한다', () async {
      when(
        () => mockFacebookAuth.login(
          permissions: any(named: 'permissions'),
          loginTracking: any(named: 'loginTracking'),
          loginBehavior: any(named: 'loginBehavior'),
          nonce: any(named: 'nonce'),
        ),
      ).thenThrow(Exception('Platform error'));

      final result = await repository.signInWithFacebook();

      expect(result, isA<Failure<dynamic>>());
      expect((result! as Failure).exception, isA<ServiceUnavailable>());
    });
  });

  group('signOut (FacebookAuth logOut 테스트)', () {
    test('signOut이 FacebookAuth.logOut()을 호출한다', () async {
      when(() => mockGoogleSignIn.signOut()).thenAnswer((_) async {});
      when(() => mockFacebookAuth.logOut()).thenAnswer((_) async {});
      when(() => mockAuth.signOut()).thenAnswer((_) async {});

      await repository.signOut();

      verify(() => mockFacebookAuth.logOut()).called(1);
    });

    test('FacebookAuth.logOut() 실패 시에도 FirebaseAuth.signOut()은 '
        '호출된다', () async {
      when(() => mockGoogleSignIn.signOut()).thenAnswer((_) async {});
      when(
        () => mockFacebookAuth.logOut(),
      ).thenThrow(Exception('Facebook logOut failed'));
      when(() => mockAuth.signOut()).thenAnswer((_) async {});

      await repository.signOut();

      verify(() => mockFacebookAuth.logOut()).called(1);
      verify(() => mockAuth.signOut()).called(1);
    });
  });

  /// Phase 9.1 D-03 / D-04 회귀 가드 — 3개 social sign-in 메서드의 try-finally
  /// 가드가 어떤 경로에서도 begin()/end() 를 정확히 1회씩 호출함을 검증한다.
  ///
  /// 테스트 분류:
  /// - SDK throw / non-anonymous success path (SLP-1~6): 기존 6개 catch 분기
  ///   별로 begin/end 가 finally 에서 호출되는지 확인
  /// - race-window-path (SLP-7~9): `_safeDelete + signInWith*` 시퀀스에서
  ///   `begin → user.delete → signInWith* → end` 순서를 verifyInOrder 로
  ///   확정 (race-window 의 핵심 invariant — Warning #2 해소)
  group('Phase 9.1: socialLinkInProgress begin/end (race-fix)', () {
    /// ────────────────────────────────────────────────────────────
    /// SDK throw / non-anonymous success path — early-throw verification
    /// ────────────────────────────────────────────────────────────

    test(
      'Test SLP-1: signInWithGoogle 성공 (비익명) 시 begin() + end() 각 1회 호출',
      () async {
        // Arrange — 비익명 경로 + Google 성공 fixture (currentUser=null).
        when(() => mockAuth.currentUser).thenReturn(null);
        final mockAccount = _MockGoogleSignInAccount();
        when(() => mockAccount.authentication).thenReturn(
          const GoogleSignInAuthentication(idToken: 'id-token-test'),
        );
        when(
          () =>
              mockGoogleSignIn.authenticate(scopeHint: any(named: 'scopeHint')),
        ).thenAnswer((_) async => mockAccount);
        when(
          () => mockAuth.signInWithCredential(any()),
        ).thenAnswer((_) async => mockCredential);

        // Act
        final result = await repository.signInWithGoogle();

        // Assert
        expect(result, isA<Success<User>>());
        verify(() => mockSocialLinkInProgress.begin()).called(1);
        verify(() => mockSocialLinkInProgress.end()).called(1);
      },
    );

    test('Test SLP-2: signInWithGoogle 실패(GoogleSignInException 비-취소) 시에도 '
        'end() 가 finally 에서 호출됨', () async {
      // Arrange — Google SDK 가 throw 하는 시나리오.
      when(
        () => mockGoogleSignIn.authenticate(scopeHint: any(named: 'scopeHint')),
      ).thenThrow(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.unknownError,
          description: 'Something went wrong',
        ),
      );

      // Act
      final result = await repository.signInWithGoogle();

      // Assert — Failure 반환 + end() 는 여전히 호출.
      expect(result, isA<Failure<User>>());
      verify(() => mockSocialLinkInProgress.begin()).called(1);
      verify(() => mockSocialLinkInProgress.end()).called(1);
    });

    test(
      'Test SLP-3: signInWithApple 성공 (비익명) 시 begin() + end() 각 1회',
      () async {
        // Arrange — 비익명 경로 + signInWithProvider 성공.
        when(() => mockAuth.currentUser).thenReturn(null);
        when(
          () => mockAuth.signInWithProvider(any()),
        ).thenAnswer((_) async => mockCredential);

        // Act
        final result = await repository.signInWithApple();

        // Assert
        expect(result, isA<Success<User>>());
        verify(() => mockSocialLinkInProgress.begin()).called(1);
        verify(() => mockSocialLinkInProgress.end()).called(1);
      },
    );

    test('Test SLP-4: signInWithApple FirebaseAuthException(비-취소) 발생 시에도 '
        'end() 호출됨', () async {
      // Arrange — 비익명 경로 + signInWithProvider throw.
      when(() => mockAuth.currentUser).thenReturn(null);
      when(
        () => mockAuth.signInWithProvider(any()),
      ).thenThrow(fb.FirebaseAuthException(code: 'network-request-failed'));

      // Act
      final result = await repository.signInWithApple();

      // Assert
      expect(result, isA<Failure<User>>());
      verify(() => mockSocialLinkInProgress.begin()).called(1);
      verify(() => mockSocialLinkInProgress.end()).called(1);
    });

    test(
      'Test SLP-5: signInWithFacebook 성공 (비익명) 시 begin() + end() 각 1회',
      () async {
        // Arrange — 비익명 경로 + Facebook 성공 fixture.
        when(() => mockAuth.currentUser).thenReturn(null);
        final mockLoginResult = _MockFacebookLoginResult();
        final mockAccessToken = _MockFacebookAccessToken();
        when(
          () => mockFacebookAuth.login(
            permissions: any(named: 'permissions'),
            loginTracking: any(named: 'loginTracking'),
            loginBehavior: any(named: 'loginBehavior'),
            nonce: any(named: 'nonce'),
          ),
        ).thenAnswer((_) async => mockLoginResult);
        when(() => mockLoginResult.status).thenReturn(LoginStatus.success);
        when(() => mockLoginResult.accessToken).thenReturn(mockAccessToken);
        when(() => mockAccessToken.tokenString).thenReturn('fb-token-test');
        when(
          () => mockAuth.signInWithCredential(any()),
        ).thenAnswer((_) async => mockCredential);

        // Act
        final result = await repository.signInWithFacebook();

        // Assert
        expect(result, isA<Success<User>>());
        verify(() => mockSocialLinkInProgress.begin()).called(1);
        verify(() => mockSocialLinkInProgress.end()).called(1);
      },
    );

    test(
      'Test SLP-6: signInWithFacebook 비-Auth Object 예외 발생 시에도 '
      'end() 호출됨 (Object catch + ServiceUnavailable wrapping path)',
      () async {
        // Arrange — Facebook SDK 가 PlatformException 같은 비-Auth 예외 throw.
        when(
          () => mockFacebookAuth.login(
            permissions: any(named: 'permissions'),
            loginTracking: any(named: 'loginTracking'),
            loginBehavior: any(named: 'loginBehavior'),
            nonce: any(named: 'nonce'),
          ),
        ).thenThrow(Exception('platform error'));

        // Act
        final result = await repository.signInWithFacebook();

        // Assert
        expect(result, isA<Failure<User>>());
        verify(() => mockSocialLinkInProgress.begin()).called(1);
        verify(() => mockSocialLinkInProgress.end()).called(1);
      },
    );

    /// ────────────────────────────────────────────────────────────
    /// race-window-path direct verification (Warning #2 fix) —
    /// `_safeDelete + signInWithCredential` success path
    /// ────────────────────────────────────────────────────────────

    test(
      'Test SLP-7: signInWithGoogle race-window — anonymous + linkWithCredential '
      'throws credential-already-in-use → _safeDelete → signInWithCredential '
      'success. begin → user.delete → signInWithCredential → end 순서 검증',
      () async {
        // Arrange — anonymous user fixture (race-window 진입 조건).
        final mockAnonymous = _MockFbUser();
        when(() => mockAnonymous.isAnonymous).thenReturn(true);
        when(() => mockAuth.currentUser).thenReturn(mockAnonymous);

        // SDK flow: Google authenticate + token exchange.
        final mockAccount = _MockGoogleSignInAccount();
        when(() => mockAccount.authentication).thenReturn(
          const GoogleSignInAuthentication(idToken: 'id-token-test'),
        );
        when(
          () =>
              mockGoogleSignIn.authenticate(scopeHint: any(named: 'scopeHint')),
        ).thenAnswer((_) async => mockAccount);

        // linkWithCredential throws → triggers race-window fallback.
        when(() => mockAnonymous.linkWithCredential(any())).thenThrow(
          fb.FirebaseAuthException(code: 'credential-already-in-use'),
        );
        // _safeDelete (anonymous user.delete()) succeeds.
        when(() => mockAnonymous.delete()).thenAnswer((_) async {});
        // signInWithCredential succeeds (non-anonymous user returned).
        when(
          () => mockAuth.signInWithCredential(any()),
        ).thenAnswer((_) async => mockCredential);

        // Act
        final result = await repository.signInWithGoogle();

        // Assert — Success + race-window 핵심 호출 순서 검증.
        expect(result, isA<Success<User>>());
        // 호출 순서: begin → user.delete (= _safeDelete) → signInWithCredential
        // → end. race-window 핵심: end() 가 signInWithCredential resolve 후에
        // 발동됨을 확정. mocktail 의 verifyInOrder 는 verified 처리되지 않은
        // 매칭 호출만 1회씩 검증하므로, 별도 .called(1) 검증을 두지 않는다
        // (이미 verified 된 호출은 verifyInOrder 매칭에서 제외되어 실패).
        // begin/end 가 2회 이상 호출되면 verifyInOrder 후 unverified 호출이
        // 남아 verifyNever 로 추가 검증 가능 — 본 테스트는 1회 매칭 후 end.
        verifyInOrder([
          () => mockSocialLinkInProgress.begin(),
          () => mockAnonymous.delete(),
          () => mockAuth.signInWithCredential(any()),
          () => mockSocialLinkInProgress.end(),
        ]);
        // 추가 begin/end 호출이 없음을 검증 (1회 호출 invariant 보장).
        verifyNever(() => mockSocialLinkInProgress.begin());
        verifyNever(() => mockSocialLinkInProgress.end());
      },
    );

    /// Quick 260503-ang (Apple OAuth credential 재사용 픽스) — 기존 SLP-8
    /// 단일 테스트를 SLP-8a/8b/8c 세 갈래로 분리한다.
    /// - SLP-8a: `e.credential != null` → `signInWithCredential` 1회,
    ///   `signInWithProvider` 0회 (OAuth 재진입 회피 핵심 회귀 가드).
    /// - SLP-8b: `e.credential == null` → 기존 `signInWithProvider` fallback
    ///   보존 (회귀 0).
    /// - SLP-8c: `credential-already-in-use` 외 FirebaseAuthException →
    ///   rethrow → `_mapAuthException` 매핑 → `Result.failure`.
    test('Test SLP-8a: signInWithApple credential-reuse — anonymous + '
        'linkWithProvider throws credential-already-in-use 이고 e.credential != '
        'null 이면 _safeDelete 후 signInWithCredential 1회만 호출되고 '
        'signInWithProvider 는 0회 호출됨. '
        'begin → user.delete → signInWithCredential → end 순서 검증', () async {
      // Arrange — anonymous user fixture.
      final mockAnonymous = _MockFbUser();
      when(() => mockAnonymous.isAnonymous).thenReturn(true);
      when(() => mockAuth.currentUser).thenReturn(mockAnonymous);

      // linkWithProvider throws with non-null credential → triggers
      // credential-reuse fast-path (no OAuth re-entry).
      final reusedCredential = _FakeAuthCredential();
      when(() => mockAnonymous.linkWithProvider(any())).thenThrow(
        fb.FirebaseAuthException(
          code: 'credential-already-in-use',
          credential: reusedCredential,
        ),
      );
      // _safeDelete succeeds.
      when(() => mockAnonymous.delete()).thenAnswer((_) async {});
      // signInWithCredential success (credential reuse path).
      when(
        () => mockAuth.signInWithCredential(any()),
      ).thenAnswer((_) async => mockCredential);

      // Act
      final result = await repository.signInWithApple();

      // Assert — Success + 호출 순서 + OAuth 재진입 0회 invariant.
      expect(result, isA<Success<User>>());
      // mocktail.verifyInOrder 는 매칭된 호출을 VERIFIED 처리하므로,
      // 동일 호출에 대한 후속 verify(...).called(1) 은 사용 불가.
      // 대신 verifyInOrder + verifyNever(signInWithProvider) 조합으로
      // "signInWithCredential 1회 + signInWithProvider 0회" invariant 보장.
      verifyInOrder([
        () => mockSocialLinkInProgress.begin(),
        () => mockAnonymous.delete(),
        () => mockAuth.signInWithCredential(any()),
        () => mockSocialLinkInProgress.end(),
      ]);
      // 핵심 회귀 가드: OAuth 시트/Custom Tab 재진입(signInWithProvider) 0회.
      verifyNever(() => mockAuth.signInWithProvider(any()));
      // 추가 signInWithCredential 호출 없음 (verifyInOrder 매칭 1회 외에).
      verifyNever(() => mockAuth.signInWithCredential(any()));
      // 추가 begin/end 호출 없음 (try-finally 1회 invariant).
      verifyNever(() => mockSocialLinkInProgress.begin());
      verifyNever(() => mockSocialLinkInProgress.end());
    });

    test('Test SLP-8b: signInWithApple credential null fallback — anonymous + '
        'linkWithProvider throws credential-already-in-use 이고 e.credential == '
        'null 이면 기존 signInWithProvider fallback 경로가 보존됨. '
        'begin → user.delete → signInWithProvider → end 순서 검증', () async {
      // Arrange — anonymous user fixture.
      final mockAnonymous = _MockFbUser();
      when(() => mockAnonymous.isAnonymous).thenReturn(true);
      when(() => mockAuth.currentUser).thenReturn(mockAnonymous);

      // linkWithProvider throws with null credential (credential 미지정).
      when(
        () => mockAnonymous.linkWithProvider(any()),
      ).thenThrow(fb.FirebaseAuthException(code: 'credential-already-in-use'));
      // _safeDelete succeeds.
      when(() => mockAnonymous.delete()).thenAnswer((_) async {});
      // signInWithProvider success (legacy fallback path).
      when(
        () => mockAuth.signInWithProvider(any()),
      ).thenAnswer((_) async => mockCredential);

      // Act
      final result = await repository.signInWithApple();

      // Assert — fallback 경로 보존 (회귀 0).
      expect(result, isA<Success<User>>());
      verifyInOrder([
        () => mockSocialLinkInProgress.begin(),
        () => mockAnonymous.delete(),
        () => mockAuth.signInWithProvider(any()),
        () => mockSocialLinkInProgress.end(),
      ]);
      // signInWithCredential 은 fallback 경로에서 호출되지 않음.
      verifyNever(() => mockAuth.signInWithCredential(any()));
      verifyNever(() => mockSocialLinkInProgress.begin());
      verifyNever(() => mockSocialLinkInProgress.end());
    });

    test('Test SLP-8c: signInWithApple linkWithProvider — '
        'credential-already-in-use 외 FirebaseAuthException(예: '
        'network-request-failed) 은 rethrow 되어 outer catch 가 _mapAuthException '
        '으로 매핑한다. delete / signInWithProvider / signInWithCredential 미호출, '
        'begin/end 는 try-finally 로 1회씩 호출됨', () async {
      // Arrange — anonymous user fixture + 비-credential-already-in-use 예외.
      final mockAnonymous = _MockFbUser();
      when(() => mockAnonymous.isAnonymous).thenReturn(true);
      when(() => mockAuth.currentUser).thenReturn(mockAnonymous);

      when(
        () => mockAnonymous.linkWithProvider(any()),
      ).thenThrow(fb.FirebaseAuthException(code: 'network-request-failed'));
      // 의도적으로 anonymous.delete / signInWithProvider /
      // signInWithCredential stub 안 함 — verifyNever 로 검증.

      // Act
      final result = await repository.signInWithApple();

      // Assert — Failure + _mapAuthException 매핑 + race-fix invariant 보존.
      expect(result, isA<Failure<User>>());
      final failure = (result! as Failure<User>).exception;
      expect(failure, isA<NoInternetConnection>());
      verifyNever(() => mockAnonymous.delete());
      verifyNever(() => mockAuth.signInWithProvider(any()));
      verifyNever(() => mockAuth.signInWithCredential(any()));
      verify(() => mockSocialLinkInProgress.begin()).called(1);
      verify(() => mockSocialLinkInProgress.end()).called(1);
    });

    test('Test SLP-9: signInWithFacebook race-window — anonymous + '
        'linkWithCredential throws credential-already-in-use → _safeDelete → '
        'signInWithCredential success. begin → user.delete → signInWithCredential '
        '→ end 순서 검증', () async {
      // Arrange — anonymous user fixture.
      final mockAnonymous = _MockFbUser();
      when(() => mockAnonymous.isAnonymous).thenReturn(true);
      when(() => mockAuth.currentUser).thenReturn(mockAnonymous);

      // SDK flow: Facebook login + token exchange.
      final mockLoginResult = _MockFacebookLoginResult();
      final mockAccessToken = _MockFacebookAccessToken();
      when(
        () => mockFacebookAuth.login(
          permissions: any(named: 'permissions'),
          loginTracking: any(named: 'loginTracking'),
          loginBehavior: any(named: 'loginBehavior'),
          nonce: any(named: 'nonce'),
        ),
      ).thenAnswer((_) async => mockLoginResult);
      when(() => mockLoginResult.status).thenReturn(LoginStatus.success);
      when(() => mockLoginResult.accessToken).thenReturn(mockAccessToken);
      when(() => mockAccessToken.tokenString).thenReturn('fb-token-test');

      // linkWithCredential throws → triggers race-window fallback.
      when(
        () => mockAnonymous.linkWithCredential(any()),
      ).thenThrow(fb.FirebaseAuthException(code: 'credential-already-in-use'));
      // _safeDelete succeeds.
      when(() => mockAnonymous.delete()).thenAnswer((_) async {});
      // signInWithCredential succeeds.
      when(
        () => mockAuth.signInWithCredential(any()),
      ).thenAnswer((_) async => mockCredential);

      // Act
      final result = await repository.signInWithFacebook();

      // Assert
      expect(result, isA<Success<User>>());
      verifyInOrder([
        () => mockSocialLinkInProgress.begin(),
        () => mockAnonymous.delete(),
        () => mockAuth.signInWithCredential(any()),
        () => mockSocialLinkInProgress.end(),
      ]);
      verifyNever(() => mockSocialLinkInProgress.begin());
      verifyNever(() => mockSocialLinkInProgress.end());
    });
  });

  group('Phase 12: signInWithKakao (Custom Token 흐름)', () {
    /// Kakao 그룹 공통 setUp — 성공 path 의 4단계 (KakaoSdkClient → Cloud
    /// Function → signInWithCustomToken → User 매핑) 를 stub 한다. 각 테스트는
    /// 필요한 단계만 override 한다.
    late _MockHttpsCallable mockCallable;

    setUp(() {
      mockCallable = _MockHttpsCallable();
      // 기본: KakaoSdkClient 가 ID Token + nonce 반환.
      when(() => mockKakaoSdkClient.signIn()).thenAnswer(
        (_) async => const KakaoSignInResult(idToken: 'IDT', nonce: 'NONCE'),
      );
      // 기본: httpsCallable('kakaoCustomToken') → mockCallable.
      when(
        () =>
            mockFunctions.httpsCallable(any(), options: any(named: 'options')),
      ).thenReturn(mockCallable);
      // 기본: callable.call(...) → customToken 응답.
      // HttpsCallableResult 는 private ctor 라 mocktail 로 .data 만 stub 한다.
      final defaultResult = _MockHttpsCallableResult();
      when(() => defaultResult.data).thenReturn(<String, dynamic>{
        'customToken': 'CT',
        'uid': 'kakao-uid',
        'isNewUser': true,
      });
      when(
        () => mockCallable.call<Map<String, dynamic>>(any()),
      ).thenAnswer((_) async => defaultResult);
      // 기본: signInWithCustomToken('CT') → mockCredential (mockUser 포함).
      when(() => mockUser.uid).thenReturn('kakao-uid');
      when(() => mockUser.email).thenReturn('kakao@example.com');
      when(() => mockUser.providerData).thenReturn(<fb.UserInfo>[]);
      when(
        () => mockAuth.signInWithCustomToken('CT'),
      ).thenAnswer((_) async => mockCredential);
    });

    test('Test K1: 사용자 취소 (kakaoSdkClient → null) → null + race-fix '
        'begin/end 1회', () async {
      when(() => mockKakaoSdkClient.signIn()).thenAnswer((_) async => null);

      final result = await repository.signInWithKakao();

      expect(result, isNull);
      verify(() => mockSocialLinkInProgress.begin()).called(1);
      verify(() => mockSocialLinkInProgress.end()).called(1);
      // CF / Firebase Auth 미호출 검증.
      verifyNever(
        () =>
            mockFunctions.httpsCallable(any(), options: any(named: 'options')),
      );
      verifyNever(() => mockAuth.signInWithCustomToken(any()));
    });

    test('Test K2: 성공 path — KakaoSdkClient → CF → signInWithCustomToken → '
        'User 매핑', () async {
      final result = await repository.signInWithKakao();

      expect(result, isA<Success<dynamic>>());
      final user = (result! as Success).data as User;
      expect(user.uid, 'kakao-uid');
      expect(user.email, 'kakao@example.com');
      verify(() => mockSocialLinkInProgress.begin()).called(1);
      verify(() => mockSocialLinkInProgress.end()).called(1);
    });

    // WR-10 (Phase 7 review): Custom Token sign-in callable 4개만 timeout 이
    // 없어 race-fix try-finally 안에서 hang 시 `_socialLinkInProgress.end()`
    // 도 hang → splash 자동 익명 sign-in / auth_guard GC-04 fail-safe redirect
    // 무한 차단. link arm (10s) 과 동일 값을 적용했는지 검증한다.
    test('WR-10: kakaoCustomToken callable 에 10초 timeout 옵션이 전달된다', () async {
      await repository.signInWithKakao();

      final captured =
          verify(
                () => mockFunctions.httpsCallable(
                  'kakaoCustomToken',
                  options: captureAny(named: 'options'),
                ),
              ).captured.single
              as HttpsCallableOptions;
      expect(captured.timeout, const Duration(seconds: 10));
    });

    test('Test K3: 성공 path — httpsCallable(kakaoCustomToken).call({idToken, '
        'nonce}) 정확히 1회 호출', () async {
      await repository.signInWithKakao();

      // CF 이름 + payload 검증 (Pitfall 2 single nonce — KakaoSignInResult 의
      // nonce 가 그대로 callable payload 에 전달됐는지).
      verify(
        () => mockFunctions.httpsCallable(
          'kakaoCustomToken',
          options: any(named: 'options'),
        ),
      ).called(1);
      verify(
        () => mockCallable.call<Map<String, dynamic>>(<String, dynamic>{
          'idToken': 'IDT',
          'nonce': 'NONCE',
        }),
      ).called(1);
      verify(() => mockAuth.signInWithCustomToken('CT')).called(1);
    });

    test('Test K4: FirebaseFunctionsException(invalid-argument) → '
        'ServiceUnavailable Failure', () async {
      when(() => mockCallable.call<Map<String, dynamic>>(any())).thenThrow(
        FirebaseFunctionsException(
          code: 'invalid-argument',
          message: 'bad nonce',
        ),
      );

      final result = await repository.signInWithKakao();

      expect(result, isA<Failure<dynamic>>());
      expect((result! as Failure).exception, isA<ServiceUnavailable>());
      verify(() => mockSocialLinkInProgress.end()).called(1);
    });

    test('Test K5: FirebaseFunctionsException(unavailable) → '
        'NoInternetConnection Failure', () async {
      when(() => mockCallable.call<Map<String, dynamic>>(any())).thenThrow(
        FirebaseFunctionsException(code: 'unavailable', message: 'CF down'),
      );

      final result = await repository.signInWithKakao();

      expect(result, isA<Failure<dynamic>>());
      expect((result! as Failure).exception, isA<NoInternetConnection>());
    });

    test('Test K6: FirebaseAuthException(signInWithCustomToken) → '
        '_mapAuthException 매핑', () async {
      when(
        () => mockAuth.signInWithCustomToken('CT'),
      ).thenThrow(fb.FirebaseAuthException(code: 'invalid-credential'));

      final result = await repository.signInWithKakao();

      expect(result, isA<Failure<dynamic>>());
      expect((result! as Failure).exception, isA<InvalidCredentials>());
    });

    test('Test K7: KakaoSdkClient throw 비-CANCELED PlatformException → '
        'ServiceUnavailable Failure', () async {
      when(
        () => mockKakaoSdkClient.signIn(),
      ).thenThrow(PlatformException(code: 'NETWORK_ERROR'));

      final result = await repository.signInWithKakao();

      expect(result, isA<Failure<dynamic>>());
      expect((result! as Failure).exception, isA<ServiceUnavailable>());
    });

    test('Test K8: race-fix invariant — exception 발생해도 finally 가 '
        'end() 호출', () async {
      when(() => mockKakaoSdkClient.signIn()).thenThrow(Exception('boom'));

      await repository.signInWithKakao();

      verify(() => mockSocialLinkInProgress.begin()).called(1);
      verify(() => mockSocialLinkInProgress.end()).called(1);
    });

    test('Test K9: idToken null (OIDC 미활성화 — Pitfall 1) → '
        'ServiceUnavailable Failure', () async {
      // KakaoSdkClient 가 idToken null 시 ServiceUnavailable throw.
      when(
        () => mockKakaoSdkClient.signIn(),
      ).thenThrow(const ServiceUnavailable());

      final result = await repository.signInWithKakao();

      expect(result, isA<Failure<dynamic>>());
      expect((result! as Failure).exception, isA<ServiceUnavailable>());
      verify(() => mockSocialLinkInProgress.end()).called(1);
    });

    test(
      'Test K10: response.data.customToken 이 null → ServiceUnavailable',
      () async {
        final nullTokenResult = _MockHttpsCallableResult();
        when(
          () => nullTokenResult.data,
        ).thenReturn(<String, dynamic>{'customToken': null, 'uid': 'x'});
        when(
          () => mockCallable.call<Map<String, dynamic>>(any()),
        ).thenAnswer((_) async => nullTokenResult);

        final result = await repository.signInWithKakao();

        expect(result, isA<Failure<dynamic>>());
        expect((result! as Failure).exception, isA<ServiceUnavailable>());
      },
    );

    test('Test K11: FirebaseFunctionsException(already-exists) → '
        'AccountExistsWithDifferentCredential Failure (R3 — D-34)', () async {
      when(() => mockCallable.call<Map<String, dynamic>>(any())).thenThrow(
        FirebaseFunctionsException(
          code: 'already-exists',
          message: 'errorAccountExistsWithDifferentCredential',
        ),
      );

      final result = await repository.signInWithKakao();

      expect(result, isA<Failure<dynamic>>());
      final failure = result! as Failure;
      expect(failure.exception, isA<AccountExistsWithDifferentCredential>());
      // Cloud Function PII 미응답 — email null 보존.
      final ex = failure.exception as AccountExistsWithDifferentCredential;
      expect(ex.email, isNull);
      // Pitfall 8 — race-fix try-finally 보존 검증.
      verify(() => mockSocialLinkInProgress.end()).called(1);
    });

    // ========================================================================
    // Phase 9.2 Gap B Kakao 충돌 path (HUMAN-UAT 2026-05-11 — kakaoCustomToken
    // already-exists invariant). Plan 07 의 functions side fix (resolveIdentity
    // callerUid 분기 email collision detect) 가 배포된 후 익명승격 path 에서
    // kakaoCustomToken 가 'already-exists' HttpsError throw → client 의
    // _mapFunctionsException 가 Phase 12.1 D-34 분기 (AccountExistsWith-
    // DifferentCredential cause:e, email:null) 로 자동 매핑 + _autoSend-
    // EmailVerification 차단 + race-fix end() 1회 invariant 의 Dart-side
    // regression sentinel.
    test(
      'NK-COLLISION-K1: 익명승격 + kakaoCustomToken already-exists → '
      'AccountExistsWithDifferentCredential 매핑 (Plan 07 deploy 후 sentinel)',
      () async {
        // 익명승격 path 시뮬레이션 — Plan 07 의 callerUid 분기 활성 조건.
        when(() => mockAuth.currentUser).thenReturn(mockUser);
        when(() => mockUser.isAnonymous).thenReturn(true);
        when(() => mockCallable.call<Map<String, dynamic>>(any())).thenThrow(
          FirebaseFunctionsException(
            code: 'already-exists',
            message: 'errorAccountExistsWithDifferentCredential',
          ),
        );

        final result = await repository.signInWithKakao();

        expect(result, isA<Failure<dynamic>>());
        final failure = result! as Failure;
        expect(failure.exception, isA<AccountExistsWithDifferentCredential>());
        // Phase 12.1 D-34 매핑 — email=null + cause=FirebaseFunctionsException.
        final ex = failure.exception as AccountExistsWithDifferentCredential;
        expect(ex.email, isNull);
        expect(ex.cause, isA<FirebaseFunctionsException>());
      },
    );

    test(
      'NK-COLLISION-K2: 익명승격 + already-exists → signInWithCustomToken / '
      'sendEmailVerification 미진입 (Gap B autoSendEmailVerification 차단)',
      () async {
        when(() => mockAuth.currentUser).thenReturn(mockUser);
        when(() => mockUser.isAnonymous).thenReturn(true);
        when(() => mockCallable.call<Map<String, dynamic>>(any())).thenThrow(
          FirebaseFunctionsException(
            code: 'already-exists',
            message: 'errorAccountExistsWithDifferentCredential',
          ),
        );

        await repository.signInWithKakao();

        // Cloud Function throw 이후 signInWithCustomToken 미진입 invariant.
        verifyNever(() => mockAuth.signInWithCustomToken(any()));
        // sendEmailVerification 미호출 — fbUser 생성 0 → side-effect 격리.
        verifyNever(() => mockUser.sendEmailVerification());
      },
    );

    test(
      'NK-COLLISION-K3: 익명승격 + already-exists → race-fix begin/end + '
      'KakaoSdkClient.logout 정확 1회 (Phase 9.1 D-03/D-04 + D-57 invariant)',
      () async {
        when(() => mockAuth.currentUser).thenReturn(mockUser);
        when(() => mockUser.isAnonymous).thenReturn(true);
        when(() => mockCallable.call<Map<String, dynamic>>(any())).thenThrow(
          FirebaseFunctionsException(
            code: 'already-exists',
            message: 'errorAccountExistsWithDifferentCredential',
          ),
        );

        await repository.signInWithKakao();

        verify(() => mockSocialLinkInProgress.begin()).called(1);
        verify(() => mockSocialLinkInProgress.end()).called(1);
        verify(() => mockKakaoSdkClient.logout()).called(1);
      },
    );
  });

  // ==========================================================================
  // Phase 13 — see ROADMAP.md
  // ==========================================================================
  // signInWithNaver — Custom Token 흐름 (Phase 12 verbatim 미러 + D-46 nonce
  // 부재 + D-57 finally logout). Validation Architecture line 1616 —
  // T-13-NAVER-REPO-{n}.
  group('AuthRepository.signInWithNaver (T-13-NAVER-REPO)', () {
    late _MockHttpsCallable mockCallable;

    setUp(() {
      mockCallable = _MockHttpsCallable();
      // 기본: NaverSdkClient 가 access_token 반환.
      when(() => mockNaverSdkClient.signIn()).thenAnswer(
        (_) async => const NaverSignInResult(accessToken: 'AT_NAVER'),
      );
      // 기본: httpsCallable('naverCustomToken') → mockCallable.
      when(
        () =>
            mockFunctions.httpsCallable(any(), options: any(named: 'options')),
      ).thenReturn(mockCallable);
      // 기본: callable.call(...) → customToken 응답.
      final defaultResult = _MockHttpsCallableResult();
      when(() => defaultResult.data).thenReturn(<String, dynamic>{
        'customToken': 'CT_NAVER',
        'uid': 'naver-uid',
        'isNewUser': true,
      });
      when(
        () => mockCallable.call<Map<String, dynamic>>(any()),
      ).thenAnswer((_) async => defaultResult);
      // 기본: signInWithCustomToken('CT_NAVER') → mockCredential.
      when(() => mockUser.uid).thenReturn('naver-uid');
      when(() => mockUser.email).thenReturn('naver@example.com');
      when(() => mockUser.providerData).thenReturn(<fb.UserInfo>[]);
      when(
        () => mockAuth.signInWithCustomToken('CT_NAVER'),
      ).thenAnswer((_) async => mockCredential);
    });

    test('T-13-NAVER-REPO-01: 정상 → Result.success(User) + finally logout '
        '+ end()', () async {
      final result = await repository.signInWithNaver();

      expect(result, isA<Success<dynamic>>());
      final user = (result! as Success).data as User;
      expect(user.uid, 'naver-uid');
      expect(user.email, 'naver@example.com');
      verify(() => mockSocialLinkInProgress.begin()).called(1);
      verify(() => mockNaverSdkClient.logout()).called(1); // D-57
      verify(() => mockSocialLinkInProgress.end()).called(1);
    });

    test('T-13-NAVER-REPO-02 (WR-01-iter2): NaverSdkClient null (사용자 취소) → '
        'null + logout 1회 호출 (D-57 모든 path 일관)', () async {
      when(() => mockNaverSdkClient.signIn()).thenAnswer((_) async => null);

      final result = await repository.signInWithNaver();

      expect(result, isNull);
      // WR-01-iter2 (Phase 13 review iter2): D-57 1회성 토큰 정책의 invariant
      // 강화 — timeout / 취소 path 에서도 SDK 측 디바이스 토큰이 잔존할 가능성
      // (24h TTL) 이 있으므로 모든 path 에서 logout. NaverSdkClient.logout 은
      // 내부 try/catch graceful — "no session" 상태도 silent 흡수.
      verify(() => mockNaverSdkClient.logout()).called(1);
      verify(() => mockSocialLinkInProgress.end()).called(1);
      // CF / Firebase Auth 미호출 검증.
      verifyNever(
        () =>
            mockFunctions.httpsCallable(any(), options: any(named: 'options')),
      );
      verifyNever(() => mockAuth.signInWithCustomToken(any()));
    });

    test('T-13-NAVER-REPO-03: FirebaseFunctionsException(invalid-argument) '
        '→ ServiceUnavailable Failure', () async {
      when(() => mockCallable.call<Map<String, dynamic>>(any())).thenThrow(
        FirebaseFunctionsException(
          code: 'invalid-argument',
          message: 'bad accessToken',
        ),
      );

      final result = await repository.signInWithNaver();

      expect(result, isA<Failure<dynamic>>());
      expect((result! as Failure).exception, isA<ServiceUnavailable>());
      verify(() => mockNaverSdkClient.logout()).called(1);
      verify(() => mockSocialLinkInProgress.end()).called(1);
    });

    test('T-13-NAVER-REPO-04: FirebaseAuthException(signInWithCustomToken) '
        '→ _mapAuthException 매핑', () async {
      when(
        () => mockAuth.signInWithCustomToken('CT_NAVER'),
      ).thenThrow(fb.FirebaseAuthException(code: 'invalid-credential'));

      final result = await repository.signInWithNaver();

      expect(result, isA<Failure<dynamic>>());
      expect((result! as Failure).exception, isA<InvalidCredentials>());
    });

    test(
      'T-13-NAVER-REPO-05 (WR-01-iter2): 비-Auth 예외 (PlatformException 등) '
      '→ ServiceUnavailable(cause) + signIn 단계 throw → logout 1회 호출',
      () async {
        when(
          () => mockNaverSdkClient.signIn(),
        ).thenThrow(PlatformException(code: 'NETWORK_ERROR'));

        final result = await repository.signInWithNaver();

        expect(result, isA<Failure<dynamic>>());
        expect((result! as Failure).exception, isA<ServiceUnavailable>());
        // WR-01-iter2 (Phase 13 review iter2): D-57 invariant — signIn 단계 throw
        // path 에서도 SDK 가 부분적으로 토큰을 발급한 후 throw 한 가능성을 배제할
        // 수 없으므로 모든 path 에서 logout. graceful no-op 으로 흡수.
        verify(() => mockNaverSdkClient.logout()).called(1);
        // end 는 race-fix 보장 — exception 와 무관하게 1회.
        verify(() => mockSocialLinkInProgress.end()).called(1);
      },
    );

    test('T-13-NAVER-REPO-06: response.data.customToken 이 null → '
        'ServiceUnavailable Failure', () async {
      final nullTokenResult = _MockHttpsCallableResult();
      when(
        () => nullTokenResult.data,
      ).thenReturn(<String, dynamic>{'customToken': null, 'uid': 'x'});
      when(
        () => mockCallable.call<Map<String, dynamic>>(any()),
      ).thenAnswer((_) async => nullTokenResult);

      final result = await repository.signInWithNaver();

      expect(result, isA<Failure<dynamic>>());
      expect((result! as Failure).exception, isA<ServiceUnavailable>());
    });

    test('T-13-NAVER-REPO-07: race-fix begin/end + logout 호출 순서 검증 '
        '(Pitfall 2 + Pitfall 8)', () async {
      await repository.signInWithNaver();

      // begin → SDK signIn → callable → logout → end 순서 (Pitfall 2 — logout
      // 은 race-fix end 직전 위치).
      verifyInOrder([
        () => mockSocialLinkInProgress.begin(),
        () => mockNaverSdkClient.signIn(),
        () => mockFunctions.httpsCallable(
          'naverCustomToken',
          options: any(named: 'options'),
        ),
        () => mockNaverSdkClient.logout(),
        () => mockSocialLinkInProgress.end(),
      ]);
    });

    test('T-13-NAVER-REPO-08: already-exists FirebaseFunctionsException → '
        'AccountExistsWithDifferentCredential 자동 흡수 '
        '(Phase 12.1 D-34 회귀 가드)', () async {
      when(() => mockCallable.call<Map<String, dynamic>>(any())).thenThrow(
        FirebaseFunctionsException(
          code: 'already-exists',
          message: 'errorAccountExistsWithDifferentCredential',
        ),
      );

      final result = await repository.signInWithNaver();

      expect(result, isA<Failure<dynamic>>());
      final failure = result! as Failure;
      expect(failure.exception, isA<AccountExistsWithDifferentCredential>());
      // Cloud Function PII 미응답 — email null 보존.
      final ex = failure.exception as AccountExistsWithDifferentCredential;
      expect(ex.email, isNull);
      verify(() => mockNaverSdkClient.logout()).called(1);
      verify(() => mockSocialLinkInProgress.end()).called(1);
    });

    test('T-13-NAVER-REPO-09: callable payload = {accessToken} 단일 (D-46 — '
        'nonce 부재)', () async {
      await repository.signInWithNaver();

      // D-46 — Naver 는 OAuth 2.0 access_token 흐름이라 nonce 부재.
      verify(
        () => mockFunctions.httpsCallable(
          'naverCustomToken',
          options: any(named: 'options'),
        ),
      ).called(1);
      verify(
        () => mockCallable.call<Map<String, dynamic>>(<String, dynamic>{
          'accessToken': 'AT_NAVER',
        }),
      ).called(1);
      verify(() => mockAuth.signInWithCustomToken('CT_NAVER')).called(1);
    });
  });

  // ==========================================================================
  // Phase 9.2 Gap B Naver 충돌 path (HUMAN-UAT 2026-05-11 — naverCustomToken
  // already-exists invariant). Plan 07 의 Functions side fix (resolveIdentity
  // callerUid 분기 email collision detect) 가 배포된 후 익명승격 path 에서
  // naverCustomToken 가 'already-exists' HttpsError throw 시 client 의
  // _mapFunctionsException 가 Phase 12.1 D-34 분기 (AccountExistsWith-
  // DifferentCredential cause:e, email:null) 로 자동 매핑되는 Dart-side
  // regression sentinel.
  // ==========================================================================
  group('Phase 9.2 Gap B Naver 충돌 path (NK-COLLISION-N)', () {
    late _MockHttpsCallable mockCallable;

    setUp(() {
      mockCallable = _MockHttpsCallable();
      when(() => mockNaverSdkClient.signIn()).thenAnswer(
        (_) async => const NaverSignInResult(accessToken: 'AT_NAVER'),
      );
      when(
        () =>
            mockFunctions.httpsCallable(any(), options: any(named: 'options')),
      ).thenReturn(mockCallable);
    });

    test(
      'NK-COLLISION-N1: 익명승격 + naverCustomToken already-exists → '
      'AccountExistsWithDifferentCredential 매핑 (Plan 07 deploy 후 sentinel)',
      () async {
        // 익명승격 path 시뮬레이션 — Plan 07 의 callerUid 분기 활성 조건.
        when(() => mockAuth.currentUser).thenReturn(mockUser);
        when(() => mockUser.isAnonymous).thenReturn(true);
        when(() => mockCallable.call<Map<String, dynamic>>(any())).thenThrow(
          FirebaseFunctionsException(
            code: 'already-exists',
            message: 'errorAccountExistsWithDifferentCredential',
          ),
        );

        final result = await repository.signInWithNaver();

        expect(result, isA<Failure<dynamic>>());
        final failure = result! as Failure;
        expect(failure.exception, isA<AccountExistsWithDifferentCredential>());
        // Phase 12.1 D-34 매핑 — email=null + cause=FirebaseFunctionsException.
        final ex = failure.exception as AccountExistsWithDifferentCredential;
        expect(ex.email, isNull);
        expect(ex.cause, isA<FirebaseFunctionsException>());
      },
    );

    test(
      'NK-COLLISION-N2: 익명승격 + already-exists → signInWithCustomToken / '
      'sendEmailVerification 미진입 (Gap B autoSendEmailVerification 차단)',
      () async {
        when(() => mockAuth.currentUser).thenReturn(mockUser);
        when(() => mockUser.isAnonymous).thenReturn(true);
        when(() => mockCallable.call<Map<String, dynamic>>(any())).thenThrow(
          FirebaseFunctionsException(
            code: 'already-exists',
            message: 'errorAccountExistsWithDifferentCredential',
          ),
        );

        await repository.signInWithNaver();

        // Cloud Function throw 이후 signInWithCustomToken 미진입 invariant.
        verifyNever(() => mockAuth.signInWithCustomToken(any()));
        // sendEmailVerification 미호출 — fbUser 생성 0 → side-effect 격리.
        verifyNever(() => mockUser.sendEmailVerification());
      },
    );

    test(
      'NK-COLLISION-N3: 익명승격 + already-exists → race-fix begin/end + '
      'NaverSdkClient.logout 정확 1회 (Phase 9.1 D-03/D-04 + D-57 invariant)',
      () async {
        when(() => mockAuth.currentUser).thenReturn(mockUser);
        when(() => mockUser.isAnonymous).thenReturn(true);
        when(() => mockCallable.call<Map<String, dynamic>>(any())).thenThrow(
          FirebaseFunctionsException(
            code: 'already-exists',
            message: 'errorAccountExistsWithDifferentCredential',
          ),
        );

        await repository.signInWithNaver();

        verify(() => mockSocialLinkInProgress.begin()).called(1);
        verify(() => mockSocialLinkInProgress.end()).called(1);
        verify(() => mockNaverSdkClient.logout()).called(1);
      },
    );
  });

  // ==========================================================================
  // Phase 13 — see ROADMAP.md, D-57 retroactive
  // ==========================================================================
  // signInWithKakao 의 finally 블록에서 KakaoSdkClient.logout 이 호출되는지
  // 회귀 가드. Validation Architecture line 1617 — T-13-KAKAO-RETRO-LOGOUT-{n}.
  group('AuthRepository.signInWithKakao D-57 retroactive '
      '(T-13-KAKAO-RETRO-LOGOUT)', () {
    late _MockHttpsCallable mockCallable;

    setUp(() {
      mockCallable = _MockHttpsCallable();
      // Phase 12 정상 path 재사용 — KakaoSdkClient signIn → CF → 인증.
      when(() => mockKakaoSdkClient.signIn()).thenAnswer(
        (_) async => const KakaoSignInResult(idToken: 'IDT', nonce: 'NONCE'),
      );
      when(
        () =>
            mockFunctions.httpsCallable(any(), options: any(named: 'options')),
      ).thenReturn(mockCallable);
      final defaultResult = _MockHttpsCallableResult();
      when(
        () => defaultResult.data,
      ).thenReturn(<String, dynamic>{'customToken': 'CT', 'uid': 'kakao-uid'});
      when(
        () => mockCallable.call<Map<String, dynamic>>(any()),
      ).thenAnswer((_) async => defaultResult);
      when(() => mockUser.uid).thenReturn('kakao-uid');
      when(() => mockUser.email).thenReturn('kakao@example.com');
      when(() => mockUser.providerData).thenReturn(<fb.UserInfo>[]);
      when(
        () => mockAuth.signInWithCustomToken('CT'),
      ).thenAnswer((_) async => mockCredential);
    });

    test('T-13-KAKAO-RETRO-LOGOUT-01: 정상 종료 finally 에서 '
        'KakaoSdkClient.logout 호출 (D-57)', () async {
      await repository.signInWithKakao();

      verify(() => mockKakaoSdkClient.logout()).called(1);
      verify(() => mockSocialLinkInProgress.end()).called(1);
    });

    test('T-13-KAKAO-RETRO-LOGOUT-02 (WR-01-iter2): 사용자 취소 (signIn null) → '
        'KakaoSdkClient.logout 1회 호출 (D-57 모든 path 일관)', () async {
      when(() => mockKakaoSdkClient.signIn()).thenAnswer((_) async => null);

      final result = await repository.signInWithKakao();

      expect(result, isNull);
      // WR-01-iter2 (Phase 13 review iter2): D-57 1회성 토큰 정책의 invariant
      // 강화 — Naver path 와 대칭. timeout / 취소 path 에서도 SDK 측 토큰
      // 잔존 가능성을 배제하기 위해 모든 path 에서 logout. KakaoSdkClient.logout
      // 은 내부 try/catch graceful — "no session" 상태도 silent 흡수.
      verify(() => mockKakaoSdkClient.logout()).called(1);
      verify(() => mockSocialLinkInProgress.end()).called(1);
    });

    test('T-13-KAKAO-RETRO-LOGOUT-03: race-fix begin/end + logout 호출 순서 '
        '(Pitfall 2)', () async {
      await repository.signInWithKakao();

      verifyInOrder([
        () => mockSocialLinkInProgress.begin(),
        () => mockKakaoSdkClient.signIn(),
        () => mockKakaoSdkClient.logout(), // D-57 — end 직전 (Pitfall 2)
        () => mockSocialLinkInProgress.end(),
      ]);
    });
  });

  // Phase 10.2 D-A3 — Plan 02 land 시 production signOutAndResetOnboarding
  // 도입 (8-arg ctor + 메서드 신규) 으로 GREEN 전환. 현재 RED (Plan 02 land
  // 전) 는 의도된 Wave 0 acceptance signal: 본 group 의 8-arg ctor 호출이
  // "Too many positional arguments: 7 expected, but 8 found" compile error
  // 를 트리거하며, 메서드 `signOutAndResetOnboarding` 미정의도 동시 노출된다.
  group('signOutAndResetOnboarding (Phase 10.2 D-A3)', () {
    test(
      'reset → signOut 순서로 5 SDK + onResetOnboarding 호출된다 '
      '(D-A3 reset → signOut 순서 + Phase 9.2 R6 5 SDK 순서 invariant)',
      () async {
        // D-A3 의 핵심: reset 이 signOut (Google SDK 첫 호출) 보다 먼저
        // 수행되어야 resolveAuthRedirect 재평가 시점에 onboardingSeen=false 가
        // 확정되어 분기 (2) 자연 redirect /onboarding 이 성립한다.
        // 순서 뒤집기 회귀 시 GC-04 fail-safe /splash churn 가능 (Pitfall 3).
        var callIndex = 0;
        var resetCallOrder = 0;
        var googleSignOutOrder = 0;

        Future<void> onResetOnboarding() async {
          resetCallOrder = ++callIndex;
        }

        // Plan 15 land — AuthRepository ctor 10-arg (9번째 YahoojpSdkClient,
        // 10번째 onResetOnboarding). Phase 12~14 의 9-arg 호출은 자동 확장.
        final repo = AuthRepository(
          mockAuth,
          mockGoogleSignIn,
          mockFacebookAuth,
          mockSocialLinkInProgress,
          mockKakaoSdkClient,
          mockFunctions,
          mockNaverSdkClient,
          mockLineSdkClient,
          mockYahoojpSdkClient,
          onResetOnboarding,
        );

        when(() => mockGoogleSignIn.signOut()).thenAnswer((_) async {
          googleSignOutOrder = ++callIndex;
        });
        when(() => mockFacebookAuth.logOut()).thenAnswer((_) async {});
        when(() => mockKakaoSdkClient.logout()).thenAnswer((_) async {});
        when(() => mockNaverSdkClient.logout()).thenAnswer((_) async {});
        when(() => mockLineSdkClient.logout()).thenAnswer((_) async {});
        when(() => mockYahoojpSdkClient.logout()).thenAnswer((_) async {});
        when(() => mockAuth.signOut()).thenAnswer((_) async {});

        await repo.signOutAndResetOnboarding();

        // D-A3 핵심: reset 이 signOut (Google SDK 첫 호출) 보다 먼저.
        expect(
          resetCallOrder,
          lessThan(googleSignOutOrder),
          reason: 'D-A3: onResetOnboarding 이 signOut 보다 먼저 호출되어야 한다',
        );

        // 7 SDK 호출 순서 invariant (Phase 14 — LINE 추가, Phase 15 — Yahoo!JP
        // 추가, signOut 본체 Phase 9.2 R6 회귀 가드 확장).
        verifyInOrder([
          () => mockGoogleSignIn.signOut(),
          () => mockFacebookAuth.logOut(),
          () => mockKakaoSdkClient.logout(),
          () => mockNaverSdkClient.logout(),
          () => mockLineSdkClient.logout(),
          () => mockYahoojpSdkClient.logout(),
          () => mockAuth.signOut(),
        ]);
      },
    );

    // Phase 10.2 review WR-01 (iter 3): _onResetOnboarding 이 throw 할 경우의
    // 계약 명문화 회귀 sentinel. 현재 production 의
    // `signOutAndResetOnboarding` 본체 (auth_repository.dart:742-745) 는
    // `await _onResetOnboarding()` → `await signOut()` 의 직선 await 만
    // 수행하므로, reset 콜백이 throw 하면 예외가 그대로 전파되고 signOut() 은
    // 실행되지 않는다. 현 OnboardingNotifier.reset() 은 lossy 정책
    // (catch + Crashlytics 기록 후 silent 흡수) 로 throw 하지 않으므로 본
    // invariant 는 today 에서 holds. 미래 reset() 에서 try/catch 가 제거되어
    // throw 가 surface 되는 회귀가 들어올 경우, 본 test 가 RED 로 surface 하여
    // (a) 계약 변경 의도 검토 + (b) `try/finally` 로 signOut 보장 변경
    // 양자택일을 강제한다.
    test('WR-01 (iter3) 회귀 sentinel: _onResetOnboarding throws → '
        '예외 전파 + signOut() 미호출 (현재 계약)', () async {
      Future<void> failingReset() async {
        throw StateError('simulated reset failure');
      }

      final repo = AuthRepository(
        mockAuth,
        mockGoogleSignIn,
        mockFacebookAuth,
        mockSocialLinkInProgress,
        mockKakaoSdkClient,
        mockFunctions,
        mockNaverSdkClient,
        mockLineSdkClient,
        mockYahoojpSdkClient,
        failingReset,
      );

      when(() => mockGoogleSignIn.signOut()).thenAnswer((_) async {});
      when(() => mockFacebookAuth.logOut()).thenAnswer((_) async {});
      when(() => mockKakaoSdkClient.logout()).thenAnswer((_) async {});
      when(() => mockNaverSdkClient.logout()).thenAnswer((_) async {});
      when(() => mockAuth.signOut()).thenAnswer((_) async {});

      await expectLater(
        repo.signOutAndResetOnboarding(),
        throwsA(isA<StateError>()),
        reason: 'reset 콜백의 예외는 호출자에게 전파되어야 한다 (현 계약)',
      );

      // 현 계약: reset 실패 시 signOut 은 실행되지 않는다 — D-A3 reset →
      // signOut 순서 invariant 의 자연 귀결. 본 contract 를 "reset 실패
      // 와 무관하게 signOut 은 항상 실행" 으로 변경하려면 try/finally
      // 도입 + 본 verifyNever 들을 verify(...).called(1) 로 갱신해야
      // 한다 (의도된 회귀 surface).
      verifyNever(() => mockGoogleSignIn.signOut());
      verifyNever(() => mockFacebookAuth.logOut());
      verifyNever(() => mockKakaoSdkClient.logout());
      verifyNever(() => mockNaverSdkClient.logout());
      verifyNever(() => mockLineSdkClient.logout());
      verifyNever(() => mockAuth.signOut());
    });
  });

  // ==========================================================================
  // Phase 14: signInWithLine (Custom Token 흐름 — Phase 12 Kakao 패턴 mirror).
  // ==========================================================================
  group('Phase 14: signInWithLine (Custom Token 흐름)', () {
    /// LINE 그룹 공통 setUp — 성공 path 의 4단계 (LineSdkClient → Cloud
    /// Function → signInWithCustomToken → User 매핑) 를 stub 한다. 각 테스트는
    /// 필요한 단계만 override 한다.
    late _MockHttpsCallable mockCallable;

    setUp(() {
      mockCallable = _MockHttpsCallable();
      // 기본: LineSdkClient 가 ID Token + nonce 반환.
      when(() => mockLineSdkClient.signIn()).thenAnswer(
        (_) async => const LineSignInResult(idToken: 'LIDT', nonce: 'LNONCE'),
      );
      // 기본: httpsCallable('lineCustomToken') → mockCallable.
      when(
        () =>
            mockFunctions.httpsCallable(any(), options: any(named: 'options')),
      ).thenReturn(mockCallable);
      // 기본: callable.call(...) → customToken 응답.
      final defaultResult = _MockHttpsCallableResult();
      when(() => defaultResult.data).thenReturn(<String, dynamic>{
        'customToken': 'LCT',
        'uid': 'line-uid',
        'isNewUser': true,
      });
      when(
        () => mockCallable.call<Map<String, dynamic>>(any()),
      ).thenAnswer((_) async => defaultResult);
      // 기본: signInWithCustomToken('LCT') → mockCredential.
      when(() => mockUser.uid).thenReturn('line-uid');
      when(() => mockUser.email).thenReturn('line@example.com');
      when(() => mockUser.providerData).thenReturn(<fb.UserInfo>[]);
      when(
        () => mockAuth.signInWithCustomToken('LCT'),
      ).thenAnswer((_) async => mockCredential);
    });

    test('Test L1 (정상): LineSdkClient → CF lineCustomToken → '
        'signInWithCustomToken → Result.success(User) + race-fix begin/end 1회 + '
        'LineSdkClient.logout 정확 1회', () async {
      final result = await repository.signInWithLine();

      expect(result, isA<Success<dynamic>>());
      final user = (result! as Success).data as User;
      expect(user.uid, 'line-uid');
      expect(user.email, 'line@example.com');

      // race-fix begin/end 1회씩.
      verify(() => mockSocialLinkInProgress.begin()).called(1);
      verify(() => mockSocialLinkInProgress.end()).called(1);
      // D-LINE-57: 성공 path 에서 SDK logout 정확 1회.
      verify(() => mockLineSdkClient.logout()).called(1);
      // CF 이름 + payload (idToken + nonce) 검증.
      verify(
        () => mockFunctions.httpsCallable(
          'lineCustomToken',
          options: any(named: 'options'),
        ),
      ).called(1);
      verify(
        () => mockCallable.call<Map<String, dynamic>>(<String, dynamic>{
          'idToken': 'LIDT',
          'nonce': 'LNONCE',
        }),
      ).called(1);
    });

    test('Test L2 (cancel): LineSdkClient → null → repository null 반환 + '
        'race-fix begin/end 1회 + logout 1회 (D-LINE-21 silent)', () async {
      when(() => mockLineSdkClient.signIn()).thenAnswer((_) async => null);

      final result = await repository.signInWithLine();

      expect(result, isNull);
      verify(() => mockSocialLinkInProgress.begin()).called(1);
      verify(() => mockSocialLinkInProgress.end()).called(1);
      // D-LINE-57 invariant: 모든 path 에서 finally logout (Phase 13 WR-01-iter2 일관).
      verify(() => mockLineSdkClient.logout()).called(1);
      // CF / Firebase Auth 미진입 검증.
      verifyNever(
        () =>
            mockFunctions.httpsCallable(any(), options: any(named: 'options')),
      );
      verifyNever(() => mockAuth.signInWithCustomToken(any()));
    });

    test('Test L3 (race-fix invariant): LineSdkClient throw 시에도 finally 가 '
        'end() + logout() 호출 (Pitfall 8 단일 진실원)', () async {
      when(() => mockLineSdkClient.signIn()).thenThrow(Exception('boom'));

      await repository.signInWithLine();

      verify(() => mockSocialLinkInProgress.begin()).called(1);
      verify(() => mockSocialLinkInProgress.end()).called(1);
      verify(() => mockLineSdkClient.logout()).called(1);
    });

    test(
      'Test L4 (Functions already-exists → AccountExistsWithDifferentCredential '
      '매핑 R3 — D-34 helper 재사용)',
      () async {
        when(() => mockCallable.call<Map<String, dynamic>>(any())).thenThrow(
          FirebaseFunctionsException(
            code: 'already-exists',
            message: 'errorAccountExistsWithDifferentCredential',
          ),
        );

        final result = await repository.signInWithLine();

        expect(result, isA<Failure<dynamic>>());
        final failure = result! as Failure;
        expect(failure.exception, isA<AccountExistsWithDifferentCredential>());
        // Cloud Function PII 미응답 — email null 보존.
        final ex = failure.exception as AccountExistsWithDifferentCredential;
        expect(ex.email, isNull);
        verify(() => mockSocialLinkInProgress.end()).called(1);
        verify(() => mockLineSdkClient.logout()).called(1);
      },
    );

    test('Test L5 (Firebase Auth exception): signInWithCustomToken throws '
        'FirebaseAuthException → _mapAuthException 매핑', () async {
      when(
        () => mockAuth.signInWithCustomToken('LCT'),
      ).thenThrow(fb.FirebaseAuthException(code: 'invalid-credential'));

      final result = await repository.signInWithLine();

      expect(result, isA<Failure<dynamic>>());
      expect((result! as Failure).exception, isA<InvalidCredentials>());
      verify(() => mockLineSdkClient.logout()).called(1);
    });

    test('Test L6 (idToken null / OIDC scope 누락 — Pitfall 1): LineSdkClient 가 '
        'ServiceUnavailable throw 시 그대로 Failure 재패키징', () async {
      when(
        () => mockLineSdkClient.signIn(),
      ).thenThrow(const ServiceUnavailable());

      final result = await repository.signInWithLine();

      expect(result, isA<Failure<dynamic>>());
      expect((result! as Failure).exception, isA<ServiceUnavailable>());
      verify(() => mockSocialLinkInProgress.end()).called(1);
      verify(() => mockLineSdkClient.logout()).called(1);
    });
  });

  // ==========================================================================
  // Phase 15: signInWithYahoojp (Custom Token 흐름 — Phase 14 LINE 패턴 mirror).
  // ==========================================================================
  group('Phase 15: signInWithYahoojp (Custom Token 흐름)', () {
    /// Yahoo!JP 그룹 공통 setUp — 성공 path 의 4단계 (YahoojpSdkClient → Cloud
    /// Function → signInWithCustomToken → User 매핑) 를 stub 한다. 각
    /// 테스트는 필요한 단계만 override 한다.
    late _MockHttpsCallable mockCallable;

    setUp(() {
      mockCallable = _MockHttpsCallable();
      // 기본: YahoojpSdkClient 가 ID Token + nonce 반환.
      when(() => mockYahoojpSdkClient.signIn()).thenAnswer(
        (_) async =>
            const YahoojpSignInResult(idToken: 'YJIDT', nonce: 'YJNONCE'),
      );
      // 기본: httpsCallable('yahoojpCustomToken') → mockCallable.
      when(
        () =>
            mockFunctions.httpsCallable(any(), options: any(named: 'options')),
      ).thenReturn(mockCallable);
      // 기본: callable.call(...) → customToken 응답.
      final defaultResult = _MockHttpsCallableResult();
      when(() => defaultResult.data).thenReturn(<String, dynamic>{
        'customToken': 'YJCT',
        'uid': 'yj-uid',
        'isNewUser': true,
      });
      when(
        () => mockCallable.call<Map<String, dynamic>>(any()),
      ).thenAnswer((_) async => defaultResult);
      // 기본: signInWithCustomToken('YJCT') → mockCredential.
      when(() => mockUser.uid).thenReturn('yj-uid');
      // D-YJP-09 정정 lock — scope openid+profile 만 → email 빈 문자열
      // (LINE D-LINE-21 와 동일 mechanism).
      when(() => mockUser.email).thenReturn('');
      when(() => mockUser.providerData).thenReturn(<fb.UserInfo>[]);
      when(
        () => mockAuth.signInWithCustomToken('YJCT'),
      ).thenAnswer((_) async => mockCredential);
    });

    test('Test YJ1 (정상): YahoojpSdkClient → CF yahoojpCustomToken → '
        'signInWithCustomToken → Result.success(User) + race-fix begin/end 1회 '
        '+ YahoojpSdkClient.logout 정확 1회', () async {
      final result = await repository.signInWithYahoojp();

      expect(result, isA<Success<dynamic>>());
      final user = (result! as Success).data as User;
      expect(user.uid, 'yj-uid');
      // D-YJP-09: email 빈 문자열 — _autoSendEmailVerification 자연 no-op.
      expect(user.email, '');

      // race-fix begin/end 1회씩.
      verify(() => mockSocialLinkInProgress.begin()).called(1);
      verify(() => mockSocialLinkInProgress.end()).called(1);
      // D-YJP-08: 성공 path 에서 SDK logout 정확 1회.
      verify(() => mockYahoojpSdkClient.logout()).called(1);
      // CF 이름 + payload (idToken + nonce) 검증.
      verify(
        () => mockFunctions.httpsCallable(
          'yahoojpCustomToken',
          options: any(named: 'options'),
        ),
      ).called(1);
      verify(
        () => mockCallable.call<Map<String, dynamic>>(<String, dynamic>{
          'idToken': 'YJIDT',
          'nonce': 'YJNONCE',
        }),
      ).called(1);
    });

    test('Test YJ2 (cancel): YahoojpSdkClient → null → repository null 반환 + '
        'race-fix begin/end 1회 + logout 1회 (D-YJP-09 silent)', () async {
      when(() => mockYahoojpSdkClient.signIn()).thenAnswer((_) async => null);

      final result = await repository.signInWithYahoojp();

      expect(result, isNull);
      verify(() => mockSocialLinkInProgress.begin()).called(1);
      verify(() => mockSocialLinkInProgress.end()).called(1);
      // D-YJP-08 invariant: 모든 path 에서 finally logout
      // (Phase 14 D-LINE-57 mirror).
      verify(() => mockYahoojpSdkClient.logout()).called(1);
      // CF / Firebase Auth 미진입 검증.
      verifyNever(
        () =>
            mockFunctions.httpsCallable(any(), options: any(named: 'options')),
      );
      verifyNever(() => mockAuth.signInWithCustomToken(any()));
    });

    test('Test YJ3 (race-fix invariant): YahoojpSdkClient throw 시에도 finally '
        '가 end() + logout() 호출 (Pitfall 8 단일 진실원)', () async {
      when(() => mockYahoojpSdkClient.signIn()).thenThrow(Exception('boom'));

      await repository.signInWithYahoojp();

      verify(() => mockSocialLinkInProgress.begin()).called(1);
      verify(() => mockSocialLinkInProgress.end()).called(1);
      verify(() => mockYahoojpSdkClient.logout()).called(1);
    });

    test(
      'Test YJ4 (Functions already-exists → AccountExistsWithDifferentCredential '
      '매핑 — D-34 helper 재사용)',
      () async {
        when(() => mockCallable.call<Map<String, dynamic>>(any())).thenThrow(
          FirebaseFunctionsException(
            code: 'already-exists',
            message: 'errorAccountExistsWithDifferentCredential',
          ),
        );

        final result = await repository.signInWithYahoojp();

        expect(result, isA<Failure<dynamic>>());
        final failure = result! as Failure;
        expect(failure.exception, isA<AccountExistsWithDifferentCredential>());
        // Cloud Function PII 미응답 — email null 보존.
        final ex = failure.exception as AccountExistsWithDifferentCredential;
        expect(ex.email, isNull);
        verify(() => mockSocialLinkInProgress.end()).called(1);
        verify(() => mockYahoojpSdkClient.logout()).called(1);
      },
    );

    test('Test YJ5 (Firebase Auth exception): signInWithCustomToken throws '
        'FirebaseAuthException → _mapAuthException 매핑', () async {
      when(
        () => mockAuth.signInWithCustomToken('YJCT'),
      ).thenThrow(fb.FirebaseAuthException(code: 'invalid-credential'));

      final result = await repository.signInWithYahoojp();

      expect(result, isA<Failure<dynamic>>());
      expect((result! as Failure).exception, isA<InvalidCredentials>());
      verify(() => mockYahoojpSdkClient.logout()).called(1);
    });

    test(
      'Test YJ6 (idToken null / clientId empty — Pitfall 1 / T-15-15): '
      'YahoojpSdkClient 가 ServiceUnavailable throw 시 그대로 Failure 재패키징',
      () async {
        when(
          () => mockYahoojpSdkClient.signIn(),
        ).thenThrow(const ServiceUnavailable());

        final result = await repository.signInWithYahoojp();

        expect(result, isA<Failure<dynamic>>());
        expect((result! as Failure).exception, isA<ServiceUnavailable>());
        verify(() => mockSocialLinkInProgress.end()).called(1);
        verify(() => mockYahoojpSdkClient.logout()).called(1);
      },
    );
  });
}
