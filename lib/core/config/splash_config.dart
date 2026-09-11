import 'package:flutter/foundation.dart';

import 'debug_only_override.dart';

/// 스플래시 최소 표시 시간 설정 (Phase 10 AUTH-09, D-23).
///
/// `--dart-define-from-file=config/{flavor}.json`의 `splashMinDurationMs`
/// 값을 읽는다. 미지정 시 기본값 2000ms(2초)를 사용한다.
///
/// 프로젝트에서 조정하려면 `config/{flavor}.json`의 값을 변경 후 앱 재빌드.
///
/// **Design note:** `int.fromEnvironment`는 컴파일 타임 상수이므로
/// runtime 변경 불가. 런타임 조정이 필요하면 Remote Config(Phase 18 —
/// see ROADMAP.md)로 승격 대상.
///
/// **범위 (코드 리뷰 IN-07):** 본 클래스는 스플래시 UI 타이밍만 다룬다.
/// 자동 익명 사인인 retry backoff 정책은 [AuthRetryConfig] 로 분리했다.
abstract final class SplashConfig {
  const SplashConfig._();

  /// 기본 최소 표시 시간 (2초).
  static const int _defaultMs = 2000;

  /// 허용 최소값 (ms).
  static const int minAllowedMs = 0;

  /// 허용 최대값 (ms) — 10초.
  ///
  /// 이보다 길면 사용자에게는 앱 정지로 보인다.
  static const int maxAllowedMs = 10000;

  /// `--dart-define-from-file`에서 읽은 밀리초 값.
  ///
  /// **검증되지 않은 원본값이다.** 범위 검증과 clamp 는 [minDuration] 이
  /// 담당한다 (WR-10).
  static int get minDurationMs => const int.fromEnvironment(
    'splashMinDurationMs',
    defaultValue: _defaultMs,
  );

  /// [minDurationMs]의 [Duration] 변환.
  ///
  /// [overrideMinDuration]이 설정되어 있으면 해당 값을 우선 반환한다
  /// (테스트 전용 seam — Plan 05 splash_screen_test가 2초 실대기를
  /// 피하기 위해 사용. production 코드에서는 절대 설정 금지).
  ///
  /// **값 검증 (코드 리뷰 WR-10).** 주입값이
  /// [minAllowedMs] ~ [maxAllowedMs] 범위를 벗어나면 debug 에서 assert 로
  /// 즉시 실패하고, release 에서는 clamp 한다. 검증이 없던 시절의 위험은
  /// 양방향이었다.
  /// - 음수 (`-1`, 부호 오타 / 잘못된 계산식): `Future.delayed` 는 음수
  ///   [Duration] 을 **즉시 완료로 처리**하므로 스플래시 최소 표시가 통째로
  ///   사라지고, 같은 프레임에 온보딩·홈 전환이 일어나 D-23 이 보장하려던
  ///   "초기화 완료 전 화면 전환 방지" 가 깨진다.
  /// - 과대값 (`2000000`, 0 하나 더): 33분짜리 스플래시 — 사용자에게는 앱
  ///   정지로 보인다.
  ///
  /// [overrideMinDuration] 은 명시적 테스트 seam 이므로 clamp 대상이 아니다
  /// (splash_screen_test 가 타임아웃 경로 검증에 5분을 주입한다).
  static Duration get minDuration {
    final ms = minDurationMs;
    assert(
      ms >= minAllowedMs && ms <= maxAllowedMs,
      'splashMinDurationMs 는 $minAllowedMs~$maxAllowedMs 범위여야 한다 '
      '(주입값: $ms). config/{flavor}.json 확인.',
    );
    return overrideMinDuration ??
        Duration(milliseconds: ms.clamp(minAllowedMs, maxAllowedMs));
  }

  /// 내부 override 저장소 — release 빌드에서는 항상 null 로 유지된다
  /// ([writeIfDebug] 가 보장).
  static Duration? _overrideMinDuration;

  /// 테스트 전용 오버라이드 (WARNING #13 대응 — splash_screen_test 피드백 레이턴시 단축).
  ///
  /// ```dart
  /// setUp(() => SplashConfig.overrideMinDuration = const Duration(milliseconds: 1));
  /// tearDown(() => SplashConfig.overrideMinDuration = null);
  /// ```
  @visibleForTesting
  static Duration? get overrideMinDuration => _overrideMinDuration;

  @visibleForTesting
  static set overrideMinDuration(Duration? value) => writeIfDebug<Duration?>(
    (v) => _overrideMinDuration = v,
    value,
    'overrideMinDuration must not be set outside debug/test builds',
  );
}
