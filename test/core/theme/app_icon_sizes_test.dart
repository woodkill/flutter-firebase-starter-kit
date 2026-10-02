// Phase 17 리뷰 IN-10 — 아이콘 크기 토큰 [AppIconSizes] 계약.
//
// `app_spacing_test.dart` 와 같은 관례(기본값 · copyWith · lerp · 값 동등성 ·
// 진단 정보)를 따른다.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/theme/app_icon_sizes.dart';

void main() {
  group('AppIconSizes', () {
    group('기본값', () {
      test('sm은 20.0이다 (오류 배너 아이콘 — 값 변경 0)', () {
        const iconSizes = AppIconSizes();
        expect(iconSizes.sm, equals(20.0));
      });
    });

    group('copyWith', () {
      test('sm을 변경하면 바뀐 값을 돌려준다 · 인자 없으면 원본 값', () {
        const original = AppIconSizes();

        expect(original.copyWith(sm: 18).sm, equals(18.0));
        expect(original.copyWith().sm, equals(original.sm));
      });
    });

    group('lerp', () {
      test('t=0.0이면 this, t=1.0이면 other 의 값이다', () {
        const a = AppIconSizes();
        final b = const AppIconSizes().copyWith(sm: 28);

        expect(a.lerp(b, 0.0).sm, equals(a.sm));
        expect(a.lerp(b, 1.0).sm, equals(b.sm));
        expect(a.lerp(b, 0.5).sm, equals(24.0));
      });

      test('other 가 null 이면 this 를 돌려준다', () {
        const a = AppIconSizes();
        expect(a.lerp(null, 0.5), same(a));
      });
    });

    group('값 동등성', () {
      test('동일 값 두 인스턴스는 == 이고 hashCode 도 같다', () {
        const a = AppIconSizes(sm: 20);
        final b = const AppIconSizes().copyWith(sm: 20);

        expect(a == b, isTrue);
        expect(a.hashCode, equals(b.hashCode));
      });

      test('copyWith 로 값을 바꾸면 원본과 != 이다', () {
        expect(
          const AppIconSizes() == const AppIconSizes().copyWith(sm: 21),
          isFalse,
        );
      });
    });

    group('진단 정보', () {
      test('toString 과 debugFillProperties 에 sm 이 드러난다', () {
        const iconSizes = AppIconSizes();
        final builder = DiagnosticPropertiesBuilder();
        iconSizes.debugFillProperties(builder);

        expect(iconSizes.toString(), contains('AppIconSizes'));
        expect(iconSizes.toString(), contains('sm'));
        expect(builder.properties.map((p) => p.name), contains('sm'));
      });
    });
  });
}
