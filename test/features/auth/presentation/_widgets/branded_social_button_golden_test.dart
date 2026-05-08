// Phase 13.1 — see ROADMAP.md (D-86 6 fixture golden + D-87 zero tolerance)

import 'package:flutter/material.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/branded_social_button.dart';
import 'package:flutter_test/flutter_test.dart';

/// 360×480 viewport + en locale + 단일 brightness 적용 wrap helper.
///
/// D-86 명시 — 다중 사이즈 / 다중 locale 비채택 (label drift 는
/// brand_label_whitelist_test 가 별도 책임). brand drift detection 만 목적.
Widget _wrap(Widget child, {required Brightness brightness}) {
  return MaterialApp(
    theme: brightness == Brightness.light
        ? ThemeData.light(useMaterial3: true)
        : ThemeData.dark(useMaterial3: true),
    home: Scaffold(
      backgroundColor: brightness == Brightness.light
          ? const Color(0xFFFFFFFF)
          : const Color(0xFF000000),
      body: Center(
        child: SizedBox(
          width: 360,
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  group('BrandedSocialButton golden — D-86 6 fixture / D-87 zero tolerance', () {
    testWidgets('Naver light', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 480));
      await tester.pumpWidget(
        _wrap(
          BrandedSocialButton.naver(
            label: 'Continue with Naver',
            theme: NaverTheme.light,
            onPressed: () {},
          ),
          brightness: Brightness.light,
        ),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/naver_light.png'),
      );
    });

    testWidgets('Naver dark', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 480));
      await tester.pumpWidget(
        _wrap(
          BrandedSocialButton.naver(
            label: 'Continue with Naver',
            theme: NaverTheme.dark,
            onPressed: () {},
          ),
          brightness: Brightness.dark,
        ),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/naver_dark.png'),
      );
    });

    testWidgets('Kakao light', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 480));
      await tester.pumpWidget(
        _wrap(
          BrandedSocialButton.kakao(
            label: 'Continue with Kakao',
            onPressed: () {},
          ),
          brightness: Brightness.light,
        ),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/kakao_light.png'),
      );
    });

    testWidgets('Google light', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 480));
      await tester.pumpWidget(
        _wrap(
          BrandedSocialButton.google(
            label: 'Sign in with Google',
            theme: GoogleTheme.light,
            onPressed: () {},
          ),
          brightness: Brightness.light,
        ),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/google_light.png'),
      );
    });

    testWidgets('Google dark', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 480));
      await tester.pumpWidget(
        _wrap(
          BrandedSocialButton.google(
            label: 'Sign in with Google',
            theme: GoogleTheme.dark,
            onPressed: () {},
          ),
          brightness: Brightness.dark,
        ),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/google_dark.png'),
      );
    });

    testWidgets('Google neutral', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 480));
      await tester.pumpWidget(
        _wrap(
          BrandedSocialButton.google(
            label: 'Sign in with Google',
            theme: GoogleTheme.neutral,
            onPressed: () {},
          ),
          brightness: Brightness.light,
        ),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/google_neutral.png'),
      );
    });
  });
}
