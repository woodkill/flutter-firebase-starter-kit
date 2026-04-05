import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppException sealed class 계층', () {
    // Test 1: AppException은 sealed class (직접 인스턴스화 불가)
    // -> sealed class는 컴파일 타임에 강제되므로, subclass만 인스턴스화 가능함을 검증
    test('AppException의 subclass만 인스턴스화 가능', () {
      // NetworkException, AuthException, ServerException만 생성 가능
      const AppException networkEx = ConnectionTimeout();
      const AppException authEx = InvalidCredentials();
      const AppException serverEx = InternalServerError();

      expect(networkEx, isA<AppException>());
      expect(authEx, isA<AppException>());
      expect(serverEx, isA<AppException>());
    });

    // Test 2: NetworkException의 모든 구체 subclass에 userMessage 필드 존재
    test('NetworkException subclass에 빈 문자열이 아닌 userMessage 존재', () {
      const exceptions = <NetworkException>[
        ConnectionTimeout(),
        NoInternetConnection(),
        RequestTimeout(),
      ];

      for (final ex in exceptions) {
        expect(ex.userMessage, isNotEmpty, reason: '${ex.runtimeType}');
        expect(ex, isA<AppException>());
      }
    });

    // Test 3: AuthException의 모든 구체 subclass에 userMessage 필드 존재
    test('AuthException subclass에 userMessage 존재', () {
      const exceptions = <AuthException>[
        InvalidCredentials(),
        UserNotFound(),
        EmailAlreadyInUse(),
        WeakPassword(),
        SessionExpired(),
      ];

      for (final ex in exceptions) {
        expect(ex.userMessage, isNotEmpty, reason: '${ex.runtimeType}');
        expect(ex, isA<AppException>());
      }
    });

    // Test 4: ServerException의 모든 구체 subclass에 userMessage 필드 존재
    test('ServerException subclass에 userMessage 존재', () {
      const exceptions = <ServerException>[
        InternalServerError(),
        ServiceUnavailable(),
      ];

      for (final ex in exceptions) {
        expect(ex.userMessage, isNotEmpty, reason: '${ex.runtimeType}');
        expect(ex, isA<AppException>());
      }
    });

    // Test 5: AppException에 대한 switch 문이 exhaustive
    test('AppException switch 문이 exhaustive하게 동작', () {
      const AppException exception = ConnectionTimeout();

      // sealed class이므로 3개 분기로 exhaustive switch 가능
      final result = switch (exception) {
        NetworkException() => 'network',
        AuthException() => 'auth',
        ServerException() => 'server',
      };

      expect(result, equals('network'));
    });

    // Test 6: cause 파라미터가 optional이며 원본 예외를 보존
    test('cause 파라미터가 optional이며 원본 예외를 보존', () {
      // cause 없이 생성
      const noCause = ConnectionTimeout();
      expect(noCause.cause, isNull);

      // cause와 함께 생성
      final originalError = Exception('원본 에러');
      final withCause = ConnectionTimeout(cause: originalError);
      expect(withCause.cause, equals(originalError));
      expect(withCause.cause, isA<Exception>());
    });

    // 보안 위협 T-02-01 대응: userMessage에 기술 상세 미포함
    test('userMessage에 기술 상세 정보가 포함되지 않음', () {
      const allExceptions = <AppException>[
        ConnectionTimeout(),
        NoInternetConnection(),
        RequestTimeout(),
        InvalidCredentials(),
        UserNotFound(),
        EmailAlreadyInUse(),
        WeakPassword(),
        SessionExpired(),
        InternalServerError(),
        ServiceUnavailable(),
      ];

      for (final ex in allExceptions) {
        // 스택 트레이스, 내부 에러 코드, DB 쿼리 등이 포함되지 않아야 함
        expect(
          ex.userMessage,
          isNot(contains('stack')),
          reason: '${ex.runtimeType} userMessage에 stack 정보 포함',
        );
        expect(
          ex.userMessage,
          isNot(contains('trace')),
          reason: '${ex.runtimeType} userMessage에 trace 정보 포함',
        );
        expect(
          ex.userMessage,
          isNot(contains('query')),
          reason: '${ex.runtimeType} userMessage에 query 정보 포함',
        );
        expect(
          ex.userMessage,
          isNot(contains('SELECT')),
          reason: '${ex.runtimeType} userMessage에 SQL 정보 포함',
        );
      }
    });
  });
}
