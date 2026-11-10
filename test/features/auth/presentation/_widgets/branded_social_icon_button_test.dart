// 원형 소셜 아이콘 버튼 계약 — 줄 나누기 · 스킨 · 로고 상자 · 누르는 영역 ·
// 비활성 · 툴팁을 고정한다.
//
// 크기 · 간격 · 로고 비율은 시험이 인자로 넣고, 기본값 시험만 인자를 뺀다.
// 스킨 기대값은 가이드 값의 리터럴로 적는다 — 스킨 객체에서 읽은 값을 스킨
// 객체와 견주지 않는다.

import 'package:flutter/material.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/core/theme/brand_focus_wrapper.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/branded_social_button.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

/// 이름 붙은 생성자 6개가 함께 갖는 모양.
typedef _IconBuilder =
    BrandedSocialIconButton Function({
      required String label,
      required VoidCallback? onPressed,
      required double size,
      required double logoHeightRatio,
      Key? key,
    });

/// provider 한 개의 스킨 기대값 — 가이드 값을 리터럴로 적는다.
typedef _IconCase = ({
  String name,
  _IconBuilder build,
  Color lightBackground,
  Color darkBackground,
  Color? lightOutline,
  Color? darkOutline,
  bool isBitmapLogo,
  double logoAspectRatio,
});

const _IconCase _google = (
  name: 'google',
  build: BrandedSocialIconButton.google,
  lightBackground: Color(0xFFFFFFFF),
  darkBackground: Color(0xFF131314),
  lightOutline: Color(0xFF747775),
  darkOutline: Color(0xFF8E918F),
  isBitmapLogo: true,
  logoAspectRatio: 1,
);
const _IconCase _apple = (
  name: 'apple',
  build: BrandedSocialIconButton.apple,
  lightBackground: Color(0xFF000000),
  darkBackground: Color(0xFFFFFFFF),
  lightOutline: null,
  darkOutline: null,
  isBitmapLogo: false,
  logoAspectRatio: 17 / 44,
);
const _IconCase _facebook = (
  name: 'facebook',
  build: BrandedSocialIconButton.facebook,
  lightBackground: Color(0xFFFFFFFF),
  darkBackground: Color(0xFF131314),
  lightOutline: Color(0xFF747775),
  darkOutline: Color(0xFF8E918F),
  isBitmapLogo: false,
  logoAspectRatio: 1,
);
const _IconCase _kakao = (
  name: 'kakao',
  build: BrandedSocialIconButton.kakao,
  lightBackground: Color(0xFFFEE500),
  darkBackground: Color(0xFFFEE500),
  lightOutline: null,
  darkOutline: null,
  isBitmapLogo: false,
  logoAspectRatio: 1,
);
const _IconCase _naver = (
  name: 'naver',
  build: BrandedSocialIconButton.naver,
  lightBackground: Color(0xFF03A94D),
  darkBackground: Color(0xFF03A94D),
  lightOutline: null,
  darkOutline: null,
  isBitmapLogo: false,
  logoAspectRatio: 1,
);
const _IconCase _line = (
  name: 'line',
  build: BrandedSocialIconButton.line,
  lightBackground: Color(0xFF06C755),
  darkBackground: Color(0xFF06C755),
  lightOutline: null,
  darkOutline: null,
  isBitmapLogo: false,
  logoAspectRatio: 47 / 44,
);

const List<_IconCase> _cases = <_IconCase>[
  _google,
  _apple,
  _facebook,
  _kakao,
  _naver,
  _line,
];

/// 앱 테마 시드를 바꿔 볼 때 쓰는 색 — 킷 시드와 거리가 먼 빨강.
const Color _otherSeedColor = Color(0xFFFF0000);

/// 비활성 버튼의 투명도.
const double _approvedDisabledOpacity = 0.38;

/// 화면 가운데에 아이콘 버튼 하나를 그린다.
Future<void> _pumpIcon(
  WidgetTester tester,
  Widget button, {
  Brightness brightness = Brightness.light,
  Color? seedColor,
}) async {
  final theme = brightness == Brightness.dark
      ? (seedColor == null
            ? AppTheme.dark()
            : AppTheme.dark(seedColor: seedColor))
      : (seedColor == null
            ? AppTheme.light()
            : AppTheme.light(seedColor: seedColor));
  await tester.pumpWidget(
    MaterialApp(
      // 테마가 바뀌는 pump 마다 새 트리로 그려 전환 애니메이션이 섞이지 않게 한다.
      key: UniqueKey(),
      theme: theme,
      home: Scaffold(body: Center(child: button)),
    ),
  );
  await tester.pumpAndSettle();
}

/// 그려진 아이콘 버튼의 원 바탕을 찾는다.
Finder _findSurface() => find.descendant(
  of: find.byType(BrandedSocialIconButton),
  matching: find.byType(Material),
);

/// 그려진 아이콘 버튼의 로고를 찾는다.
Finder _findLogo(_IconCase provider) => find.descendant(
  of: find.byType(BrandedSocialIconButton),
  matching: provider.isBitmapLogo
      ? find.byType(Image)
      : find.byType(SvgPicture),
);

/// 그려진 아이콘 버튼의 칸(포커스 테두리 래퍼)을 찾는다.
Finder _findSlot() => find.descendant(
  of: find.byType(BrandedSocialIconButton),
  matching: find.byType(BrandFocusWrapper),
);

void main() {
  group('원형 소셜 아이콘 버튼', () {
    test('T-25-IBTN-01: 줄 나누기 — 한 줄 폭이 가용 폭 이하면 한 줄 · 넘치면 '
        '반씩 두 줄(위가 많게) · 0 개면 빈 목록', () {
      // (개수, 가용 폭, 크기, 간격) → 줄별 칸 수.
      final table =
          <({int count, double maxWidth, double size, double gap}), List<int>>{
            (count: 6, maxWidth: 248, size: 48, gap: 8): <int>[3, 3],
            (count: 5, maxWidth: 248, size: 48, gap: 8): <int>[3, 2],
            (count: 3, maxWidth: 248, size: 48, gap: 8): <int>[3],
            // 여유 0 경계 — 한 줄 폭 = 가용 폭.
            (count: 6, maxWidth: 352, size: 44, gap: 8): <int>[6],
            (count: 5, maxWidth: 328, size: 48, gap: 12): <int>[5],
            (count: 6, maxWidth: 328, size: 44, gap: 8): <int>[3, 3],
            (count: 6, maxWidth: 379, size: 48, gap: 8): <int>[6],
            (count: 1, maxWidth: 248, size: 48, gap: 12): <int>[1],
            (count: 0, maxWidth: 248, size: 48, gap: 8): <int>[],
          };
      for (final MapEntry(key: input, value: want) in table.entries) {
        expect(
          resolveBrandIconRowCounts(
            input.count,
            maxWidth: input.maxWidth,
            iconSize: input.size,
            gap: input.gap,
          ),
          want,
          reason: '$input',
        );
      }
    });

    testWidgets('T-25-IBTN-02: 스킨 — 원 바탕 · 외곽선이 밝기별 가이드 값이고 앱 '
        '테마 시드를 바꿔도 그대로다', (tester) async {
      for (final provider in _cases) {
        for (final brightness in Brightness.values) {
          for (final seedColor in <Color?>[null, _otherSeedColor]) {
            await _pumpIcon(
              tester,
              provider.build(
                label: provider.name,
                onPressed: () {},
                size: 48,
                logoHeightRatio: 0.5,
              ),
              brightness: brightness,
              seedColor: seedColor,
            );
            final isDark = brightness == Brightness.dark;
            final where = '${provider.name} · ${brightness.name} · $seedColor';
            final surface = tester.widget<Material>(_findSurface());
            expect(
              surface.color,
              isDark ? provider.darkBackground : provider.lightBackground,
              reason: '$where 바탕',
            );
            final wantOutline = isDark
                ? provider.darkOutline
                : provider.lightOutline;
            expect(
              surface.shape,
              CircleBorder(
                side: wantOutline == null
                    ? BorderSide.none
                    : BorderSide(color: wantOutline),
              ),
              reason: '$where 원 · 외곽선',
            );
          }
        }
      }
    });

    testWidgets('T-25-IBTN-03: 로고 상자 — 높이 = 지름 × 비율 · 폭 = 높이 × '
        '로고 가로 ÷ 세로 · 원보다 커도 줄어들지 않는다', (tester) async {
      // (provider, 비율) — 「절반」 과 공식 비율 변형을 함께 본다.
      final ratios = <(_IconCase, double)>[
        (_google, 0.5),
        (_facebook, 0.5),
        (_kakao, 0.5),
        (_naver, 0.45),
        (_naver, 0.375),
        (_line, 0.5),
        (_line, 0.683),
        (_apple, 1.2),
        (_apple, 1.0),
      ];
      const size = 48.0;
      for (final (provider, ratio) in ratios) {
        await _pumpIcon(
          tester,
          provider.build(
            label: provider.name,
            onPressed: () {},
            size: size,
            logoHeightRatio: ratio,
          ),
        );
        final where = '${provider.name} · $ratio';
        expect(tester.takeException(), isNull, reason: '$where 예외 0');
        final logo = tester.getSize(_findLogo(provider));
        final wantHeight = size * ratio;
        expect(logo.height, closeTo(wantHeight, 0.01), reason: '$where 높이');
        expect(
          logo.width,
          closeTo(wantHeight * provider.logoAspectRatio, 0.01),
          reason: '$where 폭',
        );
      }
    });

    testWidgets('T-25-IBTN-07: 로고 상자 대표값 — 48 에서 Google 24 · Naver 21.6 · '
        'LINE 24 · Apple 57.6(폭 22.25)', (tester) async {
      final expectations = <(_IconCase, double, Size)>[
        (_google, 0.5, const Size(24, 24)),
        (_naver, 0.45, const Size(21.6, 21.6)),
        (_line, 0.5, const Size(24 * 47 / 44, 24)),
        (_apple, 1.2, const Size(22.25, 57.6)),
        (_apple, 1.0, const Size(48 * 17 / 44, 48)),
        (_naver, 0.375, const Size(18, 18)),
        (_line, 0.683, const Size(32.784 * 47 / 44, 32.784)),
      ];
      for (final (provider, ratio, want) in expectations) {
        await _pumpIcon(
          tester,
          provider.build(
            label: provider.name,
            onPressed: () {},
            size: 48,
            logoHeightRatio: ratio,
          ),
        );
        final logo = tester.getSize(_findLogo(provider));
        final where = '${provider.name} · $ratio';
        expect(logo.height, closeTo(want.height, 0.01), reason: '$where 높이');
        expect(logo.width, closeTo(want.width, 0.01), reason: '$where 폭');
      }
    });

    testWidgets('T-25-IBTN-08: 기본값 — 지름 · 로고 비율을 빼면 지름 48 · 칸 56 · '
        '로고 상자는 스킨 비율(Google · Facebook · Kakao 24 · Apple 57.6 · '
        'Naver 18 · LINE 28.32)', (tester) async {
      final expectations = <(_IconCase, BrandedSocialIconButton, Size)>[
        (
          _google,
          BrandedSocialIconButton.google(label: 'google', onPressed: () {}),
          const Size(24, 24),
        ),
        (
          _facebook,
          BrandedSocialIconButton.facebook(label: 'facebook', onPressed: () {}),
          const Size(24, 24),
        ),
        (
          _kakao,
          BrandedSocialIconButton.kakao(label: 'kakao', onPressed: () {}),
          const Size(24, 24),
        ),
        (
          _apple,
          BrandedSocialIconButton.apple(label: 'apple', onPressed: () {}),
          const Size(57.6 * 17 / 44, 57.6),
        ),
        (
          _naver,
          BrandedSocialIconButton.naver(label: 'naver', onPressed: () {}),
          const Size(18, 18),
        ),
        (
          _line,
          BrandedSocialIconButton.line(label: 'line', onPressed: () {}),
          const Size(28.32 * 47 / 44, 28.32),
        ),
      ];
      for (final (provider, button, want) in expectations) {
        await _pumpIcon(tester, button);
        final where = '${provider.name} 기본값';
        expect(button.size, 48, reason: '$where 지름');
        expect(tester.getRect(_findSlot()).width, 56, reason: '$where 칸 폭');
        final logo = tester.getSize(_findLogo(provider));
        expect(logo.height, closeTo(want.height, 0.01), reason: '$where 높이');
        expect(logo.width, closeTo(want.width, 0.01), reason: '$where 폭');
      }
    });

    for (final size in <double>[44, 48]) {
      testWidgets('T-25-IBTN-04: 크기 $size — 칸 전체가 눌린다(원 밖 · 칸 안 한 '
          '점 1회 · 고리 1회 · 가운데 1회)', (tester) async {
        var tapCount = 0;
        await _pumpIcon(
          tester,
          BrandedSocialIconButton.google(
            label: 'Link Google',
            onPressed: () => tapCount++,
            size: size,
            logoHeightRatio: 0.5,
          ),
        );
        final slot = tester.getRect(_findSlot());
        expect(slot.width, size + 2 * kBrandIconSlotInset, reason: '칸 폭');
        expect(slot.width, greaterThanOrEqualTo(48), reason: '칸 폭 48 이상');
        expect(slot.height, greaterThanOrEqualTo(48), reason: '칸 높이 48 이상');

        // 원 밖 · 칸 안 한 점 — 가운데에서 위로 반지름 + 1.
        await tester.tapAt(slot.center - Offset(0, size / 2 + 1));
        await tester.pumpAndSettle();
        expect(tapCount, 1, reason: '원 밖 · 칸 안 탭 1회');

        // 고리 — 칸 위 가장자리 + 1.
        await tester.tapAt(Offset(slot.center.dx, slot.top + 1));
        await tester.pumpAndSettle();
        expect(tapCount, 2, reason: '고리 탭 1회');

        // 가운데 — 바깥 영역과 원이 함께 받아도 한 번만 불린다.
        await tester.tapAt(slot.center);
        await tester.pumpAndSettle();
        expect(tapCount, 3, reason: '가운데 탭 1회');
      });
    }

    testWidgets('T-25-IBTN-05: 비활성 — 투명도 0.38 · semantics 비활성 · 어디를 '
        '눌러도 0 회', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpIcon(
        tester,
        BrandedSocialIconButton.kakao(label: 'Link Kakao', onPressed: null),
      );
      final opacity = tester.widget<Opacity>(
        find.descendant(
          of: find.byType(BrandedSocialIconButton),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacity.opacity, _approvedDisabledOpacity);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Link Kakao')),
        isSemantics(
          label: 'Link Kakao',
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
        ),
      );
      final slot = tester.getRect(_findSlot());
      for (final point in <Offset>[
        slot.center,
        slot.center - const Offset(0, 25),
        Offset(slot.center.dx, slot.top + 1),
      ]) {
        await tester.tapAt(point);
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });

    testWidgets('T-25-IBTN-06: 라벨은 한 번 — 툴팁은 있으나 semantics 에 '
        '들어가지 않는다', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpIcon(
        tester,
        BrandedSocialIconButton.line(
          label: 'Link LINE',
          onPressed: () {},
          size: 44,
          logoHeightRatio: 0.5,
        ),
      );
      final finder = find.bySemanticsLabel('Link LINE');
      expect(finder, findsOneWidget);
      expect(tester.getSemantics(finder).getSemanticsData().tooltip, isEmpty);
      expect(find.byTooltip('Link LINE'), findsOneWidget);
      semantics.dispose();
    });
  });
}
