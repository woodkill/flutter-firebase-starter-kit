import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'theme_provider.g.dart';

/// 앱 테마 모드를 관리하는 [AsyncNotifier].
///
/// [SharedPreferences]로 사용자 선호를 영속화한다. [build]는
/// 저장된 [ThemeMode] 인덱스를 비동기로 복원한 뒤에만 resolve 하며,
/// 복원 I/O 가 실패하거나 인덱스가 유효하지 않으면 [ThemeMode.system]
/// 으로 fallback 한 뒤 디버그 로그를 남긴다.
///
/// fire-and-forget 패턴을 제거하여 에러 경로가 [AsyncValue.error] 로
/// 노출 가능하도록 한다. UI 단(`App` / `_ThemeToggleSection`) 은
/// `.value ?? ThemeMode.system` 또는 `.maybeWhen` 패턴으로 해석한다.
@Riverpod(keepAlive: true)
class ThemeNotifier extends _$ThemeNotifier {
  static const _key = 'theme_mode';

  @override
  Future<ThemeMode> build() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final index = prefs.getInt(_key);
      if (index == null ||
          index < 0 ||
          index >= ThemeMode.values.length) {
        return ThemeMode.system;
      }
      return ThemeMode.values[index];
    } on Exception catch (e, st) {
      // TODO(phase-08): FirebaseCrashlytics.recordError(e, st, reason: 'theme_load')
      debugPrint('theme_load failed: $e\n$st');
      return ThemeMode.system;
    }
  }

  /// 테마 모드를 변경하고 [SharedPreferences]에 영속화한다.
  ///
  /// lossy persistence: UI 는 즉시 [AsyncData] 로 갱신되며, 디스크 쓰기
  /// 실패 시에도 화면 테마는 유지되고 디버그 로그만 남긴다. Phase 8
  /// (Crashlytics 통합) 시점에 [FirebaseCrashlytics.recordError] 로 교체 예정.
  Future<void> setThemeMode(ThemeMode mode) async {
    state = AsyncData(mode);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_key, mode.index);
    } on Exception catch (e, st) {
      // TODO(phase-08): FirebaseCrashlytics.recordError(e, st, reason: 'theme_save')
      debugPrint('theme_save failed: $e\n$st');
    }
  }
}
