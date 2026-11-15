// 위저드 「앱 아이콘」 단계의 그림 계산 — 알파 판정 · 합성 · 축소 · PNG 인코딩 ·
// adaptive 전경.
//
// 원본은 sips 가 sRGB PNG 로 바꾼 파일을 받는다. 픽셀 계산은 모두 이 파일의
// 순수 함수가 하고, 바깥 도구를 부르지 않는다. 읽을 수 없는 바이트는 예외 대신
// null 로 돌려준다 — 단계가 까닭 한 줄을 보이고 다시 묻는다.
//
// 크기를 줄일 때는 늘 구간 평균을 쓴다. 알파를 남기는 축소만 RGB 에 알파를 곱해
// 평균한 뒤 알파로 나눈다 — 투명 픽셀의 숨은 색이 반투명 가장자리에 섞이지 않게
// 한다. 채운 그림은 원본을 한 변 [filledIconSide] 로 먼저 줄인 뒤 배경색 위에
// 합성한다 — 큰 원본에서 합성 사본을 원본 크기로 만들지 않는다.
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 채운 그림의 한 변(px) — iOS 1024 아이콘 크기이고, 합성 전에 줄이는 크기다.
const int filledIconSide = 1024;

/// PNG 머리(IHDR)에서 읽은 값 — 너비 · 높이 · 비트 깊이 · color type.
typedef PngHeader = ({int width, int height, int bitDepth, int colorType});

/// PNG 시그니처 8바이트.
const List<int> _pngSignature = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
];

/// 시그니처(8) + 청크 길이(4) + 청크 이름(4) + IHDR 내용(13) + CRC(4).
const int _ihdrEnd = 33;

/// IHDR 내용의 길이.
const int _ihdrLength = 13;

/// [bytes] 의 PNG 머리를 읽는다.
///
/// 시그니처가 다르거나 · 첫 청크가 길이 13 의 `IHDR` 가 아니거나 · IHDR
/// 청크(CRC 포함)를 다 담지 못할 만큼 짧거나 · 너비나 높이가 0 이면 null 이다.
/// 예외를 던지지 않는다.
PngHeader? readPngHeader(Uint8List bytes) {
  if (bytes.length < _ihdrEnd) return null;
  for (var i = 0; i < _pngSignature.length; i++) {
    if (bytes[i] != _pngSignature[i]) return null;
  }
  if (_readUint32(bytes, 8) != _ihdrLength) return null;
  if (_readChunkType(bytes, 12) != 'IHDR') return null;
  final int width = _readUint32(bytes, 16);
  final int height = _readUint32(bytes, 20);
  if (width == 0 || height == 0) return null;
  return (
    width: width,
    height: height,
    bitDepth: bytes[24],
    colorType: bytes[25],
  );
}

/// [bytes] 의 PNG 에 알파가 있는지 머리만 보고 판정한다(`sips -g hasAlpha` 와
/// 같은 뜻).
///
/// 머리를 못 읽으면 null, color type 4 · 6 이면 true, 그 밖은 `IDAT` 앞에
/// `tRNS` 청크가 있으면 true, 아니면 false 다.
bool? readPngHasAlpha(Uint8List bytes) {
  final PngHeader? header = readPngHeader(bytes);
  if (header == null) return null;
  if (header.colorType == 4 || header.colorType == 6) return true;
  var offset = _ihdrEnd;
  while (offset + 8 <= bytes.length) {
    final String type = _readChunkType(bytes, offset + 4);
    if (type == 'tRNS') return true;
    if (type == 'IDAT' || type == 'IEND') return false;
    offset += 12 + _readUint32(bytes, offset);
  }
  return false;
}

/// [bytes] 를 PNG 로 디코드한다 — 읽을 수 없으면 null.
///
/// 머리부터 확인한다. 짧은 바이트를 디코더에 그대로 주면 잡을 수 없는 오류가
/// 나기 때문이다. 디코더가 null 을 돌려주거나 예외를 던져도 null 이다.
img.Image? decodeIconPng(Uint8List bytes) {
  if (readPngHeader(bytes) == null) return null;
  try {
    return img.decodePng(bytes);
  } on Exception {
    return null;
  }
}

/// [source] 를 8비트 · 팔레트 없음 · RGB 또는 RGBA 그림으로 맞춘다.
///
/// 이미 그 꼴이면 그대로 돌려준다.
img.Image normalizeIcon(img.Image source) {
  if (source.hasPalette ||
      source.format != img.Format.uint8 ||
      source.numChannels < 3) {
    return source.convert(
      format: img.Format.uint8,
      numChannels: source.hasAlpha ? 4 : 3,
    );
  }
  return source;
}

/// [image] 에서 투명 · 반투명 픽셀(알파가 최댓값보다 작은 픽셀) 수를 센다.
///
/// 알파 채널이 없으면 0 이다. 알파 채널이 있어도 모든 픽셀이 불투명하면 0 이라,
/// 채널 유무가 아니라 이 값으로 투명한 원본인지 가른다.
int countTransparentPixels(img.Image image) {
  if (!image.hasAlpha) return 0;
  final num maxValue = image.maxChannelValue;
  var count = 0;
  for (final pixel in image) {
    if (pixel.a < maxValue) count++;
  }
  return count;
}

/// 불투명하게 쓸 [image] 를 한 변 [side] 로 줄인다(구간 평균).
///
/// 한 변이 이미 [side] 면 그대로 돌려준다.
img.Image resizeOpaque(img.Image image, int side) {
  if (image.width == side && image.height == side) return image;
  return img.copyResize(
    image,
    width: side,
    height: side,
    interpolation: img.Interpolation.average,
  );
}

/// 알파를 남길 [image] 를 한 변 [side] 의 4채널 그림으로 줄인다.
///
/// 픽셀마다 RGB 에 알파를 곱해 구간 평균을 내고 평균 알파로 나눈다 — 투명
/// 픽셀의 숨은 색이 가장자리를 어둡게 하지 않는다. 평균 알파가 0 인 픽셀은
/// RGB 도 0 이다. 구간은 [img.copyResize] 의 구간 평균과 같고, 원본 크기의 곱한
/// 사본을 따로 만들지 않아 큰 원본에서도 메모리를 더 쓰지 않는다. 한 변이 이미
/// [side] 면 그대로 돌려준다. [image] 는 [normalizeIcon] 을 거친 8비트 그림이다.
img.Image resizeKeepingAlpha(img.Image image, int side) {
  if (image.width == side && image.height == side) return image;
  final out = img.Image(width: side, height: side, numChannels: 4);
  _averagePremultiplied(image, side, (int x, int y, _Average average) {
    if (average.alpha <= 0) {
      out.setPixelRgba(x, y, 0, 0, 0, 0);
      return;
    }
    out.setPixelRgba(
      x,
      y,
      (average.red / average.alpha).round(),
      (average.green / average.alpha).round(),
      (average.blue / average.alpha).round(),
      (average.alpha * 255).round(),
    );
  });
  return out;
}

/// [image] 를 배경색 [backgroundRgb](`0xRRGGBB`) 위에 합성한 3채널 그림을 만든다.
///
/// 픽셀마다 `원본 × a + 배경 × (1 − a)` 를 반올림한다. 알파 채널이 없으면
/// 픽셀 값은 원본 그대로다. 새 그림이라 원본의 색 프로파일 · 글 청크가 실리지
/// 않는다.
img.Image flattenOnto(img.Image image, int backgroundRgb) {
  final int red = (backgroundRgb >> 16) & 0xFF;
  final int green = (backgroundRgb >> 8) & 0xFF;
  final int blue = backgroundRgb & 0xFF;
  final bool hasAlpha = image.hasAlpha;
  final num maxValue = image.maxChannelValue;
  final out = img.Image(width: image.width, height: image.height);
  final Iterator<img.Pixel> target = out.iterator;
  for (final pixel in image) {
    target.moveNext();
    final double alpha = hasAlpha ? pixel.a / maxValue : 1.0;
    target.current
      ..r = (pixel.r * alpha + red * (1 - alpha)).round()
      ..g = (pixel.g * alpha + green * (1 - alpha)).round()
      ..b = (pixel.b * alpha + blue * (1 - alpha)).round();
  }
  return out;
}

/// 모든 홈 화면 · 콘솔 아이콘의 원본이 되는 채운 그림(3채널 · 한 변
/// [filledIconSide])을 만든다.
///
/// [normalized] 에 투명 · 반투명 픽셀이 있으면 [resizeKeepingAlpha] 와 같은
/// 구간 평균으로 줄이면서 배경색 [backgroundRgb] 위에 합성하고, 없으면 줄인 뒤
/// 알파만 없앤다.
///
/// 투명한 원본은 줄인 평균을 8비트로 담지 않고 바로 합성해 한 번만
/// 반올림한다 — 원본 크기에서 합성한 뒤 줄인 그림과 채널마다 1 이하로 같다.
img.Image buildFilledIcon(img.Image normalized, {required int backgroundRgb}) {
  if (countTransparentPixels(normalized) == 0) {
    return flattenOnto(resizeOpaque(normalized, filledIconSide), backgroundRgb);
  }
  final int red = (backgroundRgb >> 16) & 0xFF;
  final int green = (backgroundRgb >> 8) & 0xFF;
  final int blue = backgroundRgb & 0xFF;
  final out = img.Image(width: filledIconSide, height: filledIconSide);
  _averagePremultiplied(normalized, filledIconSide, (
    int x,
    int y,
    _Average average,
  ) {
    final double rest = 1 - average.alpha;
    out.setPixelRgb(
      x,
      y,
      (average.red + red * rest).round(),
      (average.green + green * rest).round(),
      (average.blue + blue * rest).round(),
    );
  });
  return out;
}

/// 투명한 원본 [normalized] 에서 adaptive 전경의 재료(알파 유지 · 한 변
/// [filledIconSide])를 만든다.
img.Image buildLogoLayer(img.Image normalized) =>
    resizeKeepingAlpha(normalized, filledIconSide);

/// 채운 그림 [filled] 를 한 변 [side] 의 PNG 바이트로 만든다.
///
/// 3채널 그림이라 PNG color type 은 2(알파 없음)다.
Uint8List encodeSquareIcon(img.Image filled, int side) =>
    img.encodePng(resizeOpaque(filled, side));

/// adaptive 전경 캔버스 한 변 [canvasSide](px)에서 로고 한 변(px)을 구한다.
///
/// 캔버스는 108dp 이고 로고는 [logoDp] 다 — `canvasSide × logoDp ÷ 108` 반올림.
int adaptiveLogoSide(int canvasSide, num logoDp) =>
    (canvasSide * logoDp / 108).round();

/// [layer] 를 adaptive 전경 PNG(투명 4채널 · 한 변 [canvasSide])로 만든다.
///
/// [layer] 를 [adaptiveLogoSide] 크기로 줄여(알파 채널이 있으면 알파를 남기며)
/// 캔버스 가운데에 그대로 놓는다 — 여백은 PNG 에 구워 넣는다. 결과 PNG 의
/// color type 은 6 이다.
Uint8List encodeAdaptiveForeground(
  img.Image layer, {
  required int canvasSide,
  required num logoDp,
}) {
  final int logoSide = adaptiveLogoSide(canvasSide, logoDp);
  final img.Image logo = layer.hasAlpha
      ? resizeKeepingAlpha(layer, logoSide)
      : resizeOpaque(layer, logoSide);
  final canvas = img.Image(
    width: canvasSide,
    height: canvasSide,
    numChannels: 4,
  );
  final int offset = (canvasSide - logoSide) ~/ 2;
  img.compositeImage(
    canvas,
    logo,
    dstX: offset,
    dstY: offset,
    blend: img.BlendMode.direct,
  );
  return img.encodePng(canvas);
}

/// 채운 그림 [filled] 의 가장자리 1px 고리 색 평균을 `0xRRGGBB` 로 구한다.
///
/// 채널마다 평균을 반올림한다.
int averageEdgeRgb(img.Image filled) {
  final int width = filled.width;
  final int height = filled.height;
  var red = 0;
  var green = 0;
  var blue = 0;
  var count = 0;
  void add(int x, int y) {
    final img.Pixel pixel = filled.getPixel(x, y);
    red += pixel.r.toInt();
    green += pixel.g.toInt();
    blue += pixel.b.toInt();
    count++;
  }

  for (var x = 0; x < width; x++) {
    add(x, 0);
    if (height > 1) add(x, height - 1);
  }
  for (var y = 1; y < height - 1; y++) {
    add(0, y);
    if (width > 1) add(width - 1, y);
  }
  if (count == 0) return 0;
  return ((red / count).round() << 16) |
      ((green / count).round() << 8) |
      (blue / count).round();
}

/// [rgb](`0xRRGGBB`)를 `#RRGGBB`(대문자)로 쓴다.
String formatHexRgb(int rgb) =>
    '#${(rgb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// 구간 하나의 평균 — 알파를 곱한 RGB 와 알파(0 ~ 1).
typedef _Average = ({double red, double green, double blue, double alpha});

/// [image] 를 한 변 [side] 의 구간으로 나눠 구간마다 알파를 곱한 RGB 평균과
/// 알파 평균을 [emit] 에 넘긴다.
///
/// 구간 경계는 [img.copyResize] 의 구간 평균과 같다.
void _averagePremultiplied(
  img.Image image,
  int side,
  void Function(int x, int y, _Average average) emit,
) {
  final bool hasAlpha = image.hasAlpha;
  final num maxValue = image.maxChannelValue;
  final double stepX = image.width / side;
  final double stepY = image.height / side;
  img.Pixel? pixel;
  for (var y = 0; y < side; y++) {
    final int top = (y * stepY).toInt();
    var bottom = ((y + 1) * stepY).toInt();
    if (bottom == top) bottom++;
    for (var x = 0; x < side; x++) {
      final int left = (x * stepX).toInt();
      var right = ((x + 1) * stepX).toInt();
      if (right == left) right++;
      var red = 0.0;
      var green = 0.0;
      var blue = 0.0;
      var alpha = 0.0;
      for (var sy = top; sy < bottom; sy++) {
        for (var sx = left; sx < right; sx++) {
          pixel = image.getPixel(sx, sy, pixel);
          final double a = hasAlpha ? pixel.a / maxValue : 1.0;
          red += pixel.r * a;
          green += pixel.g * a;
          blue += pixel.b * a;
          alpha += a;
        }
      }
      final int count = (bottom - top) * (right - left);
      emit(x, y, (
        red: red / count,
        green: green / count,
        blue: blue / count,
        alpha: alpha / count,
      ));
    }
  }
}

/// [bytes] 의 [offset] 에서 빅엔디언 32비트 부호 없는 정수를 읽는다.
int _readUint32(Uint8List bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

/// [bytes] 의 [offset] 에서 4바이트 청크 이름을 읽는다.
String _readChunkType(Uint8List bytes, int offset) =>
    String.fromCharCodes(bytes, offset, offset + 4);
