import 'dart:io';

import 'package:test/test.dart';

/// 위저드 소스 디렉터리 — 저장소 루트 상대 경로.
const String wizardSourceDirectory = 'tool/setup';

/// 위저드가 가리키는 사용자 매뉴얼 — 저장소 루트 상대 경로.
const String manualPath = 'docs/manual.md';

/// 로그인 수단을 켜고 끄는 매뉴얼 절 머리.
const String providersSectionHeading = '## 로그인 수단 켜고 끄기';

/// [providersSectionHeading] 바로 아래 첫 줄이 시작하는 안내 문장.
const String providersWizardLine =
    '> **로그인 수단을 켜고 끄는 일은 저장소 루트에서 `./setup.sh --providers` 를 '
    '실행하면 설정 위저드가 대신한다.**';

/// DocRef 밖에 남은 매뉴얼 절 머리 수의 하한 — 수집이 비어 공허하게 통과하지
/// 않게 한다.
const int minManualHeadingCount = 1;

/// 서로 다른 DocRef (문서 파일, 머리) 쌍 수의 하한 — 로그인 수단 여섯 · 이메일
/// 받기 · flavor 새 앱 · secret 확인 절.
const int minDocRefCount = 9;

/// 작은따옴표 문자열 전체가 매뉴얼 절 머리(`## ` · `### ` 로 시작)인 리터럴.
final RegExp manualHeadingLiteral = RegExp("'(#{2,3} [^']+)'");

/// 위저드의 문서 참조 리터럴 — `DocRef(<문서 파일>, <머리>)` 의 두 작은따옴표
/// 인자를 잡는다(포매터가 인자를 여러 줄로 나눠도 맞는다).
final RegExp docRefLiteral = RegExp(
  r"DocRef\(\s*'([^']+)',\s*'(#{2,3} [^']+)',?\s*\)",
);

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

/// [source] 의 작은따옴표 리터럴 가운데 매뉴얼 절 머리를 순서대로 뽑는다.
List<String> extractManualHeadings(String source) => manualHeadingLiteral
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

/// [paths] 의 파일에서 DocRef 밖의 매뉴얼 절 머리를 모아 중복 없이 정렬해
/// 돌려준다.
List<String> collectManualHeadings(List<String> paths) {
  final headings = <String>{
    for (final path in paths)
      ...extractManualHeadings(removeDocRefs(File(path).readAsStringSync())),
  };
  return headings.toList()..sort();
}

/// [paths] 의 파일에서 DocRef 쌍을 중복 없이 모은다.
Set<DocRefPair> collectDocRefs(List<String> paths) => <DocRefPair>{
  for (final path in paths) ...extractDocRefs(File(path).readAsStringSync()),
};

/// [headings] 가운데 [manualLines] 의 어느 머리 줄(`#` 로 시작)의 앞부분과도
/// 같지 않은 것을 돌려준다.
List<String> findUnmatchedHeadings(
  List<String> headings,
  List<String> manualLines,
) {
  final List<String> headingLines = manualLines
      .where((String line) => line.startsWith('#'))
      .toList();
  return headings
      .where(
        (String heading) =>
            !headingLines.any((String line) => line.startsWith(heading)),
      )
      .toList();
}

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

  test('T-20-DOCS-01: DocRef 밖 절 머리 리터럴은 원본 매뉴얼에 있다', () {
    final List<String> headings = collectManualHeadings(
      listDartSources(wizardSourceDirectory),
    );
    final List<String> manualLines = File(manualPath).readAsLinesSync();

    expect(headings.length, greaterThanOrEqualTo(minManualHeadingCount));
    expect(
      findUnmatchedHeadings(headings, manualLines),
      isEmpty,
      reason: '위저드 문구가 가리키는 매뉴얼 절이 없다',
    );
  });

  test('T-20-DOCS-02: 「로그인 수단 켜고 끄기」 절 머리에 위저드 안내 한 줄이 있다', () {
    final String manual = File(manualPath).readAsStringSync();
    final List<String> manualLines = manual.split('\n');
    final List<String> headings = collectManualHeadings(
      listDartSources(wizardSourceDirectory),
    );

    // 위저드가 이 절을 가리키고, 매뉴얼에 그 절 머리가 한 줄 있다.
    expect(headings, contains(providersSectionHeading));
    expect(
      manualLines.where((String line) => line == providersSectionHeading),
      hasLength(1),
    );
    final String? firstLine = findLineAfterHeading(
      manualLines,
      providersSectionHeading,
    );
    expect(firstLine, isNotNull);
    expect(firstLine, startsWith(providersWizardLine));
    expect(countOccurrences(manual, providersWizardLine), 1);
  });

  test('T-20-DOCS-03: 양성 대조 — 없는 절 머리는 걸러진다', () {
    final List<String> manualLines = File(manualPath).readAsLinesSync();

    // 수집기는 머리 리터럴만 뽑는다 — 한 줄짜리 `#` · 큰따옴표는 대상 밖이다.
    expect(
      extractManualHeadings(
        "const a = '## 가 절'; const b = '# 머리'; const c = \"## 나 절\";"
        " const d = '### 다 절 (꼬리)';",
      ),
      <String>['## 가 절', '### 다 절 (꼬리)'],
    );
    expect(findUnmatchedHeadings(<String>['## 없는 절'], manualLines), <String>[
      '## 없는 절',
    ]);
    // 실제 절 머리의 앞부분은 통과한다(절 제목 뒤 꼬리는 접두 일치로 흡수).
    expect(
      findUnmatchedHeadings(<String>[providersSectionHeading], manualLines),
      isEmpty,
    );
    expect(findLineAfterHeading(manualLines, '## 없는 절'), isNull);
  });
}
