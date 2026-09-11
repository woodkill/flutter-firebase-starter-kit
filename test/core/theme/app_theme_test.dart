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

  // ─── T-03-WR-02: ThemeData 동등성 ────────────────────────
  //
  // `lib/app.dart` 는 build 안에서 `AppTheme.light()`/`dark()` 를 매번 새로
  // 만든다. extension 이 값 동등성을 구현하지 않으면 App 리빌드마다
  // ThemeData 가 불일치로 판정되어 `AnimatedTheme` 이 200ms 보간을
  // 재시작하고 `Theme.of` 의존 서브트리 전체가 리빌드된다.
  group('T-03-WR-02: ThemeData 동등성', () {
    test('AppTheme.light() 두 호출 결과가 == 이다', () {
      expect(AppTheme.light() == AppTheme.light(), isTrue);
      expect(AppTheme.light().hashCode, equals(AppTheme.light().hashCode));
    });

    test('AppTheme.dark() 두 호출 결과가 == 이다', () {
      expect(AppTheme.dark() == AppTheme.dark(), isTrue);
      expect(AppTheme.dark().hashCode, equals(AppTheme.dark().hashCode));
    });

    test('light 와 dark 는 != 이다', () {
      expect(AppTheme.light() == AppTheme.dark(), isFalse);
    });
  });

  // ─── T-03-IN-01: 중복 인자 제거 후 파생값 보존 ──────────────
  //
  // `useMaterial3` 는 Flutter 3.41 기준 기본값 true (`theme_data.dart` 의
  // `useMaterial3 ??= true`), `dark()` 의 `brightness` 는 colorScheme 에서
  // 파생된다. 인자를 지우고도 결과가 동일한지 고정한다.
  group('T-03-IN-01: 중복 인자를 제거해도 파생값은 동일하다', () {
    test('light() 의 brightness 는 light 다', () {
      expect(AppTheme.light().brightness, equals(Brightness.light));
    });

    test('dark() 의 brightness 는 colorScheme 에서 파생된다', () {
      final theme = AppTheme.dark();

      expect(
        theme.brightness,
        equals(Brightness.dark),
        reason:
            'ThemeData(brightness:) 인자를 제거했으므로 colorScheme.brightness '
            '파생이 깨지면 여기서 RED 가 된다.',
      );
      expect(theme.colorScheme.brightness, equals(Brightness.dark));
    });
  });
}
