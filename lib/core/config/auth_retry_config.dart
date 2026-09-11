import 'package:flutter/foundation.dart';

import 'debug_only_override.dart';

/// 자동 익명 사인인 retry 정책 (Phase 10.1 D-03, D-16).
///
/// 첫 시도 실패 + transient 분류 시 [backoffSteps] 의 [Duration] 을 순차적으로
/// 대기한 뒤 재시도한다. 소비처는 `splash_initializer.dart` 의 retry loop 다.
///
/// **분리 근거 (코드 리뷰 IN-07):** 이 정책은 원래 `SplashConfig` 안에 있었다.
/// 그런데 `SplashConfig` 의 클래스 doc 은 "스플래시 최소 표시 시간 설정" 만
/// 선언하는데 파일의 절반이 인증 재시도 스케쥴이었다. 두 관심사는 수명도
/// 소비처도 다르므로 (전자는 UI 타이밍, 후자는 인증 재시도 정책) SRP 에 따라
/// 분리했다. 분리 결과 `SplashConfig` 의 doc 범위 선언이 실제와 일치한다.
abstract final class AuthRetryConfig {
  const AuthRetryConfig._();

  /// 자동 익명 사인인 retry exponential backoff 스케쥴 (Phase 10.1 D-03).
  ///
  /// 합계 최대 7초 (1s + 2s + 4s) — 사용자 체감 한계 (D-03 — jitter 없음,
  /// 단일 단말 가정으로 thundering herd 무관).
  ///
  /// 변경 시 retry 매트릭스 unit test (T5 C1~C7) 의 `verify(...).called(N)`
  /// 횟수가 본 List 길이 + 1 (첫 시도) 에 동기되어야 한다.
  static const List<Duration> backoffSteps = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
  ];

  /// 내부 override 저장소 — release 빌드에서는 항상 null 로 유지된다
  /// ([writeIfDebug] 가 보장).
  static List<Duration>? _overrideBackoffSteps;

  /// 테스트 전용 backoff 오버라이드 (Phase 10.1 D-16 — 실대기 9s → 3ms 단축).
  ///
  /// ```dart
  /// setUp(() => AuthRetryConfig.overrideBackoffSteps = const [
  ///   Duration(milliseconds: 1),
  ///   Duration(milliseconds: 1),
  ///   Duration(milliseconds: 1),
  /// ]);
  /// tearDown(() => AuthRetryConfig.overrideBackoffSteps = null);
  /// ```
  @visibleForTesting
  static List<Duration>? get overrideBackoffSteps => _overrideBackoffSteps;

  @visibleForTesting
  static set overrideBackoffSteps(List<Duration>? value) =>
      writeIfDebug<List<Duration>?>(
        (v) => _overrideBackoffSteps = v,
        value,
        'overrideBackoffSteps must not be set outside debug/test builds',
      );

  /// Consumer 단일 진입점 — [overrideBackoffSteps] 가 설정되어 있으면 우선
  /// 반환, 아니면 production [backoffSteps] 반환 (Phase 10.1 D-03/D-16).
  static List<Duration> get effectiveBackoffSteps =>
      overrideBackoffSteps ?? backoffSteps;
}
