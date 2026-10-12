// 글자 배율 헬퍼의 오류 분류가 세 갈래로 작동하는지 확인한다.
//
// 화면 테스트는 「버튼에서 비롯된 넘침 0」 을 단언한다. 분류가 버튼의 넘침을
// 놓치면 그 0 은 뜻이 없으므로, 일부러 넘치게 만든 위젯으로 버튼 밖 · 버튼 안
// 넘침이 각각 제자리에 잡히는지 본다. 넘침이 아닌 오류는 헬퍼가 삼키지 않고
// 테스트 바인딩에 넘기는지도 본다 — 삼키면 화면 테스트가 예외를 놓친다.

import 'package:flutter/material.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/branded_social_button.dart';
import 'package:flutter_test/flutter_test.dart';

import 'brand_button_text_scale.dart';

void main() {
  group('글자 배율 헬퍼의 layout 오류 분류', () {
    testWidgets('T-177-SCALE-00: 버튼 밖 위젯의 넘침은 버튼 밖 오류로 센다', (tester) async {
      applyLargeTextNarrowView(tester);

      final errors = await collectBrandScaleErrors(() async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Center(
              child: SizedBox(
                width: 50,
                child: Row(children: [SizedBox(width: 100, height: 10)]),
              ),
            ),
          ),
        );
      });

      expect(errors.outside, isNotEmpty);
      expect(errors.outside.first, contains('overflowed'));
      expect(errors.outside.first, contains('@ Row < '));
      expect(errors.fromButtons, isEmpty);
    });

    testWidgets('T-177-SCALE-00: 좁힌 버튼의 넘침은 버튼의 오류로 센다', (tester) async {
      applyLargeTextNarrowView(tester);

      final errors = await collectBrandScaleErrors(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              // 로고와 간격이 들어갈 자리보다 좁되 0 은 아닌 폭이다 — 폭이 0 인
              // 줄은 그려지지 않아 넘침도 보고하지 않는다.
              child: SizedBox(
                width: 48,
                child: BrandedSocialButton.kakao(
                  label: 'Login with Kakao',
                  onPressed: () {},
                ),
              ),
            ),
          ),
        );
      });

      expect(errors.fromButtons, isNotEmpty);
      expect(errors.fromButtons.first, contains('overflowed'));
      expect(errors.outside, isEmpty);
    });

    testWidgets('T-177-SCALE-00: 넘침이 아닌 오류는 모으지 않고 테스트 바인딩에 넘긴다', (
      tester,
    ) async {
      applyLargeTextNarrowView(tester);

      final errors = await collectBrandScaleErrors(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(builder: (_) => throw StateError('버튼 밖 위젯의 빌드 예외')),
          ),
        );
      });

      // 헬퍼가 삼켰다면 바인딩에 남은 예외가 없어 null 이 나온다.
      expect(tester.takeException(), isA<StateError>());
      expect(errors.fromButtons, isEmpty);
      expect(errors.outside, isEmpty);
    });
  });
}
