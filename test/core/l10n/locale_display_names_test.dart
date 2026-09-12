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

    test('등록된 코드는 endonym 을 반환한다', () {
      expect(localeDisplayName(const Locale('ko')), '한국어');
      expect(localeDisplayName(const Locale('en')), 'English');
      expect(localeDisplayName(const Locale('ja')), '日本語');
    });

    test('미지원 코드는 코드 자체로 폴백한다', () {
      expect(localeDisplayName(const Locale('fr')), 'fr');
    });
  });
}
