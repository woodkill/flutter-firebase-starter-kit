import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/theme/app_breakpoint.dart';

void main() {
  group('AppBreakpoint', () {
    group('enum 필드값', () {
      test('compact.minWidth는 280이고 maxWidth는 360이다', () {
        // 280dp 는 PROJECT 제약의 모바일 지원 하한이다 (구값 0 은 문서화된
        // 하한과 어긋나 WR-05 지적 대상이었다).
        expect(AppBreakpoint.compact.minWidth, equals(280));
        expect(AppBreakpoint.compact.maxWidth, equals(360));
      });

      test('medium.minWidth는 360이고 maxWidth는 600이다', () {
        expect(AppBreakpoint.medium.minWidth, equals(360));
        expect(AppBreakpoint.medium.maxWidth, equals(600));
      });

      test('expanded.minWidth는 600이고 maxWidth는 674이다', () {
        expect(AppBreakpoint.expanded.minWidth, equals(600));
        expect(AppBreakpoint.expanded.maxWidth, equals(674));
      });
    });

    group('fromWidth', () {
      test('280dp는 compact이다', () {
        expect(AppBreakpoint.fromWidth(280), equals(AppBreakpoint.compact));
      });

      test('359dp는 compact이다', () {
        expect(AppBreakpoint.fromWidth(359), equals(AppBreakpoint.compact));
      });

      test('360dp는 medium이다', () {
        expect(AppBreakpoint.fromWidth(360), equals(AppBreakpoint.medium));
      });

      test('599dp는 medium이다', () {
        expect(AppBreakpoint.fromWidth(599), equals(AppBreakpoint.medium));
      });

      test('600dp는 expanded이다', () {
        expect(AppBreakpoint.fromWidth(600), equals(AppBreakpoint.expanded));
      });

      test('674dp는 expanded이다', () {
        expect(AppBreakpoint.fromWidth(674), equals(AppBreakpoint.expanded));
      });
    });
  });

  group('ResponsiveX', () {
    testWidgets('MediaQuery size 400x800에서 breakpoint는 medium이다', (
      tester,
    ) async {
      late AppBreakpoint breakpoint;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(400, 800)),
          child: Builder(
            builder: (context) {
              breakpoint = context.breakpoint;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(breakpoint, equals(AppBreakpoint.medium));
    });

    testWidgets('portrait orientation에서 isPortrait은 true이다', (tester) async {
      late bool isPortrait;
      late bool isLandscape;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(400, 800)),
          child: Builder(
            builder: (context) {
              isPortrait = context.isPortrait;
              isLandscape = context.isLandscape;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(isPortrait, isTrue);
      expect(isLandscape, isFalse);
    });

    testWidgets('landscape orientation에서 isLandscape는 true이다', (tester) async {
      late bool isPortrait;
      late bool isLandscape;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(800, 400)),
          child: Builder(
            builder: (context) {
              isPortrait = context.isPortrait;
              isLandscape = context.isLandscape;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(isLandscape, isTrue);
      expect(isPortrait, isFalse);
    });
  });

  // ─── T-03-WR-05: 범위 필드와 fromWidth 의 단일 진실원 ────────
  //
  // 구 구현은 범위 필드(minWidth/maxWidth)와 분기 함수(fromWidth)가 서로
  // 강제되지 않아, `expanded.maxWidth = 674` 인데도 `fromWidth(800)` 이
  // expanded 를 돌려줬다. 소비자가 `bp.maxWidth` 로 레이아웃을 계산하면
  // 조용히 틀린 값을 쓴다.
  group('T-03-WR-05: contains 와 fromWidth 가 범위에서 파생된다', () {
    test('contains 는 하한 포함 · 상한 배타다', () {
      expect(AppBreakpoint.compact.contains(280), isTrue);
      expect(AppBreakpoint.compact.contains(359.9), isTrue);
      expect(AppBreakpoint.compact.contains(360), isFalse);
      expect(AppBreakpoint.compact.contains(279), isFalse);

      expect(AppBreakpoint.medium.contains(360), isTrue);
      expect(AppBreakpoint.medium.contains(600), isFalse);

      expect(AppBreakpoint.expanded.contains(600), isTrue);
      expect(AppBreakpoint.expanded.contains(673.9), isTrue);
      expect(AppBreakpoint.expanded.contains(674), isFalse);
    });

    test('경계값은 정확히 한 breakpoint 에만 속한다', () {
      for (final width in <double>[280, 359, 360, 599, 600, 673]) {
        expect(
          AppBreakpoint.values.where((bp) => bp.contains(width)).length,
          1,
          reason: '${width}dp 가 중복/미분류 된다 — 범위가 연속적이어야 한다.',
        );
      }
    });

    test('fromWidth 결과는 항상 contains 와 일치한다 (지원 범위 내)', () {
      for (final width in <double>[280, 359, 360, 599, 600, 673]) {
        final bp = AppBreakpoint.fromWidth(width);

        expect(
          bp.contains(width),
          isTrue,
          reason: '${width}dp — fromWidth 가 범위 필드와 어긋난다 (WR-05 회귀).',
        );
      }
    });

    test('지원 범위 밖은 양끝으로 포화된다', () {
      // 하한 미만 — compact 로 포화.
      expect(AppBreakpoint.fromWidth(279), equals(AppBreakpoint.compact));
      expect(AppBreakpoint.fromWidth(0), equals(AppBreakpoint.compact));

      // 상한 이상 — expanded 로 포화 (360dp 폰을 가로로 돌리면 800dp).
      expect(AppBreakpoint.fromWidth(674), equals(AppBreakpoint.expanded));
      expect(AppBreakpoint.fromWidth(800), equals(AppBreakpoint.expanded));
    });
  });
}
