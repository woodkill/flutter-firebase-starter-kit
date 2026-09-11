import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/theme/app_typography.dart';

void main() {
  group('AppTypography', () {
    group('fromTextTheme', () {
      test('ThemeData.light()의 textTheme에서 displayLarge가 null이 아니다', () {
        final typography = AppTypography.fromTextTheme(
          ThemeData.light().textTheme,
        );

        expect(typography.displayLarge, isNotNull);
      });

      test('모든 스타일 필드가 null이 아니다', () {
        final typography = AppTypography.fromTextTheme(
          ThemeData.light().textTheme,
        );

        expect(typography.displayLarge, isNotNull);
        expect(typography.displayMedium, isNotNull);
        expect(typography.displaySmall, isNotNull);
        expect(typography.headlineLarge, isNotNull);
        expect(typography.headlineMedium, isNotNull);
        expect(typography.headlineSmall, isNotNull);
        expect(typography.titleLarge, isNotNull);
        expect(typography.titleMedium, isNotNull);
        expect(typography.titleSmall, isNotNull);
        expect(typography.bodyLarge, isNotNull);
        expect(typography.bodyMedium, isNotNull);
        expect(typography.bodySmall, isNotNull);
        expect(typography.labelLarge, isNotNull);
        expect(typography.labelMedium, isNotNull);
        expect(typography.labelSmall, isNotNull);
      });
    });

    group('copyWith', () {
      test('displayLarge를 변경하면 해당 필드만 바뀐다', () {
        final original = AppTypography.fromTextTheme(
          ThemeData.light().textTheme,
        );
        const newStyle = TextStyle(fontSize: 100);
        final copied = original.copyWith(displayLarge: newStyle);

        expect(copied.displayLarge, equals(newStyle));
        expect(copied.displayMedium, equals(original.displayMedium));
        expect(copied.bodyLarge, equals(original.bodyLarge));
      });
    });

    group('lerp', () {
      test('null safety - other가 null이면 this를 반환한다', () {
        final typography = AppTypography.fromTextTheme(
          ThemeData.light().textTheme,
        );
        final result = typography.lerp(null, 0.5);

        expect(result.displayLarge, equals(typography.displayLarge));
      });

      test('t=0.0이면 this의 스타일을 유지한다', () {
        final light = AppTypography.fromTextTheme(ThemeData.light().textTheme);
        final dark = AppTypography.fromTextTheme(ThemeData.dark().textTheme);
        final result = light.lerp(dark, 0.0);

        expect(result.displayLarge, equals(light.displayLarge));
      });
    });
  });

  // ─── T-03-WR-02: 값 동등성 ─────────────────────────────
  group('T-03-WR-02: AppTypography 값 동등성', () {
    test('동일 TextTheme 에서 만든 두 인스턴스는 == 이고 hashCode 도 같다', () {
      final a = AppTypography.fromTextTheme(ThemeData.light().textTheme);
      final b = AppTypography.fromTextTheme(ThemeData.light().textTheme);

      expect(a == b, isTrue);
      expect(a.hashCode, equals(b.hashCode));
    });

    test('copyWith 로 변경하면 원본과 != 이다', () {
      final original = AppTypography.fromTextTheme(ThemeData.light().textTheme);
      final modified = original.copyWith(
        displayLarge: const TextStyle(fontSize: 100),
      );

      expect(original == modified, isFalse);
    });

    test('light 와 dark 는 != 이다', () {
      expect(
        AppTypography.fromTextTheme(ThemeData.light().textTheme) ==
            AppTypography.fromTextTheme(ThemeData.dark().textTheme),
        isFalse,
      );
    });
  });

  // ─── T-03-IN-06: 진단 정보 ─────────────────────────
  group('T-03-IN-06: AppTypography 진단 정보', () {
    test('toString 에 클래스명과 스타일 이름이 드러난다', () {
      final text = AppTypography.fromTextTheme(
        ThemeData.light().textTheme,
      ).toString();

      expect(text, contains('AppTypography'));
      expect(text, contains('bodyMedium'));
      expect(text, isNot(contains("Instance of 'AppTypography'")));
    });

    test('debugFillProperties 가 15개 스타일을 모두 등록한다', () {
      final builder = DiagnosticPropertiesBuilder();
      AppTypography.fromTextTheme(
        ThemeData.light().textTheme,
      ).debugFillProperties(builder);

      expect(builder.properties.map((p) => p.name).toSet().length, 15);
    });
  });
}
