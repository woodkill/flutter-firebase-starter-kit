// 홈 화면 앱 이름(런처 이름)을 언어별로 빌드 산출물에 쓰는 생성기.
//
// 원본은 `l10n.yaml` 의 `arb-dir` 안 ARB 파일들의 `appTitle` 하나다. 기본 언어
// 이름은 지금처럼 config `appName`(Android) · xcconfig `DISPLAY_NAME`(iOS)이 맡고,
// 이 생성기는 기본 이름과 다른 이름을 가진 언어만 파일로 쓴다.
//
// - Android: `android/app/build.gradle.kts` 의 variant 마다 등록된 Gradle task 가
//   `local.properties` 의 `flutter.sdk` 아래 `bin/dart` 로 부른다. 출력은
//   `--out` 아래 `values-<qualifier>/strings.xml`(`app_name` 하나)이고 Gradle 이
//   그 디렉터리를 variant 의 생성 리소스로 붙인다.
// - iOS: Runner target 의 Run Script 단계가 `$FLUTTER_ROOT/bin/dart` 로 부른다.
//   빌드된 앱의 `<lang>.lproj/InfoPlist.strings` 에 `CFBundleDisplayName` 키 하나만
//   얹고(다른 키는 보존 · binary plist), 빌드된 Info.plist 의 `CFBundleLocalizations`
//   를 ARB 언어 목록으로 채운다. 저장소의 `ios/Runner/Info.plist` 는 건드리지 않는다.
//   지난 빌드가 이름을 얹었다가 이번에 빠진 언어는 `DERIVED_FILE_DIR` 의 기록 파일
//   (`launcher_names.manifest`) 기준으로 그 키만 빼고, 빈 파일 · 빈 lproj 는 지운다.
//
// 영어(template) ARB 의 `appTitle` 이 기본 이름(config 이름에서 flavor 접미사를 뗀
// 값)과 다르거나 Android 빌드에 config `appName` 이 들어오지 않았으면, 고칠 곳을
// 적은 오류로 빌드를 멈춘다.
//
// dart: 라이브러리만 쓴다 — `dart <이 파일>` 꼴로 패키지 해석(pub) 없이 바로
// 실행되게 하기 위함이다. 언어를 더해도 빌드 설정 파일은 바뀌지 않고 이 파일의
// 규칙만 바뀐다.
import 'dart:convert';
import 'dart:io';

/// ARB 에서 앱 이름을 읽는 키.
const String appTitleKey = 'appTitle';

/// ARB 가 자기 locale 을 적는 키.
const String _arbLocaleKey = '@@locale';

/// 홈 화면 이름표가 읽는 Info.plist 키.
const String displayNameKey = 'CFBundleDisplayName';

/// 앱이 지원하는 언어를 OS 에 알리는 Info.plist 키.
const String localizationsKey = 'CFBundleLocalizations';

/// iOS 가 지난 빌드에 쓴 lproj 목록을 둘 기록 파일 이름(`DERIVED_FILE_DIR` 아래).
const String manifestFileName = 'launcher_names.manifest';

/// flavor 이름 → 표시 이름 접미사.
///
/// 설정 위저드 `tool/setup/flavor.dart` 의 `Flavor.displayNameSuffix` 와 같은
/// 표다(prod 는 빈 문자열).
const Map<String, String> flavorDisplayNameSuffixes = <String, String>{
  'dev': ' Dev',
  'stg': ' Stg',
  'prod': '',
};

/// ARB 파일 이름의 locale 부분이 따라야 하는 꼴(언어 · 문자 체계 · 지역).
///
/// 문자 · 숫자 · `_` 만 허용해 파일 이름이 출력 경로 밖을 가리키지 못하게 한다.
final RegExp arbLocalePattern = RegExp(
  r'^[A-Za-z]{2,3}(_[A-Za-z]{4})?(_([A-Za-z]{2}|[0-9]{3}))?$',
);

/// 생성기 진입점 — 실패하면 빌드가 멈추도록 0 이 아닌 코드로 끝낸다.
///
/// 실패는 종류와 관계없이 `error: launcher_names:` 로 시작하는 한 줄로 알린다.
Future<void> main(List<String> args) async {
  try {
    final Options options = parseOptions(args, Platform.environment);
    final GenerationResult result = await generateLauncherNames(options);
    for (final String line in result.log) {
      stdout.writeln('launcher_names: $line');
    }
    stdout.writeln(
      'launcher_names: ${options.platform.name} · flavor ${options.flavor} · '
      'wrote ${result.written.length} · skipped ${result.skipped.length}',
    );
  } on GeneratorException catch (error) {
    // Xcode 는 `error:` 로 시작하는 줄을 이슈 목록의 오류로 보이고, Gradle 은
    // stderr 를 「What went wrong」 에 그대로 싣는다.
    stderr.writeln('error: launcher_names: ${error.message}');
    exitCode = 1;
  } on Object catch (error, stackTrace) {
    // 파일 쓰기 · plist 해석 같은 예기치 못한 실패도 같은 `error:` 줄로 알려
    // Xcode 이슈 목록에 보이게 하고, 원인을 찾도록 스택을 그 뒤에 남긴다.
    stderr
      ..writeln('error: launcher_names: 예기치 못한 실패 — $error')
      ..writeln(stackTrace);
    exitCode = 1;
  }
}

/// 생성기 실패 — 메시지는 빌드 출력에 그대로 실린다.
final class GeneratorException implements Exception {
  /// [message] 로 실패를 만든다.
  const GeneratorException(this.message);

  /// 사람이 읽는 실패 이유와 고칠 방법.
  final String message;

  @override
  String toString() => 'GeneratorException: $message';
}

/// 생성기가 파일을 쓰는 대상 플랫폼.
enum LauncherPlatform {
  /// Android 생성 리소스(`values-<qualifier>/strings.xml`).
  android,

  /// iOS 빌드된 앱 번들(`<lang>.lproj/InfoPlist.strings` · Info.plist).
  ios,
}

/// 한 언어의 홈 화면 이름 — 생성기가 파일 하나로 쓰는 단위.
final class LauncherName {
  /// [locale] 의 이름 [name] 을 만든다.
  const LauncherName(this.locale, this.name);

  /// ARB 파일 이름의 locale(`ko` · `pt_BR` · `zh_Hant`).
  final String locale;

  /// 홈 화면에 보일 이름(붙일 flavor 접미사 포함).
  final String name;

  @override
  bool operator ==(Object other) =>
      other is LauncherName && other.locale == locale && other.name == name;

  @override
  int get hashCode => Object.hash(locale, name);

  @override
  String toString() => 'LauncherName($locale, $name)';
}

/// 생성기 실행 인자 묶음.
final class Options {
  /// 인자 묶음을 만든다.
  const Options({
    required this.platform,
    required this.projectRoot,
    required this.flavor,
    required this.configName,
    this.androidOutDir,
    this.iosBundleDir,
    this.iosInfoPlistPath,
    this.iosManifestPath,
  });

  /// 대상 플랫폼.
  final LauncherPlatform platform;

  /// Flutter 프로젝트 루트(`l10n.yaml` 이 있는 곳).
  final String projectRoot;

  /// flavor 이름(dev · stg · prod).
  final String flavor;

  /// 기본 언어 이름의 원본 값 — Android 는 config `appName`, iOS 는 xcconfig
  /// `DISPLAY_NAME`(flavor 접미사 포함). 빌드에 들어오지 않았으면 빈 문자열이다.
  final String configName;

  /// Android 생성 리소스 디렉터리(`--out`).
  final String? androidOutDir;

  /// iOS 빌드된 앱 번들 리소스 디렉터리.
  final String? iosBundleDir;

  /// iOS 빌드된 Info.plist 경로.
  final String? iosInfoPlistPath;

  /// iOS 지난 빌드 기록 파일 경로.
  final String? iosManifestPath;
}

/// 생성 결과 — 쓴 파일 · 건너뛴 언어 · 빌드 로그 줄.
final class GenerationResult {
  /// 결과를 만든다.
  const GenerationResult({
    required this.written,
    required this.skipped,
    required this.log,
  });

  /// 이번에 쓴 파일(출력 디렉터리 기준 상대 경로).
  final List<String> written;

  /// 이름이 없거나 기본 이름과 같아 파일을 쓰지 않은 locale.
  final List<String> skipped;

  /// 빌드 로그에 남길 줄.
  final List<String> log;
}

/// 사용법 — 인자가 틀렸을 때 실패 메시지에 붙인다.
const String _usage =
    '사용법: dart tool/launcher_names.dart android --project-root <dir> '
    '--out <dir> --flavor <flavor> --app-name <name> | '
    'dart tool/launcher_names.dart ios (Xcode 빌드 설정 SRCROOT · FLAVOR · '
    'DISPLAY_NAME · TARGET_BUILD_DIR · UNLOCALIZED_RESOURCES_FOLDER_PATH · '
    'INFOPLIST_PATH · DERIVED_FILE_DIR 를 환경 변수로 읽는다)';

/// Android 모드가 받는 옵션 이름.
const List<String> _androidOptionNames = <String>[
  'project-root',
  'out',
  'flavor',
  'app-name',
];

/// iOS 모드가 읽는 환경 변수 이름.
const List<String> _iosEnvironmentNames = <String>[
  'SRCROOT',
  'FLAVOR',
  'DISPLAY_NAME',
  'TARGET_BUILD_DIR',
  'UNLOCALIZED_RESOURCES_FOLDER_PATH',
  'INFOPLIST_PATH',
  'DERIVED_FILE_DIR',
];

/// 명령행 인자 [args] 와 환경 변수 [environment] 를 [Options] 로 읽는다.
///
/// 첫 인자는 `android` 또는 `ios` 다. Android 는 `--project-root` · `--out` ·
/// `--flavor` · `--app-name` 네 옵션이 모두 있어야 하고 빈 값은 `--app-name` 만
/// 허용한다. iOS 는 다른 인자 없이 Xcode 빌드 설정 환경 변수를 읽는다. 틀리면
/// 사용법을 담은 [GeneratorException] 을 던진다.
Options parseOptions(List<String> args, Map<String, String> environment) {
  if (args.isEmpty) {
    throw const GeneratorException('대상 플랫폼 인자가 없다 — $_usage');
  }
  switch (args.first) {
    case 'android':
      return _parseAndroidOptions(args.sublist(1));
    case 'ios':
      if (args.length > 1) {
        throw GeneratorException(
          'ios 모드는 다른 인자를 받지 않는다: ${args.sublist(1).join(' ')} — '
          '$_usage',
        );
      }
      return _parseIosOptions(environment);
    default:
      throw GeneratorException('알 수 없는 대상 플랫폼 "${args.first}" — $_usage');
  }
}

/// Android 모드의 `--key value` 인자를 읽는다.
Options _parseAndroidOptions(List<String> rest) {
  final values = <String, String>{};
  for (var i = 0; i < rest.length; i++) {
    final String arg = rest[i];
    if (!arg.startsWith('--')) {
      throw GeneratorException('알 수 없는 인자 "$arg" — $_usage');
    }
    final String key = arg.substring(2);
    if (!_androidOptionNames.contains(key)) {
      throw GeneratorException('알 수 없는 옵션 "$arg" — $_usage');
    }
    if (values.containsKey(key)) {
      throw GeneratorException('옵션 "$arg" 이 두 번 있다 — $_usage');
    }
    if (i + 1 >= rest.length) {
      throw GeneratorException('옵션 "$arg" 의 값이 없다 — $_usage');
    }
    values[key] = rest[++i];
  }
  for (final String key in _androidOptionNames) {
    final String? value = values[key];
    if (value == null) {
      throw GeneratorException('옵션 "--$key" 이 없다 — $_usage');
    }
    if (value.isEmpty && key != 'app-name') {
      throw GeneratorException('옵션 "--$key" 의 값이 비어 있다 — $_usage');
    }
  }
  return Options(
    platform: LauncherPlatform.android,
    projectRoot: values['project-root']!,
    flavor: values['flavor']!,
    configName: values['app-name']!,
    androidOutDir: values['out'],
  );
}

/// iOS 모드의 Xcode 빌드 설정 환경 변수를 읽는다.
Options _parseIosOptions(Map<String, String> environment) {
  for (final String name in _iosEnvironmentNames) {
    // DISPLAY_NAME 이 비어 있는 경우는 생성 단계가 고칠 파일을 적어 알린다.
    if (name == 'DISPLAY_NAME') continue;
    final String? value = environment[name];
    if (value == null || value.isEmpty) {
      throw GeneratorException(
        '환경 변수 $name 이 없다 — Xcode Run Script 단계에서 실행한다. $_usage',
      );
    }
  }
  final String targetBuildDir = environment['TARGET_BUILD_DIR']!;
  return Options(
    platform: LauncherPlatform.ios,
    projectRoot: Directory(environment['SRCROOT']!).parent.path,
    flavor: environment['FLAVOR']!,
    configName: environment['DISPLAY_NAME'] ?? '',
    iosBundleDir:
        '$targetBuildDir/${environment['UNLOCALIZED_RESOURCES_FOLDER_PATH']}',
    iosInfoPlistPath: '$targetBuildDir/${environment['INFOPLIST_PATH']}',
    iosManifestPath: '${environment['DERIVED_FILE_DIR']}/$manifestFileName',
  );
}

/// [suffix] 가 비어 있지 않고 [name] 이 그것으로 끝나면 뗀 값, 아니면 [name].
String stripFlavorSuffix(String name, String suffix) {
  if (suffix.isNotEmpty && name.endsWith(suffix)) {
    return name.substring(0, name.length - suffix.length);
  }
  return name;
}

/// 언어별 홈 화면 이름 계획을 세운다(플랫폼 무관).
///
/// [arbNames] 는 locale → ARB `appTitle`(없으면 null)이다. [templateLocale] 과
/// 이름이 없거나(앞뒤 공백을 뗀 값이 빈 경우 포함) [baseName] 과 같은 언어는
/// 뺀다. 남은 언어마다 이름 뒤에 [appliedSuffix] 를 붙이고 locale 순으로 정렬한다.
///
/// 지역 변형(`pt_BR` · `es_419` — 문자 체계 없이 지역만 있는 locale)이 계획에
/// 있고 같은 언어의 기본 locale(`pt`)이 이름이 없거나 [baseName] 과 같으면, 기본
/// locale 에 [baseName] + [appliedSuffix] 를 더한다. 같은 언어의 다른 지역 기기가
/// 그 지역 변형 이름으로 떨어지지 않고 기본 이름을 쓰게 하기 위함이다. 문자 체계
/// 변형(`zh_Hant`)은 기본 locale 항목을 만들지 않는다.
List<LauncherName> planLauncherNames({
  required Map<String, String?> arbNames,
  required String templateLocale,
  required String baseName,
  required String appliedSuffix,
}) {
  bool hasOwnName(String locale) {
    final String? name = arbNames[locale];
    return name != null && name.trim().isNotEmpty && name != baseName;
  }

  final named = <String>{
    for (final String locale in arbNames.keys)
      if (locale != templateLocale && hasOwnName(locale)) locale,
  };
  final baseLocales = <String>{};
  for (final locale in named) {
    final (:String language, :String? script, :String? region) = _splitLocale(
      locale,
    );
    if (region == null || script != null) continue;
    final String baseLocale = _findBaseLocale(arbNames.keys, language);
    if (!hasOwnName(baseLocale)) baseLocales.add(baseLocale);
  }
  final List<String> locales = <String>{...named, ...baseLocales}.toList()
    ..sort();
  return <LauncherName>[
    for (final String locale in locales)
      LauncherName(
        locale,
        named.contains(locale)
            ? '${arbNames[locale]}$appliedSuffix'
            : '$baseName$appliedSuffix',
      ),
  ];
}

/// [locales] 가운데 [language] 의 기본 locale(문자 체계 · 지역 없음)을 찾는다 —
/// 없으면 [language] 그대로.
String _findBaseLocale(Iterable<String> locales, String language) {
  for (final locale in locales) {
    final (language: String candidate, :String? script, :String? region) =
        _splitLocale(locale);
    if (candidate == language && script == null && region == null) {
      return locale;
    }
  }
  return language;
}

/// ARB locale 을 언어 · 문자 체계 · 지역으로 나눈다 — 꼴이 어긋나면 실패.
({String language, String? script, String? region}) _splitLocale(
  String arbLocale,
) {
  final List<String> parts = arbLocale.split(RegExp('[_-]'));
  final String language = parts.first.toLowerCase();
  if (language.length < 2 ||
      language.length > 3 ||
      !RegExp(r'^[a-z]+$').hasMatch(language)) {
    throw GeneratorException('ARB locale 의 언어 코드가 아니다: "$arbLocale"');
  }
  String? script;
  String? region;
  for (final String part in parts.skip(1)) {
    if (script == null &&
        region == null &&
        RegExp(r'^[A-Za-z]{4}$').hasMatch(part)) {
      script = part[0].toUpperCase() + part.substring(1).toLowerCase();
    } else if (region == null &&
        RegExp(r'^([A-Za-z]{2}|[0-9]{3})$').hasMatch(part)) {
      region = part.toUpperCase();
    } else {
      throw GeneratorException('ARB locale 을 변환할 수 없다: "$arbLocale"');
    }
  }
  return (language: language, script: script, region: region);
}

/// ARB locale 을 Android 리소스 qualifier 로 바꾼다.
///
/// 2글자 언어(+ 2글자 지역)는 `ko` · `pt-rBR` 꼴, 문자 체계 · 3글자 언어 · 숫자
/// 지역이 있으면 `b+zh+Hant` · `b+fil` · `b+es+419` 꼴이다. Android 는 `he` · `id` ·
/// `yi` 기기에서도 옛 코드 `iw` · `in` · `ji` 폴더를 찾으므로 그 코드로 쓴다.
/// 바꿀 수 없으면 [GeneratorException].
String toAndroidQualifier(String arbLocale) {
  final (:String language, :String? script, :String? region) = _splitLocale(
    arbLocale,
  );
  final String code = switch (language) {
    'he' => 'iw',
    'id' => 'in',
    'yi' => 'ji',
    _ => language,
  };
  final bool isLegacyForm =
      code.length == 2 &&
      script == null &&
      (region == null || region.length == 2);
  if (isLegacyForm) {
    return region == null ? code : '$code-r$region';
  }
  return 'b+${<String>[code, ?script, ?region].join('+')}';
}

/// ARB locale 을 iOS lproj 이름(확장자 없음)으로 바꾼다.
///
/// `zh_Hant` → `zh-Hant`, `pt_BR` → `pt-BR` 처럼 현대 언어 코드를 그대로 쓴다.
/// 바꿀 수 없으면 [GeneratorException].
String toLprojName(String arbLocale) {
  final (:String language, :String? script, :String? region) = _splitLocale(
    arbLocale,
  );
  return <String>[language, ?script, ?region].join('-');
}

/// `l10n.yaml` 에서 읽은 ARB 위치.
final class L10nConfig {
  /// [arbDir] 디렉터리 · [templateArbFile] 파일 이름으로 설정을 만든다.
  const L10nConfig(this.arbDir, this.templateArbFile);

  /// 프로젝트 루트 기준 ARB 디렉터리(`lib/l10n`).
  final String arbDir;

  /// template ARB 파일 이름(`app_en.arb`).
  final String templateArbFile;

  /// 프로젝트 루트 기준 template ARB 경로(`lib/l10n/app_en.arb`).
  String get templatePath => '$arbDir/$templateArbFile';

  /// ARB 파일 이름에서 locale 앞에 오는 부분(`app_en.arb` → `app_`).
  ///
  /// 파일 이름 꼴(`<prefix>_<locale>.arb`)은 [listArbFiles] 가 먼저 검사한다.
  String get arbFilePrefix =>
      templateArbFile.substring(0, templateArbFile.indexOf('_') + 1);

  /// template ARB 의 locale(`app_en.arb` → `en`).
  ///
  /// 파일 이름 꼴(`<prefix>_<locale>.arb`)은 [listArbFiles] 가 먼저 검사한다.
  String get templateLocale => templateArbFile.substring(
    arbFilePrefix.length,
    templateArbFile.length - '.arb'.length,
  );
}

/// 입력 파일 실패 — 「무엇이 틀렸나 — 어느 파일(프로젝트 상대 경로) — 어떻게
/// 고치나」 순서의 문구를 만든다.
GeneratorException _inputError(String problem, String file, String fix) =>
    GeneratorException('$problem — $file — $fix');

/// 프로젝트 루트 기준 `l10n.yaml` 경로.
const String _l10nYamlPath = 'l10n.yaml';

/// `l10n.yaml` 의 `arb-dir` · `template-arb-file` 두 줄만 줄 단위로 읽는다.
///
/// 파일이 없거나 두 값 가운데 하나라도 비면 [GeneratorException] 을 던진다.
L10nConfig readL10nConfig(String projectRoot) {
  final file = File('$projectRoot/$_l10nYamlPath');
  if (!file.existsSync()) {
    throw _inputError(
      'l10n.yaml 을 찾지 못했다',
      _l10nYamlPath,
      '프로젝트 루트에 arb-dir · template-arb-file 을 적은 l10n.yaml 을 둔다',
    );
  }
  String? arbDir;
  String? template;
  for (final String raw in file.readAsLinesSync()) {
    final String line = raw.split('#').first.trim();
    if (line.startsWith('arb-dir:')) {
      arbDir = _unquote(line.substring('arb-dir:'.length).trim());
    } else if (line.startsWith('template-arb-file:')) {
      template = _unquote(line.substring('template-arb-file:'.length).trim());
    }
  }
  if (arbDir == null ||
      arbDir.isEmpty ||
      template == null ||
      template.isEmpty) {
    throw _inputError(
      'arb-dir 또는 template-arb-file 이 없다',
      _l10nYamlPath,
      '두 줄을 모두 적는다(예: arb-dir: lib/l10n · template-arb-file: '
          'app_en.arb)',
    );
  }
  if (arbDir.endsWith('/')) arbDir = arbDir.substring(0, arbDir.length - 1);
  return L10nConfig(arbDir, template);
}

/// yaml 값의 바깥 따옴표 한 쌍을 뗀다.
String _unquote(String value) {
  if (value.length >= 2 &&
      ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'")))) {
    return value.substring(1, value.length - 1);
  }
  return value;
}

/// ARB 파일 이름 [fileName] 에서 [prefix] 뒤 locale 을 읽는다 — 꼴이 어긋나면 실패.
///
/// 실패는 `<arbDir>/<fileName>` 을 적은 [GeneratorException] 이다.
String localeFromArbFileName(String fileName, String prefix, String arbDir) {
  const extension = '.arb';
  final String locale =
      fileName.startsWith(prefix) && fileName.endsWith(extension)
      ? fileName.substring(prefix.length, fileName.length - extension.length)
      : '';
  if (!arbLocalePattern.hasMatch(locale)) {
    throw _inputError(
      'ARB 파일 이름의 locale 을 읽을 수 없다',
      '$arbDir/$fileName',
      '파일 이름을 $prefix<locale>.arb 꼴로 바꾼다 — locale 은 언어(2~3글자) · '
          '문자 체계(4글자) · 지역(2글자 또는 숫자 3자리)을 `_` 로 이은 값이다 '
          '(예: ${prefix}ko.arb · ${prefix}pt_BR.arb · ${prefix}zh_Hant.arb)',
    );
  }
  return locale;
}

/// 이어진 공백 — Android string 리소스가 한 칸으로 접는다.
final RegExp _repeatedWhitespace = RegExp(r'\s{2,}');

/// 언어별 이름 [name] 의 앞뒤에 공백이 있거나 공백이 이어지면 true.
///
/// Android string 리소스는 앞뒤 공백을 지우고 이어진 공백을 한 칸으로 접지만
/// iOS 는 그대로 보여, 이런 이름은 두 플랫폼 이름이 갈린다.
bool hasLauncherNameWhitespaceIssue(String name) =>
    name != name.trim() || _repeatedWhitespace.hasMatch(name);

/// [config] 의 ARB 디렉터리에서 `.arb` 파일을 경로 순으로 돌려준다.
///
/// template ARB 이름이 `<prefix>_<locale>.arb` 꼴이 아니거나 디렉터리가 없으면
/// [GeneratorException] 을 던진다. 파일 내용은 읽지 않는다.
List<File> listArbFiles(String projectRoot, L10nConfig config) {
  final String template = config.templateArbFile;
  if (!template.contains('_') || !template.endsWith('.arb')) {
    throw _inputError(
      'template ARB 이름에서 locale 을 읽을 수 없다(${config.templatePath})',
      _l10nYamlPath,
      'template-arb-file 을 <prefix>_<locale>.arb 꼴(예: app_en.arb)로 적는다',
    );
  }
  final dir = Directory('$projectRoot/${config.arbDir}');
  if (!dir.existsSync()) {
    throw _inputError(
      'ARB 디렉터리 ${config.arbDir} 를 찾지 못했다',
      _l10nYamlPath,
      'arb-dir 을 ARB 파일이 있는 디렉터리(프로젝트 루트 기준)로 고친다',
    );
  }
  return dir
      .listSync()
      .whereType<File>()
      .where((File file) => file.path.endsWith('.arb'))
      .toList()
    ..sort((File a, File b) => a.path.compareTo(b.path));
}

/// ARB 디렉터리의 파일마다 locale → `appTitle`(없으면 null)을 모은다.
Map<String, String?> _readArbNames(String projectRoot, L10nConfig config) {
  final List<File> files = listArbFiles(projectRoot, config);
  final String prefix = config.arbFilePrefix;
  final names = <String, String?>{};
  for (final file in files) {
    final String fileName = file.uri.pathSegments.last;
    final relativePath = '${config.arbDir}/$fileName';
    final String locale = localeFromArbFileName(
      fileName,
      prefix,
      config.arbDir,
    );
    final Object? decoded;
    try {
      decoded = jsonDecode(file.readAsStringSync());
    } on FormatException catch (error) {
      throw _inputError(
        'ARB 파일이 올바른 JSON 이 아니다(${error.message})',
        relativePath,
        'JSON 문법(따옴표 · 쉼표 · 괄호)을 고친다',
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw _inputError(
        'ARB 파일의 최상위가 JSON 객체가 아니다',
        relativePath,
        '{ "@@locale": "$locale", ... } 꼴의 객체로 고친다',
      );
    }
    final Object? declaredLocale = decoded[_arbLocaleKey];
    if (declaredLocale != null && declaredLocale != locale) {
      throw _inputError(
        'ARB 의 $_arbLocaleKey ${jsonEncode(declaredLocale)} 가 파일 이름의 '
            'locale "$locale" 과 다르다',
        relativePath,
        '$_arbLocaleKey 를 "$locale" 로 고치거나 파일 이름을 그 locale 로 바꾼다',
      );
    }
    final Object? name = decoded[appTitleKey];
    if (name != null && name is! String) {
      throw _inputError(
        'ARB 의 $appTitleKey 가 문자열이 아니다',
        relativePath,
        '$appTitleKey 값을 따옴표로 감싼 문자열로 고친다',
      );
    }
    if (name is String && name.trim().isEmpty) {
      throw _inputError(
        'ARB 의 $appTitleKey 가 비어 있다',
        relativePath,
        '그 언어 이름을 넣거나, 기본 이름을 쓰려면 $appTitleKey 키를 지운다',
      );
    }
    if (locale != config.templateLocale &&
        name is String &&
        hasLauncherNameWhitespaceIssue(name)) {
      // 생성기가 쓰는 언어별 이름에서 Android string 리소스는 앞뒤 공백을 지우고
      // 이어진 공백을 한 칸으로 접지만 iOS 는 그대로 보여 두 플랫폼 이름이 갈린다.
      // template 이름은 생성기가 쓰지 않고 config 기본 이름과의 대조만 받는다.
      throw _inputError(
        'ARB 의 $appTitleKey ${jsonEncode(name)} 의 앞뒤에 공백이 있거나 공백이 '
            '이어진다',
        relativePath,
        '앞뒤 공백을 지우고 낱말 사이 공백은 한 칸으로 둔다',
      );
    }
    names[locale] = name is String ? name : null;
  }
  if (!names.containsKey(config.templateLocale)) {
    throw _inputError(
      'template ARB 를 찾지 못했다',
      config.templatePath,
      '그 파일을 만들거나 l10n.yaml 의 template-arb-file 을 고친다',
    );
  }
  return names;
}

/// ARB 를 읽어 [Options.platform] 의 언어별 이름 파일을 쓴다.
///
/// 기본 이름은 [Options.configName] 에서 flavor 접미사를 뗀 값이다. 다른 언어
/// 이름에는 config 이름이 그 접미사로 끝날 때만 그 접미사를 붙인다. template ARB
/// `appTitle` 이 기본 이름과 다르거나, config 이름이 빌드에 들어오지 않았으면
/// 고칠 곳을 적은 [GeneratorException] 을 던진다.
Future<GenerationResult> generateLauncherNames(Options options) async {
  final String flavor = options.flavor;
  final String? suffix = flavorDisplayNameSuffixes[flavor];
  if (suffix == null) {
    throw GeneratorException(
      '알 수 없는 flavor "$flavor" — '
      '${flavorDisplayNameSuffixes.keys.join(' · ')} 중 하나로 빌드한다',
    );
  }
  final String nameSource = switch (options.platform) {
    LauncherPlatform.android => 'config/$flavor.json 의 appName',
    LauncherPlatform.ios => 'ios/Flutter/$flavor.xcconfig 의 DISPLAY_NAME',
  };
  if (options.configName.isEmpty) {
    throw GeneratorException(switch (options.platform) {
      LauncherPlatform.android =>
        '$nameSource 이 빌드에 들어오지 않았다 — '
            '--dart-define-from-file=config/$flavor.json 없이 빌드했다. '
            '예: fvm flutter build apk --flavor $flavor '
            '--dart-define-from-file=config/$flavor.json',
      LauncherPlatform.ios =>
        '$nameSource 이 비어 있다 — ios/Flutter/$flavor.xcconfig 의 '
            'DISPLAY_NAME 에 앱 이름을 넣거나 ./setup.sh --flavor $flavor 로 설정 '
            '위저드 「앱 정체성」 단계를 다시 실행한다',
    });
  }
  final String baseName = stripFlavorSuffix(options.configName, suffix);
  final String appliedSuffix = baseName == options.configName ? '' : suffix;

  final L10nConfig config = readL10nConfig(options.projectRoot);
  final Map<String, String?> arbNames = _readArbNames(
    options.projectRoot,
    config,
  );
  final String templateLocale = config.templateLocale;
  final String? templateName = arbNames[templateLocale];
  if (templateName != baseName) {
    final source = appliedSuffix.isEmpty
        ? '$nameSource "${options.configName}"'
        : '$nameSource "${options.configName}" 에서 flavor 접미사 '
              '"$appliedSuffix" 를 뗀 값';
    final found = templateName == null
        ? '${config.templatePath} 에 $appTitleKey 가 없다'
        : '${config.templatePath} 의 $appTitleKey "$templateName" 이';
    throw GeneratorException(
      '$found 기본 앱 이름 "$baseName"($source)과 맞지 않는다. '
      '고칠 방법 — ${config.templatePath} 의 $appTitleKey 값을 "$baseName" 로 '
      '바꾸거나, ./setup.sh --flavor $flavor 로 설정 위저드 「앱 정체성」 단계를 '
      '다시 실행한다',
    );
  }

  final List<LauncherName> plan = planLauncherNames(
    arbNames: arbNames,
    templateLocale: templateLocale,
    baseName: baseName,
    appliedSuffix: appliedSuffix,
  );
  final planned = <String>{for (final LauncherName entry in plan) entry.locale};
  final skipped = <String>[
    for (final String locale in arbNames.keys.toList()..sort())
      if (locale != templateLocale && !planned.contains(locale)) locale,
  ];
  final log = <String>[
    for (final String locale in skipped)
      'skip $locale (no $appTitleKey or same as the default name)',
  ];
  final List<String> written = switch (options.platform) {
    LauncherPlatform.android => _writeAndroid(options, plan, log),
    LauncherPlatform.ios => await _writeIos(
      options,
      plan,
      arbNames.keys.toList(),
      log,
    ),
  };
  return GenerationResult(written: written, skipped: skipped, log: log);
}

/// Android `values-<qualifier>/strings.xml` 을 계획마다 쓴다.
List<String> _writeAndroid(
  Options options,
  List<LauncherName> plan,
  List<String> log,
) {
  final String outDir = options.androidOutDir!;
  Directory(outDir).createSync(recursive: true);
  final written = <String>[];
  for (final entry in plan) {
    final relativePath =
        'values-${toAndroidQualifier(entry.locale)}/strings.xml';
    final file = File('$outDir/$relativePath');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      '<?xml version="1.0" encoding="utf-8"?>\n'
      '<resources>\n'
      '    <string name="app_name">${escapeAndroidString(entry.name)}</string>\n'
      '</resources>\n',
    );
    written.add(relativePath);
    log.add('write $relativePath = "${entry.name}"');
  }
  return written;
}

/// [value] 를 Android string 리소스 값으로 이스케이프한다.
///
/// `&` `<` `>` 는 XML 엔티티로, 역슬래시 · `'` · `"` · 줄바꿈은 역슬래시
/// 이스케이프로 바꾼다. 맨 앞 `@` `?` 는 리소스 참조로 읽히지 않도록 역슬래시를
/// 붙이고, 가운데의 `@` `?` 는 그대로 둔다.
String escapeAndroidString(String value) {
  final buffer = StringBuffer();
  for (var index = 0; index < value.length; index++) {
    final String c = value[index];
    buffer.write(switch (c) {
      '&' => '&amp;',
      '<' => '&lt;',
      '>' => '&gt;',
      r'\' => r'\\',
      "'" => r"\'",
      '"' => r'\"',
      '\n' => r'\n',
      '@' || '?' when index == 0 => '\\$c',
      _ => c,
    });
  }
  return buffer.toString();
}

/// iOS 빌드된 앱에 `<lproj>.lproj/InfoPlist.strings` 를 쓰고 Info.plist 의
/// `CFBundleLocalizations` 를 [arbLocales] 로 채운다.
///
/// 지난 빌드가 이름을 얹었지만 이번 계획에 없는 lproj 는 기록 파일
/// ([Options.iosManifestPath]) 기준으로 표시 이름 키만 빼고, 기록 파일을 이번
/// lproj 목록으로 바꾼다.
Future<List<String>> _writeIos(
  Options options,
  List<LauncherName> plan,
  List<String> arbLocales,
  List<String> log,
) async {
  final String bundleDir = options.iosBundleDir!;
  final infoPlist = File(options.iosInfoPlistPath!);
  if (!infoPlist.existsSync()) {
    throw GeneratorException(
      '빌드된 Info.plist 를 찾지 못했다: ${infoPlist.path} — 이 단계는 Runner '
      'target 의 Thin Binary 단계 뒤에 있어야 한다',
    );
  }
  final written = <String>[];
  for (final entry in plan) {
    final relativePath = '${toLprojName(entry.locale)}.lproj/InfoPlist.strings';
    final file = File('$bundleDir/$relativePath');
    // Copy Bundle Resources 가 먼저 복사한 InfoPlist.strings(권한 문구 등)가
    // 있으면 지우지 않고 그 위에 표시 이름 키 하나만 얹는다.
    final Map<String, Object?> entries = await _readPlistAsJson(file);
    final int otherKeyCount = entries.keys
        .where((String key) => key != displayNameKey)
        .length;
    entries[displayNameKey] = entry.name;
    await _writeBinaryPlist(file, entries);
    written.add(relativePath);
    log.add(
      '${otherKeyCount > 0 ? 'merge' : 'write'} $relativePath = '
      '"${entry.name}"'
      '${otherKeyCount > 0 ? ' (kept $otherKeyCount other key(s))' : ''}',
    );
  }
  final current = <String>[
    for (final entry in plan) '${toLprojName(entry.locale)}.lproj',
  ];
  final String manifestPath = options.iosManifestPath!;
  await _removeStaleDisplayNames(bundleDir, manifestPath, current, log);
  _writeManifest(manifestPath, current);

  final List<String> localizations = <String>{
    for (final String locale in arbLocales) toLprojName(locale),
  }.toList()..sort();
  await _runPlutil(<String>[
    '-replace',
    localizationsKey,
    '-json',
    jsonEncode(localizations),
    infoPlist.path,
  ], infoPlist.path);
  log.add('set Info.plist $localizationsKey = ${jsonEncode(localizations)}');
  return written;
}

/// 기록 파일 줄이 따라야 하는 lproj 디렉터리 이름 꼴.
///
/// 이 꼴이 아닌 줄은 번들 밖을 가리킬 수 있으므로 무시한다.
final RegExp _lprojEntryPattern = RegExp(r'^[A-Za-z0-9-]+\.lproj$');

/// 기록 파일 [manifestPath] 에 있었지만 [current] 에 없는 lproj 에서 표시 이름
/// 키를 뺀다.
///
/// 남은 키가 없으면 파일을, 그 뒤 lproj 디렉터리가 비면 디렉터리를 지운다.
/// 기록에 없는 lproj(adopter 가 직접 둔 표시 이름 포함)는 건드리지 않는다.
Future<void> _removeStaleDisplayNames(
  String bundleDir,
  String manifestPath,
  List<String> current,
  List<String> log,
) async {
  final manifest = File(manifestPath);
  if (!manifest.existsSync()) return;
  final List<String> previous;
  try {
    previous = manifest.readAsLinesSync();
  } on FileSystemException catch (error) {
    throw GeneratorException(
      '지난 빌드 기록 파일을 읽지 못했다(${error.message}) — $manifestPath — '
      '그 파일을 지우고 다시 빌드한다',
    );
  }
  for (final line in previous) {
    final String lproj = line.trim();
    if (!_lprojEntryPattern.hasMatch(lproj) || current.contains(lproj)) {
      continue;
    }
    final relativePath = '$lproj/InfoPlist.strings';
    final file = File('$bundleDir/$relativePath');
    if (!file.existsSync()) continue;
    final Map<String, Object?> entries = await _readPlistAsJson(file);
    if (!entries.containsKey(displayNameKey)) continue;
    entries.remove(displayNameKey);
    if (entries.isNotEmpty) {
      await _writeBinaryPlist(file, entries);
      log.add(
        'unset $relativePath $displayNameKey '
        '(kept ${entries.length} other key(s))',
      );
      continue;
    }
    file.deleteSync();
    final Directory dir = file.parent;
    if (dir.listSync().isEmpty) dir.deleteSync();
    log.add('remove $relativePath');
  }
}

/// 이번에 이름을 얹은 lproj 목록 [current] 를 기록 파일 [manifestPath] 에 쓴다.
void _writeManifest(String manifestPath, List<String> current) {
  File(manifestPath)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
      <String>[for (final lproj in current) '$lproj\n'].join(),
    );
}

/// plist 파일을 JSON 객체로 읽는다 — 없으면 빈 맵. text · binary 모두 읽는다.
Future<Map<String, Object?>> _readPlistAsJson(File file) async {
  if (!file.existsSync()) return <String, Object?>{};
  final String output = await _runPlutil(<String>[
    '-convert',
    'json',
    '-o',
    '-',
    file.path,
  ], file.path);
  final Object? decoded = jsonDecode(output);
  if (decoded is! Map<String, Object?>) {
    throw GeneratorException('strings 사전이 아니다: ${file.path}');
  }
  return decoded;
}

/// [entries] 를 binary plist 로 [file] 에 쓴다(JSON 임시 파일을 plutil 로 변환).
Future<void> _writeBinaryPlist(File file, Map<String, Object?> entries) async {
  file.parent.createSync(recursive: true);
  final Directory temp = Directory.systemTemp.createTempSync('launcher_names_');
  try {
    final json = File('${temp.path}/InfoPlist.json')
      ..writeAsStringSync(jsonEncode(entries));
    await _runPlutil(<String>[
      '-convert',
      'binary1',
      '-o',
      file.path,
      json.path,
    ], file.path);
  } finally {
    temp.deleteSync(recursive: true);
  }
}

/// `/usr/bin/plutil` 을 [arguments] 로 실행하고 stdout 을 돌려준다.
Future<String> _runPlutil(List<String> arguments, String target) async {
  final ProcessResult result;
  try {
    result = await Process.run('/usr/bin/plutil', arguments);
  } on ProcessException catch (error) {
    throw GeneratorException('plutil 을 실행하지 못했다($target): ${error.message}');
  }
  if (result.exitCode != 0) {
    throw GeneratorException(
      'plutil 이 실패했다($target): ${'${result.stderr}'.trim()}',
    );
  }
  return '${result.stdout}';
}
