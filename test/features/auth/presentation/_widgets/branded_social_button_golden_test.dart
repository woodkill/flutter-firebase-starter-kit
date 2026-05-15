// Phase 13.1 — see ROADMAP.md (D-86 6 fixture golden + D-87 zero tolerance)
// Phase 13.3 — see ROADMAP.md (R6 caller-side compile-fail 흡수, Wave 3 D-117).
//             NaverSpec/GoogleSpec theme: parameter 폐기로 caller 단순화.
//             Wave 4 의 --update-goldens 가 fixture 재생성 책임 — 본 file 은
//             compile pass 까지만 수정.

import 'package:flutter/material.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/branded_social_button.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
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
///
/// **Phase 13.1 REVIEW CR-04 정정 (2026-05-10):** `locale: const Locale('en')`
/// + `localizationsDelegates: AppLocalizations.localizationsDelegates` 명시 —
/// `_iconAssetFor` 의 `Localizations.localeOf(context).languageCode == 'ko'`
/// 분기가 test environment system locale 에 의존하지 않도록 결정성 강제.
/// 이전 버전은 macOS dev box (`en-US`) 에서 generate 한 golden 이 ko-locale
/// CI 환경에서 RED 회귀 발생 가능 (Kakao/Naver 자상이 `ko/` 분기로 로딩).
///
/// **Phase 13.1 REVIEW iter2 WR-03 verification trace (2026-05-10):** CR-04
/// fix (`locale: 'en'` + delegates 명시) 후 `fvm flutter test
/// branded_social_button_golden_test.dart` 6 PASS 검증 (자상 PNG byte-level
/// 일치 — 기존 system-locale 환경이 정확히 'en' 였음을 사후 검증). golden
/// 재생성 불필요 (PNG 변경 0). future 변경 시: `--update-goldens` 후 PNG
/// diff review 의무 (analyze 만으로는 image-diff 불가 — WR-03 가드).
Widget _wrap(Widget child, {required Brightness brightness}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: brightness == Brightness.light ? AppTheme.light() : AppTheme.dark(),
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      backgroundColor: brightness == Brightness.light
          ? const Color(0xFFFFFFFF)
          : const Color(0xFF000000),
      body: Center(child: SizedBox(width: 360, child: child)),
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
  group(
    'BrandedSocialButton golden — D-86 6 fixture / D-87 zero tolerance',
    () {
      testWidgets('Naver light', (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 480));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          _wrap(
            BrandedSocialButton.naver(
              label: 'Continue with Naver',
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
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          _wrap(
            BrandedSocialButton.naver(
              label: 'Continue with Naver',
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
        addTearDown(() => tester.binding.setSurfaceSize(null));
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
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          _wrap(
            BrandedSocialButton.google(
              label: 'Sign in with Google',
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
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          _wrap(
            BrandedSocialButton.google(
              label: 'Sign in with Google',
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

      // Phase 13.3 R1 (Wave 3 D-117) — GoogleTheme.neutral enum 폐기.
      // case 자체 보존 (compile pass 책임 minimum), Wave 4 가 case 삭제 +
      // google_neutral.png fixture rm 책임. 본 testWidgets 는 light fixture
      // 와 동일한 caller 로 임시 변경 — Wave 4 가 case 자체 삭제 시 본 임시
      // assertion 도 함께 폐기.
      testWidgets('Google neutral (Wave 4 deprecation pending)', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(360, 480));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          _wrap(
            BrandedSocialButton.google(
              label: 'Sign in with Google',
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

      // Phase 13.2 Plan 13.2-06 — Facebook fixture 신규 (옵션 A pivot 후).
      //
      // **D-94 lock (Wave 0 LOCK §D-93 vs D-94):** theme 매개변수 부재
      // (Kakao 패턴 머레). Primary Logo (#1877F2 'f' 마크 PNG) 단독 채택,
      // Secondary Logo (모노크롬 fallback) 미동봉 — Flutter mobile 컬러 환경
      // 에서 Theme.brightness 자동 분기는 `_renderFacebookButton` 위제 내부
      // 책임 (light bg + black text + 1dp grey outline vs dark bg + white
      // text + 1dp lighter outline).
      //
      // **fixture 차원 (Wave 0 LOCK §fixture 차원):** 360×480 canvas + en
      // locale + zero pixel tolerance. wide button render 결과는 360×48
      // (Material Design 표준 button height, Phase 13.1 spec.height 일관).
      // square logo (2084×2084) 를 `Image.asset(width: 18, height: 18)` 으로
      // 18dp icon 슬롯 위제 fit 시 letter-aligned + label center 의 wide
      // 외관 보존.
      //
      // **fixture 개수 1:** light only (D-94 채택 영향 — D-93 의 2 fixture
      // light + dark 미적용). Theme.brightness 분기 검증은
      // `branded_social_button_test.dart` 의 위제 단위 widget test 책임.
      testWidgets('Facebook light', (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 480));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          _wrap(
            BrandedSocialButton.facebook(
              label: 'Continue with Facebook',
              onPressed: () {},
            ),
            brightness: Brightness.light,
          ),
        );
        await _settleAssets(tester);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/facebook_light.png'),
        );
      });
    },
  );
}
