import 'dart:io';

import 'package:test/test.dart';

/// 위저드 소스(화면 문구 · 주석 · 문서 주석)에 쓰지 않는 패턴.
///
/// 사용자 문서 금지 패턴(`test/helpers/source_text.dart` 의
/// `kUserDocForbiddenPatternSource`)에서 내부 기록 이름 갈래(`project_…` 꼴 —
/// Dart 파일 이름 · JSON 키와 겹친다)와 16진 해시 갈래(색 값 · 해시 값과 겹친다)를
/// 뺀 코드용 목록이다.
const List<String> forbiddenSourcePatterns = <String>[
  'Phase [0-9]',
  r'\bD-[0-9]{2}\b',
  r'\bD-[A-Z]+-[0-9]',
  r'\b(WR|IN|CR|BL)-[0-9]',
  r'\.planning',
  r'\bquick [0-9]{6}',
  r'\b[0-9]{6}-[a-z0-9]{3}\b',
  r'\bUAT',
  '실측',
  '재현됐',
  r'\bmemory\b',
  r'\bgsd[-:]',
  '20[0-9]{2}-[0-9]{2}-[0-9]{2}',
];

/// 위저드 테스트에 쓰지 않는 패턴 — 작업 단계 표기 · 결정 ID · 작업 기록 경로.
const List<String> forbiddenTestPatterns = <String>[
  'Phase [0-9]',
  r'\bD-[0-9]{2}\b',
  r'\.planning',
];

/// 이 잠금 테스트 자신의 경로 — 패턴 원문을 담고 있어 검사에서 뺀다.
const String lockTestPath = 'test/tool/setup/message_lock_test.dart';

/// 위저드 소스 검사 파일 수의 하한 — 목록이 비어 공허하게 통과하지 않게 한다.
const int minSourceFileCount = 8;

/// [directory] 아래의 `.dart` 파일 경로를 재귀로 모아 정렬해 돌려준다.
List<String> listDartFiles(String directory) =>
    Directory(directory)
        .listSync(recursive: true)
        .whereType<File>()
        .map((File file) => file.path)
        .where((String path) => path.endsWith('.dart'))
        .toList()
      ..sort();

/// [paths] 의 줄 가운데 [patterns] 에 걸리는 곳을 `<경로>:<줄>: <패턴>` 으로 모은다.
List<String> findViolations(List<String> paths, List<String> patterns) {
  final List<RegExp> expressions = patterns.map(RegExp.new).toList();
  final violations = <String>[];
  for (final path in paths) {
    final List<String> lines = File(path).readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      for (final expression in expressions) {
        if (expression.hasMatch(lines[i])) {
          violations.add('$path:${i + 1}: ${expression.pattern}');
        }
      }
    }
  }
  return violations;
}

void main() {
  test('T-19-COPY-01: 위저드 소스 전문에 작업 기록 표기 · 날짜 · 내부 도구 이름이 없다', () {
    final sources = <String>[
      'setup.sh',
      'bin/setup.dart',
      ...listDartFiles('tool/setup'),
    ];

    expect(sources.length, greaterThanOrEqualTo(minSourceFileCount));
    expect(findViolations(sources, forbiddenSourcePatterns), isEmpty);

    // 양성 대조 — 읽은 본문이 실제 위저드 문구를 담고 있다.
    final String combined = sources
        .map((String path) => File(path).readAsStringSync())
        .join('\n');
    expect(combined, contains('점검표'));
  });

  test('T-19-COPY-02: 위저드 테스트에 작업 단계 표기 · 결정 ID · 작업 기록 경로가 없다', () {
    final List<String> tests = listDartFiles(
      'test/tool/setup',
    ).where((String path) => path != lockTestPath).toList();

    expect(tests, isNotEmpty);
    expect(tests, isNot(contains(lockTestPath)));
    expect(findViolations(tests, forbiddenTestPatterns), isEmpty);
  });

  test('금지 패턴은 실제로 걸리는 문장을 잡는다', () {
    final Directory temp = Directory.systemTemp.createTempSync('lock_test_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final sample = File('${temp.path}/sample.dart')
      ..writeAsStringSync(
        '// Phase 1 · D-12 · .planning\n'
        '// 2030-01-02 · UAT · memory\n'
        '// setup-20300102-030405.log\n',
      );

    final List<String> found = findViolations(<String>[
      sample.path,
    ], forbiddenSourcePatterns);

    expect(found.length, 6);
    expect(found.where((String line) => line.contains(':3:')), isEmpty);
  });
}
