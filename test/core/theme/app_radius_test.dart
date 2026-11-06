// 둥글기 토큰 [AppRadius] 계약.
//
// `app_spacing_test.dart` 와 같은 관례(기본값 · copyWith · lerp · 값 동등성 ·
// 진단 정보)를 따른다.

import 'package:flutter/foundation.dart';
import 'package:flutter_starter_kit/core/theme/app_radius.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppRadius', () {
    group('기본값', () {
      test('다섯 단계가 Material 3 모양 단계 값이다 (4 · 8 · 12 · 16 · 28)', () {
        const radius = AppRadius();

        expect(radius.xs, equals(4.0));
        expect(radius.sm, equals(8.0));
        expect(radius.md, equals(12.0));
        expect(radius.lg, equals(16.0));
        expect(radius.xl, equals(28.0));
      });
    });

    group('copyWith', () {
      test('필드마다 그 값만 바꾼다', () {
        const original = AppRadius();

        expect(original.copyWith(xs: 2), equals(_radiusWith(xs: 2)));
        expect(original.copyWith(sm: 6), equals(_radiusWith(sm: 6)));
        expect(original.copyWith(md: 10), equals(_radiusWith(md: 10)));
        expect(original.copyWith(lg: 20), equals(_radiusWith(lg: 20)));
        expect(original.copyWith(xl: 32), equals(_radiusWith(xl: 32)));
      });

      test('인자 없으면 원본과 == 이다', () {
        const original = AppRadius();
        expect(original.copyWith(), equals(original));
      });
    });

    group('lerp', () {
      test('t=0.0이면 this, t=1.0이면 other, t=0.5면 중간값이다', () {
        const a = AppRadius();
        const b = AppRadius(xs: 8, sm: 12, md: 16, lg: 24, xl: 36);

        expect(a.lerp(b, 0), equals(a));
        expect(a.lerp(b, 1), equals(b));
        expect(
          a.lerp(b, 0.5),
          equals(const AppRadius(xs: 6, sm: 10, md: 14, lg: 20, xl: 32)),
        );
      });

      test('other 가 null 이면 this 를 돌려준다', () {
        const a = AppRadius();
        expect(a.lerp(null, 0.5), same(a));
      });
    });

    group('값 동등성', () {
      test('동일 값 두 인스턴스는 == 이고 hashCode 도 같다', () {
        const a = AppRadius();
        final b = const AppRadius().copyWith(sm: 8);

        expect(a == b, isTrue);
        expect(a.hashCode, equals(b.hashCode));
      });

      test('필드 하나를 바꾸면 원본과 != 이다', () {
        const original = AppRadius();

        expect(original == original.copyWith(xs: 5), isFalse);
        expect(original == original.copyWith(sm: 9), isFalse);
        expect(original == original.copyWith(md: 13), isFalse);
        expect(original == original.copyWith(lg: 17), isFalse);
        expect(original == original.copyWith(xl: 29), isFalse);
      });
    });

    group('진단 정보', () {
      test('toString 과 debugFillProperties 에 다섯 필드가 드러난다', () {
        const radius = AppRadius();
        final builder = DiagnosticPropertiesBuilder();
        radius.debugFillProperties(builder);

        expect(radius.toString(), contains('AppRadius'));
        expect(
          builder.properties.map((p) => p.name).toSet(),
          equals(<String?>{'xs', 'sm', 'md', 'lg', 'xl'}),
        );
      });
    });
  });
}

/// 기본값에서 지정한 필드만 바꾼 [AppRadius] 를 만든다.
AppRadius _radiusWith({
  double xs = 4,
  double sm = 8,
  double md = 12,
  double lg = 16,
  double xl = 28,
}) => AppRadius(xs: xs, sm: sm, md: md, lg: lg, xl: xl);
