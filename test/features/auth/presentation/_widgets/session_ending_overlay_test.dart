// quick 261011-e6c — 앱 최상위 오버레이 [SessionEndingOverlay] 위젯 테스트.
//
// production 과 같은 자리(`MaterialApp` 의 `builder`)에 두고 본다:
// - E6C-HOST-01: 종류 2 × locale 3 = 문구 6개가 결정한 값과 글자 그대로 같다
// - E6C-HOST-02: 진행 중이 아니면 그리는 것이 없고 child 는 화면 전체다
// - E6C-HOST-03: 진행 중 — scrim · 입력 차단이 화면 전체 · 다이얼로그 버튼까지
//   막힘 · 켜고 끄는 사이 child(Navigator)의 State 가 유지된다
// - E6C-HOST-04: 실 관리자 + 끝나지 않는 저장소 — 30초에 걷히고 입력이 돌아온다
// - E6C-HOST-05: 최상위에서 그린 라벨의 글자 모양이 Scaffold 안에서 그린 것과
//   같다 (킷 기본 테마 + 조상 스타일을 상속하는 타이포그래피 테마)
//
// 스피너가 도는 동안 `pumpAndSettle` 은 끝나지 않는다 — 오버레이가 떠 있는
// 구간은 `pump(Duration)` 만 쓴다. 탭 직후 `pump()` 1회로 오버레이가 mount 되고
// 그때부터 표시 지연을 잰다.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/application/session_ending.dart';
import 'package:flutter_starter_kit/features/auth/data/auth_repository.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/auth_in_progress_overlay.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/session_ending_overlay.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

const List<LocalizationsDelegate<dynamic>> _delegates =
    <LocalizationsDelegate<dynamic>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ];

/// 밑 화면 버튼 라벨.
const String _underlyingLabel = 'underlying-button';

/// 다이얼로그를 여는 버튼 라벨.
const String _openDialogLabel = 'open-dialog';

/// 다이얼로그 안 버튼 라벨.
const String _dialogButtonLabel = 'dialog-button';

/// 결정한 문구 6개 (종류 × locale) — 말줄임표는 U+2026 한 글자다.
const Map<SessionEndingKind, Map<String, String>> _expectedLabels =
    <SessionEndingKind, Map<String, String>>{
      SessionEndingKind.signOut: <String, String>{
        'ko': '로그아웃 처리 중…',
        'en': 'Signing you out…',
        'ja': 'ログアウト処理中…',
      },
      SessionEndingKind.withdrawal: <String, String>{
        'ko': '탈퇴 처리 중…',
        'en': 'Deleting your account…',
        'ja': 'アカウント削除処理中…',
      },
    };

/// 탭 횟수를 세는 밑 화면 — 버튼 2개(밑 화면 · 다이얼로그 열기).
class _TapCounts {
  /// 밑 화면 버튼이 눌린 횟수.
  int underlying = 0;

  /// 다이얼로그 안 버튼이 눌린 횟수.
  int dialog = 0;
}

/// production 과 같은 자리(`builder`)에 [SessionEndingOverlay] 를 둔 앱.
///
/// [home] 을 주지 않으면 탭을 세는 버튼 2개짜리 화면을 그린다.
Widget _host({
  required List<Override> overrides,
  Locale locale = const Locale('ko'),
  ThemeData? theme,
  _TapCounts? counts,
  Widget? home,
}) {
  final tapCounts = counts ?? _TapCounts();
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: _delegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      theme: theme ?? AppTheme.light(),
      builder: (context, child) =>
          SessionEndingOverlay(child: child ?? const SizedBox.shrink()),
      home:
          home ??
          Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: <Widget>[
                  ElevatedButton(
                    onPressed: () => tapCounts.underlying++,
                    child: const Text(_underlyingLabel),
                  ),
                  ElevatedButton(
                    onPressed: () => unawaited(
                      showDialog<void>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          actions: <Widget>[
                            TextButton(
                              onPressed: () => tapCounts.dialog++,
                              child: const Text(_dialogButtonLabel),
                            ),
                          ],
                        ),
                      ),
                    ),
                    child: const Text(_openDialogLabel),
                  ),
                ],
              ),
            ),
          ),
    ),
  );
}

/// 관리자 상태를 [kind] 로 고정하는 override (타이머 · 저장소 호출 없음).
Override _fixedKind(SessionEndingKind kind) =>
    sessionEndingProvider.overrideWithBuild(
      (ref, notifier) =>
          (kind: kind, isAccountDeleted: kind == SessionEndingKind.withdrawal),
    );

/// 끝나지 않는 저장소 로그아웃을 단 실 관리자 override 와 그 완료 핸들.
({Override override, Completer<void> repoDone}) _pendingRepository() {
  final repo = _MockAuthRepository();
  final repoDone = Completer<void>();
  when(
    () => repo.signOutAndResetOnboarding(),
  ).thenAnswer((_) => repoDone.future);
  return (
    override: authRepositoryProvider.overrideWithValue(repo),
    repoDone: repoDone,
  );
}

/// 트리 안 [ProviderScope] 의 container 를 돌려준다.
ProviderContainer _readContainer(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

/// 화면 전체 사각형 (논리 픽셀).
Rect _readScreenRect(WidgetTester tester) =>
    Offset.zero & tester.getSize(find.byType(MaterialApp));

/// 최상위 오버레이가 얹은 [AuthInProgressOverlay] finder.
Finder _findTopOverlay() => find.descendant(
  of: find.byType(SessionEndingOverlay),
  matching: find.byType(AuthInProgressOverlay),
);

/// [text] 를 그린 [RichText] 의 해석된 스타일을 돌려준다.
TextStyle? _readResolvedStyle(WidgetTester tester, Finder text) => tester
    .widget<RichText>(
      find.descendant(of: text, matching: find.byType(RichText)),
    )
    .text
    .style;

void main() {
  group('SessionEndingOverlay (quick 261011-e6c)', () {
    testWidgets('E6C-HOST-01: 종류 2 × locale 3 = 문구 6개가 결정한 값과 글자 그대로 '
        '같다 (표시 지연 300ms 뒤)', (tester) async {
      var checked = 0;
      for (final MapEntry<SessionEndingKind, Map<String, String>> byKind
          in _expectedLabels.entries) {
        for (final MapEntry<String, String> byLocale in byKind.value.entries) {
          await tester.pumpWidget(
            _host(
              overrides: <Override>[_fixedKind(byKind.key)],
              locale: Locale(byLocale.key),
            ),
          );
          await tester.pump();
          expect(
            find.text(byLocale.value),
            findsNothing,
            reason: '${byKind.key} · ${byLocale.key} — 표시 지연 전',
          );

          await tester.pump(AuthInProgressOverlay.indicatorDelay);
          expect(
            find.descendant(
              of: _findTopOverlay(),
              matching: find.text(byLocale.value),
            ),
            findsOneWidget,
            reason: '${byKind.key} · ${byLocale.key}',
          );
          expect(
            find.descendant(
              of: _findTopOverlay(),
              matching: find.byType(CircularProgressIndicator),
            ),
            findsOneWidget,
          );
          expect(
            byLocale.value.runes.last,
            0x2026,
            reason: '말줄임표는 U+2026 한 글자',
          );
          checked++;

          // 다음 조합은 새 ProviderScope 로 그린다.
          await tester.pumpWidget(const SizedBox());
        }
      }
      expect(checked, 6);
    });

    testWidgets('E6C-HOST-02: 진행 중이 아니면 오버레이 0개 · child 의 rect 가 화면 '
        '전체다', (tester) async {
      await tester.pumpWidget(
        _host(overrides: <Override>[_fixedKind(SessionEndingKind.none)]),
      );
      await tester.pump(AuthInProgressOverlay.indicatorDelay);

      expect(find.byType(SessionEndingOverlay), findsOneWidget);
      expect(find.byType(AuthInProgressOverlay), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        tester.getRect(find.byType(Navigator)),
        _readScreenRect(tester),
        reason: 'child(Navigator)는 오버레이가 없을 때와 같은 크기 제약을 받는다',
      );
      expect(find.text(_underlyingLabel), findsOneWidget);
    });

    testWidgets('E6C-HOST-03: 진행 중 — scrim 32% · AbsorbPointer 가 화면 전체 · 밑 '
        '화면 버튼과 showDialog 버튼 탭이 막힘 · child State 유지', (tester) async {
      final counts = _TapCounts();
      final repository = _pendingRepository();
      await tester.pumpWidget(
        _host(overrides: <Override>[repository.override], counts: counts),
      );
      final container = _readContainer(tester);
      final notifier = container.read(sessionEndingProvider.notifier);
      final State navigatorState = tester.state(find.byType(Navigator));

      // 양성 대조: 오버레이가 없을 때는 두 버튼 모두 눌린다.
      await tester.tap(find.text(_underlyingLabel));
      await tester.tap(find.text(_openDialogLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_dialogButtonLabel));
      await tester.pump();
      expect(counts.underlying, 1);
      expect(counts.dialog, 1);
      expect(find.byType(AlertDialog), findsOneWidget);

      // 켠다 — 다이얼로그가 떠 있는 채로.
      unawaited(notifier.signOut());
      await tester.pump();

      final overlay = _findTopOverlay();
      expect(overlay, findsOneWidget);
      final scrim = find.descendant(
        of: overlay,
        matching: find.byType(ColoredBox),
      );
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
      expect(tester.getRect(scrim), _readScreenRect(tester));
      expect(absorbPointer, findsOneWidget);
      expect(tester.widget<AbsorbPointer>(absorbPointer).absorbing, isTrue);
      expect(tester.getRect(absorbPointer), _readScreenRect(tester));
      expect(
        identical(tester.state(find.byType(Navigator)), navigatorState),
        isTrue,
        reason: '켜질 때 Navigator 가 다시 만들어지지 않는다',
      );

      // 다이얼로그 버튼 · 다이얼로그 바깥(barrier) 탭이 모두 막힌다.
      await tester.tap(find.text(_dialogButtonLabel), warnIfMissed: false);
      await tester.tapAt(const Offset(5, 5));
      await tester.pump(const Duration(milliseconds: 400));
      expect(counts.dialog, 1, reason: '다이얼로그 버튼 탭이 막힌다');
      expect(
        find.byType(AlertDialog),
        findsOneWidget,
        reason: 'barrier 탭도 막혀 다이얼로그가 닫히지 않는다',
      );

      // 다이얼로그를 코드로 닫고 밑 화면 버튼을 누른다.
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.text(_underlyingLabel), warnIfMissed: false);
      await tester.pump();
      expect(counts.underlying, 1, reason: '밑 화면 버튼 탭이 막힌다');

      // 끈다 — 저장소 완료 + 도착.
      repository.repoDone.complete();
      await tester.pump();
      notifier.handleOnboardingShown();
      await tester.pump();

      expect(container.read(sessionEndingProvider), idleSessionEndingState);
      expect(find.byType(AuthInProgressOverlay), findsNothing);
      expect(
        identical(tester.state(find.byType(Navigator)), navigatorState),
        isTrue,
        reason: '꺼질 때도 Navigator State 가 같은 인스턴스다',
      );
      await tester.tap(find.text(_underlyingLabel));
      await tester.pump();
      expect(counts.underlying, 2, reason: '걷힌 뒤에는 다시 눌린다');
    });

    testWidgets('E6C-HOST-04: 실 관리자 + 끝나지 않는 저장소 — 29초까지 오버레이 유지 → '
        '30초에 사라지고 입력이 다시 된다', (tester) async {
      final counts = _TapCounts();
      final repository = _pendingRepository();
      await tester.pumpWidget(
        _host(overrides: <Override>[repository.override], counts: counts),
      );
      final container = _readContainer(tester);

      unawaited(container.read(sessionEndingProvider.notifier).signOut());
      await tester.pump();
      expect(_findTopOverlay(), findsOneWidget);

      await tester.pump(const Duration(seconds: 29));
      expect(_findTopOverlay(), findsOneWidget);
      expect(find.text('로그아웃 처리 중…'), findsOneWidget);
      await tester.tap(find.text(_underlyingLabel), warnIfMissed: false);
      await tester.pump();
      expect(counts.underlying, 0);

      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.byType(AuthInProgressOverlay), findsNothing);
      expect(
        container.read(sessionEndingProvider).kind,
        SessionEndingKind.none,
      );
      expect(repository.repoDone.isCompleted, isFalse);

      await tester.tap(find.text(_underlyingLabel));
      await tester.pump();
      expect(counts.underlying, 1, reason: '상한 뒤에는 입력이 다시 된다');

      // 정리 — 저장소 호출을 끝낸다.
      repository.repoDone.complete();
      await tester.pump();
    });

    for (final ({String name, ThemeData theme}) fixture
        in <({String name, ThemeData theme})>[
          (name: '킷 기본 테마', theme: AppTheme.light()),
          (
            // 타이포그래피 기하가 조상 스타일을 상속(`inherit: true`)하는 테마 —
            // Material 조상 없이 그리면 글자 굵기가 달라진다.
            name: '상속형 타이포그래피 테마',
            theme: AppTheme.light().copyWith(
              typography: Typography.material2021(
                platform: TargetPlatform.android,
                englishLike: const TextTheme(
                  bodyMedium: TextStyle(fontSize: 14),
                ),
              ),
            ),
          ),
        ]) {
      testWidgets('E6C-HOST-05: 최상위 라벨의 해석된 TextStyle 이 Scaffold 안 '
          '오버레이의 것과 같다 (${fixture.name})', (tester) async {
        const locale = Locale('en');
        final label = lookupAppLocalizations(locale).authSigningOut;
        await tester.pumpWidget(
          _host(
            overrides: <Override>[_fixedKind(SessionEndingKind.signOut)],
            locale: locale,
            theme: fixture.theme,
            // 기존 사용처와 같은 자리 — Scaffold 안 Stack 의 마지막 child.
            home: Scaffold(
              body: SizedBox.expand(
                child: Stack(
                  children: <Widget>[AuthInProgressOverlay(label: label)],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(AuthInProgressOverlay.indicatorDelay);

        final inScaffold = find.descendant(
          of: find.byType(Scaffold),
          matching: find.text(label),
        );
        expect(inScaffold, findsOneWidget);
        expect(find.text(label), findsNWidgets(2));
        final Element inScaffoldElement = tester.element(inScaffold);
        final Finder topLevel = find.byElementPredicate(
          (Element element) => switch (element.widget) {
            Text(:final String? data) =>
              data == label && element != inScaffoldElement,
            _ => false,
          },
        );
        expect(topLevel, findsOneWidget);

        final TextStyle? topStyle = _readResolvedStyle(tester, topLevel);
        final TextStyle? scaffoldStyle = _readResolvedStyle(tester, inScaffold);
        final ThemeData theme = Theme.of(tester.element(topLevel));

        expect(topStyle, isNotNull);
        expect(topStyle, scaffoldStyle, reason: '기존 사용처와 같은 글자 모양');
        expect(topStyle!.decoration, isNot(TextDecoration.underline));
        expect(topStyle.color, theme.colorScheme.onSurface);
        expect(topStyle.fontSize, theme.textTheme.bodyMedium!.fontSize);
      });
    }
  });
}
