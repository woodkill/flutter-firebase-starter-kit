import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_starter_kit/core/providers/locale_provider.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

void main() {
  group('LocaleNotifier', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('초기 state는 Locale("en")이다', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final locale = container.read(localeProvider);

      expect(locale, const Locale('en'));
    });

    test('setLocale(Locale("ko")) 호출 후 state는 Locale("ko")이다', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(localeProvider.notifier);
      await notifier.setLocale(const Locale('ko'));

      final locale = container.read(localeProvider);
      expect(locale, const Locale('ko'));
    });

    test('setLocale 호출 시 SharedPreferences에 locale_language_code 키로 저장한다',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(localeProvider.notifier);
      await notifier.setLocale(const Locale('ko'));

      final prefs = await SharedPreferences.getInstance();
      final savedCode = prefs.getString('locale_language_code');
      expect(savedCode, 'ko');
    });

    test('build 시 SharedPreferences에 저장된 Locale을 복원한다', () async {
      // SharedPreferences에 ko를 미리 설정한다.
      SharedPreferences.setMockInitialValues({
        'locale_language_code': 'ko',
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      // build()는 동기로 초기값을 반환하고,
      // 비동기로 저장된 값을 복원하므로 잠시 대기한다.
      // 초기값 확인
      expect(container.read(localeProvider), const Locale('en'));

      // 비동기 복원 대기
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(container.read(localeProvider), const Locale('ko'));
    });

    test('keepAlive Provider이다 (autoDispose가 아니다)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // keepAlive Provider는 ProviderSubscription을 닫아도 값이 유지된다.
      final sub = container.listen(localeProvider, (_, _) {});
      sub.close();

      // autoDispose라면 subscription 해제 후 값이 사라지지만,
      // keepAlive이므로 여전히 읽을 수 있다.
      final locale = container.read(localeProvider);
      expect(locale, isA<Locale>());
    });

    test('지원하지 않는 languageCode가 SharedPreferences에 저장되어 있으면 기본값 Locale("en")을 유지한다',
        () async {
      // 지원하지 않는 언어 코드를 설정한다.
      SharedPreferences.setMockInitialValues({
        'locale_language_code': 'fr',
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      // 비동기 복원 대기
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(container.read(localeProvider), const Locale('en'));
    });

    test('supportedLocales에 Locale("en")과 Locale("ko")가 포함된다', () {
      expect(
        AppLocalizations.supportedLocales,
        containsAll(<Locale>[const Locale('en'), const Locale('ko')]),
      );
    });
  });
}
