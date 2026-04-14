import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockUserCredential extends Mock implements fb.UserCredential {}

class _MockFbUser extends Mock implements fb.User {}

class _MockUserMetadata extends Mock implements fb.UserMetadata {}

class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

class _MockFacebookAuth extends Mock implements FacebookAuth {}

void main() {
  late _MockFirebaseAuth mockAuth;
  late _MockUserCredential mockCredential;
  late _MockFbUser mockUser;
  late _MockUserMetadata mockMetadata;
  late _MockGoogleSignIn mockGoogleSignIn;
  late _MockFacebookAuth mockFacebookAuth;
  late AuthRepository repository;

  setUp(() {
    mockAuth = _MockFirebaseAuth();
    mockCredential = _MockUserCredential();
    mockUser = _MockFbUser();
    mockMetadata = _MockUserMetadata();
    mockGoogleSignIn = _MockGoogleSignIn();
    mockFacebookAuth = _MockFacebookAuth();
    repository = AuthRepository(mockAuth, mockGoogleSignIn, mockFacebookAuth);

    // 익명 사용자 기본 stub — uid 만 있고 email 은 빈 값, emailVerified=false.
    when(() => mockUser.uid).thenReturn('anon-uid');
    when(() => mockUser.email).thenReturn(null);
    when(() => mockUser.emailVerified).thenReturn(false);
    when(() => mockUser.displayName).thenReturn(null);
    when(() => mockUser.photoURL).thenReturn(null);
    when(() => mockUser.metadata).thenReturn(mockMetadata);
    when(
      () => mockMetadata.creationTime,
    ).thenReturn(DateTime.utc(2026, 4, 14));
    when(() => mockUser.providerData).thenReturn([]);
    when(() => mockCredential.user).thenReturn(mockUser);
  });

  group('AuthRepository.signInAnonymously', () {
    test('성공 시 Result.success(User) 를 반환한다', () async {
      when(
        () => mockAuth.signInAnonymously(),
      ).thenAnswer((_) async => mockCredential);

      final result = await repository.signInAnonymously();

      expect(result, isA<Success<dynamic>>());
      final user = (result as Success).data;
      expect(user.uid, 'anon-uid');
      expect(user.email, '');
      expect(user.emailVerified, isFalse);
      expect(user.providerIds, isEmpty);
      verify(() => mockAuth.signInAnonymously()).called(1);
    });

    test('UserCredential.user 가 null 이면 ServiceUnavailable 을 반환한다',
        () async {
      when(() => mockCredential.user).thenReturn(null);
      when(
        () => mockAuth.signInAnonymously(),
      ).thenAnswer((_) async => mockCredential);

      final result = await repository.signInAnonymously();

      expect(result, isA<Failure<dynamic>>());
      expect((result as Failure).exception, isA<ServiceUnavailable>());
    });

    test('operation-not-allowed → ServiceUnavailable 매핑 (A4 위험)',
        () async {
      when(() => mockAuth.signInAnonymously()).thenThrow(
        fb.FirebaseAuthException(code: 'operation-not-allowed'),
      );

      final result = await repository.signInAnonymously();

      expect(result, isA<Failure<dynamic>>());
      expect((result as Failure).exception, isA<ServiceUnavailable>());
    });

    test('network-request-failed → NoInternetConnection 매핑 (Pitfall 3)',
        () async {
      when(() => mockAuth.signInAnonymously()).thenThrow(
        fb.FirebaseAuthException(code: 'network-request-failed'),
      );

      final result = await repository.signInAnonymously();

      expect(result, isA<Failure<dynamic>>());
      expect((result as Failure).exception, isA<NoInternetConnection>());
    });

    test('기타 FirebaseAuthException → ServiceUnavailable 매핑 (fallback)',
        () async {
      when(() => mockAuth.signInAnonymously()).thenThrow(
        fb.FirebaseAuthException(code: 'some-unknown-code'),
      );

      final result = await repository.signInAnonymously();

      expect(result, isA<Failure<dynamic>>());
      expect((result as Failure).exception, isA<ServiceUnavailable>());
    });

    test('비-Auth Object 예외 → ServiceUnavailable 매핑', () async {
      when(
        () => mockAuth.signInAnonymously(),
      ).thenThrow(Exception('platform crash'));

      final result = await repository.signInAnonymously();

      expect(result, isA<Failure<dynamic>>());
      expect((result as Failure).exception, isA<ServiceUnavailable>());
    });
  });

  group('AuthRepository.signOutAndContinueAsGuest', () {
    test('signOut 후 signInAnonymously 를 호출하여 새 익명 User 를 반환한다',
        () async {
      when(() => mockGoogleSignIn.signOut()).thenAnswer((_) async {});
      when(() => mockFacebookAuth.logOut()).thenAnswer((_) async {});
      when(() => mockAuth.signOut()).thenAnswer((_) async {});
      when(
        () => mockAuth.signInAnonymously(),
      ).thenAnswer((_) async => mockCredential);

      final result = await repository.signOutAndContinueAsGuest();

      expect(result, isA<Success<dynamic>>());
      final user = (result as Success).data;
      expect(user.uid, 'anon-uid');

      // 호출 순서 검증: Google signOut → Facebook logOut →
      // FirebaseAuth signOut → signInAnonymously.
      verifyInOrder([
        () => mockGoogleSignIn.signOut(),
        () => mockFacebookAuth.logOut(),
        () => mockAuth.signOut(),
        () => mockAuth.signInAnonymously(),
      ]);
    });

    test(
      'signOut 은 성공했지만 signInAnonymously 가 네트워크 오류로 실패 시 '
      'Result.failure(NoInternetConnection) 반환 (signOut 은 이미 수행)',
      () async {
        when(() => mockGoogleSignIn.signOut()).thenAnswer((_) async {});
        when(() => mockFacebookAuth.logOut()).thenAnswer((_) async {});
        when(() => mockAuth.signOut()).thenAnswer((_) async {});
        when(() => mockAuth.signInAnonymously()).thenThrow(
          fb.FirebaseAuthException(code: 'network-request-failed'),
        );

        final result = await repository.signOutAndContinueAsGuest();

        expect(result, isA<Failure<dynamic>>());
        expect((result as Failure).exception, isA<NoInternetConnection>());
        // FirebaseAuth.signOut 은 실제로 호출되었음을 확인.
        verify(() => mockAuth.signOut()).called(1);
        verify(() => mockAuth.signInAnonymously()).called(1);
      },
    );

    test(
      'GoogleSignIn.signOut 실패해도 FirebaseAuth.signOut 및 '
      'signInAnonymously 는 계속 진행된다 (기존 signOut 패턴 준수)',
      () async {
        when(
          () => mockGoogleSignIn.signOut(),
        ).thenThrow(Exception('google signOut failed'));
        when(() => mockFacebookAuth.logOut()).thenAnswer((_) async {});
        when(() => mockAuth.signOut()).thenAnswer((_) async {});
        when(
          () => mockAuth.signInAnonymously(),
        ).thenAnswer((_) async => mockCredential);

        final result = await repository.signOutAndContinueAsGuest();

        expect(result, isA<Success<dynamic>>());
        verify(() => mockGoogleSignIn.signOut()).called(1);
        verify(() => mockAuth.signOut()).called(1);
        verify(() => mockAuth.signInAnonymously()).called(1);
      },
    );
  });
}
