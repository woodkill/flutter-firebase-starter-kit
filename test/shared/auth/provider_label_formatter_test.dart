import 'package:flutter/widgets.dart';
import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/features/auth/domain/user.dart';
import 'package:flutter_starter_kit/shared/auth/provider_label_formatter.dart';
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

    test('T-13-FORMATTER-NEW-01: 신규 2 매핑 (naver / line)', () {
      // ko
      expect(formatProviderIds(const [kProviderIdNaver], ko), '네이버');
      expect(formatProviderIds(const [kProviderIdLine], ko), '라인');
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
      // naver/line 6개 — kAllProviderIds 와 정확히 같은 set).
      // assert 자체가 throw 없이 통과하면 contract drift 없음.
      expect(
        () => formatProviderIds(const [kProviderIdNaver], en),
        returnsNormally,
      );
      // Custom Token slug 3개는 모두 switch 에 매핑되어 Localizable Unknown
      // 으로 떨어지지 않는다 (kakao/naver/line).
      const customTokenSlugs = <String>[
        kProviderIdKakao,
        kProviderIdNaver,
        kProviderIdLine,
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
        'Phase 14 사전 등재 (line) — 총 7 IDs', () {
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
        }),
      );
    });

    test('naver slug 가 set 에 등재 (Phase 13) + 총 7 원소 (Phase 14 사전 등재)', () {
      expect(kSupportedAuthProviderIds.contains(kProviderIdNaver), isTrue);
      expect(kSupportedAuthProviderIds.contains(kProviderIdLine), isTrue);
      expect(kSupportedAuthProviderIds.length, 7);
    });
  });

  group('Phase 16.7 표시 helper (D-04 · D-05 · D-11 · D-12)', () {
    final AppLocalizations en = AppLocalizationsEn();
    final AppLocalizations ko = AppLocalizationsKo();
    final AppLocalizations ja = AppLocalizationsJa();

    // 사용자가 보유할 수 있는 provider 전부 — native URI 와 CT slug 혼합,
    // kAllProviderIds 순서와 일부러 다르게 섞었다.
    const mixedIds = <String>[
      'password',
      kProviderIdLine,
      'google.com',
      kProviderIdKakao,
      'apple.com',
      kProviderIdNaver,
      'facebook.com',
    ];

    // D-05 표시 순서 — kAllProviderIds 순 소셜 + 이메일 맨 끝.
    const orderedIds = <String>[
      'google.com',
      'apple.com',
      'facebook.com',
      kProviderIdKakao,
      kProviderIdNaver,
      kProviderIdLine,
      'password',
    ];

    test('H1 formatProviderLabels — 기존 switch 매핑 · 미지 = Unknown', () {
      for (final l10n in <AppLocalizations>[en, ko, ja]) {
        expect(
          formatProviderLabels(const <String>[
            'password',
            'google.com',
            'apple.com',
            'facebook.com',
            kProviderIdKakao,
            kProviderIdNaver,
            kProviderIdLine,
            'zzz_unknown_slug',
          ], l10n),
          <String>[
            l10n.authAccountProviderEmailPassword,
            l10n.authAccountProviderGoogle,
            l10n.authAccountProviderApple,
            l10n.authAccountProviderFacebook,
            l10n.authAccountProviderKakao,
            l10n.authAccountProviderNaver,
            l10n.authAccountProviderLine,
            l10n.errorUnknownProvider,
          ],
        );
      }
      // raw providerId 가 라벨에 섞이지 않는다 (D-12 · D-53).
      final labels = formatProviderLabels(const <String>[
        'zzz_unknown_slug',
        kProviderIdKakao,
        'google.com',
      ], en);
      expect(labels.join(', '), isNot(contains('zzz_unknown_slug')));
      expect(labels, isNot(contains(kProviderIdKakao)));
      expect(labels, isNot(contains('google.com')));
      expect(formatProviderLabels(const <String>[], en), isEmpty);
    });

    test('H2 formatProviderIds — 결과 불변 (빈 = "-" · ", " 결합)', () {
      expect(formatProviderIds(const <String>[], ko), '-');
      for (final l10n in <AppLocalizations>[en, ko, ja]) {
        expect(
          formatProviderIds(mixedIds, l10n),
          formatProviderLabels(mixedIds, l10n).join(', '),
        );
      }
      expect(
        formatProviderIds(const <String>['kakao', 'password'], ko),
        '카카오, 이메일 / 비밀번호',
      );
    });

    test('H3 orderForDisplay — URI · slug 혼합 → kAllProviderIds 순 + 이메일 끝', () {
      expect(orderForDisplay(mixedIds), orderedIds);
      // 입력을 바꾸지 않는다.
      expect(mixedIds.first, 'password');
    });

    test('H4 orderForDisplay — 미지 값은 소셜 뒤 · 이메일 앞 · 입력 순', () {
      expect(
        orderForDisplay(const <String>[
          'password',
          'zzz',
          kProviderIdLine,
          'aaa',
          'google.com',
        ]),
        <String>['google.com', kProviderIdLine, 'zzz', 'aaa', 'password'],
      );
      // rank 가 같은 원소만 있으면 입력 순서 그대로 (안정 정렬).
      expect(orderForDisplay(const <String>['zzz', 'aaa', 'mmm']), <String>[
        'zzz',
        'aaa',
        'mmm',
      ]);
    });

    test('H5 splitAccountProviders — 기록 X · 보유 {X, Y, Z} → (X, [Y, Z])', () {
      final split = splitAccountProviders(
        _userWith(
          providerIds: const <String>[
            'password',
            kProviderIdKakao,
            'google.com',
          ],
          signUpProviderId: kProviderIdKakao,
        ),
      );
      expect(split.signUpProviderId, kProviderIdKakao);
      expect(split.linkedProviderIds, <String>['google.com', 'password']);
    });

    test('H6 splitAccountProviders — 기록 ∉ 보유 · 유일 보유 · 중복', () {
      // 기록 X ∉ 보유 → 기록값 그대로 + 연결 = 보유 전부 (D-12).
      final notOwned = splitAccountProviders(
        _userWith(
          providerIds: const <String>['password', 'google.com'],
          signUpProviderId: kProviderIdNaver,
        ),
      );
      expect(notOwned.signUpProviderId, kProviderIdNaver);
      expect(notOwned.linkedProviderIds, <String>['google.com', 'password']);

      // 기록이 유일한 보유 → 연결 0개.
      final onlyOwned = splitAccountProviders(
        _userWith(
          providerIds: const <String>['google.com'],
          signUpProviderId: 'google.com',
        ),
      );
      expect(onlyOwned.signUpProviderId, 'google.com');
      expect(onlyOwned.linkedProviderIds, isEmpty);

      // 같은 값이 둘 이상이면 전부 빠지고 나머지는 보존된다.
      final duplicated = splitAccountProviders(
        _userWith(
          providerIds: const <String>[
            kProviderIdKakao,
            kProviderIdLine,
            kProviderIdKakao,
          ],
          signUpProviderId: kProviderIdKakao,
        ),
      );
      expect(duplicated.linkedProviderIds, <String>[kProviderIdLine]);
    });

    test('H7 splitAccountProviders — null · 빈 보유 (기록 유무)', () {
      final guest = splitAccountProviders(null);
      expect(guest.signUpProviderId, isNull);
      expect(guest.linkedProviderIds, isEmpty);

      final emptyNoRecord = splitAccountProviders(_userWith());
      expect(emptyNoRecord.signUpProviderId, isNull);
      expect(emptyNoRecord.linkedProviderIds, isEmpty);

      final emptyWithRecord = splitAccountProviders(
        _userWith(signUpProviderId: kProviderIdLine),
      );
      expect(emptyWithRecord.signUpProviderId, kProviderIdLine);
      expect(emptyWithRecord.linkedProviderIds, isEmpty);
    });

    test('H8 splitAccountProviders — 기록 null 이면 추론 0 · 보유 전부 정렬', () {
      final split = splitAccountProviders(_userWith(providerIds: mixedIds));
      // 첫 원소 · 단일 원소 등에서 가입 수단을 추론하지 않는다 (D-11).
      expect(split.signUpProviderId, isNull);
      expect(split.linkedProviderIds, orderedIds);

      final single = splitAccountProviders(
        _userWith(providerIds: const <String>['google.com']),
      );
      expect(single.signUpProviderId, isNull);
      expect(single.linkedProviderIds, <String>['google.com']);
    });

    test('H9 buildLinkedAccountsValue — 0개 = TextSpan(none)', () {
      final value = buildLinkedAccountsValue(
        const <String>[],
        none: ko.authAccountLinkedAccountsNone,
      );
      expect(value.semantics, ko.authAccountLinkedAccountsNone);
      final display = value.display;
      expect(display, isA<TextSpan>());
      expect((display as TextSpan).text, ko.authAccountLinkedAccountsNone);
      // 자식 span 이 없으므로 WidgetSpan 0.
      expect(display.children, isNull);
      expect(_widgetSpansOf(display), isEmpty);
    });

    test('H10 buildLinkedAccountsValue — 1개 = WidgetSpan 1 · 쉼표 0', () {
      final value = buildLinkedAccountsValue(<String>[
        ko.authAccountProviderKakao,
      ], none: ko.authAccountLinkedAccountsNone);
      final widgetSpans = _widgetSpansOf(value.display);
      expect(widgetSpans, hasLength(1));
      expect(
        _itemTextsOf(widgetSpans).single.data,
        ko.authAccountProviderKakao,
      );
      expect(_itemTextsOf(widgetSpans).single.data, isNot(contains(',')));
      expect(_separatorSpansOf(value.display), isEmpty);
      expect(value.semantics, ko.authAccountProviderKakao);
    });

    test('H11 buildLinkedAccountsValue — N개 span 트리 (baseline · 쉼표)', () {
      const style = TextStyle(fontSize: 14);
      final labels = formatProviderLabels(orderedIds, ko);
      final value = buildLinkedAccountsValue(
        labels,
        none: ko.authAccountLinkedAccountsNone,
        style: style,
      );
      final widgetSpans = _widgetSpansOf(value.display);
      expect(widgetSpans, hasLength(labels.length));
      for (final span in widgetSpans) {
        expect(span.alignment, PlaceholderAlignment.baseline);
        expect(span.baseline, TextBaseline.alphabetic);
      }
      final texts = _itemTextsOf(widgetSpans);
      expect(texts, hasLength(labels.length));
      for (var i = 0; i < labels.length; i++) {
        final isLast = i == labels.length - 1;
        expect(texts[i].data, isLast ? labels[i] : '${labels[i]},');
        expect(texts[i].style, style);
      }
      final separators = _separatorSpansOf(value.display);
      expect(separators, hasLength(labels.length - 1));
      for (final separator in separators) {
        expect(separator.text, ' ');
      }
    });

    test('H12 buildLinkedAccountsValue — semantics 무오염 · 표시만 U+FFFC', () {
      for (final l10n in <AppLocalizations>[en, ko, ja]) {
        final labels = formatProviderLabels(orderedIds, l10n);
        final value = buildLinkedAccountsValue(
          labels,
          none: l10n.authAccountLinkedAccountsNone,
        );
        expect(value.semantics, labels.join(', '));
        expect(value.semantics, isNot(contains('\uFFFC')));
        expect(value.semantics, isNot(contains('\u2060')));
        expect(value.semantics, isNot(contains('\u00A0')));
        // WidgetSpan 자리표시 — find.text 가 전체 목록과 맞지 않는 근거.
        expect(value.display.toPlainText(), contains('\uFFFC'));
      }
    });
  });
}

/// [providerIds] · [signUpProviderId] 를 가진 정식 사용자 도메인 모델.
User _userWith({
  List<String> providerIds = const <String>[],
  String? signUpProviderId,
}) => User(
  uid: 'uid-16-7-04',
  email: 'user@example.com',
  emailVerified: true,
  createdAt: DateTime.utc(2026, 9, 26),
  providerIds: providerIds,
  signUpProviderId: signUpProviderId,
);

/// [display] 의 직계 자식 중 [WidgetSpan] 만 순서대로 모은다.
List<WidgetSpan> _widgetSpansOf(InlineSpan display) => switch (display) {
  TextSpan(:final children?) => children.whereType<WidgetSpan>().toList(),
  _ => const <WidgetSpan>[],
};

/// [display] 의 직계 자식 중 라벨 사이 구분 [TextSpan] 만 순서대로 모은다.
List<TextSpan> _separatorSpansOf(InlineSpan display) => switch (display) {
  TextSpan(:final children?) => children.whereType<TextSpan>().toList(),
  _ => const <TextSpan>[],
};

/// [widgetSpans] 각각의 child 중 [Text] 만 순서대로 모은다.
List<Text> _itemTextsOf(List<WidgetSpan> widgetSpans) => <Text>[
  for (final span in widgetSpans)
    if (span.child case final Text text) text,
];
