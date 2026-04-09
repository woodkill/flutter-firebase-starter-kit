import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';

void main() {
  final now = DateTime(2026, 4, 5, 12, 0);

  group('User 모델', () {
    test('필수 필드로 생성하고 접근할 수 있다', () {
      final user = User(
        uid: 'uid-123',
        email: 'test@example.com',
        emailVerified: true,
        createdAt: now,
      );

      expect(user.uid, 'uid-123');
      expect(user.email, 'test@example.com');
      expect(user.emailVerified, isTrue);
      expect(user.displayName, isNull);
      expect(user.photoUrl, isNull);
      expect(user.createdAt, now);
    });

    test('providerIds 기본값은 빈 리스트이다', () {
      final user = User(
        uid: 'uid-123',
        email: 'test@example.com',
        emailVerified: true,
        createdAt: now,
      );

      expect(user.providerIds, isEmpty);
      expect(user.providerIds, isA<List<String>>());
    });

    test('providerIds를 명시적으로 설정할 수 있다', () {
      final user = User(
        uid: 'uid-123',
        email: 'test@example.com',
        emailVerified: true,
        createdAt: now,
        providerIds: ['google.com', 'password'],
      );

      expect(user.providerIds, ['google.com', 'password']);
    });

    test('모든 필드로 생성할 수 있다', () {
      final user = User(
        uid: 'uid-456',
        email: 'full@example.com',
        emailVerified: true,
        displayName: 'Test User',
        photoUrl: 'https://example.com/photo.jpg',
        createdAt: now,
        providerIds: ['google.com'],
      );

      expect(user.uid, 'uid-456');
      expect(user.email, 'full@example.com');
      expect(user.displayName, 'Test User');
      expect(user.photoUrl, 'https://example.com/photo.jpg');
      expect(user.providerIds, ['google.com']);
    });

    test('copyWith로 일부 필드를 변경한 새 객체를 생성할 수 있다', () {
      final user = User(
        uid: 'uid-123',
        email: 'test@example.com',
        emailVerified: true,
        createdAt: now,
      );

      final updated = user.copyWith(displayName: 'Updated Name');

      expect(updated.uid, 'uid-123');
      expect(updated.email, 'test@example.com');
      expect(updated.displayName, 'Updated Name');
      expect(updated.createdAt, now);
      // 원본은 변경되지 않는다.
      expect(user.displayName, isNull);
    });

    test('같은 값을 가진 두 객체는 동등하다', () {
      final user1 = User(
        uid: 'uid-123',
        email: 'test@example.com',
        emailVerified: true,
        createdAt: now,
      );
      final user2 = User(
        uid: 'uid-123',
        email: 'test@example.com',
        emailVerified: true,
        createdAt: now,
      );

      expect(user1, equals(user2));
      expect(user1.hashCode, equals(user2.hashCode));
    });

    test('다른 값을 가진 두 객체는 동등하지 않다', () {
      final user1 = User(
        uid: 'uid-123',
        email: 'test@example.com',
        emailVerified: true,
        createdAt: now,
      );
      final user2 = User(
        uid: 'uid-456',
        email: 'other@example.com',
        emailVerified: true,
        createdAt: now,
      );

      expect(user1, isNot(equals(user2)));
    });

    group('JSON 직렬화', () {
      test('toJson/fromJson 라운드트립이 동작한다', () {
        final user = User(
          uid: 'uid-123',
          email: 'test@example.com',
          emailVerified: true,
          displayName: 'Test User',
          photoUrl: 'https://example.com/photo.jpg',
          createdAt: now,
          providerIds: ['google.com', 'password'],
        );

        final json = user.toJson();
        final restored = User.fromJson(json);

        expect(restored, equals(user));
      });

      test('toJson이 올바른 키-값 쌍을 반환한다', () {
        final user = User(
          uid: 'uid-123',
          email: 'test@example.com',
          emailVerified: true,
          createdAt: now,
        );

        final json = user.toJson();

        expect(json['uid'], 'uid-123');
        expect(json['email'], 'test@example.com');
        expect(json['displayName'], isNull);
        expect(json['photoUrl'], isNull);
        expect(json['createdAt'], isNotNull);
        expect(json['providerIds'], isEmpty);
      });

      test('fromJson에서 providerIds를 올바르게 파싱한다', () {
        final json = <String, dynamic>{
          'uid': 'uid-provider',
          'email': 'provider@example.com',
          'emailVerified': true,
          'createdAt': '2026-04-05T12:00:00.000',
          'providerIds': ['google.com'],
        };

        final user = User.fromJson(json);

        expect(user.providerIds, ['google.com']);
      });

      test('fromJson에서 DateTime을 올바르게 파싱한다', () {
        final json = <String, dynamic>{
          'uid': 'uid-789',
          'email': 'datetime@example.com',
          'emailVerified': true,
          'createdAt': '2026-04-05T12:00:00.000',
          'displayName': null,
          'photoUrl': null,
        };

        final user = User.fromJson(json);

        expect(user.uid, 'uid-789');
        expect(user.createdAt.year, 2026);
        expect(user.createdAt.month, 4);
        expect(user.createdAt.day, 5);
        expect(user.createdAt.hour, 12);
      });

      test('nullable 필드가 없는 JSON에서도 fromJson이 동작한다', () {
        final json = <String, dynamic>{
          'uid': 'uid-minimal',
          'email': 'minimal@example.com',
          'emailVerified': true,
          'createdAt': '2026-01-01T00:00:00.000',
        };

        final user = User.fromJson(json);

        expect(user.uid, 'uid-minimal');
        expect(user.displayName, isNull);
        expect(user.photoUrl, isNull);
        // providerIds가 없는 JSON에서도 기본값 빈 리스트로 동작한다.
        expect(user.providerIds, isEmpty);
      });
    });
  });

  group('AccountExistsWithDifferentCredential', () {
    test('인스턴스 생성 시 email 필드에 접근할 수 있다', () {
      const exception = AccountExistsWithDifferentCredential(
        email: 'test@example.com',
      );

      expect(exception.email, 'test@example.com');
    });

    test('userMessage가 올바른 ARB 키를 반환한다', () {
      const exception = AccountExistsWithDifferentCredential();

      expect(
        exception.userMessage,
        'errorAccountExistsWithDifferentCredential',
      );
    });

    test('email이 null일 수 있다', () {
      const exception = AccountExistsWithDifferentCredential();

      expect(exception.email, isNull);
    });

    test('AuthException을 상속한다', () {
      const exception = AccountExistsWithDifferentCredential();

      expect(exception, isA<AuthException>());
      expect(exception, isA<AppException>());
    });

    test('cause를 전달할 수 있다', () {
      final cause = Exception('original');
      final exception = AccountExistsWithDifferentCredential(
        email: 'a@b.com',
        cause: cause,
      );

      expect(exception.cause, cause);
    });
  });
}
