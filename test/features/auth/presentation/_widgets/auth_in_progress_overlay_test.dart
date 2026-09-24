import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/auth_in_progress_overlay.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

const List<LocalizationsDelegate<dynamic>> _delegates =
    <LocalizationsDelegate<dynamic>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ];

/// 스피너 + 라벨 표시 지연 (사용자 결정 L1+d = 300ms) — 값 자체를 고정한다.
const Duration _indicatorDelay = Duration(milliseconds: 300);

/// 지연 경계 직전 시점 (300ms - 1ms).
const Duration _justBeforeDelay = Duration(milliseconds: 299);

/// Stack 이 화면 전체를 차지하도록 [SizedBox.expand] 로 감싼 호스트 빌더.
/// 실제 [LoginScreen] 에서는 첫 Stack child 가 [AuthScaffold] 라 화면 전체를
/// 차지하므로 동일한 layout invariant 를 모사한다.
Widget _host({required Locale locale, VoidCallback? underlyingTap}) {
  return MaterialApp(
    localizationsDelegates: _delegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: locale,
    theme: AppTheme.light(),
    home: Scaffold(
      body: SizedBox.expand(
        child: Stack(
          children: <Widget>[
            ElevatedButton(
              onPressed: underlyingTap ?? () {},
              child: const Text('underlying-button'),
            ),
            const AuthInProgressOverlay(),
          ],
        ),
      ),
    ),
  );
}

/// 오버레이 안의 스피너 · ko 라벨이 [matcher] 대로 보이는지 단언한다.
void _expectIndicator(Matcher matcher) {
  expect(find.byType(CircularProgressIndicator), matcher);
  expect(find.text('로그인 처리 중…'), matcher);
}

/// scrim(32%) 과 입력 차단이 화면 전체를 덮고 있는지 단언한다.
///
/// 구조(scrim 색 · 크기 · [AbsorbPointer.absorbing]) 와 동작(아래 버튼 탭
/// 차단) 을 함께 확인한다 — 스피너가 숨겨진 구간에도 유지되어야 한다.
Future<void> _expectScrimAndInputBlock(
  WidgetTester tester, {
  required ValueGetter<int> readUnderlyingTapCount,
}) async {
  final overlay = find.byType(AuthInProgressOverlay);
  final scrim = find.descendant(of: overlay, matching: find.byType(ColoredBox));
  final absorbPointer = find.descendant(
    of: overlay,
    matching: find.byType(AbsorbPointer),
  );
  final colorScheme = Theme.of(tester.element(overlay)).colorScheme;

  expect(scrim, findsOneWidget);
  expect(
    tester.widget<ColoredBox>(scrim).color,
    colorScheme.scrim.withValues(alpha: 0.32),
  );
  expect(tester.getRect(scrim), tester.getRect(find.byType(Scaffold)));
  expect(absorbPointer, findsOneWidget);
  expect(tester.widget<AbsorbPointer>(absorbPointer).absorbing, isTrue);

  final tapCountBefore = readUnderlyingTapCount();
  await tester.tap(find.text('underlying-button'), warnIfMissed: false);
  await tester.pump();
  expect(
    readUnderlyingTapCount(),
    tapCountBefore,
    reason: 'AbsorbPointer 가 underlying 입력을 흡수해야 한다',
  );
}

/// [states] 를 순서대로 앱 lifecycle 전환으로 전달한 뒤 한 프레임 그린다.
///
/// [AppLifecycleListener] 가 유효하지 않은 전환을 assert 하므로 호출부는
/// 엔진과 같은 순서(resumed → inactive → hidden → paused 및 역순)를 넘긴다.
Future<void> _driveLifecycle(
  WidgetTester tester,
  List<AppLifecycleState> states,
) async {
  for (final state in states) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await tester.pump();
}

void main() {
  group('AuthInProgressOverlay (Phase 11-04 hotfix UX gap)', () {
    testWidgets('Test 1: spinner + en 라벨 동시 표시', (tester) async {
      await tester.pumpWidget(_host(locale: const Locale('en')));
      await tester.pump(_indicatorDelay);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Signing you in…'), findsOneWidget);
    });

    testWidgets('Test 2: AbsorbPointer 가 underlying 버튼 탭을 차단한다', (
      tester,
    ) async {
      var underlyingTapped = false;
      await tester.pumpWidget(
        _host(
          locale: const Locale('en'),
          underlyingTap: () => underlyingTapped = true,
        ),
      );
      await tester.pump();

      await tester.tap(find.text('underlying-button'), warnIfMissed: false);
      await tester.pump();

      expect(
        underlyingTapped,
        isFalse,
        reason: 'AbsorbPointer 가 underlying 입력을 흡수해야 한다',
      );
    });

    testWidgets('Test 3: ko 라벨', (tester) async {
      await tester.pumpWidget(_host(locale: const Locale('ko')));
      await tester.pump(_indicatorDelay);

      expect(find.text('로그인 처리 중…'), findsOneWidget);
    });

    testWidgets('Test 4: ja 라벨', (tester) async {
      await tester.pumpWidget(_host(locale: const Locale('ja')));
      await tester.pump(_indicatorDelay);

      expect(find.text('サインイン処理中…'), findsOneWidget);
    });
  });

  // debug facebook-login-double-spinner (L1+d) — 네이티브 SDK 의 투명
  // Activity 가 자기 스피너를 켜는 동안 우리 스피너를 접어 이중 표시를 막는다.
  group('AuthInProgressOverlay 표시 지연 · lifecycle (L1+d)', () {
    testWidgets('Test 5: 300ms 전에는 스피너 · 라벨 없음, scrim · 입력 차단은 '
        '첫 프레임부터', (tester) async {
      var underlyingTapCount = 0;
      await tester.pumpWidget(
        _host(
          locale: const Locale('ko'),
          underlyingTap: () => underlyingTapCount++,
        ),
      );

      // 첫 프레임 — scrim · 입력 차단만.
      _expectIndicator(findsNothing);
      await _expectScrimAndInputBlock(
        tester,
        readUnderlyingTapCount: () => underlyingTapCount,
      );

      // 지연 경계 직전 — 아직 없음.
      await tester.pump(_justBeforeDelay);
      _expectIndicator(findsNothing);

      // 300ms 도달 — 표시.
      await tester.pump(const Duration(milliseconds: 1));
      _expectIndicator(findsOneWidget);
      await _expectScrimAndInputBlock(
        tester,
        readUnderlyingTapCount: () => underlyingTapCount,
      );
    });

    testWidgets('Test 6: inactive 동안 스피너 · 라벨 숨김(scrim · 입력 차단 '
        '유지), resumed 복귀 시 즉시 재표시', (tester) async {
      var underlyingTapCount = 0;
      await tester.pumpWidget(
        _host(
          locale: const Locale('ko'),
          underlyingTap: () => underlyingTapCount++,
        ),
      );
      await tester.pump(_indicatorDelay);
      _expectIndicator(findsOneWidget);

      await _driveLifecycle(tester, const <AppLifecycleState>[
        AppLifecycleState.resumed,
        AppLifecycleState.inactive,
      ]);
      _expectIndicator(findsNothing);
      await _expectScrimAndInputBlock(
        tester,
        readUnderlyingTapCount: () => underlyingTapCount,
      );

      await _driveLifecycle(tester, const <AppLifecycleState>[
        AppLifecycleState.resumed,
      ]);
      _expectIndicator(findsOneWidget);
    });

    testWidgets('Test 7: paused 동안 스피너 · 라벨 숨김(scrim · 입력 차단 유지), '
        'resumed 복귀 시 즉시 재표시', (tester) async {
      var underlyingTapCount = 0;
      await tester.pumpWidget(
        _host(
          locale: const Locale('ko'),
          underlyingTap: () => underlyingTapCount++,
        ),
      );
      await tester.pump(_indicatorDelay);
      _expectIndicator(findsOneWidget);

      await _driveLifecycle(tester, const <AppLifecycleState>[
        AppLifecycleState.resumed,
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]);
      _expectIndicator(findsNothing);
      await _expectScrimAndInputBlock(
        tester,
        readUnderlyingTapCount: () => underlyingTapCount,
      );

      await _driveLifecycle(tester, const <AppLifecycleState>[
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]);
      _expectIndicator(findsOneWidget);
    });

    testWidgets('Test 8: 지연 중 inactive 로 가면 300ms 가 지나도 숨김 유지, '
        'resumed 복귀 즉시 표시 (실기기 순서: 탭 → ≈93ms 포커스 상실 → 복귀)', (tester) async {
      await tester.pumpWidget(_host(locale: const Locale('ko')));

      await tester.pump(const Duration(milliseconds: 93));
      await _driveLifecycle(tester, const <AppLifecycleState>[
        AppLifecycleState.resumed,
        AppLifecycleState.inactive,
      ]);

      // 타이머는 inactive 중에 만료 — 그래도 숨김.
      await tester.pump(const Duration(seconds: 1));
      _expectIndicator(findsNothing);

      await _driveLifecycle(tester, const <AppLifecycleState>[
        AppLifecycleState.resumed,
      ]);
      _expectIndicator(findsOneWidget);
    });

    testWidgets('Test 9: 지연 전에 resumed 로 돌아와도 300ms 까지는 숨김', (tester) async {
      await tester.pumpWidget(_host(locale: const Locale('ko')));

      await _driveLifecycle(tester, const <AppLifecycleState>[
        AppLifecycleState.resumed,
        AppLifecycleState.inactive,
      ]);
      await tester.pump(const Duration(milliseconds: 100));
      await _driveLifecycle(tester, const <AppLifecycleState>[
        AppLifecycleState.resumed,
      ]);
      _expectIndicator(findsNothing);

      // 누적 경과 = 100ms → 299ms 까지 숨김, 300ms 에 표시.
      await tester.pump(const Duration(milliseconds: 199));
      _expectIndicator(findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      _expectIndicator(findsOneWidget);
    });
  });
}
