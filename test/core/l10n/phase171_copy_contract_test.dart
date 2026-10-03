import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

import '../../helpers/source_text.dart';

// Phase 17.1 — see ROADMAP.md (UI-SPEC §Copywriting Q8 LOCK).
// 기대 문자열은 17.1-UI-SPEC.md 「ARB 신설」 표의 셀을 그대로 복사한 상수다.
// 문구를 바꾸려면 sign-off 를 다시 받고 표와 이 상수를 함께 고친다.
// 테마 값 3키는 UI-SPEC 「키 정리 후보」 의 이름 바꿈 결과다 — 기대값은 리터럴로만
// 적는다(이름 바꾸기 전 키는 마지막 사용처와 함께 지워진다).

/// UI-SPEC 「ARB 신설」 표 한 행 — 키 · getter · 3 locale verbatim 문구.
class _CopyRow {
  /// [_CopyRow] 를 만든다.
  const _CopyRow(this.key, this.read, this.ko, this.en, this.ja);

  /// ARB 키 이름.
  final String key;

  /// [AppLocalizations] 에서 이 키의 값을 읽는다.
  final String Function(AppLocalizations l10n) read;

  /// ko 셀.
  final String ko;

  /// en 셀.
  final String en;

  /// ja 셀.
  final String ja;

  /// [languageCode] 에 해당하는 기대 문구를 돌려준다.
  String expectedFor(String languageCode) => switch (languageCode) {
    'ko' => ko,
    'en' => en,
    'ja' => ja,
    _ => throw ArgumentError.value(languageCode, 'languageCode'),
  };
}

/// UI-SPEC 표 14행(표 순서 그대로) + 테마 값 이름 바꿈 3행 = 17행.
final List<_CopyRow> _kPhase171Rows = <_CopyRow>[
  _CopyRow(
    'homeDevGuideTitle',
    (l) => l.homeDevGuideTitle,
    '이 본문을 앱 홈으로 바꾸세요',
    "Replace this with your app's home",
    'この本文をアプリのホームに置き換えてください',
  ),
  _CopyRow(
    'homeDevGuideBody',
    (l) => l.homeDevGuideBody,
    'home_body.dart 만 고치면 돼요. 이 안내와 데모 화면은 release 빌드에 없어요.',
    'Edit only home_body.dart. This note and the demo screen '
        "don't appear in release builds.",
    'home_body.dart だけを編集してください。'
        'この案内とデモ画面はリリースビルドには表示されません。',
  ),
  _CopyRow(
    'homeDevGuideOpenDemo',
    (l) => l.homeDevGuideOpenDemo,
    '데모 화면 열기',
    'Open demo screen',
    'デモ画面を開く',
  ),
  _CopyRow(
    'demoScreenTitle',
    (l) => l.demoScreenTitle,
    '개발자 · 데모 화면',
    'Developer demo screen',
    '開発者・デモ画面',
  ),
  _CopyRow(
    'settingsDemoScreenSubtitle',
    (l) => l.settingsDemoScreenSubtitle,
    'release 빌드에서는 보이지 않습니다.',
    'Hidden in release builds.',
    'リリースビルドでは表示されません。',
  ),
  _CopyRow(
    'settingsGeneralSection',
    (l) => l.settingsGeneralSection,
    '일반',
    'General',
    '一般',
  ),
  _CopyRow(
    'settingsDeveloperSection',
    (l) => l.settingsDeveloperSection,
    '개발자',
    'Developer',
    '開発者',
  ),
  _CopyRow('settingsTheme', (l) => l.settingsTheme, '테마', 'Theme', 'テーマ'),
  _CopyRow(
    'settingsLanguage',
    (l) => l.settingsLanguage,
    '언어',
    'Language',
    '言語',
  ),
  _CopyRow(
    'settingsGuestLabel',
    (l) => l.settingsGuestLabel,
    '게스트로 이용 중',
    'Using as a guest',
    'ゲストとして利用中',
  ),
  _CopyRow(
    'settingsSignInOrSignUp',
    (l) => l.settingsSignInOrSignUp,
    '로그인 · 가입',
    'Sign in or sign up',
    'ログイン・登録',
  ),
  _CopyRow(
    'accountProfileSection',
    (l) => l.accountProfileSection,
    '프로필',
    'Profile',
    'プロフィール',
  ),
  _CopyRow(
    'accountSignInMethodsSection',
    (l) => l.accountSignInMethodsSection,
    '로그인 수단',
    'Sign-in methods',
    'ログイン方法',
  ),
  _CopyRow(
    'demoAccountDebugSection',
    (l) => l.demoAccountDebugSection,
    '계정 디버그 정보',
    'Account debug info',
    'アカウントのデバッグ情報',
  ),
  _CopyRow(
    'settingsThemeSystem',
    (l) => l.settingsThemeSystem,
    '시스템',
    'System',
    'システム',
  ),
  _CopyRow(
    'settingsThemeLight',
    (l) => l.settingsThemeLight,
    '라이트',
    'Light',
    'ライト',
  ),
  _CopyRow(
    'settingsThemeDark',
    (l) => l.settingsThemeDark,
    '다크',
    'Dark',
    'ダーク',
  ),
];

/// 테스트가 대조하는 3 locale.
const List<String> _kLocales = <String>['ko', 'en', 'ja'];

/// 새 문구에 나오면 안 되는 낱말 — `@` · URL · 문의 채널 · ICU placeholder.
const List<String> _kForbiddenFragments = <String>[
  '@',
  'http',
  '고객센터',
  '문의',
  'support',
  'contact',
  'お問い合わせ',
  '{',
];

void main() {
  group('Phase 17.1 새 문구 계약 (T-171-L10N)', () {
    test('T-171-L10N-01: ARB 17키가 ko · en · ja 모두 UI-SPEC 셀과 verbatim 같다', () {
      // 양성 대조 — 표가 17행 전부를 담고 있고 키 중복이 없다.
      expect(_kPhase171Rows, hasLength(17));
      expect(_kPhase171Rows.map((r) => r.key).toSet(), hasLength(17));

      for (final code in _kLocales) {
        final l10n = lookupAppLocalizations(Locale(code));
        for (final row in _kPhase171Rows) {
          expect(
            row.read(l10n),
            row.expectedFor(code),
            reason: '${row.key} ($code)',
          );
        }
      }
    });

    test('T-171-L10N-02: 17키 값에 @ · URL · 문의 채널 · placeholder 가 없다', () {
      // 양성 대조를 먼저 — 검사 대상이 17키 × 3 locale 전부임을 확인한다.
      final values = <String>[
        for (final code in _kLocales)
          for (final row in _kPhase171Rows)
            row.read(lookupAppLocalizations(Locale(code))),
      ];
      expect(values, hasLength(17 * _kLocales.length));
      expect(values.where((v) => v.isNotEmpty), hasLength(values.length));

      for (final value in values) {
        for (final fragment in _kForbiddenFragments) {
          expect(
            value.contains(fragment),
            isFalse,
            reason: '"$value" 에 "$fragment" 가 있다',
          );
        }
      }
    });

    test('T-171-L10N-03: en ARB 의 17키 description 에 Phase 17.1 D-NN 이 있다', () {
      final arb =
          jsonDecode(readTrackedFile('lib/l10n/app_en.arb'))
              as Map<String, dynamic>;

      for (final row in _kPhase171Rows) {
        expect(arb.containsKey(row.key), isTrue, reason: row.key);
        final meta = arb['@${row.key}'];
        expect(meta, isA<Map<String, dynamic>>(), reason: '@${row.key}');
        final description = (meta as Map<String, dynamic>)['description'];
        expect(description, isA<String>(), reason: '@${row.key}.description');
        expect(
          description as String,
          contains('Phase 17.1 D-'),
          reason: '@${row.key}.description',
        );
      }
    });
  });
}
