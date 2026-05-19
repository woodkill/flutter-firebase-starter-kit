// Phase 13.3 — see ROADMAP.md (D-125-B LINE/WeChat placeholder 회귀 가드).
//
// **목적:** `_renderPlaceholder` wrapper layout 변경 0 자동 회귀 가드. Phase
// 13.1 D-71 lock (height 48 / radius 12 / icon 18) + D-73 회색 fallback.
// Phase 16 (WeChat 자상화) 전까지 placeholder wrapper layout 변경 0 의무.
//
// **Phase 14 갱신 (2026-05-19):** LINE 자상화 완료 (Plan 14-06 active 전환 —
// `_renderLineButton` 신규, #06C755 bg 적용). T-13.3-PLACEHOLDER-LINE-LAYOUT-01
// testcase 폐기 — `BrandedSocialButton.line` 가 이제 `_renderPlaceholder` 가
// 아닌 `_renderLineButton` 으로 dispatch (회색 fallback 검증 의미 소실).
// 회귀 가드 책임은 `branded_social_button_test.dart` 의 T-14-LINE-*-01 5
// testcase 로 승계 (Plan 14-06 산출물).
// WeChat placeholder 단독 잔존 (T-13.3-PLACEHOLDER-WECHAT-LAYOUT-01).
//
// **D-125 명시 "git diff snapshot test 비채택. structural matching."** —
// widget tree 구조 검증 (SizedBox.height / Material.borderRadius / Material.
// color), pixel diff 0.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/branded_social_button.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

/// 위제 트리 assertion 환경 wrap helper (`_wrap` 패턴 일관).
Widget _wrap(Widget child, {required Brightness brightness}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: brightness == Brightness.light ? AppTheme.light() : AppTheme.dark(),
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Center(child: SizedBox(width: 360, child: child)),
    ),
  );
}

void main() {
  group('Phase 13.3 D-125-B placeholder wrapper 회귀 가드 (WeChat 단독 잔존 — Phase 14 LINE active 전환 후)', () {
    // ─── T-13.3-PLACEHOLDER-LINE-LAYOUT-01 (폐기 — Phase 14 Plan 14-06) ────
    //
    // **폐기 사유 (Plan 14-06, 2026-05-19):** LINE 가 active 전환 (`_render
    // LineButton` 신규 + bg #06C755) — `BrandedSocialButton.line` 가 더 이상
    // `_renderPlaceholder` 로 dispatch 안 함. 회색 fallback 검증 의미 소실.
    // 회귀 가드 책임 승계: `branded_social_button_test.dart` 의 T-14-LINE-
    // RENDER-01 (#06C755 verbatim) + T-14-LINE-DRIFT-01 (colorScheme override
    // 무관) + T-14-LINE-DARK-01 (dark/light 동일) + T-14-LINE-ICON-01 (자상
    // SVG 19.227×18) + T-14-LINE-DISABLED-01 (onPressed null wiring).

    // ─── T-13.3-PLACEHOLDER-WECHAT-LAYOUT-01 ──────────────────────────────
    testWidgets(
      'T-13.3-PLACEHOLDER-WECHAT-LAYOUT-01: WeChat wrapper layout 변경 0 '
      '(D-71 + D-73 LINE 동일 패턴)',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            BrandedSocialButton.wechat(
              label: 'Continue with WeChat',
              onPressed: () {},
            ),
            brightness: Brightness.light,
          ),
        );
        await tester.pumpAndSettle();

        // 1. SizedBox height 48
        expect(
          find.byWidgetPredicate((Widget w) {
            if (w is! SizedBox) return false;
            return w.height == 48.0;
          }),
          findsAtLeastNWidgets(1),
          reason:
              'WeChat placeholder wrapper height 48 dp 의무 (D-71 lock — '
              'Phase 16 자상 commit 전 회귀 가드).',
        );

        // 2. Material shape = RoundedRectangleBorder + borderRadius 12
        //    (Phase 13.3 WR-04 정정 — 5 active provider 패턴 mirror).
        expect(
          find.byWidgetPredicate((Widget w) {
            if (w is! Material) return false;
            final ShapeBorder? shape = w.shape;
            if (shape is! RoundedRectangleBorder) return false;
            final BorderRadiusGeometry br = shape.borderRadius;
            if (br is! BorderRadius) return false;
            return br.topLeft.x == 12.0;
          }),
          findsAtLeastNWidgets(1),
          reason:
              'WeChat placeholder Material shape=RoundedRectangleBorder + '
              'borderRadius 12 dp 의무 (D-71 lock).',
        );

        // 3. Material.color == Colors.grey.shade200
        expect(
          find.byWidgetPredicate((Widget w) {
            if (w is! Material) return false;
            return w.color == Colors.grey.shade200;
          }),
          findsAtLeastNWidgets(1),
          reason:
              'WeChat placeholder 회색 fallback (Colors.grey.shade200) 의무 '
              '(D-73 — 자상 미존재 시 disabled 외관).',
        );

        // 4. ARB authBrandAssetMissing 보간 결과
        expect(find.textContaining('WeChat'), findsOneWidget);
      },
    );
  });
}
