import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
import 'core/providers/locale_provider.dart';
import 'core/providers/theme_provider.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/notifications/application/notification_settings_notifier.dart';
import 'features/notifications/application/notification_tap_handler.dart';
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
    //
    // loading 과 error 를 `orElse` 한 팔로 합치면 error 가 텔레메트리 없이
    // 삼켜진다 (사용자 저장 테마가 영구히 무시되는데 로그도 남지 않는다).
    // error arm 을 분리해 최소한 관측 가능하게 둔다.
    final themeMode = ref
        .watch(themeProvider)
        .when(
          data: (mode) => mode,
          loading: () => ThemeMode.system,
          error: (e, st) {
            if (kDebugMode) {
              debugPrint('theme resolve failed: $e\n$st');
            }
            return ThemeMode.system;
          },
        );
    final locale = ref.watch(localeProvider);
    final router = ref.watch(appRouterProvider);
    // Phase 17 D-32 — 앱 시작 동기화 · keepAlive notifier 활성화(재빌드 0).
    // listen 은 값이 바뀌어도 App 을 다시 그리지 않는다 — 알림 notifier 가
    // 앱 시작 때 OS 권한 · opt-in 을 읽고 토큰 문서를 맞추게 깨우기만 한다.
    ref.listen<AsyncValue<bool>>(notificationSettingsProvider, (_, _) {});
    // Phase 17 D-01 · D-04 — 알림 수신 표시 · 탭 경로 핸들러 활성화(재빌드 0).
    ref.listen(notificationTapHandlerProvider, (previous, next) {});

    return MaterialApp.router(
      // 앱 타이틀은 OS 최근 앱 화면(task description) 과 접근성 표면에
      // 노출되므로 로케일을 따라야 한다. `onGenerateTitle` 은 BuildContext 를
      // 주므로 l10n 접근이 가능하다. dart-define 으로 `appName` 이 주입된
      // 경우에만 그 값을 우선한다 (브랜드명 고정 의도).
      onGenerateTitle: (context) => AppConfig.appName.isEmpty
          ? AppLocalizations.of(context).appTitle
          : AppConfig.appName,
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
