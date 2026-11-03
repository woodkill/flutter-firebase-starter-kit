// 앱 글꼴을 golden 하네스 · 계약 시험에 올리는 공용 헬퍼.
//
// 테마 글꼴(`AppTheme.fontFamily`)의 파일 경로와 등록 함수를 한 곳에 둔다.
// 앱 글꼴을 바꾸면 이 파일의 경로를 함께 고친다 — pubspec 의 asset 경로와
// 같아야 한다.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_starter_kit/core/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

/// pubspec 이 [AppTheme.fontFamily] family 로 선언하는 앱 글꼴 파일 경로.
const String kAppFontAssetPath =
    'assets/fonts/pretendard-jp/PretendardJPVariable.ttf';

/// [kAppFontAssetPath] 파일을 [AppTheme.fontFamily] 이름으로 [FontLoader] 에
/// 올린다.
///
/// flutter_tester 는 pubspec `fonts:` 를 자동으로 올리지 않아, 부르지 않으면
/// 테마 글자가 네모 상자로 그려진다. 파일이 없으면 경로를 담은 [TestFailure] 를
/// 던진다 — 조용히 상자 글꼴로 떨어져 golden 이 바뀌는 일을 막는다.
Future<void> loadAppFont() async {
  final file = File(kAppFontAssetPath);
  if (!file.existsSync()) {
    throw TestFailure(
      '${AppTheme.fontFamily} 글꼴 파일 부재 ($kAppFontAssetPath) — '
      'pubspec 의 asset 경로와 이 상수가 같은지 확인한다.',
    );
  }
  final bytes = await file.readAsBytes();
  final loader = FontLoader(AppTheme.fontFamily)
    ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
  await loader.load();
}
