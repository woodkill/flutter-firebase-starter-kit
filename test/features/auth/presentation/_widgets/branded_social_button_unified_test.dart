// 소셜 버튼 공통 골격 계약 — 골격 값 한 벌 · 스킨 값 6벌 · iOS 에서 달라지는
// 값을 고정한다.
//
// 공통 골격은 미리보기 값이 있을 때만 그려진다. 이 파일은 실제로 쓸 값과
// 일부러 다른 표식 값을 넣어, 위젯이 그 값을 주입받아 그린다는 것까지 확인한다.
// 기대값은 가이드 값의 리터럴 · 골격 상수 · 표식 값으로만 쓴다 — 스킨 객체에서
// 읽은 값을 스킨 객체와 견주지 않는다.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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

/// 버튼 밖에 두는 대조 글자 — 글자 배율 상한이 라벨에만 걸리는지 볼 때 쓴다.
const String _controlText = 'Aa';

/// 이름 붙은 생성자 6개가 함께 갖는 모양.
typedef _ButtonBuilder =
    BrandedSocialButton Function({
      required String label,
      required VoidCallback? onPressed,
      Key? key,
    });

/// provider 한 개의 시험 재료 — 이름 · 영문 로그인 문구 · 생성자.
typedef _ProviderCase = ({String name, String label, _ButtonBuilder build});

/// 스킨 한 벌의 기대값 — 가이드 값을 리터럴로 적는다.
typedef _SkinExpectation = ({
  Color lightBackground,
  Color darkBackground,
  Color lightLabel,
  Color darkLabel,
  Color? lightOutline,
  Color? darkOutline,
  String lightLogoAsset,
  String darkLogoAsset,
  bool isBitmapLogo,
  Size logoSize,
  Color? logoTint,
  double logoGap,
  String labelFontFamily,
});

/// 그려진 버튼에서 읽은 값 묶음 — 플랫폼끼리 견줄 때 쓴다.
typedef _Snapshot = Map<String, Object?>;

const _ProviderCase _google = (
  name: 'google',
  label: 'Sign in with Google',
  build: BrandedSocialButton.google,
);
const _ProviderCase _apple = (
  name: 'apple',
  label: 'Sign in with Apple',
  build: BrandedSocialButton.apple,
);
const _ProviderCase _facebook = (
  name: 'facebook',
  label: 'Login with Facebook',
  build: BrandedSocialButton.facebook,
);
const _ProviderCase _kakao = (
  name: 'kakao',
  label: 'Login with Kakao',
  build: BrandedSocialButton.kakao,
);
const _ProviderCase _naver = (
  name: 'naver',
  label: 'Log in with NAVER',
  build: BrandedSocialButton.naver,
);
const _ProviderCase _line = (
  name: 'line',
  label: 'Log in with LINE',
  build: BrandedSocialButton.line,
);

const List<_ProviderCase> _cases = <_ProviderCase>[
  _google,
  _apple,
  _facebook,
  _kakao,
  _naver,
  _line,
];

/// 기본 간격을 쓰는 provider — Google 은 가이드 값, Apple 은 표식 값을 쓴다.
const Set<String> _defaultGapProviders = <String>{
  'facebook',
  'kakao',
  'naver',
  'line',
};

/// 버튼 한 개와 대조 글자를 `MaterialApp` 안에 그린다.
///
/// 호출마다 새 key 를 줘 앞선 pump 의 테마 전환 애니메이션이 섞이지 않게 한다.
Future<void> _pumpButton(
  WidgetTester tester,
  _ProviderCase provider, {
  Brightness brightness = Brightness.light,
  TargetPlatform platform = TargetPlatform.android,
  bool isEnabled = true,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      theme: ThemeData(brightness: brightness, platform: platform),
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child ?? const SizedBox.shrink(),
      ),
      home: Scaffold(
        body: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            provider.build(
              label: provider.label,
              onPressed: isEnabled ? () {} : null,
            ),
            const Text(_controlText),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
}

/// 버튼 안에서만 찾는다.
Finder _findInButton(Finder matching) =>
    find.descendant(of: find.byType(BrandedSocialButton), matching: matching);

/// 버튼의 로고 위젯을 찾는다 — SVG 또는 비트맵.
Finder _findLogo() => _findInButton(
  find.byWidgetPredicate((Widget w) => w is SvgPicture || w is Image),
);

/// 버튼 바탕 `Material` 을 찾는다.
Finder _findSurface() => _findInButton(find.byType(Material));

/// [text] 를 그린 문단이 글자 크기 16 을 실제로 몇으로 그리는지 읽는다.
double _readScaledFontSize(WidgetTester tester, String text) {
  final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: find.text(text), matching: find.byType(RichText)),
  );
  return paragraph.textScaler.scale(16);
}

/// 번들에서 [asset] 을 읽어 바이트 수를 돌려준다 — 경로가 실제 자산인지 본다.
Future<int> _loadAssetLength(WidgetTester tester, String asset) async {
  final ByteData? data = await tester.runAsync<ByteData>(
    () => rootBundle.load(asset),
  );
  return data?.lengthInBytes ?? 0;
}

/// 밝은 · 어두운 테마에서 그려진 버튼의 스킨 값을 [want] 와 견준다.
Future<void> _expectSkin(
  WidgetTester tester,
  _ProviderCase provider,
  _SkinExpectation want,
) async {
  for (final Brightness brightness in Brightness.values) {
    final bool isDark = brightness == Brightness.dark;
    await _pumpButton(tester, provider, brightness: brightness);
    final String where = '${provider.name} · ${brightness.name}';

    final Material surface = tester.widget<Material>(_findSurface());
    expect(
      surface.color,
      isDark ? want.darkBackground : want.lightBackground,
      reason: '$where 배경색',
    );
    final Color? wantOutline = isDark ? want.darkOutline : want.lightOutline;
    expect(
      surface.shape,
      isA<RoundedRectangleBorder>().having(
        (RoundedRectangleBorder s) => s.side,
        'side',
        wantOutline == null
            ? BorderSide.none
            : BorderSide(color: wantOutline, width: 1),
      ),
      reason: '$where 외곽선',
    );

    final TextStyle? style = tester
        .widget<Text>(find.text(provider.label))
        .style;
    expect(
      style?.color,
      isDark ? want.darkLabel : want.lightLabel,
      reason: '$where 글자색',
    );
    expect(style?.fontFamily, want.labelFontFamily, reason: '$where 라벨 글꼴');

    final String wantAsset = isDark ? want.darkLogoAsset : want.lightLogoAsset;
    final Color? wantTint = want.logoTint;
    final Finder logoFinder = _findLogo();
    final Widget logo = tester.widget<Widget>(logoFinder);
    if (want.isBitmapLogo) {
      expect(
        logo,
        isA<Image>().having(
          (Image i) => i.image,
          'image',
          isA<AssetImage>().having(
            (AssetImage a) => a.assetName,
            'assetName',
            wantAsset,
          ),
        ),
        reason: '$where 로고 = 비트맵 자산',
      );
    } else {
      expect(
        logo,
        isA<SvgPicture>()
            .having(
              (SvgPicture s) => s.bytesLoader,
              'bytesLoader',
              isA<SvgAssetLoader>().having(
                (SvgAssetLoader l) => l.assetName,
                'assetName',
                wantAsset,
              ),
            )
            .having(
              (SvgPicture s) => s.colorFilter,
              'colorFilter',
              wantTint == null
                  ? isNull
                  : ColorFilter.mode(wantTint, BlendMode.srcIn),
            ),
        reason: '$where 로고 = SVG 자산 · 단색 칠',
      );
    }
    expect(
      await _loadAssetLength(tester, wantAsset),
      greaterThan(0),
      reason: '$where 로고 경로가 번들 자산을 가리킨다',
    );

    final Size logoSize = tester.getSize(logoFinder);
    expect(
      logoSize.width,
      closeTo(want.logoSize.width, 1e-9),
      reason: '$where 로고 상자 폭',
    );
    expect(
      logoSize.height,
      closeTo(want.logoSize.height, 1e-9),
      reason: '$where 로고 상자 높이',
    );

    expect(
      tester.widget<Row>(_findInButton(find.byType(Row))).children[1],
      isA<SizedBox>().having((SizedBox b) => b.width, 'width', want.logoGap),
      reason: '$where 로고와 라벨 사이 간격',
    );
  }
}

/// [platform] 으로 그린 버튼에서 플랫폼끼리 견줄 값을 읽는다.
Future<_Snapshot> _readSnapshot(
  WidgetTester tester,
  _ProviderCase provider,
  TargetPlatform platform,
) async {
  await _pumpButton(tester, provider, platform: platform);
  final Finder labelFinder = find.text(provider.label);
  final TextStyle? style = tester.widget<Text>(labelFinder).style;
  final Finder rowFinder = _findInButton(find.byType(Row));
  final Widget gap = tester.widget<Row>(rowFinder).children[1];
  final Material surface = tester.widget<Material>(_findSurface());
  return <String, Object?>{
    'labelFontFamily': style?.fontFamily,
    'labelTopInset': tester
        .widget<Padding>(
          find.ancestor(of: labelFinder, matching: find.byType(Padding)).first,
        )
        .padding,
    'horizontalPadding': tester
        .widget<Padding>(
          find.ancestor(of: rowFinder, matching: find.byType(Padding)).first,
        )
        .padding,
    'logoGap': gap is SizedBox ? gap.width : null,
    'fontSize': style?.fontSize,
    'fontWeight': style?.fontWeight,
    'lineHeight': style?.height,
    'letterSpacing': style?.letterSpacing,
    'backgroundColor': surface.color,
    'labelColor': style?.color,
    'shape': surface.shape,
    'logoSize': tester.getSize(_findLogo()),
  };
}

/// 두 값 묶음에서 서로 다른 항목만 `(앞, 뒤)` 쌍으로 모은다.
Map<String, (Object?, Object?)> _diffSnapshots(_Snapshot from, _Snapshot to) =>
    <String, (Object?, Object?)>{
      for (final String key in from.keys)
        if (from[key] != to[key]) key: (from[key], to[key]),
    };

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

          final Finder surface = _findSurface();
          expect(
            tester.getSize(surface).height,
            kBrandButtonHeight,
            reason: '$where 그려진 높이',
          );
          expect(
            tester.widget<Material>(surface).shape,
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

    testWidgets('T-177-SKEL-04: 글자 배율 2.0 에서 라벨만 상한까지 커지고 '
        '버튼 높이 · 로고 상자는 그대로다', (tester) async {
      for (final _ProviderCase provider in _cases) {
        final String where = provider.name;

        await _pumpButton(tester, provider);
        expect(
          _readScaledFontSize(tester, provider.label),
          16,
          reason: '$where 배율 1.0 라벨',
        );
        expect(
          tester.getSize(_findSurface()).height,
          48,
          reason: '$where 배율 1.0 버튼 높이',
        );
        final Size logoAtBase = tester.getSize(_findLogo());

        await _pumpButton(tester, provider, textScale: 2);
        expect(
          _readScaledFontSize(tester, provider.label),
          16 * _metrics.labelScaleCap,
          reason: '$where 배율 2.0 라벨 = 16 × 주입한 상한',
        );
        expect(
          _readScaledFontSize(tester, _controlText),
          32,
          reason: '$where 버튼 밖 글자는 배율 2.0 을 그대로 받는다',
        );
        expect(
          tester.getSize(_findSurface()).height,
          48,
          reason: '$where 배율 2.0 버튼 높이',
        );
        expect(
          tester.getSize(_findLogo()),
          logoAtBase,
          reason: '$where 로고 상자는 글자 배율을 따르지 않는다',
        );
      }
    });

    testWidgets('T-177-SKEL-05: 비활성 버튼 6개가 주입한 한 값의 투명도로 '
        '그려진다', (tester) async {
      for (final _ProviderCase provider in _cases) {
        for (final bool isEnabled in <bool>[false, true]) {
          await _pumpButton(tester, provider, isEnabled: isEnabled);
          final String where = '${provider.name} · ${isEnabled ? '활성' : '비활성'}';

          expect(
            tester.widget<Opacity>(_findInButton(find.byType(Opacity))).opacity,
            isEnabled ? 1.0 : _metrics.disabledOpacity,
            reason: '$where 투명도',
          );
          final Semantics semantics = tester.widget<Semantics>(
            _findInButton(
              find.byWidgetPredicate(
                (Widget w) => w is Semantics && w.properties.button == true,
              ),
            ),
          );
          expect(
            semantics.properties.enabled,
            isEnabled,
            reason: '$where 접근성 enabled',
          );
          expect(
            semantics.properties.label,
            provider.label,
            reason: '$where 접근성 라벨',
          );
        }
      }
    });

    testWidgets('T-177-SKEL-06: 폭 280 · 글자 배율 2.0 에서도 라벨 6개가 '
        '한 줄로 그려지고 넘침 오류가 없다', (tester) async {
      tester.view.physicalSize = const Size(280, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      for (final _ProviderCase provider in _cases) {
        await _pumpButton(tester, provider, textScale: 2);
        final String where = provider.name;

        expect(tester.takeException(), isNull, reason: '$where 넘침 오류');
        final Finder labelFinder = find.text(provider.label);
        expect(labelFinder, findsOneWidget, reason: '$where 라벨 문구 그대로');
        expect(
          tester.widget<Text>(labelFinder).maxLines,
          1,
          reason: '$where 한 줄',
        );
        expect(
          tester.getSize(labelFinder).height,
          lessThanOrEqualTo(48),
          reason: '$where 라벨이 버튼 높이 안에 든다',
        );
        final Size surfaceSize = tester.getSize(_findSurface());
        expect(surfaceSize.height, 48, reason: '$where 버튼 높이');
        expect(
          surfaceSize.width,
          lessThanOrEqualTo(280),
          reason: '$where 버튼이 화면 폭 안에 든다',
        );
      }
    });
  });

  group('브랜드 스킨 — provider 마다 남는 값', () {
    testWidgets('T-177-SKIN-01: Google — 흰 · 어두운 바탕 · 외곽선 1 · '
        'gradient G 비트맵 20 · 간격 10 · Google Sans', (tester) async {
      await _expectSkin(tester, _google, (
        lightBackground: const Color(0xFFFFFFFF),
        darkBackground: const Color(0xFF131314),
        lightLabel: const Color(0xFF1F1F1F),
        darkLabel: const Color(0xFFE3E3E3),
        lightOutline: const Color(0xFF747775),
        darkOutline: const Color(0xFF8E918F),
        lightLogoAsset: 'assets/brand/google/g.png',
        darkLogoAsset: 'assets/brand/google/g.png',
        isBitmapLogo: true,
        logoSize: const Size(20, 20),
        logoTint: null,
        logoGap: 10,
        labelFontFamily: 'GoogleSans',
      ));
    });

    testWidgets('T-177-SKIN-02: Apple — 검정 · 흰 바탕 · 밝기별 흑 · 백 '
        'medium 로고 · 로고 높이 = 버튼 높이', (tester) async {
      await _expectSkin(tester, _apple, (
        lightBackground: const Color(0xFF000000),
        darkBackground: const Color(0xFFFFFFFF),
        lightLabel: const Color(0xFFFFFFFF),
        darkLabel: const Color(0xFF000000),
        lightOutline: null,
        darkOutline: null,
        lightLogoAsset:
            'assets/brand/apple/white_logo/btn_signin_icon_medium.svg',
        darkLogoAsset:
            'assets/brand/apple/black_logo/btn_signin_icon_medium.svg',
        isBitmapLogo: false,
        logoSize: const Size(17 * 48 / 44, 48),
        logoTint: null,
        logoGap: 11,
        labelFontFamily: 'Roboto',
      ));

      await _pumpButton(tester, _apple);
      expect(
        tester.getSize(_findLogo()).height,
        tester.getSize(_findSurface()).height,
        reason:
            'Apple 가이드 — 로고 파일의 높이를 버튼 높이에 맞춘다 '
            '("Match the height of the logo file to the height of the button")',
      );
      expect(
        tester.widget<Row>(_findInButton(find.byType(Row))).children[1],
        isA<SizedBox>().having(
          (SizedBox b) => b.width,
          'width',
          _metrics.appleLogoGap,
        ),
        reason: 'Apple 로고 옆 간격은 주입한 값에서 온다',
      );
    });

    testWidgets('T-177-SKIN-03: Facebook — 흰 · 어두운 바탕 · 외곽선 1 · '
        '로고 20 · 간격 8', (tester) async {
      await _expectSkin(tester, _facebook, (
        lightBackground: const Color(0xFFFFFFFF),
        darkBackground: const Color(0xFF131314),
        lightLabel: const Color(0xFF1F1F1F),
        darkLabel: const Color(0xFFE3E3E3),
        lightOutline: const Color(0xFF747775),
        darkOutline: const Color(0xFF8E918F),
        lightLogoAsset: 'assets/brand/facebook/btn_signin_icon.svg',
        darkLogoAsset: 'assets/brand/facebook/btn_signin_icon.svg',
        isBitmapLogo: false,
        logoSize: const Size(20, 20),
        logoTint: null,
        logoGap: 8,
        labelFontFamily: 'Roboto',
      ));
    });

    testWidgets('T-177-SKIN-04: Kakao — 노랑 바탕 · 검정 85% 글자 · '
        '검정 심볼 20 · radius 12', (tester) async {
      await _expectSkin(tester, _kakao, (
        lightBackground: const Color(0xFFFEE500),
        darkBackground: const Color(0xFFFEE500),
        lightLabel: const Color(0xD9000000),
        darkLabel: const Color(0xD9000000),
        lightOutline: null,
        darkOutline: null,
        lightLogoAsset: 'assets/brand/kakao/btn_signin_icon.svg',
        darkLogoAsset: 'assets/brand/kakao/btn_signin_icon.svg',
        isBitmapLogo: false,
        logoSize: const Size(20, 20),
        logoTint: const Color(0xFF000000),
        logoGap: 8,
        labelFontFamily: 'Roboto',
      ));

      await _pumpButton(tester, _kakao);
      expect(
        tester.widget<Material>(_findSurface()).shape,
        isA<RoundedRectangleBorder>().having(
          (RoundedRectangleBorder s) => s.borderRadius,
          'borderRadius',
          BorderRadius.circular(12),
        ),
        reason: 'Kakao 가이드 — 「컨테이너 박스의 radius는 12 픽셀로 적용합니다」',
      );
    });

    testWidgets('T-177-SKIN-05: Naver — 초록 바탕 · 흰 글자 · 흰 로고 18 · '
        '간격 8', (tester) async {
      await _expectSkin(tester, _naver, (
        lightBackground: const Color(0xFF03A94D),
        darkBackground: const Color(0xFF03A94D),
        lightLabel: const Color(0xFFFFFFFF),
        darkLabel: const Color(0xFFFFFFFF),
        lightOutline: null,
        darkOutline: null,
        lightLogoAsset: 'assets/brand/naver/btn_signin_icon.svg',
        darkLogoAsset: 'assets/brand/naver/btn_signin_icon.svg',
        isBitmapLogo: false,
        logoSize: const Size(18, 18),
        logoTint: const Color(0xFFFFFFFF),
        logoGap: 8,
        labelFontFamily: 'Roboto',
      ));

      await _pumpButton(tester, _naver);
      expect(
        tester.getSize(_findLogo()).height,
        greaterThan(_readScaledFontSize(tester, _naver.label)),
        reason: 'Naver 가이드 — 「텍스트는 로고 높이보다 작은 크기를 사용해야 해요」',
      );
      expect(
        tester.widget<Row>(_findInButton(find.byType(Row))).children[1],
        isA<SizedBox>().having((SizedBox b) => b.width, 'width', 8),
        reason: 'Naver 가이드 — 「가운데 정렬 시 로고와 레이블의 간격은 8px」',
      );
    });

    testWidgets('T-177-SKIN-06: LINE — 초록 바탕 · 흰 글자 · 흰 로고 '
        '47 : 44 · 간격 8', (tester) async {
      await _expectSkin(tester, _line, (
        lightBackground: const Color(0xFF06C755),
        darkBackground: const Color(0xFF06C755),
        lightLabel: const Color(0xFFFFFFFF),
        darkLabel: const Color(0xFFFFFFFF),
        lightOutline: null,
        darkOutline: null,
        lightLogoAsset: 'assets/brand/line/btn_signin_icon.svg',
        darkLogoAsset: 'assets/brand/line/btn_signin_icon.svg',
        isBitmapLogo: false,
        logoSize: const Size(20 * 47 / 44, 20),
        logoTint: const Color(0xFFFFFFFF),
        logoGap: 8,
        labelFontFamily: 'Roboto',
      ));

      await _pumpButton(tester, _line);
      final Size logoSize = tester.getSize(_findLogo());
      expect(
        logoSize.width / logoSize.height,
        closeTo(47 / 44, 1e-9),
        reason:
            'LINE 가이드 — 로고의 종횡비를 바꾸지 않는다 '
            '("The aspect ratio of the LINE icon does not change")',
      );
    });
  });

  group('iOS 에서 달라지는 값', () {
    testWidgets('T-177-IOS-01: Android 와 iOS 사이에 달라지는 값은 Google 의 '
        '여백 · 간격과 나머지 5개의 글꼴 · 라벨 위 여백뿐이다', (tester) async {
      for (final _ProviderCase provider in _cases) {
        final _Snapshot android = await _readSnapshot(
          tester,
          provider,
          TargetPlatform.android,
        );
        final _Snapshot ios = await _readSnapshot(
          tester,
          provider,
          TargetPlatform.iOS,
        );
        final _Snapshot macos = await _readSnapshot(
          tester,
          provider,
          TargetPlatform.macOS,
        );

        final Map<String, (Object?, Object?)> want = provider.name == 'google'
            ? <String, (Object?, Object?)>{
                'horizontalPadding': (
                  const EdgeInsets.symmetric(horizontal: 12),
                  const EdgeInsets.symmetric(horizontal: 16),
                ),
                'logoGap': (10.0, 12.0),
              }
            : <String, (Object?, Object?)>{
                'labelFontFamily': ('Roboto', 'CupertinoSystemText'),
                'labelTopInset': (
                  EdgeInsets.zero,
                  const EdgeInsets.only(top: 3),
                ),
              };
        expect(
          _diffSnapshots(android, ios),
          want,
          reason: '${provider.name} Android → iOS 에서 달라진 항목',
        );
        expect(macos, ios, reason: '${provider.name} macOS 는 iOS 와 같은 값을 쓴다');
      }
    });
  });
}
