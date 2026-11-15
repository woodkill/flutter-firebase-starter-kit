// 홈 화면 앱 아이콘 규격 표(`tool/setup/icons/home_icon_specs.dart`)의 모양 ·
// adaptive 파일 원문 · 승인 상수 범위를 고정한다.
//
// 표 지문과 저장소 아이콘 바이트 대조는 킷 유지보수자 트리에서만 돈다 — 킷을 받은
// 저장소(adopter 트리)는 자기 아이콘을 쓴다.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import '../../../tool/setup/icons/home_icon_specs.dart';
import '../../../tool/setup/icons/icon_pipeline.dart' show filledIconSide;
import '../../../tool/setup/providers/icon_specs.dart' show maxSourceSide;
import '../../helpers/planning_docs.dart';

/// Android legacy 아이콘 다섯 밀도의 한 변(px) — mdpi ~ xxxhdpi 순서.
const List<int> androidLegacySides = <int>[48, 72, 96, 144, 192];

/// 승인판 후보 dp — 상수는 이 가운데 하나여야 한다.
const List<double> candidateDps = <double>[73.44, 72, 66, 48];

/// `Contents.json` 의 `images` 를 파일 이름 → 한 변(px) 맵으로 읽는다.
///
/// 한 변 = `size` 의 앞 숫자 × `scale` 의 배율이다. 같은 파일을 두 idiom 이 쓰면
/// 한 항목으로 모인다.
Map<String, int> readContentsSides() {
  final Object? decoded = jsonDecode(
    File('$iosAppIconDirectory/Contents.json').readAsStringSync(),
  );
  final sides = <String, int>{};
  if (decoded case {'images': final List<Object?> images}) {
    for (final image in images) {
      if (image case {
        'filename': final String fileName,
        'size': final String size,
        'scale': final String scale,
      }) {
        final double point = double.parse(size.split('x').first);
        final int factor = int.parse(scale.replaceAll('x', ''));
        sides[fileName] = (point * factor).round();
      }
    }
  }
  return sides;
}

void main() {
  test('T-28-SPEC-01: 홈 화면 아이콘 표는 iOS 15 · Android 5 행이고 크기가 규격과 같다', () {
    final Map<String, int> contentsSides = readContentsSides();
    final List<HomeIconFile> iosFiles = homeIconFiles
        .where(
          (HomeIconFile file) =>
              file.relativePath.startsWith('$iosAppIconDirectory/'),
        )
        .toList();
    final List<HomeIconFile> androidFiles = homeIconFiles
        .where(
          (HomeIconFile file) =>
              file.relativePath.startsWith('$androidResDirectory/'),
        )
        .toList();

    expect(homeIconFiles, hasLength(20));
    expect(contentsSides, hasLength(15));
    expect(iosFiles, hasLength(15));
    expect(<String, int>{
      for (final HomeIconFile file in iosFiles)
        file.relativePath.split('/').last: file.side,
    }, contentsSides);
    expect(
      androidFiles.map((HomeIconFile file) => file.side).toList(),
      androidLegacySides,
    );
    for (final file in androidFiles) {
      expect(
        file.relativePath,
        matches(RegExp(r'/mipmap-[a-z]+dpi/ic_launcher\.png$')),
      );
    }
    expect(
      homeIconFiles.map((HomeIconFile file) => file.relativePath).toSet(),
      hasLength(20),
    );
    expect(
      homeIconFiles.map((HomeIconFile file) => file.relativePath),
      contains(ios1024Path),
    );
    for (final HomeIconFile file in homeIconFiles) {
      expect(file.kitDigest, matches(RegExp(r'^[0-9a-f]{64}$')));
    }
    expect(buildKitDefaultDigests(), hasLength(20));
  });

  test('T-28-SPEC-02: 표의 킷 기본 지문이 저장소 아이콘 바이트의 sha256 과 같다', () {
    final Map<String, String> digests = buildKitDefaultDigests();

    expect(digests, hasLength(20));
    for (final MapEntry<String, String> entry in digests.entries) {
      final List<int> bytes = File(entry.key).readAsBytesSync();
      expect(sha256.convert(bytes).toString(), entry.value, reason: entry.key);
    }
  }, skip: skipUnlessMaintainerTree());

  test('T-28-SPEC-03: adaptive 파일 7개의 경로 순서와 XML 원문', () {
    expect(listAdaptiveFilePaths(), <String>[
      'android/app/src/main/res/mipmap-mdpi/ic_launcher_foreground.png',
      'android/app/src/main/res/mipmap-hdpi/ic_launcher_foreground.png',
      'android/app/src/main/res/mipmap-xhdpi/ic_launcher_foreground.png',
      'android/app/src/main/res/mipmap-xxhdpi/ic_launcher_foreground.png',
      'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_foreground.png',
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
      'android/app/src/main/res/values/ic_launcher_background.xml',
    ]);
    expect(
      adaptiveDensities.map((AdaptiveDensity density) => density.canvasSide),
      <int>[108, 162, 216, 324, 432],
    );
    expect(
      buildAdaptiveIconXml(),
      '<?xml version="1.0" encoding="utf-8"?>\n'
      '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
      '    <background android:drawable="@color/ic_launcher_background" />\n'
      '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
      '</adaptive-icon>\n',
    );
    expect(
      buildAdaptiveBackgroundXml(0x1A2B3C),
      '<?xml version="1.0" encoding="utf-8"?>\n'
      '<resources>\n'
      '    <color name="ic_launcher_background">#1A2B3C</color>\n'
      '</resources>\n',
    );
  });

  test('T-28-SPEC-04: 승인 상수는 후보 안 · 기본 배경 흰색 · 표식 이름 · 원본 상한', () {
    expect(candidateDps, contains(logoForegroundDp));
    expect(candidateDps, contains(paintedForegroundDp));
    expect(PaintedBackground.values, contains(paintedBackground));
    expect(defaultBackgroundRgb, 0xFFFFFF);
    expect(homeIconMarkerName.startsWith('source.'), isFalse);
    expect(homeIconMarkerPath, '.setup/icons/$homeIconMarkerName');
    expect(maxSourceSide, 16384);
    expect(filledIconSide, 1024);
  });
}
