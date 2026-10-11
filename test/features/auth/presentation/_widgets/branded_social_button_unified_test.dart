// 소셜 버튼 공통 골격 계약 — 골격 값 한 벌이 버튼 6개에 똑같이 걸리는지 본다.
//
// 공통 골격은 미리보기 값이 있을 때만 그려진다. 이 파일은 실제로 쓸 값과
// 일부러 다른 표식 값을 넣어, 위젯이 그 값을 주입받아 그린다는 것까지 확인한다.
// 기대값은 가이드 값의 리터럴 · 골격 상수 · 표식 값으로만 쓴다 — 스킨 객체에서
// 읽은 값을 스킨 객체와 견주지 않는다.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/theme/brand_focus_wrapper.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/branded_social_button.dart';

/// 표식 값 — 어느 값도 지금 외관이나 고르는 중인 후보와 같지 않다.
const BrandButtonMetrics _metrics = BrandButtonMetrics(
  labelScaleCap: 1.25,
  disabledOpacity: 0.42,
  labelLineHeight: 23,
  labelLetterSpacing: 0.2,
  iosLabelTopInset: 3,
  appleLogoGap: 11,
);

/// 이름 붙은 생성자 6개가 함께 갖는 모양.
typedef _ButtonBuilder =
    BrandedSocialButton Function({
      required String label,
      required VoidCallback? onPressed,
      Key? key,
    });

/// provider 한 개의 시험 재료 — 이름 · 영문 로그인 문구 · 생성자.
typedef _ProviderCase = ({String name, String label, _ButtonBuilder build});

final List<_ProviderCase> _cases = <_ProviderCase>[
  (
    name: 'google',
    label: 'Sign in with Google',
    build: BrandedSocialButton.google,
  ),
  (
    name: 'apple',
    label: 'Sign in with Apple',
    build: BrandedSocialButton.apple,
  ),
  (
    name: 'facebook',
    label: 'Login with Facebook',
    build: BrandedSocialButton.facebook,
  ),
  (name: 'kakao', label: 'Login with Kakao', build: BrandedSocialButton.kakao),
  (name: 'naver', label: 'Log in with NAVER', build: BrandedSocialButton.naver),
  (name: 'line', label: 'Log in with LINE', build: BrandedSocialButton.line),
];

/// 기본 간격을 쓰는 provider — Google 은 가이드 값, Apple 은 표식 값을 쓴다.
const Set<String> _defaultGapProviders = <String>{
  'facebook',
  'kakao',
  'naver',
  'line',
};

/// 버튼 한 개를 `MaterialApp` 안에 그린다.
///
/// 호출마다 새 key 를 줘 앞선 pump 의 테마 전환 애니메이션이 섞이지 않게 한다.
Future<void> _pumpButton(
  WidgetTester tester,
  _ProviderCase provider, {
  Brightness brightness = Brightness.light,
  TargetPlatform platform = TargetPlatform.android,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      theme: ThemeData(brightness: brightness, platform: platform),
      home: Scaffold(
        body: Center(
          child: provider.build(label: provider.label, onPressed: () {}),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// 버튼 안에서만 찾는다.
Finder _findInButton(Finder matching) =>
    find.descendant(of: find.byType(BrandedSocialButton), matching: matching);

void main() {
  setUp(() => debugBrandButtonPreviewMetrics = _metrics);
  tearDown(() => debugBrandButtonPreviewMetrics = null);

  group('공통 골격 — 버튼 6개에 같은 값', () {
    testWidgets('T-177-SKEL-01: 버튼 6개가 밝은 · 어두운 테마에서 '
        '같은 높이 · 같은 모서리 반지름으로 그려진다', (tester) async {
      final BorderRadius radius = BorderRadius.circular(kBrandButtonRadius);
      for (final _ProviderCase provider in _cases) {
        for (final Brightness brightness in Brightness.values) {
          await _pumpButton(tester, provider, brightness: brightness);
          final String where = '${provider.name} · ${brightness.name}';

          final SizedBox box = tester.widget<SizedBox>(
            _findInButton(
              find.byWidgetPredicate(
                (Widget w) => w is SizedBox && w.width == double.infinity,
              ),
            ),
          );
          expect(box.height, kBrandButtonHeight, reason: '$where 높이 상자');

          final Finder material = _findInButton(find.byType(Material));
          expect(
            tester.getSize(material).height,
            kBrandButtonHeight,
            reason: '$where 그려진 높이',
          );
          expect(
            tester.widget<Material>(material).shape,
            isA<RoundedRectangleBorder>().having(
              (RoundedRectangleBorder s) => s.borderRadius,
              'borderRadius',
              radius,
            ),
            reason: '$where 바탕 모서리',
          );
          expect(
            tester
                .widget<InkWell>(_findInButton(find.byType(InkWell)))
                .borderRadius,
            radius,
            reason: '$where 누름 물결 모서리',
          );
          expect(
            tester
                .widget<BrandFocusWrapper>(
                  _findInButton(find.byType(BrandFocusWrapper)),
                )
                .borderRadius,
            kBrandButtonRadius,
            reason: '$where 포커스 테두리 모서리',
          );
        }
      }
    });

    testWidgets('T-177-SKEL-02: 라벨 6개가 같은 크기 · 굵기 · 줄 높이 · 자간이고 '
        '글꼴 이름을 명시한다', (tester) async {
      for (final _ProviderCase provider in _cases) {
        await _pumpButton(tester, provider);
        final String where = provider.name;

        final Text text = tester.widget<Text>(find.text(provider.label));
        final TextStyle? style = text.style;
        expect(style, isNotNull, reason: '$where 라벨 style');
        expect(style?.fontSize, 16, reason: '$where 글자 크기');
        expect(style?.fontWeight, FontWeight.w500, reason: '$where 굵기');
        expect(
          style?.height,
          _metrics.labelLineHeight / 16,
          reason: '$where 줄 높이 = 주입한 줄 높이 / 글자 크기',
        );
        expect(
          style?.letterSpacing,
          _metrics.labelLetterSpacing,
          reason: '$where 자간 = 주입한 값',
        );
        expect(
          style?.leadingDistribution,
          TextLeadingDistribution.even,
          reason: '$where 줄 안 위아래 여백 배분',
        );
        expect(
          style?.fontFamily,
          isNotNull,
          reason: '$where 글꼴 이름이 비면 앱 테마의 글꼴을 물려받는다',
        );
        expect(
          style?.fontFamilyFallback,
          isNull,
          reason:
              '$where 대체 글꼴 목록을 직접 두면 테마의 목록을 덮어써 '
              '한글 · 가나가 기기 글꼴로 넘어가지 못한다',
        );
        expect(text.maxLines, 1, reason: '$where 한 줄');
        expect(text.overflow, TextOverflow.ellipsis, reason: '$where 말줄임');
      }
    });

    testWidgets('T-177-SKEL-03: 버튼 6개가 로고 → 간격 → 라벨을 '
        '가운데 묶음으로 놓고 같은 좌우 여백을 쓴다', (tester) async {
      for (final _ProviderCase provider in _cases) {
        await _pumpButton(tester, provider);
        final String where = provider.name;

        final Finder rowFinder = _findInButton(find.byType(Row));
        final Row row = tester.widget<Row>(rowFinder);
        expect(
          row.mainAxisAlignment,
          MainAxisAlignment.center,
          reason: '$where 가운데 정렬',
        );
        expect(row.mainAxisSize, MainAxisSize.min, reason: '$where 묶음 폭');
        expect(row.children, hasLength(3), reason: '$where 자식 수');
        expect(
          row.children[0],
          anyOf(isA<SvgPicture>(), isA<Image>()),
          reason: '$where 첫 자식 = 로고',
        );
        expect(
          row.children[1],
          _defaultGapProviders.contains(provider.name)
              ? isA<SizedBox>().having(
                  (SizedBox b) => b.width,
                  'width',
                  kBrandButtonLogoGap,
                )
              : isA<SizedBox>(),
          reason: '$where 둘째 자식 = 간격',
        );
        expect(row.children[2], isA<Flexible>(), reason: '$where 셋째 자식 = 라벨');

        final Padding padding = tester.widget<Padding>(
          find.ancestor(of: rowFinder, matching: find.byType(Padding)).first,
        );
        expect(
          padding.padding,
          const EdgeInsets.symmetric(horizontal: kBrandButtonHorizontalPadding),
          reason: '$where 좌우 여백',
        );
      }
    });
  });
}
