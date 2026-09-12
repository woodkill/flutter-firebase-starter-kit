import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/crashlytics/crashlytics_service.dart';

part 'onboarding_notifier.g.dart';

/// 온보딩 완료 상태를 영속화하는 AsyncNotifier (Phase 10 D-02, Issue #10).
///
/// [SharedPreferences] `onboarding.seen_version` 키에 정수 버전을 저장한다.
/// - `build()` 반환값: `true` 이면 현재 버전 이상 완료, `false` 이면 미시청.
/// - 온보딩 콘텐츠를 교체하여 기존 사용자에게 재표시하고 싶으면
///   [currentVersion] 을 bump 한다.
///
/// ## Issue #10 (Plan 10-14) — race condition 구조적 제거
///
/// 이전 구현은 동기 `bool build()` 가 `false` 를 즉시 반환하고 별도의
/// private 비동기 헬퍼를 fire-and-forget 으로 호출하여 SharedPreferences
/// 로드가 완료되기 전에도 consumer 가 `false` 를 관찰할 수 있었다. 이로
/// 인해 [SplashInitializer] 가 `signInAnonymously` 호출을 스킵하는
/// deterministic race 가 발생 (UAT Test 17 재검증 FAIL 2026-04-21).
///
/// 현재 구현은 `FutureOr<bool> build() async` 로 전환되어 SharedPreferences
/// 로드 완료 전까지 [AsyncLoading] 을 노출하고, 완료 후 [AsyncData] 로
/// 전환된다. 모든 consumer 는 AsyncValue 소비 패턴 (`.when` /
/// `.value ?? false` / `.isLoading`) 을 사용한다 (GC-02 전면 마이그레이션).
///
/// build 예외 처리는 **lossy persistence** 정책을 유지 —
/// [CrashlyticsService.recordError] 기록 후 `false` 반환 (AsyncError 로
/// surface 하지 않음). 이는 기존 비동기 헬퍼의 Phase 1 D-13 철학
/// (Firebase/IO 장애에도 앱이 동작) 을 승계한 것이며, build error 를
/// surface 했을 때 upstream 이 전부 AsyncError 처리를 추가해야 하는
/// 복잡도를 Starter Kit 수준에서 회피한다.
///
/// ## D-33: Dev Tools production 표면 (Plan-checker WARNING #8)
///
/// [reset] 은 `@visibleForTesting` 없이 **public** 메서드이다. Plan 04
/// `_DevToolsSection` 이 프로덕션 코드에서 이 메서드를 호출하므로 제한을
/// 두지 않는다. 테스트에서도 동일한 public API 를 사용한다.
@Riverpod(keepAlive: true)
class OnboardingNotifier extends _$OnboardingNotifier {
  /// SharedPreferences 저장 키.
  static const String _key = 'onboarding.seen_version';

  /// 현재 온보딩 콘텐츠 버전. 콘텐츠 교체 후 bump 하면 기존 사용자에게
  /// 재표시된다 (Pitfall 7).
  static const int currentVersion = 1;

  /// SharedPreferences 로드 완료를 await 한 뒤 state 를 반환한다.
  ///
  /// 저장값이 [currentVersion] 이상이면 `true`, 미만이면 `false`.
  /// I/O 예외 발생 시 [CrashlyticsService.recordError] 로 기록하고
  /// lossy fallback `false` 를 반환한다 (Phase 1 D-13 철학 승계).
  @override
  FutureOr<bool> build() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedVersion = prefs.getInt(_key) ?? 0;
      return savedVersion >= currentVersion;
    } on Object catch (e, st) {
      // 10-REVIEW CR-03: 예외 타입 지정자를 넓혔다. 손상된 prefs 값의 cast
      // 실패 (Error 계열) 가 build() 밖으로 새면 splash 가 영구 스피너로
      // 고정된다 (CR-02 연계).
      await ref
          .read(crashlyticsServiceProvider)
          .recordError(e, st, reason: 'onboarding_load');
      return false;
    }
  }

  /// 온보딩 완료를 기록한다. UI 는 즉시 [AsyncData] (true) 로 갱신되며,
  /// 디스크 쓰기 실패 시에도 state 는 유지된다 (lossy persistence,
  /// locale_provider 패턴).
  Future<void> markSeen() async {
    state = const AsyncData<bool>(true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_key, currentVersion);
    } on Object catch (e, st) {
      // 10-REVIEW CR-03: 예외 타입 지정자를 넓혔다 (영속 계층 일관성).
      await ref
          .read(crashlyticsServiceProvider)
          .recordError(e, st, reason: 'onboarding_save');
    }
  }

  /// 온보딩 상태를 초기화한다 (D-33 Dev Tools, WARNING #8: production 표면).
  ///
  /// Plan 04 `_DevToolsSection` 과 테스트 모두 본 메서드를 직접 호출한다.
  /// `@visibleForTesting` 어노테이션은 부여하지 않는다.
  Future<void> reset() async {
    state = const AsyncData<bool>(false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } on Object catch (e, st) {
      // 10-REVIEW CR-03: 예외 타입 지정자를 넓혔다 (영속 계층 일관성).
      await ref
          .read(crashlyticsServiceProvider)
          .recordError(e, st, reason: 'onboarding_reset');
    }
  }
}
