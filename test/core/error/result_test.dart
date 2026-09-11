import 'dart:io';

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
      expect((result as Failure<String>).exception, isA<ConnectionTimeout>());
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
          // IN-05: UnknownException 은 AppException 직속 leaf 이므로
          // 별도 arm 이 필요하다 (캐치올을 서버 장애로 뭉개지 않는다).
          UnknownException() => 'unknown error',
        },
      };

      expect(message, equals('network error'));
    });
  });

  group('WR-08: result.dart 문서 예시가 실제로 컴파일된다', () {
    // 이 저장소의 존재 이유는 "복사해서 바로 쓰는 보일러플레이트" 다.
    // 수정 전 doc 예시는 `Result.failure(ServerException(...))` 이었는데
    // ServerException 은 sealed = 암묵적 abstract 라 인스턴스화할 수 없다.
    // 붙여 넣는 순간 analyzer 에러가 나는 레퍼런스였다.
    //
    // 아래 함수는 doc 예시와 **같은 모양** 이며, 컴파일된다는 사실 자체가
    // 계약이다. doc 을 다시 sealed 상위 타입으로 되돌리면 여기서도 깨진다.
    Result<String> fetchUserLike({required bool shouldFail}) {
      try {
        if (shouldFail) {
          throw Exception('upstream failure');
        }
        return const Result<String>.success('user');
      } on Exception catch (e) {
        // sealed 상위 타입이 아니라 구체 하위 타입.
        return Result<String>.failure(InternalServerError(cause: e));
      }
    }

    test('성공 경로는 Success 를 반환한다', () {
      final result = fetchUserLike(shouldFail: false);
      final output = switch (result) {
        Success(data: final user) => 'success: $user',
        Failure(exception: final ex) => 'failure: ${ex.userMessage}',
      };
      expect(output, 'success: user');
    });

    test('실패 경로는 구체 하위 타입을 담은 Failure 를 반환한다', () {
      final result = fetchUserLike(shouldFail: true);
      expect(result, isA<Failure<String>>());
      final failure = result as Failure<String>;
      expect(failure.exception, isA<InternalServerError>());
      expect(failure.exception, isA<ServerException>());
      expect(failure.exception.cause, isA<Exception>());
    });

    test('문서 예시가 구체 하위 타입을 쓰도록 유지된다 (소스 계약)', () async {
      final source = await File('lib/core/error/result.dart').readAsString();
      // doc 예시가 sealed 상위 타입을 생성자 호출하면 안 된다.
      expect(
        RegExp(r'Result\.failure\(ServerException\(').hasMatch(source),
        isFalse,
        reason: 'WR-08: sealed 상위 타입은 인스턴스화할 수 없다',
      );
      expect(
        source.contains('Result.failure(InternalServerError(cause: e))'),
        isTrue,
        reason: 'WR-08: doc 예시는 구체 하위 타입을 사용해야 한다',
      );
    });
  });

  group('IN-01: Phase 02 core 파일의 import 스타일', () {
    // .claude/rules/flutter.md — "relative import 사용 (같은 패키지 내)".
    // 리뷰가 지적한 result.dart 를 포함해, 같은 리뷰 범위의 core 디렉터리
    // 전체를 한 번에 잠근다.
    const reviewedDirs = <String>[
      'lib/core/analytics',
      'lib/core/config',
      'lib/core/crashlytics',
      'lib/core/error',
      'lib/core/providers',
    ];

    for (final dir in reviewedDirs) {
      test('$dir 은 자기 패키지를 absolute package: 로 import 하지 않는다', () {
        final files = Directory(dir)
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .where((f) => !f.path.endsWith('.g.dart'));

        final offenders = <String>[];
        for (final file in files) {
          final source = file.readAsStringSync();
          if (RegExp(
            r"^import 'package:flutter_starter_kit/",
            multiLine: true,
          ).hasMatch(source)) {
            offenders.add(file.path);
          }
        }

        expect(
          offenders,
          isEmpty,
          reason:
              '.claude/rules/flutter.md: 같은 패키지 내에서는 relative import 를 '
              '사용한다. 위반 파일: $offenders',
        );
      });
    }
  });
}
