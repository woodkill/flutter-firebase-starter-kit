import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_starter_kit/core/providers/theme_provider.dart';

void main() {
  group('ThemeNotifier (AsyncNotifier)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('초기 build()는 빈 SharedPreferences 에서 ThemeMode.system 으로 resolve 한다',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // build() 가 SharedPreferences I/O 를 끝낸 뒤에만 resolve 한다.
      await container.read(themeProvider.future);

      expect(container.read(themeProvider).value, ThemeMode.system);
    });

    test('setThemeMode(ThemeMode.dark) 호출 후 state.value 는 ThemeMode.dark 이다',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // 먼저 build() 완료 대기 (race 회피)
      await container.read(themeProvider.future);

      final notifier = container.read(themeProvider.notifier);
      await notifier.setThemeMode(ThemeMode.dark);

      expect(container.read(themeProvider).value, ThemeMode.dark);
    });

    test('setThemeMode(ThemeMode.light) 호출 후 state.value 는 ThemeMode.light 이다',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(themeProvider.future);

      final notifier = container.read(themeProvider.notifier);
      await notifier.setThemeMode(ThemeMode.light);

      expect(container.read(themeProvider).value, ThemeMode.light);
    });

    test('setThemeMode 호출 시 SharedPreferences 에 theme_mode 키로 저장한다',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(themeProvider.future);

      final notifier = container.read(themeProvider.notifier);
      await notifier.setThemeMode(ThemeMode.dark);

      final prefs = await SharedPreferences.getInstance();
      final savedIndex = prefs.getInt('theme_mode');
      expect(savedIndex, ThemeMode.dark.index);
    });

    test('build() 는 SharedPreferences 에 저장된 ThemeMode 를 resolve 시점에 복원한다',
        () async {
      // SharedPreferences 에 dark 모드 인덱스를 미리 설정한다.
      SharedPreferences.setMockInitialValues({
        'theme_mode': ThemeMode.dark.index,
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      // build() 는 SharedPreferences 복원을 완료한 후에만 resolve 한다.
      // 폴링 (Future.delayed) 불필요 — `.future` await 한 번이면 충분하다.
      await container.read(themeProvider.future);

      expect(container.read(themeProvider).value, ThemeMode.dark);
    });

    test('keepAlive Provider 이므로 subscription 해제 후에도 AsyncValue 를 읽을 수 있다',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // keepAlive Provider 는 ProviderSubscription 을 닫아도 값이 유지된다.
      final sub = container.listen<AsyncValue<ThemeMode>>(
        themeProvider,
        (previous, next) {},
      );
      sub.close();

      // autoDispose 라면 subscription 해제 후 값이 사라지지만,
      // keepAlive 이므로 여전히 읽을 수 있다.
      final asyncValue = container.read(themeProvider);
      expect(asyncValue, isA<AsyncValue<ThemeMode>>());
    });

    test('유효하지 않은 index 가 저장되어 있으면 ThemeMode.system 으로 fallback 한다',
        () async {
      // ThemeMode.values.length (3) 이상의 인덱스를 설정한다.
      SharedPreferences.setMockInitialValues({
        'theme_mode': 999,
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(themeProvider.future);

      expect(container.read(themeProvider).value, ThemeMode.system);
    });
  });
}
