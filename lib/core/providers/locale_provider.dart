import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/generated/app_localizations.dart';
import '../crashlytics/crashlytics_service.dart';

part 'locale_provider.g.dart';

/// 앱 로케일을 관리하는 Notifier.
///
/// [SharedPreferences]로 사용자 선호를 영속화한다.
/// 초기값은 기기 로케일이며, 지원 언어가 아닌 경우 en으로 fallback한다.
///
/// **첫 프레임 race 방어 (코드 리뷰 WR-03).** [build] 는 동기로 기기 로케일을
/// 반환하고 저장값 복원([restoreSavedLocale])은 fire-and-forget 으로 띄운다.
/// 그 사이에 사용자가 [setLocale] 을 호출하면, 뒤늦게 resolve 된 복원이
/// 사용자 선택을 덮어쓰고 **state 와 prefs 가 발산**한다 (화면은 옛 값,
/// 디스크는 새 값 — 사용자에게는 "바꿨는데 안 바뀌었다가 재시작하니 바뀌어
/// 있다" 는 재현 불가능해 보이는 버그다). [_isUserOverridden] 플래그로
/// "사용자 명시 선택 이후에는 복원을 포기" 를 보장한다.
///
/// 형제 파일 `theme_provider.dart` 는 같은 결함을 [AsyncNotifier] 승격으로
/// 해소했다 (코드 리뷰 MD-01). 여기서 같은 승격을 하지 않은 이유는 `build()`
/// 의 반환 타입이 `Locale` -> `AsyncValue<Locale>` 로 바뀌면서 `app.dart:41`
/// 의 `ref.watch(localeProvider)` 소비처가 함께 바뀌어야 하기 때문이다 —
/// 리뷰 권고대로 별도 작업으로 분리한다.
@Riverpod(keepAlive: true)
class LocaleNotifier extends _$LocaleNotifier {
  static const _key = 'locale_language_code';

  /// 사용자가 [setLocale] 로 로케일을 명시 선택했는지 여부 (WR-03).
  ///
  /// true 가 되면 [restoreSavedLocale] 은 state 를 건드리지 않는다.
  bool _isUserOverridden = false;

  @override
  Locale build() {
    // unawaited 로 fire-and-forget 의도를 명시한다 (discarded_futures 대응).
    // 복원 실패는 restoreSavedLocale 내부에서 흡수된다.
    unawaited(restoreSavedLocale());
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
  ///
  /// **사용자 선택 우선 (WR-03):** [setLocale] 이 이미 호출된 뒤라면
  /// ([_isUserOverridden] == true) state 를 건드리지 않고 즉시 반환한다.
  /// [build] 가 띄운 복원이 뒤늦게 resolve 되어 사용자 선택을 덮는 첫 프레임
  /// race 를 막는다.
  ///
  /// I/O 예외 발생 시(SharedPreferences 디스크 장애 등) 사용자에게는 무해하므로
  /// 기본 로케일을 유지하고 [CrashlyticsService.recordError]로 stg/prod 환경에
  /// 비치명 에러를 기록한다 (dev flavor 는 wrapper 가 자동 no-op).
  ///
  /// [build] 외부에서 호출하는 것은 테스트 전용이다 — 첫 프레임 race 를
  /// 결정론적으로 재현하기 위한 seam ([visibleForTesting]).
  @visibleForTesting
  Future<void> restoreSavedLocale() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_key);
      if (code != null) {
        final isSupported = AppLocalizations.supportedLocales.any(
          (l) => l.languageCode == code,
        );
        if (isSupported) {
          // autoDispose race 방어: dispose된 notifier에 state 쓰기 금지.
          // WR-03: 늦은 복원이 사용자의 명시 선택을 덮지 않는다.
          if (!ref.mounted || _isUserOverridden) return;
          state = Locale(code);
        }
      }
    } on Object catch (e, st) {
      // Error 계열도 포함 — theme_provider 와 동일 패턴.
      // WR-05: debugPrint 는 release 에서 제거되지 않으므로 kDebugMode 로 가둔다.
      if (kDebugMode) {
        debugPrint('locale_load failed: $e\n$st');
      }
      // WR-04: async gap 이후의 ref.read 는 dispose 된 컨테이너에서
      // StateError 를 던진다. 가드 없이 두면 원래 진단하려던 e 가 사라지고,
      // 이 메서드는 build() 에서 await 되지 않는 fire-and-forget 이므로
      // 그 StateError 가 unhandled rejection 으로 zone 까지 올라가
      // runZonedGuarded 가 fatal 로 기록한다 (비치명 이벤트의 치명 둔갑).
      if (!ref.mounted) return;
      // recordError 자체의 실패는 CrashlyticsService 래퍼가 흡수한다 (WR-01).
      await ref
          .read(crashlyticsServiceProvider)
          .recordError(e, st, reason: 'locale_load');
    }
  }

  /// 로케일을 변경하고 [SharedPreferences]에 영속화한다.
  ///
  /// lossy persistence: UI는 즉시 갱신되며, 디스크 쓰기 실패 시에도 화면
  /// 로케일은 유지되고 [CrashlyticsService.recordError]로 stg/prod 환경에
  /// 비치명 에러를 기록한다 (dev flavor 는 wrapper 가 자동 no-op).
  Future<void> setLocale(Locale locale) async {
    // WR-03: 이 시점 이후의 복원은 사용자 선택을 덮지 않는다.
    _isUserOverridden = true;
    state = locale;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, locale.languageCode);
    } on Object catch (e, st) {
      // WR-05: release logcat 출력 방지.
      if (kDebugMode) {
        debugPrint('locale_save failed: $e\n$st');
      }
      // WR-04: async gap 이후 ref.read 가드.
      if (!ref.mounted) return;
      await ref
          .read(crashlyticsServiceProvider)
          .recordError(e, st, reason: 'locale_save');
    }
  }
}
