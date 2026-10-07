// 공개 mirror 규칙 파일(.planning/release/)의 내용과 동결 해시를 고정한다 (Phase 17.4
// D-12 — see ROADMAP.md).
//
// 규칙 파일 3종이 진실원이고 scripts/publish_kit.sh 가 그대로 git filter-repo 에
// 넘긴다. rc.1 발행 뒤에는 규칙 · mirror 레시피를 바꾸지 않는다 — 한 글자만 바꿔도
// 공개 이력 전체의 해시가 달라진다. 이 테스트가 줄 내용 · 값 0 · 정규식 동작 ·
// rules.sha256 을 고정한다. 공개 mirror 에는 .planning/ 이 없으므로 전부 건너뛴다
// (D-08 skip 형).
//
// **값 모양 리터럴을 두지 않는다** — 양성 대조 문자열은 조각으로 조립한다. 이 파일도
// 공개 이력에 들어가 같은 규칙 · 스캔을 거치므로, 리터럴이 있으면 치환되거나 부재
// 단언에 걸린다.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/planning_docs.dart';
import '../helpers/source_text.dart';

const String _rulesDir = '.planning/release';
const String _excludePath = '$_rulesDir/mirror-exclude-paths.txt';
const String _replaceTextPath = '$_rulesDir/mirror-replace-text.txt';
const String _replaceMessagePath = '$_rulesDir/mirror-replace-message.txt';
const String _hashPath = '$_rulesDir/rules.sha256';
const String _scriptPath = 'scripts/publish_kit.sh';
const String _recipeBegin = '# MIRROR-RECIPE-BEGIN';
const String _recipeEnd = '# MIRROR-RECIPE-END';

const List<String> _expectedExcludes = <String>[
  '.planning',
  'CLAUDE.md',
  '.claude/rules/docs-user-manual.md',
  '.claude/skills/sketch-findings-flutter-starter-kit',
  '.claude/settings.json',
];

// 치환값의 10자리 0 은 인접 문자열로 끊어 둔다 — 한 줄에 「팀 키 = 10자;」 모양이
// 생기지 않게 한다.
const List<String> _expectedReplaceText = <String>[
  r'regex:AIza[0-9A-Za-z_-]{35}==>PLACEHOLDER',
  r'regex:DEVELOPMENT_TEAM = [A-Z0-9]{10};==>DEVELOPMENT_TEAM = '
      '0000000000;',
  r'regex:(`Channel ID` — 숫자 \(예: `)[0-9]{10}(`\))==>\g<1>0000000000\g<2>',
];

const List<String> _expectedReplaceMessage = <String>[
  r'regex:(?m)^Claude-Session: .*\n?==>',
  r'regex:[A-Za-z0-9._%+-]+@(naver|gmail)\.com==>redacted@example.com',
  r'regex:(client_id |Channel )[0-9]{10}==>\g<1>[redacted]',
];

/// 파일 [path] 를 줄 목록으로 읽는다 — 끝 개행 1개 · CR 없음을 함께 단언한다.
List<String> _readLines(String path) {
  final String text = readTrackedFile(path);
  expect(text.endsWith('\n'), isTrue, reason: '$path 는 개행 1개로 끝나야 한다');
  expect(text.contains('\r'), isFalse, reason: '$path 에 CR 이 있다');
  return text.substring(0, text.length - 1).split('\n');
}

/// `regex:<패턴>==><치환>` 줄에서 패턴부만 Dart [RegExp] 로 컴파일한다.
///
/// 치환부는 Python `re` 문법(`\g<1>`)이라 컴파일하지 않는다. 패턴이 `(?m)` 로
/// 시작하면 떼고 multiLine 으로 만든다.
RegExp _compilePattern(String line) {
  expect(line.startsWith('regex:'), isTrue, reason: '$line 은 regex: 줄이 아니다');
  final int arrow = line.lastIndexOf('==>');
  expect(arrow, greaterThan(0), reason: '$line 에 ==> 가 없다');
  final String pattern = line.substring('regex:'.length, arrow);
  if (pattern.startsWith('(?m)')) {
    return RegExp(pattern.substring('(?m)'.length), multiLine: true);
  }
  return RegExp(pattern);
}

/// 규칙 줄 목록에 주석 · 빈 줄이 없는지 단언한다.
///
/// `--replace-text` · `--replace-message` 파일은 `#` 줄을 주석이 아니라 치환할
/// 리터럴로 읽는다(filter-repo 설치본 `get_replace_text` 실측).
void _expectNoCommentOrBlank(List<String> lines, String path) {
  expect(
    lines.where((String line) => line.startsWith('#')),
    isEmpty,
    reason: '$path 에 # 줄이 있다 — filter-repo 는 이 줄을 치환 리터럴로 읽는다',
  );
  expect(
    lines.where((String line) => line.trim().isEmpty),
    isEmpty,
    reason: '$path 에 빈 줄이 있다',
  );
}

/// 파일 바이트의 sha256 16진 문자열을 돌려준다.
String _sha256OfFile(String path) =>
    sha256.convert(File(path).readAsBytesSync()).toString();

void main() {
  group('mirror 규칙 (D-12)', () {
    test(
      'T-174-RULES-01: 제외 경로 5줄 == .planning · CLAUDE.md · 비공개 .claude 3',
      () {
        final List<String> paths = _readLines(_excludePath)
            .where((String line) => line.isNotEmpty && !line.startsWith('#'))
            .toList();
        expect(
          paths,
          _expectedExcludes,
          reason:
              '$_excludePath 의 경로(순서 포함)가 D-01 · D-03 결정과 다르다. '
              'rc.1 뒤에는 바꾸지 않는다',
        );
      },
      skip: skipUnlessPlanningDocsExist(<String>[_excludePath]),
    );

    test('T-174-RULES-02: blob 치환 3줄 · 주석 0 · 값 0 · 정규식 양성 대조', () {
      final List<String> lines = _readLines(_replaceTextPath);
      expect(lines, _expectedReplaceText);
      _expectNoCommentOrBlank(lines, _replaceTextPath);

      final String text = readTrackedFile(_replaceTextPath);
      // 값 0 — 키 모양 토큰이 없고, 10자리 숫자는 전부 자리표시 0 이다.
      expect(RegExp(r'AIza[0-9A-Za-z_-]{35}').hasMatch(text), isFalse);
      final Iterable<String> digitRuns = RegExp(
        r'(?<![0-9])[0-9]{10}(?![0-9])',
      ).allMatches(text).map((RegExpMatch match) => match.group(0)!);
      expect(digitRuns, isNotEmpty);
      expect(
        digitRuns.where((String run) => run != '0' * 10),
        isEmpty,
        reason: '$_replaceTextPath 에 0 이 아닌 10자리 숫자가 있다 — 값은 넣지 않는다',
      );

      final RegExp keyPattern = _compilePattern(lines[0]);
      final RegExp teamPattern = _compilePattern(lines[1]);
      final RegExp channelPattern = _compilePattern(lines[2]);
      final String keyPrefix = <String>['AI', 'za'].join();
      expect(keyPattern.hasMatch('$keyPrefix${'x' * 35}'), isTrue);
      expect(keyPattern.hasMatch('$keyPrefix${'x' * 34} '), isFalse);
      final String teamKey = <String>['DEVELOPMENT', '_TEAM = '].join();
      expect(teamPattern.hasMatch('$teamKey${'ABCDE' * 2};'), isTrue);
      expect(
        channelPattern.hasMatch(
          '  - `Channel ID` — 숫자 (예: `${'7' * 10}`) — 공개 키',
        ),
        isTrue,
      );
    }, skip: skipUnlessPlanningDocsExist(<String>[_replaceTextPath]));

    test('T-174-RULES-03: 메시지 치환 3줄 · 메일 로컬부 = 문자 클래스 · 양성 대조', () {
      final List<String> lines = _readLines(_replaceMessagePath);
      expect(lines, _expectedReplaceMessage);
      _expectNoCommentOrBlank(lines, _replaceMessagePath);

      final RegExp sessionPattern = _compilePattern(lines[0]);
      final RegExp mailPattern = _compilePattern(lines[1]);
      final RegExp channelPattern = _compilePattern(lines[2]);

      // 메일 규칙은 실 주소 없이 모양만 — 로컬부가 문자 클래스여야 한다.
      expect(
        mailPattern.pattern.split('@').first,
        '[A-Za-z0-9._%+-]+',
        reason: '메일 규칙의 로컬부에 실 주소 리터럴을 넣지 않는다',
      );

      expect(
        sessionPattern.hasMatch(
          'title\n\nClaude-Session: https://example.invalid/s\n',
        ),
        isTrue,
      );
      final String mailDomain = <String>['gm', 'ail'].join();
      expect(mailPattern.hasMatch('someone@$mailDomain.com'), isTrue);
      expect(mailPattern.hasMatch('someone@example.com'), isFalse);
      expect(channelPattern.hasMatch('(client_id ${'7' * 10} + PKCE'), isTrue);
    }, skip: skipUnlessPlanningDocsExist(<String>[_replaceMessagePath]));

    test(
      'T-174-RULES-04: rules.sha256 4줄 == 규칙 3파일 + mirror 레시피 블록 sha256',
      () {
        final List<String> scriptLines = readTrackedFile(
          _scriptPath,
        ).split('\n');
        expect(
          scriptLines.where((String line) => line == _recipeBegin).length,
          1,
          reason: '$_scriptPath 에 "$_recipeBegin" 줄이 정확히 1줄 있어야 한다',
        );
        expect(
          scriptLines.where((String line) => line == _recipeEnd).length,
          1,
          reason: '$_scriptPath 에 "$_recipeEnd" 줄이 정확히 1줄 있어야 한다',
        );
        final int begin = scriptLines.indexOf(_recipeBegin);
        final int end = scriptLines.indexOf(_recipeEnd);
        expect(end, greaterThan(begin));
        final String recipe =
            '${scriptLines.sublist(begin, end + 1).join('\n')}\n';
        final String recipeHash = sha256
            .convert(utf8.encode(recipe))
            .toString();

        final String expected = <String>[
          '${_sha256OfFile(_excludePath)}  $_excludePath',
          '${_sha256OfFile(_replaceTextPath)}  $_replaceTextPath',
          '${_sha256OfFile(_replaceMessagePath)}  $_replaceMessagePath',
          '$recipeHash  $_scriptPath#MIRROR-RECIPE',
        ].map((String line) => '$line\n').join();
        expect(
          readTrackedFile(_hashPath),
          expected,
          reason:
              '$_hashPath 가 규칙 3파일 · mirror 레시피의 현재 해시와 다르다. '
              'rc.1 뒤에는 규칙을 바꾸지 않는다 — rc.1 전 의도한 변경이면 '
              'bash scripts/publish_kit.sh rules-hash > $_hashPath 로 다시 만든다',
        );
      },
      skip: skipUnlessPlanningDocsExist(<String>[
        _excludePath,
        _replaceTextPath,
        _replaceMessagePath,
        _hashPath,
      ]),
    );
  });
}
