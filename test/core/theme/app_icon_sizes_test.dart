// Phase 17 리뷰 IN-10 — 아이콘 크기 토큰 [AppIconSizes] 계약.
//
// `app_spacing_test.dart` 와 같은 관례(기본값 · copyWith · lerp · 값 동등성 ·
// 진단 정보)를 따른다.

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_starter_kit/core/theme/app_icon_sizes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppIconSizes', () {
    group('기본값', () {
      test('sm은 20.0이다 (오류 배너 아이콘 — 값 변경 0)', () {
        const iconSizes = AppIconSizes();
        expect(iconSizes.sm, equals(20.0));
      });

      test('크기순 6단계다 (16 · 20 · 24 · 32 · 48 · 64)', () {
        const iconSizes = AppIconSizes();

        expect(iconSizes.xs, equals(16.0));
        expect(iconSizes.sm, equals(20.0));
        expect(iconSizes.md, equals(24.0));
        expect(iconSizes.lg, equals(32.0));
        expect(iconSizes.xl, equals(48.0));
        expect(iconSizes.xxl, equals(64.0));
      });

      test('md 는 IconThemeData 기본 크기와 같은 값이다', () {
        expect(
          const AppIconSizes().md,
          equals(const IconThemeData.fallback().size),
        );
      });
    });

    group('copyWith', () {
      test('sm을 변경하면 바뀐 값을 돌려준다 · 인자 없으면 원본 값', () {
        const original = AppIconSizes();

        expect(original.copyWith(sm: 18).sm, equals(18.0));
        expect(original.copyWith().sm, equals(original.sm));
      });

      test('필드마다 그 값만 바꾸고 인자 없으면 원본과 == 이다', () {
        const original = AppIconSizes();

        expect(original.copyWith(xs: 14), equals(_iconSizesWith(xs: 14)));
        expect(original.copyWith(sm: 18), equals(_iconSizesWith(sm: 18)));
        expect(original.copyWith(md: 22), equals(_iconSizesWith(md: 22)));
        expect(original.copyWith(lg: 36), equals(_iconSizesWith(lg: 36)));
        expect(original.copyWith(xl: 40), equals(_iconSizesWith(xl: 40)));
        expect(original.copyWith(xxl: 72), equals(_iconSizesWith(xxl: 72)));
        expect(original.copyWith(), equals(original));
      });
    });

    group('lerp', () {
      test('t=0.0이면 this, t=1.0이면 other 의 값이다', () {
        const a = AppIconSizes();
        final b = const AppIconSizes().copyWith(sm: 28);

        expect(a.lerp(b, 0).sm, equals(a.sm));
        expect(a.lerp(b, 1).sm, equals(b.sm));
        expect(a.lerp(b, 0.5).sm, equals(24.0));
      });

      test('여섯 필드 모두 중간값으로 보간한다', () {
        const a = AppIconSizes();
        const b = AppIconSizes(xs: 20, sm: 24, md: 28, lg: 40, xl: 56, xxl: 80);

        expect(a.lerp(b, 0), equals(a));
        expect(a.lerp(b, 1), equals(b));
        expect(
          a.lerp(b, 0.5),
          equals(
            const AppIconSizes(xs: 18, sm: 22, md: 26, lg: 36, xl: 52, xxl: 72),
          ),
        );
      });

      test('other 가 null 이면 this 를 돌려준다', () {
        const a = AppIconSizes();
        expect(a.lerp(null, 0.5), same(a));
      });
    });

    group('값 동등성', () {
      test('동일 값 두 인스턴스는 == 이고 hashCode 도 같다', () {
        const a = AppIconSizes();
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

      test('필드 하나를 바꾸면 원본과 != 이다', () {
        const original = AppIconSizes();

        expect(original == original.copyWith(xs: 17), isFalse);
        expect(original == original.copyWith(md: 25), isFalse);
        expect(original == original.copyWith(lg: 33), isFalse);
        expect(original == original.copyWith(xl: 49), isFalse);
        expect(original == original.copyWith(xxl: 65), isFalse);
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

      test('debugFillProperties 에 여섯 필드가 드러난다', () {
        const iconSizes = AppIconSizes();
        final builder = DiagnosticPropertiesBuilder();
        iconSizes.debugFillProperties(builder);

        expect(
          builder.properties.map((p) => p.name).toSet(),
          equals(<String?>{'xs', 'sm', 'md', 'lg', 'xl', 'xxl'}),
        );
      });
    });
  });
}

/// 기본값에서 지정한 필드만 바꾼 [AppIconSizes] 를 만든다.
AppIconSizes _iconSizesWith({
  double xs = 16,
  double sm = 20,
  double md = 24,
  double lg = 32,
  double xl = 48,
  double xxl = 64,
}) => AppIconSizes(xs: xs, sm: sm, md: md, lg: lg, xl: xl, xxl: xxl);
