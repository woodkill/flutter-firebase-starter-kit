// 소셜 로그인 버튼이 쓰는 번들 자산(글꼴 · 로고)의 계약 테스트.
//
// 이 자산들은 외부 원문에서 만든 파일이라, 바뀌어도 눈으로는 알기 어렵다. 그래서
// 커밋한 파일의 sha256 과 번들 선언을 여기에 고정한다. 자산을 다시 만들면 해시가
// 달라지므로 그 자산의 README 와 이 파일의 값을 함께 고친다.
//
// 원문이 있어야 하는 대조(원본 글꼴 · 공식 버튼 그림)는 opt-in 이다 — 원문은
// 저장소에 싣지 않고, 경로를 `--dart-define` 으로 준 실행에서만 돈다. 받는 곳과
// 해시는 각 자산의 README 에 있다.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/planning_docs.dart';
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

/// Google 「G」 투명 PNG 의 배율별 경로 · sha256.
///
/// 1배 파일(20px)이 기본이고 2 ~ 4배(40 · 60 · 80px)는 같은 이름으로 `N.0x/`
/// 아래에 있다. 값은 `assets/brand/google/` 의 파일을 다시 만들면 함께 고친다.
const List<({int scale, String path, String sha256})>
_gVariants = <({int scale, String path, String sha256})>[
  (
    scale: 1,
    path: 'assets/brand/google/g.png',
    sha256: '7dd27866e69aa77ab7b9d4aae6649e3207d29d60100d3a36b0aa69edcda2270c',
  ),
  (
    scale: 2,
    path: 'assets/brand/google/2.0x/g.png',
    sha256: 'c56f8e471761761735fb0dc0f06500d01ac1b60f4c7ff8312eece7ab3bae4600',
  ),
  (
    scale: 3,
    path: 'assets/brand/google/3.0x/g.png',
    sha256: '17bfc27f2bbbc7d60de882b8aad89af030aba833aa8ed0c915e5401fb705a595',
  ),
  (
    scale: 4,
    path: 'assets/brand/google/4.0x/g.png',
    sha256: '830af225265111738899788c16db2783120e7da58c035b4c157a6f3e809f1e29',
  ),
];

/// Google 공식 로그인 버튼 그림 묶음을 푼 디렉터리의 절대 경로.
///
/// 비어 있으면 공식 그림 대조를 건너뛴다.
/// `--dart-define=BRAND_ASSET_GOOGLE_SIGNIN_DIR=<경로>` 로 준다.
const String _gDir = String.fromEnvironment('BRAND_ASSET_GOOGLE_SIGNIN_DIR');

/// 공식 그림과 대조할 때 G 를 얹는 배경 — 공식 Light · Dark 버튼의 바탕색.
const List<({String label, String theme, List<int> background})> _gThemes =
    <({String label, String theme, List<int> background})>[
      (label: 'white', theme: 'Light', background: <int>[0xFF, 0xFF, 0xFF]),
      (label: 'dark', theme: 'Dark', background: <int>[0x13, 0x13, 0x14]),
    ];

/// Apple 공식 medium 로고 — 검정(밝은 바탕용).
const String _appleBlackMediumPath =
    'assets/brand/apple/black_logo/btn_signin_icon.svg';

/// Apple 공식 medium 로고 — 흰색(어두운 바탕용).
const String _appleWhiteMediumPath =
    'assets/brand/apple/white_logo/btn_signin_icon.svg';

/// Apple medium 로고 path(`d` 속성 문자열)의 sha256.
///
/// Apple 웹 로그인 스크립트의 `medium` 로고 객체에서 옮긴 문자열 그대로다.
const String _appleMediumPathSha256 =
    '870e7f7ff994651ec0d878cd0dd6007c2b99089332e65efb656a4862d3cabf74';

/// Apple medium 로고의 viewBox — 캔버스 31 × 44 가운데 로고 폭 17 만 잘라 쓴다.
const String _appleMediumViewBox = 'viewBox="7 0 17 44"';

/// Apple small 로고 path 의 첫 좌표 — 정식 경로의 파일에 있으면 안 된다.
const String _appleSmallPathStart = 'M12.2337427,16.9879688';

/// Apple medium 로고 path 의 첫 좌표.
const String _appleMediumPathStart = 'M15.7099491,14.8846154';

/// 공식 그림 대조 기준 — 채널별 차의 평균 상한.
const double _gMeanLimit = 3;

/// 공식 그림 대조 기준 — 채널별 차의 최대 상한.
const double _gMaxLimit = 96;

/// 공식 그림 대조 기준 — 채널 최대차가 16 을 넘는 픽셀이 칸에서 차지하는 비율 상한.
const double _gOver16RatioLimit = 0.10;

/// Google 자산 디렉터리.
const String _googleAssetDir = 'assets/brand/google';

/// Apple 자산 디렉터리.
const String _appleAssetDir = 'assets/brand/apple';

/// Google 자산 디렉터리에 있어야 하는 파일 — 로고 4장과 문서 2개.
const List<String> _googleAssetFiles = <String>[
  '$_googleAssetDir/2.0x/g.png',
  '$_googleAssetDir/3.0x/g.png',
  '$_googleAssetDir/4.0x/g.png',
  '$_googleAssetDir/LICENSE.txt',
  '$_googleAssetDir/README.md',
  '$_googleAssetDir/g.png',
];

/// Apple 자산 디렉터리에 있어야 하는 파일 — 로고 2장과 문서 1개.
const List<String> _appleAssetFiles = <String>[
  '$_appleAssetDir/README.md',
  _appleBlackMediumPath,
  _appleWhiteMediumPath,
];

/// 유지보수자 트리에만 있는 파일 — 이 파일이 없는 트리에서는 집합 대조를 건너뛴다.
const List<String> _maintainerOnlyDocs = <String>['.planning/ROADMAP.md'];

/// 한 번 찍은 그림의 크기와 RGBA 바이트.
typedef _Raster = ({int width, int height, Uint8List rgba});

/// 공식 그림 대조 통계.
///
/// `mean` 은 채널별 차(픽셀 × RGB)의 전체 평균, `max` 는 채널별 차의 최대,
/// `over16` 은 채널 최대차가 16 을 넘는 픽셀 수다.
typedef _GStats = ({double mean, double max, int over16});

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
  return _captureBoundary(tester, boundaryKey, label);
}

/// [boundaryKey] 가 붙은 `RepaintBoundary` 를 [_dpr] 배로 찍는다.
///
/// [what] 은 실패 메시지에 넣는 이름이다.
Future<_Raster> _captureBoundary(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String what,
) async {
  final RenderObject? renderObject = boundaryKey.currentContext
      ?.findRenderObject();
  if (renderObject is! RenderRepaintBoundary) {
    fail('RepaintBoundary 를 찾지 못했다: $what');
  }
  final _Raster? raster = await tester.runAsync<_Raster>(() async {
    final ui.Image image = await renderObject.toImage(pixelRatio: _dpr);
    final ByteData? data = await image.toByteData();
    final int width = image.width;
    final int height = image.height;
    image.dispose();
    if (data == null) {
      fail('그림을 RGBA 로 읽지 못했다: $what');
    }
    return (
      width: width,
      height: height,
      rgba: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  });
  if (raster == null) {
    fail('그림을 찍지 못했다: $what');
  }
  return raster;
}

/// [raster] 에서 불투명한(alpha 255) 픽셀 수를 센다.
int _countOpaquePixels(_Raster raster) {
  int count = 0;
  for (int i = 3; i < raster.rgba.length; i += 4) {
    if (raster.rgba[i] == 255) {
      count++;
    }
  }
  return count;
}

/// SVG [source] 의 `<path>` 에서 `d` 속성 값을 꺼낸다. 하나가 아니면 실패한다.
String _extractSvgPathData(String source, String path) {
  final List<RegExpMatch> matches = RegExp(
    r'\sd="([^"]*)"',
  ).allMatches(source).toList();
  if (matches.length != 1) {
    fail('$path 의 d 속성이 ${matches.length}개다(1개여야 한다)');
  }
  return matches.single.group(1)!;
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

/// PNG [bytes] 의 IHDR 에서 폭 · 높이 · bit depth · color type 을 읽는다.
({int width, int height, int bitDepth, int colorType}) _readPngHeader(
  Uint8List bytes,
  String path,
) {
  const List<int> signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.length < 26) {
    fail('PNG 가 아니다(너무 짧다): $path');
  }
  for (int i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) {
      fail('PNG 서명이 아니다: $path');
    }
  }
  if (String.fromCharCodes(bytes.sublist(12, 16)) != 'IHDR') {
    fail('첫 chunk 가 IHDR 이 아니다: $path');
  }
  final ByteData data = ByteData.sublistView(bytes);
  return (
    width: data.getUint32(16),
    height: data.getUint32(20),
    bitDepth: bytes[24],
    colorType: bytes[25],
  );
}

/// PNG 파일 [path] 를 디코딩해 straight RGBA 로 돌려준다.
///
/// 엔진 디코더가 실제 시간으로 돌므로 `tester.runAsync` 안에서 부른다.
Future<_Raster> _decodePngFile(String path) async {
  final File file = File(path);
  if (!file.existsSync()) {
    fail('PNG 파일 부재: $path');
  }
  final ui.Codec codec = await ui.instantiateImageCodec(file.readAsBytesSync());
  final ui.FrameInfo frame = await codec.getNextFrame();
  final ui.Image image = frame.image;
  final ByteData? data = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  final int width = image.width;
  final int height = image.height;
  image.dispose();
  codec.dispose();
  if (data == null) {
    fail('PNG 를 RGBA 로 읽지 못했다: $path');
  }
  return (
    width: width,
    height: height,
    rgba: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
}

/// 공식 버튼 그림(Android + Web · 글자 없음 · Square)의 [scale] 배 PNG 경로.
String _buildOfficialButtonPath(String theme, int scale) {
  final String suffix = scale == 1 ? '' : '@${scale}x';
  return '$_gDir/Android + Web/PNG @${scale}x/$theme/'
      'Theme=$theme, Show text=No, Shape=Square, Platform=Android+Web$suffix.png';
}

/// [logo] 를 [background] 위에 합성한 그림과 [official] 의 한 칸을 대조한다.
///
/// 칸은 [official] 에서 가로 · 세로 [offset] 픽셀 떨어진 자리의 [logo] 크기
/// 영역이다. 합성은 `c × a + 배경 × (1 − a)`(a = alpha / 255)이고 반올림하지
/// 않는다.
_GStats _compareWithOfficialCell(
  _Raster logo,
  _Raster official, {
  required int offset,
  required List<int> background,
}) {
  if (official.width < offset + logo.width ||
      official.height < offset + logo.height) {
    fail(
      '공식 그림이 칸보다 작다: ${official.width}x${official.height} '
      '< $offset + ${logo.width}x${logo.height}',
    );
  }
  double sum = 0;
  double max = 0;
  int over16 = 0;
  for (int y = 0; y < logo.height; y++) {
    for (int x = 0; x < logo.width; x++) {
      final int il = (y * logo.width + x) * 4;
      final int io = ((y + offset) * official.width + (x + offset)) * 4;
      final double alpha = logo.rgba[il + 3] / 255;
      double pixelMax = 0;
      for (int c = 0; c < 3; c++) {
        final double composed =
            logo.rgba[il + c] * alpha + background[c] * (1 - alpha);
        final double diff = (composed - official.rgba[io + c]).abs();
        sum += diff;
        if (diff > pixelMax) {
          pixelMax = diff;
        }
      }
      if (pixelMax > max) {
        max = pixelMax;
      }
      if (pixelMax > 16) {
        over16++;
      }
    }
  }
  return (mean: sum / (logo.width * logo.height * 3), max: max, over16: over16);
}

/// git 이 추적하는 [directory] 아래 파일 경로를 저장소 루트 기준으로 모은다.
Set<String> _listTrackedFiles(String directory) {
  final ProcessResult result = Process.runSync(
    'git',
    <String>['ls-files', directory],
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (result.exitCode != 0) {
    fail('git ls-files $directory 실패 — git 이 PATH 에 없거나 저장소 밖에서 실행됐다');
  }
  return (result.stdout as String)
      .split('\n')
      .where((String path) => path.isNotEmpty)
      .toSet();
}

/// [paths] 가운데 디스크에 없는 것을 모은다.
List<String> _collectMissingFiles(List<String> paths) => <String>[
  for (final String path in paths)
    if (!File(path).existsSync()) path,
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

  group('Google G 투명 PNG', () {
    test('T-177-ASSET-04: 배율 4개 PNG 의 sha256 · 크기가 고정값과 같다', () {
      for (final ({int scale, String path, String sha256}) variant
          in _gVariants) {
        expect(
          _computeSha256OfFile(variant.path),
          variant.sha256,
          reason:
              '${variant.path} 가 바뀌었다 — 다시 만들었으면 README 와 이 값을 '
              '함께 고친다',
        );
        final ({int width, int height, int bitDepth, int colorType}) header =
            _readPngHeader(File(variant.path).readAsBytesSync(), variant.path);
        final int side = 20 * variant.scale;
        expect(
          (header.width, header.height),
          (side, side),
          reason: '${variant.path} 는 $side × $side 여야 한다',
        );
        // bit depth 8 · color type 6 = 8-bit RGBA(투명 배경).
        expect(
          (header.bitDepth, header.colorType),
          (8, 6),
          reason: '${variant.path} 는 8-bit RGBA 여야 한다',
        );
      }
    });

    test('T-177-ASSET-05: 번들이 g.png 의 해상도 변형 4개를 싣는다', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final AssetManifest manifest = await AssetManifest.loadFromAssetBundle(
        rootBundle,
      );
      final List<AssetMetadata> variants =
          manifest.getAssetVariants(_gVariants.first.path) ?? <AssetMetadata>[];
      expect(
        <String, double>{
          for (final AssetMetadata variant in variants)
            variant.key: variant.targetDevicePixelRatio ?? 1,
        },
        <String, double>{
          for (final ({int scale, String path, String sha256}) variant
              in _gVariants)
            variant.path: variant.scale.toDouble(),
        },
        reason:
            '번들의 g.png 변형이 기본 · 2.0x · 3.0x · 4.0x 가 아니다 — pubspec assets: 선언이 '
            '변형 디렉터리를 싣는지 확인한다',
      );
    });

    // 공식 버튼 그림 묶음은 저장소에 없다 — 푼 디렉터리의 경로를 dart-define 으로
    // 준 실행에서만 돈다.
    testWidgets('T-177-ASSET-06: G PNG 가 공식 버튼 그림의 G 칸과 기준 안에서 같다', (
      WidgetTester tester,
    ) async {
      final List<String> lines = <String>[];
      final List<String> failures = <String>[];
      await tester.runAsync<void>(() async {
        for (final ({int scale, String path, String sha256}) variant
            in _gVariants) {
          final int n = variant.scale;
          final int side = 20 * n;
          final _Raster logo = await _decodePngFile(variant.path);
          final StringBuffer line = StringBuffer('GOOGLE_G scale=$n px=$side');
          for (final ({String label, String theme, List<int> background}) theme
              in _gThemes) {
            final _Raster official = await _decodePngFile(
              _buildOfficialButtonPath(theme.theme, n),
            );
            // 공식 버튼은 40 × 40 이고 G 는 가운데 20 × 20 칸에 있다.
            final _GStats cell = _compareWithOfficialCell(
              logo,
              official,
              offset: 10 * n,
              background: theme.background,
            );
            // 대조군: 칸을 2N 픽셀 어긋나게 자르면 같은 통계가 크게 벌어져야 한다.
            final _GStats shifted = _compareWithOfficialCell(
              logo,
              official,
              offset: 12 * n,
              background: theme.background,
            );
            line.write(
              ' ${theme.label}_mean=${cell.mean.toStringAsFixed(2)}'
              ' ${theme.label}_max=${cell.max.floor()}'
              ' ${theme.label}_gt16=${cell.over16}',
            );
            if (cell.mean > _gMeanLimit ||
                cell.max > _gMaxLimit ||
                cell.over16 > side * side * _gOver16RatioLimit) {
              failures.add('scale=$n ${theme.label} 기준 밖: $cell');
            }
            if (shifted.mean <= _gMeanLimit) {
              failures.add('scale=$n ${theme.label} 대조군이 차이를 내지 못한다: $shifted');
            }
          }
          lines.add(line.toString());
        }
      });
      lines.forEach(debugPrint);

      expect(lines, hasLength(_gVariants.length));
      expect(failures, isEmpty);
    }, skip: _gDir.isEmpty);
  });

  group('Apple 공식 medium 로고', () {
    test('T-177-ASSET-07: 흑 · 백 SVG 가 같은 공식 path 를 변형 없이 담는다', () {
      final String black = readTrackedFile(_appleBlackMediumPath);
      final String white = readTrackedFile(_appleWhiteMediumPath);
      for (final (String path, String source) in <(String, String)>[
        (_appleBlackMediumPath, black),
        (_appleWhiteMediumPath, white),
      ]) {
        expect(
          countOccurrences(source, _appleMediumViewBox),
          1,
          reason: '$path 의 viewBox 가 medium(7 0 17 44)이 아니다',
        );
        expect(
          _extractSvgPathData(source, path),
          startsWith('$_appleMediumPathStart '),
          reason: '$path 의 path 가 medium 로고의 첫 좌표로 시작하지 않는다',
        );
        expect(
          countOccurrences(source, _appleSmallPathStart),
          0,
          reason: '$path 에 small 로고의 path 가 남아 있다',
        );
      }

      final String blackData = _extractSvgPathData(
        black,
        _appleBlackMediumPath,
      );
      expect(
        _extractSvgPathData(white, _appleWhiteMediumPath),
        blackData,
        reason: '흑 · 백 파일의 path 가 다르다',
      );
      expect(
        sha256.convert(utf8.encode(blackData)).toString(),
        _appleMediumPathSha256,
        reason: 'path 가 바뀌었다 — 공식 path 는 좌표를 손대지 않고 그대로 쓴다',
      );

      final RegExp pathFill = RegExp(r'<path\s+fill="(#[0-9A-Fa-f]{6})"');
      expect(pathFill.firstMatch(black)?.group(1), '#000000');
      expect(pathFill.firstMatch(white)?.group(1), '#FFFFFF');
    });

    testWidgets('T-177-ASSET-08: flutter_svg 가 medium 로고를 그린다', (
      WidgetTester tester,
    ) async {
      final GlobalKey boundaryKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              // 버튼 높이 48 에 맞춘 크기 — 파일 높이 44 를 48 로 늘린다.
              child: SvgPicture.asset(
                _appleBlackMediumPath,
                width: 17 * 48 / 44,
                height: 48,
              ),
            ),
          ),
        ),
      );

      // SVG 는 비동기로 올라온다 — 그려질 때까지 실제 시간으로 잠깐씩 기다린다.
      int opaque = 0;
      for (int attempt = 0; attempt < 20 && opaque == 0; attempt++) {
        await tester.runAsync<void>(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
        opaque = _countOpaquePixels(
          await _captureBoundary(tester, boundaryKey, _appleBlackMediumPath),
        );
      }

      expect(tester.takeException(), isNull);
      expect(
        opaque,
        greaterThan(0),
        reason: '$_appleBlackMediumPath 를 그렸는데 불투명한 픽셀이 없다',
      );
    });
  });

  group('자산 디렉터리', () {
    // 앱 코드가 이름으로 부르는 파일과 그 문서가 있는지만 본다. 변형을 더한
    // 트리에서도 통과한다.
    test('T-177-ASSET-10: Google · Apple 로고 파일과 문서가 있다', () {
      expect(
        _collectMissingFiles(_googleAssetFiles),
        isEmpty,
        reason: '$_googleAssetDir 에 있어야 하는 파일이 없다',
      );
      expect(
        _collectMissingFiles(_appleAssetFiles),
        isEmpty,
        reason: '$_appleAssetDir 에 있어야 하는 파일이 없다',
      );
    });

    // 킷 저장소 자체의 정리 상태 — 쓰지 않는 파일이 남아 있지 않은지 본다.
    test('T-177-ASSET-12: Google · Apple 자산 디렉터리의 추적 파일이 목록과 같다', () {
      final Set<String> google = _listTrackedFiles(_googleAssetDir);
      final Set<String> apple = _listTrackedFiles(_appleAssetDir);
      // 양성 대조: 목록이 비면 아래 집합 비교가 뜻을 잃는다.
      expect(google, isNotEmpty);
      expect(apple, isNotEmpty);

      expect(
        google,
        _googleAssetFiles.toSet(),
        reason: '$_googleAssetDir 의 추적 파일이 로고 4장 + 문서 2개가 아니다',
      );
      expect(
        apple,
        _appleAssetFiles.toSet(),
        reason: '$_appleAssetDir 의 추적 파일이 로고 2장 + 문서 1개가 아니다',
      );
    }, skip: skipUnlessPlanningDocsExist(_maintainerOnlyDocs));
  });
}
