import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/theme/app_colors.dart';

void main() {
  group('AppColors', () {
    group('fromBrightness', () {
      test('light와 dark의 success 값이 다르다', () {
        final light = AppColors.fromBrightness(Brightness.light);
        final dark = AppColors.fromBrightness(Brightness.dark);

        expect(light.success, isNot(equals(dark.success)));
      });

      test('light warning 값은 Color(0xFFF57F17)이다', () {
        final light = AppColors.fromBrightness(Brightness.light);

        expect(light.warning, equals(const Color(0xFFF57F17)));
      });

      test('dark success 값은 Color(0xFF81C784)이다', () {
        final dark = AppColors.fromBrightness(Brightness.dark);

        expect(dark.success, equals(const Color(0xFF81C784)));
      });
    });

    group('copyWith', () {
      test('success를 변경하면 해당 필드만 바뀐다', () {
        final original = AppColors.fromBrightness(Brightness.light);
        final copied = original.copyWith(success: Colors.red);

        expect(copied.success, equals(Colors.red));
        expect(copied.warning, equals(original.warning));
        expect(copied.info, equals(original.info));
        expect(copied.onSuccess, equals(original.onSuccess));
        expect(copied.onWarning, equals(original.onWarning));
        expect(copied.onInfo, equals(original.onInfo));
      });
    });

    group('lerp', () {
      test('t=0.0이면 this를 반환한다', () {
        final light = AppColors.fromBrightness(Brightness.light);
        final dark = AppColors.fromBrightness(Brightness.dark);
        final result = light.lerp(dark, 0.0);

        expect(result.success, equals(light.success));
        expect(result.warning, equals(light.warning));
        expect(result.info, equals(light.info));
      });

      test('t=1.0이면 other를 반환한다', () {
        final light = AppColors.fromBrightness(Brightness.light);
        final dark = AppColors.fromBrightness(Brightness.dark);
        final result = light.lerp(dark, 1.0);

        expect(result.success, equals(dark.success));
        expect(result.warning, equals(dark.warning));
        expect(result.info, equals(dark.info));
      });

      test('other가 AppColors가 아니면 this를 반환한다', () {
        final light = AppColors.fromBrightness(Brightness.light);
        final result = light.lerp(null, 0.5);

        expect(result.success, equals(light.success));
      });
    });
  });
}
