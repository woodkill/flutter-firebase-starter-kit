// 홈 화면 앱 이름 생성기(`tool/launcher_names.dart`)의 규칙을 fixture ARB 한 벌로
// 고정한다.
//
// 같은 fixture(15개 언어)로 생성기를 Android 모드와 iOS 모드로 실제로 돌려, 두
// 플랫폼 출력(Android `values-*/strings.xml` · iOS `*.lproj/InfoPlist.strings`)이
// 같은 기대 표를 따르는지 본다. 언어 코드 변환 · 지역 변형 · 실패 분류 ·
// 이스케이프도 함께 고정한다.
//
// 파일은 `Directory.systemTemp` 아래 임시 프로젝트에만 쓰고 시험마다 지운다 —
// 저장소의 ARB · 빌드 설정은 읽지도 쓰지도 않는다.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../tool/launcher_names.dart' as gen;
import '../helpers/source_text.dart';

/// fixture 의 config 이름(flavor dev) — 기본 이름 `RunningPencil` + 접미사 ` Dev`.
const String fixtureConfigName = 'RunningPencil Dev';

/// fixture ARB 한 벌 — ARB 파일 이름의 locale → `appTitle`(키가 없으면 null).
///
/// fr 은 기본 이름과 같고 de · zh · pt 는 이름이 없다.
const Map<String, String?> fixtureAppTitles = <String, String?>{
  'en': 'RunningPencil',
  'ko': '러닝펜슬',
  'ja': 'ランニングペンシル',
  'fr': 'RunningPencil',
  'de': null,
  'zh': null,
  'zh_Hant': '跑步鉛筆',
  'pt': null,
  'pt_BR': 'Lápis Corredor',
  'es': 'Lápiz Corredor',
  'es_419': 'Lápiz Veloz',
  'he': 'עיפרון רץ',
  'id': 'Pensil Lari',
  'yi': 'לויפנדיקער בלייַער',
  'fil': 'Lapis na Tumatakbo',
};

/// fixture 로 기대하는 출력 — ARB locale · Android 폴더 · iOS lproj · 이름.
///
/// `androidDir` 순으로 정렬돼 있다. pt 는 이름이 없지만 pt_BR 에 이름이 있어
/// 기본 이름 + 접미사를 쓴다.
const List<({String locale, String androidDir, String lproj, String name})>
expectedOutputs =
    <({String locale, String androidDir, String lproj, String name})>[
      (
        locale: 'es_419',
        androidDir: 'values-b+es+419',
        lproj: 'es-419',
        name: 'Lápiz Veloz Dev',
      ),
      (
        locale: 'fil',
        androidDir: 'values-b+fil',
        lproj: 'fil',
        name: 'Lapis na Tumatakbo Dev',
      ),
      (
        locale: 'zh_Hant',
        androidDir: 'values-b+zh+Hant',
        lproj: 'zh-Hant',
        name: '跑步鉛筆 Dev',
      ),
      (
        locale: 'es',
        androidDir: 'values-es',
        lproj: 'es',
        name: 'Lápiz Corredor Dev',
      ),
      (
        locale: 'id',
        androidDir: 'values-in',
        lproj: 'id',
        name: 'Pensil Lari Dev',
      ),
      (
        locale: 'he',
        androidDir: 'values-iw',
        lproj: 'he',
        name: 'עיפרון רץ Dev',
      ),
      (
        locale: 'ja',
        androidDir: 'values-ja',
        lproj: 'ja',
        name: 'ランニングペンシル Dev',
      ),
      (
        locale: 'yi',
        androidDir: 'values-ji',
        lproj: 'yi',
        name: 'לויפנדיקער בלייַער Dev',
      ),
      (locale: 'ko', androidDir: 'values-ko', lproj: 'ko', name: '러닝펜슬 Dev'),
      (
        locale: 'pt',
        androidDir: 'values-pt',
        lproj: 'pt',
        name: 'RunningPencil Dev',
      ),
      (
        locale: 'pt_BR',
        androidDir: 'values-pt-rBR',
        lproj: 'pt-BR',
        name: 'Lápis Corredor Dev',
      ),
    ];

/// 기대 iOS lproj 이름 목록(정렬).
const List<String> expectedLprojNames = <String>[
  'es',
  'es-419',
  'fil',
  'he',
  'id',
  'ja',
  'ko',
  'pt',
  'pt-BR',
  'yi',
  'zh-Hant',
];

/// [project] 아래에 `l10n.yaml` 과 [appTitles] 의 ARB 파일을 쓴다.
///
/// ARB 마다 `@@locale` 은 파일 이름의 locale 이고, 값이 null 인 언어는
/// `appTitle` 키를 두지 않는다.
void writeFixtureProject(Directory project, Map<String, String?> appTitles) {
  File('${project.path}/l10n.yaml').writeAsStringSync(
    'arb-dir: lib/l10n\n'
    'template-arb-file: app_en.arb\n'
    'output-dir: lib/l10n/generated\n',
  );
  final arbDir = Directory('${project.path}/lib/l10n')
    ..createSync(recursive: true);
  for (final MapEntry<String, String?> entry in appTitles.entries) {
    final String? title = entry.value;
    File('${arbDir.path}/app_${entry.key}.arb').writeAsStringSync(
      jsonEncode(<String, String>{'@@locale': entry.key, 'appTitle': ?title}),
    );
  }
}

/// [project] 로 Android 모드를 돌리고 출력 디렉터리를 돌려준다.
Future<Directory> runAndroid(
  Directory project, {
  String flavor = 'dev',
  String appName = fixtureConfigName,
}) async {
  final out = Directory('${project.path}/android-out');
  await gen.generateLauncherNames(
    gen.parseOptions(<String>[
      'android',
      '--project-root',
      project.path,
      '--out',
      out.path,
      '--flavor',
      flavor,
      '--app-name',
      appName,
    ], const <String, String>{}),
  );
  return out;
}

/// [out] 바로 아래 `values-*` 디렉터리 이름 목록(정렬).
List<String> listValuesDirs(Directory out) {
  if (!out.existsSync()) return <String>[];
  return out
      .listSync()
      .whereType<Directory>()
      .map(
        (Directory dir) =>
            dir.uri.pathSegments[dir.uri.pathSegments.length - 2],
      )
      .where((String name) => name.startsWith('values-'))
      .toList()
    ..sort();
}

/// Android `strings.xml` 에서 `app_name` 값을 읽는다.
String readAndroidAppName(File stringsXml) {
  final RegExpMatch? match = RegExp(
    '<string name="app_name">(.*)</string>',
  ).firstMatch(stringsXml.readAsStringSync());
  if (match == null) {
    throw StateError('${stringsXml.path} 에 app_name 이 없다');
  }
  return match.group(1)!;
}

/// fixture 이름 표로 생성기 계획(플랫폼 무관)을 세운다.
List<gen.LauncherName> planFixture(Map<String, String?> appTitles) {
  return gen.planLauncherNames(
    arbNames: appTitles,
    templateLocale: 'en',
    baseName: 'RunningPencil',
    appliedSuffix: ' Dev',
  );
}

/// [root] 를 Flutter 프로젝트로 보는 iOS 모드 가짜 Xcode 빌드 환경 변수.
///
/// 번들은 `<root>/build/Runner.app`, Info.plist 는 그 안 `Info.plist`, 기록 파일
/// 디렉터리는 `<root>/build/derived` 다(아직 없을 수 있다).
Map<String, String> iosEnvironment(
  Directory root, {
  String flavor = 'dev',
  String displayName = fixtureConfigName,
}) {
  return <String, String>{
    'SRCROOT': '${root.path}/ios',
    'FLAVOR': flavor,
    'DISPLAY_NAME': displayName,
    'TARGET_BUILD_DIR': '${root.path}/build',
    'UNLOCALIZED_RESOURCES_FOLDER_PATH': 'Runner.app',
    'INFOPLIST_PATH': 'Runner.app/Info.plist',
    'DERIVED_FILE_DIR': '${root.path}/build/derived',
  };
}

/// [GeneratorException] 이고 문구에 [fragments] 가 모두 들어 있는지 보는 matcher.
Matcher throwsGeneratorError(List<String> fragments) {
  return throwsA(
    isA<gen.GeneratorException>().having(
      (gen.GeneratorException error) => error.message,
      'message',
      allOf(<Matcher>[for (final fragment in fragments) contains(fragment)]),
    ),
  );
}

/// [run] 을 실행해 [gen.GeneratorException] 문구를 돌려준다 — 실패가 없으면 시험 실패.
Future<String> captureGeneratorMessage(Future<Object?> Function() run) async {
  try {
    await run();
  } on gen.GeneratorException catch (error) {
    return error.message;
  }
  fail('GeneratorException 이 나지 않았다');
}

/// macOS `plutil` 이 없는 기계에서 iOS 쓰기 시험을 건너뛰는 까닭(macOS 면 false).
final Object skipWithoutPlutil = Platform.isMacOS
    ? false
    : 'iOS 쓰기는 macOS /usr/bin/plutil 로 plist 를 읽고 쓴다';

/// `/usr/bin/plutil` 을 [arguments] 로 실행하고 stdout 을 돌려준다 — 실패하면 시험 실패.
String runPlutil(List<String> arguments) {
  final ProcessResult result = Process.runSync('/usr/bin/plutil', arguments);
  if (result.exitCode != 0) {
    fail('plutil ${arguments.join(' ')} 실패: ${result.stderr}');
  }
  return '${result.stdout}';
}

/// [entries] 를 binary plist 로 [file] 에 쓴다.
void writeBinaryPlist(File file, Map<String, Object?> entries) {
  file.parent.createSync(recursive: true);
  final json = File('${file.path}.json')
    ..writeAsStringSync(jsonEncode(entries));
  runPlutil(<String>['-convert', 'binary1', '-o', file.path, json.path]);
  json.deleteSync();
}

/// plist [file] 전체를 JSON 객체로 읽는다(text · binary 모두).
Map<String, Object?> readPlist(File file) {
  final Object? decoded = jsonDecode(
    runPlutil(<String>['-convert', 'json', '-o', '-', file.path]),
  );
  if (decoded is! Map<String, Object?>) {
    fail('${file.path} 이 plist 사전이 아니다');
  }
  return decoded;
}

/// `plutil -extract <key> raw` 로 [file] 의 문자열 값을 읽는다.
String extractRaw(File file, String key) {
  final String output = runPlutil(<String>[
    '-extract',
    key,
    'raw',
    '-o',
    '-',
    file.path,
  ]);
  // raw 출력은 값 뒤에 줄바꿈 하나를 붙인다.
  return output.endsWith('\n')
      ? output.substring(0, output.length - 1)
      : output;
}

/// [file] 이 binary plist(`bplist00` 머리)인지 본다.
bool isBinaryPlist(File file) {
  final List<int> head = file.readAsBytesSync().take(8).toList();
  return ascii.decode(head, allowInvalid: true) == 'bplist00';
}

/// [root] 의 가짜 빌드된 번들 디렉터리(`iosEnvironment` 와 같은 자리).
Directory bundleDirOf(Directory root) =>
    Directory('${root.path}/build/Runner.app');

/// [root] 의 가짜 빌드된 Info.plist 를 binary 로 만든다.
File createBuiltInfoPlist(
  Directory root, {
  Map<String, Object?> entries = const <String, Object?>{
    'CFBundleDisplayName': fixtureConfigName,
  },
}) {
  final file = File('${bundleDirOf(root).path}/Info.plist');
  writeBinaryPlist(file, entries);
  return file;
}

/// [root] 로 iOS 모드를 돌린다.
Future<gen.GenerationResult> runIos(
  Directory root, {
  String displayName = fixtureConfigName,
}) {
  return gen.generateLauncherNames(
    gen.parseOptions(<String>[
      'ios',
    ], iosEnvironment(root, displayName: displayName)),
  );
}

/// 번들의 `<lproj>.lproj/InfoPlist.strings` 파일.
File infoPlistStringsOf(Directory root, String lproj) =>
    File('${bundleDirOf(root).path}/$lproj.lproj/InfoPlist.strings');

/// 번들 안 `InfoPlist.strings` 가 있는 lproj 이름 목록(정렬).
List<String> listLprojWithStrings(Directory root) {
  return bundleDirOf(root)
      .listSync()
      .whereType<Directory>()
      .map(
        (Directory dir) =>
            dir.uri.pathSegments[dir.uri.pathSegments.length - 2],
      )
      .where((String name) => name.endsWith('.lproj'))
      .map((String name) => name.substring(0, name.length - '.lproj'.length))
      .where((String lproj) => infoPlistStringsOf(root, lproj).existsSync())
      .toList()
    ..sort();
}

/// [root] 의 iOS 기록 파일 줄 목록.
List<String> readManifestLines(Directory root) => File(
  '${root.path}/build/derived/${gen.manifestFileName}',
).readAsLinesSync();

void main() {
  late Directory project;

  setUp(() {
    project = Directory.systemTemp.createTempSync('launcher_names_test_');
  });

  tearDown(() {
    if (project.existsSync()) project.deleteSync(recursive: true);
  });

  test('T-22-GEN-01: 같은 fixture 의 Android 쓰기 결과 · iOS 계획이 기대 표와 같다', () async {
    writeFixtureProject(project, fixtureAppTitles);

    final Directory out = await runAndroid(project);
    expect(listValuesDirs(out), <String>[
      for (final expected in expectedOutputs) expected.androidDir,
    ]);
    for (final expected in expectedOutputs) {
      expect(
        readAndroidAppName(
          File('${out.path}/${expected.androidDir}/strings.xml'),
        ),
        expected.name,
        reason: expected.androidDir,
      );
    }

    final List<gen.LauncherName> plan = planFixture(fixtureAppTitles);
    expect(
      <String>[for (final entry in plan) gen.toLprojName(entry.locale)]..sort(),
      expectedLprojNames,
    );
    final lprojValues = <String, String>{
      for (final entry in plan) gen.toLprojName(entry.locale): entry.name,
    };
    for (final expected in expectedOutputs) {
      expect(
        lprojValues[expected.lproj],
        expected.name,
        reason: expected.lproj,
      );
    }
    expect(lprojValues['ko'], '러닝펜슬 Dev');
    expect(lprojValues['pt'], 'RunningPencil Dev');
  });

  test('T-22-GEN-02: ARB locale → Android qualifier · iOS lproj 변환 표', () {
    const table = <({String arb, String android, String ios})>[
      (arb: 'ko', android: 'ko', ios: 'ko'),
      (arb: 'pt_BR', android: 'pt-rBR', ios: 'pt-BR'),
      (arb: 'zh_Hant', android: 'b+zh+Hant', ios: 'zh-Hant'),
      (arb: 'es_419', android: 'b+es+419', ios: 'es-419'),
      (arb: 'fil', android: 'b+fil', ios: 'fil'),
      (arb: 'he', android: 'iw', ios: 'he'),
      (arb: 'id', android: 'in', ios: 'id'),
      (arb: 'yi', android: 'ji', ios: 'yi'),
      (arb: 'sr_Latn', android: 'b+sr+Latn', ios: 'sr-Latn'),
      (arb: 'en_US', android: 'en-rUS', ios: 'en-US'),
    ];
    for (final row in table) {
      expect(gen.toAndroidQualifier(row.arb), row.android, reason: row.arb);
      expect(gen.toLprojName(row.arb), row.ios, reason: row.arb);
    }
  });

  test(
    'T-22-GEN-03: 이름이 없거나 기본과 같은 언어(fr · de · zh · en)는 두 출력 어디에도 없다',
    () async {
      writeFixtureProject(project, fixtureAppTitles);

      final List<String> androidDirs = listValuesDirs(
        await runAndroid(project),
      );
      final lprojNames = <String>[
        for (final entry in planFixture(fixtureAppTitles))
          gen.toLprojName(entry.locale),
      ];
      for (final locale in <String>['fr', 'de', 'zh', 'en']) {
        expect(androidDirs, isNot(contains('values-$locale')), reason: locale);
        expect(lprojNames, isNot(contains(locale)), reason: locale);
      }
    },
  );

  group('T-22-GEN-04: 지역 변형', () {
    List<gen.LauncherName> planOf(
      Map<String, String?> arbNames, {
      String appliedSuffix = ' Dev',
    }) => gen.planLauncherNames(
      arbNames: arbNames,
      templateLocale: 'en',
      baseName: 'A',
      appliedSuffix: appliedSuffix,
    );

    test('T-22-GEN-04: pt 이름이 없으면 pt 에 기본 이름 + 접미사', () {
      expect(
        planOf(<String, String?>{'en': 'A', 'pt': null, 'pt_BR': 'B'}),
        <gen.LauncherName>[
          const gen.LauncherName('pt', 'A Dev'),
          const gen.LauncherName('pt_BR', 'B Dev'),
        ],
      );
    });

    test('T-22-GEN-04: pt 이름이 기본과 같으면 pt 에 기본 이름 + 접미사', () {
      expect(
        planOf(<String, String?>{'en': 'A', 'pt': 'A', 'pt_BR': 'B'}),
        <gen.LauncherName>[
          const gen.LauncherName('pt', 'A Dev'),
          const gen.LauncherName('pt_BR', 'B Dev'),
        ],
      );
    });

    test('T-22-GEN-04: 접미사가 없으면 pt 에 기본 이름 그대로', () {
      expect(
        planOf(<String, String?>{
          'en': 'A',
          'pt': null,
          'pt_BR': 'B',
        }, appliedSuffix: ''),
        <gen.LauncherName>[
          const gen.LauncherName('pt', 'A'),
          const gen.LauncherName('pt_BR', 'B'),
        ],
      );
    });

    test('T-22-GEN-04: pt 이름이 다르면 pt 에 그 이름', () {
      expect(
        planOf(<String, String?>{'en': 'A', 'pt': 'C', 'pt_BR': 'B'}),
        <gen.LauncherName>[
          const gen.LauncherName('pt', 'C Dev'),
          const gen.LauncherName('pt_BR', 'B Dev'),
        ],
      );
    });

    test('T-22-GEN-04: pt_BR 이름이 없으면 pt 는 0', () {
      expect(
        planOf(<String, String?>{'en': 'A', 'pt': null, 'pt_BR': null}),
        isEmpty,
      );
    });

    test('T-22-GEN-04: 문자 체계 변형(zh_Hant)만 이름이 있으면 zh 는 0', () {
      expect(
        planOf(<String, String?>{'en': 'A', 'zh': null, 'zh_Hant': 'Z'}),
        <gen.LauncherName>[const gen.LauncherName('zh_Hant', 'Z Dev')],
      );
    });
  });

  test(
    'T-22-GEN-05: values-ko/strings.xml 은 XML 선언 · resources · app_name 하나뿐이다',
    () async {
      writeFixtureProject(project, fixtureAppTitles);

      final Directory out = await runAndroid(project);
      final String content = File(
        '${out.path}/values-ko/strings.xml',
      ).readAsStringSync();
      expect(
        content,
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<resources>\n'
        '    <string name="app_name">러닝펜슬 Dev</string>\n'
        '</resources>\n',
      );
      expect('<string '.allMatches(content).length, 1);
    },
  );

  group('T-22-GEN-06: 영어 ARB 와 기본 이름 대조(양방향)', () {
    const mismatchFragments = <String>[
      'lib/l10n/app_en.arb',
      '"RunningPencil"',
      '"RunningPencik"',
      './setup.sh --flavor dev',
    ];

    test('T-22-GEN-06: 영어 ARB 와 기본 이름이 같으면 통과한다', () async {
      writeFixtureProject(project, fixtureAppTitles);
      await expectLater(runAndroid(project), completes);
    });

    test('T-22-GEN-06: 영어 ARB 가 한 글자 다르면 실패한다', () async {
      writeFixtureProject(project, <String, String?>{
        ...fixtureAppTitles,
        'en': 'RunningPencik',
      });
      await expectLater(
        runAndroid(project),
        throwsGeneratorError(mismatchFragments),
      );
    });

    test('T-22-GEN-06: config 이름이 한 글자 다르면 실패한다', () async {
      writeFixtureProject(project, fixtureAppTitles);
      await expectLater(
        runAndroid(project, appName: 'RunningPencik Dev'),
        throwsGeneratorError(mismatchFragments),
      );
    });

    test('T-22-GEN-06: 영어 ARB 에 appTitle 이 없으면 실패한다', () async {
      writeFixtureProject(project, <String, String?>{
        ...fixtureAppTitles,
        'en': null,
      });
      await expectLater(
        runAndroid(project),
        throwsGeneratorError(<String>[
          'lib/l10n/app_en.arb',
          'appTitle',
          './setup.sh --flavor dev',
        ]),
      );
    });
  });

  test('T-22-GEN-07: config 이름 미주입은 이름 불일치와 다른 문구로 실패한다', () async {
    writeFixtureProject(project, fixtureAppTitles);

    final String android = await captureGeneratorMessage(
      () => runAndroid(project, appName: ''),
    );
    expect(android, contains('--dart-define-from-file=config/dev.json'));

    final String ios = await captureGeneratorMessage(
      () => gen.generateLauncherNames(
        gen.parseOptions(<String>[
          'ios',
        ], iosEnvironment(project, displayName: '')),
      ),
    );
    expect(ios, contains('ios/Flutter/dev.xcconfig'));
    expect(ios, contains('DISPLAY_NAME'));

    final String mismatch = await captureGeneratorMessage(
      () => runAndroid(project, appName: 'RunningPencik Dev'),
    );
    for (final message in <String>[android, ios]) {
      expect(message, isNot(contains('lib/l10n/app_en.arb')));
      expect(message, isNot(mismatch));
    }
    expect(android, isNot(ios));
  });

  group('T-22-GEN-08: 깨진 입력은 고칠 파일을 적은 GeneratorException', () {
    void writeArb(Directory root, String fileName, String content) {
      File('${root.path}/lib/l10n/$fileName').writeAsStringSync(content);
    }

    final cases =
        <
          ({
            String label,
            void Function(Directory root) breakInput,
            String fragment,
            String flavor,
          })
        >[
          (
            label: '깨진 JSON',
            breakInput: (Directory root) =>
                writeArb(root, 'app_ko.arb', '{"appTitle": '),
            fragment: 'lib/l10n/app_ko.arb',
            flavor: 'dev',
          ),
          (
            label: '최상위가 배열',
            breakInput: (Directory root) =>
                writeArb(root, 'app_ko.arb', '["러닝펜슬"]'),
            fragment: 'lib/l10n/app_ko.arb',
            flavor: 'dev',
          ),
          (
            label: 'appTitle 이 숫자',
            breakInput: (Directory root) => writeArb(
              root,
              'app_ko.arb',
              '{"@@locale": "ko", "appTitle": 3}',
            ),
            fragment: 'lib/l10n/app_ko.arb',
            flavor: 'dev',
          ),
          (
            label: 'appTitle 이 공백뿐',
            breakInput: (Directory root) => writeArb(
              root,
              'app_ko.arb',
              '{"@@locale": "ko", "appTitle": "   "}',
            ),
            fragment: 'lib/l10n/app_ko.arb',
            flavor: 'dev',
          ),
          (
            label: 'appTitle 이 빈 문자열',
            breakInput: (Directory root) => writeArb(
              root,
              'app_ko.arb',
              '{"@@locale": "ko", "appTitle": ""}',
            ),
            fragment: 'lib/l10n/app_ko.arb',
            flavor: 'dev',
          ),
          for (final (String label, String title) in <(String, String)>[
            ('appTitle 앞에 공백', ' 러닝펜슬'),
            ('appTitle 뒤에 공백', '러닝펜슬 '),
            ('appTitle 안에 이어진 공백', '러닝  펜슬'),
          ])
            (
              // Android 는 앞뒤 공백을 지우고 이어진 공백을 접어 iOS 와 이름이 갈린다.
              label: label,
              breakInput: (Directory root) => writeArb(
                root,
                'app_ko.arb',
                jsonEncode(<String, String>{
                  '@@locale': 'ko',
                  'appTitle': title,
                }),
              ),
              fragment: 'lib/l10n/app_ko.arb',
              flavor: 'dev',
            ),
          (
            label: '파일 이름 app_k.arb',
            breakInput: (Directory root) =>
                writeArb(root, 'app_k.arb', '{"@@locale": "k"}'),
            fragment: 'lib/l10n/app_k.arb',
            flavor: 'dev',
          ),
          (
            label: '파일 이름 app_ko-KR.arb',
            breakInput: (Directory root) =>
                writeArb(root, 'app_ko-KR.arb', '{"@@locale": "ko_KR"}'),
            fragment: 'lib/l10n/app_ko-KR.arb',
            flavor: 'dev',
          ),
          (
            label: '파일 이름 app_abcd_EFG.arb',
            breakInput: (Directory root) =>
                writeArb(root, 'app_abcd_EFG.arb', '{"@@locale": "abcd_EFG"}'),
            fragment: 'lib/l10n/app_abcd_EFG.arb',
            flavor: 'dev',
          ),
          (
            label: '@@locale 이 파일 이름과 다름',
            breakInput: (Directory root) => writeArb(
              root,
              'app_ko.arb',
              '{"@@locale": "ja", "appTitle": "러닝펜슬"}',
            ),
            fragment: 'lib/l10n/app_ko.arb',
            flavor: 'dev',
          ),
          (
            label: 'l10n.yaml 없음',
            breakInput: (Directory root) =>
                File('${root.path}/l10n.yaml').deleteSync(),
            fragment: 'l10n.yaml',
            flavor: 'dev',
          ),
          (
            label: 'l10n.yaml 에 arb-dir 없음',
            breakInput: (Directory root) => File(
              '${root.path}/l10n.yaml',
            ).writeAsStringSync('template-arb-file: app_en.arb\n'),
            fragment: 'l10n.yaml',
            flavor: 'dev',
          ),
          (
            label: '모르는 flavor',
            breakInput: (Directory root) {},
            fragment: '"qa"',
            flavor: 'qa',
          ),
        ];

    for (final c in cases) {
      test('T-22-GEN-08: ${c.label}', () async {
        writeFixtureProject(project, fixtureAppTitles);
        c.breakInput(project);

        final String message = await captureGeneratorMessage(
          () => runAndroid(project, flavor: c.flavor),
        );
        expect(message, contains(c.fragment));
        // 파일은 임시 디렉터리 절대 경로가 아니라 저장소 상대 경로로 적는다.
        expect(message, isNot(contains(project.path)));
      });
    }
  });

  test('T-22-GEN-09: flavor 접미사는 config 이름이 그 접미사로 끝날 때만 붙는다', () async {
    expect(gen.stripFlavorSuffix('A Dev', ' Dev'), 'A');
    expect(gen.stripFlavorSuffix('A', ' Dev'), 'A');
    expect(gen.stripFlavorSuffix('A Dev', ''), 'A Dev');

    writeFixtureProject(project, fixtureAppTitles);
    final Directory prod = await runAndroid(
      project,
      flavor: 'prod',
      appName: 'RunningPencil',
    );
    expect(
      readAndroidAppName(File('${prod.path}/values-ko/strings.xml')),
      '러닝펜슬',
    );
    expect(
      readAndroidAppName(File('${prod.path}/values-pt/strings.xml')),
      'RunningPencil',
    );
    prod.deleteSync(recursive: true);

    final Directory devWithoutSuffix = await runAndroid(
      project,
      appName: 'RunningPencil',
    );
    expect(
      readAndroidAppName(
        File('${devWithoutSuffix.path}/values-ko/strings.xml'),
      ),
      '러닝펜슬',
    );
    expect(
      readAndroidAppName(
        File('${devWithoutSuffix.path}/values-ja/strings.xml'),
      ),
      'ランニングペンシル',
    );
  });

  test('T-22-GEN-10: Android 이스케이프 — 엔티티 · 역슬래시 · 맨 앞 @ ? 규칙', () async {
    expect(
      gen.escapeAndroidString("A&B<C>'D\"E\\F\nG"),
      "A&amp;B&lt;C&gt;\\'D\\\"E\\\\F\\nG",
    );
    expect(gen.escapeAndroidString('@x'), r'\@x');
    expect(gen.escapeAndroidString('?x'), r'\?x');
    expect(gen.escapeAndroidString('a@b'), 'a@b');
    expect(gen.escapeAndroidString('a?b'), 'a?b');

    // Android 쓰기가 같은 이스케이프를 쓴다.
    writeFixtureProject(project, <String, String?>{
      'en': 'RunningPencil',
      'ko': '@러닝 & <펜슬>',
    });
    final Directory out = await runAndroid(project);
    expect(
      readAndroidAppName(File('${out.path}/values-ko/strings.xml')),
      gen.escapeAndroidString('@러닝 & <펜슬> Dev'),
    );
    expect(
      readAndroidAppName(File('${out.path}/values-ko/strings.xml')),
      r'\@러닝 &amp; &lt;펜슬&gt; Dev',
    );
  });

  test('T-22-GEN-11: 기존 InfoPlist.strings 의 다른 키는 남고 출력은 binary 다', () async {
    writeFixtureProject(project, <String, String?>{
      'en': 'RunningPencil',
      'ko': '러닝펜슬',
      'ja': 'ランニングペンシル',
    });
    createBuiltInfoPlist(project);
    final File ko = infoPlistStringsOf(project, 'ko');
    ko.parent.createSync(recursive: true);
    ko.writeAsStringSync('"NSCameraUsageDescription" = "카메라";\n');
    expect(isBinaryPlist(ko), isFalse);

    await runIos(project);

    expect(isBinaryPlist(ko), isTrue);
    expect(readPlist(ko), <String, Object?>{
      'NSCameraUsageDescription': '카메라',
      'CFBundleDisplayName': '러닝펜슬 Dev',
    });
    final File ja = infoPlistStringsOf(project, 'ja');
    expect(isBinaryPlist(ja), isTrue);
    expect(readPlist(ja), <String, Object?>{
      'CFBundleDisplayName': 'ランニングペンシル Dev',
    });
  }, skip: skipWithoutPlutil);

  test('T-22-GEN-12: ARB 에서 빠진 언어는 기록 파일 기준으로 표시 이름 키만 지운다', () async {
    writeFixtureProject(project, <String, String?>{
      'en': 'RunningPencil',
      'ko': '러닝펜슬',
      'ja': 'ランニングペンシル',
    });
    createBuiltInfoPlist(project);
    writeBinaryPlist(infoPlistStringsOf(project, 'ko'), <String, Object?>{
      'NSCameraUsageDescription': '카메라',
    });
    // 기록에 없는 언어에 adopter 가 직접 둔 표시 이름.
    final File fr = infoPlistStringsOf(project, 'fr');
    writeBinaryPlist(fr, <String, Object?>{'CFBundleDisplayName': 'Mon App'});

    await runIos(project);
    expect(readManifestLines(project), <String>['ja.lproj', 'ko.lproj']);
    expect(listLprojWithStrings(project), <String>['fr', 'ja', 'ko']);

    // 2회차 — ja ARB 를 지운다: 키 하나뿐인 ja 는 파일 · lproj 까지 사라진다.
    File('${project.path}/lib/l10n/app_ja.arb').deleteSync();
    await runIos(project);
    expect(
      Directory('${bundleDirOf(project).path}/ja.lproj').existsSync(),
      isFalse,
    );
    expect(readManifestLines(project), <String>['ko.lproj']);
    expect(
      readPlist(infoPlistStringsOf(project, 'ko'))['CFBundleDisplayName'],
      '러닝펜슬 Dev',
    );

    // 3회차 — ko ARB 를 지운다: 표시 이름 키만 빠지고 adopter 키 · 파일은 남는다.
    File('${project.path}/lib/l10n/app_ko.arb').deleteSync();
    await runIos(project);
    final File ko = infoPlistStringsOf(project, 'ko');
    expect(ko.existsSync(), isTrue);
    expect(isBinaryPlist(ko), isTrue);
    expect(readPlist(ko), <String, Object?>{'NSCameraUsageDescription': '카메라'});
    expect(readManifestLines(project), isEmpty);
    expect(readPlist(fr), <String, Object?>{'CFBundleDisplayName': 'Mon App'});
  }, skip: skipWithoutPlutil);

  test(
    'T-22-GEN-13: 빌드된 Info.plist 의 CFBundleLocalizations 를 ARB 언어 목록으로 덮는다',
    () async {
      writeFixtureProject(project, <String, String?>{
        'en': 'RunningPencil',
        'ko': '러닝펜슬',
        'ja': null,
        'zh_Hant': '跑步鉛筆',
      });
      final File infoPlist = createBuiltInfoPlist(
        project,
        entries: <String, Object?>{
          'CFBundleDisplayName': fixtureConfigName,
          'CFBundleLocalizations': <String>['xx'],
        },
      );

      await runIos(project);

      expect(isBinaryPlist(infoPlist), isTrue);
      expect(readPlist(infoPlist), <String, Object?>{
        'CFBundleDisplayName': fixtureConfigName,
        'CFBundleLocalizations': <String>['en', 'ja', 'ko', 'zh-Hant'],
      });

      infoPlist.deleteSync();
      await expectLater(
        runIos(project),
        throwsGeneratorError(<String>['Info.plist']),
      );
    },
    skip: skipWithoutPlutil,
  );

  test('T-22-GEN-14: 따옴표 · 역슬래시 · 줄바꿈이 든 이름이 plutil 로 다시 읽어도 같다', () async {
    const quoted = r'Say "Hi" \';
    const multiline = 'line1\nline2';
    writeFixtureProject(project, <String, String?>{
      'en': 'RunningPencil',
      'ko': quoted,
      'ja': multiline,
    });
    createBuiltInfoPlist(project);

    await runIos(project);

    expect(
      extractRaw(infoPlistStringsOf(project, 'ko'), 'CFBundleDisplayName'),
      '$quoted Dev',
    );
    expect(
      extractRaw(infoPlistStringsOf(project, 'ja'), 'CFBundleDisplayName'),
      '$multiline Dev',
    );
  }, skip: skipWithoutPlutil);

  test('T-22-GEN-15: 생성기는 dart: import 만 쓰는 파일 하나이고 쓰는 키는 셋뿐이다', () {
    final String source = readTrackedFile('tool/launcher_names.dart');
    final List<String> lines = source.split('\n');

    final importLines = <String>[
      for (final line in lines)
        if (RegExp(r'^\s*import\s').hasMatch(line)) line,
    ];
    // 양성 대조 — import 줄을 실제로 찾는다.
    expect(importLines, isNotEmpty);
    for (final line in importLines) {
      expect(line, matches(RegExp(r"^\s*import\s+'dart:[a-z_]+';\s*$")));
    }
    expect(
      lines.where((String line) => RegExp(r'^\s*part\s').hasMatch(line)),
      isEmpty,
    );

    final generatorFiles = <String>[
      for (final entity in Directory('tool').listSync())
        if (entity is File &&
            RegExp(
              r'^launcher_names.*\.dart$',
            ).hasMatch(entity.uri.pathSegments.last))
          entity.uri.pathSegments.last,
    ];
    expect(generatorFiles, <String>['launcher_names.dart']);

    // 쓰는 키: Android app_name · iOS CFBundleDisplayName · CFBundleLocalizations.
    final String code = stripSlashComments(source);
    expect(code, contains('<string name="app_name">'));
    expect(code, contains("'CFBundleDisplayName'"));
    expect(code, contains("'CFBundleLocalizations'"));
    for (final key in <String>[
      'FacebookDisplayName',
      'NidAppName',
      'naver_client_name',
      'CFBundleName',
    ]) {
      expect(code, isNot(contains("'$key'")), reason: key);
    }
    expect(
      RegExp('<string name="').allMatches(code).length,
      1,
      reason: 'Android 리소스 이름은 app_name 하나',
    );
  });

  test(
    'T-22-GEN-16: 같은 fixture 의 iOS 실제 출력이 Android 출력과 같은 기대 표를 따른다',
    () async {
      writeFixtureProject(project, fixtureAppTitles);
      final Directory androidOut = await runAndroid(project);
      final File infoPlist = createBuiltInfoPlist(project);

      await runIos(project);

      expect(listLprojWithStrings(project), expectedLprojNames);
      for (final expected in expectedOutputs) {
        final String iosName = extractRaw(
          infoPlistStringsOf(project, expected.lproj),
          'CFBundleDisplayName',
        );
        final String androidName = readAndroidAppName(
          File('${androidOut.path}/${expected.androidDir}/strings.xml'),
        );
        expect(iosName, expected.name, reason: expected.lproj);
        expect(iosName, androidName, reason: expected.locale);
      }
      expect(readPlist(infoPlist)['CFBundleLocalizations'], <String>[
        'de',
        'en',
        'es',
        'es-419',
        'fil',
        'fr',
        'he',
        'id',
        'ja',
        'ko',
        'pt',
        'pt-BR',
        'yi',
        'zh',
        'zh-Hant',
      ]);
    },
    skip: skipWithoutPlutil,
  );

  test('예기치 못한 실패도 error: 줄 하나로 알리고 코드 1 로 끝낸다', () async {
    writeFixtureProject(project, fixtureAppTitles);
    // 출력 디렉터리 자리에 일반 파일을 두면 디렉터리를 만들다 FileSystemException 이 난다.
    final blocker = File('${project.path}/android-out')
      ..writeAsStringSync('not a directory');
    final Process process = await Process.start('fvm', <String>[
      'dart',
      '${Directory.current.path}/tool/launcher_names.dart',
      'android',
      '--project-root',
      project.path,
      '--out',
      blocker.path,
      '--flavor',
      'dev',
      '--app-name',
      fixtureConfigName,
    ]);
    final Future<String> out = process.stdout.transform(utf8.decoder).join();
    final Future<String> err = process.stderr.transform(utf8.decoder).join();
    final int code = await process.exitCode.timeout(
      const Duration(seconds: 50),
      onTimeout: () {
        // 멈춘 생성기 프로세스를 남기지 않는다.
        process.kill();
        throw TimeoutException('생성기가 끝나지 않았다');
      },
    );
    final String stderrText = await err;
    await out;

    expect(code, 1, reason: stderrText);
    final errorLines = <String>[
      for (final String line in const LineSplitter().convert(stderrText))
        if (line.startsWith('error: launcher_names: ')) line,
    ];
    expect(errorLines, hasLength(1), reason: stderrText);
    expect(errorLines.single, contains('FileSystemException'));
  });

  group('T-23-GEN-01: readL10nConfig 가 l10n.yaml 두 줄을 읽는다', () {
    test('T-23-GEN-01: 따옴표 값 · # 주석 줄이 있어도 다섯 값을 돌려준다', () {
      File('${project.path}/l10n.yaml').writeAsStringSync(
        '# 앱 문구 설정\n'
        'arb-dir: "lib/l10n/"\n'
        "template-arb-file: 'app_en.arb' # template\n"
        'output-dir: lib/l10n/generated\n',
      );

      final gen.L10nConfig config = gen.readL10nConfig(project.path);

      expect(config.arbDir, 'lib/l10n');
      expect(config.templateArbFile, 'app_en.arb');
      expect(config.templatePath, 'lib/l10n/app_en.arb');
      expect(config.arbFilePrefix, 'app_');
      expect(config.templateLocale, 'en');
    });

    test('T-23-GEN-01: l10n.yaml 이 없으면 GeneratorException', () {
      expect(
        () => gen.readL10nConfig(project.path),
        throwsGeneratorError(<String>['l10n.yaml 을 찾지 못했다', 'l10n.yaml']),
      );
    });

    for (final (String label, String body) in <(String, String)>[
      ('arb-dir 없음', 'template-arb-file: app_en.arb\n'),
      ('template-arb-file 값이 빔', 'arb-dir: lib/l10n\ntemplate-arb-file:\n'),
    ]) {
      test('T-23-GEN-01: $label 이면 GeneratorException', () {
        File('${project.path}/l10n.yaml').writeAsStringSync(body);

        expect(
          () => gen.readL10nConfig(project.path),
          throwsGeneratorError(<String>['arb-dir 또는 template-arb-file 이 없다']),
        );
      });
    }
  });

  group('T-23-GEN-02: listArbFiles 가 ARB 파일만 경로 순으로 돌려준다', () {
    const config = gen.L10nConfig('lib/l10n', 'app_en.arb');

    test('T-23-GEN-02: .arb 만 · 경로 순 · 다른 확장자 제외', () {
      final arbDir = Directory('${project.path}/lib/l10n')
        ..createSync(recursive: true);
      for (final name in <String>[
        'app_zh_Hant.arb',
        'app_pt_BR.arb',
        'app_ko.arb',
        'app_pt.arb',
        'app_ja.arb',
        'app_ko.json',
        'app_ko.arb.bak',
      ]) {
        File('${arbDir.path}/$name').writeAsStringSync('{}');
      }

      final List<File> files = gen.listArbFiles(project.path, config);

      expect(
        <String>[for (final file in files) file.uri.pathSegments.last],
        <String>[
          'app_ja.arb',
          'app_ko.arb',
          'app_pt.arb',
          'app_pt_BR.arb',
          'app_zh_Hant.arb',
        ],
      );
      expect(files.first.path, '${project.path}/lib/l10n/app_ja.arb');
    });

    test('T-23-GEN-02: ARB 디렉터리가 없으면 GeneratorException', () {
      expect(
        () => gen.listArbFiles(project.path, config),
        throwsGeneratorError(<String>['ARB 디렉터리 lib/l10n 를 찾지 못했다']),
      );
    });

    test('T-23-GEN-02: template 이름에서 locale 을 못 읽으면 GeneratorException', () {
      Directory('${project.path}/lib/l10n').createSync(recursive: true);

      expect(
        () => gen.listArbFiles(
          project.path,
          const gen.L10nConfig('lib/l10n', 'en.arb'),
        ),
        throwsGeneratorError(<String>['template ARB 이름에서 locale 을 읽을 수 없다']),
      );
    });
  });

  test('T-23-GEN-03: localeFromArbFileName 이 파일 이름에서 locale 을 읽는다', () {
    expect(
      gen.localeFromArbFileName('app_pt_BR.arb', 'app_', 'lib/l10n'),
      'pt_BR',
    );
    expect(
      gen.localeFromArbFileName('app_zh_Hant.arb', 'app_', 'lib/l10n'),
      'zh_Hant',
    );
    expect(gen.localeFromArbFileName('app_ko.arb', 'app_', 'lib/l10n'), 'ko');
    for (final name in <String>['app-ko.arb', 'app_k.arb']) {
      expect(
        () => gen.localeFromArbFileName(name, 'app_', 'lib/l10n'),
        throwsGeneratorError(<String>[
          'ARB 파일 이름의 locale 을 읽을 수 없다',
          'lib/l10n/$name',
        ]),
        reason: name,
      );
    }
  });

  test('T-23-GEN-04: hasLauncherNameWhitespaceIssue 는 앞뒤 공백 · 이어진 공백만 잡는다', () {
    const table = <(String, bool)>[
      ('마이  앱', true),
      (' 마이앱', true),
      ('마이앱 ', true),
      ('\t마이앱', true),
      ('마이\t\t앱', true),
      ('마이앱', false),
      ('My App', false),
      ('마이\t앱', false),
    ];
    for (final (String name, bool expected) in table) {
      expect(
        gen.hasLauncherNameWhitespaceIssue(name),
        expected,
        reason: jsonEncode(name),
      );
    }
  });
}
