// `flutter_native_splash.yaml` 과 스플래시 상수의 대조.
//
// **목적:** Flutter 스플래시(`SplashFrame`) 배경 · 로고가 네이티브 스플래시와
// 같도록 `flutter_native_splash.yaml` 의 색 · 그림 경로와
// `lib/features/splash/presentation/splash_body.dart` 상수가 같은지 본다. yaml
// 만 바꾸고 상수를 잊으면 화면에서는 늦게 드러나는 조용한 어긋남이 되므로, 키
// 이름 · 두 값 · 붙여 넣을 Dart 선언을 담은 메시지로 실패한다.
//
// **YAML 을 파서 없이 줄 단위로 읽는다** — YAML 파서 패키지는 이 앱의 직접
// 의존이 아니라 import 하면 `depend_on_referenced_packages` 진단이 난다.
//
// **주석을 먼저 걷어낸다** — 앞 공백을 걷어낸 줄이 `#` 로 시작하면 버린다. 설명
// 주석이 키 이름을 말해도 값으로 읽지 않는다.
//
// **`android_12` 의 색 · 플랫폼별 색 · 로고 키는 없거나 짝 키와 같아야 한다** —
// 생성기는 없으면 짝 키 값을 쓰고, Flutter 스플래시는 Android 버전 · 플랫폼을
// 구분하지 않는다.
//
// **`android_12` 의 그림 키는 있어야 하고 `image` · `image_dark` 와 같아야 한다** —
// 생성기는 이 두 값이 없을 때 짝 키로 되돌아가지 않는다(없으면 런처 아이콘 ·
// `image_dark` 가 없으면 `android_12.image`).
//
// **배경 그림 키는 쓰지 않는다** — Flutter 스플래시는 단색 배경만 그린다.
//
// **색 상수는 불투명이어야 한다** — yaml 색에는 알파가 없다.
//
// 사용자 안내: `docs/guide.md` 「스플래시 바꾸기」.
//
// 시험 ID: T-26-YAML-01(저장소 yaml ↔ 상수) · 02(색 상수 어긋남 양방향 · 알파) ·
// 03(`android_12` 색) · 04(값 없음) · 05(플랫폼별 색 키) · 06(플랫폼별 로고 키) ·
// 07(배경 그림 키) · 08(로고 경로 상수) · 09(주석 줄) · 10(`android_12` 그림).

import 'package:flutter/painting.dart';
import 'package:flutter_starter_kit/features/splash/presentation/splash_body.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_text.dart';

const String _yamlPath = 'flutter_native_splash.yaml';

/// [readSplashYaml] 의 결과 — 블록을 찾았는지와 키 → 원값 맵 두 개.
///
/// - `hasBlock`: 들여쓰기 0 의 `flutter_native_splash:` 줄이 있다.
/// - `hasAndroid12`: 그 블록 안에 들여쓰기 2 의 `android_12:` 줄이 있다.
/// - `top`: 블록 안 들여쓰기 2 키 → 원값(따옴표 포함 · 주석 제외).
/// - `android12`: `android_12:` 블록 안 들여쓰기 4 키 → 원값.
typedef SplashYamlBlocks = ({
  bool hasBlock,
  bool hasAndroid12,
  Map<String, String> top,
  Map<String, String> android12,
});

/// [yaml] 의 `flutter_native_splash:` 블록을 줄 단위로 읽는다.
///
/// 앞 공백을 걷어낸 줄이 `#` 로 시작하면 버린다(블록을 끝내지도 않는다). 값이
/// 따옴표로 시작하면 짝 따옴표까지, 아니면 첫 「공백 + `#`」 앞까지를 값으로 본다
/// — 값이 `#` 로 시작하면 YAML 주석이라 빈 값이다.
SplashYamlBlocks readSplashYaml(String yaml) {
  final top = <String, String>{};
  final android12 = <String, String>{};
  final List<String> lines = yaml.split('\n');
  final int start = lines.indexWhere(
    (String line) => line.trimRight() == 'flutter_native_splash:',
  );
  if (start == -1) {
    return (
      hasBlock: false,
      hasAndroid12: false,
      top: top,
      android12: android12,
    );
  }

  var hasAndroid12 = false;
  var inAndroid12 = false;
  for (var i = start + 1; i < lines.length; i++) {
    final String line = lines[i];
    final String trimmed = line.trimLeft();
    // 빈 줄 · 주석 줄은 들여쓰기와 무관하게 버린다 — 블록을 끝내지 않는다.
    if (trimmed.isEmpty || trimmed.startsWith('#')) {
      continue;
    }
    final int indent = line.length - trimmed.length;
    if (indent == 0) {
      break;
    }
    final int colon = trimmed.indexOf(':');
    if (colon == -1) {
      continue;
    }
    final String key = trimmed.substring(0, colon).trim();
    final String value = _readYamlValue(trimmed.substring(colon + 1));
    if (indent == 2) {
      inAndroid12 = key == 'android_12' && value.isEmpty;
      if (inAndroid12) {
        hasAndroid12 = true;
      } else {
        top[key] = value;
      }
    } else if (indent == 4 && inAndroid12) {
      android12[key] = value;
    }
  }
  return (
    hasBlock: true,
    hasAndroid12: hasAndroid12,
    top: top,
    android12: android12,
  );
}

/// 키 뒤 [rest] 에서 값을 꺼낸다 — 따옴표 값은 짝 따옴표까지(따옴표 포함),
/// 아니면 첫 「공백 + `#`」 앞까지. `#` 로 시작하면 YAML 주석이라 빈 값이다.
String _readYamlValue(String rest) {
  final String value = rest.trim();
  if (value.startsWith('"') || value.startsWith("'")) {
    final int close = value.indexOf(value[0], 1);
    return close == -1 ? value : value.substring(0, close + 1);
  }
  if (value.startsWith('#')) {
    return '';
  }
  final int comment = value.indexOf(RegExp(r'\s#'));
  return (comment == -1 ? value : value.substring(0, comment)).trim();
}

/// 값 양 끝의 짝 따옴표를 뗀다 — 그림 경로 비교용.
String _unquote(String raw) {
  if (raw.length >= 2 &&
      (raw.startsWith('"') || raw.startsWith("'")) &&
      raw.endsWith(raw[0])) {
    return raw.substring(1, raw.length - 1);
  }
  return raw;
}

/// 생성기 `parseColor` 와 같은 규칙으로 색 값을 6자리 대문자 hex 로 바꾼다.
///
/// 따옴표 · `#` · 공백을 지우고 대문자로 바꾼 뒤 6글자가 아니면 null 이다.
String? normalizeSplashColor(String raw) {
  final String value = raw
      .replaceAll('"', '')
      .replaceAll("'", '')
      .replaceAll('#', '')
      .replaceAll(' ', '')
      .toUpperCase();
  return value.length == 6 ? value : null;
}

/// [color] 의 RGB 를 6자리 대문자 hex 로 쓴다(알파는 뺀다).
String formatColorHex(Color color) => (color.toARGB32() & 0xFFFFFF)
    .toRadixString(16)
    .padLeft(6, '0')
    .toUpperCase();

const String _bodyPath = 'lib/features/splash/presentation/splash_body.dart';
const String _guideLine = '(docs/guide.md 「스플래시 바꾸기」)';

/// 메시지 본문 [body] 에 안내 절 끝줄을 붙여 한 메시지로 만든다.
String _buildMessage(String body) => '$body\n$_guideLine';

/// 색 키 [key] 의 값 문제(없음 · 6자리 아님) 메시지를 만든다.
String _buildColorValueMessage(String key, String? raw) {
  if (raw == null || raw.isEmpty) {
    return _buildMessage(
      'flutter_native_splash.yaml 의 $key 값이 없다 — 따옴표 없는 # '
      '값($key: #FFFFFF)은 YAML 주석이 되어 빈 값이다.\n'
      '$key: "#FFFFFF" 처럼 따옴표로 감싼다.',
    );
  }
  return _buildMessage(
    'flutter_native_splash.yaml 의 $key 는 $raw 인데 6자리 색(#RRGGBB)이 아니다 — '
    '네이티브 스플래시 생성기도 이 값을 받지 않는다.',
  );
}

/// 필수 색 키 [key] 를 읽어 상수 [constName] 의 [expected] 와 대조한다.
///
/// yaml 값이 쓸 수 있으면 정규화한 hex 를 돌려준다(짝 키 대조의 기준).
String? _checkRequiredColor(
  List<String> messages,
  Map<String, String> top,
  String key,
  String constName,
  Color expected,
) {
  final String? raw = top[key];
  final String? hex = raw == null ? null : normalizeSplashColor(raw);
  final String expectedHex = formatColorHex(expected);
  if (hex == null) {
    messages.add(_buildColorValueMessage(key, raw));
    _checkOpaque(messages, constName, expected, expectedHex);
    return null;
  }
  if (hex != expectedHex) {
    // 고칠 선언이 알파 FF 를 담으므로 알파 메시지를 따로 내지 않는다.
    messages.add(
      _buildMessage(
        'flutter_native_splash.yaml 의 $key 는 #$hex 인데 $_bodyPath 의 '
        '$constName 는 #$expectedHex 다.\n'
        'Flutter 스플래시가 네이티브 스플래시와 같도록 상수를 yaml 값으로 고친다: '
        'const Color $constName = Color(0xFF$hex);',
      ),
    );
  } else {
    _checkOpaque(messages, constName, expected, hex);
  }
  return hex;
}

/// 상수 [constName] 의 [color] 알파가 `0xFF` 인지 본다 — yaml 색에는 알파가
/// 없어 네이티브 스플래시는 늘 불투명하므로, 알파가 다르면 RGB 가 같아도 두
/// 화면이 이어지지 않는다. [hex] 는 고칠 선언에 넣을 6자리 RGB 다.
void _checkOpaque(
  List<String> messages,
  String constName,
  Color color,
  String hex,
) {
  final int alpha = color.toARGB32() >>> 24;
  if (alpha == 0xFF) {
    return;
  }
  final String alphaHex = alpha.toRadixString(16).padLeft(2, '0').toUpperCase();
  messages.add(
    _buildMessage(
      '$_bodyPath 의 $constName 알파가 0x$alphaHex 다 — 스플래시 배경은 '
      '불투명해야 한다(Color(0xFF<6자리>) 꼴).\n'
      '상수를 고친다: const Color $constName = Color(0xFF$hex);',
    ),
  );
}

/// 필수 그림 경로 키 [key] 를 읽어 상수 [constName] 의 [expected] 와 대조한다.
///
/// yaml 값이 있으면 따옴표 뺀 경로를 돌려준다(짝 키 대조의 기준).
String? _checkRequiredImage(
  List<String> messages,
  Map<String, String> top,
  String key,
  String constName,
  String expected,
) {
  final String? raw = top[key];
  final String path = raw == null ? '' : _unquote(raw);
  if (path.isEmpty) {
    messages.add(
      _buildMessage('flutter_native_splash.yaml 의 $key 값이 없다 — 로고 그림 경로를 적는다.'),
    );
    return null;
  }
  if (path != expected) {
    messages.add(
      _buildMessage(
        'flutter_native_splash.yaml 의 $key 는 $path 인데 $_bodyPath 의 '
        '$constName 는 $expected 다.\n'
        'Flutter 스플래시가 네이티브 스플래시와 같도록 상수를 yaml 값으로 고친다: '
        "const String $constName = '$path';",
      ),
    );
  }
  return path;
}

/// 짝 키가 다를 때의 메시지를 만든다 — [value] · [pairValue] 는 표시용 값이다.
String _buildPairMessage(
  String key,
  String value,
  String pairKey,
  String pairValue,
) => _buildMessage(
  '$key 는 $value 인데 $pairKey 는 $pairValue 다 — 지우거나 같게 '
  '둔다(Flutter 스플래시는 Android 버전 · 플랫폼을 구분하지 않는다)',
);

/// 색 짝 키 [key](메시지 이름 [name])가 없거나 짝 [pairKey] 의 [pairHex] 와
/// 같은지 본다.
void _checkPairColor(
  List<String> messages,
  Map<String, String> map,
  String key,
  String name,
  String pairKey,
  String? pairHex,
) {
  final String? raw = map[key];
  if (raw == null) {
    return;
  }
  final String? hex = normalizeSplashColor(raw);
  if (hex == null) {
    messages.add(_buildColorValueMessage(name, raw));
    return;
  }
  // 짝 키 값 문제는 이미 메시지로 알렸다.
  if (pairHex != null && hex != pairHex) {
    messages.add(_buildPairMessage(name, '#$hex', pairKey, '#$pairHex'));
  }
}

/// 그림 경로 짝 키 [key] 가 없거나 짝 [pairKey] 의 [pairPath] 와 같은지 본다.
void _checkPairImage(
  List<String> messages,
  Map<String, String> top,
  String key,
  String pairKey,
  String? pairPath,
) {
  final String? raw = top[key];
  if (raw == null) {
    return;
  }
  final String path = _unquote(raw);
  if (path.isEmpty) {
    messages.add(
      _buildMessage(
        'flutter_native_splash.yaml 의 $key 값이 없다 — 지우거나 $pairKey 와 같은 '
        '경로를 적는다.',
      ),
    );
    return;
  }
  if (pairPath != null && path != pairPath) {
    messages.add(_buildPairMessage(key, path, pairKey, pairPath));
  }
}

/// `android_12:` 블록의 그림 키 [key] 가 있고 짝 [pairKey] 의 [pairPath] 와
/// 같은지 본다.
///
/// 색 키와 달리 지우면 안 된다 — 생성기는 이 값이 없을 때 top-level 경로로
/// 되돌아가지 않는다. [missingEffect] 는 없을 때 네이티브 스플래시가 그리는 것이다.
void _checkAndroid12Image(
  List<String> messages,
  Map<String, String> android12,
  String key,
  String pairKey,
  String? pairPath,
  String missingEffect,
) {
  final String? raw = android12[key];
  final String path = raw == null ? '' : _unquote(raw);
  if (path.isEmpty) {
    messages.add(
      _buildMessage(
        'flutter_native_splash.yaml 의 android_12.$key 값이 없다 — 이 값이 '
        '없으면 Android 12 이상 네이티브 스플래시는 $missingEffect.\n'
        'android_12: 블록에 $key: 줄을 두고 $pairKey 와 같은 경로를 적는다.',
      ),
    );
    return;
  }
  // 짝 키 값 문제는 이미 메시지로 알렸다.
  if (pairPath != null && path != pairPath) {
    messages.add(
      _buildMessage(
        'android_12.$key 는 $path 인데 $pairKey 는 $pairPath 다 — 같은 경로를 '
        '적는다(Flutter 스플래시는 Android 버전을 구분하지 않는다)',
      ),
    );
  }
}

/// [yaml] 의 색 · 그림 경로를 기대 상수 값과 대조해 어긋남 메시지를 돌려준다.
///
/// 빈 목록이면 통과다. 메시지는 키마다 하나이고 끝줄이 안내 절 이름이다.
/// - `color` · `color_dark` · `image` · `image_dark` 는 필수이고 [color] ·
///   [colorDark] · [image] · [imageDark] 와 같아야 한다. [color] · [colorDark]
///   는 불투명(알파 `0xFF`)이어야 한다.
/// - `android_12.image` · `android_12.image_dark` 는 필수이고 `image` ·
///   `image_dark` 와 같아야 한다.
/// - `android_12.color` · `android_12.color_dark` · 플랫폼별 색 · 로고 키는
///   없거나 짝 키와 같아야 한다.
/// - `background_image` 로 시작하는 키는 있으면 어긋남이다.
List<String> findSplashMismatches(
  String yaml, {
  required Color color,
  required Color colorDark,
  required String image,
  required String imageDark,
}) {
  final SplashYamlBlocks blocks = readSplashYaml(yaml);
  if (!blocks.hasBlock) {
    return <String>[
      _buildMessage(
        'flutter_native_splash.yaml 에 들여쓰기 0 의 flutter_native_splash: 줄이 '
        '없다.',
      ),
    ];
  }
  final Map<String, String> top = blocks.top;
  final messages = <String>[];

  final String? lightHex = _checkRequiredColor(
    messages,
    top,
    'color',
    'kSplashColor',
    color,
  );
  final String? darkHex = _checkRequiredColor(
    messages,
    top,
    'color_dark',
    'kSplashColorDark',
    colorDark,
  );
  final String? lightImage = _checkRequiredImage(
    messages,
    top,
    'image',
    'kSplashImage',
    image,
  );
  final String? darkImage = _checkRequiredImage(
    messages,
    top,
    'image_dark',
    'kSplashImageDark',
    imageDark,
  );

  final Map<String, String> android12 = blocks.android12;
  _checkPairColor(
    messages,
    android12,
    'color',
    'android_12.color',
    'color',
    lightHex,
  );
  _checkPairColor(
    messages,
    android12,
    'color_dark',
    'android_12.color_dark',
    'color_dark',
    darkHex,
  );
  // android_12 그림 키 — 생성기(flutter_native_splash 2.4.7 cli_commands.dart)는
  // android_12.image 를 이 블록에서만 읽고, android_12.image_dark 가 없으면
  // android_12.image 를 쓴다.
  _checkAndroid12Image(
    messages,
    android12,
    'image',
    'image',
    lightImage,
    '로고 대신 런처 아이콘을 그린다',
  );
  _checkAndroid12Image(
    messages,
    android12,
    'image_dark',
    'image_dark',
    darkImage,
    '다크 모드에서도 android_12.image(라이트 로고)를 그린다',
  );

  // 플랫폼별 색 키 — 생성기 cli_commands.dart 의 color_android · color_ios ·
  // color_dark_android · color_dark_ios.
  for (final key in <String>['color_android', 'color_ios']) {
    _checkPairColor(messages, top, key, key, 'color', lightHex);
  }
  for (final key in <String>['color_dark_android', 'color_dark_ios']) {
    _checkPairColor(messages, top, key, key, 'color_dark', darkHex);
  }
  // 플랫폼별 로고 키.
  for (final key in <String>['image_android', 'image_ios']) {
    _checkPairImage(messages, top, key, 'image', lightImage);
  }
  for (final key in <String>['image_dark_android', 'image_dark_ios']) {
    _checkPairImage(messages, top, key, 'image_dark', darkImage);
  }

  // 배경 그림 키 — background_image · background_image_dark 와 플랫폼별 변형.
  for (final MapEntry<String, String> entry in top.entries) {
    if (!entry.key.startsWith('background_image')) {
      continue;
    }
    final String value = _unquote(entry.value);
    messages.add(
      _buildMessage(
        '${entry.key} 는 ${value.isEmpty ? '(빈 값)' : value} 이다 — Flutter '
        '스플래시는 단색 배경만 그리므로 두 화면이 이어지지 않는다. 이 키를 지우고 '
        'color · color_dark 로 배경을 정한다',
      ),
    );
  }
  return messages;
}

// 시험 전용 기대값 — 02 ~ 09 는 사용자 소유 상수를 읽지 않는다.
const Color _white = Color(0xFFFFFFFF);
const Color _black = Color(0xFF000000);
const Color _yellow = Color(0xFFF2B134);
const String _logo = 'assets/images/splash/logo.png';
const String _logoDark = 'assets/images/splash/logo_dark.png';

/// 킷 yaml 꼴 fixture 를 만든다 — 바꿀 값 · 더할 줄만 넘긴다.
///
/// [android12Images] 가 null 이면 `android_12:` 블록의 그림 키를 [image] ·
/// [imageDark] 와 같은 값으로 둔다.
String _buildSplashYaml({
  String color = '"#FFFFFF"',
  String colorDark = '"#000000"',
  String image = _logo,
  String imageDark = _logoDark,
  String topExtra = '',
  String? android12Images,
  String android12Colors =
      '    color: "#FFFFFF"\n'
      '    color_dark: "#000000"\n',
}) =>
    'flutter_native_splash:\n'
    '  color: $color\n'
    '  color_dark: $colorDark\n'
    '  image: $image\n'
    '  image_dark: $imageDark\n'
    '$topExtra'
    '\n'
    '  android_12:\n'
    '${android12Images ?? '    image: $image\n    image_dark: $imageDark\n'}'
    '$android12Colors'
    '\n'
    '  fullscreen: false\n'
    '  android: true\n'
    '  ios: true\n'
    '  web: false # web 은 지원 범위 밖\n';

/// fixture [yaml] 을 시험 전용 기대값(기본 흰색 · 검정 · 킷 로고 경로)과 대조한다.
List<String> _findFixtureMismatches(
  String yaml, {
  Color color = _white,
  Color colorDark = _black,
  String image = _logo,
  String imageDark = _logoDark,
}) => findSplashMismatches(
  yaml,
  color: color,
  colorDark: colorDark,
  image: image,
  imageDark: imageDark,
);

void main() {
  group('flutter_native_splash.yaml ↔ 스플래시 상수 (Phase 26 · T-26-YAML)', () {
    test('T-26-YAML-01: 저장소 yaml 의 색 · 그림 경로가 splash_body.dart 상수와 '
        '같고 짝 키 · 배경 그림 규칙을 지킨다', () {
      final String yaml = readTrackedFile(_yamlPath);
      final SplashYamlBlocks blocks = readSplashYaml(yaml);
      expect(
        blocks.hasBlock,
        isTrue,
        reason: '$_yamlPath 에서 들여쓰기 0 의 flutter_native_splash: 줄을 찾지 못했다',
      );
      expect(
        blocks.hasAndroid12,
        isTrue,
        reason:
            '$_yamlPath 의 flutter_native_splash: 블록에 android_12: 블록이 없다 — '
            'Android 12 이상 네이티브 스플래시 설정이다',
      );

      final List<String> messages = findSplashMismatches(
        yaml,
        color: kSplashColor,
        colorDark: kSplashColorDark,
        image: kSplashImage,
        imageDark: kSplashImageDark,
      );
      expect(
        messages,
        isEmpty,
        reason:
            '$_yamlPath 과 splash_body.dart 상수가 어긋난다:\n\n'
            '${messages.join('\n\n')}',
      );
    });

    test('T-26-YAML-02: yaml 색이 상수와 다르거나 상수 알파가 FF 가 아니면 고칠 '
        '선언으로 실패 · 같으면 통과', () {
      // RunningPencil 꼴 — 네 색 모두 노랑.
      final String yaml = _buildSplashYaml(
        color: '"#F2B134"',
        colorDark: '"#F2B134"',
        android12Colors:
            '    color: "#F2B134"\n'
            '    color_dark: "#F2B134"\n',
      );

      final List<String> messages = _findFixtureMismatches(yaml);
      expect(messages, hasLength(2), reason: messages.join('\n\n'));
      expect(
        messages[0],
        allOf(<Matcher>[
          contains('color 는 #F2B134'),
          contains('kSplashColor 는 #FFFFFF'),
          contains('const Color kSplashColor = Color(0xFFF2B134);'),
          contains('스플래시 바꾸기'),
        ]),
      );
      expect(
        messages[1],
        allOf(<Matcher>[
          contains('color_dark 는 #F2B134'),
          contains('kSplashColorDark 는 #000000'),
          contains('const Color kSplashColorDark = Color(0xFFF2B134);'),
          contains('스플래시 바꾸기'),
        ]),
      );

      // 상수를 yaml 에 맞추면 통과한다.
      expect(
        _findFixtureMismatches(yaml, color: _yellow, colorDark: _yellow),
        isEmpty,
      );

      // RGB 가 같아도 알파가 FF 가 아니면 실패한다(0x 뒤 FF 를 빠뜨린 꼴).
      final List<String> transparent = _findFixtureMismatches(
        _buildSplashYaml(),
        color: const Color(0x00FFFFFF),
      );
      expect(transparent, hasLength(1), reason: transparent.join('\n\n'));
      expect(
        transparent.single,
        allOf(<Matcher>[
          contains('kSplashColor 알파가 0x00 다'),
          contains('불투명'),
          contains('const Color kSplashColor = Color(0xFFFFFFFF);'),
          contains('스플래시 바꾸기'),
        ]),
      );
      final List<String> translucent = _findFixtureMismatches(
        yaml,
        color: _yellow,
        colorDark: const Color(0x80F2B134),
      );
      expect(translucent, hasLength(1), reason: translucent.join('\n\n'));
      expect(
        translucent.single,
        allOf(<Matcher>[
          contains('kSplashColorDark 알파가 0x80 다'),
          contains('const Color kSplashColorDark = Color(0xFFF2B134);'),
        ]),
      );
    });

    test('T-26-YAML-03: android_12.color · color_dark 는 없거나 color · '
        'color_dark 와 같을 때만 통과', () {
      // 없음 → 통과.
      expect(
        _findFixtureMismatches(_buildSplashYaml(android12Colors: '')),
        isEmpty,
      );
      // 같음 → 통과(따옴표 · 대소문자 · # 은 정규화).
      expect(
        _findFixtureMismatches(
          _buildSplashYaml(
            android12Colors:
                "    color: 'ffffff'\n"
                '    color_dark: "#000000"\n',
          ),
        ),
        isEmpty,
      );
      // 다름 → 키마다 메시지.
      final List<String> messages = _findFixtureMismatches(
        _buildSplashYaml(
          android12Colors:
              '    color: "#123456"\n'
              '    color_dark: "#654321"\n',
        ),
      );
      expect(messages, hasLength(2), reason: messages.join('\n\n'));
      expect(
        messages[0],
        allOf(<Matcher>[
          startsWith('android_12.color 는 #123456 인데 color 는 #FFFFFF 다'),
          contains('지우거나 같게 둔다'),
          contains('Android 버전'),
          contains('스플래시 바꾸기'),
        ]),
      );
      expect(
        messages[1],
        startsWith('android_12.color_dark 는 #654321 인데 color_dark 는 #000000 다'),
      );
    });

    test('T-26-YAML-04: 따옴표 없는 # 값(YAML 주석 → 빈 값)과 6자리가 아닌 색은 '
        '값 문제로 실패', () {
      final List<String> unquoted = _findFixtureMismatches(
        _buildSplashYaml(color: '#F2B134'),
      );
      expect(unquoted, hasLength(1), reason: unquoted.join('\n\n'));
      expect(
        unquoted.single,
        allOf(<Matcher>[
          contains('color 값이 없다'),
          contains('따옴표'),
          contains('스플래시 바꾸기'),
        ]),
      );

      // 짝 키도 같은 규칙이다.
      final List<String> pairUnquoted = _findFixtureMismatches(
        _buildSplashYaml(
          android12Colors:
              '    color: #FFFFFF\n'
              '    color_dark: "#000000"\n',
        ),
      );
      expect(pairUnquoted, hasLength(1), reason: pairUnquoted.join('\n\n'));
      expect(pairUnquoted.single, contains('android_12.color 값이 없다'));

      final List<String> short = _findFixtureMismatches(
        _buildSplashYaml(colorDark: '"#000"'),
      );
      expect(short, hasLength(1), reason: short.join('\n\n'));
      expect(short.single, contains('color_dark 는 "#000" 인데 6자리 색'));
    });

    test('T-26-YAML-05: 플랫폼별 색 키는 없거나 짝 키와 같을 때만 통과', () {
      // 없음 → 통과(기본 fixture 에 플랫폼 키가 없다).
      expect(_findFixtureMismatches(_buildSplashYaml()), isEmpty);
      // 같음 → 통과.
      expect(
        _findFixtureMismatches(
          _buildSplashYaml(
            topExtra:
                '  color_android: "#FFFFFF"\n'
                '  color_ios: "ffffff"\n'
                '  color_dark_android: "#000000"\n'
                '  color_dark_ios: "#000000"\n',
          ),
        ),
        isEmpty,
      );
      // 다름 → 키마다 키 이름 · 두 값이 든 메시지.
      final List<String> messages = _findFixtureMismatches(
        _buildSplashYaml(
          topExtra:
              '  color_android: "#123456"\n'
              '  color_dark_ios: "#654321"\n',
        ),
      );
      expect(messages, hasLength(2), reason: messages.join('\n\n'));
      expect(
        messages[0],
        allOf(<Matcher>[
          startsWith('color_android 는 #123456 인데 color 는 #FFFFFF 다'),
          contains('플랫폼'),
          contains('스플래시 바꾸기'),
        ]),
      );
      expect(
        messages[1],
        startsWith('color_dark_ios 는 #654321 인데 color_dark 는 #000000 다'),
      );
    });

    test('T-26-YAML-06: 플랫폼별 로고 키는 없거나 짝 키와 같을 때만 통과', () {
      expect(_findFixtureMismatches(_buildSplashYaml()), isEmpty);
      expect(
        _findFixtureMismatches(
          _buildSplashYaml(
            topExtra:
                '  image_ios: $_logo\n'
                '  image_android: "$_logo"\n'
                '  image_dark_android: $_logoDark\n'
                "  image_dark_ios: '$_logoDark'\n",
          ),
        ),
        isEmpty,
      );
      final List<String> messages = _findFixtureMismatches(
        _buildSplashYaml(
          topExtra:
              '  image_ios: assets/images/splash/logo_ios.png\n'
              '  image_dark_android: "assets/images/splash/logo_dark_aos.png"\n',
        ),
      );
      expect(messages, hasLength(2), reason: messages.join('\n\n'));
      expect(
        messages[0],
        startsWith(
          'image_ios 는 assets/images/splash/logo_ios.png 인데 image 는 '
          '$_logo 다',
        ),
      );
      expect(
        messages[1],
        startsWith(
          'image_dark_android 는 assets/images/splash/logo_dark_aos.png 인데 '
          'image_dark 는 $_logoDark 다',
        ),
      );
    });

    test('T-26-YAML-07: 배경 그림 키는 있으면 키 · 값 · 단색 이유로 실패', () {
      expect(_findFixtureMismatches(_buildSplashYaml()), isEmpty);
      final List<String> messages = _findFixtureMismatches(
        _buildSplashYaml(
          topExtra:
              '  background_image: "assets/images/splash/bg_probe.png"\n'
              '  background_image_dark_ios: assets/images/splash/bg_dark.png\n',
        ),
      );
      expect(messages, hasLength(2), reason: messages.join('\n\n'));
      expect(
        messages[0],
        allOf(<Matcher>[
          startsWith('background_image 는 assets/images/splash/bg_probe.png 이다'),
          contains('단색 배경만 그리므로'),
          contains('이 키를 지우고 color · color_dark 로 배경을 정한다'),
          contains('스플래시 바꾸기'),
        ]),
      );
      expect(
        messages[1],
        allOf(<Matcher>[
          startsWith(
            'background_image_dark_ios 는 assets/images/splash/bg_dark.png 이다',
          ),
          contains('단색'),
        ]),
      );
    });

    test('T-26-YAML-08: image · image_dark 가 로고 경로 상수와 다르면 고칠 선언으로 '
        '실패 · 같으면 통과', () {
      const myLogo = 'assets/images/splash/my_logo.png';
      final String yaml = _buildSplashYaml(image: myLogo);
      final List<String> messages = _findFixtureMismatches(yaml);
      expect(messages, hasLength(1), reason: messages.join('\n\n'));
      expect(
        messages.single,
        allOf(<Matcher>[
          contains('image 는 $myLogo'),
          contains('kSplashImage 는 $_logo'),
          contains("const String kSplashImage = '$myLogo';"),
          contains('스플래시 바꾸기'),
        ]),
      );
      expect(_findFixtureMismatches(yaml, image: myLogo), isEmpty);

      final List<String> darkMessages = _findFixtureMismatches(
        _buildSplashYaml(imageDark: '"assets/images/splash/my_logo_dark.png"'),
      );
      expect(darkMessages, hasLength(1), reason: darkMessages.join('\n\n'));
      expect(
        darkMessages.single,
        contains(
          'const String kSplashImageDark = '
          "'assets/images/splash/my_logo_dark.png';",
        ),
      );
    });

    test('T-26-YAML-09: 키 이름이 든 주석 줄은 값으로 읽지 않고 블록을 끝내지도 '
        '않는다', () {
      const yaml =
          '# 머리 주석: color 를 바꾼다\n'
          'flutter_native_splash:\n'
          '#   color: "#123456"\n'
          '  color: "#FFFFFF" # 흰색\n'
          '  # color_android: "#123456"\n'
          '  color_dark: "#000000"\n'
          '#  background_image: x.png\n'
          '  image: assets/images/splash/logo.png\n'
          '  image_dark: assets/images/splash/logo_dark.png\n'
          '  android_12:\n'
          '    # color: "#123456"\n'
          '    image: assets/images/splash/logo.png\n'
          '  # 들여쓰기 2 주석은 android_12 블록을 끝내지 않는다\n'
          '    image_dark: assets/images/splash/logo_dark.png\n'
          '    color_dark: "#000000"\n'
          '  web: false # web: true 로 두지 않는다\n';

      final SplashYamlBlocks blocks = readSplashYaml(yaml);
      expect(blocks.hasBlock, isTrue);
      expect(blocks.hasAndroid12, isTrue);
      expect(
        blocks.top,
        equals(<String, String>{
          'color': '"#FFFFFF"',
          'color_dark': '"#000000"',
          'image': 'assets/images/splash/logo.png',
          'image_dark': 'assets/images/splash/logo_dark.png',
          'web': 'false',
        }),
      );
      expect(
        blocks.android12,
        equals(<String, String>{
          'image': 'assets/images/splash/logo.png',
          'image_dark': 'assets/images/splash/logo_dark.png',
          'color_dark': '"#000000"',
        }),
      );
      expect(_findFixtureMismatches(yaml), isEmpty);

      // 주석 뒤 실제 줄은 여전히 android_12 블록 값이다.
      final List<String> messages = _findFixtureMismatches(
        yaml.replaceFirst(
          '    color_dark: "#000000"\n',
          '    color_dark: "#654321"\n',
        ),
      );
      expect(messages, hasLength(1), reason: messages.join('\n\n'));
      expect(messages.single, startsWith('android_12.color_dark 는 #654321'));
    });

    test('T-26-YAML-10: android_12.image · image_dark 는 없으면 실패 · image · '
        'image_dark 와 다르면 실패 · 같으면 통과', () {
      // 같음 → 통과(따옴표는 정규화).
      expect(
        _findFixtureMismatches(
          _buildSplashYaml(
            android12Images:
                '    image: "$_logo"\n'
                "    image_dark: '$_logoDark'\n",
          ),
        ),
        isEmpty,
      );

      // image_dark 만 없음 → 다크에서 라이트 로고를 그린다는 메시지.
      final List<String> noDark = _findFixtureMismatches(
        _buildSplashYaml(android12Images: '    image: $_logo\n'),
      );
      expect(noDark, hasLength(1), reason: noDark.join('\n\n'));
      expect(
        noDark.single,
        allOf(<Matcher>[
          contains('android_12.image_dark 값이 없다'),
          contains('라이트 로고'),
          contains('image_dark 와 같은 경로를 적는다'),
          contains('스플래시 바꾸기'),
        ]),
      );

      // 둘 다 없음 → 키마다 메시지(image 는 런처 아이콘).
      final List<String> none = _findFixtureMismatches(
        _buildSplashYaml(android12Images: ''),
      );
      expect(none, hasLength(2), reason: none.join('\n\n'));
      expect(
        none[0],
        allOf(<Matcher>[
          contains('android_12.image 값이 없다'),
          contains('런처 아이콘'),
        ]),
      );
      expect(none[1], contains('android_12.image_dark 값이 없다'));

      // 빈 값도 없음과 같다.
      final List<String> empty = _findFixtureMismatches(
        _buildSplashYaml(
          android12Images:
              '    image: ""\n'
              '    image_dark: $_logoDark\n',
        ),
      );
      expect(empty, hasLength(1), reason: empty.join('\n\n'));
      expect(empty.single, contains('android_12.image 값이 없다'));

      // 다름 → 키 이름 · 두 경로가 든 메시지.
      final List<String> differs = _findFixtureMismatches(
        _buildSplashYaml(
          android12Images:
              '    image: assets/images/splash/logo_a12.png\n'
              '    image_dark: $_logoDark\n',
        ),
      );
      expect(differs, hasLength(1), reason: differs.join('\n\n'));
      expect(
        differs.single,
        allOf(<Matcher>[
          startsWith(
            'android_12.image 는 assets/images/splash/logo_a12.png 인데 image 는 '
            '$_logo 다',
          ),
          contains('같은 경로를 적는다'),
          contains('스플래시 바꾸기'),
        ]),
      );
    });
  });
}
