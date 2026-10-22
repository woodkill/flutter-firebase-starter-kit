import 'dart:io';

import 'package:test/test.dart';

/// 위저드 소스 디렉터리 — 저장소 루트 상대 경로.
const String wizardSourceDirectory = 'tool/setup';

/// 로그인 수단을 켜는 절차가 있는 설정 가이드 — 저장소 루트 상대 경로.
const String setupGuidePath = 'docs/setup.md';

/// 로그인 수단을 켜는 setup.md 절 머리.
const String providersSectionHeading = '## 로그인 수단 켜기';

/// [providersSectionHeading] 바로 아래 첫 줄 — 위저드로 켜라는 안내 문장 전체.
const String providersWizardLine =
    '> **로그인 수단은 저장소 루트에서 `./setup.sh --providers` 로 켠다 — 설정 위저드가 '
    '체크 목록을 열고, 수단마다 콘솔에 넣을 값을 보여 준 뒤 키를 받아 기록하고 '
    '배포한다.**';

/// 서로 다른 DocRef (문서 파일, 머리) 쌍 수의 하한 — 수집이 비어 공허하게
/// 통과하지 않게 한다(로그인 수단 여섯 · 이메일 받기 · flavor 새 앱 · secret
/// 확인 절만 세어도 이만큼이다).
const int minDocRefCount = 9;

/// 작은따옴표 문자열 전체가 문서 머리(`## ` · `### ` 로 시작)인 리터럴.
final RegExp headingLiteral = RegExp("'(#{2,3} [^']+)'");

/// 위저드의 문서 참조 리터럴 — `DocRef(<문서 파일>, <머리>)` 의 두 작은따옴표
/// 인자를 잡는다(포매터가 인자를 여러 줄로 나눠도 맞는다).
final RegExp docRefLiteral = RegExp(
  r"DocRef\(\s*'([^']+)',\s*'(#{2,3} [^']+)',?\s*\)",
);

/// 수집기 양성 대조용 표본 소스 — DocRef 안의 머리 둘(한 줄 · 여러 줄)과
/// DocRef 밖의 머리 리터럴 하나.
const String sampleWizardSource = '''
const DocRef a = DocRef('docs/setup.md', '### 가 절');
const DocRef b = DocRef(
  'docs/guide.md',
  '## 나 절',
);
const String c = '## 밖 절';
''';

/// 위저드가 가리키는 문서 절 하나 — 문서 파일 경로와 그 절의 머리 줄.
typedef DocRefPair = ({String file, String heading});

/// [directory] 아래의 `.dart` 파일 경로를 재귀로 모아 정렬해 돌려준다.
List<String> listDartSources(String directory) =>
    Directory(directory)
        .listSync(recursive: true)
        .whereType<File>()
        .map((File file) => file.path)
        .where((String path) => path.endsWith('.dart'))
        .toList()
      ..sort();

/// [source] 의 작은따옴표 리터럴 가운데 문서 머리를 순서대로 뽑는다.
List<String> extractHeadingLiterals(String source) => headingLiteral
    .allMatches(source)
    .map((RegExpMatch match) => match.group(1)!)
    .toList();

/// [source] 에서 DocRef 리터럴을 지운다 — 그 밖의 머리 리터럴만 남긴다.
String removeDocRefs(String source) => source.replaceAll(docRefLiteral, '');

/// [source] 의 DocRef 리터럴을 (문서 파일, 머리) 쌍으로 순서대로 뽑는다.
List<DocRefPair> extractDocRefs(String source) => docRefLiteral
    .allMatches(source)
    .map(
      (RegExpMatch match) => (file: match.group(1)!, heading: match.group(2)!),
    )
    .toList();

/// [paths] 의 파일에서 DocRef 밖의 문서 머리 리터럴을 모아 중복 없이 정렬해
/// 돌려준다.
List<String> collectStrayHeadings(List<String> paths) {
  final headings = <String>{
    for (final path in paths)
      ...extractHeadingLiterals(removeDocRefs(File(path).readAsStringSync())),
  };
  return headings.toList()..sort();
}

/// [paths] 의 파일에서 DocRef 쌍을 중복 없이 모은다.
Set<DocRefPair> collectDocRefs(List<String> paths) => <DocRefPair>{
  for (final path in paths) ...extractDocRefs(File(path).readAsStringSync()),
};

/// [lines] 에서 [heading] 과 같은 줄 다음의 비지 않은 첫 줄을 찾는다 — 없으면 null.
String? findLineAfterHeading(List<String> lines, String heading) {
  final int index = lines.indexOf(heading);
  if (index < 0) {
    return null;
  }
  for (final String line in lines.skip(index + 1)) {
    if (line.trim().isNotEmpty) {
      return line;
    }
  }
  return null;
}

/// [text] 안에 [pattern] 이 나오는 횟수를 센다.
int countOccurrences(String text, String pattern) =>
    pattern.allMatches(text).length;

void main() {
  test('T-21-WIZ-01: 위저드의 DocRef 머리가 그 문서에 한 줄씩 있다', () {
    final Set<DocRefPair> refs = collectDocRefs(
      listDartSources(wizardSourceDirectory),
    );

    expect(refs.length, greaterThanOrEqualTo(minDocRefCount));
    for (final ref in refs) {
      expect(ref.file, startsWith('docs/'));
      final document = File(ref.file);
      expect(document.existsSync(), isTrue, reason: '${ref.file} 문서가 없다');
      expect(
        document.readAsLinesSync().where((String line) => line == ref.heading),
        hasLength(1),
        reason:
            '${ref.file} 에 「${ref.heading}」 줄이 한 번 있어야 한다 — 문서 절 '
            '제목을 바꿨으면 위저드의 DocRef 도 함께 고친다',
      );
    }
  });

  test('T-20-DOCS-01: tool/setup 에 DocRef 밖 문서 머리 리터럴이 없다', () {
    final List<String> sources = listDartSources(wizardSourceDirectory);

    // 양성 대조 — 수집기는 DocRef 밖에 남은 머리 리터럴을 잡는다.
    expect(extractHeadingLiterals(removeDocRefs(sampleWizardSource)), <String>[
      '## 밖 절',
    ]);
    expect(sources, isNotEmpty);
    expect(
      collectStrayHeadings(sources),
      isEmpty,
      reason:
          '위저드가 문서 절을 가리킬 때는 DocRef 로 쓴다 — 그래야 T-21-WIZ-01 이 '
          '그 머리를 문서에서 확인한다',
    );
  });

  test('T-20-DOCS-02: setup.md 로그인 수단 켜기 다음 줄이 위저드 안내다', () {
    final String setup = File(setupGuidePath).readAsStringSync();
    final List<String> setupLines = setup.split('\n');

    expect(
      setupLines.where((String line) => line == providersSectionHeading),
      hasLength(1),
    );
    final String? firstLine = findLineAfterHeading(
      setupLines,
      providersSectionHeading,
    );
    expect(firstLine, isNotNull);
    expect(firstLine, providersWizardLine);
    expect(countOccurrences(setup, providersWizardLine), 1);
  });

  test('T-20-DOCS-03: 양성 대조 — 수집기는 머리 리터럴 · DocRef 만 잡고 없는 절은 '
      '걸러진다', () {
    final List<String> setupLines = File(setupGuidePath).readAsLinesSync();

    // 수집기는 머리 리터럴만 뽑는다 — 한 줄짜리 `#` · 큰따옴표는 대상 밖이다.
    expect(
      extractHeadingLiterals(
        "const a = '## 가 절'; const b = '# 머리'; const c = \"## 나 절\";"
        " const d = '### 다 절 (꼬리)';",
      ),
      <String>['## 가 절', '### 다 절 (꼬리)'],
    );
    // DocRef 는 인자를 여러 줄로 나눠도 (문서 파일, 머리) 쌍으로 잡힌다.
    expect(extractDocRefs(sampleWizardSource), <DocRefPair>[
      (file: 'docs/setup.md', heading: '### 가 절'),
      (file: 'docs/guide.md', heading: '## 나 절'),
    ]);
    // 없는 절 머리는 setup.md 에 한 줄도 없다 — T-21-WIZ-01 이 그런 DocRef 를 잡는다.
    expect(setupLines.where((String line) => line == '### 없는 절'), isEmpty);
    expect(findLineAfterHeading(setupLines, '## 없는 절'), isNull);
    // 머리 다음의 빈 줄 · 공백 줄은 건너뛴다.
    expect(
      findLineAfterHeading(<String>['## 가', '', '  ', '첫 줄', '둘째 줄'], '## 가'),
      '첫 줄',
    );
  });
}
