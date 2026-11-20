// 사진 없는 기본 아바타의 사람 아이콘과 원 바탕이 한 역할 묶음
// (onPrimaryContainer · primaryContainer)으로 그려지는지 고정한다.
// 아이콘 색은 Icon 이 칠하는 글리프(RichText)의 색으로 읽는다 — 감싸는
// IconTheme 은 아이콘 자체 색 인자를 반영하지 않아 실제 색을 못 본다.
// 킷 기본 테마는 사용자 색 역할 자리를 거치므로 내 팔레트에서 아이콘이 안
// 보이면 대비 단언이 실패해 알려 준다. 밝은 강조 바탕 팔레트는 primaryContainer
// 짝 묶음만 바꿔 그 묶음과 다른 역할이 갈라질 때를 본다.

import 'package:flutter/material.dart';
import 'package:flutter_starter_kit/core/theme/app_color_scheme_slot.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/settings/presentation/_widgets/profile_avatar.dart';
import 'package:flutter_test/flutter_test.dart';

/// 밝은 강조 바탕 — 시드 팔레트의 primaryContainer 자리에 넣는 색.
const Color _brightContainer = Color(0xFFF2B134);

/// 밝은 강조 바탕 위 진한 글자 — onPrimaryContainer 자리에 넣는 색.
const Color _ink = Color(0xFF2B2B2B);

/// 일반 글자 대비 기준(WCAG AA).
const double _minContrast = 4.5;

/// 사진이 있는 경우에 쓰는 합성 사진 URL.
const String _photoUrl = 'https://example.com/avatar.jpg';

/// 받은 팔레트에서 primaryContainer 짝 묶음만 밝은 바탕 · 진한 글자로 바꾼다.
ColorScheme _brightContainerScheme(AppColorSchemeInput input) => input.scheme
    .copyWith(primaryContainer: _brightContainer, onPrimaryContainer: _ink);

/// [color] 를 `#aarrggbb` 소문자 16진 문자열로 돌려준다.
String _hex(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0')}';

/// 두 색의 대비비 `(밝은 쪽 휘도 + 0.05) / (어두운 쪽 휘도 + 0.05)` 를 돌려준다.
double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return la > lb ? (la + 0.05) / (lb + 0.05) : (lb + 0.05) / (la + 0.05);
}

/// [theme] 으로 [ProfileAvatar] 하나를 그리고 애니메이션이 끝날 때까지 기다린다.
Future<void> _pumpAvatar(
  WidgetTester tester,
  ThemeData theme, {
  String? photoUrl,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Center(child: ProfileAvatar(photoUrl: photoUrl)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 사람 아이콘이 실제로 칠하는 글리프 색을 읽는다.
///
/// 감싸는 IconTheme 은 아이콘 자체 색 인자를 반영하지 않으므로 실제로 칠하는
/// span 색을 읽는다 — [Icon] 아래 [RichText] 의 글자 style 색이다.
Color _readGlyphColor(WidgetTester tester) {
  final glyph = find.descendant(
    of: find.byIcon(Icons.person),
    matching: find.byType(RichText),
  );
  expect(glyph, findsOneWidget);
  final color = tester.widget<RichText>(glyph).text.style?.color;
  if (color == null) {
    fail('사람 아이콘 글리프에 색이 없다');
  }
  return color;
}

/// 아바타 원 바탕색을 읽는다 — 아바타 안 [AnimatedContainer] 의 장식 색이다.
Color _readBackgroundColor(WidgetTester tester) {
  final container = find.descendant(
    of: find.byType(ProfileAvatar),
    matching: find.byType(AnimatedContainer),
  );
  expect(container, findsOneWidget);
  return switch (tester.widget<AnimatedContainer>(container).decoration) {
    BoxDecoration(:final color?) => color,
    _ => fail('아바타 원 바탕에 색이 없다'),
  };
}

void main() {
  final themes = <String, ThemeData>{
    '킷 라이트': AppTheme.light(),
    '킷 다크': AppTheme.dark(),
    '킷 라이트 고대비': AppTheme.light(contrastLevel: 1),
    '킷 다크 고대비': AppTheme.dark(contrastLevel: 1),
    '밝은 강조 바탕 라이트': AppTheme.light(colorSchemeBuilder: _brightContainerScheme),
    '밝은 강조 바탕 다크': AppTheme.dark(colorSchemeBuilder: _brightContainerScheme),
  };

  group('ProfileAvatar 기본 아바타 색 역할', () {
    for (final MapEntry(key: name, value: theme) in themes.entries) {
      testWidgets('$name — 사진이 없으면 아이콘 · 바탕이 한 역할 묶음', (tester) async {
        await _pumpAvatar(tester, theme);
        final scheme = theme.colorScheme;
        final glyph = _readGlyphColor(tester);
        final background = _readBackgroundColor(tester);

        expect(
          _hex(glyph),
          _hex(scheme.onPrimaryContainer),
          reason: '아이콘 글리프 색이 바탕의 짝 onPrimaryContainer 와 다르다',
        );
        expect(
          _hex(background),
          _hex(scheme.primaryContainer),
          reason: '원 바탕색이 primaryContainer 와 다르다',
        );
        expect(
          _contrastRatio(glyph, background),
          greaterThanOrEqualTo(_minContrast),
          reason: '아이콘 · 바탕 대비가 4.5 보다 낮다',
        );
      });
    }

    testWidgets('사진이 있으면 사람 아이콘을 그리지 않는다', (tester) async {
      await _pumpAvatar(tester, AppTheme.light(), photoUrl: _photoUrl);

      expect(
        find.byIcon(Icons.person),
        findsNothing,
        reason: '사진이 있는데 사람 아이콘을 그렸다',
      );
      expect(tester.takeException(), isNull);
    });
  });
}
