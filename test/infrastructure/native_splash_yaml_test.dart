// `flutter_native_splash.yaml` 과 스플래시 상수의 대조.
//
// **목적:** Flutter 스플래시(`SplashFrame`) 배경 · 로고가 네이티브 스플래시와
// 같도록 `flutter_native_splash.yaml` 의 색 · 그림 경로와
// `lib/features/splash/presentation/splash_body.dart` 상수가 같은지 본다. yaml
// 만 바꾸고 상수를 잊으면 화면에서는 늦게 드러나는 조용한 어긋남이 되므로, 키
// 이름 · 두 값 · 붙여 넣을 Dart 선언을 담은 메시지로 실패한다.
//
// **YAML 을 파서 없이 줄 단위로 읽는다** — YAML 파서 패키지는 이 앱의 직접
// 의존이 아니라 import 하면 `depend_on_referenced_packages` 진단이 난다. 읽는
// 범위는 [readSplashYaml] · [readFlutterAssets] 문서에 있다.
//
// **읽지 못한 줄은 그 줄을 말하는 메시지로 실패한다** — 들여쓰기로 자리를 정하지
// 못한 줄, 블록으로 읽어야 하는 키(`flutter_native_splash:` · `android_12:` ·
// `flutter:` · `assets:`)의 flow 꼴(`{…}` · `[…]`) 값, `assets:` 목록 항목 안에서
// [readFlutterAssets] 문서의 읽는 꼴 밖의 줄이 그 줄이다.
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
// **로고 경로는 번들 자산이어야 한다** — 생성기는 파일 시스템에서 읽지만 Flutter
// 스플래시는 `pubspec.yaml` 의 `flutter: assets:` 에 등록된 자산만 읽고, 자산 키는
// 파일 이름의 대소문자를 구분한다. 빌드를 한정한 항목([_isBuildRestricted])은 그
// 빌드에만 실리므로 등록으로 보지 않는다.
//
// 사용자 안내: `docs/guide.md` 「스플래시 바꾸기」.
//
// 시험 ID: T-26-YAML-01(저장소 yaml ↔ 상수) · 02(색 상수 어긋남 양방향 · 알파) ·
// 03(`android_12` 색) · 04(값 없음) · 05(플랫폼별 색 키) · 06(플랫폼별 로고 키) ·
// 07(배경 그림 키) · 08(로고 경로 상수) · 09(주석 줄) · 10(`android_12` 그림) ·
// 11(들여쓰기) · 12(저장소 로고 = 번들 자산) · 13(번들 자산 어긋남) · 14(로고 파일
// 이름 대소문자).

import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_starter_kit/features/splash/presentation/splash_body.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_text.dart';

const String _yamlPath = 'flutter_native_splash.yaml';

/// 읽지 못한 줄의 이유 — 메시지가 말하는 원인과 고칠 꼴을 고른다.
enum UnreadableYamlReason {
  /// 들여쓰기로 자리를 정하지 못한 줄이다.
  indent,

  /// 블록으로 읽어야 하는 키의 값이 flow 꼴이다.
  flow,

  /// `flutter: assets:` 목록 항목 안에서 [readFlutterAssets] 가 읽는 꼴이 아니다.
  assetItem,
}

/// 두 줄 파서가 읽지 못한 첫 줄 — 파일 머리 주석의 「읽지 못한 줄」 이다.
///
/// - `line`: 줄 번호 · 원문(「N번째 줄 「…」」 꼴).
/// - `reason`: 읽지 못한 이유다.
typedef UnreadableYamlLine = ({String line, UnreadableYamlReason reason});

/// [lines] 의 [index] 번째 줄을 [reason] 이유의 읽지 못한 줄로 만든다.
UnreadableYamlLine _unreadableAt(
  List<String> lines,
  int index, {
  UnreadableYamlReason reason = UnreadableYamlReason.indent,
}) => (line: '${index + 1}번째 줄 「${lines[index].trim()}」', reason: reason);

/// 값 [value] 가 flow 꼴(`{…}` · `[…]`)인지 본다.
bool _isFlowValue(String value) =>
    value.startsWith('{') || value.startsWith('[');

/// [line] 이 들여쓰기 0 의 [key] 줄이면 끝 주석을 걷어낸 값을 돌려준다 — 아니면
/// null 이다.
String? _readTopKeyValue(String line, String key) {
  if (line.isEmpty || line.startsWith(RegExp(r'[\s#]'))) {
    return null;
  }
  final int colon = line.indexOf(':');
  if (colon == -1 || line.substring(0, colon) != key) {
    return null;
  }
  return _readYamlValue(line.substring(colon + 1));
}

/// [readSplashYaml] 의 결과 — 블록을 찾았는지 · 읽지 못한 줄 · 키 → 원값 맵 두 개.
///
/// 어느 줄을 어느 맵에 넣는지는 [readSplashYaml] 문서의 규칙을 따른다.
/// - `hasBlock`: 들여쓰기 0 의 `flutter_native_splash:` 줄이 있다.
/// - `hasAndroid12`: 그 블록의 top 키로 `android_12:` 줄이 있다.
/// - `unreadable`: 읽지 못한 첫 줄이다. null 이 아니면 두 맵을 믿지 않는다.
/// - `top`: 블록의 top 키 → 원값(따옴표 포함 · 주석 제외).
/// - `android12`: `android_12:` 블록의 키 → 원값.
typedef SplashYamlBlocks = ({
  bool hasBlock,
  bool hasAndroid12,
  UnreadableYamlLine? unreadable,
  Map<String, String> top,
  Map<String, String> android12,
});

/// [yaml] 의 `flutter_native_splash:` 블록을 줄 단위로 읽는다.
///
/// 들여쓰기는 칸 수가 아니라 상대 깊이로 읽는다 — 블록 안 첫 키 줄의 들여쓰기가
/// top 키, `android_12:` 다음 첫 줄의 들여쓰기가 `android_12` 키이고, 값이 빈 다른
/// top 키 아래의 더 깊은 줄(목록 · 맵 내용)은 대조하지 않고 건너뛰며, 이 셋 중
/// 어디에도 들지 않는 줄과 `flutter_native_splash:` · `android_12:` 의 flow 꼴 값은
/// `unreadable` 로 돌려준다.
///
/// 앞 공백을 걷어낸 줄이 `#` 로 시작하면 버린다(블록을 끝내지도 않는다). 값이
/// 따옴표로 시작하면 짝 따옴표까지, 아니면 첫 「공백 + `#`」 앞까지를 값으로 본다
/// — 값이 `#` 로 시작하면 YAML 주석이라 빈 값이다.
SplashYamlBlocks readSplashYaml(String yaml) {
  final top = <String, String>{};
  final android12 = <String, String>{};
  final List<String> lines = yaml.split('\n');
  final int start = lines.indexWhere((String line) {
    final String? value = _readTopKeyValue(line, 'flutter_native_splash');
    return value != null && (value.isEmpty || _isFlowValue(value));
  });
  if (start == -1) {
    return (
      hasBlock: false,
      hasAndroid12: false,
      unreadable: null,
      top: top,
      android12: android12,
    );
  }
  if (_readTopKeyValue(lines[start], 'flutter_native_splash')!.isNotEmpty) {
    return (
      hasBlock: true,
      hasAndroid12: false,
      unreadable: _unreadableAt(
        lines,
        start,
        reason: UnreadableYamlReason.flow,
      ),
      top: top,
      android12: android12,
    );
  }

  var hasAndroid12 = false;
  var inAndroid12 = false;
  // 값이 빈 top 키(android_12 밖) 아래 — 더 깊은 줄은 그 키의 내용이다.
  var inOtherContainer = false;
  int? topIndent;
  int? android12Indent;
  UnreadableYamlLine? unreadable;
  for (var i = start + 1; i < lines.length; i++) {
    final String line = lines[i].trimRight();
    final String trimmed = line.trimLeft();
    // 빈 줄 · 주석 줄은 들여쓰기와 무관하게 버린다 — 블록을 끝내지 않는다.
    if (trimmed.isEmpty || trimmed.startsWith('#')) {
      continue;
    }
    final int indent = line.length - trimmed.length;
    if (indent == 0) {
      break;
    }
    topIndent ??= indent;
    final bool isListItem = trimmed == '-' || trimmed.startsWith('- ');
    final int colon = trimmed.indexOf(':');
    final String key = colon == -1 ? '' : trimmed.substring(0, colon).trim();
    final String value = colon == -1
        ? ''
        : _readYamlValue(trimmed.substring(colon + 1));

    if (indent == topIndent && !isListItem && colon != -1) {
      if (key == 'android_12' && _isFlowValue(value)) {
        unreadable = _unreadableAt(lines, i, reason: UnreadableYamlReason.flow);
        break;
      }
      inAndroid12 = key == 'android_12' && value.isEmpty;
      inOtherContainer = !inAndroid12 && value.isEmpty;
      android12Indent = null;
      if (inAndroid12) {
        hasAndroid12 = true;
      } else {
        top[key] = value;
      }
      continue;
    }
    if (inAndroid12 && indent > topIndent) {
      android12Indent ??= indent;
      if (indent == android12Indent && !isListItem && colon != -1) {
        android12[key] = value;
        continue;
      }
    }
    // YAML 은 목록 항목을 키와 같은 들여쓰기에 둘 수도 있다.
    final bool isContainerContent =
        indent > topIndent || (indent == topIndent && isListItem);
    if (inOtherContainer && isContainerContent) {
      continue;
    }
    unreadable = _unreadableAt(lines, i);
    break;
  }
  if (topIndent == null) {
    unreadable = (
      line: '${start + 2}번째 줄부터 — flutter_native_splash: 블록에 키 줄이 없다',
      reason: UnreadableYamlReason.indent,
    );
  }
  return (
    hasBlock: true,
    hasAndroid12: hasAndroid12,
    unreadable: unreadable,
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

/// [file] 의 읽지 못한 줄 [unreadable] 메시지를 만든다 — 들여쓰기를 읽지 못했으면
/// [indentScope](들여쓰기를 본 범위)와 고칠 꼴 [indentHint] 를 함께 쓴다.
String _buildUnreadableMessage(
  String file,
  UnreadableYamlLine unreadable, {
  required String indentScope,
  required String indentHint,
}) => _buildMessage(switch (unreadable.reason) {
  UnreadableYamlReason.flow =>
    '$file 의 ${unreadable.line} 을 읽지 못했다.\n'
        'flow 꼴({…} · […])은 읽지 않는다 — 블록 꼴로 적는다.',
  UnreadableYamlReason.indent =>
    '$file 의 $indentScope들여쓰기를 읽지 못했다 — ${unreadable.line}.\n'
        '$indentHint',
  // 이 이유는 pubspec.yaml 의 assets: 목록에서만 난다.
  UnreadableYamlReason.assetItem =>
    '$file 의 ${unreadable.line} 을 읽지 못했다 — flutter: assets: 목록 항목에서 '
        '읽는 꼴이 아니다.\n'
        '목록 항목은 같은 들여쓰기의 「- 경로」 한 줄이나 「- path: 경로」 와 그 '
        '아래 따옴표 없는 「키: 값」 줄로 적고, 따옴표로 감싼 값 안에는 같은 따옴표와 '
        r'\ 를 쓰지 않으며, flavors: · platforms: 값은 같은 줄의 […] 이나 그 아래 '
        '「- 이름」 줄로 적는다.',
});

/// `flutter_native_splash.yaml` 의 읽지 못한 줄 [unreadable] 메시지를 만든다.
String _buildSplashUnreadableMessage(UnreadableYamlLine unreadable) =>
    _buildUnreadableMessage(
      _yamlPath,
      unreadable,
      indentScope: '',
      indentHint:
          'flutter_native_splash: 블록의 키는 모두 같은 들여쓰기로, android_12: '
          '아래 키는 그보다 깊은 같은 들여쓰기로 적는다.',
    );

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
/// 읽지 못한 줄(파일 머리 주석)이 있으면 그 메시지 하나만 낸다.
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
  final UnreadableYamlLine? unreadable = blocks.unreadable;
  if (unreadable != null) {
    // 맵을 믿을 수 없으므로 값 문제 메시지를 함께 내지 않는다.
    return <String>[_buildSplashUnreadableMessage(unreadable)];
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

const String _pubspecPath = 'pubspec.yaml';

/// [readFlutterAssets] 가 읽은 `flutter: assets:` 항목 하나.
///
/// - `path`: 자산 경로(따옴표 · 끝 주석 제외 · `path:` 꼴은 그 값).
/// - `isBuildRestricted`: 항목이 빌드를 한정한다 — [_isBuildRestricted] 규칙이다.
typedef FlutterAssetEntry = ({String path, bool isBuildRestricted});

/// [readFlutterAssets] 의 결과 — `flutter: assets:` 목록과 읽지 못한 줄.
///
/// 어느 줄을 목록 항목으로 읽는지는 [readFlutterAssets] 문서의 규칙을 따른다.
/// - `hasAssets`: 맨 위 `flutter:` 절에 `assets:` 키가 있다.
/// - `unreadable`: 읽지 못한 첫 줄이다. null 이 아니면 `assets` 를 믿지 않는다.
/// - `assets`: `path` 가 있는 항목들이다.
typedef FlutterAssetList = ({
  bool hasAssets,
  UnreadableYamlLine? unreadable,
  List<FlutterAssetEntry> assets,
});

/// `키: 값` 꼴 줄의 키 — 키는 따옴표 없이 영문자 · `_` 로 시작하고 영문자 ·
/// 숫자 · `_` · `-` 만 쓰며, 바로 뒤 `:` 다음은 공백이거나 줄 끝이다.
final RegExp _yamlKeyPattern = RegExp(r'^([A-Za-z_][\w-]*):(?=\s|$)');

/// 자산 항목의 빌드 한정 키 — Flutter 도구는 이 키의 이름에 맞는 빌드에만 그
/// 항목을 싣는다(빈 목록이면 모든 빌드).
const List<String> _buildRestrictionKeys = <String>['flavors', 'platforms'];

/// 킷이 만드는 앱 플랫폼 — `platforms:` 가 둘을 모두 담으면 킷 빌드를 한정하지
/// 않는다.
const List<String> _kitPlatforms = <String>['android', 'ios'];

/// 항목의 `flavors:` 이름 [flavors] · `platforms:` 이름 [platforms] 가 빌드를
/// 한정하는지 본다 — flavor 이름이 있거나, 플랫폼 이름이 있는데 킷 플랫폼
/// (android · ios)을 모두 담지 않으면 한정이다.
bool _isBuildRestricted(List<String> flavors, List<String> platforms) =>
    flavors.isNotEmpty ||
    (platforms.isNotEmpty && !_kitPlatforms.every(platforms.contains));

/// 빌드 한정 키의 한 줄 값 [value] 에서 이름을 꺼낸다 — `[]` · `null` · `~` 는
/// 이름이 없다. [value] 는 [_isReadableRestrictionValue] 를 지난 원문의 비지 않은
/// 값([_readYamlValue])이다.
List<String> _readInlineNames(String value) {
  if (value == 'null' || value == '~') {
    return const <String>[];
  }
  if (!value.startsWith('[')) {
    return <String>[_unquote(value)];
  }
  return <String>[
    for (final String part in value.substring(1, value.length - 1).split(','))
      if (part.trim().isNotEmpty) _unquote(part.trim()),
  ];
}

/// 값 [value] 가 비지 않았고 YAML 표시로 시작하지 않는지 본다 — 표시는 flow ·
/// 태그 · 앵커 · 별칭 · 블록 스칼라 · 예약 글자(`{` `[` `!` `&` `*` `|` `>` `%`
/// `@` `` ` ``)와 뒤에 공백이 오거나 줄이 끝나는 `?` · `:` · `-`(복합 키 · 목록)다.
bool _isPlainScalar(String value) =>
    value.isNotEmpty && !value.startsWith(RegExp(r'[{\[!&*|>%@`]|[?:-](\s|$)'));

/// 키 뒤나 `- ` 뒤의 원문 [rest] 가 이 시험이 읽는 한 줄 스칼라 값인지 본다 —
/// 값([_readYamlValue])이 [_isPlainScalar] 이고, 따옴표로 시작하면 같은 따옴표로
/// 닫히며 닫는 따옴표 뒤는 비거나 `#` 로 시작한다(주석).
bool _isScalarValue(String rest) {
  final String value = _readYamlValue(rest);
  if (!_isPlainScalar(value)) {
    return false;
  }
  if (value.startsWith('"') || value.startsWith("'")) {
    final String after = rest.trim().substring(value.length).trim();
    return value.length >= 2 &&
        value.endsWith(value[0]) &&
        (after.isEmpty || after.startsWith('#'));
  }
  return true;
}

/// 빌드 한정 키 뒤의 원문 [rest] 를 읽을 수 있는지 본다 — 값([_readYamlValue])이
/// 비었거나, [_isScalarValue] 이거나, 같은 줄에서 닫히는 `[…]` 다.
bool _isReadableRestrictionValue(String rest) {
  final String value = _readYamlValue(rest);
  return value.isEmpty ||
      _isScalarValue(rest) ||
      (value.startsWith('[') && value.endsWith(']'));
}

/// 목록 항목 첫 줄의 `- ` 뒤 [rest] 가 경로 한 줄인지 본다 — [_isScalarValue] 이고,
/// 따옴표 없는 값이면 `키:` 꼴(`: ` 를 담거나 `:` 로 끝남)이 아니다.
bool _isItemPathLine(String rest) {
  if (!_isScalarValue(rest)) {
    return false;
  }
  final String value = _readYamlValue(rest);
  return value.startsWith('"') ||
      value.startsWith("'") ||
      (!value.contains(': ') && !value.endsWith(':'));
}

/// [pubspec] 의 맨 위 `flutter:` 절에서 `assets:` 목록을 줄 단위로 읽는다.
///
/// 들여쓰기는 상대 깊이로 읽는다.
/// - `flutter:` 절은 다음 들여쓰기 0 의 줄(빈 줄 · 주석 줄 제외)에서 끝나고, 그 뒤
///   줄은 읽지 않는다 — 목록 안이나 첫 `- ` 줄 앞이어도 같다.
/// - `flutter:` 절 첫 줄(빈 줄 · 주석 줄 제외)의 들여쓰기가 절의 키다. 그
///   들여쓰기의 값이 빈 `assets:` 줄 앞의 줄(절의 다른 키와 그 내용)은 읽지 않고
///   건너뛴다.
/// - `assets:` 다음 첫 `- ` 줄의 들여쓰기가 목록 항목이다. 절 들여쓰기의 `- `
///   아닌 줄(다음 키 줄)에서 목록이 끝나고, 그 뒤 줄은 읽지 않는다.
/// - 목록 안에서 항목 줄도 목록을 끝내는 줄도 아닌 줄은, 항목보다 깊으면 아래
///   「목록 항목 안」 의 꼴로 읽는다. 아니면(첫 `- ` 줄 앞의 줄 · 항목보다 얕은 줄
///   · 항목 들여쓰기의 `- ` 아닌 줄) 이유 [UnreadableYamlReason.indent] 의
///   `unreadable` 로 돌려준다.
/// - `flutter:` · `assets:` 의 flow 꼴 값은 이유 [UnreadableYamlReason.flow] 의
///   `unreadable` 로 돌려준다.
///
/// 목록 항목 안에서 읽는 꼴은 아래뿐이다.
/// - 항목 첫 줄: `- 경로`([_isItemPathLine])나 `- 키: 값` 이다.
/// - 키 줄: `- ` 뒤 글자 자리(첫 줄의 `- 키: 값` 포함)의 `키: 값` — 키는
///   [_yamlKeyPattern] 꼴이다. `path:` 의 값은 경로([_isScalarValue])다.
/// - 빌드 한정 키(`flavors:` · `platforms:`)의 값: [_isReadableRestrictionValue]
///   다. 빈 값이면 그 아래 키 들여쓰기 이상의 `- 이름` 줄([_isScalarValue])이
///   이름이다.
/// - 그 밖의 키: 그 키보다 깊은 줄과 키 들여쓰기의 목록 줄은 그 키의 내용이라
///   건너뛴다(transformers 목록 등).
///
/// 목록 항목 안의 그 밖의 줄은 그 줄을 말하는
/// `unreadable`(이유 [UnreadableYamlReason.assetItem])로 돌려준다 — 예: 여러 줄에
/// 걸친 `flavors: [`, 따옴표 키 `"flavors":`, 항목 자체가 flow 맵인 `- {path: …}`.
FlutterAssetList readFlutterAssets(String pubspec) {
  final assets = <FlutterAssetEntry>[];
  final List<String> lines = pubspec.split('\n');
  final int start = lines.indexWhere((String line) {
    final String? value = _readTopKeyValue(line, 'flutter');
    return value != null && (value.isEmpty || _isFlowValue(value));
  });
  if (start == -1) {
    return (hasAssets: false, unreadable: null, assets: assets);
  }
  if (_readTopKeyValue(lines[start], 'flutter')!.isNotEmpty) {
    return (
      hasAssets: false,
      unreadable: _unreadableAt(
        lines,
        start,
        reason: UnreadableYamlReason.flow,
      ),
      assets: assets,
    );
  }
  int? sectionIndent;
  int? itemIndent;
  var inAssets = false;
  var hasAssets = false;
  // 지금 항목의 키 들여쓰기 · 경로 · 빌드 한정 키별 이름.
  int? itemKeyIndent;
  String? itemPath;
  var itemNames = <String, List<String>>{};
  // 값이 빈 빌드 한정 키 아래 — 목록 줄이 그 키의 이름이다.
  String? listKey;
  // 마지막 키가 path · 빌드 한정 키가 아닌 그 밖의 키다 — 그 내용을 건너뛴다.
  var inOtherKey = false;

  void addItem() {
    final path = itemPath;
    if (path != null) {
      final bool isBuildRestricted = _isBuildRestricted(
        itemNames['flavors'] ?? const <String>[],
        itemNames['platforms'] ?? const <String>[],
      );
      assets.add((path: path, isBuildRestricted: isBuildRestricted));
    }
    itemPath = null;
    itemNames = <String, List<String>>{};
    listKey = null;
    inOtherKey = false;
  }

  // 항목 키 줄 [text] 를 읽는다 — `키: 값` 꼴이 아니면 null, 값을 읽지 못하면
  // false 다.
  bool? readItemKey(String text) {
    final Match? match = _yamlKeyPattern.firstMatch(text);
    if (match == null) {
      return null;
    }
    final String key = match.group(1)!;
    final String rest = text.substring(match.end);
    final String value = _readYamlValue(rest);
    listKey = null;
    inOtherKey = false;
    if (key == 'path') {
      if (!_isScalarValue(rest)) {
        return false;
      }
      itemPath = _unquote(value);
    } else if (_buildRestrictionKeys.contains(key)) {
      if (!_isReadableRestrictionValue(rest)) {
        return false;
      }
      if (value.isEmpty) {
        listKey = key;
        itemNames[key] = <String>[];
      } else {
        itemNames[key] = _readInlineNames(value);
      }
    } else {
      inOtherKey = true;
    }
    return true;
  }

  // [index] 번째 줄이 목록 항목 안에서 읽는 꼴이 아니다.
  FlutterAssetList unreadableItemAt(int index) => (
    hasAssets: hasAssets,
    unreadable: _unreadableAt(
      lines,
      index,
      reason: UnreadableYamlReason.assetItem,
    ),
    assets: assets,
  );

  for (var i = start + 1; i < lines.length; i++) {
    final String line = lines[i].trimRight();
    final String trimmed = line.trimLeft();
    if (trimmed.isEmpty || trimmed.startsWith('#')) {
      continue;
    }
    final int indent = line.length - trimmed.length;
    if (indent == 0) {
      break;
    }
    sectionIndent ??= indent;
    final bool isListItem = trimmed == '-' || trimmed.startsWith('- ');
    if (indent == sectionIndent && !isListItem) {
      if (inAssets) {
        break;
      }
      final int colon = trimmed.indexOf(':');
      if (colon == -1 || trimmed.substring(0, colon).trim() != 'assets') {
        continue;
      }
      final String value = _readYamlValue(trimmed.substring(colon + 1));
      if (_isFlowValue(value)) {
        return (
          hasAssets: true,
          unreadable: _unreadableAt(
            lines,
            i,
            reason: UnreadableYamlReason.flow,
          ),
          assets: assets,
        );
      }
      if (value.isEmpty) {
        inAssets = true;
        hasAssets = true;
      }
      continue;
    }
    if (!inAssets) {
      // 다른 키의 내용이다.
      continue;
    }
    if (isListItem && (itemIndent == null || indent == itemIndent)) {
      addItem();
      itemIndent = indent;
      final String rest = trimmed.substring(1);
      itemKeyIndent = indent + 1 + rest.length - rest.trimLeft().length;
      final bool? isKeyRead = readItemKey(rest.trim());
      if (isKeyRead == false) {
        return unreadableItemAt(i);
      }
      if (isKeyRead == null) {
        if (!_isItemPathLine(rest)) {
          return unreadableItemAt(i);
        }
        itemPath = _unquote(_readYamlValue(rest));
      }
      continue;
    }
    if (itemIndent != null && indent > itemIndent) {
      final int keyIndent = itemKeyIndent!;
      final namesKey = listKey;
      if (indent == keyIndent && !isListItem) {
        if (readItemKey(trimmed) ?? false) {
          continue;
        }
      } else if (namesKey != null && isListItem && indent >= keyIndent) {
        final String nameRest = trimmed.substring(1);
        if (_isScalarValue(nameRest)) {
          itemNames[namesKey]!.add(_unquote(_readYamlValue(nameRest)));
          continue;
        }
      } else if (inOtherKey &&
          (indent > keyIndent || (isListItem && indent == keyIndent))) {
        continue;
      }
      return unreadableItemAt(i);
    }
    return (
      hasAssets: hasAssets,
      unreadable: _unreadableAt(lines, i),
      assets: assets,
    );
  }
  addItem();
  return (hasAssets: hasAssets, unreadable: null, assets: assets);
}

/// `pubspec.yaml` 의 읽지 못한 줄 [unreadable] 메시지를 만든다.
String _buildPubspecUnreadableMessage(UnreadableYamlLine unreadable) =>
    _buildUnreadableMessage(
      _pubspecPath,
      unreadable,
      indentScope: 'flutter: assets: ',
      indentHint: '목록 항목은 모두 같은 들여쓰기의 「- 경로」 줄로 적는다.',
    );

/// 자산 키 [path] 가 [assets] 목록에 들어가는지 본다 — 같은 파일 항목이거나,
/// `/` 로 끝나는 디렉터리 항목의 바로 아래 파일이다(하위 디렉터리는 따로
/// 선언해야 한다).
bool _isBundledAsset(String path, List<String> assets) => assets.any(
  (String entry) =>
      entry == path ||
      (entry.endsWith('/') &&
          path.startsWith(entry) &&
          !path.substring(entry.length).contains('/')),
);

/// [path] 파일의 실제 경로를 마지막 경로 조각의 대소문자까지 돌려준다 — 없으면
/// null 이다.
///
/// 파일 시스템에 묻지 않고 부모 디렉터리 목록의 이름과 글자 그대로 비교한다 —
/// macOS 파일 시스템은 이름의 대소문자를 무시하므로 `File.existsSync` 는 대소문자가
/// 틀린 이름에도 참이지만, 번들 자산 키는 대소문자를 구분한다. 글자 그대로 같은
/// 이름이 없고 대소문자만 다른 이름이 있으면 그 이름으로 바꾼 경로를 돌려준다.
String? findActualPath(String path) {
  final int slash = path.lastIndexOf('/');
  final String name = path.substring(slash + 1);
  final directory = Directory(slash == -1 ? '.' : path.substring(0, slash));
  if (name.isEmpty || !directory.existsSync()) {
    return null;
  }
  final names = <String>[
    for (final FileSystemEntity entity in directory.listSync())
      if (entity is File)
        entity.path.substring(
          entity.path.lastIndexOf(Platform.pathSeparator) + 1,
        ),
  ];
  if (names.contains(name)) {
    return path;
  }
  final String lowerName = name.toLowerCase();
  for (final actualName in names) {
    if (actualName.toLowerCase() == lowerName) {
      return '${path.substring(0, slash + 1)}$actualName';
    }
  }
  return null;
}

/// 로고 경로 상수(이름 → 경로) [logos] 가 번들 자산인지 [pubspec] ·
/// [resolveActualPath] 로 대조해 어긋남 메시지를 돌려준다.
///
/// 네이티브 스플래시 생성기는 파일 시스템에서 경로를 읽지만 Flutter 스플래시는
/// `pubspec.yaml` 의 `flutter: assets:` 에 등록된 자산만 읽는다 — 등록이 빠지면
/// 네이티브 스플래시에만 로고가 보인다. [resolveActualPath] 는 [findActualPath]
/// 꼴로 실제 경로(없으면 null)를 돌려준다. 빈 목록이면 통과다.
List<String> findLogoAssetMismatches(
  String pubspec, {
  required Map<String, String> logos,
  required String? Function(String path) resolveActualPath,
}) {
  final FlutterAssetList list = readFlutterAssets(pubspec);
  final UnreadableYamlLine? unreadable = list.unreadable;
  if (unreadable != null) {
    return <String>[_buildPubspecUnreadableMessage(unreadable)];
  }
  // 대조 시험이 읽는 yaml 은 모든 flavor · 플랫폼 공통이므로 로고는 모든 킷
  // 빌드에 실려야 한다 — 빌드를 한정하지 않은 항목만 등록으로 본다.
  final plainAssets = <String>[
    for (final FlutterAssetEntry entry in list.assets)
      if (!entry.isBuildRestricted) entry.path,
  ];
  final restrictedAssets = <String>[
    for (final FlutterAssetEntry entry in list.assets)
      if (entry.isBuildRestricted) entry.path,
  ];
  final messages = <String>[];
  for (final MapEntry<String, String> logo in logos.entries) {
    final String constName = logo.key;
    final String path = logo.value;
    if (path.startsWith('./')) {
      messages.add(
        _buildMessage(
          '$_bodyPath 의 $constName 는 $path 다 — 자산 키는 ./ 없이 적는다(yaml '
          '도 같은 값으로 고친다): '
          "const String $constName = '${path.substring(2)}';",
        ),
      );
      continue;
    }
    final String? actualPath = resolveActualPath(path);
    if (actualPath == null) {
      messages.add(
        _buildMessage(
          '$_bodyPath 의 $constName 인 $path 파일이 없다 — 로고 그림을 그 경로에 '
          '둔다.',
        ),
      );
    } else if (actualPath != path) {
      final String actualName = actualPath.substring(
        actualPath.lastIndexOf('/') + 1,
      );
      messages.add(
        _buildMessage(
          '$_bodyPath 의 $constName 인 $path 는 파일 이름의 대소문자가 실제 '
          '파일($actualName)과 다르다 — 번들 자산 키는 대소문자를 구분한다.\n'
          '상수와 yaml 을 실제 이름으로 고친다: '
          "const String $constName = '$actualPath';",
        ),
      );
    }
    if (_isBundledAsset(path, plainAssets)) {
      continue;
    }
    if (_isBundledAsset(path, restrictedAssets)) {
      messages.add(
        _buildMessage(
          '$_bodyPath 의 $constName 인 $path 는 $_pubspecPath 의 flutter: '
          'assets: 에서 빌드를 한정한 항목에만 있다 — flavors: 로 한정한 항목은 '
          '다른 flavor 빌드에, platforms: 로 한정한 항목은 다른 플랫폼 빌드에 '
          '실리지 않는다.\n'
          'flavors: 없이, platforms: 는 없거나 android · ios 를 모두 담은 '
          '항목으로 등록한다(그 파일이나 그 파일이 든 디렉터리, 끝에 /).',
        ),
      );
    } else {
      messages.add(
        _buildMessage(
          '$_bodyPath 의 $constName 인 $path 가 $_pubspecPath 의 flutter: '
          'assets: 에 없다 — Flutter 스플래시는 등록된 자산만 읽으므로 로고가 '
          '비어 보인다.\n'
          'assets: 에 그 파일이나 그 파일이 든 디렉터리(끝에 /)를 더한다.',
        ),
      );
    }
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
      final UnreadableYamlLine? unreadable = blocks.unreadable;
      expect(
        unreadable,
        isNull,
        reason: unreadable == null
            ? null
            : _buildSplashUnreadableMessage(unreadable),
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
      expect(blocks.unreadable, isNull);
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

    test('T-26-YAML-11: 들여쓰기는 칸 수가 아니라 상대 깊이로 읽고, 읽지 못한 '
        '줄은 그 줄을 말하는 메시지 하나로 실패', () {
      // 파일 전체 4칸 · 머리 줄 끝 주석 · android_12 아래 6칸(4칸 + 2) — 킷 값과
      // 같으므로 통과한다.
      const fourSpace =
          'flutter_native_splash: # 네이티브 스플래시 설정\n'
          '    color: "#FFFFFF"\n'
          '    color_dark: "#000000"\n'
          '    image: $_logo\n'
          '    image_dark: $_logoDark\n'
          '    android_12:\n'
          '      image: $_logo\n'
          '      image_dark: $_logoDark\n'
          '      color: "#FFFFFF"\n'
          '    web: false\n';
      final SplashYamlBlocks fourBlocks = readSplashYaml(fourSpace);
      expect(fourBlocks.hasBlock, isTrue);
      expect(fourBlocks.unreadable, isNull);
      expect(fourBlocks.hasAndroid12, isTrue);
      expect(fourBlocks.top['color'], '"#FFFFFF"');
      expect(fourBlocks.android12['color'], '"#FFFFFF"');
      expect(_findFixtureMismatches(fourSpace), isEmpty);

      // android_12 아래를 6칸으로 들여 써도 그 블록의 값으로 읽어 대조한다.
      final List<String> sixSpace = _findFixtureMismatches(
        _buildSplashYaml(
          android12Images:
              '      image: $_logo\n'
              '      image_dark: $_logoDark\n',
          android12Colors: '      color: "#123456"\n',
        ),
      );
      expect(sixSpace, hasLength(1), reason: sixSpace.join('\n\n'));
      expect(
        sixSpace.single,
        startsWith('android_12.color 는 #123456 인데 color 는 #FFFFFF 다'),
      );

      // 값이 빈 다른 top 키 아래 목록(더 깊게 · 같은 깊이)은 건너뛴다.
      expect(
        _findFixtureMismatches(
          _buildSplashYaml(
            topExtra:
                '  info_plist_files:\n'
                "    - 'ios/Runner/Info-Debug.plist'\n"
                '  ios_extra_list:\n'
                "  - 'ios/Runner/Info-Release.plist'\n",
          ),
        ),
        isEmpty,
      );

      // android_12 안에서 들여쓰기가 섞이면 그 줄을 말하고 값 메시지는 내지 않는다.
      final List<String> mixed = _findFixtureMismatches(
        _buildSplashYaml(
          android12Colors:
              '    color: "#FFFFFF"\n'
              '      color_dark: "#000000"\n',
        ),
      );
      expect(mixed, hasLength(1), reason: mixed.join('\n\n'));
      expect(
        mixed.single,
        allOf(<Matcher>[
          contains('들여쓰기를 읽지 못했다'),
          contains('「color_dark: "#000000"」'),
          isNot(contains('따옴표')),
          contains('스플래시 바꾸기'),
        ]),
      );

      // top 키보다 얕은 줄도 읽지 못한 줄이다.
      final List<String> shallow = _findFixtureMismatches(
        fourSpace.replaceFirst('    web: false\n', '  web: false\n'),
      );
      expect(shallow, hasLength(1), reason: shallow.join('\n\n'));
      expect(shallow.single, contains('「web: false」'));

      // 블록으로 읽을 키의 flow 꼴 값은 그 줄을 말하는 메시지 하나로 실패한다 —
      // 블록 · 값이 없다고 말하지 않는다.
      const flowAndroid12 =
          '  android_12: {image: $_logo, image_dark: $_logoDark}\n';
      final List<String> flowBlock = _findFixtureMismatches(
        _buildSplashYaml(
          android12Images: '',
          android12Colors: '',
        ).replaceFirst('  android_12:\n', flowAndroid12),
      );
      expect(flowBlock, hasLength(1), reason: flowBlock.join('\n\n'));
      expect(
        flowBlock.single,
        allOf(<Matcher>[
          contains('「${flowAndroid12.trim()}」 을 읽지 못했다'),
          contains('flow 꼴({…} · […])은 읽지 않는다 — 블록 꼴로 적는다'),
          isNot(contains('들여쓰기')),
          isNot(contains('값이 없다')),
          contains('스플래시 바꾸기'),
        ]),
      );
      final SplashYamlBlocks flowHead = readSplashYaml(
        'flutter_native_splash: {color: "#FFFFFF"}\n',
      );
      expect(flowHead.hasBlock, isTrue);
      expect(flowHead.unreadable?.reason, UnreadableYamlReason.flow);
      expect(
        _findFixtureMismatches('flutter_native_splash: {color: "#FFFFFF"}\n'),
        <Matcher>[
          contains('1번째 줄 「flutter_native_splash: {color: "#FFFFFF"}」'),
        ],
      );

      // 대조와 무관한 키의 한 줄 flow 값은 읽지 않고 지나간다.
      expect(
        _findFixtureMismatches(
          _buildSplashYaml(
            topExtra: "  info_plist_files: ['ios/Runner/Info-Debug.plist']\n",
          ),
        ),
        isEmpty,
      );
    });

    test('T-26-YAML-12: 저장소 로고 경로 상수는 파일이 있고 pubspec.yaml 의 '
        'flutter: assets: 에 등록된 번들 자산이다', () {
      final String pubspec = readTrackedFile(_pubspecPath);
      final FlutterAssetList list = readFlutterAssets(pubspec);
      final UnreadableYamlLine? unreadable = list.unreadable;
      expect(
        unreadable,
        isNull,
        reason: unreadable == null
            ? null
            : _buildPubspecUnreadableMessage(unreadable),
      );
      // 양성 대조 — 목록을 실제로 읽었다.
      expect(
        list.hasAssets,
        isTrue,
        reason: '$_pubspecPath 에 flutter: assets: 가 없다',
      );
      expect(list.assets, isNotEmpty);
      final List<String> messages = findLogoAssetMismatches(
        pubspec,
        logos: <String, String>{
          'kSplashImage': kSplashImage,
          'kSplashImageDark': kSplashImageDark,
        },
        resolveActualPath: findActualPath,
      );
      expect(messages, isEmpty, reason: messages.join('\n\n'));
    });

    test('T-26-YAML-13: 등록되지 않은 디렉터리 · 하위 디렉터리 · ./ · 없는 파일 · '
        'flavors: · platforms: 로 빌드를 한정한 항목은 실패 · 파일 항목 · 빌드를 '
        '한정하지 않은 path: 항목은 통과', () {
      const pubspec =
          'name: app\n'
          'flutter:\n'
          '  uses-material-design: true\n'
          '  fonts:\n'
          '    - family: Sample\n'
          '      fonts:\n'
          '        - asset: assets/fonts/sample.ttf\n'
          '  assets:\n'
          '    - assets/images/splash/ # 스플래시 로고\n'
          '    # 주석 줄은 항목이 아니다\n'
          '    - "assets/brand/logo_file.png"\n'
          '    - path: assets/flavor/\n'
          '      flavors:\n'
          '        - dev\n'
          '    - path: assets/flavor_flow/\n'
          '      flavors: [dev, stg]\n'
          '    - flavors:\n'
          '      - prod\n'
          '      path: assets/flavor_first/\n'
          '    - path: assets/plain_path/ # flavors 없는 path 항목\n'
          '      transformers:\n'
          '        - package: sample_transformer\n'
          '    - path: assets/empty_flavors/\n'
          '      flavors: []\n'
          '    - path: assets/platform_block/\n'
          '      platforms:\n'
          '        - android\n'
          '    - path: assets/platform_flow/\n'
          '      platforms: [ios]\n'
          '    - path: assets/flavor_platform/\n'
          '      flavors: [dev]\n'
          '      platforms: [android]\n'
          '    - path: assets/empty_platforms/\n'
          '      platforms: []\n'
          '    - path: assets/mobile_platforms/\n'
          '      platforms:\n'
          '        - android\n'
          '        - "ios"\n'
          '  generate: true\n';
      // 파일은 모두 그 이름 그대로 있다고 본다 — 파일 판정은 아래 따로 본다.
      String resolveSame(String path) => path;
      List<String> check(String path) => findLogoAssetMismatches(
        pubspec,
        logos: <String, String>{'kSplashImage': path},
        resolveActualPath: resolveSame,
      );

      final FlutterAssetList list = readFlutterAssets(pubspec);
      expect(list.unreadable, isNull);
      expect(list.assets, <FlutterAssetEntry>[
        (path: 'assets/images/splash/', isBuildRestricted: false),
        (path: 'assets/brand/logo_file.png', isBuildRestricted: false),
        (path: 'assets/flavor/', isBuildRestricted: true),
        (path: 'assets/flavor_flow/', isBuildRestricted: true),
        (path: 'assets/flavor_first/', isBuildRestricted: true),
        (path: 'assets/plain_path/', isBuildRestricted: false),
        (path: 'assets/empty_flavors/', isBuildRestricted: false),
        (path: 'assets/platform_block/', isBuildRestricted: true),
        (path: 'assets/platform_flow/', isBuildRestricted: true),
        (path: 'assets/flavor_platform/', isBuildRestricted: true),
        (path: 'assets/empty_platforms/', isBuildRestricted: false),
        (path: 'assets/mobile_platforms/', isBuildRestricted: false),
      ]);
      expect(check(_logo), isEmpty);
      expect(check('assets/brand/logo_file.png'), isEmpty);
      expect(check('assets/plain_path/logo.png'), isEmpty);
      // 빈 목록은 이름이 없어 모든 빌드에 실린다.
      expect(check('assets/empty_flavors/logo.png'), isEmpty);
      expect(check('assets/empty_platforms/logo.png'), isEmpty);
      // 킷 플랫폼(android · ios)을 모두 담은 platforms: 는 킷 빌드를 한정하지
      // 않는다.
      expect(check('assets/mobile_platforms/logo.png'), isEmpty);

      // 빌드를 한정한 항목(flavors: 목록 줄 · 한 줄 값 · path 앞 키, platforms:
      // 목록 줄 · 한 줄 값, 둘 다)에만 있으면 실패한다.
      for (final restrictedDirectory in <String>[
        'assets/flavor/',
        'assets/flavor_flow/',
        'assets/flavor_first/',
        'assets/platform_block/',
        'assets/platform_flow/',
        'assets/flavor_platform/',
      ]) {
        final List<String> restricted = check('${restrictedDirectory}logo.png');
        expect(restricted, hasLength(1), reason: restricted.join('\n\n'));
        expect(
          restricted.single,
          allOf(<Matcher>[
            contains(
              'kSplashImage 인 ${restrictedDirectory}logo.png 는 pubspec.yaml 의 '
              'flutter: assets: 에서 빌드를 한정한 항목에만 있다',
            ),
            contains('다른 flavor 빌드에'),
            contains('다른 플랫폼 빌드에 실리지 않는다'),
            contains('flavors: 없이, platforms: 는 없거나 android · ios 를 모두'),
            isNot(contains('flow 꼴')),
            contains('스플래시 바꾸기'),
          ]),
        );
      }

      final List<String> unregistered = check('assets/brand/logo.png');
      expect(unregistered, hasLength(1), reason: unregistered.join('\n\n'));
      expect(
        unregistered.single,
        allOf(<Matcher>[
          contains(
            'kSplashImage 인 assets/brand/logo.png 가 pubspec.yaml 의 '
            'flutter: assets: 에 없다',
          ),
          contains('스플래시 바꾸기'),
        ]),
      );
      expect(
        check('assets/images/splash/sub/logo.png').single,
        contains('flutter: assets: 에 없다'),
      );
      expect(
        check('./$_logo').single,
        allOf(<Matcher>[
          contains('./ 없이 적는다'),
          contains("const String kSplashImage = '$_logo';"),
        ]),
      );
      final List<String> missing = findLogoAssetMismatches(
        pubspec,
        logos: <String, String>{'kSplashImageDark': _logoDark},
        resolveActualPath: (String _) => null,
      );
      expect(missing, hasLength(1), reason: missing.join('\n\n'));
      expect(missing.single, contains('$_logoDark 파일이 없다'));

      // 목록 들여쓰기가 섞이면 그 줄을 말하는 메시지 하나로 실패한다.
      final List<String> mixed = findLogoAssetMismatches(
        pubspec.replaceFirst(
          '    - "assets/brand/logo_file.png"\n',
          '   - "assets/brand/logo_file.png"\n',
        ),
        logos: <String, String>{'kSplashImage': _logo},
        resolveActualPath: resolveSame,
      );
      expect(mixed, hasLength(1), reason: mixed.join('\n\n'));
      expect(mixed.single, contains('들여쓰기를 읽지 못했다'));

      // flutter: · assets: 의 flow 꼴 값은 그 줄을 말하는 메시지 하나로 실패한다
      // — assets: 가 없다고 말하지 않는다.
      List<String> checkPubspec(String text) => findLogoAssetMismatches(
        text,
        logos: <String, String>{'kSplashImage': _logo},
        resolveActualPath: resolveSame,
      );
      const flowAssets =
          'name: app\n'
          'flutter:\n'
          '  uses-material-design: true\n'
          '  assets: [assets/images/splash/]\n';
      expect(
        readFlutterAssets(flowAssets).unreadable?.reason,
        UnreadableYamlReason.flow,
      );
      final List<String> flowList = checkPubspec(flowAssets);
      expect(flowList, hasLength(1), reason: flowList.join('\n\n'));
      expect(
        flowList.single,
        allOf(<Matcher>[
          contains('4번째 줄 「assets: [assets/images/splash/]」 을 읽지 못했다'),
          contains('flow 꼴({…} · […])은 읽지 않는다 — 블록 꼴로 적는다'),
          isNot(contains('에 없다')),
          contains('스플래시 바꾸기'),
        ]),
      );
      expect(
        checkPubspec('flutter: {assets: [assets/images/splash/]}\n'),
        <Matcher>[
          contains('1번째 줄 「flutter: {assets: [assets/images/splash/]}」'),
        ],
      );

      // assets: 목록 항목 안에서 읽는 꼴 밖의 줄은 그 줄을 말하는 메시지 하나로
      // 실패한다 — 빌드를 한정했다고도, assets: 에 없다고도 말하지 않는다.
      String assetsPubspec(String items) =>
          'name: app\n'
          'flutter:\n'
          '  uses-material-design: true\n'
          '  assets:\n'
          '$items'
          '  generate: true\n';
      const pathLine = '    - path: assets/images/splash/\n';
      String itemPubspec(String item) => assetsPubspec('$pathLine$item');
      // 목록 항목 줄 → 메시지가 말해야 할 줄.
      const unreadableItems = <String, String>{
        // 빌드 한정 키의 같은 줄에서 닫히지 않는 flow 값.
        '$pathLine      flavors: [\n        dev\n      ]\n': 'flavors: [',
        '$pathLine      platforms: [android,\n        ios]\n':
            'platforms: [android,',
        // 빌드 한정 키의 같은 줄 값이 태그로 시작한다.
        '$pathLine      flavors: !!seq [dev]\n': 'flavors: !!seq [dev]',
        // 값이 빈 빌드 한정 키 아래 「- 이름」 이 아닌 줄 · 이름이 flow 꼴인 줄.
        '$pathLine      flavors:\n        [dev]\n': '[dev]',
        '$pathLine      flavors:\n        - [dev]\n': '- [dev]',
        // 항목 키 들여쓰기에서 알아보지 못한 줄(따옴표 키 · 콜론 앞 공백).
        '$pathLine      "flavors": [dev]\n': '"flavors": [dev]',
        '$pathLine      flavors : [dev]\n': 'flavors : [dev]',
        // 항목 첫 줄이 flow 맵 · 빈 값 · 따옴표 키 — 유효한 등록이어도 경로로
        // 읽지 않는다.
        '    - {path: assets/images/splash/}\n':
            '- {path: assets/images/splash/}',
        '    -\n      path: assets/images/splash/\n': '-',
        '    - "path": assets/images/splash/\n':
            '- "path": assets/images/splash/',
        // 항목 첫 줄이 콜론 앞 공백 키 · 값이 빈 path: 다.
        '    - path : assets/images/splash/\n':
            '- path : assets/images/splash/',
        '    - path:\n      flavors: [dev]\n': '- path:',
        // 항목 첫 줄이 목록 표시로 시작한다(항목이 목록이다).
        '    - - assets/images/splash/\n': '- - assets/images/splash/',
        // 따옴표 값의 닫는 따옴표 뒤에 주석 아닌 글자가 있다 — path: 값(첫 줄 ·
        // 키 줄) · 빌드 한정 키의 같은 줄 값 · 이름 줄.
        "    - path: 'assets/images/splash/''old/'\n":
            "- path: 'assets/images/splash/''old/'",
        "    - flavors: []\n      path: 'assets/images/splash/''old/'\n":
            "path: 'assets/images/splash/''old/'",
        '    - path: "assets/images/splash/" junk\n':
            '- path: "assets/images/splash/" junk',
        '$pathLine      flavors: "dev" junk\n': 'flavors: "dev" junk',
        '$pathLine      platforms:\n        - "android" x\n        - ios\n':
            '- "android" x',
        // 따옴표 하나뿐인 값 · 닫히지 않는 따옴표 값(첫 줄 「- 경로」 · path: 값).
        '    - "\n': '- "',
        '    - "assets/images/splash/\n': '- "assets/images/splash/',
        '    - path: "assets/images/splash/\n':
            '- path: "assets/images/splash/',
        // 항목 첫 줄이 「:」 로 끝나는 키 꼴 · 복합 키 표시로 시작한다.
        '    - path :\n': '- path :',
        '    - ? path\n      : assets/images/splash/\n': '- ? path',
      };
      // 빌드 한정 키의 같은 줄 값이 YAML 표시 글자로 시작한다 — 표시 글자마다
      // 하나(flow · 태그 · 앵커 · 별칭 · 블록 스칼라 · 예약 글자 · 뒤에 공백이 오는
      // 복합 키 · 값 · 목록 표시).
      const indicatorValues = <String>[
        '{dev: 1}',
        '[dev',
        '!dev',
        '&a',
        '*a',
        '|',
        '>',
        '%dev',
        '@dev',
        '`dev`',
        '? dev',
        ': dev',
        '- dev',
      ];
      final unreadableSamples = <String, String>{
        ...unreadableItems,
        for (final indicatorValue in indicatorValues)
          '$pathLine      flavors: $indicatorValue\n':
              'flavors: $indicatorValue',
      };
      for (final MapEntry<String, String> sample in unreadableSamples.entries) {
        final String text = assetsPubspec(sample.key);
        expect(
          readFlutterAssets(text).unreadable?.reason,
          UnreadableYamlReason.assetItem,
          reason: sample.value,
        );
        final List<String> itemList = checkPubspec(text);
        expect(itemList, hasLength(1), reason: itemList.join('\n\n'));
        expect(
          itemList.single,
          allOf(<Matcher>[
            contains(
              '「${sample.value}」 을 읽지 못했다 — flutter: assets: 목록 항목에서 '
              '읽는 꼴이 아니다',
            ),
            isNot(contains('한정한 항목에만')),
            isNot(contains('에 없다')),
            isNot(contains('flow 꼴')),
            contains(r'따옴표로 감싼 값 안에는 같은 따옴표와 \ 를 쓰지 않으며'),
            contains('스플래시 바꾸기'),
          ]),
        );
      }
      // 대조군 — 읽는 꼴의 같은 내용은 그대로 읽는다.
      expect(
        checkPubspec(itemPubspec('      platforms: [android, ios] # 둘 다\n')),
        isEmpty,
      );
      // 따옴표 값 뒤의 끝 주석은 값이 아니고, 따옴표 안의 「공백 + #」 은 값이다
      // — 항목 첫 줄과 키 줄이 같은 값을 읽는다.
      for (final quotedItem in <String>[
        '    - "assets/images/splash/" # c\n',
        '    - path: "assets/images/splash/" # c\n',
        '    - flavors: []\n      path: "assets/images/splash/" # c\n',
      ]) {
        expect(checkPubspec(assetsPubspec(quotedItem)), isEmpty);
      }
      for (final quotedItem in <String>[
        '    - path: "assets/images/splash/ #x/"\n',
        '    - flavors: []\n      path: "assets/images/splash/ #x/"\n',
      ]) {
        expect(
          readFlutterAssets(assetsPubspec(quotedItem)).assets,
          <FlutterAssetEntry>[
            (path: 'assets/images/splash/ #x/', isBuildRestricted: false),
          ],
        );
      }
      // 따옴표 값은 「: 」 를 담아도 키 꼴이 아니라 경로다.
      for (final quotedPath in <String>[
        '    - "assets/a: b/"\n',
        "    - 'assets/a: b/'\n",
      ]) {
        expect(
          readFlutterAssets(assetsPubspec(quotedPath)).assets,
          <FlutterAssetEntry>[(path: 'assets/a: b/', isBuildRestricted: false)],
        );
      }
      // 빌드 한정 키의 null · ~ 는 이름이 없어 모든 빌드에 실린다.
      for (final unnamedItem in <String>[
        '      flavors: null\n',
        '      platforms: ~\n',
      ]) {
        expect(checkPubspec(itemPubspec(unnamedItem)), isEmpty);
      }
      for (final restrictedItem in <String>[
        // 한 줄 스칼라 값도 이름으로 읽는다.
        '      flavors: dev\n',
        '      flavors: [dev] # 끝 주석\n',
        '      flavors:\n        - dev\n',
        '      flavors:\n      - dev\n',
      ]) {
        final List<String> restricted = checkPubspec(
          itemPubspec(restrictedItem),
        );
        expect(restricted, hasLength(1), reason: restricted.join('\n\n'));
        expect(restricted.single, contains('빌드를 한정한 항목에만 있다'));
      }
      // 그 밖의 키(transformers)의 내용은 건너뛴다 — 깊은 줄 · compact 목록.
      const nestedTransformers =
          '      transformers:\n'
          '        - package: vector_graphics_compiler\n'
          "          args: ['--tessellate']\n";
      for (final transformers in <String>[
        nestedTransformers,
        '      transformers:\n      - package: sample_transformer\n',
      ]) {
        expect(checkPubspec(itemPubspec(transformers)), isEmpty);
      }

      // assets: 앞 절의 다른 키의 flow 값은 읽지 않고 건너뛴다.
      expect(
        checkPubspec(
          pubspec.replaceFirst(
            '  assets:\n',
            '  config: {enable-web: false}\n  assets:\n',
          ),
        ),
        isEmpty,
      );
    });

    test('T-26-YAML-14: 로고 파일은 이름의 대소문자까지 실제 파일과 같아야 '
        '통과 — 대소문자를 무시하는 파일 시스템에서도 실패', () {
      // 실제 디렉터리에 logo.png 를 두고 판정한다 — 저장소 로고와 무관하다.
      final Directory directory = Directory.systemTemp.createTempSync(
        'splash_logo_case_',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      File('${directory.path}/logo.png').writeAsBytesSync(const <int>[]);
      final base = '${directory.path}/';
      final pubspec =
          'name: app\n'
          'flutter:\n'
          '  assets:\n'
          '    - $base\n';
      List<String> check(String path) => findLogoAssetMismatches(
        pubspec,
        logos: <String, String>{'kSplashImage': path},
        resolveActualPath: findActualPath,
      );

      expect(findActualPath('${base}logo.png'), '${base}logo.png');
      expect(findActualPath('${base}LOGO.PNG'), '${base}logo.png');
      expect(findActualPath('${base}none.png'), isNull);
      expect(findActualPath('${base}missing/logo.png'), isNull);

      expect(check('${base}logo.png'), isEmpty);
      final List<String> upper = check('${base}LOGO.PNG');
      expect(upper, hasLength(1), reason: upper.join('\n\n'));
      expect(
        upper.single,
        allOf(<Matcher>[
          contains('${base}LOGO.PNG 는 파일 이름의 대소문자가 실제 파일(logo.png)과 다르다'),
          contains('번들 자산 키는 대소문자를 구분한다'),
          contains("const String kSplashImage = '${base}logo.png';"),
          contains('스플래시 바꾸기'),
        ]),
      );
      final List<String> none = check('${base}none.png');
      expect(none, hasLength(1), reason: none.join('\n\n'));
      expect(none.single, contains('${base}none.png 파일이 없다'));
    });
  });
}
