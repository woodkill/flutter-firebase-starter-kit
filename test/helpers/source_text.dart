// 소스 텍스트 감사용 공용 헬퍼 (코드 리뷰 WR-04(R2)).
//
// `test/` 의 여러 계약 test 가 tracked 소스 파일을 **문자열로 읽어** 규칙 위반을
// 센다. 그때 필요한 헬퍼(파일 읽기 · 행 주석 제거 · 등장 횟수 세기)가 3개 test
// 파일에 본문까지 똑같이 복제돼 있었다. DRY 위반일 뿐 아니라 실제 위험은
// divergence 다 — 사본 하나만 「주석 제거 규칙」 이 바뀌면(예: 인라인 `#` 주석까지
// 제거) 같은 이름의 함수가 파일마다 다르게 동작하면서 감사용 카운트가 갈린다.
// 여기 한 번만 정의하고 모든 호출자가 import 한다. 매뉴얼(`docs/manual.md`)
// 계약 test 들의 절 자르기 · 줄 모으기 헬퍼도 같은 이유로 여기 있다(Phase 17.2
// 코드 리뷰 IN-10).
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
  final File file = File(path);
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
    raw.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

/// [needle] 이 [haystack] 에 나타나는 횟수를 센다.
///
/// 겹치는 등장은 세지 않는다 — 한 번 맞을 때마다 [needle] 길이만큼 건너뛴다.
/// [needle] 이 비어 있으면 0 을 돌려준다(무한 루프 방지).
int countOccurrences(String haystack, String needle) {
  if (needle.isEmpty) {
    return 0;
  }
  int count = 0;
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
/// 매뉴얼 계약 test 들이 같은 자르기 규칙을 쓰게 여기 한 번만 둔다 — 사본마다
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

/// 매뉴얼에서 `## 목차` 다음 줄부터 그 뒤 첫 `---` 줄 앞까지를 돌려준다.
///
/// 목차 링크 문자열은 본문에도 다시 나오므로(다른 절의 안내 링크) 목차 블록
/// 안에서만 센다. 블록이 없으면 빈 문자열이다.
String sliceTocBlock(String manual) {
  final List<String> lines = manual.split('\n');
  final int start = lines.indexOf('## 목차');
  if (start == -1) {
    return '';
  }
  final List<String> block = <String>[];
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
  final List<String> table = <String>[];
  for (int i = start; i < lines.length && lines[i].startsWith('|'); i++) {
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
/// 날짜)를 한 정규식으로 적는다. 매뉴얼 · README · 공개 문서(CHANGELOG ·
/// CONTRIBUTING · 이슈 · PR 템플릿) 계약 테스트가 모두 이 상수를 import 한다 —
/// 사본을 두면 규칙이 바뀔 때 파일마다 다른 패턴으로 세게 된다. 플랜 verify 의
/// `FP` 와 글자 그대로 같다.
const String kUserDocForbiddenPatternSource =
    r'Phase [0-9]|\bD-[0-9]{2}\b|\bD-[A-Z]+-[0-9]|\b(WR|IN|CR|BL)-[0-9]|\b[0-9]+(\.[0-9]+)?-(CONTEXT|RESEARCH|PATTERNS|PLAN|SUMMARY|LEDGER|VERIFICATION|VALIDATION|REVIEW|UAT)\b|\.planning|\bquick [0-9]{6}|\b[0-9]{6}-[a-z0-9]{3}\b|\b[0-9a-f]{7,40}\b|\bUAT|실측|재현됐|\bmemory\b|\b(project|feedback|reference)_[a-z0-9_]+|\bgsd[-:]|20[0-9]{2}-[0-9]{2}-[0-9]{2}';
