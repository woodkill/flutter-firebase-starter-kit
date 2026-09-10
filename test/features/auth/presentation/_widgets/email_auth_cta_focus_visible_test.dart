// Phase 16.1 — UI-REVIEW Top fix ③ (2026-09-10, /gsd-add-tests 16.1).
//
// `EmailAuthCta` 의 keyboard focus 가시성 회귀 가드 (WCAG 2.1 SC 2.4.7 Focus
// Visible, Level AA). UI-SPEC 은 당초 신규 CTA 가 `BrandFocusWrapper` 의 2 dp
// outline 을 테마 차원에서 상속한다고 서술했으나 Plan 04 가 사실 오류로
// 정정했다 — 그 wrapper 는 provider 버튼 전용이고 `app_theme.dart` 에 focus
// 설정이 0건이라, CTA 는 **M3 `TextButton` 기본 focus overlay**
// (`overlayColor` 의 focused 분기 = `colorScheme.primary` @ 0.1) 에 의존한다.
// 정정 후에도 "실제 렌더 레벨에서 overlay 가 보이는가" 를 고정하는 test 가
// 없어 48 dp 탭 타겟 단언으로 대체돼 있었다 (탭 타겟 ≠ focus ring 가시성).
//
// 본 file 은 `paints` matcher 로 Tab focus 진입 전후의 paint 호출을 직접
// 비교한다 — `InkWell` 의 focus `InkHighlight` 가 `customBorder`
// (StadiumBorder) 영역을 primary 색으로 채우는 순간을 잡는다.
// `ThemeData.textButtonTheme` 로 overlayColor 를 투명하게 덮거나 CTA 를
// focus 를 삼키는 wrapper 로 감싸면 RED 가 된다 (scratch 로 RED 실측
// 2026-09-10).
//
// Phase 13.3 `focus_visible_test.dart` (T-13.3-FOCUS-VISIBLE-THEME-01) 와의
// 분업: 그 file 은 provider 버튼의 hardcode outline, 본 file 은 M3 토큰
// 경유 CTA 의 overlay 를 각각 담당한다.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/email_auth_cta.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// [EmailAuthCta] 를 [brightness] 테마로 단독 pump 한다.
///
/// 위젯이 provider 를 읽지 않으므로 `ProviderScope` 는 불필요하다. `onPressed`
/// 는 `null` 을 그대로 통과시킨다 (WR-08 disabled 경로 검증용).
Future<void> _pumpCta(
  WidgetTester tester, {
  required Brightness brightness,
  required VoidCallback? onPressed,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: brightness == Brightness.light
          ? AppTheme.light()
          : AppTheme.dark(),
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(child: EmailAuthCta(onPressed: onPressed)),
      ),
    ),
  );
  await tester.pump();
}

/// 현재 pump 된 [EmailAuthCta] 테마의 `colorScheme.primary`.
Color _primaryOf(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(EmailAuthCta))).colorScheme.primary;

/// CTA 내부 [Material] — `ButtonStyleButton` 이 `InkWell` 을 감싸는 그
/// Material 로, focus `InkHighlight` 는 이 Material 의 ink feature 로 paint
/// 된다. [Scaffold] 의 Material 은 조상이라 descendant finder 에 잡히지 않는다.
Finder _ctaMaterial() => find.descendant(
  of: find.byType(EmailAuthCta),
  matching: find.byType(Material),
);

/// 두 색의 RGB 가 같은지 (alpha 무시).
bool _sameRgb(Color a, Color b) =>
    (a.toARGB32() & 0x00FFFFFF) == (b.toARGB32() & 0x00FFFFFF);

/// [primary] RGB 로 alpha > 0 인 fill 을 그리는 paint 호출인지 판정한다.
///
/// `InkHighlight` 는 `color.withAlpha(animatedAlpha)` 로 그리므로 (0.1 →
/// 26/255) float alpha 정확 일치 대신 "RGB 동일 + alpha > 0" 으로 판정한다.
/// 그리는 primitive 는 SDK 구현에 따라 다르다 — Flutter 3.41 은 customBorder
/// 로 `clipPath` 한 뒤 `drawRect`, 이전 버전은 `drawPath` (2026-09-10 RED
/// 실측). 그래서 method 는 고정하지 않고 [Paint] 인자의 색만 본다.
/// `Material` 배경 fill 은 TextButton 에서 투명 (alpha 0) 이라 제외된다.
PaintPatternPredicate _focusOverlayFill(Color primary) {
  return (Symbol method, List<dynamic> args) {
    for (final arg in args) {
      if (arg is Paint && arg.color.a > 0 && _sameRgb(arg.color, primary)) {
        return true;
      }
    }
    return false;
  };
}

/// `primaryFocus` 가 [EmailAuthCta] 서브트리 안에 있는지.
bool _ctaHasPrimaryFocus(WidgetTester tester) {
  final focusContext = tester.binding.focusManager.primaryFocus?.context;
  if (focusContext == null) return false;
  return focusContext.findAncestorWidgetOfExactType<EmailAuthCta>() != null;
}

/// Tab 키 1회로 keyboard focus traversal 을 시작하고 settle 한다.
///
/// 키 이벤트는 `FocusManager.highlightMode` 를 touch → traditional 로 전환
/// 하므로 (`FocusHighlightStrategy.automatic`), `InkWell` 이 focus highlight
/// 를 표시하는 조건이 함께 충족된다. 실 단말의 외장 키보드/TV 리모컨 경로와
/// 동일하다.
Future<void> _pressTab(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.pumpAndSettle();
}

void main() {
  group('EmailAuthCta focus-visible (Phase 16.1 UI-REVIEW Top fix ③)', () {
    for (final brightness in <Brightness>[Brightness.light, Brightness.dark]) {
      testWidgets(
        '${brightness.name}: Tab focus 진입 시 M3 focus overlay (primary@α) 가 '
        '실제로 paint 된다',
        (tester) async {
          await _pumpCta(tester, brightness: brightness, onPressed: () {});
          final primary = _primaryOf(tester);

          // Arrange 검증 — focus 진입 전: CTA 밖에 focus, overlay 미paint.
          expect(_ctaHasPrimaryFocus(tester), isFalse);
          expect(
            _ctaMaterial(),
            isNot(paints..something(_focusOverlayFill(primary))),
            reason:
                'focus 진입 전에 primary 색 overlay 가 이미 그려져 있으면 '
                '"focus 시 나타남" 을 검증할 수 없다',
          );

          // Act — Tab 키.
          await _pressTab(tester);

          // Assert — focus 가 CTA 에 도착했고 overlay 가 렌더된다.
          expect(
            _ctaHasPrimaryFocus(tester),
            isTrue,
            reason: 'Tab traversal 이 EmailAuthCta (TextButton) 에 도착해야 한다',
          );
          expect(
            _ctaMaterial(),
            paints..something(_focusOverlayFill(primary)),
            reason:
                'focus 진입 후 colorScheme.primary 색 (alpha > 0) 의 focus '
                'overlay path 가 그려져야 한다 — M3 TextButton overlayColor '
                'focused 분기 (primary @ 0.1) 회귀 (WCAG 2.4.7 미달)',
          );
        },
      );
    }

    testWidgets(
      'disabled (onPressed: null): Tab 이 CTA 에 focus 를 주지 않고 overlay 도 '
      '없다 (WR-08 시각·시맨틱 정합)',
      (tester) async {
        await _pumpCta(tester, brightness: Brightness.light, onPressed: null);
        final primary = _primaryOf(tester);

        await _pressTab(tester);

        expect(
          _ctaHasPrimaryFocus(tester),
          isFalse,
          reason:
              'disabled TextButton 은 canRequestFocus=false — traversal '
              '대상에서 제외돼야 한다',
        );
        expect(
          _ctaMaterial(),
          isNot(paints..something(_focusOverlayFill(primary))),
          reason:
              'disabled 상태에서 focus overlay 가 그려지면 시각/시맨틱이 '
              '어긋난다',
        );
      },
    );

    testWidgets('keyboard activation: Tab → Enter 로 onPressed 가 정확히 1회 호출된다', (
      tester,
    ) async {
      var tapCount = 0;
      await _pumpCta(
        tester,
        brightness: Brightness.light,
        onPressed: () => tapCount++,
      );

      await _pressTab(tester);
      expect(_ctaHasPrimaryFocus(tester), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(
        tapCount,
        1,
        reason:
            'focus 된 CTA 는 Enter (ActivateIntent) 로 활성화돼야 keyboard '
            '전용 사용자가 이메일 로그인에 도달할 수 있다',
      );
    });
  });
}
