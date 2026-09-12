import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/l10n/locale_display_names.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

void main() {
  // WR-04 (Phase 04 리뷰) — kLocaleEndonyms 는 손으로 유지되는 맵이고
  // localeDisplayName 은 미등록 코드를 조용히 코드 자체로 폴백한다. 새 ARB 를
  // 추가하면서 이 맵을 잊으면 언어 선택 드롭다운에 원시 코드('fr')가 노출된
  // 채로 build / analyze / test 가 전부 통과한다. 그 드리프트를 RED 로 만든다.
  group('kLocaleEndonyms ↔ supportedLocales 정합', () {
    test('supportedLocales 전부가 endonym 을 가진다', () {
      final missing = AppLocalizations.supportedLocales
          .where((l) => !kLocaleEndonyms.containsKey(l.languageCode))
          .map((l) => l.languageCode)
          .toList();

      expect(
        missing,
        isEmpty,
        reason: 'kLocaleEndonyms 에 항목이 없으면 언어 선택 UI 에 원시 코드가 노출된다',
      );
    });

    test('endonym 맵에 지원하지 않는 언어가 남아 있지 않다', () {
      final supported = AppLocalizations.supportedLocales
          .map((l) => l.languageCode)
          .toSet();
      final orphans = kLocaleEndonyms.keys
          .where((code) => !supported.contains(code))
          .toList();

      expect(
        orphans,
        isEmpty,
        reason: 'ARB 를 제거했다면 kLocaleEndonyms 항목도 함께 제거할 것',
      );
    });

    // IN-02 (2차 리뷰) — 위 두 검사는 둘 다 languageCode 로 집계하므로 언어 축
    // 밖의 드리프트를 못 본다. supportedLocales 가 Locale('zh','Hans') +
    // Locale('zh','Hant') 로 확장되면 kLocaleEndonyms['zh'] 항목 하나로 두
    // 엔트리가 모두 만족되고, 언어 선택 드롭다운에는 동일 라벨 2개가 뜬 채
    // build / analyze / test 가 전부 통과한다. 라벨 유일성을 별도로 잠근다.
    test('표시 이름이 로케일마다 유일하다', () {
      final labels = AppLocalizations.supportedLocales
          .map(localeDisplayName)
          .toList();

      expect(
        labels.toSet().length,
        labels.length,
        reason:
            '드롭다운에 동일 라벨이 중복되면 사용자가 두 항목을 구분할 수 없다. '
            'languageCode 가 겹치는 변형(zh_Hans/zh_Hant)을 추가했다면 '
            'kLocaleEndonyms 의 키를 toLanguageTag() 축으로 올릴 것.',
      );
    });

    test('등록된 코드는 endonym 을 반환한다', () {
      expect(localeDisplayName(const Locale('ko')), '한국어');
      expect(localeDisplayName(const Locale('en')), 'English');
      expect(localeDisplayName(const Locale('ja')), '日本語');
    });

    test('미지원 코드는 languageCode 자체로 폴백한다', () {
      expect(localeDisplayName(const Locale('fr')), 'fr');
      // 폴백은 Locale 표기 전체가 아니라 languageCode 다 — 'fr_CA' 가 아니다.
      expect(localeDisplayName(const Locale('fr', 'CA')), 'fr');
    });
  });
}
