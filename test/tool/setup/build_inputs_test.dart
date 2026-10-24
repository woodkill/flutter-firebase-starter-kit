import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/setup/build_inputs.dart';
import '../../../tool/setup/flavor.dart';
import '../../../tool/setup/setup_entry.dart';
import '../../../tool/setup/step.dart';
import '../../../tool/setup/wizard.dart';
import 'fakes.dart';

/// 코드 생성 지시문 꼴 — 시험이 스스로 세는 데 쓴다(구현과 따로 둔다).
final RegExp generatedPartDirective = RegExp(
  r"^part '([^']+\.(g|freezed)\.dart)';",
);

/// 검사에서 본 세션의 시작 지문을 남기는 끝난 단계 — 검사는 늘 끝남이다.
final class _ProbeStep implements Step {
  /// 검사할 때 본 시작 지문 — 검사 전이면 null.
  Map<String, String?>? seenAtStart;

  /// 검사한 횟수.
  int checkCount = 0;

  @override
  String get id => 'probe';

  @override
  String get title => '시작 지문 확인';

  @override
  List<String> get dependsOn => const <String>[];

  @override
  bool get isCostlyOrIrreversible => false;

  @override
  Future<CheckResult> check(WizardContext context) async {
    checkCount++;
    seenAtStart ??= context.session.buildInputsAtStart;
    return const Done('확인함');
  }

  @override
  List<String> plannedCommandLines(WizardContext context) => const <String>[];

  @override
  Future<StepOutcome> apply(WizardContext context) async => const Applied();
}

/// [root] 아래 [relativePath] 파일을 [content] 로 쓴다(디렉터리를 만든다).
void writeFileUnder(String root, String relativePath, String content) {
  File('$root/$relativePath')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(content);
}

/// [root] 의 `lib` 아래 코드 생성 지시문을 세고 대상 가운데 없는 것이 있는지
/// 본다 — 시험이 기대값을 스스로 계산할 때 쓴다.
({int directives, bool hasMissing}) countGeneratedParts(String root) {
  final lib = Directory('$root/lib');
  var directives = 0;
  var hasMissing = false;
  for (final FileSystemEntity entity in lib.listSync(recursive: true)) {
    if (entity is! File) continue;
    final String path = entity.path;
    if (!path.endsWith('.dart')) continue;
    if (path.endsWith('.g.dart') || path.endsWith('.freezed.dart')) continue;
    for (final String line in entity.readAsLinesSync()) {
      final RegExpMatch? match = generatedPartDirective.firstMatch(line);
      if (match == null) continue;
      directives++;
      if (!File('${entity.parent.path}/${match.group(1)}').existsSync()) {
        hasMissing = true;
      }
    }
  }
  return (directives: directives, hasMissing: hasMissing);
}

void main() {
  late Directory tempDir;
  late String root;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('build_inputs_test_');
    root = tempDir.path;
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('T-21-BUILD-01: 지문은 경로 목록 순서의 다섯 키 · 없는 파일은 null · '
      '같은 내용은 같은 지문 · 한 글자 다르면 다른 지문', () {
    const paths = FlavorPaths(Flavor.dev);
    final WizardContext context = buildTestContext(projectRoot: root);
    writeFileUnder(root, paths.json, '{"a":"1"}\n');
    writeFileUnder(root, paths.xcconfig, '{"a":"1"}\n');

    final Map<String, String?> first = readBuildInputDigests(context);

    expect(first.keys.toList(), buildInputPaths(Flavor.dev));
    expect(first.keys.toList(), <String>[
      paths.json,
      paths.xcconfig,
      paths.dartOptions,
      paths.iosPlist,
      paths.androidJson,
    ]);
    expect(first[paths.json], isNotNull);
    expect(first[paths.json], first[paths.xcconfig]);
    expect(first[paths.dartOptions], isNull);
    expect(first[paths.iosPlist], isNull);
    expect(first[paths.androidJson], isNull);

    writeFileUnder(root, paths.xcconfig, '{"a":"2"}\n');
    final Map<String, String?> second = readBuildInputDigests(context);
    expect(second[paths.json], first[paths.json]);
    expect(second[paths.xcconfig], isNot(first[paths.xcconfig]));
  });

  group('T-21-BUILD-02: 바뀐 경로 목록 · 시작 지문 기록', () {
    test('T-21-BUILD-02: 바뀐 · 생긴 · 사라진 경로만 뒤 지문의 키 순서로 · 같으면 빈 목록', () {
      const before = <String, String?>{'a': '1', 'b': '2', 'c': null, 'd': '4'};
      const after = <String, String?>{'a': '1', 'b': '9', 'c': '3', 'd': null};

      expect(findChangedBuildInputs(before, after), <String>['b', 'c', 'd']);
      expect(findChangedBuildInputs(after, after), isEmpty);
      expect(findChangedBuildInputs(before, before), isEmpty);
    });

    test('T-21-BUILD-02: 두 번 기록해도 첫 기록이 남는다', () {
      const paths = FlavorPaths(Flavor.dev);
      final WizardContext context = buildTestContext(projectRoot: root);
      writeFileUnder(root, paths.json, '{"a":"1"}\n');

      recordBuildInputsAtStart(context);
      final Map<String, String?>? first = context.session.buildInputsAtStart;
      writeFileUnder(root, paths.json, '{"a":"2"}\n');
      recordBuildInputsAtStart(context);

      expect(first, isNotNull);
      expect(context.session.buildInputsAtStart, same(first));
      expect(
        findChangedBuildInputs(first!, readBuildInputDigests(context)),
        <String>[paths.json],
      );
    });
  });

  group('T-21-BUILD-03: 코드 생성 파일 없음 판정', () {
    test('T-21-BUILD-03: g 지시문 대상이 없으면 true · 만들면 false', () {
      writeFileUnder(root, 'lib/a.dart', "part 'a.g.dart';\n");
      expect(hasMissingGeneratedParts(root), isTrue);

      writeFileUnder(root, 'lib/a.g.dart', "part of 'a.dart';\n");
      expect(hasMissingGeneratedParts(root), isFalse);
    });

    test('T-21-BUILD-03: freezed 지시문 대상도 같다', () {
      writeFileUnder(root, 'lib/b.dart', "part 'b.freezed.dart';\n");
      expect(hasMissingGeneratedParts(root), isTrue);

      writeFileUnder(root, 'lib/b.freezed.dart', "part of 'b.dart';\n");
      expect(hasMissingGeneratedParts(root), isFalse);
    });

    test('T-21-BUILD-03: part of 줄만 있으면 false · lib 이 없으면 false', () {
      expect(hasMissingGeneratedParts(root), isFalse);

      writeFileUnder(root, 'lib/x.dart', "part of 'y.dart';\n");
      expect(hasMissingGeneratedParts(root), isFalse);
    });

    test('T-21-BUILD-03: 하위 디렉터리 소스의 지시문은 그 디렉터리 기준', () {
      writeFileUnder(root, 'lib/feature/c.dart', "part 'c.g.dart';\n");
      // 다른 디렉터리의 같은 이름 파일은 대상이 아니다.
      writeFileUnder(root, 'lib/c.g.dart', "part of 'feature/c.dart';\n");
      expect(hasMissingGeneratedParts(root), isTrue);

      writeFileUnder(root, 'lib/feature/c.g.dart', "part of 'c.dart';\n");
      expect(hasMissingGeneratedParts(root), isFalse);
    });

    test('T-21-BUILD-03: 생성 파일 안의 지시문은 보지 않는다', () {
      writeFileUnder(root, 'lib/d.g.dart', "part 'e.g.dart';\n");
      writeFileUnder(root, 'lib/f.freezed.dart', "part 'h.freezed.dart';\n");
      expect(hasMissingGeneratedParts(root), isFalse);
    });
  });

  test('T-21-BUILD-04: 이 저장소의 lib 판정이 시험이 스스로 센 결과와 같다', () {
    final String repoRoot = Directory.current.path;
    final ({int directives, bool hasMissing}) counted = countGeneratedParts(
      repoRoot,
    );

    // 공허한 통과를 막는다 — 지시문이 하나 이상 있어야 판정이 뜻을 갖는다.
    expect(counted.directives, greaterThanOrEqualTo(1));
    expect(hasMissingGeneratedParts(repoRoot), counted.hasMissing);
  });

  test('T-21-BUILD-05: 위저드 진입점은 시작 지문을 기록하는 실행 함수만 부른다', () {
    final String source = File('bin/setup.dart').readAsStringSync();

    expect(RegExp(r'\brunSetupWizard\s*\(').allMatches(source), hasLength(1));
    expect(RegExp(r'(^|[^A-Za-z_])runWizard\s*\(').hasMatch(source), isFalse);
    // 진입 함수는 진입 파일에서 가져온다 — 빌드 입력 지문 파일은 진입점이 쓰지 않는다.
    expect(source, contains("import '../tool/setup/setup_entry.dart';"));
    expect(source, isNot(contains('build_inputs.dart')));

    // 진입 파일의 실행 함수는 위저드 실행 전에 시작 지문을 남긴다.
    final String entry = File('tool/setup/setup_entry.dart').readAsStringSync();
    expect(
      RegExp(
        r'recordBuildInputsAtStart\(context\);\s*return\s+runWizard\(',
      ).allMatches(entry),
      hasLength(1),
    );
    expect(
      File('tool/setup/build_inputs.dart').readAsStringSync(),
      isNot(contains('runSetupWizard')),
    );
  });

  group('T-21-BUILD-06: 진입 실행 함수', () {
    test('T-21-BUILD-06: 첫 검사 전에 시작 지문을 기록하고 끝난 뒤 함수 · 종료 코드는 '
        '위저드 실행과 같다', () async {
      const paths = FlavorPaths(Flavor.dev);
      writeFileUnder(root, paths.json, '{"firebaseProjectId":"demo-p"}\n');
      writeFileUnder(root, paths.xcconfig, 'A = 1\n');
      final WizardContext context = buildTestContext(projectRoot: root);
      final Map<String, String?> atStart = readBuildInputDigests(context);
      final probe = _ProbeStep();
      var completedCount = 0;

      final int code = await runSetupWizard(
        context,
        <Step>[probe],
        onCompleted: (WizardContext completed) async {
          completedCount++;
        },
      );

      expect(probe.checkCount, greaterThanOrEqualTo(1));
      expect(probe.seenAtStart, isNotNull);
      expect(probe.seenAtStart, atStart);
      expect(context.session.buildInputsAtStart, atStart);
      expect(completedCount, 1);

      final WizardContext direct = buildTestContext(projectRoot: root);
      final int directCode = await runWizard(direct, <Step>[_ProbeStep()]);
      expect(code, directCode);
      expect(code, wizardExitDone);
    });

    test('T-21-BUILD-06: 위저드 실행을 직접 부르면 시작 지문은 기록하지 않는다', () async {
      writeFileUnder(root, 'config/dev.json', '{"a":"1"}\n');
      final WizardContext context = buildTestContext(projectRoot: root);
      final probe = _ProbeStep();

      expect(await runWizard(context, <Step>[probe]), wizardExitDone);
      expect(probe.seenAtStart, isNull);
      expect(context.session.buildInputsAtStart, isNull);
    });
  });
}
