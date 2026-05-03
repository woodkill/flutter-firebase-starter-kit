import 'package:flutter_starter_kit/features/home/presentation/provider_label_formatter.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations_en.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations_ko.dart';
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

  group('formatProviderIds — Kakao 회귀 (Phase 12 D-17)', () {
    final AppLocalizations en = AppLocalizationsEn();
    final AppLocalizations ko = AppLocalizationsKo();

    test('kakao slug 단일 → Kakao 라벨 (en)', () {
      expect(
        formatProviderIds(const ['kakao'], en),
        en.authAccountProviderKakao,
      );
      expect(en.authAccountProviderKakao, 'Kakao');
    });

    test('kakao slug 단일 → 카카오 라벨 (ko)', () {
      expect(
        formatProviderIds(const ['kakao'], ko),
        ko.authAccountProviderKakao,
      );
      expect(ko.authAccountProviderKakao, '카카오');
    });

    test(
      'google.com + kakao 혼합 (Native URI + Custom Token slug 공존, D-16) → '
      '"Google, Kakao" (en)',
      () {
        expect(
          formatProviderIds(const ['google.com', 'kakao'], en),
          '${en.authAccountProviderGoogle}, ${en.authAccountProviderKakao}',
        );
      },
    );

    test(
      'kakao + password 혼합 → provider 순서 보존 + ", " 결합 (en)',
      () {
        expect(
          formatProviderIds(const ['kakao', 'password'], en),
          '${en.authAccountProviderKakao}, '
          '${en.authAccountProviderEmailPassword}',
        );
      },
    );

    test(
      'kakao slug 가 `_ => id` fallback 으로 빠지지 않음 — switch 매핑 회귀 가드',
      () {
        // raw 'kakao' 가 그대로 노출되면 D-17 매핑 누락. 매핑된 값과 raw slug 가
        // 다름을 검증 (en 로케일에서 라벨 == 'Kakao' != 'kakao').
        final formatted = formatProviderIds(const ['kakao'], en);
        expect(formatted, isNot('kakao'));
        expect(formatted, en.authAccountProviderKakao);
      },
    );
  });

  group('kSupportedAuthProviderIds 컨트랙트', () {
    test(
      'Phase 7~9 + Phase 12 (kakao) 기준 매핑 set 동등성 — Phase 13~16 신규 '
      'provider 추가 시 본 테스트가 우선 깨져 단위 테스트/fixture 동시 갱신을 '
      '강제한다',
      () {
        expect(
          kSupportedAuthProviderIds,
          equals(<String>{
            'password',
            'google.com',
            'apple.com',
            'facebook.com',
            'kakao',
          }),
        );
      },
    );

    test('kakao slug 가 set 의 5번째 원소로 등재', () {
      expect(kSupportedAuthProviderIds.contains('kakao'), isTrue);
      expect(kSupportedAuthProviderIds.length, 5);
    });
  });
}
