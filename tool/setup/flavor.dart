/// 위저드가 준비하는 앱 환경(flavor).
enum Flavor {
  /// 개발 환경.
  dev,

  /// 검수 환경.
  stg,

  /// 출시 환경.
  prod;

  /// Android 패키지 · iOS 번들 ID 에 붙는 접미사 — Gradle productFlavors 의
  /// `applicationIdSuffix` 와 같다(prod 는 빈 문자열).
  String get suffix => switch (this) {
    Flavor.dev => '.dev',
    Flavor.stg => '.stg',
    Flavor.prod => '',
  };

  /// [value] 를 flavor 로 읽는다 — 모르는 이름이면 null.
  static Flavor? tryParse(String value) {
    for (final Flavor flavor in Flavor.values) {
      if (flavor.name == value) return flavor;
    }
    return null;
  }
}

/// flavor 하나가 쓰는 사용자 파일 · 설정 파일의 저장소 상대 경로 모음.
final class FlavorPaths {
  /// [flavor] 의 경로 모음을 만든다.
  const FlavorPaths(this.flavor);

  /// 경로를 만들 flavor.
  final Flavor flavor;

  /// 사용자 config(`config/<flavor>.json`).
  String get json => 'config/${flavor.name}.json';

  /// 추적되는 example config(`config/<flavor>.example.json`).
  String get jsonExample => 'config/${flavor.name}.example.json';

  /// 사용자 xcconfig(`ios/Flutter/<flavor>.xcconfig`).
  String get xcconfig => 'ios/Flutter/${flavor.name}.xcconfig';

  /// 추적되는 example xcconfig(`ios/Flutter/<flavor>.example.xcconfig`).
  String get xcconfigExample => 'ios/Flutter/${flavor.name}.example.xcconfig';

  /// iOS Firebase 설정 파일.
  String get iosPlist => 'ios/config/${flavor.name}/GoogleService-Info.plist';

  /// Android Firebase 설정 파일.
  String get androidJson =>
      'android/app/src/${flavor.name}/google-services.json';

  /// FlutterFire 가 만드는 Dart 설정 파일.
  String get dartOptions =>
      'lib/core/firebase/firebase_options_${flavor.name}.dart';
}
