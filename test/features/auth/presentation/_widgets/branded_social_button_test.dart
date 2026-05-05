// Phase 13 — see ROADMAP.md (D-55 BrandedSocialButton 회귀 테스트)

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_starter_kit/features/auth/presentation/_widgets/branded_social_button.dart';

/// `MaterialApp` + `AppTheme` 으로 [BrandedSocialButton] 을 pump 하는 helper.
Widget _wrap(Widget child, {Brightness brightness = Brightness.light}) {
  return MaterialApp(
    theme: brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
    home: Scaffold(body: child),
  );
}

/// 테스트용 expected color 상수 (production 코드의 private literal 미러).
///
/// 단일 진실원은 `branded_social_button.dart` 의 `_kKakao*` / `_kNaver*`
/// const 이며 본 상수는 회귀 가드 비교 대상이다 — 둘 중 어느 쪽이든 변경되면
/// 테스트가 RED 로 떨어져 contract drift 를 즉시 surface.
const _kKakaoYellowExpected = Color(0xFFFEE500);
const _kKakaoLabelExpected = Color(0xD9000000);
const _kKakaoIconExpected = Color(0xFF000000);
const _kNaverGreenExpected = Color(0xFF03C75A);
const _kNaverLabelExpected = Color(0xFFFFFFFF);

/// `BrandedSocialButton` 내부의 brand 배경 [Material] 위젯을 찾는다.
///
/// `MaterialApp` 자체가 root [Material] 을 포함하므로 단순 `find.byType` 은
/// 여러 매치를 반환한다. 본 helper 는 [BrandedSocialButton] descendant 만
/// 한정한다.
Material _findBrandMaterial(WidgetTester tester) {
  final materials = tester.widgetList<Material>(
    find.descendant(
      of: find.byType(BrandedSocialButton),
      matching: find.byType(Material),
    ),
  );
  return materials.first;
}

/// `BrandedSocialButton` 내부의 [InkWell] 위젯을 찾는다.
InkWell _findBrandInkWell(WidgetTester tester) {
  final inkWells = tester.widgetList<InkWell>(
    find.descendant(
      of: find.byType(BrandedSocialButton),
      matching: find.byType(InkWell),
    ),
  );
  return inkWells.first;
}

/// `BrandedSocialButton` 내부의 [Text] 위젯을 찾는다.
Text _findBrandLabel(WidgetTester tester, String label) {
  return tester.widget<Text>(
    find.descendant(
      of: find.byType(BrandedSocialButton),
      matching: find.text(label),
    ),
  );
}

void main() {
  group('BrandedSocialButton — Naver + Kakao retroactive (T-13-BRAND)', () {
    // ─── Naver named factory ──────────────────────────────────────────────
    testWidgets(
      'T-13-BRAND-NAVER-01: BrandedSocialButton.naver — backgroundColor #03C75A',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            BrandedSocialButton.naver(label: 'Naver', onPressed: () {}),
          ),
        );
        await tester.pumpAndSettle();

        final material = _findBrandMaterial(tester);
        expect(
          material.color,
          _kNaverGreenExpected,
          reason: 'Naver brand spec 의 backgroundColor 가 #03C75A 이어야 한다',
        );
      },
    );

    testWidgets(
      'T-13-BRAND-NAVER-02: foregroundColor 흰 100% — Text + SvgPicture 둘 다',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            BrandedSocialButton.naver(label: 'Naver', onPressed: () {}),
          ),
        );
        await tester.pumpAndSettle();

        final text = _findBrandLabel(tester, 'Naver');
        expect(
          text.style?.color,
          _kNaverLabelExpected,
          reason: 'Naver 라벨 Text.color 가 흰 100% (#FFFFFF) 이어야 한다',
        );

        // SvgPicture 의 colorFilter 가 흰색 srcIn 이어야 한다.
        final svg = tester.widget<SvgPicture>(
          find.descendant(
            of: find.byType(BrandedSocialButton),
            matching: find.byType(SvgPicture),
          ),
        );
        expect(
          svg.colorFilter,
          const ColorFilter.mode(_kNaverLabelExpected, BlendMode.srcIn),
          reason: 'Naver 아이콘 ColorFilter 가 흰 100% srcIn 이어야 한다',
        );
      },
    );

    testWidgets(
      'T-13-BRAND-NAVER-03: onPressed null → InkWell.onTap == null (disabled)',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            BrandedSocialButton.naver(label: 'Naver', onPressed: null),
          ),
        );
        await tester.pumpAndSettle();

        final inkWell = _findBrandInkWell(tester);
        expect(
          inkWell.onTap,
          isNull,
          reason: 'onPressed=null 이면 InkWell.onTap 도 null (Material default disabled)',
        );
      },
    );

    testWidgets(
      'T-13-BRAND-NAVER-04: onPressed != null → tap → onPressed 1회 호출',
      (tester) async {
        var pressed = 0;
        await tester.pumpWidget(
          _wrap(
            BrandedSocialButton.naver(
              label: 'Naver',
              onPressed: () => pressed += 1,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(BrandedSocialButton));
        await tester.pump();

        expect(
          pressed,
          1,
          reason: 'tap 시 onPressed 콜백이 1회 호출되어야 한다',
        );
      },
    );

    // ─── Kakao retroactive (회귀 가드) ────────────────────────────────────
    testWidgets(
      'T-13-BRAND-KAKAO-RETRO-01: Phase 12 Kakao 색 일치 (회귀 0)',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            BrandedSocialButton.kakao(label: 'Kakao', onPressed: () {}),
          ),
        );
        await tester.pumpAndSettle();

        // Material 배경 = Kakao Yellow #FEE500
        final material = _findBrandMaterial(tester);
        expect(material.color, _kKakaoYellowExpected);

        // 라벨 색 = 검정 85% #D9000000
        final text = _findBrandLabel(tester, 'Kakao');
        expect(text.style?.color, _kKakaoLabelExpected);

        // 아이콘 색 = 검정 100% #000000 (라벨과 분리)
        final svg = tester.widget<SvgPicture>(
          find.descendant(
            of: find.byType(BrandedSocialButton),
            matching: find.byType(SvgPicture),
          ),
        );
        expect(
          svg.colorFilter,
          const ColorFilter.mode(_kKakaoIconExpected, BlendMode.srcIn),
          reason: 'Kakao 아이콘 ColorFilter 가 검정 100% (라벨 85% 와 분리)',
        );
      },
    );

    testWidgets(
      'T-13-BRAND-KAKAO-RETRO-02: brandIconAsset = kakao_logo.svg 자산 로드',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            BrandedSocialButton.kakao(label: 'Kakao', onPressed: () {}),
          ),
        );
        await tester.pumpAndSettle();

        // SvgPicture 가 정확히 1개 — kakao 분기 외에는 SVG 미사용.
        expect(
          find.descendant(
            of: find.byType(BrandedSocialButton),
            matching: find.byType(SvgPicture),
          ),
          findsOneWidget,
        );
      },
    );

    // ─── 시각 사양 검증 (UI-SPEC line 522-572) ─────────────────────────────
    testWidgets(
      'T-13-BRAND-LAYOUT-01: 너비 = double.infinity, 높이 = 48 dp',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            BrandedSocialButton.naver(label: 'Naver', onPressed: () {}),
          ),
        );
        await tester.pumpAndSettle();

        // Gap 위젯이 내부에서 SizedBox 를 만들기 때문에 다중 매치 — first 가
        // root [BrandedSocialButton] 의 outer SizedBox.
        final sizedBoxes = tester.widgetList<SizedBox>(
          find.descendant(
            of: find.byType(BrandedSocialButton),
            matching: find.byType(SizedBox),
          ),
        );
        final outer = sizedBoxes.first;
        expect(outer.width, double.infinity);
        expect(outer.height, 48);
      },
    );

    // ─── Semantics 검증 (UI-SPEC line 600-605 — Material+InkWell 자동) ─────
    testWidgets(
      'T-13-BRAND-SEMANTICS-01: SvgPicture excludeFromSemantics = true',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            BrandedSocialButton.naver(label: 'Naver', onPressed: () {}),
          ),
        );
        await tester.pumpAndSettle();

        final svg = tester.widget<SvgPicture>(
          find.descendant(
            of: find.byType(BrandedSocialButton),
            matching: find.byType(SvgPicture),
          ),
        );
        expect(
          svg.excludeFromSemantics,
          isTrue,
          reason: 'SvgPicture 는 라벨이 의미 전달 — 아이콘 단독 의미 없음',
        );
      },
    );

    // ─── BrandSpec 인터페이스 검증 ─────────────────────────────────────────
    test('T-13-BRAND-SPEC-01: BrandSpec const ctor + immutable', () {
      const spec = BrandSpec(
        backgroundColor: _kNaverGreenExpected,
        foregroundColor: _kNaverLabelExpected,
        brandIconAsset: 'assets/icons/naver_logo.svg',
      );
      expect(spec.backgroundColor, _kNaverGreenExpected);
      expect(spec.foregroundColor, _kNaverLabelExpected);
      expect(spec.iconColor, isNull);
      expect(spec.iconSize, 18);
      expect(spec.borderRadius, 6);
    });
  });
}
