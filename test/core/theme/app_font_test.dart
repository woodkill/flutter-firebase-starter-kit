// 앱 글꼴(테마 글꼴) 계약 시험.
//
// - M3V-FONT-01 테마 연결: `AppTheme.light()` · `dark()` 의 `textTheme` ·
//   `primaryTextTheme` 15 스타일이 모두 `AppTheme.fontFamily` 이고 대체 글꼴
//   목록 · 글꼴 기능 목록이 없다. ja · ko 로 localize 된 테마에서도 같다.
// - M3V-FONT-02 파일 · pubspec 선언: 글꼴 파일과 라이선스 파일의 크기 · sha256 이
//   고정값과 같고, pubspec 이 그 family 를 weight 줄 없이 선언한다.
// - M3V-FONT-03 하네스 등록: `loadAppFont()` 가 글꼴을 실제로 등록한다(등록 안 된
//   family 와 잰 폭이 다르다).

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_font.dart';
import '../../helpers/source_text.dart';

/// 앱 글꼴 파일의 크기(bytes) — 글꼴을 바꾸면 이 값을 고친다(`wc -c`).
const int _fontFileBytes = 13087888;

/// 앱 글꼴 파일의 sha256 — 글꼴을 바꾸면 이 값을 고친다(`shasum -a 256`).
const String _fontFileSha256 =
    'bc1d77db0f3cb9c20986b8939aa8a28d5216552d777d082955da22f420535cbb';

/// 앱 글꼴 라이선스 파일 경로 — 글꼴을 바꾸면 이 값을 고친다.
const String _licenseFilePath = 'assets/fonts/pretendard-jp/OFL.txt';

/// 앱 글꼴 라이선스 파일의 크기(bytes) — 글꼴을 바꾸면 이 값을 고친다.
const int _licenseFileBytes = 4418;

/// 앱 글꼴 라이선스 파일의 sha256 — 글꼴을 바꾸면 이 값을 고친다.
const String _licenseFileSha256 =
    'd31ddd9f2bed32fd7e302a205cf2380ba0de6529152d239ef99cfb6f261bfc04';

/// pubspec 에서 family 선언 → `fonts:` → asset 한 줄이 이어지고 바로 다음 줄이
/// weight 가 아닌 꼴을 찾는 RegExp 를 만든다.
RegExp _buildFamilyDeclarationPattern(String family, String assetPath) =>
    RegExp(
      <String>[
        r'-\s*family:\s*',
        RegExp.escape(family),
        r'\s*\n\s*fonts:\s*\n\s*-\s*asset:\s*',
        RegExp.escape(assetPath),
        r'\s*\n(?!\s*weight:)',
      ].join(),
    );

/// [theme] 의 display · headline · title · body · label × Large · Medium ·
/// Small 15 스타일을 모은다.
List<TextStyle?> _collectTextStyles(TextTheme theme) => <TextStyle?>[
  theme.displayLarge,
  theme.displayMedium,
  theme.displaySmall,
  theme.headlineLarge,
  theme.headlineMedium,
  theme.headlineSmall,
  theme.titleLarge,
  theme.titleMedium,
  theme.titleSmall,
  theme.bodyLarge,
  theme.bodyMedium,
  theme.bodySmall,
  theme.labelLarge,
  theme.labelMedium,
  theme.labelSmall,
];

/// [style] 이 앱 글꼴만 쓰고 대체 목록 · 글꼴 기능 목록이 없는지 단언한다.
void _expectAppFontOnly(TextStyle? style, String reason) {
  expect(style, isNotNull, reason: reason);
  expect(style!.fontFamily, AppTheme.fontFamily, reason: reason);
  expect(style.fontFamilyFallback, isNull, reason: reason);
  expect(style.fontFeatures, isNull, reason: reason);
}

/// [text] 를 [family] 20px 로 한 줄 배치했을 때의 폭을 잰다.
double _measureTextWidth(String text, String family) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(fontFamily: family, fontSize: 20),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// [locale] 로 localize 된 테마의 `bodyMedium` 을 읽는다.
Future<TextStyle?> _readLocalizedBodyMedium(
  WidgetTester tester,
  Locale locale,
) async {
  TextStyle? captured;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) {
            captured = Theme.of(context).textTheme.bodyMedium;
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return captured;
}

void main() {
  group('앱 글꼴 계약', () {
    test('M3V-FONT-01 테마 15 스타일이 앱 글꼴만 쓴다', () {
      expect(AppTheme.fontFamily, 'PretendardJP');
      final themes = <String, ThemeData>{
        'light': AppTheme.light(),
        'dark': AppTheme.dark(),
      };
      for (final MapEntry(key: name, value: theme) in themes.entries) {
        final styles = <String, List<TextStyle?>>{
          'textTheme': _collectTextStyles(theme.textTheme),
          'primaryTextTheme': _collectTextStyles(theme.primaryTextTheme),
        };
        for (final MapEntry(key: group, value: list) in styles.entries) {
          expect(list, hasLength(15));
          for (var i = 0; i < list.length; i++) {
            _expectAppFontOnly(list[i], '$name $group #$i');
          }
        }
      }

      // 양성 대조: 맨 ThemeData 는 앱 글꼴을 쓰지 않는다 — 검사가 공허하지 않다.
      final bare = ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: AppTheme.seedColor),
      );
      expect(bare.textTheme.bodyMedium?.fontFamily, isNot(AppTheme.fontFamily));
    });

    for (final locale in const <Locale>[Locale('ja'), Locale('ko')]) {
      testWidgets(
        'M3V-FONT-01 ${locale.languageCode} 로 localize 된 테마도 앱 글꼴이다',
        (WidgetTester tester) async {
          final style = await _readLocalizedBodyMedium(tester, locale);
          expect(style, isNotNull);
          expect(style!.fontFamily, AppTheme.fontFamily);
          expect(style.fontFamilyFallback, isNull);
          // 양성 대조: localize 가 실제로 적용됐다(ko · ja = dense 기하).
          expect(style.textBaseline, TextBaseline.ideographic);
        },
      );
    }

    test('M3V-FONT-02 글꼴 · 라이선스 파일이 고정값과 같다', () {
      final font = File(kAppFontAssetPath);
      expect(font.existsSync(), isTrue, reason: kAppFontAssetPath);
      final fontBytes = font.readAsBytesSync();
      expect(fontBytes.length, _fontFileBytes);
      expect(sha256.convert(fontBytes).toString(), _fontFileSha256);

      final license = File(_licenseFilePath);
      expect(license.existsSync(), isTrue, reason: _licenseFilePath);
      final licenseBytes = license.readAsBytesSync();
      expect(licenseBytes.length, _licenseFileBytes);
      expect(sha256.convert(licenseBytes).toString(), _licenseFileSha256);
    });

    test('M3V-FONT-02 pubspec 이 앱 글꼴 family 를 weight 줄 없이 선언한다', () {
      final pattern = _buildFamilyDeclarationPattern(
        AppTheme.fontFamily,
        kAppFontAssetPath,
      );
      final pubspec = stripHashComments(readTrackedFile('pubspec.yaml'));
      expect(
        pattern.hasMatch(pubspec),
        isTrue,
        reason:
            'pubspec 에 `- family: ${AppTheme.fontFamily}` → `fonts:` → '
            '`- asset: $kAppFontAssetPath` 선언(weight 줄 없음)이 없다',
      );

      // 양성 대조: 같은 RegExp 가 견본에 맞고, weight 줄을 넣은 견본에는 맞지 않는다.
      const sample =
          '  - family: ${AppTheme.fontFamily}\n'
          '    fonts:\n'
          '      - asset: $kAppFontAssetPath\n'
          '  - family: Other\n';
      expect(pattern.hasMatch(sample), isTrue);
      const weighted =
          '  - family: ${AppTheme.fontFamily}\n'
          '    fonts:\n'
          '      - asset: $kAppFontAssetPath\n'
          '        weight: 400\n';
      expect(pattern.hasMatch(weighted), isFalse);
    });
  });

  group('앱 글꼴 하네스 등록', () {
    setUpAll(loadAppFont);

    test('M3V-FONT-03 loadAppFont 가 글꼴을 실제로 등록한다', () {
      const sample = 'Ag한あ漢';
      final appWidth = _measureTextWidth(sample, AppTheme.fontFamily);
      final unregisteredWidth = _measureTextWidth(
        sample,
        'M3vUnregisteredFamily',
      );
      expect(appWidth, greaterThan(0));
      expect(appWidth, isNot(unregisteredWidth));
    });
  });
}
