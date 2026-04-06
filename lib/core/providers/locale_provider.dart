import 'dart:ui';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/generated/app_localizations.dart';

part 'locale_provider.g.dart';

/// 앱 로케일을 관리하는 Notifier.
///
/// [SharedPreferences]로 사용자 선호를 영속화한다.
/// 초기값은 기기 로케일이며, 지원 언어가 아닌 경우 en으로 fallback한다.
@Riverpod(keepAlive: true)
class LocaleNotifier extends _$LocaleNotifier {
  static const _key = 'locale_language_code';

  @override
  Locale build() {
    _loadLocale();
    return _resolveInitialLocale();
  }

  /// 기기 로케일을 기반으로 초기 로케일을 결정한다.
  ///
  /// [PlatformDispatcher.instance.locale]에서 기기 로케일을 가져오고,
  /// [AppLocalizations.supportedLocales]에 포함되지 않으면
  /// [Locale('en')]으로 fallback한다.
  Locale _resolveInitialLocale() {
    final deviceLocale = PlatformDispatcher.instance.locale;
    final isSupported = AppLocalizations.supportedLocales.any(
      (l) => l.languageCode == deviceLocale.languageCode,
    );
    return isSupported ? Locale(deviceLocale.languageCode) : const Locale('en');
  }

  /// [SharedPreferences]에서 저장된 로케일을 비동기로 복원한다.
  ///
  /// 저장된 언어 코드가 [AppLocalizations.supportedLocales]에 포함되지 않으면
  /// 무시하고 기본값을 유지한다 (위협 T-04-03 대응).
  Future<void> _loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_key);
    if (code != null) {
      final isSupported = AppLocalizations.supportedLocales.any(
        (l) => l.languageCode == code,
      );
      if (isSupported) {
        state = Locale(code);
      }
    }
  }

  /// 로케일을 변경하고 [SharedPreferences]에 영속화한다.
  Future<void> setLocale(Locale locale) async {
    state = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, locale.languageCode);
  }
}
