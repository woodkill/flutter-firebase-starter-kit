// Phase 17.1 Plan 03 — 홈 본문 seam (D-11 · D-15 · UI-SPEC E1).
//
// T-171-HOME-10 ~ 12: release 본문(빈 화면) · 개발자 안내 카드 · 데모 경로 push ·
// 280 dp 넘침 · 줄 늘림 · 접근성 guideline.

import 'package:flutter/material.dart';
import 'package:flutter_starter_kit/core/router/app_routes.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/home/presentation/home_body.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// 데모 경로 stub 화면 문구 — push 도달 확인용.
const String _demoStub = 'DEMO STUB';

/// [body] 를 Scaffold 본문으로 GoRouter 안(데모 경로 stub)에서 띄운다.
Future<void> _pumpBody(
  WidgetTester tester, {
  required HomeBody body,
  Locale locale = const Locale('en'),
  Size size = const Size(280, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => Scaffold(body: body),
      ),
      GoRoute(
        path: AppRoutes.developerDemo,
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text(_demoStub))),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    MaterialApp.router(
      theme: AppTheme.light(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Phase 17.1 production home (T-171-HOME)', () {
    testWidgets(
      'T-171-HOME-10: showsDeveloperGuide false → 빈 본문 (release · E1 empty)',
      (tester) async {
        final en = lookupAppLocalizations(const Locale('en'));
        await _pumpBody(
          tester,
          body: const HomeBody(showsDeveloperGuide: false),
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(Card), findsNothing);
        expect(find.text(en.homeDevGuideTitle), findsNothing);
        expect(find.text(en.homeDevGuideBody), findsNothing);
        expect(find.text(en.homeDevGuideOpenDemo), findsNothing);
      },
    );

    for (final code in const ['ko', 'en', 'ja']) {
      testWidgets(
        'T-171-HOME-11: $code 기본 → 안내 카드 · 버튼 → 데모 경로 (D-11 · D-15)',
        (tester) async {
          final locale = Locale(code);
          final l10n = lookupAppLocalizations(locale);
          await _pumpBody(tester, body: const HomeBody(), locale: locale);

          expect(find.byType(Card), findsOneWidget);
          expect(find.text(l10n.homeDevGuideTitle), findsOneWidget);
          expect(find.text(l10n.homeDevGuideBody), findsOneWidget);
          final button = find.widgetWithText(
            FilledButton,
            l10n.homeDevGuideOpenDemo,
          );
          expect(button, findsOneWidget);

          await tester.tap(button);
          await tester.pumpAndSettle();
          expect(find.text(_demoStub), findsOneWidget);
        },
      );

      testWidgets(
        'T-171-HOME-12: $code 280x800 — 넘침 0 · 카드 문구 maxLines 없음 (E1)',
        (tester) async {
          await _pumpBody(tester, body: const HomeBody(), locale: Locale(code));

          expect(tester.takeException(), isNull);
          final texts = tester.widgetList<Text>(
            find.descendant(of: find.byType(Card), matching: find.byType(Text)),
          );
          expect(texts, isNotEmpty);
          for (final text in texts) {
            expect(text.maxLines, isNull, reason: '카드 문구는 줄을 늘린다(잘림 0)');
          }
        },
      );
    }

    testWidgets('T-171-HOME-12: ko 280 light — 터치 영역 · 라벨 · 대비 guideline', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpBody(
        tester,
        body: const HomeBody(),
        locale: const Locale('ko'),
      );

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  });
}
