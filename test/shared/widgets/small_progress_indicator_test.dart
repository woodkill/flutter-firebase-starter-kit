// 공용 작은 진행 표시 [SmallProgressIndicator] 계약.
//
// 크기는 호출부가 넘긴 지름을 그대로 따르고, 선 굵기는 지름과 상관없이
// 2 로 고정된다.

import 'package:flutter/material.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/shared/widgets/small_progress_indicator.dart';
import 'package:flutter_test/flutter_test.dart';

/// [child] 를 앱 라이트 테마 화면 가운데에 pump 한다.
Future<void> pumpWithAppTheme(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

/// 화면에 그려진 안쪽 [CircularProgressIndicator] 를 찾는다.
CircularProgressIndicator findInnerIndicator(WidgetTester tester) =>
    tester.widget<CircularProgressIndicator>(
      find.descendant(
        of: find.byType(SmallProgressIndicator),
        matching: find.byType(CircularProgressIndicator),
      ),
    );

void main() {
  group('SmallProgressIndicator', () {
    testWidgets('T-24-SPIN-01: 지름 20 · 색을 넘기면 20x20 · 굵기 2 · 넘긴 색이다', (
      tester,
    ) async {
      const color = Color(0xFF123456);
      await pumpWithAppTheme(
        tester,
        const SmallProgressIndicator(dimension: 20, color: color),
      );

      expect(
        tester.getSize(find.byType(SmallProgressIndicator)),
        equals(const Size(20, 20)),
      );
      final indicator = findInnerIndicator(tester);
      expect(indicator.strokeWidth, equals(2.0));
      expect(indicator.color, equals(color));
    });

    testWidgets('T-24-SPIN-02: 색을 넘기지 않으면 안쪽 색이 null(테마 기본)이다', (tester) async {
      await pumpWithAppTheme(
        tester,
        const SmallProgressIndicator(dimension: 20),
      );

      expect(findInnerIndicator(tester).color, isNull);
    });

    testWidgets('T-24-SPIN-03: 지름 24 여도 굵기는 2 다(지름에서 파생하지 않는다)', (
      tester,
    ) async {
      await pumpWithAppTheme(
        tester,
        const SmallProgressIndicator(dimension: 24),
      );

      expect(
        tester.getSize(find.byType(SmallProgressIndicator)),
        equals(const Size(24, 24)),
      );
      expect(findInnerIndicator(tester).strokeWidth, equals(2.0));
    });
  });
}
