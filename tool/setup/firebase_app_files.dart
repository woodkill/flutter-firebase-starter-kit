import 'dart:convert';
import 'dart:io';

import 'config_files.dart';
import 'steps/identity_step.dart';
import 'steps/user_files_step.dart';

/// dev flavor 의 Android 패키지 접미사 — Gradle productFlavors 의
/// `applicationIdSuffix` 와 같다.
const String devPackageSuffix = '.dev';

/// Gradle 의 `applicationId = "…"` 줄 — group 1 = 앱 ID.
final RegExp _applicationIdPattern = RegExp(r'applicationId\s*=\s*"([^"]+)"');

/// 사용자 xcconfig 에서 지금 앱 정체성의 dev iOS 번들 ID 를 읽는다.
///
/// 파일이 없거나 값이 비었으면 null.
String? readDevBundleId(String projectRoot) {
  final File file = File('$projectRoot/${UserFilesStep.xcconfigUserPath}');
  if (!file.existsSync()) return null;
  final String? value = readXcconfigValue(
    file.path,
    'PRODUCT_BUNDLE_IDENTIFIER',
  );
  return value == null || value.isEmpty ? null : value;
}

/// Gradle 파일의 `applicationId` 에 [devPackageSuffix] 를 붙여 dev Android
/// 패키지를 만든다.
///
/// 파일이 없거나 `applicationId` 줄이 없으면 null.
String? readDevAndroidPackage(String projectRoot) {
  final File file = File('$projectRoot/${IdentityStep.gradlePath}');
  if (!file.existsSync()) return null;
  final RegExpMatch? match = _applicationIdPattern.firstMatch(
    file.readAsStringSync(),
  );
  if (match == null) return null;
  return '${match.group(1)!}$devPackageSuffix';
}

/// configure 스크립트가 만드는 dev 앱 설정 파일 3개에서 판정에 필요한 값만 읽는다.
///
/// 파일에는 API 키 · 앱 ID 같은 값이 들어 있으므로 원문을 밖으로 내지 않고,
/// 단계가 비교에 쓰는 값만 getter 로 돌려준다. 호출한 쪽도 이 값을 화면 · 기록에
/// 쓰지 않는다. 파일이 없거나 읽지 못하면 해당 값은 null 이다.
final class FirebaseAppFiles {
  FirebaseAppFiles._(this._options, this._plist, this._googleServices);

  /// FlutterFire 가 만드는 Dart 설정 파일(저장소 상대 경로).
  static const String optionsPath =
      'lib/core/firebase/firebase_options_dev.dart';

  /// iOS 설정 파일(저장소 상대 경로).
  static const String iosPlistPath = 'ios/config/dev/GoogleService-Info.plist';

  /// Android 설정 파일(저장소 상대 경로).
  static const String androidJsonPath =
      'android/app/src/dev/google-services.json';

  /// 저장소 자리표시 Dart 설정 파일에만 있는 표시.
  static const String optionsPlaceholderMarker = 'UnsupportedError(';

  final String? _options;
  final String? _plist;
  final Map<String, Object?>? _googleServices;

  /// [projectRoot] 아래 설정 파일 3개를 읽는다.
  static FirebaseAppFiles read(String projectRoot) => FirebaseAppFiles._(
    _readText('$projectRoot/$optionsPath'),
    _readText('$projectRoot/$iosPlistPath'),
    _decodeObject(_readText('$projectRoot/$androidJsonPath')),
  );

  /// Dart 설정 파일이 없거나 저장소 자리표시면 true.
  bool get isOptionsPlaceholder {
    final String? options = _options;
    return options == null || options.contains(optionsPlaceholderMarker);
  }

  /// Dart 설정 파일의 `projectId: '<p>'` 값.
  ///
  /// 플랫폼별 값이 서로 다르거나 하나도 없으면 null.
  String? get optionsProjectId {
    final String? options = _options;
    if (options == null) return null;
    final Set<String> values = <String>{
      for (final RegExpMatch match in RegExp(
        r"projectId:\s*'([^']+)'",
      ).allMatches(options))
        match.group(1)!,
    };
    return values.length == 1 ? values.single : null;
  }

  /// iOS 설정 파일의 `PROJECT_ID`.
  String? get iosProjectId => _readPlistString('PROJECT_ID');

  /// iOS 설정 파일의 `BUNDLE_ID`.
  String? get iosBundleId => _readPlistString('BUNDLE_ID');

  /// iOS 설정 파일의 `GOOGLE_APP_ID`(Firebase 앱 ID).
  String? get iosAppId => _readPlistString('GOOGLE_APP_ID');

  /// Android 설정 파일의 `project_info.project_id`.
  String? get androidProjectId {
    final Object? info = _googleServices?['project_info'];
    if (info is! Map<String, Object?>) return null;
    final Object? id = info['project_id'];
    return id is String ? id : null;
  }

  /// Android 설정 파일에서 [packageName] client 의 Firebase 앱 ID 를 찾는다.
  ///
  /// 그 패키지의 client 가 없으면 null.
  String? androidAppIdFor(String packageName) {
    final Object? clients = _googleServices?['client'];
    if (clients is! List<Object?>) return null;
    for (final Object? client in clients) {
      if (client is! Map<String, Object?>) continue;
      final Object? info = client['client_info'];
      if (info is! Map<String, Object?>) continue;
      final Object? android = info['android_client_info'];
      if (android is! Map<String, Object?>) continue;
      if (android['package_name'] != packageName) continue;
      final Object? appId = info['mobilesdk_app_id'];
      return appId is String ? appId : null;
    }
    return null;
  }

  /// plist 의 `<key>K</key>` 바로 뒤 `<string>V</string>` 값을 읽는다.
  String? _readPlistString(String key) {
    final String? plist = _plist;
    if (plist == null) return null;
    final RegExpMatch? match = RegExp(
      '<key>${RegExp.escape(key)}</key>\\s*<string>([^<]*)</string>',
    ).firstMatch(plist);
    return match?.group(1);
  }

  /// 파일을 읽는다 — 없거나 읽지 못하면 null.
  static String? _readText(String path) {
    final File file = File(path);
    if (!file.existsSync()) return null;
    try {
      return file.readAsStringSync();
    } on FileSystemException {
      return null;
    }
  }

  /// JSON 객체로 해석한다 — 비었거나 객체가 아니면 null.
  static Map<String, Object?>? _decodeObject(String? text) {
    if (text == null) return null;
    try {
      final Object? decoded = jsonDecode(text);
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}
