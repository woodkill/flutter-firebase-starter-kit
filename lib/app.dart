import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers/locale_provider.dart';
import 'core/providers/theme_provider.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'l10n/generated/app_localizations.dart';

/// 앱의 루트 위젯.
///
/// [MaterialApp.router]를 구성하고, [ThemeNotifier]로 테마 모드를,
/// [LocaleNotifier]로 앱 로케일을, [GoRouter]로 라우팅을 관리한다.
class App extends ConsumerWidget {
  /// 앱의 루트 위젯을 생성한다.
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ThemeNotifier 가 AsyncNotifier 로 전환됨에 따라 AsyncValue<ThemeMode>
    // 를 반환한다. SharedPreferences 복원 전(loading) 또는 실패(error)
    // 시에는 ThemeMode.system 으로 fallback 한다.
    final themeMode = ref.watch(themeProvider).maybeWhen(
          data: (mode) => mode,
          orElse: () => ThemeMode.system,
        );
    final locale = ref.watch(localeProvider);
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: const String.fromEnvironment(
        'appName',
        defaultValue: 'StarterKit',
      ),
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    );
  }
}
