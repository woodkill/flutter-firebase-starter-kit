import 'package:flutter/foundation.dart';

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

  /// 내부 override 저장소 — release 빌드에서는 항상 null 로 유지되도록
  /// setter 에서 assert 로 게이트한다 (WR-02).
  static Duration? _overrideMinDuration;

  /// 테스트 전용 오버라이드 (WARNING #13 대응 — splash_screen_test 피드백 레이턴시 단축).
  ///
  /// ```dart
  /// setUp(() => SplashConfig.overrideMinDuration = const Duration(milliseconds: 1));
  /// tearDown(() => SplashConfig.overrideMinDuration = null);
  /// ```
  ///
  /// **WR-02 방어:** setter 는 `assert` 블록 내부에서만 실제 write 를
  /// 수행하므로 release 빌드에서는 이 필드를 실수로 대입해도 no-op 이며
  /// 프로덕션 스플래시 시간이 오염되지 않는다.
  @visibleForTesting
  static Duration? get overrideMinDuration => _overrideMinDuration;

  @visibleForTesting
  static set overrideMinDuration(Duration? value) {
    // assert 표현식은 debug/profile 빌드에서만 평가된다. IIFE 로 부작용을
    // 감싸 release 빌드에서는 write 자체가 실행되지 않는다.
    assert(() {
      _overrideMinDuration = value;
      return true;
    }(), 'overrideMinDuration must not be set outside debug/test builds');
  }

  /// 자동 익명 사인인 retry exponential backoff 스케쥴 (Phase 10.1 D-03).
  ///
  /// 첫 시도 실패 + transient 분류 시 본 List 의 Duration 을 순차적으로
  /// 대기한 뒤 [signInAnonymously] 를 재호출한다. 합계 최대 7초 (1s + 2s
  /// + 4s) — 사용자 체감 한계 (D-03 — jitter 없음, 단일 단말 가정으로
  /// thundering herd 무관).
  ///
  /// 변경 시 retry 매트릭스 unit test (T5 C1~C7) 의 `verify(...).called(N)`
  /// 횟수가 본 List 길이 + 1 (첫 시도) 에 동기되어야 한다.
  static const List<Duration> backoffSteps = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
  ];

  /// 내부 override 저장소 — release 빌드에서는 항상 null 로 유지되도록
  /// setter 에서 assert 로 게이트한다 (WR-02 verbatim 복제 — Phase 10.1 D-16).
  static List<Duration>? _overrideBackoffSteps;

  /// 테스트 전용 backoff 오버라이드 (Phase 10.1 D-16 — 실대기 9s → 3ms 단축).
  ///
  /// ```dart
  /// setUp(() => SplashConfig.overrideBackoffSteps = const [
  ///   Duration(milliseconds: 1),
  ///   Duration(milliseconds: 1),
  ///   Duration(milliseconds: 1),
  /// ]);
  /// tearDown(() => SplashConfig.overrideBackoffSteps = null);
  /// ```
  ///
  /// **WR-02 방어:** setter 는 `assert` 블록 내부에서만 실제 write 를
  /// 수행하므로 release 빌드에서는 이 필드를 실수로 대입해도 no-op 이며
  /// 프로덕션 retry 스케쥴이 오염되지 않는다.
  @visibleForTesting
  static List<Duration>? get overrideBackoffSteps => _overrideBackoffSteps;

  @visibleForTesting
  static set overrideBackoffSteps(List<Duration>? value) {
    // assert 표현식은 debug/profile 빌드에서만 평가된다. IIFE 로 부작용을
    // 감싸 release 빌드에서는 write 자체가 실행되지 않는다.
    assert(() {
      _overrideBackoffSteps = value;
      return true;
    }(), 'overrideBackoffSteps must not be set outside debug/test builds');
  }

  /// Consumer 단일 진입점 — [overrideBackoffSteps] 가 설정되어 있으면 우선
  /// 반환, 아니면 production [backoffSteps] 반환 (Phase 10.1 D-03/D-16).
  static List<Duration> get effectiveBackoffSteps =>
      overrideBackoffSteps ?? backoffSteps;
}
