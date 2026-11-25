// 약관 묶음([TermsCheckboxGroup])의 큰 글자 배율 · 좁은 폭 회귀 시험.
//
// 고정하는 것: 기기 글자 배율을 크게 하거나 폭이 좁아도 (1) 넘침 · 레이아웃
// assert 가 없고 (2) 세 약관 행의 이름 · 필수/선택 배지 · 제목 링크 상자(이용약관 ·
// 개인정보처리방침 행)가 폭과 높이를 가진 채 타일 가로 범위 안에 있으며 (3) 제목
// 링크 상자는 48 × 48 dp 이상이고 링크 행 이름만 밑줄이며 (4) 배지 글자는 한
// 줄이다(한 줄 폭보다 넓은 배지는 줄여 그린다).
//
// 조건마다 testWidgets 하나 — 한 시험 안에서 다시 pump 하면 넘침 보고가 한 번만
// 나와 예외 0 이 거짓 통과한다.
//
// loadAppFont 는 setUpAll 에서만 부른다 — testWidgets 본문에서 부르면 영원히
// 멈춘다. 실제 글꼴을 올려야 글자 폭이 기기와 같아 넘침이 재현된다. 글꼴 적재는
// 프로세스 전역이라 기존 terms_checkbox_group_test.dart 의 측정을 바꾸지 않게
// 파일을 나눈다.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/onboarding/presentation/_widgets/terms_checkbox_group.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/app_font.dart';
import '../../../helpers/keep_hangul_words_finder.dart';
import '../../../helpers/terms_tile_finder.dart';

/// iPhone SE 의 가장 큰 「더 큰 글자」 배율(기기 로그 재현 값).
const double _iphoneSeScale = 3.1176470588235294;

/// Galaxy 글자 크기 최대 배율(기기 로그 재현 값 · 26sp / 14sp).
const double _galaxyScale = 26 / 14;

/// 온보딩 화면 SingleChildScrollView 의 가로 여백(`spacing.lg`).
const double _screenHorizontalPadding = 16;

/// 위치 · 크기 판정 허용치(dp).
const double _tolerance = 0.5;

/// 시험 조건 — 언어 · 화면 폭(dp) · 글자 배율 · 설명.
typedef _Condition = ({String locale, double width, double scale, String note});

/// 최소 11 조건 — 기기 재현 2 · 지원 최소 폭 280dp 5 · 기준 1 · 360dp 글자 2배 3.
const List<_Condition> _conditions = [
  (locale: 'ko', width: 375, scale: _iphoneSeScale, note: 'iPhone SE 재현'),
  (locale: 'ko', width: 320, scale: _galaxyScale, note: 'Galaxy 재현'),
  (locale: 'ko', width: 280, scale: _iphoneSeScale, note: '최소 폭 · 큰 배율'),
  (locale: 'en', width: 280, scale: _iphoneSeScale, note: '최소 폭 · 큰 배율'),
  (locale: 'ja', width: 280, scale: _iphoneSeScale, note: '최소 폭 · 큰 배율'),
  (locale: 'en', width: 280, scale: 1, note: '최소 폭 · 기본 배율'),
  (locale: 'ja', width: 280, scale: 1, note: '최소 폭 · 기본 배율'),
  (locale: 'ko', width: 360, scale: 1, note: '기준'),
  (locale: 'ko', width: 360, scale: 2, note: '글자 2배'),
  (locale: 'en', width: 360, scale: 2, note: '글자 2배'),
  (locale: 'ja', width: 360, scale: 2, note: '글자 2배'),
];

/// 체크 변경 콜백 자리 — 이 시험은 누르지 않는다.
void _ignoreChange(bool? _) {}

/// 배율을 시험 이름용 문자열로 바꾼다(정수면 소수 한 자리, 아니면 네 자리).
String _formatScale(double scale) => scale == scale.roundToDouble()
    ? scale.toStringAsFixed(1)
    : scale.toStringAsFixed(4);

void main() {
  setUpAll(loadAppFont);

  for (final condition in _conditions) {
    final name =
        '${condition.locale} ${condition.width.toInt()}dp × '
        '${_formatScale(condition.scale)} (${condition.note}) — '
        '넘침 0 · 제목 링크 48dp · 배지 한 줄';
    testWidgets(name, (tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = Size(condition.width, 2400) * 3;
      addTearDown(tester.view.reset);

      final errors = <String>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = (details) =>
          errors.add(details.exceptionAsString().split('\n').first);
      try {
        await tester.pumpWidget(_buildHarness(condition));
        await tester.pump();
      } finally {
        FlutterError.onError = previousOnError;
      }

      final violations = <String>[for (final error in errors) '[error] $error'];
      final l10n = AppLocalizations.of(
        tester.element(find.byType(TermsCheckboxGroup)),
      );
      final rows = <({String label, String badge, bool hasLink})>[
        (label: l10n.termsService, badge: l10n.termsRequired, hasLink: true),
        (label: l10n.termsPrivacy, badge: l10n.termsRequired, hasLink: true),
        (label: l10n.termsMarketing, badge: l10n.termsOptional, hasLink: false),
      ];
      for (var i = 0; i < rows.length; i++) {
        _checkRow(
          tester,
          index: i,
          label: rows[i].label,
          badge: rows[i].badge,
          hasLink: rows[i].hasLink,
          violations: violations,
        );
      }

      expect(violations, isEmpty, reason: violations.join('\n'));
    });
  }
}

/// 온보딩 화면과 같은 꼴(가로 16 여백 스크롤 안)로 약관 묶음을 그리는 하네스를 만든다.
Widget _buildHarness(_Condition condition) {
  return MaterialApp(
    theme: AppTheme.light(),
    locale: Locale(condition.locale),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(condition.scale)),
      child: child!,
    ),
    home: const Scaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: _screenHorizontalPadding),
        child: TermsCheckboxGroup(
          service: false,
          privacy: false,
          marketing: false,
          allChecked: false,
          onServiceChanged: _ignoreChange,
          onPrivacyChanged: _ignoreChange,
          onMarketingChanged: _ignoreChange,
          onAllChanged: _ignoreChange,
        ),
      ),
    ),
  );
}

/// 약관 행 [index](0 이용약관 · 1 개인정보처리방침 · 2 마케팅)를 재고 위반을 [violations] 에 더한다.
void _checkRow(
  WidgetTester tester, {
  required int index,
  required String label,
  required String badge,
  required bool hasLink,
  required List<String> violations,
}) {
  // 0 번 타일은 「전체 동의」 다.
  final tile = findTermsTiles().at(index + 1);
  final tileRect = _readRect(tester, tile, 'r$index tile', violations);
  if (tileRect == null) return;

  final labelFinder = find.descendant(
    of: tile,
    matching: findKeepHangulWordsText(label),
  );
  final badgeTextFinder = find.descendant(
    of: tile,
    matching: findKeepHangulWordsText(badge),
  );
  final linkFinder = findTermsTitleLink(tile);

  final labelCount = labelFinder.evaluate().length;
  final badgeCount = badgeTextFinder.evaluate().length;
  final linkCount = linkFinder.evaluate().length;
  final expectedLink = hasLink ? 1 : 0;
  if (labelCount != 1) {
    violations.add('[count] r$index 라벨 "$label" $labelCount개(기대 1)');
  }
  if (badgeCount != 1) {
    violations.add('[count] r$index 배지 "$badge" $badgeCount개(기대 1)');
  }
  if (linkCount != expectedLink) {
    violations.add('[count] r$index 제목 링크 상자 $linkCount개(기대 $expectedLink)');
  }

  Rect? labelText;
  Rect? badgeBox;
  RenderParagraph? badgeParagraph;
  Rect? linkBox;

  if (labelCount == 1) {
    labelText = _readRect(
      tester,
      _paragraphOf(labelFinder),
      'r$index 라벨',
      violations,
    );
    final decoration = tester
        .widget<RichText>(_paragraphOf(labelFinder))
        .text
        .style
        ?.decoration;
    final isUnderlined = decoration == TextDecoration.underline;
    if (isUnderlined != hasLink) {
      violations.add('[link-style] r$index 라벨 밑줄 $isUnderlined(기대 $hasLink)');
    }
  }
  if (badgeCount == 1) {
    // ancestor 는 가까운 것부터 — 첫 Container 가 배지 상자다.
    badgeBox = _readRect(
      tester,
      find
          .ancestor(of: badgeTextFinder, matching: find.byType(Container))
          .first,
      'r$index 배지',
      violations,
    );
    final paragraph = tester.renderObject(_paragraphOf(badgeTextFinder));
    if (paragraph is RenderParagraph &&
        paragraph.hasSize &&
        !paragraph.debugNeedsLayout) {
      badgeParagraph = paragraph;
    }
  }
  if (hasLink && linkCount == 1) {
    linkBox = _readRect(tester, linkFinder, 'r$index 제목 링크 상자', violations);
  }

  final parts = <String, Rect?>{
    '라벨': labelText,
    '배지': badgeBox,
    if (hasLink) '제목 링크 상자': linkBox,
  };
  for (final MapEntry(key: partName, value: rect) in parts.entries) {
    if (rect == null) continue;
    if (rect.width <= _tolerance || rect.height <= _tolerance) {
      violations.add('[zero] r$index $partName ${_formatSize(rect)}');
    }
    if (rect.left < tileRect.left - _tolerance ||
        rect.right > tileRect.right + _tolerance) {
      violations.add(
        '[outside] r$index $partName '
        'x ${rect.left.toStringAsFixed(1)}~${rect.right.toStringAsFixed(1)} '
        '(타일 ${tileRect.left.toStringAsFixed(1)}~'
        '${tileRect.right.toStringAsFixed(1)})',
      );
    }
  }

  if (linkBox != null &&
      (linkBox.width < kMinInteractiveDimension - _tolerance ||
          linkBox.height < kMinInteractiveDimension - _tolerance)) {
    violations.add(
      '[link-size] r$index 제목 링크 상자 ${_formatSize(linkBox)}'
      '(기대 48x48 이상)',
    );
  }
  if (badgeParagraph != null) {
    final lines = _countLines(badgeParagraph);
    if (lines != 1) {
      violations.add('[badge-lines] r$index 배지 "$badge" $lines줄');
    }
  }
}

/// [finder] 아래 첫 RichText 를 찾는다(감싸개는 글자를 RichText 하나로 그린다).
Finder _paragraphOf(Finder finder) =>
    find.descendant(of: finder, matching: find.byType(RichText)).first;

/// [finder] 의 전역 사각형을 읽는다 — 크기 없는 render box 면 `[no-layout]` 을 남기고 null.
Rect? _readRect(
  WidgetTester tester,
  Finder finder,
  String what,
  List<String> violations,
) {
  final renderObject = tester.renderObject(finder);
  if (renderObject is! RenderBox ||
      !renderObject.hasSize ||
      renderObject.debugNeedsLayout) {
    violations.add('[no-layout] $what — 크기 없는 render box');
    return null;
  }
  return tester.getRect(finder);
}

/// 글자 줄 수 — 각 글자 자리의 caret 세로 위치를 허용치 안으로 묶은 서로 다른 값의 수.
///
/// 피할 수 없는 쪼개짐도 빼지 않고 그대로 센다(raw 줄 수).
int _countLines(RenderParagraph paragraph) {
  final length = paragraph.text.toPlainText().length;
  final tops = <double>[];
  for (var k = 0; k < length; k++) {
    final dy = paragraph
        .getOffsetForCaret(TextPosition(offset: k), Rect.zero)
        .dy;
    if (tops.every((top) => (top - dy).abs() > _tolerance)) {
      tops.add(dy);
    }
  }
  return tops.length;
}

/// 사각형 크기를 「폭x높이」 문자열로 바꾼다.
String _formatSize(Rect rect) =>
    '${rect.width.toStringAsFixed(1)}x${rect.height.toStringAsFixed(1)}';
