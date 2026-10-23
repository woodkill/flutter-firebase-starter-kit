// 소스 텍스트 감사용 공용 헬퍼 — 사본을 두지 않는다.
//
// `test/` 의 여러 계약 test 가 tracked 소스 파일을 **문자열로 읽어** 규칙 위반을
// 센다. 그때 필요한 헬퍼(파일 읽기 · 행 주석 제거 · 등장 횟수 세기)와 사용자
// 문서(`docs/setup.md` · `docs/guide.md` · README) 계약 test 들의 절 자르기 · 줄
// 모으기 헬퍼를 여기 한 번만 정의하고 모든 호출자가 import 한다. 사본이 생기면
// 하나만 「주석 제거 규칙」 이 바뀌어(예: 인라인 `#` 주석까지 제거) 같은 이름의
// 함수가 파일마다 다르게 동작하면서 감사용 카운트가 갈린다.
//
// **주석을 걷어낸 뒤 세는 이유:** 설명 주석이 감사용 카운트를 오염시킨다.
// 「금지 문자열 0건」 을 세는 단언은 그 문자열을 언급한 설명 주석 한 줄에도 red 가
// 된다(`AndroidManifest.xml` 이 같은 규칙을 명문화하고 있다).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 저장소 루트 기준 상대 경로 [path] 의 파일 내용을 돌려준다.
///
/// 파일이 없으면 경로를 알리며 테스트를 실패시킨다
/// (`flutter test` 의 CWD = 프로젝트 루트).
///
/// **부재 단언에는 쓰지 않는다** — 파일이 없을 때 `fail()` 하므로 「이 파일이
/// 없어야 한다」 는 검사를 할 수 없다. 그 경우는 `File(path).existsSync()` 를 직접
/// 쓰고, 같은 API 가 실제로 매칭한다는 양성 대조를 함께 세운다.
String readTrackedFile(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    fail('tracked 파일 부재: $path');
  }
  return file.readAsStringSync();
}

/// `//` 로 시작하는 행 주석을 제거한다 (Dart · Kotlin · xcconfig 공용).
String stripSlashComments(String raw) => raw
    .split('\n')
    .where((String line) => !line.trimLeft().startsWith('//'))
    .join('\n');

/// `/* ... */` 블록 주석을 제거한다 (Dart `/** */` KDoc · Kotlin · Java 공용).
///
/// [stripSlashComments] 는 행 주석만 걷어내므로 KDoc 블록이 그대로 남는다. 「이
/// 토큰이 코드에 **있어야 한다**」 를 단언하는 소스 계약에서는 그 블록이 토큰을
/// 언급하는 것만으로 단언이 공허하게 참이 되므로 둘을 함께 쓴다.
String stripBlockComments(String raw) =>
    raw.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');

/// `#` 로 시작하는 행 주석을 제거한다 (YAML).
String stripHashComments(String raw) => raw
    .split('\n')
    .where((String line) => !line.trimLeft().startsWith('#'))
    .join('\n');

/// `<!-- ... -->` 블록 주석을 제거한다 (XML · plist).
String stripXmlComments(String raw) =>
    raw.replaceAll(RegExp('<!--.*?-->', dotAll: true), '');

/// [needle] 이 [haystack] 에 나타나는 횟수를 센다.
///
/// 겹치는 등장은 세지 않는다 — 한 번 맞을 때마다 [needle] 길이만큼 건너뛴다.
/// [needle] 이 비어 있으면 0 을 돌려준다(무한 루프 방지).
int countOccurrences(String haystack, String needle) {
  if (needle.isEmpty) {
    return 0;
  }
  var count = 0;
  int index = haystack.indexOf(needle);
  while (index != -1) {
    count++;
    index = haystack.indexOf(needle, index + needle.length);
  }
  return count;
}

/// 마크다운 [text] 에서 [heading] 줄부터 다음 헤딩 직전까지를 돌려준다.
///
/// 경계로 치는 헤딩은 `## ` 부터 [maxLevel] 개의 `#` 까지다 — 2 면 `## ` 만,
/// 3 이면 `## ` · `### ` 이다. [heading] 은 정확히 한 줄이어야 하며, 없으면 빈
/// 문자열을 돌려준다(호출자가 「비어 있지 않음 · 헤딩 1회」 양성 대조를 세운다).
///
/// 문서 계약 test 들이 같은 자르기 규칙을 쓰게 여기 한 번만 둔다 — 사본마다
/// 경계 규칙이 갈리면 같은 헤딩의 슬라이스가 파일마다 다른 범위가 된다.
String sliceMarkdownSection(
  String text,
  String heading, {
  required int maxLevel,
}) {
  if (maxLevel < 2) {
    throw ArgumentError.value(maxLevel, 'maxLevel', '2 이상이어야 한다');
  }
  final int start = text.indexOf('$heading\n');
  if (start == -1) {
    return '';
  }
  final int next = text.indexOf(
    RegExp('\\n#{2,$maxLevel} '),
    start + heading.length,
  );
  return next == -1 ? text.substring(start) : text.substring(start, next);
}

/// [text] 에서 [prefix] 로 시작하는 줄만 모은다.
List<String> linesStartingWith(String text, String prefix) =>
    text.split('\n').where((String line) => line.startsWith(prefix)).toList();

/// 마크다운 [markdown] 에서 `## 목차` 다음 줄부터 그 뒤 첫 `---` 줄 앞까지를
/// 돌려준다.
///
/// 목차 링크 문자열은 본문에도 다시 나오므로(다른 절의 안내 링크) 목차 블록
/// 안에서만 센다. 블록이 없으면 빈 문자열이다.
String sliceTocBlock(String markdown) {
  final List<String> lines = markdown.split('\n');
  final int start = lines.indexOf('## 목차');
  if (start == -1) {
    return '';
  }
  final block = <String>[];
  for (int i = start + 1; i < lines.length; i++) {
    if (lines[i] == '---') {
      break;
    }
    block.add(lines[i]);
  }
  return block.join('\n');
}

/// [text] 에서 [header] 줄부터 `|` 로 시작하는 줄이 이어지는 동안(표 블록)을
/// 줄 목록으로 돌려준다. [header] 가 없으면 빈 목록이다.
List<String> collectTableLines(String text, String header) {
  final List<String> lines = text.split('\n');
  final int start = lines.indexOf(header);
  if (start == -1) {
    return <String>[];
  }
  final table = <String>[];
  for (var i = start; i < lines.length && lines[i].startsWith('|'); i++) {
    table.add(lines[i]);
  }
  return table;
}

/// [text] 의 줄 가운데 [line] 과 정확히 같은 줄의 수를 센다.
int countExactLines(String text, String line) =>
    text.split('\n').where((String l) => l == line).length;

/// 사용자 문서 금지 패턴 정규식 원문이다.
///
/// `.claude/rules/docs-user-manual.md` §4 표 전체(planning 경로 · phase 번호 ·
/// 결정 · 리뷰 ID · quick · 세션 식별자 · 커밋 해시 · 판정 서술 · 내부 도구 이름 ·
/// 날짜)를 한 정규식으로 적는다. 두 가이드 · README · 공개 문서(CHANGELOG ·
/// CONTRIBUTING · 이슈 · PR 템플릿) 계약 테스트가 모두 이 상수를 import 한다 —
/// 사본을 두면 규칙이 바뀔 때 파일마다 다른 패턴으로 세게 된다. 플랜 verify 의
/// `FP` 와 글자 그대로 같다.
const String kUserDocForbiddenPatternSource =
    r'Phase [0-9]|\bD-[0-9]{2}\b|\bD-[A-Z]+-[0-9]|\b(WR|IN|CR|BL)-[0-9]|\b[0-9]+(\.[0-9]+)?-(CONTEXT|RESEARCH|PATTERNS|PLAN|SUMMARY|LEDGER|VERIFICATION|VALIDATION|REVIEW|UAT)\b|\.planning|\bquick [0-9]{6}|\b[0-9]{6}-[a-z0-9]{3}\b|\b[0-9a-f]{7,40}\b|\bUAT|실측|재현됐|\bmemory\b|\b(project|feedback|reference)_[a-z0-9_]+|\bgsd[-:]|20[0-9]{2}-[0-9]{2}-[0-9]{2}';

/// 이름을 붙인 정규식 하나 — 위반 줄을 알릴 때 패턴 이름을 함께 낸다.
typedef NamedPattern = ({String name, RegExp pattern});

/// 날짜 패턴의 이름 — CHANGELOG 판 머리 줄에서만 이 패턴을 건너뛴다.
const String _datePatternName = 'date';

/// 사용자 문서 금지 패턴을 이름과 함께 줄 단위로 적은 목록이다.
///
/// `.claude/rules/docs-user-manual.md` §4 표의 식별자 꼴(planning 경로 · phase 번호 ·
/// 결정 · 리뷰 ID · quick · 세션 식별자 · 커밋 해시 · 판정 서술 · 내부 도구 이름 ·
/// 날짜)에 작업 일지 참조 문구 · 제목 줄의 이력 어휘 · 콘솔 라벨 자리 표시를 더한다.
/// 단일 정규식 원문과
/// 달리 두 갈래를 좁혔다 — 커밋 해시는 숫자와 a-f 를 둘 다 담은 7~40자만 잡고(채움
/// 값 `00000000` · SVG 좌표 숫자를 놓친다), memory 이름은 접두 뒤 밑줄로 이은 조각이
/// 둘 이상인 꼴만 잡는다(설정 키 `project_id` 를 놓친다). 사용자 문서 시험
/// (`test/docs/`)이 [findForbiddenPatternHits] 로 이 목록을 쓴다.
final List<NamedPattern> kUserDocForbiddenPatterns = <NamedPattern>[
  (name: 'phase-number', pattern: RegExp('Phase [0-9]')),
  (name: 'decision-id', pattern: RegExp(r'\bD-[0-9]{2}\b')),
  (name: 'area-decision-id', pattern: RegExp(r'\bD-[A-Z]+-[0-9]')),
  (name: 'review-id', pattern: RegExp(r'\b(WR|IN|CR|BL)-[0-9]')),
  (
    name: 'planning-doc-name',
    pattern: RegExp(
      r'\b[0-9]+(\.[0-9]+)?-(CONTEXT|RESEARCH|PATTERNS|PLAN|SUMMARY|LEDGER|VERIFICATION|VALIDATION|REVIEW|UAT)\b',
    ),
  ),
  (name: 'planning-path', pattern: RegExp(r'\.planning')),
  (name: 'quick-id', pattern: RegExp(r'\bquick [0-9]{6}')),
  (name: 'session-id', pattern: RegExp(r'\b[0-9]{6}-[a-z0-9]{3}\b')),
  (
    name: 'commit-hash',
    pattern: RegExp(r'\b(?=[0-9a-f]*[a-f])(?=[0-9a-f]*[0-9])[0-9a-f]{7,40}\b'),
  ),
  (name: 'uat-word', pattern: RegExp(r'\bUAT')),
  (name: 'measured-word', pattern: RegExp('실측')),
  (name: 'reproduced-word', pattern: RegExp('재현됐')),
  (name: 'memory-word', pattern: RegExp(r'\bmemory\b')),
  (
    name: 'memory-name',
    pattern: RegExp(r'\b(project|feedback|reference)_[a-z0-9]+_[a-z0-9_]+'),
  ),
  (name: 'gsd-command', pattern: RegExp(r'\bgsd[-:]')),
  (name: _datePatternName, pattern: RegExp('20[0-9]{2}-[0-9]{2}-[0-9]{2}')),
  (name: 'roadmap-reference', pattern: RegExp(r'see ROADMAP\.md')),
  (
    name: 'history-heading',
    pattern: RegExp(
      '^#{1,6} .*(DEPRECATED|retroactive|hotfix)',
      caseSensitive: false,
    ),
  ),
  (name: 'label-slot', pattern: RegExp(r'\[\[LABEL:')),
];

/// CHANGELOG 의 판 머리 줄(`## [<판>] - <연>-<월>-<일>`)이다 — 이 줄의 날짜만 금지
/// 패턴에서 뺀다.
final RegExp kChangelogReleaseHeading = RegExp(
  r'^## \[[0-9][^\]]*\] - 20[0-9]{2}-[0-9]{2}-[0-9]{2}$',
);

/// 두 사용자 가이드에서만 잡는 시험 ID 꼴이다.
///
/// [kUserDocForbiddenPatterns] 밖에 따로 둔다 — CHANGELOG 의 발행 절 · 설정 안내 ·
/// 자산 README 는 시험 ID 를 쓸 수 있고, 두 가이드([kGuideTestIdPaths])만 이 꼴을
/// 막는다.
final NamedPattern kGuideTestIdPattern = (
  name: 'test-id',
  pattern: RegExp(r'\bT-[0-9][0-9.]*-[A-Z][A-Z0-9]*-[0-9]'),
);

/// 시험 ID 꼴([kGuideTestIdPattern])을 검사하는 사용자 가이드 경로다.
const Set<String> kGuideTestIdPaths = <String>{
  'docs/setup.md',
  'docs/guide.md',
};

/// 시험 ID 꼴을 허용하는 한 소절이 있는 가이드 경로다.
const String _demoRemovalGuidePath = 'docs/guide.md';

/// 사용 가이드 「홈 화면 바꾸기」 의 데모 지우는 법 소절을 여는 줄이다.
///
/// 데모를 지운 뒤 함께 지우거나 고칠 시험을 시험 파일과 시험 ID 로 적는 곳이라, 이
/// 줄부터 그 뒤 첫 제목 줄 앞까지는 시험 ID 꼴만 허용한다(다른 금지 패턴은 그대로
/// 잡는다).
const String kDemoRemovalStartLine = '- **지우는 법(데모를 앱에서 빼기):**';

/// 마크다운 제목 줄(`#` 1개 이상 뒤 공백)이다.
final RegExp _markdownHeadingLine = RegExp('^#+ ');

/// 사용자 문서 [text] 에서 금지 패턴 위반을 줄마다 찾아 `'<path>:<줄> — <이름>'`
/// 목록으로 돌려준다.
///
/// [path] 는 저장소 루트 기준 경로이고 예외 규칙을 고르는 데 쓴다. `CHANGELOG.md` 의
/// 판 머리 줄([kChangelogReleaseHeading])은 날짜 패턴만 건너뛴다. [path] 가
/// [kGuideTestIdPaths] 에 들면 [kGuideTestIdPattern] 도 보되, 사용 가이드에서
/// [kDemoRemovalStartLine] 줄부터 그 뒤 첫 제목 줄 앞까지는 시험 ID 꼴만 건너뛴다
/// (코드 펜스 안의 `#` 줄은 제목으로 치지 않는다). 위반 줄의 내용은 내지 않는다.
List<String> findForbiddenPatternHits(String path, String text) {
  final isChangelog = path == 'CHANGELOG.md';
  final bool checksTestIds = kGuideTestIdPaths.contains(path);
  final hasDemoRemoval = path == _demoRemovalGuidePath;
  final hits = <String>[];
  final List<String> lines = text.split('\n');
  var inFence = false;
  var inDemoRemoval = false;
  for (var i = 0; i < lines.length; i++) {
    final String line = lines[i];
    if (line.trimLeft().startsWith('```')) {
      inFence = !inFence;
    }
    if (hasDemoRemoval) {
      if (line.trimRight() == kDemoRemovalStartLine) {
        inDemoRemoval = true;
      } else if (!inFence && _markdownHeadingLine.hasMatch(line)) {
        inDemoRemoval = false;
      }
    }
    final bool isReleaseHeading =
        isChangelog && kChangelogReleaseHeading.hasMatch(line);
    for (final NamedPattern named in kUserDocForbiddenPatterns) {
      if (isReleaseHeading && named.name == _datePatternName) {
        continue;
      }
      if (named.pattern.hasMatch(line)) {
        hits.add('$path:${i + 1} — ${named.name}');
      }
    }
    if (checksTestIds &&
        !inDemoRemoval &&
        kGuideTestIdPattern.pattern.hasMatch(line)) {
      hits.add('$path:${i + 1} — ${kGuideTestIdPattern.name}');
    }
  }
  return hits;
}
