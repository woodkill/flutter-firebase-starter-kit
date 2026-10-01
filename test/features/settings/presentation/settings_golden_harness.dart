// Phase 16.10 Plan 16.10-08 Task 2 — 설정 · 탈퇴 진행 화면 golden 공용 harness.
//
// Phase 16.7 · 16.8 의 `settings_screen_golden_test.dart` private 함수를 승격했다
// (DRY — 진행 화면 golden 이 같은 캡처 조건을 공유한다). 본문은 verbatim 이고
// 진입 route · override 만 인자로 일반화했다 — 승격 뒤에도 설정 화면 golden 은
// byte 불변이어야 한다(16.8 채택안 `cmp`).
//
// **캡처 계약 (UI-SPEC §Golden 캡처 계약):** 280×800 logical · DPR 3 · 빈
// `Scaffold` 위 `MaterialPageRoute` push 진입(AppBar back 화살표 포함) ·
// production 폰트 FontLoader + `assets/test_fonts` Noto Sans CJK KR/JP subset ·
// test 전용 ThemeData 에만 `fontFamilyFallback` · `find.byType(MaterialApp)`
// 전체 캡처 · viewport 는 `tester.view` 로 주입(MediaQuery 동기화).
//
// 파일명이 `_test.dart` 가 아니라 테스트 러너가 단독 실행하지 않는다.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_starter_kit/core/auth/auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/apple_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/facebook_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/google_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/kakao_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/line_auth_strategy.dart';
import 'package:flutter_starter_kit/core/auth/strategies/naver_auth_strategy.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/notifications/application/notification_settings_notifier.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// golden device pixel ratio — mockup 촬영 조건(DPR 3)과 같다.
const double kGoldenDpr = 3.0;

/// golden viewport 높이 (logical px) — UI-SPEC §Golden 캡처 계약.
const double kGoldenHeight = 800;

/// 활성 소셜 Strategy 6종 — `settings_screen_test.dart` `_allStrategies` 순서.
const List<AuthStrategy> kGoldenSixStrategies = <AuthStrategy>[
  GoogleAuthStrategy(),
  AppleAuthStrategy(),
  FacebookAuthStrategy(),
  KakaoAuthStrategy(),
  NaverAuthStrategy(),
  LineAuthStrategy(),
];

/// [family] 이름으로 [paths] 의 폰트 파일들을 [FontLoader] 에 등록한다.
///
/// 자산 부재는 [TestFailure] 로 surface 한다 — silent fallback 으로 golden 이
/// tofu · Ahem 렌더로 바뀌는 drift 를 막는다.
Future<void> _loadFamily(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) {
      throw TestFailure(
        '$family 폰트 자산 부재 ($path) — Phase 16.7 golden 생성 불가. '
        'production bundle 자산 또는 assets/test_fonts 누락 여부 확인 의무.',
      );
    }
    final bytes = await file.readAsBytes();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

/// golden 폰트 5 family + CJK subset 2종을 등록한다.
///
/// flutter_test 는 pubspec `fonts:` 를 자동 로드하지 않고 동적 로드 폰트로
/// 자동 fallback 하지도 않는다 — ko/ja 글리프는 [goldenTheme] 의 test 전용
/// `fontFamilyFallback` 으로만 CJK subset 에 닿는다.
Future<void> loadGoldenFonts() async {
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
  await _loadFamily('MockCjkKR', <String>[
    'assets/test_fonts/NotoSansCJKKR-Regular-Subset.otf',
  ]);
  await _loadFamily('MockCjkJP', <String>[
    'assets/test_fonts/NotoSansCJKJP-Regular-Subset.otf',
  ]);
}

/// [lang] 의 CJK fallback family 이름 (ko/ja 외 null).
String? goldenCjkFamily(String lang) => switch (lang) {
  'ko' => 'MockCjkKR',
  'ja' => 'MockCjkJP',
  _ => null,
};

/// production [AppTheme] + ko/ja 만 test 전용 CJK `fontFamilyFallback`.
///
/// `lib/` 테마는 건드리지 않는다 — Android 시스템 CJK fallback 을 test 에서
/// 재현하는 장치다 (UI-SPEC §Mockup CJK 재현성).
ThemeData goldenTheme(Brightness brightness, String lang) {
  final base = brightness == Brightness.light
      ? AppTheme.light()
      : AppTheme.dark();
  final family = goldenCjkFamily(lang);
  if (family == null) return base;
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamilyFallback: <String>[family]),
  );
}

/// 비동기 이미지 디코딩을 흡수한 뒤 frame 을 안정화한다 (16.1 golden 패턴).
Future<void> settleGoldenAssets(WidgetTester tester) async {
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

/// 빈 [Scaffold] 위에 [route] 화면을 push 해 [width]×[kGoldenHeight] · DPR 3
/// viewport 에 올린다.
///
/// [overrides] 는 화면별 provider override(repository mock · 활성 strategy ·
/// 사용자 fixture · 상태 fixture)다. [ProviderScope] 에 새 key 를 줘 반복
/// pump 마다 새 container 를 만든다. 스피너 없는 상태만 대상이다 —
/// indeterminate 스피너가 있으면 settle 이 끝나지 않는다.
///
/// Phase 17 (T-17-NOTIF-12 · UI-SPEC §Golden 캡처 계약) — 설정 「알림」
/// 섹션은 harness 가 항상 꺼짐(`AsyncData(false)`)으로 고정한다. 미초기화
/// 기본값에 기대지 않으며, 호출부는 같은 provider 를 다시 override 하지 않는다.
Future<void> pumpGoldenRoute(
  WidgetTester tester, {
  required WidgetBuilder route,
  required List<Override> overrides,
  required Locale locale,
  required Brightness brightness,
  required double width,
}) async {
  tester.view.devicePixelRatio = kGoldenDpr;
  tester.view.physicalSize = Size(width, kGoldenHeight) * kGoldenDpr;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        notificationSettingsProvider.overrideWithBuild(
          (ref, notifier) => false,
        ),
        ...overrides,
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: goldenTheme(brightness, locale.languageCode),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(),
      ),
    ),
  );
  await tester.pump();
  unawaited(
    Navigator.of(
      tester.element(find.byType(Scaffold)),
    ).push(MaterialPageRoute<void>(builder: route)),
  );
  await settleGoldenAssets(tester);
}
