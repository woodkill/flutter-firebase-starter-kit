import 'app_exception.dart';

/// 성공 또는 실패를 나타내는 sealed 결과 타입.
///
/// Repository 계층의 반환값으로만 사용한다 (D-05).
/// Presentation 계층에서는 Riverpod [AsyncValue]를 사용하고,
/// Provider에서 [Result] -> [AsyncValue] 변환을 수행한다.
///
/// ```dart
/// // Repository 사용 예시
/// Future<Result<User>> fetchUser(String uid) async {
///   try {
///     final user = await dataSource.getUser(uid);
///     return Result.success(user);
///   } on FirebaseException catch (e) {
///     // sealed 상위 타입([ServerException])이 아니라 구체 하위 타입을
///     // 넘긴다 — Dart 3 의 sealed class 는 암묵적 abstract 라
///     // 인스턴스화할 수 없다 (코드 리뷰 WR-08).
///     return Result.failure(InternalServerError(cause: e));
///   }
/// }
///
/// // switch 패턴 매칭
/// final result = await repository.fetchUser(uid);
/// switch (result) {
///   case Success(data: final user):
///     // 성공 처리
///   case Failure(exception: final ex):
///     // 실패 처리
/// }
/// ```
sealed class Result<T> {
  /// [Result]의 기본 생성자.
  const Result();

  /// 성공 결과를 생성한다.
  const factory Result.success(T data) = Success<T>;

  /// 실패 결과를 생성한다.
  ///
  /// [exception]은 [AppException] 타입으로 제한된다 (D-04).
  const factory Result.failure(AppException exception) = Failure<T>;
}

/// 성공 결과.
///
/// [data]에 반환된 데이터를 포함한다.
final class Success<T> extends Result<T> {
  /// [Success]를 생성한다.
  const Success(this.data);

  /// 반환된 데이터.
  final T data;
}

/// 실패 결과.
///
/// [exception]에 발생한 예외를 포함한다.
/// [AppException] 타입으로 제한되어 일반 [Exception]은 허용하지 않는다 (D-04).
final class Failure<T> extends Result<T> {
  /// [Failure]를 생성한다.
  const Failure(this.exception);

  /// 발생한 예외. [AppException] 타입으로 제한된다 (D-04).
  final AppException exception;
}
