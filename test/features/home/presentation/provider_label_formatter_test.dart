import 'package:flutter_starter_kit/features/home/presentation/provider_label_formatter.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations_en.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatProviderIds', () {
    final AppLocalizations en = AppLocalizationsEn();

    test('빈 리스트는 "-" fallback', () {
      expect(formatProviderIds(const <String>[], en), '-');
    });

    test('password 단일 → Email/Password 라벨', () {
      expect(
        formatProviderIds(const ['password'], en),
        en.authAccountProviderEmailPassword,
      );
    });

    test('google.com 단일 → Google 라벨', () {
      expect(
        formatProviderIds(const ['google.com'], en),
        en.authAccountProviderGoogle,
      );
    });

    test('apple.com 단일 → Apple 라벨 (Phase 8)', () {
      expect(
        formatProviderIds(const ['apple.com'], en),
        en.authAccountProviderApple,
      );
    });

    test('facebook.com 단일 → Facebook 라벨 (Phase 9)', () {
      expect(
        formatProviderIds(const ['facebook.com'], en),
        en.authAccountProviderFacebook,
      );
    });

    test('미지원 provider 는 raw ID fallback (`_ => id`)', () {
      expect(formatProviderIds(const ['twitter.com'], en), 'twitter.com');
      expect(formatProviderIds(const ['github.com'], en), 'github.com');
    });

    test('다중 매핑 provider 는 ", " 로 결합', () {
      expect(
        formatProviderIds(const ['password', 'google.com'], en),
        '${en.authAccountProviderEmailPassword}, '
        '${en.authAccountProviderGoogle}',
      );
    });

    test('매핑 + 미매핑 혼합 → 각자 변환 후 결합', () {
      expect(
        formatProviderIds(const ['google.com', 'twitter.com'], en),
        '${en.authAccountProviderGoogle}, twitter.com',
      );
    });
  });

  group('kSupportedAuthProviderIds 컨트랙트', () {
    test('Phase 7~9 기준 매핑 set 동등성 — Phase 12~16 신규 provider 추가 시 본 테스트가 '
        '우선 깨져 단위 테스트/fixture 동시 갱신을 강제한다', () {
      expect(
        kSupportedAuthProviderIds,
        equals(<String>{'password', 'google.com', 'apple.com', 'facebook.com'}),
      );
    });
  });
}
