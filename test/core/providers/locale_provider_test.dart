import 'dart:io';
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

    test(
      'setLocale 호출 시 SharedPreferences에 locale_language_code 키로 저장한다',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(localeProvider.notifier);
        await notifier.setLocale(const Locale('ko'));

        final prefs = await SharedPreferences.getInstance();
        final savedCode = prefs.getString('locale_language_code');
        expect(savedCode, 'ko');
      },
    );

    test('build 시 SharedPreferences에 저장된 Locale을 복원한다', () async {
      // SharedPreferences에 ko를 미리 설정한다.
      SharedPreferences.setMockInitialValues({'locale_language_code': 'ko'});

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

    test(
      '지원하지 않는 languageCode가 SharedPreferences에 저장되어 있으면 기본값 Locale("en")을 유지한다',
      () async {
        // 지원하지 않는 언어 코드를 설정한다.
        SharedPreferences.setMockInitialValues({'locale_language_code': 'fr'});

        final container = ProviderContainer();
        addTearDown(container.dispose);

        // 비동기 복원 대기
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(container.read(localeProvider), const Locale('en'));
      },
    );

    test('supportedLocales에 Locale("en")과 Locale("ko")가 포함된다', () {
      expect(
        AppLocalizations.supportedLocales,
        containsAll(<Locale>[const Locale('en'), const Locale('ko')]),
      );
    });

    test('setLocale 이후의 늦은 복원은 사용자 선택을 덮지 않는다 (WR-03)', () async {
      // build() 가 띄운 fire-and-forget 복원이 setLocale 뒤에 resolve 되는
      // 첫 프레임 race 를 결정론적으로 재현한다. mock SharedPreferences 는
      // getInstance() 해소 순서를 제어할 수 없어 실제 race 를 재현하지
      // 못하므로, 복원 본체(restoreSavedLocale) 를 명시 호출해 "늦게 도착한
      // 복원" 을 그대로 흉내낸다.
      //
      // 수정 전 구현이라면 여기서 state 가 ko 로 되돌아가고, 디스크에는 ja 가
      // 남아 state 와 prefs 가 발산한다.
      SharedPreferences.setMockInitialValues({'locale_language_code': 'ko'});

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(localeProvider.notifier);
      await notifier.setLocale(const Locale('ja'));

      // 늦게 도착한 복원.
      await notifier.restoreSavedLocale();

      expect(
        container.read(localeProvider),
        const Locale('ja'),
        reason: 'WR-03: 사용자 명시 선택 이후에는 복원을 포기해야 한다',
      );

      // state 와 prefs 가 같은 값이어야 한다 (발산 금지).
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('locale_language_code'), 'ja');
    });

    test('사용자 선택이 없으면 복원은 정상 적용된다 (WR-03 회귀 가드)', () async {
      // 위 가드가 복원 기능 자체를 죽이지 않았음을 확인한다.
      SharedPreferences.setMockInitialValues({'locale_language_code': 'ko'});

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(localeProvider.notifier);
      await notifier.restoreSavedLocale();

      expect(container.read(localeProvider), const Locale('ko'));
    });
  });

  group('core/providers 로깅 정책 (WR-05)', () {
    // debugPrint 는 이름과 달리 release 에서 제거되지 않는다
    // (debugPrintThrottled -> print). 프로젝트의 다른 파일들은 이미
    // `if (kDebugMode) debugPrint(...)` 를 지키고 있고, core/providers 2파일만
    // 무가드로 남아 로깅 정책이 파일 단위로 갈려 있었다.
    for (final path in const <String>[
      'lib/core/providers/locale_provider.dart',
      'lib/core/providers/theme_provider.dart',
    ]) {
      test('$path 의 debugPrint 는 모두 kDebugMode 로 가드된다', () async {
        final source = await File(path).readAsString();
        // 주석/문서 라인은 제외한다 (설명문에 등장하는 식별자 오탐 방지).
        final codeOnly = source
            .split('\n')
            .where((line) {
              final trimmed = line.trimLeft();
              return !trimmed.startsWith('//') && !trimmed.startsWith('///');
            })
            .join('\n');

        final debugPrintCount = RegExp(
          r'debugPrint\s*\(',
        ).allMatches(codeOnly).length;
        final guardCount = RegExp(
          r'if\s*\(\s*kDebugMode\s*\)',
        ).allMatches(codeOnly).length;

        expect(
          debugPrintCount,
          greaterThan(0),
          reason: '검사 대상 호출이 사라졌다면 테스트를 갱신할 것',
        );
        expect(
          guardCount,
          debugPrintCount,
          reason: 'WR-05: debugPrint 호출 수와 kDebugMode 가드 수가 일치해야 한다',
        );
      });

      test(
        '$path 의 async gap 뒤 ref.read 는 ref.mounted 로 가드된다 (WR-04)',
        () async {
          final source = await File(path).readAsString();
          final codeOnly = source
              .split('\n')
              .where((line) {
                final trimmed = line.trimLeft();
                return !trimmed.startsWith('//') && !trimmed.startsWith('///');
              })
              .join('\n');

          // catch 블록 안에서 crashlyticsServiceProvider 를 읽는 지점마다
          // 앞선 `if (!ref.mounted) return` 가드가 있어야 한다.
          final readCount = RegExp(
            r'read\s*\(\s*crashlyticsServiceProvider\s*\)',
          ).allMatches(codeOnly).length;
          final guardCount = RegExp(
            r'if\s*\(\s*!\s*ref\.mounted\s*\)',
          ).allMatches(codeOnly).length;

          expect(readCount, greaterThan(0));
          expect(
            guardCount,
            greaterThanOrEqualTo(readCount),
            reason:
                'WR-04: dispose 된 컨테이너에서 ref.read 가 StateError 를 던지면 '
                '원래 진단하려던 예외가 대체된다',
          );
        },
      );
    }
  });
}
