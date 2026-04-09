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

    test(
      'build() 완료 전 setThemeMode 를 호출해도 build() 결과에 덮어써지지 않는다 (MD-01 race 회피)',
      () async {
        // SharedPreferences 에 light 를 미리 저장 — build() 가 resolve 되면
        // light 로 복원된다. 수정 전 구현이라면 뒤늦게 resolve 된 build()
        // 결과가 사용자 선택(dark) 을 덮어써 UI 가 light 로 롤백된다.
        SharedPreferences.setMockInitialValues({
          'theme_mode': ThemeMode.light.index,
        });

        final container = ProviderContainer();
        addTearDown(container.dispose);

        // build() 가 아직 resolve 되지 않은 상태(`.future` 를 await 하지
        // 않음) 에서 즉시 setThemeMode(dark) 를 호출한다.
        // notifier 를 read 하면 Provider 가 초기화되며 build() 가 시작되지만
        // 아직 resolve 되지는 않는다.
        final notifier = container.read(themeProvider.notifier);
        await notifier.setThemeMode(ThemeMode.dark);

        // 수정 전 구현에서는 setThemeMode 가 먼저 optimistic update 를
        // 수행하고, 그 다음 `await SharedPreferences.getInstance()` 사이에
        // 뒤늦게 resolve 된 build() 결과(light) 가 state 를 덮어쓴다.
        // `.future` 를 추가로 await 하여 build() 가 확실히 resolve 되도록
        // 강제한 시점에도 state 는 dark 여야 한다 — 이 시점에 light 로
        // 덮어써져 있다면 race 가 발생한 것이다.
        await container.read(themeProvider.future);

        // build() 결과(light) 가 state 를 덮어쓰지 않고 dark 가 유지되어야
        // 한다. setThemeMode 내부에서 `await future` 로 build() 완료를
        // 먼저 대기하면 이후 optimistic update (state = AsyncData(dark)) 가
        // build() 결과 이후에 적용되어 race 가 사라진다.
        expect(container.read(themeProvider).value, ThemeMode.dark);

        // 저장도 되어 있어야 한다 (persistence 회귀 방지).
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt('theme_mode'), ThemeMode.dark.index);
      },
    );
  });
}
