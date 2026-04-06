import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/theme/app_breakpoint.dart';

void main() {
  group('AppBreakpoint', () {
    group('enum 필드값', () {
      test('compact.minWidth는 0이고 maxWidth는 360이다', () {
        expect(AppBreakpoint.compact.minWidth, equals(0));
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
        expect(
          AppBreakpoint.fromWidth(280),
          equals(AppBreakpoint.compact),
        );
      });

      test('359dp는 compact이다', () {
        expect(
          AppBreakpoint.fromWidth(359),
          equals(AppBreakpoint.compact),
        );
      });

      test('360dp는 medium이다', () {
        expect(
          AppBreakpoint.fromWidth(360),
          equals(AppBreakpoint.medium),
        );
      });

      test('599dp는 medium이다', () {
        expect(
          AppBreakpoint.fromWidth(599),
          equals(AppBreakpoint.medium),
        );
      });

      test('600dp는 expanded이다', () {
        expect(
          AppBreakpoint.fromWidth(600),
          equals(AppBreakpoint.expanded),
        );
      });

      test('674dp는 expanded이다', () {
        expect(
          AppBreakpoint.fromWidth(674),
          equals(AppBreakpoint.expanded),
        );
      });
    });
  });

  group('ResponsiveX', () {
    testWidgets(
      'MediaQuery size 400x800에서 breakpoint는 medium이다',
      (tester) async {
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
      },
    );

    testWidgets(
      'portrait orientation에서 isPortrait은 true이다',
      (tester) async {
        late bool isPortrait;
        late bool isLandscape;

        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(400, 800),
            ),
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
      },
    );

    testWidgets(
      'landscape orientation에서 isLandscape는 true이다',
      (tester) async {
        late bool isPortrait;
        late bool isLandscape;

        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(800, 400),
            ),
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
      },
    );
  });
}
