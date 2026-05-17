// Phase 13.3 — see ROADMAP.md (D-125-B LINE/WeChat placeholder 회귀 가드).
//
// **목적:** `_renderPlaceholder` (line 752-768) wrapper layout 변경 0 자동
// 회귀 가드. Phase 13.1 D-71 lock (height 48 / radius 12 / icon 18) + D-73
// 회색 fallback. Phase 14 (LINE 자상화) + Phase 16 (WeChat 자상화) 전까지
// placeholder wrapper layout 변경 0 의무.
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
  group('Phase 13.3 D-125-B LINE/WeChat placeholder wrapper 회귀 가드', () {
    // ─── T-13.3-PLACEHOLDER-LINE-LAYOUT-01 ────────────────────────────────
    //
    // LINE placeholder (Phase 14 자상 commit 전 회색 fallback):
    //   1. SizedBox.height == 48.0 (D-71 lock)
    //   2. Material.shape is RoundedRectangleBorder + borderRadius topLeft.x == 12.0
    //   3. Material.color == Colors.grey.shade200 (D-73 회색 fallback)
    //   4. find.textContaining('LINE') (ARB authBrandAssetMissing 보간 결과)
    //
    // Phase 13.3 WR-04 정정 (2026-05-17): `_renderPlaceholder` 가
    // `Material.borderRadius` → `Material.shape: RoundedRectangleBorder` 로
    // 전환. 5 active provider 패턴 일관성 회복. 검증도 shape 기반으로 갱신.
    testWidgets('T-13.3-PLACEHOLDER-LINE-LAYOUT-01: LINE wrapper layout 변경 0 '
        '(D-71 height 48 + radius 12 + D-73 회색 fallback)', (tester) async {
      await tester.pumpWidget(
        _wrap(
          BrandedSocialButton.line(
            label: 'Continue with LINE',
            onPressed: () {},
          ),
          brightness: Brightness.light,
        ),
      );
      await tester.pumpAndSettle();

      // 1. SizedBox height 48 (D-71 lock)
      expect(
        find.byWidgetPredicate((Widget w) {
          if (w is! SizedBox) return false;
          return w.height == 48.0;
        }),
        findsAtLeastNWidgets(1),
        reason:
            'LINE placeholder wrapper height 48 dp 의무 (D-71 lock — Phase '
            '14 자상 commit 전 회귀 가드).',
      );

      // 2. Material shape = RoundedRectangleBorder + borderRadius 12 (D-71 lock,
      //    Phase 13.3 WR-04 정정 — 5 active provider 패턴 mirror).
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
            'LINE placeholder Material shape=RoundedRectangleBorder + '
            'borderRadius 12 dp 의무 (D-71 lock + 5 provider 패턴 mirror).',
      );

      // 3. Material.color == Colors.grey.shade200 (D-73)
      expect(
        find.byWidgetPredicate((Widget w) {
          if (w is! Material) return false;
          return w.color == Colors.grey.shade200;
        }),
        findsAtLeastNWidgets(1),
        reason:
            'LINE placeholder 회색 fallback (Colors.grey.shade200) 의무 '
            '(D-73 — 자상 미존재 시 disabled 외관).',
      );

      // 4. ARB authBrandAssetMissing 라벨 보간 결과 ('Asset missing: Continue with LINE')
      expect(find.textContaining('LINE'), findsOneWidget);
    });

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
