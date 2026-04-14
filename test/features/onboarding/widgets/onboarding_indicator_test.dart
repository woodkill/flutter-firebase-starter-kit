import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/onboarding/presentation/_widgets/onboarding_indicator.dart';

Widget _wrap({required int count, required int activeIndex}) {
  return MaterialApp(
    theme: AppTheme.light(),
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

      final BuildContext context = tester.element(find.byType(OnboardingIndicator));
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
    });

    testWidgets('Test 2: activeIndex 변경 시 색상 업데이트', (tester) async {
      await tester.pumpWidget(_wrap(count: 3, activeIndex: 1));
      await tester.pumpAndSettle();

      final BuildContext context = tester.element(find.byType(OnboardingIndicator));
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
  });
}
