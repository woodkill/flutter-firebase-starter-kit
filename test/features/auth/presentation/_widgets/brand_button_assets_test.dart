// 소셜 로그인 버튼이 쓰는 번들 자산(글꼴 · 로고)의 계약 테스트.
//
// 이 자산들은 외부 원문에서 만든 파일이라, 바뀌어도 눈으로는 알기 어렵다. 그래서
// 커밋한 파일의 sha256 과 번들 선언을 여기에 고정한다. 자산을 다시 만들면 해시가
// 달라지므로 그 자산의 README 와 이 파일의 값을 함께 고친다.
//
// 원문이 있어야 하는 대조(원본 글꼴)는 opt-in 이다 — 원문은 저장소에 싣지 않고,
// 경로를 `--dart-define` 으로 준 실행에서만 돈다. 받는 곳과 해시는 각 자산의
// README 에 있다.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/source_text.dart';

/// 번들 선언 파일.
const String _pubspecPath = 'pubspec.yaml';

/// Google Sans 라틴 subset — Google 로그인 버튼의 영문 라벨 글꼴.
const String _gsansAssetPath =
    'assets/fonts/googlesans/GoogleSans-Latin-wght.ttf';

/// [_gsansAssetPath] 의 sha256 — `assets/fonts/googlesans/README.md` 의 값과 같다.
const String _gsansSha256 =
    '349dce84fdb280f980a3cfd7e52103d2a4e2bfb7321be674fe038bbec87fda2c';

/// pubspec 이 선언하는 family 이름 — 위젯이 `fontFamily` 로 쓰는 문자열이다.
const String _gsansFamily = 'GoogleSans';

/// 원본 가변 파일을 올리는 테스트 전용 family 이름.
const String _gsansOriginalFamily = 'GoogleSansOriginal';

/// Google Sans 원본 가변 파일의 절대 경로 — 비어 있으면 원본 대조를 건너뛴다.
///
/// `--dart-define=BRAND_ASSET_GSANS_ORIGINAL=<경로>` 로 준다.
const String _gsansOrig = String.fromEnvironment('BRAND_ASSET_GSANS_ORIGINAL');

/// 원본 대조에 쓰는 문자열 — 버튼 라벨과 라틴 문장부호 · 확장 글자.
const List<String> _gsansLabels = <String>[
  'Sign in with Google',
  'Ça va — “Größe” … Łódź ñ',
];

/// 찍는 배율 — 실기기(DPR 3)와 같은 밀도로 대조한다.
const double _dpr = 3;

/// 한 번 찍은 그림의 크기와 RGBA 바이트.
typedef _Raster = ({int width, int height, Uint8List rgba});

/// 파일 바이트의 sha256 16진 문자열을 돌려준다.
String _computeSha256OfFile(String path) {
  final File file = File(path);
  if (!file.existsSync()) {
    fail('자산 파일 부재: $path');
  }
  return sha256.convert(file.readAsBytesSync()).toString();
}

/// 주석을 걷어낸 pubspec [source] 에서 `- family: [family]` 블록의 줄을 돌려준다.
///
/// family 줄 다음 줄부터 다음 `- family:` 줄이나 빈 줄 앞까지다. 블록이 없으면
/// 빈 목록이다.
List<String> _extractFontFamilyBlock(String source, String family) {
  final List<String> lines = stripHashComments(source).split('\n');
  final RegExp target = RegExp(
    '^\\s*-\\s*family:\\s*${RegExp.escape(family)}\\s*\$',
  );
  final RegExp anyFamily = RegExp(r'^\s*-\s*family:\s*\S');
  final int start = lines.indexWhere(target.hasMatch);
  if (start == -1) {
    return <String>[];
  }
  final List<String> block = <String>[];
  for (int i = start + 1; i < lines.length; i++) {
    if (anyFamily.hasMatch(lines[i]) || lines[i].trim().isEmpty) {
      break;
    }
    block.add(lines[i]);
  }
  return block;
}

/// [block] 에서 `- asset: <경로>` 줄의 경로만 모은다.
List<String> _collectFontAssets(List<String> block) {
  final RegExp asset = RegExp(r'^\s*-\s*asset:\s*(\S+)\s*$');
  return block
      .map(asset.firstMatch)
      .whereType<RegExpMatch>()
      .map((RegExpMatch match) => match.group(1)!)
      .toList();
}

/// [block] 에 `weight:` 줄이 몇 개인지 센다.
int _countWeightLines(List<String> block) =>
    block.where(RegExp(r'^\s*weight:\s*\S').hasMatch).length;

/// [path] 의 글꼴 파일을 [family] 이름으로 올린다.
Future<void> _loadFontFile(String family, String path) async {
  final File file = File(path);
  if (!file.existsSync()) {
    fail('글꼴 파일 부재: $path');
  }
  final Uint8List bytes = file.readAsBytesSync();
  final FontLoader loader = FontLoader(family)
    ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
  await loader.load();
}

/// [label] 을 버튼 라벨과 같은 조건(16sp · 줄 높이 22 · 자간 0.1)으로 그려 찍는다.
///
/// [variations] 를 주면 가변 축을 그 값으로 고정한다 — 원본 가변 파일은 축을
/// 명시하지 않으면 실행 환경이 광학 크기 축을 스스로 골라 폭이 달라진다.
Future<_Raster> _renderLabel(
  WidgetTester tester,
  String label, {
  required String family,
  required FontWeight weight,
  List<ui.FontVariation>? variations,
}) async {
  final GlobalKey boundaryKey = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFFFFFFF),
        body: Center(
          child: RepaintBoundary(
            key: boundaryKey,
            child: Container(
              color: const Color(0xFFFFFFFF),
              padding: const EdgeInsets.all(8),
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: family,
                  fontSize: 16,
                  fontWeight: weight,
                  height: 22 / 16,
                  letterSpacing: 0.1,
                  color: const Color(0xFF000000),
                  leadingDistribution: TextLeadingDistribution.even,
                  fontVariations: variations,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final RenderObject? renderObject = boundaryKey.currentContext
      ?.findRenderObject();
  if (renderObject is! RenderRepaintBoundary) {
    fail('RepaintBoundary 를 찾지 못했다: $label');
  }
  final _Raster? raster = await tester.runAsync<_Raster>(() async {
    final ui.Image image = await renderObject.toImage(pixelRatio: _dpr);
    final ByteData? data = await image.toByteData();
    final int width = image.width;
    final int height = image.height;
    image.dispose();
    if (data == null) {
      fail('그림을 RGBA 로 읽지 못했다: $label');
    }
    return (
      width: width,
      height: height,
      rgba: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  });
  if (raster == null) {
    fail('그림을 찍지 못했다: $label');
  }
  return raster;
}

/// 두 그림에서 RGBA 가 다른 픽셀 수를 센다.
///
/// 왼쪽 위를 맞춰 겹쳐 놓고 센다. 크기가 다르면 한쪽에만 있는 자리의 픽셀도
/// 다르다고 센다.
int _countDifferentPixels(_Raster a, _Raster b) {
  final int width = a.width > b.width ? a.width : b.width;
  final int height = a.height > b.height ? a.height : b.height;
  int count = 0;
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final bool isInA = x < a.width && y < a.height;
      final bool isInB = x < b.width && y < b.height;
      if (!isInA || !isInB) {
        count++;
        continue;
      }
      final int ia = (y * a.width + x) * 4;
      final int ib = (y * b.width + x) * 4;
      if (a.rgba[ia] != b.rgba[ib] ||
          a.rgba[ia + 1] != b.rgba[ib + 1] ||
          a.rgba[ia + 2] != b.rgba[ib + 2] ||
          a.rgba[ia + 3] != b.rgba[ib + 3]) {
        count++;
      }
    }
  }
  return count;
}

/// 원본 가변 파일을 축소본과 같은 자리(`opsz` 18 · `GRAD` 0)에 놓는 축 값.
List<ui.FontVariation> _buildOriginalAxes(double weight) => <ui.FontVariation>[
  ui.FontVariation('wght', weight),
  const ui.FontVariation('opsz', 18),
  const ui.FontVariation('GRAD', 0),
];

void main() {
  group('Google Sans 라틴 subset', () {
    test('T-177-ASSET-01: 번들 글꼴 파일의 sha256 이 고정값과 같다', () {
      expect(
        _computeSha256OfFile(_gsansAssetPath),
        _gsansSha256,
        reason:
            '$_gsansAssetPath 가 바뀌었다 — 다시 만들었으면 README 와 이 값을 '
            '함께 고친다',
      );
    });

    test('T-177-ASSET-02: pubspec 이 GoogleSans family 를 weight 줄 없이 선언한다', () {
      final String pubspec = readTrackedFile(_pubspecPath);

      // 양성 대조 1: 같은 추출이 이미 있는 family 블록을 찾는다.
      expect(
        _collectFontAssets(_extractFontFamilyBlock(pubspec, 'Roboto')),
        <String>['assets/fonts/roboto/Roboto-VariableFont_wdth_wght.ttf'],
        reason: '추출 방법이 Roboto 블록을 찾지 못한다',
      );
      // 양성 대조 2: weight 줄이 있으면 같은 계수가 센다.
      const String sample =
          'fonts:\n'
          '  - family: Sample\n'
          '    fonts:\n'
          '      - asset: a.ttf\n'
          '        weight: 500\n';
      expect(_countWeightLines(_extractFontFamilyBlock(sample, 'Sample')), 1);

      final List<String> block = _extractFontFamilyBlock(pubspec, _gsansFamily);
      expect(_collectFontAssets(block), <String>[
        _gsansAssetPath,
      ], reason: 'pubspec fonts: 에 family $_gsansFamily 선언이 없거나 asset 이 다르다');
      expect(
        _countWeightLines(block),
        0,
        reason:
            '$_gsansFamily 는 굵기 가변 파일 하나다 — weight 줄을 두지 않는다'
            '(굵기는 파일의 wght 축이 정한다)',
      );
    });

    group('원본 대조', () {
      setUpAll(() async {
        if (_gsansOrig.isEmpty) {
          return;
        }
        await _loadFontFile(_gsansFamily, _gsansAssetPath);
        await _loadFontFile(_gsansOriginalFamily, _gsansOrig);
      });

      // 원본 가변 파일(약 5MB)은 저장소에 없다 — 경로를 dart-define 으로 준
      // 실행에서만 돈다.
      testWidgets('T-177-ASSET-03: 축소본으로 그린 글자가 원본 가변 파일과 픽셀까지 같다', (
        WidgetTester tester,
      ) async {
        tester.view.devicePixelRatio = _dpr;
        addTearDown(tester.view.resetDevicePixelRatio);

        int diffTotal = 0;
        int controlTotal = 0;
        final List<int> controls = <int>[];
        for (int i = 0; i < _gsansLabels.length; i++) {
          final String label = _gsansLabels[i];
          final _Raster subset = await _renderLabel(
            tester,
            label,
            family: _gsansFamily,
            weight: FontWeight.w500,
          );
          final _Raster original = await _renderLabel(
            tester,
            label,
            family: _gsansOriginalFamily,
            weight: FontWeight.w500,
            variations: _buildOriginalAxes(500),
          );
          // 대조군: 굵기만 다르게 그린 원본 — 같은 측정이 차이를 내야 한다.
          final _Raster lighter = await _renderLabel(
            tester,
            label,
            family: _gsansOriginalFamily,
            weight: FontWeight.w400,
            variations: _buildOriginalAxes(400),
          );
          final int diff = _countDifferentPixels(subset, original);
          final int control = _countDifferentPixels(subset, lighter);
          diffTotal += diff;
          controlTotal += control;
          controls.add(control);
          debugPrint(
            'GSANS_PIXEL_DETAIL label=$i '
            'subset=${subset.width}x${subset.height} '
            'original=${original.width}x${original.height} '
            'control=${lighter.width}x${lighter.height} '
            'diff_px=$diff control_diff_px=$control',
          );
        }
        debugPrint(
          'GSANS_PIXEL identical=${diffTotal == 0 ? 'yes' : 'no'} '
          'diff_px=$diffTotal control_diff_px=$controlTotal',
        );

        expect(
          diffTotal,
          0,
          reason: '축소본 렌더가 원본(wght 500 · opsz 18 · GRAD 0)과 다르다',
        );
        expect(
          controls.every((int control) => control > 0),
          isTrue,
          reason: '굵기를 다르게 그려도 차이가 0 이다 — 글꼴이 올라가지 않았다: $controls',
        );
      }, skip: _gsansOrig.isEmpty);
    });
  });
}
