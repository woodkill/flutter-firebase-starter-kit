import 'dart:math' as math;

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

    // WCAG 2.1 텍스트 대비비 4.5:1 회귀 가드.
    //
    // semantic 토큰 6쌍(success/onSuccess, warning/onWarning, info/onInfo,
    // light/dark 양 모드)이 chip 컨테이너의 배경+전경 페어로 사용될 때
    // AA 텍스트 대비비를 만족함을 검증한다. 또한 light surface 위에 raw
    // warning을 전경색으로 사용하면 대비비가 4.5 미만임을 단언하여,
    // `_EnvironmentCard.valueColor` 안티패턴(03-UI-REVIEW.md Top 3 #1)이
    // 토큰을 오용하면 AA 미달임을 코드로 영구 기록한다.
    group('WCAG AA contrast', () {
      const minTextContrast = 4.5;

      group('light semantic pair', () {
        test('success / onSuccess가 AA 텍스트 대비비를 만족한다', () {
          final light = AppColors.fromBrightness(Brightness.light);
          final ratio = _contrastRatio(light.success, light.onSuccess);

          expect(ratio, greaterThanOrEqualTo(minTextContrast));
        });

        test('warning / onWarning이 AA 텍스트 대비비를 만족한다', () {
          final light = AppColors.fromBrightness(Brightness.light);
          final ratio = _contrastRatio(light.warning, light.onWarning);

          expect(ratio, greaterThanOrEqualTo(minTextContrast));
        });

        test('info / onInfo가 AA 텍스트 대비비를 만족한다', () {
          final light = AppColors.fromBrightness(Brightness.light);
          final ratio = _contrastRatio(light.info, light.onInfo);

          expect(ratio, greaterThanOrEqualTo(minTextContrast));
        });
      });

      group('dark semantic pair', () {
        test('success / onSuccess가 AA 텍스트 대비비를 만족한다', () {
          final dark = AppColors.fromBrightness(Brightness.dark);
          final ratio = _contrastRatio(dark.success, dark.onSuccess);

          expect(ratio, greaterThanOrEqualTo(minTextContrast));
        });

        test('warning / onWarning이 AA 텍스트 대비비를 만족한다', () {
          final dark = AppColors.fromBrightness(Brightness.dark);
          final ratio = _contrastRatio(dark.warning, dark.onWarning);

          expect(ratio, greaterThanOrEqualTo(minTextContrast));
        });

        test('info / onInfo가 AA 텍스트 대비비를 만족한다', () {
          final dark = AppColors.fromBrightness(Brightness.dark);
          final ratio = _contrastRatio(dark.info, dark.onInfo);

          expect(ratio, greaterThanOrEqualTo(minTextContrast));
        });
      });

      // 회귀 가드: `_EnvironmentCard.valueColor` 안티패턴(03-UI-REVIEW.md
      // Top 3 #1) 의 수치적 근거를 코드로 고정한다. light surface 근사값
      // (`ColorScheme.fromSeed(deepPurple).surface ≈ #FEF7FF`) 위에 raw
      // light warning 토큰을 텍스트 전경색으로 사용하면 대비비가 4.5 미만
      // 으로 떨어진다 — chip 컨테이너로 감싸 `onWarning` 페어링을 강제해야
      // 한다. 토큰 정의가 변경되더라도 이 사실은 안정적이며, 안티패턴이
      // 부활하면 위젯 테스트가 별도로 잡는다.
      test('light surface 위 raw warning 전경색은 AA 텍스트 대비비 미달이다', () {
        const lightSurface = Color(0xFFFEF7FF);
        final light = AppColors.fromBrightness(Brightness.light);
        final ratio = _contrastRatio(light.warning, lightSurface);

        expect(ratio, lessThan(minTextContrast));
      });
    });
  });
}

/// sRGB 채널 컴포넌트 [v]([0.0, 1.0])를 WCAG 2.1 정의에 따라 선형화한다.
///
/// [v] 는 감마 인코딩된 sRGB 값(`Color.r/g/b`)이며, 반환값은 상대 휘도
/// 계산에 사용되는 선형 광도값이다.
double _channelLinear(double v) {
  if (v <= 0.03928) {
    return v / 12.92;
  }
  return math.pow((v + 0.055) / 1.055, 2.4).toDouble();
}

/// WCAG 2.1 상대 휘도(relative luminance) 를 계산한다.
///
/// 공식: `0.2126 * R_linear + 0.7152 * G_linear + 0.0722 * B_linear`.
/// [color] 가 alpha 를 포함해도 무시한다 (불투명 전경색 가정).
double _relativeLuminance(Color color) {
  final r = _channelLinear(color.r);
  final g = _channelLinear(color.g);
  final b = _channelLinear(color.b);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/// 두 색의 WCAG 2.1 대비비(contrast ratio) 를 계산한다.
///
/// 공식: `(L_lighter + 0.05) / (L_darker + 0.05)`. 결과는 항상 1.0
/// 이상이며, 4.5 이상이면 AA 텍스트 기준을 만족한다.
double _contrastRatio(Color a, Color b) {
  final la = _relativeLuminance(a);
  final lb = _relativeLuminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}
