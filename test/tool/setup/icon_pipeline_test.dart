// 위저드 앱 아이콘 파이프라인(`tool/setup/icons/icon_pipeline.dart`)을 코드로
// 그린 그림과 손으로 짠 PNG 바이트로 고정한다.
//
// sips 를 부르지 않고 파일을 쓰지 않는다 — 입력 그림 · 바이트는 모두 시험이 메모리에서
// 만든다. 판정 불리언(투명 픽셀 셈 · PNG 머리 알파)은 참 · 거짓 두 방향을 따로 본다.
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:test/test.dart';

import '../../../tool/setup/icons/icon_pipeline.dart';

/// PNG 시그니처 8바이트.
const List<int> pngSignature = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
];

/// 4×4 체커(0 · 255)를 2×2 로 구간 평균한 칸 값.
///
/// 칸마다 0 둘 · 255 둘의 평균 127.5 를 8비트에 담으며 버린 값이다. 가장 가까운
/// 이웃으로 줄이면 칸 값은 0 또는 255 가 된다.
const int checkerAverage = 127;

/// 후보 dp 넷 × adaptive 캔버스 다섯(108 · 162 · 216 · 324 · 432)의 로고 한 변.
const List<({num dp, List<int> sides})> expectedLogoSides =
    <({num dp, List<int> sides})>[
      (dp: 73.44, sides: <int>[73, 110, 147, 220, 294]),
      (dp: 72, sides: <int>[72, 108, 144, 216, 288]),
      (dp: 66, sides: <int>[66, 99, 132, 198, 264]),
      (dp: 48, sides: <int>[48, 72, 96, 144, 192]),
    ];

/// adaptive 캔버스 다섯 밀도의 한 변(px).
const List<int> canvasSides = <int>[108, 162, 216, 324, 432];

/// [type] 청크 바이트를 만든다 — 길이 · 이름 · 내용 · CRC.
///
/// CRC 는 0 으로 둔다. 머리 판정(`readPngHeader` · `readPngHasAlpha`)은 청크
/// 길이와 이름만 읽고 CRC 를 보지 않으므로 이 바이트로 판정을 고정할 수 있다.
List<int> buildChunk(String type, List<int> data) {
  final int length = data.length;
  return <int>[
    (length >> 24) & 0xFF,
    (length >> 16) & 0xFF,
    (length >> 8) & 0xFF,
    length & 0xFF,
    ...type.codeUnits,
    ...data,
    0,
    0,
    0,
    0,
  ];
}

/// color type [colorType] 의 4×4 · 8비트 PNG 머리 바이트를 짠다.
///
/// [transparencyBeforeData] 가 true 면 `IDAT` 앞에 `tRNS` 청크를 둔다. false 면
/// `tRNS` 를 `IDAT` 뒤에 둔다 — 판정이 `IDAT` 뒤 청크를 읽지 않는지도 함께 본다.
Uint8List buildPngHeaderBytes(
  int colorType, {
  bool transparencyBeforeData = false,
}) {
  final transparency = buildChunk('tRNS', <int>[0, 0, 0, 0, 0, 0]);
  return Uint8List.fromList(<int>[
    ...pngSignature,
    ...buildChunk('IHDR', <int>[0, 0, 0, 4, 0, 0, 0, 4, 8, colorType, 0, 0, 0]),
    ...buildChunk('sRGB', <int>[0]),
    if (transparencyBeforeData) ...transparency,
    ...buildChunk('IDAT', <int>[1, 2, 3]),
    if (!transparencyBeforeData) ...transparency,
    ...buildChunk('IEND', <int>[]),
  ]);
}

/// [png] 의 IHDR 청크 바로 뒤에 `tRNS` 청크를 끼워 넣는다(CRC 0 — [buildChunk]).
Uint8List insertTransparencyChunk(Uint8List png) {
  const ihdrEnd = 33;
  return Uint8List.fromList(<int>[
    ...png.sublist(0, ihdrEnd),
    ...buildChunk('tRNS', <int>[0, 0, 0, 0, 0, 0]),
    ...png.sublist(ihdrEnd),
  ]);
}

/// 한 변 [side] 의 불투명 RGBA 그림(모든 알파 255).
img.Image buildOpaqueRgba(int side) =>
    img.Image(width: side, height: side, numChannels: 4)
      ..clear(img.ColorRgba8(10, 20, 30, 255));

/// 한 변 [side] 의 RGB 그림(알파 채널 없음).
img.Image buildRgb(int side) =>
    img.Image(width: side, height: side)..clear(img.ColorRgb8(10, 20, 30));

/// 체커 RGBA 그림 — (x + y) 가 짝수면 불투명 흰색 · 홀수면 투명 검정.
img.Image buildWhiteTransparentChecker(int side) {
  final image = img.Image(width: side, height: side, numChannels: 4);
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      if ((x + y).isEven) {
        image.setPixelRgba(x, y, 255, 255, 255, 255);
      } else {
        image.setPixelRgba(x, y, 0, 0, 0, 0);
      }
    }
  }
  return image;
}

/// 왼쪽 한 열만 투명 검정이고 나머지는 불투명 흰색인 RGBA 그림.
img.Image buildLeftColumnTransparent(int side) {
  final image = img.Image(width: side, height: side, numChannels: 4)
    ..clear(img.ColorRgba8(255, 255, 255, 255));
  for (var y = 0; y < side; y++) {
    image.setPixelRgba(0, y, 0, 0, 0, 0);
  }
  return image;
}

/// [image] 의 모든 픽셀 RGB 채널 가운데 가장 작은 값.
int findMinChannel(img.Image image) {
  var minimum = 255;
  for (final pixel in image) {
    for (final channel in <num>[pixel.r, pixel.g, pixel.b]) {
      minimum = min(minimum, channel.toInt());
    }
  }
  return minimum;
}

/// 같은 크기 두 그림의 RGB 채널 차 최댓값.
int findMaxChannelDiff(img.Image a, img.Image b) {
  var worst = 0;
  final Iterator<img.Pixel> other = b.iterator;
  for (final pixel in a) {
    other.moveNext();
    final img.Pixel q = other.current;
    worst = max(worst, (pixel.r - q.r).abs().toInt());
    worst = max(worst, (pixel.g - q.g).abs().toInt());
    worst = max(worst, (pixel.b - q.b).abs().toInt());
  }
  return worst;
}

/// 가장자리가 반투명한 원(반지름 [radius]) · 픽셀마다 다른 색 · 한 변 [side].
img.Image buildSoftCircle(int side, double radius) {
  final image = img.Image(width: side, height: side, numChannels: 4);
  final double center = side / 2 + 0.3;
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      final double dx = x + 0.5 - center;
      final double dy = y + 0.5 - center;
      final double coverage = (radius - sqrt(dx * dx + dy * dy) + 0.5).clamp(
        0.0,
        1.0,
      );
      final int alpha = (coverage * 255).round();
      if (alpha == 0) {
        image.setPixelRgba(x, y, 0, 0, 0, 0);
      } else {
        image.setPixelRgba(
          x,
          y,
          (x * 7) & 0xFF,
          (y * 5) & 0xFF,
          ((x + y) * 3) & 0xFF,
          alpha,
        );
      }
    }
  }
  return image;
}

/// 색 · 알파가 모두 무작위인 한 변 [side] 의 RGBA 그림(씨앗 고정).
img.Image buildNoise(int side) {
  final random = Random(28);
  final image = img.Image(width: side, height: side, numChannels: 4);
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      image.setPixelRgba(
        x,
        y,
        random.nextInt(256),
        random.nextInt(256),
        random.nextInt(256),
        random.nextInt(256),
      );
    }
  }
  return image;
}

void main() {
  test('T-28-PIPE-01: 알파 채널 없는 RGB · 모든 알파 255 인 RGBA 는 투명 픽셀 0', () {
    expect(countTransparentPixels(buildRgb(8)), 0);
    expect(countTransparentPixels(buildOpaqueRgba(8)), 0);
  });

  test('T-28-PIPE-02: 알파 254 한 픽셀 · 알파 0 한 픽셀은 각각 투명 픽셀 1', () {
    final img.Image almostOpaque = buildOpaqueRgba(8)
      ..setPixelRgba(3, 4, 10, 20, 30, 254);
    final img.Image oneHole = buildOpaqueRgba(8)
      ..setPixelRgba(5, 1, 10, 20, 30, 0);

    expect(countTransparentPixels(almostOpaque), 1);
    expect(countTransparentPixels(oneHole), 1);
  });

  test('T-28-PIPE-03: 4×4 체커를 2×2 로 줄이면 칸마다 구간 평균 값이다', () {
    final checker = img.Image(width: 4, height: 4);
    for (var y = 0; y < 4; y++) {
      for (var x = 0; x < 4; x++) {
        final value = (x + y).isEven ? 0 : 255;
        checker.setPixelRgb(x, y, value, value, value);
      }
    }

    final img.Image resized = resizeOpaque(checker, 2);

    expect(resized.width, 2);
    expect(resized.height, 2);
    for (final pixel in resized) {
      expect(
        <num>[pixel.r, pixel.g, pixel.b],
        <num>[checkerAverage, checkerAverage, checkerAverage],
      );
    }
  });

  test('T-28-PIPE-04: 투명 검정 · 불투명 흰색이 섞인 구간을 줄여 흰 배경에 놓으면 흰색이다', () {
    for (final source in <img.Image>[
      buildWhiteTransparentChecker(4),
      buildLeftColumnTransparent(4),
    ]) {
      final img.Image resized = resizeKeepingAlpha(source, 2);
      expect(resized.numChannels, 4);

      final img.Image flattened = flattenOnto(resized, 0xFFFFFF);

      expect(findMinChannel(flattened), greaterThanOrEqualTo(254));
    }
  });

  test('T-28-PIPE-05: 투명 원본의 채운 그림 120px PNG 는 color type 2 · 알파 없음', () {
    final img.Image filled = buildFilledIcon(
      buildSoftCircle(256, 100),
      backgroundRgb: 0xFFFFFF,
    );

    final Uint8List bytes = encodeSquareIcon(filled, 120);
    final PngHeader? header = readPngHeader(bytes);

    expect(header, (width: 120, height: 120, bitDepth: 8, colorType: 2));
    expect(readPngHasAlpha(bytes), isFalse);
  });

  test('T-28-PIPE-06: color type 6 · 4 · (2 + tRNS) 머리는 알파 있음', () {
    expect(readPngHasAlpha(buildPngHeaderBytes(6)), isTrue);
    expect(readPngHasAlpha(buildPngHeaderBytes(4)), isTrue);
    expect(
      readPngHasAlpha(buildPngHeaderBytes(2, transparencyBeforeData: true)),
      isTrue,
    );
    expect(readPngHasAlpha(img.encodePng(buildOpaqueRgba(8))), isTrue);
    expect(
      readPngHasAlpha(insertTransparencyChunk(img.encodePng(buildRgb(8)))),
      isTrue,
    );
  });

  test('T-28-PIPE-07: color type 2 · 0(tRNS 없음)은 알파 없음 · 못 읽는 머리는 null', () {
    expect(readPngHasAlpha(buildPngHeaderBytes(2)), isFalse);
    expect(readPngHasAlpha(buildPngHeaderBytes(0)), isFalse);
    expect(readPngHasAlpha(img.encodePng(buildRgb(8))), isFalse);
    expect(
      readPngHasAlpha(Uint8List.fromList(List<int>.filled(40, 7))),
      isNull,
    );
    expect(
      readPngHasAlpha(
        Uint8List.fromList(buildPngHeaderBytes(2).sublist(0, 30)),
      ),
      isNull,
    );
  });

  test('T-28-PIPE-08: 2048 투명 원본의 채운 그림은 원본 크기 합성 뒤 축소와 채널 차 1 이하', () {
    for (final source in <img.Image>[
      buildSoftCircle(2048, 900),
      buildNoise(2048),
    ]) {
      for (final backgroundRgb in <int>[0xFFFFFF, 0x1B4D6B]) {
        final img.Image filled = buildFilledIcon(
          source,
          backgroundRgb: backgroundRgb,
        );
        final img.Image reference = resizeOpaque(
          flattenOnto(source, backgroundRgb),
          filledIconSide,
        );

        expect(filled.width, filledIconSide);
        expect(filled.height, filledIconSide);
        expect(filled.numChannels, 3);
        expect(findMaxChannelDiff(filled, reference), lessThanOrEqualTo(1));
      }
    }
  });

  test('T-28-PIPE-09: 짧거나 · 시그니처가 다르거나 · 잘린 바이트는 예외 없이 null', () {
    final Uint8List small = img.encodePng(buildOpaqueRgba(8));
    final Uint8List large = img.encodePng(buildNoise(64));
    final badSignature = Uint8List.fromList(small.sublist(0, 40))..[1] = 0x51;
    final cases = <String, Uint8List>{
      '0 바이트': Uint8List(0),
      '7 바이트': Uint8List.fromList(small.sublist(0, 7)),
      '8 바이트': Uint8List.fromList(small.sublist(0, 8)),
      '32 바이트': Uint8List.fromList(small.sublist(0, 32)),
      '시그니처 다른 40 바이트': badSignature,
      '작은 PNG 앞 절반': Uint8List.fromList(small.sublist(0, small.length ~/ 2)),
      '큰 PNG 앞 절반': Uint8List.fromList(large.sublist(0, large.length ~/ 2)),
    };

    for (final MapEntry<String, Uint8List> entry in cases.entries) {
      expect(decodeIconPng(entry.value), isNull, reason: entry.key);
    }
  });

  test('T-28-PIPE-10: adaptive 로고 한 변 표 · 전경 여백 경계의 알파 · color type 6', () {
    final layer = img.Image(width: 1024, height: 1024)
      ..clear(img.ColorRgb8(200, 100, 50));

    for (final (:num dp, :List<int> sides) in expectedLogoSides) {
      for (var i = 0; i < canvasSides.length; i++) {
        final int canvasSide = canvasSides[i];
        final int logoSide = adaptiveLogoSide(canvasSide, dp);
        expect(logoSide, sides[i], reason: '$dp/$canvasSide');

        final Uint8List png = encodeAdaptiveForeground(
          layer,
          canvasSide: canvasSide,
          logoDp: dp,
        );
        final img.Image decoded = img.decodePng(png)!;
        final int margin = (canvasSide - logoSide) ~/ 2;
        final int middle = canvasSide ~/ 2;

        expect(decoded.width, canvasSide);
        expect(decoded.getPixel(margin, middle).a, 255);
        expect(decoded.getPixel(margin - 1, middle).a, 0);
        expect(readPngHeader(png)?.colorType, 6);
      }
    }
  });

  test('T-28-PIPE-11: 가장자리 평균색 · #RRGGBB 표기', () {
    final edge = img.Image(width: 10, height: 10)
      ..clear(img.ColorRgb8(0, 0, 255));
    for (var i = 0; i < 10; i++) {
      edge
        ..setPixelRgb(i, 0, 255, 0, 0)
        ..setPixelRgb(i, 9, 255, 0, 0)
        ..setPixelRgb(0, i, 255, 0, 0)
        ..setPixelRgb(9, i, 255, 0, 0);
    }

    expect(averageEdgeRgb(edge), 0xFF0000);
    expect(formatHexRgb(0x1a2b3c), '#1A2B3C');
  });
}
