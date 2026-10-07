// 매뉴얼 「킷 업데이트 반영」 · README 머리 계약 (Phase 17.4 D-36 · D-37 · D-38 — see ROADMAP.md).
// 헤딩 · 목차 · 사용자 문서 금지 패턴 · 시작 명령 · README 진입점 대조.
//
// T-174-DOCS-01: 절 헤딩 1개 · 목차 항목 1개 · 목차 번호 0부터 연속 · 새 항목이
//   「로그인 수단 켜고 끄기」 항목 바로 다음 줄이다.
// T-174-DOCS-02: 절에 사용자 문서 금지 패턴이 0 건이고, template 시작 명령 4줄이
//   정확한 줄로 각 1개 있다.
// T-174-DOCS-06: README 머리(첫 `## ` 앞)에 Use this template · 매뉴얼 절 링크 ·
//   Issues 안내가 있고 금지 패턴이 0 건이다.

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_text.dart';

/// 매뉴얼 경로.
const String _manualPath = 'docs/manual.md';

/// README 경로.
const String _readmePath = 'README.md';

/// 절 헤딩 (정확히 한 줄).
const String _sectionHeading = '## 킷 업데이트 반영';

/// 목차 항목 줄 (번호는 목차 위치에 따라 바뀌므로 정규식으로 본다).
final RegExp _tocEntryPattern = RegExp(
  r'^\d+\. \[킷 업데이트 반영\]\(#킷-업데이트-반영\)$',
  multiLine: true,
);

/// 새 항목 바로 앞에 있어야 하는 목차 항목.
final RegExp _previousTocEntryPattern = RegExp(
  r'^\d+\. \[로그인 수단 켜고 끄기\]\(#로그인-수단-켜고-끄기\)$',
);

/// 「시작하기 — template」 의 기준점 명령 4줄 (정확한 줄).
const List<String> _templateCommandLines = <String>[
  'git remote add upstream https://github.com/woodkill/flutter-firebase-starter-kit.git',
  'git fetch upstream --tags',
  'git merge -s ours --allow-unrelated-histories "v\$(cat KIT_VERSION)" -m "킷 기준점 v\$(cat KIT_VERSION)"',
  'git push',
];

/// README 머리의 매뉴얼 절 링크.
const String _readmeManualLink = '](docs/manual.md#킷-업데이트-반영)';

/// [text] 에서 사용자 문서 금지 패턴에 걸린 문자열을 모은다.
List<String> _collectForbiddenHits(String text) => RegExp(
  kUserDocForbiddenPatternSource,
).allMatches(text).map((RegExpMatch m) => m.group(0)!).toList();

/// README 에서 첫 `## ` 줄 앞까지(머리)를 돌려준다.
String _sliceReadmeHead(String readme) {
  final int index = readme.indexOf(RegExp(r'^## ', multiLine: true));
  return index == -1 ? readme : readme.substring(0, index);
}

void main() {
  final String manual = readTrackedFile(_manualPath);
  final String readme = readTrackedFile(_readmePath);
  final String section = sliceMarkdownSection(
    manual,
    _sectionHeading,
    maxLevel: 2,
  );

  group('매뉴얼 「킷 업데이트 반영」 계약 (T-174-DOCS)', () {
    test('T-174-DOCS-01: 절 헤딩 1개 · 목차 항목 1개 · 번호 0부터 연속 · 로그인 수단 항목 다음이다', () {
      expect(
        countExactLines(manual, _sectionHeading),
        1,
        reason: '절 헤딩이 없거나 중복이다',
      );

      final String toc = sliceTocBlock(manual);
      expect(toc.trim(), isNotEmpty, reason: '목차 블록을 찾지 못했다');
      expect(
        _tocEntryPattern.allMatches(toc).length,
        1,
        reason: '목차 블록 안 「킷 업데이트 반영」 항목이 없거나 중복이다',
      );

      final List<int> numbers = RegExp(
        r'^(\d+)\. ',
        multiLine: true,
      ).allMatches(toc).map((RegExpMatch m) => int.parse(m.group(1)!)).toList();
      expect(numbers, isNotEmpty, reason: '목차 번호 줄이 없다');
      expect(
        numbers,
        List<int>.generate(numbers.length, (int i) => i),
        reason: '목차 번호가 0부터 빠짐없이 이어지지 않는다',
      );

      final List<String> tocLines = toc.split('\n');
      final int entryIndex = tocLines.indexWhere(_tocEntryPattern.hasMatch);
      expect(entryIndex, greaterThan(0), reason: '목차 항목 위치를 찾지 못했다');
      expect(
        _previousTocEntryPattern.hasMatch(tocLines[entryIndex - 1]),
        isTrue,
        reason: '「킷 업데이트 반영」 항목이 「로그인 수단 켜고 끄기」 바로 다음이 아니다',
      );
    });

    test('T-174-DOCS-02: 절에 금지 패턴이 0 건이고 template 시작 명령 4줄이 있다', () {
      expect(section.trim(), isNotEmpty, reason: '절 슬라이스가 비었다');
      // 양성 대조: 금지 패턴 정규식이 실제로 phase 번호를 잡는다.
      expect(_collectForbiddenHits('Phase 9'), isNotEmpty);
      final List<String> hits = _collectForbiddenHits(section);
      expect(hits, isEmpty, reason: '금지 패턴이 절에 있다: $hits');

      for (final String line in _templateCommandLines) {
        expect(
          countExactLines(section, line),
          1,
          reason: 'template 시작 명령 줄이 없거나 중복이다: $line',
        );
      }
    });
  });

  group('README 머리 계약 (T-174-DOCS)', () {
    test('T-174-DOCS-06: README 머리에 template 시작 · 매뉴얼 링크 · Issues 안내가 있다', () {
      final String head = _sliceReadmeHead(readme);
      expect(head.trim(), isNotEmpty, reason: 'README 머리를 찾지 못했다');
      expect(
        countOccurrences(head, 'Use this template'),
        1,
        reason: 'README 머리에 Use this template 안내가 없거나 중복이다',
      );
      expect(
        countOccurrences(head, _readmeManualLink),
        1,
        reason: 'README 머리에 매뉴얼 「킷 업데이트 반영」 링크가 없거나 중복이다',
      );
      expect(
        countOccurrences(head, 'Issues'),
        greaterThanOrEqualTo(1),
        reason: 'README 머리에 Issues 안내가 없다',
      );
      final List<String> hits = _collectForbiddenHits(head);
      expect(hits, isEmpty, reason: '금지 패턴이 README 머리에 있다: $hits');
    });
  });
}
