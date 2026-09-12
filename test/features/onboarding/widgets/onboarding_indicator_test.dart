import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/onboarding/presentation/_widgets/onboarding_indicator.dart';
import 'package:flutter_starter_kit/l10n/generated/app_localizations.dart';

/// 인디케이터를 테스트 트리에 올린다.
///
/// WR-09 이후 Semantics 라벨이 ARB 키를 거치므로 delegate 등록이 필수다
/// ([locale] 미지정 시 en).
Widget _wrap({
  required int count,
  required int activeIndex,
  Locale locale = const Locale('en'),
}) {
  return MaterialApp(
    theme: AppTheme.light(),
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Center(
        child: OnboardingIndicator(count: count, activeIndex: activeIndex),
      ),
    ),
  );
}

void main() {
  group('OnboardingIndicator', () {
    testWidgets(
      'Test 1: count=3 active=0 렌더 → 첫 번째 도트 primary, 2/3번째 onSurfaceVariant',
      (tester) async {
        await tester.pumpWidget(_wrap(count: 3, activeIndex: 0));
        await tester.pumpAndSettle();

        // count=3 이므로 도트 컨테이너가 정확히 3개 렌더된다.
        final dots = find.byType(Container);
        expect(dots, findsNWidgets(3));

        final BuildContext context = tester.element(
          find.byType(OnboardingIndicator),
        );
        final scheme = Theme.of(context).colorScheme;

        final firstDecoration =
            tester.widget<Container>(dots.at(0)).decoration as BoxDecoration;
        final secondDecoration =
            tester.widget<Container>(dots.at(1)).decoration as BoxDecoration;
        final thirdDecoration =
            tester.widget<Container>(dots.at(2)).decoration as BoxDecoration;

        expect(firstDecoration.color, scheme.primary);
        expect(
          secondDecoration.color,
          scheme.onSurfaceVariant.withValues(alpha: 0.3),
        );
        expect(
          thirdDecoration.color,
          scheme.onSurfaceVariant.withValues(alpha: 0.3),
        );
      },
    );

    testWidgets('Test 2: activeIndex 변경 시 색상 업데이트', (tester) async {
      await tester.pumpWidget(_wrap(count: 3, activeIndex: 1));
      await tester.pumpAndSettle();

      final BuildContext context = tester.element(
        find.byType(OnboardingIndicator),
      );
      final scheme = Theme.of(context).colorScheme;

      final dots = find.byType(Container);
      final secondDecoration =
          tester.widget<Container>(dots.at(1)).decoration as BoxDecoration;
      expect(secondDecoration.color, scheme.primary);
    });

    testWidgets('Test 3: Semantics label "Page X of N" 포함', (tester) async {
      await tester.pumpWidget(_wrap(count: 3, activeIndex: 1));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Page 2 of 3'), findsOneWidget);
    });

    testWidgets('Test 4 (WR-09): ko 로케일에서 라벨이 한국어로 읽힌다', (tester) async {
      // liveRegion 라벨이 하드코딩 영어면 ko/ja 사용자는 페이지 전환마다
      // 영어를 듣는다 — ARB 경유 여부를 로케일 전환으로 고정한다.
      await tester.pumpWidget(
        _wrap(count: 3, activeIndex: 1, locale: const Locale('ko')),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('3 페이지 중 2 페이지'), findsOneWidget);
      expect(find.bySemanticsLabel('Page 2 of 3'), findsNothing);
    });
  });
}
