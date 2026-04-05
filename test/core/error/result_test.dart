import 'package:flutter_starter_kit/core/error/app_exception.dart';
import 'package:flutter_starter_kit/core/error/result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Result<T> sealed class', () {
    // Test 1: Result.success(42)가 Success<int> 타입이고 data가 42
    test('Result.success()가 Success 타입이고 data가 올바름', () {
      const result = Result<int>.success(42);

      expect(result, isA<Success<int>>());
      expect((result as Success<int>).data, equals(42));
    });

    // Test 2: Result.failure()가 Failure 타입이고 exception이 올바름
    test('Result.failure()가 Failure 타입이고 exception이 올바름', () {
      const result = Result<String>.failure(ConnectionTimeout());

      expect(result, isA<Failure<String>>());
      expect(
        (result as Failure<String>).exception,
        isA<ConnectionTimeout>(),
      );
    });

    // Test 3: Result<String>에 대한 switch 문이 exhaustive
    test('Result switch 문이 Success/Failure 2개 분기로 exhaustive', () {
      const Result<String> result = Result.success('hello');

      // sealed class이므로 2개 분기로 exhaustive switch 가능
      final output = switch (result) {
        Success(data: final value) => 'success: $value',
        Failure(exception: final ex) => 'failure: ${ex.userMessage}',
      };

      expect(output, equals('success: hello'));
    });

    // Test 4: Success의 data 타입이 제네릭 T와 일치
    test('Success의 data 타입이 제네릭 T와 일치', () {
      const intResult = Result<int>.success(100);
      const stringResult = Result<String>.success('text');
      const listResult = Result<List<int>>.success([1, 2, 3]);

      expect(intResult, isA<Success<int>>());
      expect((intResult as Success<int>).data, isA<int>());

      expect(stringResult, isA<Success<String>>());
      expect((stringResult as Success<String>).data, isA<String>());

      expect(listResult, isA<Success<List<int>>>());
      expect((listResult as Success<List<int>>).data, isA<List<int>>());
    });

    // Test 5: Failure의 exception 타입이 AppException
    test('Failure의 exception 타입이 AppException으로 제한', () {
      const result = Result<int>.failure(SessionExpired());

      final failure = result as Failure<int>;
      expect(failure.exception, isA<AppException>());

      // AppException의 하위 타입들도 허용
      expect(failure.exception, isA<AuthException>());
      expect(failure.exception, isA<SessionExpired>());
    });

    // Test 6: named constructor factory가 동작
    test('Result.success / Result.failure named constructor가 동작', () {
      const success = Result<double>.success(3.14);
      const failure = Result<double>.failure(InternalServerError());

      expect(success, isA<Success<double>>());
      expect(failure, isA<Failure<double>>());
    });

    // Failure switch 문에서 exception의 도메인별 분기도 가능
    test('Failure의 exception에서 도메인별 세부 분기 가능', () {
      const Result<String> result = Result.failure(NoInternetConnection());

      final message = switch (result) {
        Success(data: final value) => value,
        Failure(exception: final ex) => switch (ex) {
          NetworkException() => 'network error',
          AuthException() => 'auth error',
          ServerException() => 'server error',
        },
      };

      expect(message, equals('network error'));
    });
  });
}
