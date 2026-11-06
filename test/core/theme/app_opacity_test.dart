// 투명도 토큰 [AppOpacity] 계약.
//
// `app_spacing_test.dart` 와 같은 관례(기본값 · copyWith · lerp · 값 동등성 ·
// 진단 정보)를 따른다.

import 'package:flutter/foundation.dart';
import 'package:flutter_starter_kit/core/theme/app_opacity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppOpacity', () {
    group('기본값', () {
      test(
        '상태 레이어 값은 hover 0.08 · focus 0.1 · pressed 0.1 · dragged 0.16 이다',
        () {
          const opacity = AppOpacity();

          expect(opacity.hover, equals(0.08));
          expect(opacity.focus, equals(0.1));
          expect(opacity.pressed, equals(0.1));
          expect(opacity.dragged, equals(0.16));
        },
      );

      test('비활성 값은 disabled 0.38 · disabledContainer 0.12 이다', () {
        const opacity = AppOpacity();

        expect(opacity.disabled, equals(0.38));
        expect(opacity.disabledContainer, equals(0.12));
      });

      test('킷 값은 scrim 0.32 · inactive 0.3 이다', () {
        const opacity = AppOpacity();

        expect(opacity.scrim, equals(0.32));
        expect(opacity.inactive, equals(0.3));
      });
    });

    group('copyWith', () {
      test('필드마다 그 값만 바꾼다', () {
        const original = AppOpacity();

        expect(original.copyWith(hover: 0.5), equals(_opacityWith(hover: 0.5)));
        expect(original.copyWith(focus: 0.5), equals(_opacityWith(focus: 0.5)));
        expect(
          original.copyWith(pressed: 0.5),
          equals(_opacityWith(pressed: 0.5)),
        );
        expect(
          original.copyWith(dragged: 0.5),
          equals(_opacityWith(dragged: 0.5)),
        );
        expect(
          original.copyWith(disabled: 0.5),
          equals(_opacityWith(disabled: 0.5)),
        );
        expect(
          original.copyWith(disabledContainer: 0.5),
          equals(_opacityWith(disabledContainer: 0.5)),
        );
        expect(original.copyWith(scrim: 0.5), equals(_opacityWith(scrim: 0.5)));
        expect(
          original.copyWith(inactive: 0.5),
          equals(_opacityWith(inactive: 0.5)),
        );
      });

      test('인자 없으면 원본과 == 이다', () {
        const original = AppOpacity();
        expect(original.copyWith(), equals(original));
      });
    });

    group('lerp', () {
      test('t=0.0이면 this, t=1.0이면 other, t=0.5면 중간값이다', () {
        const a = AppOpacity(
          hover: 0,
          focus: 0,
          pressed: 0,
          dragged: 0,
          disabled: 0,
          disabledContainer: 0,
          scrim: 0,
          inactive: 0,
        );
        const b = AppOpacity(
          hover: 1,
          focus: 1,
          pressed: 1,
          dragged: 1,
          disabled: 1,
          disabledContainer: 1,
          scrim: 1,
          inactive: 1,
        );

        expect(a.lerp(b, 0), equals(a));
        expect(a.lerp(b, 1), equals(b));
        expect(
          a.lerp(b, 0.5),
          equals(
            const AppOpacity(
              hover: 0.5,
              focus: 0.5,
              pressed: 0.5,
              dragged: 0.5,
              disabled: 0.5,
              disabledContainer: 0.5,
              scrim: 0.5,
              inactive: 0.5,
            ),
          ),
        );
      });

      test('other 가 null 이면 this 를 돌려준다', () {
        const a = AppOpacity();
        expect(a.lerp(null, 0.5), same(a));
      });
    });

    group('값 동등성', () {
      test('동일 값 두 인스턴스는 == 이고 hashCode 도 같다', () {
        const a = AppOpacity();
        final b = const AppOpacity().copyWith(scrim: 0.32);

        expect(a == b, isTrue);
        expect(a.hashCode, equals(b.hashCode));
      });

      test('필드 하나를 바꾸면 원본과 != 이다', () {
        const original = AppOpacity();

        expect(original == original.copyWith(hover: 0.09), isFalse);
        expect(original == original.copyWith(focus: 0.11), isFalse);
        expect(original == original.copyWith(pressed: 0.11), isFalse);
        expect(original == original.copyWith(dragged: 0.17), isFalse);
        expect(original == original.copyWith(disabled: 0.4), isFalse);
        expect(original == original.copyWith(disabledContainer: 0.2), isFalse);
        expect(original == original.copyWith(scrim: 0.4), isFalse);
        expect(original == original.copyWith(inactive: 0.4), isFalse);
      });
    });

    group('진단 정보', () {
      test('toString 과 debugFillProperties 에 여덟 필드가 드러난다', () {
        const opacity = AppOpacity();
        final builder = DiagnosticPropertiesBuilder();
        opacity.debugFillProperties(builder);

        expect(opacity.toString(), contains('AppOpacity'));
        expect(
          builder.properties.map((p) => p.name).toSet(),
          equals(<String?>{
            'hover',
            'focus',
            'pressed',
            'dragged',
            'disabled',
            'disabledContainer',
            'scrim',
            'inactive',
          }),
        );
      });
    });
  });
}

/// 기본값에서 지정한 필드만 바꾼 [AppOpacity] 를 만든다.
AppOpacity _opacityWith({
  double hover = 0.08,
  double focus = 0.1,
  double pressed = 0.1,
  double dragged = 0.16,
  double disabled = 0.38,
  double disabledContainer = 0.12,
  double scrim = 0.32,
  double inactive = 0.3,
}) => AppOpacity(
  hover: hover,
  focus: focus,
  pressed: pressed,
  dragged: dragged,
  disabled: disabled,
  disabledContainer: disabledContainer,
  scrim: scrim,
  inactive: inactive,
);
