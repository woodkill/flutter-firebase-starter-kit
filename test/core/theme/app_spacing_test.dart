import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/theme/app_spacing.dart';

void main() {
  group('AppSpacing', () {
    group('기본값', () {
      test('xs는 4.0이다', () {
        const spacing = AppSpacing();
        expect(spacing.xs, equals(4.0));
      });

      test('sm은 8.0이다', () {
        const spacing = AppSpacing();
        expect(spacing.sm, equals(8.0));
      });

      test('md는 12.0이다', () {
        const spacing = AppSpacing();
        expect(spacing.md, equals(12.0));
      });

      test('lg는 16.0이다', () {
        const spacing = AppSpacing();
        expect(spacing.lg, equals(16.0));
      });

      test('xl은 24.0이다', () {
        const spacing = AppSpacing();
        expect(spacing.xl, equals(24.0));
      });

      test('xxl은 32.0이다', () {
        const spacing = AppSpacing();
        expect(spacing.xxl, equals(32.0));
      });

      test('xxxl은 48.0이다', () {
        const spacing = AppSpacing();
        expect(spacing.xxxl, equals(48.0));
      });
    });

    group('copyWith', () {
      test('lg를 변경하면 해당 필드만 바뀌고 나머지는 불변이다', () {
        const original = AppSpacing();
        final copied = original.copyWith(lg: 20);

        expect(copied.lg, equals(20.0));
        expect(copied.xs, equals(original.xs));
        expect(copied.sm, equals(original.sm));
        expect(copied.md, equals(original.md));
        expect(copied.xl, equals(original.xl));
        expect(copied.xxl, equals(original.xxl));
        expect(copied.xxxl, equals(original.xxxl));
      });
    });

    group('lerp', () {
      test('t=0.0이면 this의 값을 유지한다', () {
        const a = AppSpacing();
        final b = const AppSpacing().copyWith(lg: 32);
        final result = a.lerp(b, 0.0);

        expect(result.lg, equals(a.lg));
      });

      test('t=1.0이면 other의 값을 반환한다', () {
        const a = AppSpacing();
        final b = const AppSpacing().copyWith(lg: 32);
        final result = a.lerp(b, 1.0);

        expect(result.lg, equals(b.lg));
      });
    });
  });
}
