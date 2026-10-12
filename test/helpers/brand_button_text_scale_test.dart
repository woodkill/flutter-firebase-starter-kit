// 글자 배율 헬퍼의 오류 분류가 양쪽으로 작동하는지 확인한다.
//
// 화면 테스트는 「버튼에서 비롯된 layout 오류 0」 을 단언한다. 분류가 버튼의
// 오류를 놓치면 그 0 은 뜻이 없으므로, 일부러 넘치게 만든 위젯으로 버튼 밖 ·
// 버튼 안 오류가 각각 제자리에 잡히는지 본다.

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
  });
}
