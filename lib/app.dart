import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers/locale_provider.dart';
import 'core/providers/theme_provider.dart';
import 'core/theme/app_theme.dart';
import 'features/home/presentation/environment_info_screen.dart';
import 'l10n/generated/app_localizations.dart';

/// 앱의 루트 위젯.
///
/// [MaterialApp]을 구성하고, [ThemeNotifier]로 테마 모드를,
/// [LocaleNotifier]로 앱 로케일을 관리한다.
class App extends ConsumerWidget {
  /// 앱의 루트 위젯을 생성한다.
  ///
  /// [isFirebaseInitialized]가 `true`이면 Firebase 연결 성공 상태를 표시한다.
  const App({required this.isFirebaseInitialized, super.key});

  /// Firebase 초기화 성공 여부.
  final bool isFirebaseInitialized;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final locale = ref.watch(localeProvider);

    return MaterialApp(
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
      home: EnvironmentInfoScreen(
        isFirebaseInitialized: isFirebaseInitialized,
      ),
    );
  }
}
