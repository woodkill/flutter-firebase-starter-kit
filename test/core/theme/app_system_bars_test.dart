// 앱 기본 내비게이션 바 영역 [AppSystemBarsRegion] 과 실제로 보낸 합친 값.
//
// 앱은 화면마다 내비게이션 바 값을 따로 두지 않는다 — `lib/app.dart` builder 의
// 앱 맨 바깥 영역 하나가 내비게이션 바 값을 두지 않은 화면을 맡는다. 엔진은 null
// 필드를 건너뛰어 앞 화면 값을 그대로 두므로, 스플래시가 바꾼 내비게이션 바 세
// 필드(색 · 대비 강제 · 아이콘 밝기)를 이 영역이 같은 세 필드로 되돌려야 한다.
// Android 에서는 AppBar 없는 화면의 상태 표시줄 값도 이 영역이 맡는다.
// 그래서 위젯 값뿐 아니라 시험 바인딩이 실제로 보낸 합친 값
// (`SystemChrome.latestStyle`)을 단언한다.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/app.dart';
import 'package:flutter_starter_kit/core/config/splash_config.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/theme/app_system_bars.dart';
import 'package:flutter_starter_kit/features/home/presentation/home_screen.dart';
import 'package:flutter_starter_kit/features/splash/presentation/splash_frame.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// OS 라이트 기본값 — 라이트 막 · 대비 강제 · 어두운 아이콘.
const SystemUiOverlayStyle _lightDefault = SystemUiOverlayStyle(
  systemNavigationBarColor: Color(0xE6FFFFFF),
  systemNavigationBarContrastEnforced: true,
  systemNavigationBarIconBrightness: Brightness.dark,
);

/// OS 다크 기본값 — 다크 막(검정 약 80%) · 대비 강제 · 밝은 아이콘.
const SystemUiOverlayStyle _darkDefault = SystemUiOverlayStyle(
  systemNavigationBarColor: Color(0xCC000000),
  systemNavigationBarContrastEnforced: true,
  systemNavigationBarIconBrightness: Brightness.light,
);

/// 제스처 내비게이션 · OS 라이트 기본값 — 투명 · 대비 강제 · 어두운 아이콘.
const SystemUiOverlayStyle _lightGesture = SystemUiOverlayStyle(
  systemNavigationBarColor: Color(0x00000000),
  systemNavigationBarContrastEnforced: true,
  systemNavigationBarIconBrightness: Brightness.dark,
);

/// 제스처 내비게이션 · OS 다크 기본값 — 투명 · 대비 강제 · 밝은 아이콘.
const SystemUiOverlayStyle _darkGesture = SystemUiOverlayStyle(
  systemNavigationBarColor: Color(0x00000000),
  systemNavigationBarContrastEnforced: true,
  systemNavigationBarIconBrightness: Brightness.light,
);

/// 킷 기본 스플래시 배경(밝음) 위 스플래시 값 — 막 없이 투명 · 대비 강제 끔 ·
/// 배경 밝기 판정 아이콘(밝은 배경이라 어두운 아이콘).
const SystemUiOverlayStyle _splashOnLight = SystemUiOverlayStyle(
  systemNavigationBarColor: Color(0x00000000),
  systemNavigationBarContrastEnforced: false,
  systemNavigationBarIconBrightness: Brightness.dark,
);

/// [style] 의 내비게이션 바 세 필드가 [expected] 와 같고 구분선이 null 인지
/// 단언한다.
void _expectNavigationBar(
  SystemUiOverlayStyle? style,
  SystemUiOverlayStyle expected,
) {
  expect(style, isNotNull, reason: '시험 바인딩이 보낸 값이 없다');
  expect(style!.systemNavigationBarColor, expected.systemNavigationBarColor);
  expect(
    style.systemNavigationBarContrastEnforced,
    expected.systemNavigationBarContrastEnforced,
  );
  expect(
    style.systemNavigationBarIconBrightness,
    expected.systemNavigationBarIconBrightness,
  );
  expect(style.systemNavigationBarDividerColor, isNull);
}

/// 앱 바깥 영역만 둔 [MaterialApp] 에 [home] 을 띄운다 — `lib/app.dart` builder 꼴.
///
/// [theme] 이 null 이면 SDK 기본 라이트 테마다.
Future<void> _pumpWithRegion(
  WidgetTester tester,
  Widget home, {
  ThemeData? theme,
}) => tester.pumpWidget(
  MaterialApp(
    theme: theme,
    builder: (context, child) => AppSystemBarsRegion(child: child!),
    home: home,
  ),
);

/// 실제 [App] 을 Firebase 없이 띄운다 — 첫 프레임은 스플래시다.
Future<void> _pumpApp(WidgetTester tester) => tester.pumpWidget(
  ProviderScope(
    overrides: [isFirebaseInitializedProvider.overrideWithValue(false)],
    child: const App(),
  ),
);

/// 스플래시 최소 대기를 지나 홈 화면에 닿게 한다.
Future<void> _advanceToHome(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pumpAndSettle();
  expect(find.byType(HomeScreen), findsOneWidget);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SplashConfig.overrideMinDuration = const Duration(milliseconds: 1);
  });

  tearDown(() {
    SplashConfig.overrideMinDuration = null;
  });

  group('AppSystemBarsRegion', () {
    testWidgets('T-30-BARS-01: 실제 App 홈 — 기본 영역 하나 · 내비게이션 바 세 필드 = '
        'OS 라이트 기본값 · 구분선 null', (tester) async {
      await _pumpApp(tester);
      await _advanceToHome(tester);

      expect(find.byType(AppSystemBarsRegion), findsOneWidget);
      _expectNavigationBar(SystemChrome.latestStyle, _lightDefault);
    });

    test('T-30-BARS-02: 기본값은 밝기마다 내비게이션 바 세 필드만 담는다', () {
      // 전체 `==` — 상태 표시줄 네 필드 · 구분선은 null 이어야 한다.
      expect(
        buildDefaultNavigationBarStyle(
          Brightness.light,
          isGestureNavigation: false,
        ),
        _lightDefault,
      );
      expect(
        buildDefaultNavigationBarStyle(
          Brightness.dark,
          isGestureNavigation: false,
        ),
        _darkDefault,
      );
      // 제스처 내비게이션 — 색만 투명이고 대비 강제 · 아이콘은 같다.
      expect(
        buildDefaultNavigationBarStyle(
          Brightness.light,
          isGestureNavigation: true,
        ),
        _lightGesture,
      );
      expect(
        buildDefaultNavigationBarStyle(
          Brightness.dark,
          isGestureNavigation: true,
        ),
        _darkGesture,
      );
    });

    testWidgets('T-30-BARS-03: 실제 App 첫 프레임(스플래시) — 내비게이션 바 세 필드 = '
        '스플래시 값 · 홈에 닿으면 기본값', (tester) async {
      await _pumpApp(tester);

      expect(find.byType(SplashFrame), findsOneWidget);
      _expectNavigationBar(SystemChrome.latestStyle, _splashOnLight);

      // 스플래시 값이 다음 화면에 남지 않는다 — 기본 영역이 되돌린다.
      await _advanceToHome(tester);
      _expectNavigationBar(SystemChrome.latestStyle, _lightDefault);
    });

    testWidgets('T-30-BARS-04: 실제 App · OS 다크 → 홈 — 내비게이션 바 세 필드 = '
        'OS 다크 기본값', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await _pumpApp(tester);
      await _advanceToHome(tester);

      _expectNavigationBar(SystemChrome.latestStyle, _darkDefault);
    });

    testWidgets('T-30-BARS-05: 실제 App · OS 다크 + 앱 테마 라이트 → 홈 — 막 색 · '
        '아이콘은 OS 밝기 기준(다크 기본값)', (tester) async {
      // theme_mode 1 = ThemeMode.light — setUp 의 빈 값을 덮는다.
      SharedPreferences.setMockInitialValues({'theme_mode': 1});
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await _pumpApp(tester);
      await _advanceToHome(tester);

      // 전제 — 홈의 앱 테마는 라이트다(OS 와 다른 칸).
      expect(
        Theme.of(tester.element(find.byType(HomeScreen))).brightness,
        Brightness.light,
      );
      _expectNavigationBar(SystemChrome.latestStyle, _darkDefault);
    });

    testWidgets('T-30-BARS-06: AppBar 화면 — 상태 표시줄은 AppBar 값 · 내비게이션 바 '
        '세 필드는 기본값', (tester) async {
      await _pumpWithRegion(
        tester,
        Scaffold(appBar: AppBar(title: const Text('AppBar'))),
      );

      final SystemUiOverlayStyle? style = SystemChrome.latestStyle;
      _expectNavigationBar(style, _lightDefault);
      // 밝은 AppBar 의 상태 표시줄 값이 나간다.
      expect(style!.statusBarColor, const Color(0x00000000));
      expect(style.statusBarIconBrightness, Brightness.dark);
      expect(style.statusBarBrightness, Brightness.light);
    });

    testWidgets('T-30-BARS-07: 안쪽 화면 전체 영역이 기본 영역을 이긴다 — 내비게이션 '
        '바 세 필드를 담으면 그 값 · 상태 표시줄 필드만 담으면 내비게이션 바는 null', (tester) async {
      const innerNavigation = SystemUiOverlayStyle(
        systemNavigationBarColor: Color(0xFF00FF00),
        systemNavigationBarContrastEnforced: false,
        systemNavigationBarIconBrightness: Brightness.light,
      );
      await _pumpWithRegion(
        tester,
        const AnnotatedRegion<SystemUiOverlayStyle>(
          value: innerNavigation,
          child: Scaffold(body: Text('inner')),
        ),
      );
      expect(SystemChrome.latestStyle, innerNavigation);

      // 상태 표시줄 필드만 담은 화면 — 기본 영역 값이 섞이지 않아 내비게이션 바
      // 필드가 null 로 나간다. 그래서 내 화면 영역은 세 필드를 모두 적는다.
      const innerStatusOnly = SystemUiOverlayStyle(
        statusBarColor: Color(0x00000000),
        statusBarIconBrightness: Brightness.light,
      );
      await _pumpWithRegion(
        tester,
        const AnnotatedRegion<SystemUiOverlayStyle>(
          value: innerStatusOnly,
          child: Scaffold(body: Text('inner')),
        ),
      );
      expect(SystemChrome.latestStyle, innerStatusOnly);
      expect(SystemChrome.latestStyle!.systemNavigationBarColor, isNull);
    });

    testWidgets('T-30-BARS-08: iOS · 영역 없는 화면 — 보낸 값이 모두 null(상태 표시줄 '
        '밝기 null)', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await _pumpWithRegion(tester, const Scaffold(body: Text('plain')));
      final SystemUiOverlayStyle? style = SystemChrome.latestStyle;
      final int regionCount = find
          .byType(AppSystemBarsRegion)
          .evaluate()
          .length;
      debugDefaultTargetPlatformOverride = null;

      expect(regionCount, 1);
      // iOS 엔진은 상태 표시줄 밝기가 null 이면 아무것도 하지 않는다 — 전체 `==`
      // 로 기본 영역이 상태 표시줄 값을 하나도 보내지 않음을 본다.
      expect(style, const SystemUiOverlayStyle());
      expect(style!.statusBarBrightness, isNull);
      expect(style.statusBarIconBrightness, isNull);
    });

    testWidgets('T-30-BARS-09: Android · AppBar 없는 화면 — 상태 표시줄 필드 = '
        '투명 바탕 · 앱 바탕(surface) 밝기의 반대 아이콘', (tester) async {
      // 밝은 바탕 — 어두운 아이콘.
      await _pumpWithRegion(tester, const Scaffold(body: Text('plain')));
      SystemUiOverlayStyle? style = SystemChrome.latestStyle;
      _expectNavigationBar(style, _lightDefault);
      expect(style!.statusBarColor, const Color(0x00000000));
      expect(style.statusBarIconBrightness, Brightness.dark);
      // iOS 용 필드는 담지 않는다.
      expect(style.statusBarBrightness, isNull);

      // 테마 밝기는 라이트인데 바탕만 어두운 화면 — 기준이 테마 밝기가 아니라
      // 바탕 색이므로 밝은 아이콘이다.
      await _pumpWithRegion(
        tester,
        const Scaffold(body: Text('plain')),
        theme: ThemeData(
          colorScheme: const ColorScheme.light(surface: Color(0xFF101010)),
        ),
      );
      // 앱 테마는 바뀔 때 애니메이션으로 옮겨 가므로 끝까지 진행한다.
      await tester.pumpAndSettle();
      style = SystemChrome.latestStyle;
      expect(style!.statusBarColor, const Color(0x00000000));
      expect(style.statusBarIconBrightness, Brightness.light);
      expect(style.statusBarBrightness, isNull);
    });

    testWidgets('T-30-BARS-10: Android · OS 다크 + 앱 바탕 라이트 — 상태 표시줄은 '
        '앱 바탕 기준 · 내비게이션 바는 OS 밝기 기준', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await _pumpWithRegion(tester, const Scaffold(body: Text('plain')));

      final SystemUiOverlayStyle? style = SystemChrome.latestStyle;
      _expectNavigationBar(style, _darkDefault);
      expect(style!.statusBarIconBrightness, Brightness.dark);
    });

    testWidgets('T-30-BARS-11: Android · AppBar 화면 — AppBar 의 상태 표시줄 값이 '
        '기본 영역 값을 이긴다', (tester) async {
      const appBarStatus = SystemUiOverlayStyle(
        statusBarColor: Color(0xFF0000FF),
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      );
      await _pumpWithRegion(
        tester,
        Scaffold(
          appBar: AppBar(
            title: const Text('AppBar'),
            systemOverlayStyle: appBarStatus,
          ),
        ),
      );

      final SystemUiOverlayStyle? style = SystemChrome.latestStyle;
      _expectNavigationBar(style, _lightDefault);
      expect(style!.statusBarColor, const Color(0xFF0000FF));
      expect(style.statusBarIconBrightness, Brightness.light);
      expect(style.statusBarBrightness, Brightness.dark);
    });

    testWidgets('T-30-BARS-12: Android · AppBar 의 systemOverlayStyle 에 적은 '
        '내비게이션 바 필드는 쓰이지 않는다 — 기본 영역 값이 나간다', (tester) async {
      const appBarStyle = SystemUiOverlayStyle(
        statusBarColor: Color(0xFF0000FF),
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFF00FF00),
        systemNavigationBarContrastEnforced: false,
        systemNavigationBarIconBrightness: Brightness.light,
      );
      await _pumpWithRegion(
        tester,
        Scaffold(
          appBar: AppBar(
            title: const Text('AppBar'),
            systemOverlayStyle: appBarStyle,
          ),
        ),
      );

      final SystemUiOverlayStyle? style = SystemChrome.latestStyle;
      // 화면 아래는 기본 영역이 맡는다 — AppBar 의 내비게이션 바 세 필드는 밀린다.
      _expectNavigationBar(style, _lightDefault);
      // 상태 표시줄 필드는 AppBar 값 그대로다.
      expect(style!.statusBarColor, const Color(0xFF0000FF));
      expect(style.statusBarIconBrightness, Brightness.light);
    });

    testWidgets('T-30-BARS-13: Android · 화면 왼쪽 제스처 영역이 있으면(제스처 '
        '내비게이션) 색만 투명 · 0 이면 3버튼 막', (tester) async {
      // 제스처 영역은 물리 픽셀로 준다 — 시험 화면 배율은 3 이다.
      addTearDown(tester.view.resetSystemGestureInsets);

      // 에뮬레이터 제스처 모드 크기(약 29.7 dp).
      tester.view.systemGestureInsets = const FakeViewPadding(left: 89);
      await _pumpWithRegion(tester, const Scaffold(body: Text('plain')));
      _expectNavigationBar(SystemChrome.latestStyle, _lightGesture);

      // 1 dp 보다 작은 영역도 제스처 내비게이션이다(판별 경계는 0).
      tester.view.systemGestureInsets = const FakeViewPadding(left: 1);
      await tester.pump();
      _expectNavigationBar(SystemChrome.latestStyle, _lightGesture);

      // 왼쪽이 0 이면 3버튼 막으로 돌아온다.
      tester.view.systemGestureInsets = FakeViewPadding.zero;
      await tester.pump();
      _expectNavigationBar(SystemChrome.latestStyle, _lightDefault);
    });

    testWidgets('T-30-BARS-14: Android · OS 다크 · 제스처 내비게이션 — 색만 투명 · '
        '밝은 아이콘 · 대비 강제', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      addTearDown(tester.view.resetSystemGestureInsets);
      tester.view.systemGestureInsets = const FakeViewPadding(left: 89);
      await _pumpWithRegion(tester, const Scaffold(body: Text('plain')));

      _expectNavigationBar(SystemChrome.latestStyle, _darkGesture);
    });
  });
}
