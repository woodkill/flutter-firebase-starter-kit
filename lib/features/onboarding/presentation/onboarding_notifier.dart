import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/crashlytics/crashlytics_service.dart';

part 'onboarding_notifier.g.dart';

/// 온보딩 완료 상태를 영속화하는 Notifier (Phase 10 D-02).
///
/// [SharedPreferences] `onboarding.seen_version` 키에 정수 버전을 저장한다.
/// - `build()` 반환값: `true` 이면 현재 버전 이상 완료, `false` 이면 미시청.
/// - 온보딩 콘텐츠를 교체하여 기존 사용자에게 재표시하고 싶으면
///   [currentVersion] 을 bump 한다.
///
/// [LocaleNotifier] 와 동일한 keepAlive + SharedPreferences 패턴을 따른다.
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

  @override
  bool build() {
    _loadSeenStatus();
    return false;
  }

  /// SharedPreferences 에서 저장된 버전을 비동기로 복원한다.
  ///
  /// 저장값이 [currentVersion] 이상이면 `state = true`.
  /// I/O 예외 발생 시 [CrashlyticsService.recordError] 로 기록하고
  /// 기본 state (false) 유지.
  Future<void> _loadSeenStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedVersion = prefs.getInt(_key) ?? 0;
      if (!ref.mounted) return;
      state = savedVersion >= currentVersion;
    } on Exception catch (e, st) {
      await ref
          .read(crashlyticsServiceProvider)
          .recordError(e, st, reason: 'onboarding_load');
    }
  }

  /// 온보딩 완료를 기록한다. UI는 즉시 갱신되며, 디스크 쓰기 실패 시에도
  /// state 는 유지된다 (lossy persistence, locale_provider 패턴).
  Future<void> markSeen() async {
    state = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_key, currentVersion);
    } on Exception catch (e, st) {
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
    state = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } on Exception catch (e, st) {
      await ref
          .read(crashlyticsServiceProvider)
          .recordError(e, st, reason: 'onboarding_reset');
    }
  }
}
