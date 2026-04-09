import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';

class _MockFirebaseAuth extends Mock implements fb.FirebaseAuth {}

class _MockUserCredential extends Mock implements fb.UserCredential {}

class _MockFbUser extends Mock implements fb.User {}

class _MockUserMetadata extends Mock implements fb.UserMetadata {}

void main() {
  late _MockFirebaseAuth mockAuth;
  late _MockUserCredential mockCredential;
  late _MockFbUser mockUser;
  late _MockUserMetadata mockMetadata;
  late AuthRepository repository;

  setUp(() {
    mockAuth = _MockFirebaseAuth();
    mockCredential = _MockUserCredential();
    mockUser = _MockFbUser();
    mockMetadata = _MockUserMetadata();
    repository = AuthRepository(mockAuth);

    // 기본 User 필드 stub
    when(() => mockUser.uid).thenReturn('uid-test');
    when(() => mockUser.email).thenReturn('test@example.com');
    when(() => mockUser.emailVerified).thenReturn(true);
    when(() => mockUser.displayName).thenReturn('Test');
    when(() => mockUser.photoURL).thenReturn(null);
    when(() => mockUser.metadata).thenReturn(mockMetadata);
    when(() => mockMetadata.creationTime).thenReturn(DateTime.utc(2026, 1, 1));
    when(() => mockCredential.user).thenReturn(mockUser);
  });

  group('_mapFirebaseUser via signInWithEmail (BLOCKER #1 통합 검증)', () {
    test('모든 필드가 채워진 fb.User 가 도메인 User 로 매핑된다', () async {
      when(() => mockUser.uid).thenReturn('uid-full');
      when(() => mockUser.email).thenReturn('full@example.com');
      when(() => mockUser.emailVerified).thenReturn(true);
      when(() => mockUser.displayName).thenReturn('Full User');
      when(
        () => mockUser.photoURL,
      ).thenReturn('https://example.com/photo.png');
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

    test('FirebaseAuthException invalid-email 시 InvalidEmail Failure', () async {
      when(
        () => mockAuth.sendPasswordResetEmail(email: any(named: 'email')),
      ).thenThrow(fb.FirebaseAuthException(code: 'invalid-email'));

      final result = await repository.sendPasswordReset(email: 'bad');

      expect(result, isA<Failure<dynamic>>());
      expect((result as Failure).exception, isA<InvalidEmail>());
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
      expect(
        await mapViaSignIn('wrong-password'),
        isA<InvalidCredentials>(),
      );
    });
    test('user-not-found → InvalidCredentials', () async {
      expect(
        await mapViaSignIn('user-not-found'),
        isA<InvalidCredentials>(),
      );
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
      expect(
        await mapViaSignIn('too-many-requests'),
        isA<TooManyRequests>(),
      );
    });
    test(
      'operation-not-allowed → ServiceUnavailable '
      '(Firebase Console 인증 방식 비활성 설정 오류)',
      () async {
        // 회귀 방지: dev Firebase Console에서 Email/Password 가입이 꺼져 있을 때
        // 던져지는 코드를 명시적으로 매핑한다. fallback과 동일한 결과지만,
        // 의도가 코드에 드러나며 향후 다른 매핑으로 분리할 여지를 남긴다.
        expect(
          await mapViaSignIn('operation-not-allowed'),
          isA<ServiceUnavailable>(),
        );
      },
    );
    test('알 수 없는 코드 → ServiceUnavailable (fallback)', () async {
      expect(
        await mapViaSignIn('some-unknown-code'),
        isA<ServiceUnavailable>(),
      );
    });
  });
}
