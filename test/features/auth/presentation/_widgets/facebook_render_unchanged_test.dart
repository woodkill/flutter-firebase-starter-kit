// Phase 13.3 — see ROADMAP.md (D-125-A Facebook 회귀 가드 widget test).
//
// **목적:** Phase 13.2 옵션 A 패턴 (`_renderFacebookButton` line 540-654) 의
// widget tree 변경 0 자동 회귀 가드. Phase 13.3 cross-cutting 변경에서
// Facebook 분기 (Pitfall 7) 가 의도치 않게 영향받으면 즉시 RED.
//
// **D-125 명시 "git diff snapshot test 비채택 (stylistic refactor 도 fail
// risk). structural matching."** widget tree 구조 검증 (Material / Image /
// BorderSide / Text) — pixel-level 검증은 `branded_social_button_golden_test`
// 의 `facebook_light.png` fixture 가 별도 책임.
//
// **별 file 분리 의무 (D-125-A):** Phase 13.3 의 cross-cutting 의도 명확화 —
// 기존 `branded_social_button_test.dart` 의 `T-13.2-FACEBOOK-*` 5 test cluster
// 는 Phase 13.2 책임으로 보존 (Pitfall 7), 본 file 은 Phase 13.3 책임.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/branded_social_button.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

/// 위제 트리 assertion 환경 wrap helper — AppTheme 주입 + en locale lock.
///
/// `branded_social_button_test.dart` + `branded_social_button_golden_test.dart`
/// 의 `_wrap` helper 와 동일 구조 — `context.appSpacing` ThemeExtension 의무 +
/// ARB delegate 명시.
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

/// SvgPicture / Image.asset 비동기 wait helper (Pitfall 3 가드).
Future<void> _settleAssets(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.pumpAndSettle();
    for (final Element element in find.byType(Image).evaluate().toList()) {
      final Image widget = element.widget as Image;
      await precacheImage(widget.image, element);
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
  });
  await tester.pumpAndSettle();
}

void main() {
  group('Phase 13.3 D-125-A Facebook 회귀 가드 (옵션 A 패턴 변경 0)', () {
    // ─── T-13.3-FACEBOOK-RENDER-UNCHANGED-01 ──────────────────────────────
    //
    // Phase 13.2 옵션 A pivot 의 widget tree structural matching:
    //   1. Image.asset path == 'assets/brand/facebook/facebook_login.png'
    //   2. Material.shape is RoundedRectangleBorder
    //   3. RoundedRectangleBorder.side.width == 1.0
    //   4. find.text('Login with Facebook') (en locale ARB)
    testWidgets(
      'T-13.3-FACEBOOK-RENDER-UNCHANGED-01: _renderFacebookButton widget '
      'tree 구조 변경 0 (D-125-A)',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            BrandedSocialButton.facebook(
              label: 'Login with Facebook',
              onPressed: () {},
            ),
            brightness: Brightness.light,
          ),
        );
        await _settleAssets(tester);

        // 1. Primary Logo SVG — Meta Brand Asset Pack AI verbatim 추출
        // (Wave 4 Step 2 supersede — PNG → SVG, D-94 lock + D-96 locale 독립)
        final SvgPicture svgWidget = tester.widget<SvgPicture>(
          find.byType(SvgPicture),
        );
        final dynamic loader = (svgWidget.bytesLoader as dynamic);
        expect(
          loader.assetName,
          'assets/brand/facebook/btn_signin_icon.svg',
          reason:
              'Facebook Primary Logo SVG 자상 변경 0 의무 (Wave 4 Step 2 '
              'supersede — PNG 폐기, AI verbatim 추출).',
        );

        // 2. Material shape == RoundedRectangleBorder (Apple 패턴 mirror)
        expect(
          find.byWidgetPredicate((Widget w) {
            if (w is! Material) return false;
            return w.shape is RoundedRectangleBorder;
          }),
          findsAtLeastNWidgets(1),
          reason: 'Material.shape RoundedRectangleBorder 변경 0 의무.',
        );

        // 3. BorderSide.width == 1.0 (Facebook outline 1dp lock)
        expect(
          find.byWidgetPredicate((Widget w) {
            if (w is! Material) return false;
            final ShapeBorder? shape = w.shape;
            if (shape is! RoundedRectangleBorder) return false;
            return shape.side.width == 1.0;
          }),
          findsAtLeastNWidgets(1),
          reason: 'Facebook outline 1dp BorderSide 변경 0 의무 (옵션 A pivot).',
        );

        // 4. ARB authFacebookSignIn 라벨 (en locale = 'Login with Facebook')
        expect(find.text('Login with Facebook'), findsOneWidget);
      },
    );

    // ─── T-13.3-FACEBOOK-DARK-THEME-01 ────────────────────────────────────
    //
    // D-94 lock: Primary Logo 단독 채택 — Theme.brightness 분기 시 SvgPicture
    // path 변경 0 (light/dark 모두 'btn_signin_icon.svg' 단일). render layer
    // (bg / outline / fg 색) 만 Theme.brightness 자동 분기.
    //
    // **Phase 13.3 Wave 4 Step 2 supersede:** PNG → SVG 전환 (AI verbatim 추출,
    // Meta Brand Asset Pack 의 Facebook_Logo_Primary.ai PyMuPDF 추출).
    testWidgets(
      'T-13.3-FACEBOOK-DARK-THEME-01: dark theme 도 동일 SvgPicture path '
      '(D-94 Primary Logo 단독, locale/theme 독립)',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            BrandedSocialButton.facebook(
              label: 'Login with Facebook',
              onPressed: () {},
            ),
            brightness: Brightness.dark,
          ),
        );
        await _settleAssets(tester);

        final SvgPicture svgWidget = tester.widget<SvgPicture>(
          find.byType(SvgPicture),
        );
        final dynamic loader = (svgWidget.bytesLoader as dynamic);
        expect(
          loader.assetName,
          'assets/brand/facebook/btn_signin_icon.svg',
          reason:
              'D-94 lock — Primary Logo 단독, dark theme 분기 시에도 동일 '
              'asset path. Secondary Logo (모노크롬) 분기 부재. Wave 4 Step 2 '
              'PNG → SVG 전환 후에도 단일 path 머레.',
        );
      },
    );
  });
}
