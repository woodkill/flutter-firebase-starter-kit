import 'package:flutter/foundation.dart';

/// 스플래시 최소 표시 시간 설정 (Phase 10 AUTH-09, D-23).
///
/// `--dart-define-from-file=config/{flavor}.json`의 `splashMinDurationMs`
/// 값을 읽는다. 미지정 시 기본값 2000ms(2초)를 사용한다.
///
/// 프로젝트에서 조정하려면 `config/{flavor}.json`의 값을 변경 후 앱 재빌드.
///
/// **Design note:** `int.fromEnvironment`는 컴파일 타임 상수이므로
/// runtime 변경 불가. 런타임 조정이 필요하면 Remote Config(Phase 18)로
/// 승격 대상.
abstract final class SplashConfig {
  const SplashConfig._();

  /// 기본 최소 표시 시간 (2초).
  static const int _defaultMs = 2000;

  /// `--dart-define-from-file`에서 읽은 밀리초 값.
  static int get minDurationMs => const int.fromEnvironment(
    'splashMinDurationMs',
    defaultValue: _defaultMs,
  );

  /// [minDurationMs]의 [Duration] 변환.
  ///
  /// [overrideMinDuration]이 설정되어 있으면 해당 값을 우선 반환한다
  /// (테스트 전용 seam — Plan 05 splash_screen_test가 2초 실대기를
  /// 피하기 위해 사용. production 코드에서는 절대 설정 금지).
  static Duration get minDuration =>
      overrideMinDuration ?? Duration(milliseconds: minDurationMs);

  /// 테스트 전용 오버라이드 (WARNING #13 대응 — splash_screen_test 피드백 레이턴시 단축).
  ///
  /// ```dart
  /// setUp(() => SplashConfig.overrideMinDuration = const Duration(milliseconds: 1));
  /// tearDown(() => SplashConfig.overrideMinDuration = null);
  /// ```
  @visibleForTesting
  static Duration? overrideMinDuration;
}
