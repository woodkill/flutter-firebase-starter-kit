// elevation 토큰 [AppElevation] 계약.
//
// `app_radius_test.dart` 와 같은 관례(기본값 · copyWith · lerp · 값 동등성 ·
// 진단 정보)를 따른다.

import 'package:flutter/foundation.dart';
import 'package:flutter_starter_kit/core/theme/app_elevation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppElevation', () {
    group('기본값', () {
      test('T-24-ELV-01: level0 ~ level5 가 0 · 1 · 3 · 6 · 8 · 12 다', () {
        const elevation = AppElevation();

        expect(elevation.level0, equals(0.0));
        expect(elevation.level1, equals(1.0));
        expect(elevation.level2, equals(3.0));
        expect(elevation.level3, equals(6.0));
        expect(elevation.level4, equals(8.0));
        expect(elevation.level5, equals(12.0));
      });
    });

    group('copyWith', () {
      test('T-24-ELV-02: 필드마다 그 값만 바꾼다', () {
        const original = AppElevation();

        expect(
          original.copyWith(level0: 0.5),
          equals(_elevationWith(level0: 0.5)),
        );
        expect(original.copyWith(level1: 2), equals(_elevationWith(level1: 2)));
        expect(original.copyWith(level2: 4), equals(_elevationWith(level2: 4)));
        expect(original.copyWith(level3: 7), equals(_elevationWith(level3: 7)));
        expect(original.copyWith(level4: 9), equals(_elevationWith(level4: 9)));
        expect(
          original.copyWith(level5: 16),
          equals(_elevationWith(level5: 16)),
        );
      });

      test('T-24-ELV-02: 인자 없으면 원본과 == 이다', () {
        const original = AppElevation();
        expect(original.copyWith(), equals(original));
      });
    });

    group('lerp', () {
      test('T-24-ELV-03: t=0.0이면 this, t=1.0이면 other, t=0.5면 중간값이다', () {
        const a = AppElevation();
        const b = AppElevation(
          level0: 2,
          level1: 3,
          level2: 5,
          level3: 8,
          level4: 10,
          level5: 14,
        );

        expect(a.lerp(b, 0), equals(a));
        expect(a.lerp(b, 1), equals(b));
        expect(
          a.lerp(b, 0.5),
          equals(
            const AppElevation(
              level0: 1,
              level1: 2,
              level2: 4,
              level3: 7,
              level4: 9,
              level5: 13,
            ),
          ),
        );
      });

      test('T-24-ELV-03: other 가 null 이면 this 를 돌려준다', () {
        const a = AppElevation();
        expect(a.lerp(null, 0.5), same(a));
      });
    });

    group('값 동등성', () {
      test('T-24-ELV-04: 동일 값 두 인스턴스는 == 이고 hashCode 도 같다', () {
        const a = AppElevation();
        final b = const AppElevation().copyWith(level2: 3);

        expect(a == b, isTrue);
        expect(a.hashCode, equals(b.hashCode));
      });

      test('T-24-ELV-04: 필드 하나를 바꾸면 원본과 != 이다', () {
        const original = AppElevation();

        expect(original == original.copyWith(level0: 0.5), isFalse);
        expect(original == original.copyWith(level1: 1.5), isFalse);
        expect(original == original.copyWith(level2: 3.5), isFalse);
        expect(original == original.copyWith(level3: 6.5), isFalse);
        expect(original == original.copyWith(level4: 8.5), isFalse);
        expect(original == original.copyWith(level5: 12.5), isFalse);
      });
    });

    group('진단 정보', () {
      test('T-24-ELV-05: debugFillProperties 가 여섯 DoubleProperty 를 낸다', () {
        const elevation = AppElevation();
        final builder = DiagnosticPropertiesBuilder();
        elevation.debugFillProperties(builder);

        expect(elevation.toString(), contains('AppElevation'));
        expect(
          builder.properties.whereType<DoubleProperty>().map((p) => p.name),
          orderedEquals(<String?>[
            'level0',
            'level1',
            'level2',
            'level3',
            'level4',
            'level5',
          ]),
        );
      });
    });
  });
}

/// 기본값에서 지정한 필드만 바꾼 [AppElevation] 을 만든다.
AppElevation _elevationWith({
  double level0 = 0,
  double level1 = 1,
  double level2 = 3,
  double level3 = 6,
  double level4 = 8,
  double level5 = 12,
}) => AppElevation(
  level0: level0,
  level1: level1,
  level2: level2,
  level3: level3,
  level4: level4,
  level5: level5,
);
