import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../crashlytics/crashlytics_service.dart';
import 'app_exception.dart';
import 'result.dart';

/// Repository 경계 공통 가드 — [body] 의 결과를 [Result] 로 감싼다.
///
/// Phase 17 — see ROADMAP.md (D-20 ①).
///
/// - 성공: `Result.success(값)`.
/// - [AppException]: 이미 분류된 실패라 기록하지 않고 `Result.failure(그 예외)`
///   로 돌려준다 (중복 방지 — Notifier 층 [guardAsyncValue] 와 짝).
/// - 그 밖의 [Object]: 예상치 못한 오류 — [crashlytics] 에 non-fatal 로 1회
///   기록한 뒤 `Result.failure(UnknownException(cause: 원본))` 로 바꾼다.
///
/// **PII 금지 (Phase 10 D-28~30).** [reason] 은 `'<repo>_<method>'` 형식의
/// 코드 경로 식별자 상수만 넘긴다 (예: `'profile_repo_load'`). 사용자 값 ·
/// 이메일 · 토큰 · URL · 서버 message 를 넣지 않는다.
///
/// Crashlytics 미초기화 · 전송 실패는 [CrashlyticsService] 가 흡수하므로
/// 이 가드는 호출자에게 예외를 던지지 않는다.
Future<Result<T>> guardResult<T>(
  String reason,
  Future<T> Function() body, {
  required CrashlyticsService crashlytics,
}) async {
  try {
    return Result.success(await body());
  } on AppException catch (e) {
    return Result.failure(e);
  } on Object catch (e, st) {
    await crashlytics.recordError(e, st, reason: reason, fatal: false);
    return Result.failure(UnknownException(cause: e));
  }
}

/// Notifier 층 공통 가드 — [body] 를 [AsyncValue.guard] 로 감싼다.
///
/// Phase 17 — see ROADMAP.md (D-20 ②).
///
/// 결과가 error 이고 그 error 가 [AppException] 이 **아닐** 때만 [crashlytics]
/// 에 non-fatal 로 1회 기록한다. [AppException] 은 repository 의
/// [guardResult] 가 이미 분류 · 기록한 실패라 다시 기록하지 않는다 (중복 0).
/// 기존 Notifier 의 수동 `recordError` 호출부는 바꾸지 않는다.
///
/// **PII 금지 (Phase 10 D-28~30).** [reason] 은 `'<notifier>_<method>'` 형식의
/// 코드 경로 식별자 상수만 넘긴다.
Future<AsyncValue<T>> guardAsyncValue<T>(
  Future<T> Function() body, {
  required String reason,
  required CrashlyticsService crashlytics,
}) async {
  final result = await AsyncValue.guard(body);
  if (result case AsyncError(
    :final error,
    :final stackTrace,
  ) when error is! AppException) {
    await crashlytics.recordError(
      error,
      stackTrace,
      reason: reason,
      fatal: false,
    );
  }
  return result;
}
