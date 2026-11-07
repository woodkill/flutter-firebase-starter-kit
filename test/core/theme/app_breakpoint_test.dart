import 'package:flutter/material.dart';
import 'package:flutter_starter_kit/core/theme/app_breakpoint.dart';
import 'package:flutter_test/flutter_test.dart';

/// [AppBreakpoint.fromWidth] 결과를 너비별로 대조한다.
void expectBreakpoints(List<(double, AppBreakpoint)> expected) {
  for (final (width, breakpoint) in expected) {
    expect(
      AppBreakpoint.fromWidth(width),
      equals(breakpoint),
      reason: '${width}dp 는 $breakpoint 여야 한다.',
    );
  }
}

void main() {
  group('AppBreakpoint', () {
    test('T-24-BP-01: values 가 다섯 단계 순서이고 minWidth 가 '
        '0 · 600 · 840 · 1200 · 1600 이다', () {
      expect(
        AppBreakpoint.values,
        equals(const <AppBreakpoint>[
          AppBreakpoint.compact,
          AppBreakpoint.medium,
          AppBreakpoint.expanded,
          AppBreakpoint.large,
          AppBreakpoint.extraLarge,
        ]),
      );
      expect(
        AppBreakpoint.values.map((bp) => bp.minWidth).toList(),
        equals(const <double>[0, 600, 840, 1200, 1600]),
      );
    });

    // 단계는 하한만 갖고 fromWidth 가 그 하한에서 파생된다 — 다음 단계 하한은
    // 배타이고, 범위 밖 입력(NaN · 음수 · 무한대)은 양끝 단계로 포화한다.
    group('T-03-WR-05: fromWidth 는 단계 하한에서 파생된다', () {
      test('T-24-BP-02: fromWidth 는 하한이 너비 이하인 마지막 단계를 돌려준다', () {
        expectBreakpoints(const <(double, AppBreakpoint)>[
          (0, AppBreakpoint.compact),
          (599.9, AppBreakpoint.compact),
          (600, AppBreakpoint.medium),
          (839.9, AppBreakpoint.medium),
          (840, AppBreakpoint.expanded),
          (1199.9, AppBreakpoint.expanded),
          (1200, AppBreakpoint.large),
          (1599.9, AppBreakpoint.large),
          (1600, AppBreakpoint.extraLarge),
          (4000, AppBreakpoint.extraLarge),
        ]);
      });

      test('T-24-BP-04: NaN · 음수는 compact · 무한대는 extraLarge 다', () {
        expect(
          AppBreakpoint.fromWidth(double.nan),
          equals(AppBreakpoint.compact),
        );
        expect(AppBreakpoint.fromWidth(-1), equals(AppBreakpoint.compact));
        expect(
          AppBreakpoint.fromWidth(double.infinity),
          equals(AppBreakpoint.extraLarge),
        );
      });
    });

    test('T-24-BP-03: 킷 지원 폭 280 ~ 674dp 는 compact 와 medium 이다', () {
      expectBreakpoints(const <(double, AppBreakpoint)>[
        (280, AppBreakpoint.compact),
        (360, AppBreakpoint.compact),
        (599, AppBreakpoint.compact),
        (600, AppBreakpoint.medium),
        (674, AppBreakpoint.medium),
      ]);
    });
  });

  group('ResponsiveX', () {
    testWidgets('T-24-BP-05: MediaQuery size 400x800 에서 breakpoint 는 '
        'compact 다', (tester) async {
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

      expect(breakpoint, equals(AppBreakpoint.compact));
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

  // ─── T-03-IN-05: isPortrait 파생 · 지역 제약 기준 ────────────
  group('T-03-IN-05: isPortrait 은 isLandscape 에서 파생된다', () {
    testWidgets('두 getter 는 항상 서로의 부정이다', (tester) async {
      for (final size in const <Size>[Size(400, 800), Size(800, 400)]) {
        late bool isPortrait;
        late bool isLandscape;

        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(size: size),
            child: Builder(
              builder: (context) {
                isPortrait = context.isPortrait;
                isLandscape = context.isLandscape;
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        expect(
          isPortrait,
          equals(!isLandscape),
          reason: '$size — 진실원이 둘로 갈라졌다 (IN-05 회귀).',
        );
      }
    });

    testWidgets('T-24-BP-06: 지역 제약 기준은 fromWidth(constraints.maxWidth) '
        '로 얻는다', (tester) async {
      late AppBreakpoint screenBreakpoint;
      late AppBreakpoint localBreakpoint;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(640, 800)),
          child: Center(
            child: SizedBox(
              width: 300,
              child: Builder(
                builder: (context) {
                  screenBreakpoint = context.breakpoint;
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      localBreakpoint = AppBreakpoint.fromWidth(
                        constraints.maxWidth,
                      );
                      return const SizedBox.shrink();
                    },
                  );
                },
              ),
            ),
          ),
        ),
      );

      // 화면 전체 폭 640dp → medium, 지역 가용 폭 300dp → compact.
      expect(screenBreakpoint, equals(AppBreakpoint.medium));
      expect(
        localBreakpoint,
        equals(AppBreakpoint.compact),
        reason: 'context.breakpoint 는 화면 전체 폭 기준이라 지역 제약과 다르다.',
      );
    });
  });
}
