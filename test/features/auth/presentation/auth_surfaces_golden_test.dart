// Phase 16.1 — UI-REVIEW Top fix ② (2026-09-10, /gsd-add-tests 16.1).
//
// A/B/C/D 4 surface 의 pixel 회귀 가드. 기존 layout test
// (`login_screen_layout_test.dart` 등) 는 위젯 존재·좌표 대소
// (`social.dy < cta.dy`) 만 단언하고, 실제 렌더된 간격·타이포·정렬은
// 고정하지 않았다 (Plan 01~04 SUMMARY D6/D8 `human_judgment: true`).
// 본 file 은 UI-SPEC §Layout Contract 의 시각 계약을 fixture PNG 로 고정한다.
//
// **매트릭스:** 4 surface × light/dark = 8 fixture · viewport 360×800
// (UI-SPEC "360×800 폰 fit" 계약) · locale en · provider 7 (`_allStrategies`
// 순서 verbatim — D8 "chooser 시각 위계·360×800 fit" 갭 직격) · Android
// platform (test env default).
// - iOS variant 미생성 — 본 phase 신규 delta 에 platform 분기가 0 이고,
//   provider 버튼의 iOS 분기는 Phase 13.3
//   `_widgets/branded_social_button_golden_test.dart` 가 별도 고정한다.
// - ko/ja 미생성 — Roboto 에 CJK 글리프가 없어 tofu 로 렌더된다. 문자열
//   자체는 `test/l10n/email_relegation_arb_verbatim_test.dart` 가 고정한다.
//
// **fixture 갱신:** `fvm flutter test --update-goldens <this file>` 후 PNG
// diff 시각 review 의무 (analyze 만으로는 image-diff 불가 — Phase 13.1 WR-03).

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/core/auth/auth_strategies_registry.dart';
import 'package:flutter_starter_kit/core/auth/auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/apple_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/facebook_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/google_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/kakao_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/line_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/naver_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/yahoojp_auth_strategy.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/login_prompt_sheet.dart';
import 'package:flutter_starter_kit/features/auth/presentation/email_login_screen.dart';
import 'package:flutter_starter_kit/features/auth/presentation/email_signup_screen.dart';
import 'package:flutter_starter_kit/features/auth/presentation/login_screen.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

/// [AuthRepository] 를 mocktail 로 대체하기 위한 Mock.
///
/// golden 은 탭을 발생시키지 않으므로 stub 은 두지 않는다.
class _MockAuthRepository extends Mock implements AuthRepository {}

/// golden viewport — UI-SPEC §Surface A "360×800 폰 본문 영역" 계약 (logical
/// px). [_goldenDevicePixelRatio] 3.0 과 함께 [TestFlutterView.physicalSize]
/// 로 주입하므로 fixture PNG 는 1080×2400 px 이다 (기존 button golden
/// 360×480 → 1080×1440 과 동일 규칙).
///
/// `setSurfaceSize` 를 쓰지 않는다 — 그 API 는 render view 만 바꾸고
/// `MediaQuery` 는 default 800×600 을 유지하므로, Surface D 의
/// `showLoginPromptSheet` 가 `MediaQuery.sizeOf(context).height * 0.75` 로
/// 계산하는 최대 높이가 600 이 아닌 450 (= 800 × 9/16 과 우연히 일치) 으로
/// 잘려 production 과 다른 sheet 가 찍힌다 (2026-09-10 scratch 실측).
const Size _goldenLogicalSize = Size(360, 800);

/// golden device pixel ratio — test view 기본값과 같은 3.0 을 명시해 fixture
/// 해상도를 환경 기본값 변화로부터 고정한다.
const double _goldenDevicePixelRatio = 3.0;

/// 현행 활성 provider 7종 — `_allStrategies` 선언 순서 verbatim
/// (Google · Apple · Facebook · Kakao · Naver · LINE · Yahoo!JP).
///
/// 다른 16.1 harness 의 3 provider (Google/Apple/Facebook) 대신 production
/// 기본값 7 을 쓴다 — UI-SPEC 의 "7 provider 는 360×800 에서 스크롤 없이
/// fit (≈652 dp < 736 dp)" 시각 계약이 golden 의 검증 대상이기 때문이다.
const List<AuthStrategy> _sevenStrategies = <AuthStrategy>[
  GoogleAuthStrategy(),
  AppleAuthStrategy(),
  FacebookAuthStrategy(),
  KakaoAuthStrategy(),
  NaverAuthStrategy(),
  LineAuthStrategy(),
  YahoojpAuthStrategy(),
];

/// [family] 이름으로 [paths] 의 폰트 파일들을 [FontLoader] 에 등록한다.
///
/// 자산 부재는 generic `FileSystemException` 대신 [TestFailure] 로 surface
/// 한다 (Phase 13.3 IN-06 패턴 — bundle rotation 시 phase-context 메시지).
Future<void> _loadFamily(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) {
      throw TestFailure(
        '$family 폰트 자산 부재 ($path) — Phase 16.1 A/B/C/D golden 생성 불가. '
        'production bundle 자산 (`pubspec.yaml` fonts:) 누락 여부 확인 의무.',
      );
    }
    final bytes = await file.readAsBytes();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

/// golden 라벨 글리프용 폰트 3 family 를 등록한다.
///
/// flutter_test 는 pubspec `fonts:` 를 자동 로드하지 않아 미등록 family 는
/// FlutterTest(Ahem) 정사각 box 로 렌더된다 (Phase 13.3 D-119). 4 surface 가
/// 렌더하는 family 는 다음 3종이다.
///
/// - `Roboto` — M3 textTheme 전체 (AppBar title · 본문 · CTA · 링크) +
///   Google/Facebook 라벨 + LINE/Yahoo!JP 라벨 (`DefaultTextStyle` 상속).
///   production bundle 의 variable font 를 그대로 로드한다 — pubspec 이
///   'Roboto' family 로 선언하므로 실 단말도 이 자산으로 렌더한다
///   (golden = production 렌더). 기존 button golden 이 쓰는 static
///   `assets/test_fonts/Roboto-Medium.ttf` 는 w400 본문을 Medium 으로
///   그리므로 화면 단위 golden 에는 부적합하다.
/// - `Inter` Regular/Medium — Apple 라벨 Android 분기.
/// - `Pretendard` variable — Kakao/Naver 라벨 Android 분기.
Future<void> _loadGoldenFonts() async {
  await _loadFamily('Roboto', <String>[
    'assets/fonts/roboto/Roboto-VariableFont_wdth_wght.ttf',
  ]);
  await _loadFamily('Inter', <String>[
    'assets/fonts/inter/Inter-Regular.ttf',
    'assets/fonts/inter/Inter-Medium.ttf',
  ]);
  await _loadFamily('Pretendard', <String>[
    'assets/fonts/pretendard/PretendardVariable.ttf',
  ]);
  await _loadMaterialIcons();
}

/// Flutter SDK cache 의 MaterialIcons 폰트를 등록한다.
///
/// `PasswordField` 의 가시성 토글 아이콘과 B/C AppBar 의 back 화살표
/// ([Icons]) 가 미등록 시 정사각 box 로 찍힌다. `flutter test` 가 주입하는
/// `FLUTTER_ROOT` 환경변수 아래 `bin/cache/artifacts/material_fonts/` 는
/// flutter tool 이 production bundle 에 동봉하는 바로 그 파일이다 — golden 이
/// 실 단말과 같은 글리프를 쓴다. 부재 시 [TestFailure] 로 surface 한다
/// (SDK 캐시 경로 변경 시 silent fallback 으로 fixture 가 자동 갱신되는 drift
/// 회피).
Future<void> _loadMaterialIcons() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot == null || flutterRoot.isEmpty) {
    throw TestFailure(
      'FLUTTER_ROOT 환경변수 부재 — MaterialIcons 폰트 경로를 결정할 수 없다. '
      '`fvm flutter test` 로 실행했는지 확인 의무.',
    );
  }
  await _loadFamily('MaterialIcons', <String>[
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ]);
}

/// 비동기 brand 자산 (SVG/PNG) 디코딩을 흡수한 뒤 frame 을 안정화한다.
///
/// Phase 13.1 Gap-1 X2 정정 패턴 mirror — `pumpAndSettle` 만으로는 flutter_svg
/// 의 microtask 기반 로드가 끝나기 전에 capture 되어 자상이 빈 placeholder
/// 로 찍힌다. `runAsync` 안에서 (1) `Image` 강제 디코딩 (2) SVG 로드 흡수
/// delay (3) 최종 settle 을 수행하고, 밖에서 한 번 더 pump 해 capture 단계로
/// commit 한다.
Future<void> _settleAssets(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.pumpAndSettle();
    for (final element in find.byType(Image).evaluate().toList()) {
      final widget = element.widget as Image;
      await precacheImage(widget.image, element);
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
  });
  await tester.pumpAndSettle();
}

/// [home] 을 [brightness] 테마 + en locale + 7 provider override 로 감싼다.
///
/// `debugShowCheckedModeBanner: false` — DEBUG 배너가 capture 에 섞이지
/// 않도록. override 목록은 다른 16.1 screen harness 와 동형이다
/// (`authRepositoryProvider` + `activeStrategiesProvider(en)`).
Widget _wrapApp({required Brightness brightness, required Widget home}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(_MockAuthRepository()),
      activeStrategiesProvider(
        const Locale('en'),
      ).overrideWithValue(_sevenStrategies),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: brightness == Brightness.light
          ? AppTheme.light()
          : AppTheme.dark(),
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    ),
  );
}

/// surface 가 production 에서 화면에 오르는 방식.
///
/// UI-SPEC §Layout Contract 의 진입 계약을 golden 에 그대로 반영한다 —
/// B/C 는 "항상 chooser 위에 push 된 상태로 진입" 이라 AppBar back 화살표가
/// 외관의 일부이고, D 는 `showModalBottomSheet` 의 scrim·radius·drag handle
/// 이 외관의 일부다.
enum _Entry {
  /// [MaterialApp.home] 으로 직접 렌더 — Surface A (`/login`, back 없음).
  home,

  /// 빈 [Scaffold] 위에 [MaterialPageRoute] 로 push — Surface B/C
  /// (`showBackButton: true`, back 화살표 렌더).
  pushed,

  /// 빈 [Scaffold] context 로 [showLoginPromptSheet] 직접 호출 — Surface D
  /// (트리거 버튼 없이 scrim + sheet 만 capture). 반환 Future 는 sheet 가
  /// 닫힐 때 완료되므로 test 안에서는 기다리지 않는다.
  sheet,
}

/// [surface] 를 [entry] 방식으로 golden viewport 에 올리고 자산을 settle
/// 한다. [_Entry.sheet] 는 [surface] 를 쓰지 않는다.
Future<void> _pumpSurface(
  WidgetTester tester, {
  required Brightness brightness,
  required _Entry entry,
  Widget? surface,
}) async {
  tester.view.devicePixelRatio = _goldenDevicePixelRatio;
  tester.view.physicalSize = _goldenLogicalSize * _goldenDevicePixelRatio;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final home = switch (entry) {
    _Entry.home => surface!,
    _Entry.pushed || _Entry.sheet => const Scaffold(),
  };
  await tester.pumpWidget(_wrapApp(brightness: brightness, home: home));
  await tester.pump();

  switch (entry) {
    case _Entry.home:
      break;
    case _Entry.pushed:
      final context = tester.element(find.byType(Scaffold));
      unawaited(
        Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => surface!)),
      );
    case _Entry.sheet:
      unawaited(showLoginPromptSheet(tester.element(find.byType(Scaffold))));
  }
  await _settleAssets(tester);
}

/// layout 예외 0 을 먼저 확인한 뒤 [MaterialApp] 전체를 `goldens/[fileName]`
/// 과 비교한다.
///
/// overflow 가 나면 golden 이 노란 줄무늬를 포함한 채 통과할 수 있으므로,
/// 시각 계약을 대표하는 fixture 임을 `takeException` 으로 먼저 보장한다.
Future<void> _expectSurfaceGolden(WidgetTester tester, String fileName) async {
  expect(
    tester.takeException(),
    isNull,
    reason: 'RenderFlex overflow 등 layout 예외 0 이어야 golden 이 시각 계약을 대표한다',
  );
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$fileName'),
  );
}

void main() {
  setUpAll(_loadGoldenFonts);

  group('Phase 16.1 A/B/C/D surface golden — 360×800 · en · 7 provider', () {
    for (final brightness in <Brightness>[Brightness.light, Brightness.dark]) {
      final mode = brightness.name;

      testWidgets('Surface A LoginScreen chooser — $mode', (tester) async {
        await _pumpSurface(
          tester,
          brightness: brightness,
          entry: _Entry.home,
          surface: const LoginScreen(),
        );
        await _expectSurfaceGolden(tester, 'login_screen_$mode.png');
      });

      testWidgets('Surface B EmailLoginScreen — $mode', (tester) async {
        await _pumpSurface(
          tester,
          brightness: brightness,
          entry: _Entry.pushed,
          surface: const EmailLoginScreen(),
        );
        await _expectSurfaceGolden(tester, 'email_login_screen_$mode.png');
      });

      testWidgets('Surface C EmailSignupScreen — $mode', (tester) async {
        await _pumpSurface(
          tester,
          brightness: brightness,
          entry: _Entry.pushed,
          surface: const EmailSignupScreen(),
        );
        await _expectSurfaceGolden(tester, 'email_signup_screen_$mode.png');
      });

      testWidgets('Surface D LoginPromptSheet — $mode', (tester) async {
        await _pumpSurface(tester, brightness: brightness, entry: _Entry.sheet);
        await _expectSurfaceGolden(tester, 'login_prompt_sheet_$mode.png');
      });
    }
  });
}
