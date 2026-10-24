/// 빌드 입력 파일의 경로와 지문(sha256)을 읽는다.
///
/// 위저드 실행 단계가 이번 실행에서 앱을 다시 빌드해야 하는지 판정하는 데 쓴다 —
/// 지문은 메모리(`WizardSession`)에만 두고 화면 · 기록에 쓰지 않는다.
library;

import 'dart:io';

import 'package:crypto/crypto.dart';

import 'flavor.dart';
import 'wizard.dart';

/// [flavor] 앱 빌드에 들어가는 사용자 파일 · 설정 파일의 저장소 상대 경로를
/// 돌려준다.
///
/// 순서는 config(`config/<flavor>.json`) · xcconfig · Dart 설정 파일 · iOS
/// Firebase 설정 파일 · Android Firebase 설정 파일이다.
List<String> buildInputPaths(Flavor flavor) {
  final paths = FlavorPaths(flavor);
  return <String>[
    paths.json,
    paths.xcconfig,
    paths.dartOptions,
    paths.iosPlist,
    paths.androidJson,
  ];
}

/// [context] flavor 의 빌드 입력 파일마다 파일 바이트의 sha256 16진 지문을 읽는다.
///
/// 키는 [buildInputPaths] 의 저장소 상대 경로 그대로 · 같은 순서다. 파일이
/// 없거나 읽지 못하면 그 경로의 값은 null 이다.
Map<String, String?> readBuildInputDigests(WizardContext context) =>
    <String, String?>{
      for (final String path in buildInputPaths(context.flavor))
        path: _readDigest(context.resolve(path)),
    };

/// [absolutePath] 파일 바이트의 sha256 16진 지문 — 없거나 읽지 못하면 null.
String? _readDigest(String absolutePath) {
  try {
    return sha256.convert(File(absolutePath).readAsBytesSync()).toString();
  } on FileSystemException {
    return null;
  }
}
