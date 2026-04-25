import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/theme/app_colors.dart';
import 'package:flutter_starter_kit/core/theme/app_spacing.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/core/theme/app_typography.dart';

void main() {
  group('AppTheme', () {
    group('seedColor', () {
      test('seedColor는 Colors.deepPurple이다', () {
        expect(AppTheme.seedColor, equals(Colors.deepPurple));
      });
    });

    group('light', () {
      test('ThemeData에 AppColors extension이 등록되어 있다', () {
        final theme = AppTheme.light();

        expect(theme.extension<AppColors>(), isNotNull);
      });

      test('ThemeData에 AppTypography extension이 등록되어 있다', () {
        final theme = AppTheme.light();

        expect(theme.extension<AppTypography>(), isNotNull);
      });

      test('ThemeData에 AppSpacing extension이 등록되어 있다', () {
        final theme = AppTheme.light();

        expect(theme.extension<AppSpacing>(), isNotNull);
      });

      test('colorScheme.brightness가 Brightness.light이다', () {
        final theme = AppTheme.light();

        expect(theme.colorScheme.brightness, equals(Brightness.light));
      });
    });

    group('dark', () {
      test('ThemeData에 AppColors extension이 등록되어 있다', () {
        final theme = AppTheme.dark();

        expect(theme.extension<AppColors>(), isNotNull);
      });

      test('ThemeData에 AppTypography extension이 등록되어 있다', () {
        final theme = AppTheme.dark();

        expect(theme.extension<AppTypography>(), isNotNull);
      });

      test('ThemeData에 AppSpacing extension이 등록되어 있다', () {
        final theme = AppTheme.dark();

        expect(theme.extension<AppSpacing>(), isNotNull);
      });

      test('colorScheme.brightness가 Brightness.dark이다', () {
        final theme = AppTheme.dark();

        expect(theme.colorScheme.brightness, equals(Brightness.dark));
      });
    });
  });
}
