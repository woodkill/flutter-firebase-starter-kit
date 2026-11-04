import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_starter_kit/core/l10n/app_title.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/launcher_names.dart' as gen;
import '../../../tool/setup/flavor.dart';

void main() {
  // 앱 안 제목 식은 resolveAppTitle 1곳이다(onGenerateTitle · 홈 AppBar 공유).
  // 글자는 앱 언어의 ARB appTitle 이고, config 이름이 그 flavor 접미사로 끝날
  // 때만 같은 접미사를 붙인다 — 빌드 생성기가 홈 화면 이름에 접미사를 붙이는
  // 조건과 같다. lib 은 tool/ 을 import 하지 않으므로 이 시험이 접미사 표와
  // 조건을 생성기 · 위저드 쪽과 대조한다.
  group('앱 안 제목 (T-171-HOME · T-22-TITLE)', () {
    for (final code in const ['ko', 'en', 'ja']) {
      test('T-171-HOME-02: $code — 글자는 ARB appTitle · 접미사는 config 이름이 '
          '그 접미사로 끝날 때만', () {
        final l10n = lookupAppLocalizations(Locale(code));

        // 시험의 dart-define 은 빈 값 → 접미사 없음.
        expect(resolveAppTitle(l10n), l10n.appTitle);
        expect(
          resolveAppTitle(l10n, appName: 'My App Dev', flavor: 'dev'),
          '${l10n.appTitle} Dev',
        );
        expect(
          resolveAppTitle(l10n, appName: 'My App Stg', flavor: 'stg'),
          '${l10n.appTitle} Stg',
        );
        // config 이름 글자는 제목이 되지 않는다.
        expect(
          resolveAppTitle(l10n, appName: 'My App', flavor: 'prod'),
          l10n.appTitle,
        );
      });
    }

    test('T-22-TITLE-02: lib · 생성기 · 위저드의 flavor 접미사 표가 같다', () {
      final wizardSuffixes = <String, String>{
        for (final flavor in Flavor.values)
          flavor.name: flavor.displayNameSuffix,
      };

      // 양성 대조 — 세 flavor 가 모두 있고 dev 접미사가 비어 있지 않다.
      expect(wizardSuffixes.keys, unorderedEquals(['dev', 'stg', 'prod']));
      expect(wizardSuffixes['dev'], isNotEmpty);
      expect(kFlavorDisplayNameSuffixes, wizardSuffixes);
      expect(gen.flavorDisplayNameSuffixes, wizardSuffixes);
    });

    test('T-22-TITLE-03: 접미사를 뗀 dev · stg 이름 · 빈 이름 · 모르는 flavor 는 '
        '접미사 없음 · 접미사 유무가 생성기 판정과 같다', () {
      final l10n = lookupAppLocalizations(const Locale('ko'));

      for (final (appName, flavor) in const [
        ('My App', 'dev'),
        ('', 'dev'),
        ('My App Dev', 'qa'),
        ('My App Dev', 'stg'),
      ]) {
        expect(
          resolveAppTitle(l10n, appName: appName, flavor: flavor),
          l10n.appTitle,
          reason: '($appName, $flavor)',
        );
      }

      const pairs = [
        ('My App Dev', 'dev'),
        ('My App', 'dev'),
        ('My App Stg', 'stg'),
        ('My App', 'stg'),
        ('My App', 'prod'),
        ('My App Dev', 'prod'),
        ('', 'dev'),
        ('My App Dev', 'qa'),
      ];
      var suffixedCount = 0;
      for (final (appName, flavor) in pairs) {
        final suffix = gen.flavorDisplayNameSuffixes[flavor] ?? '';
        final expectedSuffix = gen.stripFlavorSuffix(appName, suffix) != appName
            ? suffix
            : '';
        if (expectedSuffix.isNotEmpty) suffixedCount++;

        expect(
          resolveAppTitle(l10n, appName: appName, flavor: flavor),
          '${l10n.appTitle}$expectedSuffix',
          reason: '($appName, $flavor)',
        );
      }
      // 양성 대조 — 접미사가 붙는 쌍(dev · stg)이 실제로 있다.
      expect(suffixedCount, 2);
    });
  });
}
