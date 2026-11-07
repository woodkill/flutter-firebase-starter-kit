import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/app.dart';
import 'package:flutter_starter_kit/core/config/splash_config.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/home/presentation/home_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/planning_docs.dart';
import 'helpers/source_text.dart';

/// 실제 [App] 을 OS 고대비 설정 아래에서 그려 적용 팔레트를 고정한다.
///
/// - OS 가 대비 증가를 요청하면 홈 화면 테마는 같은 시드의 대비 1.0 팔레트다
///   (라이트 · 다크).
/// - 고대비를 끄면 기본 팔레트다(대조군).
/// - `lib/app.dart` 원문 대조는 유지보수자 트리에서만 본다 — 가이드가 adopter
///   에게 이 테마 연결 줄 손질을 안내한다.
///
/// pump 경로는 `test/widget_test.dart` 와 같다(Firebase 미초기화 · 스플래시
/// 최소 대기 1ms) — `lib/app.dart` 의 실제 연결을 지난다.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SplashConfig.overrideMinDuration = const Duration(milliseconds: 1);
  });

  tearDown(() {
    SplashConfig.overrideMinDuration = null;
  });

  /// 실제 [App] 을 홈 화면까지 그리고 홈 화면의 [ThemeData] 를 돌려준다.
  Future<ThemeData> pumpHomeTheme(
    WidgetTester tester, {
    required bool highContrast,
    Brightness platformBrightness = Brightness.light,
  }) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(highContrast: highContrast);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    tester.platformDispatcher.platformBrightnessTestValue = platformBrightness;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [isFirebaseInitializedProvider.overrideWithValue(false)],
        child: const App(),
      ),
    );
    // 스플래시 최소 대기(1ms) + 리다이렉트 → 홈 도착 대기.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    return Theme.of(tester.element(find.byType(HomeScreen)));
  }

  test(
    'T-24-HC-01: lib/app.dart 가 같은 시드의 대비 1.0 테마를 고대비 자리에 단다',
    () {
      final String code = stripSlashComments(readTrackedFile('lib/app.dart'));

      final patterns = <RegExp>[
        RegExp(
          r'highContrastTheme:\s*AppTheme\.light\(\s*seedColor:\s*seed,'
          r'\s*contrastLevel:\s*1\.0',
        ),
        RegExp(
          r'highContrastDarkTheme:\s*AppTheme\.dark\(\s*seedColor:\s*seed,'
          r'\s*contrastLevel:\s*1\.0',
        ),
        RegExp(r'\btheme:\s*AppTheme\.light\(\s*seedColor:\s*seed\s*\)'),
        RegExp(r'\bdarkTheme:\s*AppTheme\.dark\(\s*seedColor:\s*seed\s*\)'),
      ];
      for (final pattern in patterns) {
        expect(
          pattern.allMatches(code),
          hasLength(1),
          reason: '${pattern.pattern} 가 정확히 한 번 있어야 한다.',
        );
      }
    },
    // 가이드가 adopter 에게 app.dart 테마 손질을 안내하므로 유지보수자 트리에서만 본다.
    skip: skipUnlessMaintainerTree(),
  );

  testWidgets('T-24-HC-02: 고대비 켬 + 라이트 → 대비 1.0 라이트 팔레트', (tester) async {
    final theme = await pumpHomeTheme(tester, highContrast: true);

    expect(
      theme.colorScheme,
      equals(
        AppTheme.light(
          seedColor: AppTheme.brandColor,
          contrastLevel: 1,
        ).colorScheme,
      ),
    );
    expect(
      theme.colorScheme,
      isNot(equals(AppTheme.light(seedColor: AppTheme.brandColor).colorScheme)),
    );
  });

  testWidgets('T-24-HC-03: 고대비 켬 + 플랫폼 다크 → 대비 1.0 다크 팔레트', (tester) async {
    final theme = await pumpHomeTheme(
      tester,
      highContrast: true,
      platformBrightness: Brightness.dark,
    );

    expect(theme.brightness, equals(Brightness.dark));
    expect(
      theme.colorScheme,
      equals(
        AppTheme.dark(
          seedColor: AppTheme.brandColor,
          contrastLevel: 1,
        ).colorScheme,
      ),
    );
    expect(
      theme.colorScheme,
      isNot(equals(AppTheme.dark(seedColor: AppTheme.brandColor).colorScheme)),
    );
  });

  testWidgets('T-24-HC-04: 고대비 끔 → 기본 라이트 팔레트(대조군)', (tester) async {
    final theme = await pumpHomeTheme(tester, highContrast: false);

    expect(
      theme.colorScheme,
      equals(AppTheme.light(seedColor: AppTheme.brandColor).colorScheme),
    );
  });
}
