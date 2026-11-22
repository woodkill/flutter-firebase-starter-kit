// 앱 기본 내비게이션 바 영역 [AppSystemBarsRegion] 과 실제로 보낸 합친 값.
//
// 앱은 화면마다 내비게이션 바 값을 따로 두지 않는다 — `lib/app.dart` builder 의
// 앱 맨 바깥 영역 하나가 내비게이션 바 값을 두지 않은 화면을 맡는다. 엔진은 null
// 필드를 건너뛰어 앞 화면 값을 그대로 두므로, 스플래시가 바꾼 내비게이션 바 세
// 필드(색 · 대비 강제 · 아이콘 밝기)를 이 영역이 같은 세 필드로 되돌려야 한다.
// 그래서 위젯 값뿐 아니라 시험 바인딩이 실제로 보낸 합친 값
// (`SystemChrome.latestStyle`)을 단언한다.

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
      expect(buildDefaultNavigationBarStyle(Brightness.light), _lightDefault);
      expect(buildDefaultNavigationBarStyle(Brightness.dark), _darkDefault);
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
  });
}
