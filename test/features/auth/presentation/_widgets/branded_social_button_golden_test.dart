// Phase 13.1 — see ROADMAP.md (D-86 6 fixture golden + D-87 zero tolerance)
// Phase 13.3 — see ROADMAP.md (R6 caller-side compile-fail 흡수, Wave 3 D-117).
//             NaverSpec/GoogleSpec theme: parameter 폐기로 caller 단순화.
//             Wave 4 의 --update-goldens 가 fixture 재생성 책임 — 본 file 은
//             compile pass 까지만 수정.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
/// Phase 13.3 Wave 4 Step 3 (2026-05-16) — optional `platform` parameter 도입.
/// Kakao iOS golden fixture (`kakao_light_ios.png`) 를 위해 [TargetPlatform]
/// override 지원. null 시 ThemeData.platform default 유지 (= Android in test
/// env). starter kit drift 회피 원칙 "허용 (분기 trigger): theme.platform"
/// 검증 책임 분리.
Widget _wrap(
  Widget child, {
  required Brightness brightness,
  TargetPlatform? platform,
}) {
  final baseTheme = brightness == Brightness.light
      ? AppTheme.light()
      : AppTheme.dark();
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: platform != null
        ? baseTheme.copyWith(platform: platform)
        : baseTheme,
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

/// Phase 13.3 Wave 4 — golden test 라벨 Text 글리프 회귀 정정 (D-119).
///
/// **Background:** `flutter_test` 의 기본 폰트는 Ahem (모든 글리프가 동일
/// 정사각형 box). Phase 13.1 D-86 시점부터 모든 골든 fixture 의 라벨 텍스트
/// (`Continue with Google` / `Login with Kakao` / `Log in with NAVER` 등) 가
/// ▮▮ box 로 렌더링되어 사용자 시각 sign-off (D-119) 가 정상 검증 불가능.
///
/// **해결:** Flutter SDK 의 `Roboto-Medium.ttf` (Apache 2.0) 를
/// `assets/test_fonts/` 에 복사 commit + golden test 진입 시 `FontLoader` 로
/// 등록. `flutter > assets` pubspec 등록 비채택 — production bundle 미포함
/// (test 전용 자산). `File.fromUri` 직접 로드 — test working directory 가
/// project root 라 안정적.
///
/// **5 provider 정합성:** Apple SDK = SF Pro (caller override 0, golden 외).
/// Google = Roboto Medium 14/20 (verbatim 명시). Facebook/Kakao/Naver =
/// system 위임 + Android default = Roboto → 5 provider 모두 부합 (`feedback_*`
/// 메모리 + 13.3-UI-SPEC line 76/82-83).
Future<void> _loadGoldenFonts() async {
  final robotoLoader = FontLoader('Roboto');
  final robotoBytes = await File(
    'assets/test_fonts/Roboto-Medium.ttf',
  ).readAsBytes();
  robotoLoader.addFont(Future.value(ByteData.view(robotoBytes.buffer)));
  await robotoLoader.load();

  // Phase 13.3 Wave 4 Step 3 (2026-05-16) — Inter Regular + Medium golden
  // fixture font load. Apple Sign-in 버튼 라벨이 platform 분기로 Android/test
  // env 에서 'Inter' family 사용 (iOS/macOS 는 system 'SF Pro Text'). Apple
  // Button API verbatim `fontWeight: "400"` 매칭 위해 Inter Regular (w400) 가
  // primary, Medium (w500) 는 future use 대비. production bundle 의
  // `assets/fonts/inter/` 자산 그대로 재사용.
  final interLoader = FontLoader('Inter');
  final interRegularBytes = await File(
    'assets/fonts/inter/Inter-Regular.ttf',
  ).readAsBytes();
  interLoader.addFont(
    Future.value(ByteData.view(interRegularBytes.buffer)),
  );
  final interMediumBytes = await File(
    'assets/fonts/inter/Inter-Medium.ttf',
  ).readAsBytes();
  interLoader.addFont(Future.value(ByteData.view(interMediumBytes.buffer)));
  await interLoader.load();

  // Phase 13.3 Wave 4 Step 3 (2026-05-16) — Pretendard variable font golden
  // fixture font load. Naver 라벨이 fontFamily 'Pretendard' (전 platform 단일,
  // 공식 PNG 글리프 시각 부합 + 한국 design 표준 web font). production bundle
  // 의 `assets/fonts/pretendard/PretendardVariable.ttf` 자산 그대로 재사용.
  // Variable axis `wght` 100-900 — Flutter `fontWeight: FontWeight.w800` 명시
  // 시 wght axis 800 자동 매핑.
  final pretendardLoader = FontLoader('Pretendard');
  final pretendardBytes = await File(
    'assets/fonts/pretendard/PretendardVariable.ttf',
  ).readAsBytes();
  pretendardLoader.addFont(
    Future.value(ByteData.view(pretendardBytes.buffer)),
  );
  await pretendardLoader.load();

  // Phase 13.3 Wave 4 Step 3 (2026-05-16) — Step B Kakao/Naver iOS branch +
  // Apple/Google iOS branch golden fixture font load. macOS dev 환경에서만
  // 동작 — macOS 시스템 폰트를 FontLoader 에 alias 로 등록 (Apple OS 내부
  // 로컬 사용). 결과 golden PNG 는 `.gitignore` 로 commit 차단 (Apple Font
  // License + Sandoll 라이센스 위반 위험 회피). CI/Linux 환경은 testWidgets
  // `skip` 매개변수로 우회.
  if (Platform.isMacOS) {
    // AppleSDGothicNeo (Naver iOS + Kakao iOS 라벨용) — macOS native 시스템 폰트.
    final appleSDGothicNeoFile = File(
      '/System/Library/Fonts/AppleSDGothicNeo.ttc',
    );
    if (appleSDGothicNeoFile.existsSync()) {
      final appleSDGothicNeoLoader = FontLoader('AppleSDGothicNeo');
      final bytes = await appleSDGothicNeoFile.readAsBytes();
      appleSDGothicNeoLoader.addFont(
        Future.value(ByteData.view(bytes.buffer)),
      );
      await appleSDGothicNeoLoader.load();
    }

    // SF Pro Text (Apple iOS + Google iOS 라벨용) — macOS 시스템 SFNS.ttf 를
    // 'SF Pro Text' family alias 로 등록. SFNS.ttf 의 internal family name 은
    // '.SFNS-Regular' 라 Flutter `fontFamily: 'SF Pro Text'` 와 자동 매칭 안
    // 됨 → FontLoader 의 명시적 family name 으로 alias 활용. Apple SF Pro
    // Font License 부합 (Apple OS 내부 로컬 사용, dev 단말 사용자 본인 시스템
    // file 접근). 결과 golden PNG 는 `.gitignore` 로 commit 차단.
    //
    // Phase 13.3 code review IN-06 정정 (2026-05-17): SFNS.ttf 부재 시 silent
    // skip → fail-loud 전환. silent skip 패턴은 golden 이 Inter fallback 으로
    // 변경되어 자동 갱신 후 production drift 가능 (macOS major upgrade 시
    // system font 위치 변경 등). 명시 throw 로 system font 위치 갱신 의무
    // surface.
    final sfNSFile = File('/System/Library/Fonts/SFNS.ttf');
    if (!sfNSFile.existsSync()) {
      throw TestFailure(
        'macOS SFNS.ttf 부재 (/System/Library/Fonts/SFNS.ttf) — Apple iOS '
        'golden 생성 불가. macOS major upgrade 등으로 system font 위치 갱신 '
        '가능성 — Phase 13.3 IN-06 정정. silent skip 폐기 (golden 자동 갱신 '
        '후 production drift 회피).',
      );
    }
    final sfProTextLoader = FontLoader('SF Pro Text');
    final bytes = await sfNSFile.readAsBytes();
    sfProTextLoader.addFont(Future.value(ByteData.view(bytes.buffer)));
    await sfProTextLoader.load();
  }
}

void main() {
  setUpAll(_loadGoldenFonts);

  group(
    'BrandedSocialButton golden — D-86 6 fixture / D-87 zero tolerance',
    () {
      testWidgets('Naver light', (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 480));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          _wrap(
            BrandedSocialButton.naver(
              label: 'Log in with NAVER',
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

      // Phase 13.3 Wave 4 Step 3 (2026-05-16) — Naver platform 분기 fixture
      // (macOS dev only, Kakao 패턴 mirror). ThemeData.platform =
      // TargetPlatform.iOS override → _renderNaverButton 의 `isIOS` branch
      // 트리거 (fontFamily 'AppleSDGothicNeo' Pretendard source font + w500).
      // PNG fixture 는 `.gitignore` 로 commit 차단 (Apple Font License + Sandoll
      // 라이센스 위반 위험 회피). CI/Linux 환경은 `skip: !Platform.isMacOS` 우회.
      testWidgets(
        'Naver light (iOS)',
        skip: !Platform.isMacOS,
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(360, 480));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            _wrap(
              BrandedSocialButton.naver(
                label: 'Log in with NAVER',
                onPressed: () {},
              ),
              brightness: Brightness.light,
              platform: TargetPlatform.iOS,
            ),
          );
          await _settleAssets(tester);
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/naver_light_ios.png'),
          );
        },
      );

      // Phase 13.3 Wave 4 Q4 (option-a) — Naver light/dark 외관 동일
      // (`#03A94D` + 흰 라벨 + 흰 N glyph, `_renderNaverButton` brightness
      // 분기 0). dark fixture single 폐기 (RESEARCH §Wave 4.5 권장,
      // 13.3-04-PLAN Q4 결정 2026-05-15).
      //
      // **Phase 13.3 X3 (2026-05-17, 260517-uv4) supersede:** Kakao/Naver
      // dark golden 4 testcase 추가 — light/dark 외관 동일 invariant 의 회귀
      // 가드 (theme.brightness override 무관 baked-in 자상 보존 검증).
      // Android tracked (kakao_dark.png + naver_dark.png) + iOS gitignored
      // (kakao_dark_ios.png + naver_dark_ios.png — Apple Font License 회피).

      testWidgets('Naver dark', (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 480));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          _wrap(
            BrandedSocialButton.naver(
              label: 'Log in with NAVER',
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

      testWidgets(
        'Naver dark (iOS)',
        skip: !Platform.isMacOS,
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(360, 480));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            _wrap(
              BrandedSocialButton.naver(
                label: 'Log in with NAVER',
                onPressed: () {},
              ),
              brightness: Brightness.dark,
              platform: TargetPlatform.iOS,
            ),
          );
          await _settleAssets(tester);
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/naver_dark_ios.png'),
          );
        },
      );

      testWidgets('Kakao light', (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 480));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          _wrap(
            BrandedSocialButton.kakao(
              label: 'Login with Kakao',
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

      // Phase 13.3 Wave 4 Step 3 (2026-05-16) — Step B platform 분기 fixture
      // (macOS dev only). ThemeData.platform = TargetPlatform.iOS override →
      // _renderKakaoButton 의 `isIOS` branch 트리거 (fontFamily
      // 'AppleSDGothicNeo' + w500, PSD verbatim native). `/System/Library/
      // Fonts/AppleSDGothicNeo.ttc` 시스템 폰트를 FontLoader 로 macOS dev
      // 환경에서 로컬 로드. PNG fixture 는 `.gitignore` 로 commit 차단 (Apple
      // Font License + Sandoll 라이센스 위반 위험 회피, repo distribute 안 함).
      // CI/Linux 환경은 `skip` 매개변수로 우회.
      // skip: !Platform.isMacOS — AppleSDGothicNeo 시스템 폰트가 macOS 에만
      // 존재하므로 다른 OS (Linux CI, Windows) 에서는 자동 skip. macOS dev
      // 환경에서만 golden 생성/비교.
      testWidgets(
        'Kakao light (iOS)',
        skip: !Platform.isMacOS,
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(360, 480));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            _wrap(
              BrandedSocialButton.kakao(
                label: 'Login with Kakao',
                onPressed: () {},
              ),
              brightness: Brightness.light,
              platform: TargetPlatform.iOS,
            ),
          );
          await _settleAssets(tester);
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/kakao_light_ios.png'),
          );
        },
      );

      // Phase 13.3 X3 (2026-05-17, 260517-uv4) — Kakao dark golden testcase
      // 추가 (light/dark 외관 동일 invariant 회귀 가드).
      testWidgets('Kakao dark', (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 480));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          _wrap(
            BrandedSocialButton.kakao(
              label: 'Login with Kakao',
              onPressed: () {},
            ),
            brightness: Brightness.dark,
          ),
        );
        await _settleAssets(tester);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/kakao_dark.png'),
        );
      });

      testWidgets(
        'Kakao dark (iOS)',
        skip: !Platform.isMacOS,
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(360, 480));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            _wrap(
              BrandedSocialButton.kakao(
                label: 'Login with Kakao',
                onPressed: () {},
              ),
              brightness: Brightness.dark,
              platform: TargetPlatform.iOS,
            ),
          );
          await _settleAssets(tester);
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/kakao_dark_ios.png'),
          );
        },
      );

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

      // Phase 13.3 Wave 4 Step 3 (2026-05-16) — Google iOS branch fixture
      // (macOS dev only). ThemeData.platform = TargetPlatform.iOS override
      // → _renderGoogleButton 의 isApplePlatform branch (fontFamily 'SF Pro
      // Text' + padding.horizontal 16 + logoLabelGap 12). PNG fixture 는
      // `.gitignore` 로 commit 차단 (Apple SF Pro Font License 위반 위험
      // 회피).
      testWidgets(
        'Google light (iOS)',
        skip: !Platform.isMacOS,
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(360, 480));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            _wrap(
              BrandedSocialButton.google(
                label: 'Sign in with Google',
                onPressed: () {},
              ),
              brightness: Brightness.light,
              platform: TargetPlatform.iOS,
            ),
          );
          await _settleAssets(tester);
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/google_light_ios.png'),
          );
        },
      );

      testWidgets(
        'Google dark (iOS)',
        skip: !Platform.isMacOS,
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(360, 480));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            _wrap(
              BrandedSocialButton.google(
                label: 'Sign in with Google',
                onPressed: () {},
              ),
              brightness: Brightness.dark,
              platform: TargetPlatform.iOS,
            ),
          );
          await _settleAssets(tester);
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/google_dark_ios.png'),
          );
        },
      );

      // Phase 13.3 R1 (Wave 3 D-117) — GoogleTheme.neutral enum 폐기 +
      // `goldens/google_neutral.png` fixture rm (Wave 4 Task 4.5).
      // Universal Layout Pattern 으로 통합 → light/dark 2 fixture 만 보존.

      // Phase 13.2 Plan 13.2-06 — Facebook fixture 신규 (옵션 A pivot 후).
      // Phase 13.3 Wave 4 Step 3 (2026-05-17) — Google CSS mirror 채택 후
      // fixture 매트릭스 확장. Google 패턴 머레 — light + dark + light_ios +
      // dark_ios 의 4 fixture.
      //
      // **starter kit drift 회피 (사용자 결정 2026-05-17):** Facebook 정문
      // 자유 영역 (bg/label color/fontFamily/size/weight 모두 정성 권고만)
      // → 5 provider 시각 consistency 위해 Google CSS verbatim 패턴 머레:
      //   bg     light #FFFFFF / dark #131314
      //   label  light #1F1F1F / dark #E3E3E3
      //   outline light #DADCE0 / dark #8E918F (1dp inside)
      //   font   Roboto (Android) / SF Pro Text (iOS), size 14 / w500 /
      //          height 20/14 / letterSpacing 0.25 (Android) / -0.15 (iOS)
      //   disabled Opacity 0.38 (`.gsi-material-button:disabled` verbatim)
      //
      // **fixture 차원:** 360×480 canvas + en locale + zero pixel tolerance.
      // wide button render 결과는 360×48 (Material Design 표준 button height,
      // Phase 13.1 spec.height 일관). Logo SVG (Meta Brand Asset Pack 의 AI
      // PyMuPDF verbatim 추출, 2 paths blue circle #0866FF + white 'f') 를
      // 18dp icon 슬롯 fit.
      testWidgets('Facebook light', (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 480));
        addTearDown(() => tester.binding.setSurfaceSize(null));
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
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/facebook_light.png'),
        );
      });

      testWidgets('Facebook dark', (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 480));
        addTearDown(() => tester.binding.setSurfaceSize(null));
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
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/facebook_dark.png'),
        );
      });

      // Phase 13.3 Wave 4 Step 3 (2026-05-17) — Facebook iOS branch fixture
      // (macOS dev only). ThemeData.platform = TargetPlatform.iOS override →
      // _renderFacebookButton 의 isApplePlatform branch (fontFamily 'SF Pro
      // Text' + letterSpacing -0.15). PNG fixture 는 `.gitignore` 로 commit
      // 차단 (Apple SF Pro Font License 위반 위험 회피, Google iOS 패턴 머레).
      testWidgets(
        'Facebook light (iOS)',
        skip: !Platform.isMacOS,
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(360, 480));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            _wrap(
              BrandedSocialButton.facebook(
                label: 'Login with Facebook',
                onPressed: () {},
              ),
              brightness: Brightness.light,
              platform: TargetPlatform.iOS,
            ),
          );
          await _settleAssets(tester);
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/facebook_light_ios.png'),
          );
        },
      );

      testWidgets(
        'Facebook dark (iOS)',
        skip: !Platform.isMacOS,
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(360, 480));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            _wrap(
              BrandedSocialButton.facebook(
                label: 'Login with Facebook',
                onPressed: () {},
              ),
              brightness: Brightness.dark,
              platform: TargetPlatform.iOS,
            ),
          );
          await _settleAssets(tester);
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/facebook_dark_ios.png'),
          );
        },
      );

      // Phase 13.3 Wave 4 Step 2 (2026-05-15): Apple SDK 위제 → 자체 render
      // (`_renderAppleButton`) 전환. Apple 공식 Logo-only SVG (Black variant)
      // + wrapper bg pure white (SVG rect 흰과 정확 일치 → 정사각 외곽
      // invisible). HIG mandate "Match the height of the logo file to the
      // height of the button" — SVG render size = button height (48dp).
      testWidgets('Apple light', (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 480));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          _wrap(
            BrandedSocialButton.apple(
              label: 'Sign in with Apple',
              onPressed: () {},
            ),
            brightness: Brightness.light,
          ),
        );
        await _settleAssets(tester);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/apple_light.png'),
        );
      });

      // Apple dark variant — White SVG (rect 검정 + logo 흰) + wrapper bg
      // pure black 일치. light + dark 두 fixture 모두 검증 (Apple 의 자체
      // dark variant 자산 채택 의도 명시).
      testWidgets('Apple dark', (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 480));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          _wrap(
            BrandedSocialButton.apple(
              label: 'Sign in with Apple',
              onPressed: () {},
            ),
            brightness: Brightness.dark,
          ),
        );
        await _settleAssets(tester);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/apple_dark.png'),
        );
      });

      // Phase 13.3 Wave 4 Step 3 (2026-05-16) — Apple iOS branch fixture
      // (macOS dev only). ThemeData.platform = TargetPlatform.iOS override
      // → _renderAppleButton 의 isApplePlatform branch (fontFamily 'SF Pro
      // Text' native macOS system font). PNG fixture 는 `.gitignore` 로
      // commit 차단 (Apple SF Pro Font License 위반 위험 회피).
      testWidgets(
        'Apple light (iOS)',
        skip: !Platform.isMacOS,
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(360, 480));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            _wrap(
              BrandedSocialButton.apple(
                label: 'Sign in with Apple',
                onPressed: () {},
              ),
              brightness: Brightness.light,
              platform: TargetPlatform.iOS,
            ),
          );
          await _settleAssets(tester);
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/apple_light_ios.png'),
          );
        },
      );

      testWidgets(
        'Apple dark (iOS)',
        skip: !Platform.isMacOS,
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(360, 480));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            _wrap(
              BrandedSocialButton.apple(
                label: 'Sign in with Apple',
                onPressed: () {},
              ),
              brightness: Brightness.dark,
              platform: TargetPlatform.iOS,
            ),
          );
          await _settleAssets(tester);
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/apple_dark_ios.png'),
          );
        },
      );
    },
  );
}
