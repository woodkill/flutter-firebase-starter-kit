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
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../tool/launcher_names.dart' as gen;

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
}
