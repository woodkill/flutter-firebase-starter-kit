import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/theme/app_colors.dart';
import 'package:flutter_starter_kit/core/theme/app_spacing.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/core/theme/app_typography.dart';
import 'package:flutter_starter_kit/core/theme/theme_extensions.dart';

void main() {
  group('ThemeX', () {
    testWidgets('context.appColors가 non-null이다', (tester) async {
      late AppColors colors;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) {
              colors = context.appColors;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(colors, isNotNull);
      expect(colors, isA<AppColors>());
    });

    testWidgets('context.appTypography가 non-null이다', (tester) async {
      late AppTypography typography;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) {
              typography = context.appTypography;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(typography, isNotNull);
      expect(typography, isA<AppTypography>());
    });

    testWidgets('context.appSpacing이 non-null이다', (tester) async {
      late AppSpacing spacing;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) {
              spacing = context.appSpacing;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(spacing, isNotNull);
      expect(spacing, isA<AppSpacing>());
    });

    testWidgets('context.colorScheme에 접근할 수 있다', (tester) async {
      late ColorScheme colorScheme;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) {
              colorScheme = context.colorScheme;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(colorScheme, isNotNull);
      expect(colorScheme.brightness, equals(Brightness.light));
    });

    testWidgets('context.textTheme에 접근할 수 있다', (tester) async {
      late TextTheme textTheme;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) {
              textTheme = context.textTheme;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(textTheme, isNotNull);
    });
  });
}
