// Phase 13.1 — see ROADMAP.md (D-86 6 fixture golden + D-87 zero tolerance)

import 'package:flutter/material.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/branded_social_button.dart';
import 'package:flutter_test/flutter_test.dart';

/// 360×480 viewport + en locale + 단일 brightness 적용 wrap helper.
///
/// D-86 명시 — 다중 사이즈 / 다중 locale 비채택 (label drift 는
/// brand_label_whitelist_test 가 별도 책임). brand drift detection 만 목적.
///
/// [AppTheme.light]/[AppTheme.dark] 주입 — `BrandedSocialButton` 이
/// `context.appSpacing` ([AppSpacing] ThemeExtension) 에 의존하기 때문에
/// `ThemeData.light()` 단독으로는 ThemeExtension 누락으로 null check fail.
/// 다른 widget 테스트와 일관 (Rule 3 — blocking issue 정정, plan PATTERNS
/// Section 14 sample 의 ThemeExtension 의존성 누락 보완).
///
/// `debugShowCheckedModeBanner: false` — DEBUG 배너 (우측 상단 빨간 삼각형)
/// 가 golden capture 에 포함되어 자상 baked-in 시각 검증을 방해하지 않도록.
Widget _wrap(Widget child, {required Brightness brightness}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: brightness == Brightness.light ? AppTheme.light() : AppTheme.dark(),
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

/// Phase 13.1 Gap-1 X2 golden capture 결함 정정 — 자상 비동기 로드 wait.
///
/// **Background:** `Image.asset()` / `SvgPicture.asset()` 는 widget test
/// 환경에서 비동기적으로 자상 binary 를 디코딩하는데, `tester.pumpAndSettle()`
/// 만으로는 디코딩 완료 전에 golden capture 가 발생 → 자상이 빈 placeholder
/// 영역으로 캡처됨 (1차 capture 결함, 2026-05-09 사용자 보고).
///
/// **해결:** `tester.runAsync()` 안에서 (1) `precacheImage` 로 모든 Image
/// widget 의 ImageProvider 강제 디코딩 + (2) SvgPicture 비동기 vector_graphics
/// 로드 흡수를 위한 짧은 delay + (3) 최종 `pumpAndSettle` 으로 모든 frame
/// 안정화.
Future<void> _settleAssets(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.pumpAndSettle();

    // (1) Image.asset 강제 디코딩 — Naver/Kakao PNG 자상 (assetType.png)
    for (final element in find.byType(Image).evaluate().toList()) {
      final widget = element.widget as Image;
      await precacheImage(widget.image, element);
    }

    // (2) SvgPicture 비동기 vector_graphics 로드 흡수 — Google SVG 자상
    // (assetType.svg). flutter_svg 는 microtask 기반 비동기 로드 → 짧은
    // delay 로 첫 frame layout 안정화.
    await Future<void>.delayed(const Duration(milliseconds: 200));

    // (3) 최종 frame 안정화
    await tester.pumpAndSettle();
  });
  // runAsync 외부에서 한번 더 pump — runAsync 내부 frame 을 capture 단계로 commit.
  await tester.pumpAndSettle();
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
      // Phase 13.1 Gap-1 X2 — 자상 비동기 디코딩 wait (precacheImage +
      // SvgPicture vector_graphics delay) — _settleAssets helper 참조.
      await _settleAssets(tester);
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
      await _settleAssets(tester);
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
      await _settleAssets(tester);
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
      await _settleAssets(tester);
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
      await _settleAssets(tester);
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
      await _settleAssets(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/google_neutral.png'),
      );
    });
  });
}
