import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'theme_provider.g.dart';

/// 앱 테마 모드를 관리하는 Notifier.
///
/// [SharedPreferences]로 사용자 선호를 영속화한다.
/// 초기값은 [ThemeMode.system]이며, 비동기로 저장된 값을 복원한다.
@Riverpod(keepAlive: true)
class ThemeNotifier extends _$ThemeNotifier {
  static const _key = 'theme_mode';

  @override
  ThemeMode build() {
    _loadThemeMode();
    return ThemeMode.system;
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(_key);
    if (index != null && index < ThemeMode.values.length) {
      state = ThemeMode.values[index];
    }
  }

  /// 테마 모드를 변경하고 [SharedPreferences]에 영속화한다.
  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, mode.index);
  }
}
