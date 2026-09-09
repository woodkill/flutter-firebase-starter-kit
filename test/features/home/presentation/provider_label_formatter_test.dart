import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/features/home/presentation/provider_label_formatter.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations_en.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations_ja.dart';
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

    test(
      'D-53 미지원 slug → l10n.errorUnknownProvider Localizable Unknown fallback '
      '(raw slug 노출 차단)',
      () {
        // Phase 13 D-53: 기존 `_ => id` raw slug fallback 제거.
        expect(
          formatProviderIds(const ['twitter.com'], en),
          en.errorUnknownProvider,
        );
        expect(
          formatProviderIds(const ['github.com'], en),
          en.errorUnknownProvider,
        );
        // raw slug 가 그대로 노출되지 않는지 검증 (회귀 가드).
        expect(
          formatProviderIds(const ['twitter.com'], en),
          isNot(contains('twitter')),
        );
      },
    );

    test('다중 매핑 provider 는 ", " 로 결합', () {
      expect(
        formatProviderIds(const ['password', 'google.com'], en),
        '${en.authAccountProviderEmailPassword}, '
        '${en.authAccountProviderGoogle}',
      );
    });

    test('매핑 + 미매핑 혼합 → 각자 변환 후 결합 (D-53 — Unknown Localizable)', () {
      expect(
        formatProviderIds(const ['google.com', 'twitter.com'], en),
        '${en.authAccountProviderGoogle}, ${en.errorUnknownProvider}',
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

    test('google.com + kakao 혼합 (Native URI + Custom Token slug 공존, D-16) → '
        '"Google, Kakao" (en)', () {
      expect(
        formatProviderIds(const ['google.com', 'kakao'], en),
        '${en.authAccountProviderGoogle}, ${en.authAccountProviderKakao}',
      );
    });

    test('kakao + password 혼합 → provider 순서 보존 + ", " 결합 (en)', () {
      expect(
        formatProviderIds(const ['kakao', 'password'], en),
        '${en.authAccountProviderKakao}, '
        '${en.authAccountProviderEmailPassword}',
      );
    });

    test('kakao slug 가 Localizable Unknown fallback 으로 빠지지 않음 — switch '
        '매핑 회귀 가드', () {
      // raw 'kakao' 가 그대로 노출되면 D-17 매핑 누락. 매핑된 값과 raw slug
      // 가 다름을 검증 (en 로케일에서 라벨 == 'Kakao' != 'kakao').
      final formatted = formatProviderIds(const ['kakao'], en);
      expect(formatted, isNot('kakao'));
      expect(formatted, isNot(en.errorUnknownProvider));
      expect(formatted, en.authAccountProviderKakao);
    });
  });

  group('formatProviderIds D-53 일반화 (T-13-FORMATTER)', () {
    final AppLocalizations en = AppLocalizationsEn();
    final AppLocalizations ko = AppLocalizationsKo();
    final AppLocalizations ja = AppLocalizationsJa();

    test('T-13-FORMATTER-EXISTING-01: 기존 5 매핑 회귀 0 (password / google.com / '
        'apple.com / facebook.com / kakao)', () {
      expect(
        formatProviderIds(const ['password'], ko),
        ko.authAccountProviderEmailPassword,
      );
      expect(formatProviderIds(const ['google.com'], en), 'Google');
      expect(formatProviderIds(const ['apple.com'], en), 'Apple');
      expect(formatProviderIds(const ['facebook.com'], en), 'Facebook');
      expect(formatProviderIds(const ['kakao'], ko), '카카오');
    });

    test('T-13-FORMATTER-NEW-01: 신규 3 매핑 (naver / line / yahoojp)', () {
      // ko
      expect(formatProviderIds(const [kProviderIdNaver], ko), '네이버');
      expect(formatProviderIds(const [kProviderIdLine], ko), '라인');
      expect(formatProviderIds(const [kProviderIdYahooJp], ko), 'Yahoo! JAPAN');
      // en
      expect(formatProviderIds(const [kProviderIdNaver], en), 'Naver');
      expect(formatProviderIds(const [kProviderIdLine], en), 'LINE');
      // ja
      expect(formatProviderIds(const [kProviderIdNaver], ja), 'ネイバー');
    });

    test('T-13-FORMATTER-UNKNOWN-01: 매핑되지 않은 slug → l10n.errorUnknownProvider '
        '(raw slug 미노출)', () {
      expect(
        formatProviderIds(const ['unknown_slug_xyz'], ko),
        '알 수 없는 로그인 수단',
      );
      // raw slug 부재 검증 (D-53 정책).
      expect(
        formatProviderIds(const ['unknown_slug_xyz'], ko),
        isNot(contains('unknown_slug_xyz')),
      );
      expect(
        formatProviderIds(const ['unknown_slug_xyz'], en),
        'Unknown sign-in method',
      );
      expect(formatProviderIds(const ['unknown_slug_xyz'], ja), '不明なログイン方法');
    });

    test('T-13-FORMATTER-ASSERT-01: kDebugMode assert — kAllProviderIds 모두 '
        'switch 에 매핑 (assert 자체는 throw 없이 통과)', () {
      // D-53 의 assert 는 kAllProviderIds 의 모든 slug 가 switch 의 knownIds
      // set 에 포함되는지 검증한다 (knownIds = google/apple/facebook/kakao/
      // naver/line/yahoojp 7개 — kAllProviderIds 와 정확히 같은 set).
      // assert 자체가 throw 없이 통과하면 contract drift 없음.
      expect(
        () => formatProviderIds(const [kProviderIdNaver], en),
        returnsNormally,
      );
      // Custom Token slug 4개는 모두 switch 에 매핑되어 Localizable Unknown
      // 으로 떨어지지 않는다 (kakao/naver/line/yahoojp).
      const customTokenSlugs = <String>[
        kProviderIdKakao,
        kProviderIdNaver,
        kProviderIdLine,
        kProviderIdYahooJp,
      ];
      for (final id in customTokenSlugs) {
        final formatted = formatProviderIds(<String>[id], en);
        expect(
          formatted,
          isNot(en.errorUnknownProvider),
          reason: 'Custom Token slug $id 가 switch 에 매핑되지 않음 (D-53)',
        );
        expect(
          formatted,
          isNot(id),
          reason: 'Custom Token slug $id 가 raw 그대로 노출됨 (D-53 위반)',
        );
      }
    });

    test('T-13-FORMATTER-COMPOSITE-01: 복수 provider — 콤마+공백 연결', () {
      expect(
        formatProviderIds(const ['google.com', kProviderIdNaver], ko),
        'Google, 네이버',
      );
      expect(
        formatProviderIds(const [
          'password',
          kProviderIdKakao,
          kProviderIdNaver,
        ], ko),
        '이메일 / 비밀번호, 카카오, 네이버',
      );
    });

    test('T-13-FORMATTER-EMPTY-01: 빈 리스트 → "-"', () {
      expect(formatProviderIds(const <String>[], en), '-');
    });
  });

  group('kSupportedAuthProviderIds 컨트랙트 (Phase 13 D-53 갱신)', () {
    test('Phase 7~9 (4 native URI) + Phase 12 (kakao) + Phase 13 (naver) + '
        'Phase 14~15 사전 등재 (line/yahoojp) — 총 8 IDs', () {
      expect(
        kSupportedAuthProviderIds,
        equals(<String>{
          // Native URI
          'password',
          'google.com',
          'apple.com',
          'facebook.com',
          // Custom Token slug
          kProviderIdKakao,
          kProviderIdNaver,
          kProviderIdLine,
          kProviderIdYahooJp,
        }),
      );
    });

    test('naver slug 가 set 에 등재 (Phase 13) + 총 8 원소 (Phase 14~15 사전 등재)', () {
      expect(kSupportedAuthProviderIds.contains(kProviderIdNaver), isTrue);
      expect(kSupportedAuthProviderIds.contains(kProviderIdLine), isTrue);
      expect(kSupportedAuthProviderIds.contains(kProviderIdYahooJp), isTrue);
      expect(kSupportedAuthProviderIds.length, 8);
    });
  });
}
