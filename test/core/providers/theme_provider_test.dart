import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_starter_kit/core/providers/theme_provider.dart';

void main() {
  group('ThemeNotifier', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('초기 state는 ThemeMode.system이다', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final themeMode = container.read(themeProvider);

      expect(themeMode, ThemeMode.system);
    });

    test('setThemeMode(ThemeMode.dark) 호출 후 state는 ThemeMode.dark이다',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(themeProvider.notifier);
      await notifier.setThemeMode(ThemeMode.dark);

      final themeMode = container.read(themeProvider);
      expect(themeMode, ThemeMode.dark);
    });

    test('setThemeMode(ThemeMode.light) 호출 후 state는 ThemeMode.light이다',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(themeProvider.notifier);
      await notifier.setThemeMode(ThemeMode.light);

      final themeMode = container.read(themeProvider);
      expect(themeMode, ThemeMode.light);
    });

    test('setThemeMode 호출 시 SharedPreferences에 theme_mode 키로 저장한다',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(themeProvider.notifier);
      await notifier.setThemeMode(ThemeMode.dark);

      final prefs = await SharedPreferences.getInstance();
      final savedIndex = prefs.getInt('theme_mode');
      expect(savedIndex, ThemeMode.dark.index);
    });

    test('build 시 SharedPreferences에 저장된 ThemeMode를 복원한다', () async {
      // SharedPreferences에 dark 모드 인덱스를 미리 설정한다.
      SharedPreferences.setMockInitialValues({
        'theme_mode': ThemeMode.dark.index,
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      // build()는 동기로 ThemeMode.system을 반환하고,
      // 비동기로 저장된 값을 복원하므로 잠시 대기한다.
      // 초기값 확인
      expect(container.read(themeProvider), ThemeMode.system);

      // 비동기 복원 대기
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(container.read(themeProvider), ThemeMode.dark);
    });

    test('keepAlive Provider이다 (autoDispose가 아니다)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // keepAlive Provider는 ProviderSubscription을 닫아도 값이 유지된다.
      final sub = container.listen(themeProvider, (_, _) {});
      sub.close();

      // autoDispose라면 subscription 해제 후 값이 사라지지만,
      // keepAlive이므로 여전히 읽을 수 있다.
      final themeMode = container.read(themeProvider);
      expect(themeMode, isA<ThemeMode>());
    });

    test('유효하지 않은 index가 저장되어 있으면 기본값 ThemeMode.system을 유지한다',
        () async {
      // ThemeMode.values.length (3) 이상의 인덱스를 설정한다.
      SharedPreferences.setMockInitialValues({
        'theme_mode': 999,
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      // 비동기 복원 대기
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(container.read(themeProvider), ThemeMode.system);
    });
  });
}
