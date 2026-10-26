// 사용 가이드 「내 기능 추가하기」 튜토리얼이 기대는 킷 이름 · import · 명령 계약.
//
// 저장소에는 튜토리얼의 완성 코드가 없다 — 가이드의 글과 코드 블록만 있다. 그래서
// 킷이 튜토리얼에 쓴 이름 · 파일을 바꾸면 이 파일이 먼저 실패해 글을 고치게 한다.
//
// T-21-TUT-01: 튜토리얼 `###` 소절 12개가 정한 순서로 한 번씩 있고, TUT-02 의 킷
//   이름마다 튜토리얼에 1회 이상 나온다.
// T-21-TUT-02: 튜토리얼이 쓰는 킷 이름의 선언이 그 파일에서 주석을 걷은 뒤에도
//   있다. 양성 대조 — 선언 검색은 주석 속 이름만 있는 표본에서 찾지 못한다.
// T-21-TUT-03: 코드 블록의 `package:flutter_starter_kit/` import 가 3개 이상이고,
//   튜토리얼이 만드는 `features/memos/` 밖 경로는 `lib/` 아래에 실제 파일이다.
// T-21-TUT-04: 코드 생성 · 분석 · 시험 명령이 튜토리얼에 단독 줄로 있다.
// T-21-TUT-05: 코딩 규칙은 링크로 가리키고, 그 파일은 tracked 이며 공개 제외 목록
//   밖이다.
//
// 어디서 도는가: TUT-02 는 `lib/` · `firestore.rules` 만 읽으므로 어디서나 돈다 —
// 튜토리얼을 따라 `features/memos/` 를 만든 사용자 저장소에서도 참이다. 가이드
// 본문을 읽는 TUT-01 · 03 · 04 · 05 는 킷 사용자가 자기 가이드를 고치면 깨지는 내용
// 검사라, 비공개 작업 일지(`.planning/`)가 있는 유지보수자 트리에서만 돈다. TUT-05 는
// 공개 제외 목록 파일도 있어야 돈다.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/planning_docs.dart';
import '../helpers/source_text.dart';

/// 튜토리얼이 있는 사용 가이드 경로.
const String _guidePath = 'docs/guide.md';

/// 튜토리얼 절 제목 줄.
const String _tutorialHeading = '## 내 기능 추가하기';

/// 튜토리얼 소절 제목 — 이 순서로 한 번씩.
const List<String> _expectedSubsections = <String>[
  '### ① 기능 폴더 만들기',
  '### ② Freezed 모델',
  '### ③ withConverter 저장소',
  '### ④ Riverpod provider',
  '### ⑤ 목록 화면 · 추가 시트',
  '### ⑥ 홈 하위 라우트와 진입 버튼',
  '### ⑦ ARB 세 언어',
  '### ⑧ Firestore rules 와 rules 시험',
  '### ⑨ unit · widget 시험',
  '### ⑩ 코드 생성 · 분석 · 시험',
  '### 확인 방법',
  '### 되돌리기',
];

/// 튜토리얼이 단독 줄로 적는 명령.
const List<String> _commandLines = <String>[
  'fvm dart run build_runner build --delete-conflicting-outputs',
  'fvm flutter gen-l10n',
  'fvm flutter analyze',
  'fvm dart analyze',
  'fvm flutter test',
  'cd functions && pnpm test:rules',
];

/// 코딩 규칙 파일 경로(저장소 루트 기준).
const String _codingRulesPath = '.claude/rules/flutter.md';

/// 튜토리얼이 코딩 규칙을 가리키는 링크 꼬리.
const String _codingRulesLink = '](../.claude/rules/flutter.md)';

/// 공개 mirror 에서 빼는 경로 목록 파일.
const String _excludePath = '.planning/release/mirror-exclude-paths.txt';

/// 튜토리얼 코드 블록의 킷 import 를 찾는 정규식 — 1번 묶음이 `lib/` 아래 경로다.
final RegExp _kitImportPattern = RegExp(
  r"^import 'package:flutter_starter_kit/([^']+)';$",
  multiLine: true,
);

/// 튜토리얼이 새로 만드는 기능의 `lib/` 아래 경로 머리.
const String _tutorialFeaturePrefix = 'features/memos/';

/// 가이드 본문을 읽는 검사의 skip 값 — 유지보수자 트리에서만 돈다.
final Object _skipMaintainer = skipUnlessMaintainerTree();

/// 공개 제외 목록까지 읽는 검사의 skip 값.
final Object _skipMaintainerWithExcludes = skipUnlessPlanningDocsExist(<String>[
  _excludePath,
]);

/// 튜토리얼이 쓰는 킷 이름 하나 — 선언 파일 · 선언 꼴 · 선언 꼴에 맞는 표본 줄.
typedef _KitDeclaration = ({
  String name,
  String path,
  RegExp pattern,
  String sample,
});

/// 튜토리얼이 기대는 킷 선언.
final List<_KitDeclaration> _kitDeclarations = <_KitDeclaration>[
  (
    name: 'Result',
    path: 'lib/core/error/result.dart',
    pattern: RegExp(r'^sealed class Result<T> \{', multiLine: true),
    sample: 'sealed class Result<T> {',
  ),
  (
    name: 'guardResult',
    path: 'lib/core/error/guard_result.dart',
    pattern: RegExp(r'^Future<Result<T>> guardResult<T>\(', multiLine: true),
    sample: 'Future<Result<T>> guardResult<T>(',
  ),
  (
    name: 'TimestampConverter',
    path: 'lib/core/firestore/timestamp_converter.dart',
    pattern: RegExp(r'^class TimestampConverter\b', multiLine: true),
    sample: 'class TimestampConverter implements JsonConverter {',
  ),
  (
    name: 'AuthRequired',
    path: 'lib/features/auth/presentation/_widgets/auth_required.dart',
    pattern: RegExp(r'^class AuthRequired\b', multiLine: true),
    sample: 'class AuthRequired extends ConsumerWidget {',
  ),
  (
    name: 'showLoginPromptSheet',
    path: 'lib/features/auth/presentation/_widgets/login_prompt_sheet.dart',
    pattern: RegExp(r'^Future<void> showLoginPromptSheet\(', multiLine: true),
    sample: 'Future<void> showLoginPromptSheet(BuildContext context) {',
  ),
  (
    name: 'LoginPromptSheet',
    path: 'lib/features/auth/presentation/_widgets/login_prompt_sheet.dart',
    pattern: RegExp(r'^class LoginPromptSheet\b', multiLine: true),
    sample: 'class LoginPromptSheet extends ConsumerStatefulWidget {',
  ),
  (
    name: 'authState',
    path: 'lib/core/providers/firebase_providers.dart',
    pattern: RegExp(r'^Stream<User\?> authState\(', multiLine: true),
    sample: 'Stream<User?> authState(Ref ref) {',
  ),
  (
    name: 'AppRoutes',
    path: 'lib/core/router/app_routes.dart',
    pattern: RegExp(r'^abstract final class AppRoutes\b', multiLine: true),
    sample: 'abstract final class AppRoutes {',
  ),
  (
    name: 'isOwner',
    path: 'firestore.rules',
    pattern: RegExp(r'^\s*function isOwner\(', multiLine: true),
    sample: '    function isOwner(uid) {',
  ),
  (
    name: 'isRegular',
    path: 'firestore.rules',
    pattern: RegExp(r'^\s*function isRegular\(', multiLine: true),
    sample: '    function isRegular() {',
  ),
];

/// [raw] 에서 `//` · `/* */` 주석을 걷은 뒤 [pattern] 선언이 있는지 돌려준다.
bool _declares(String raw, RegExp pattern) =>
    pattern.hasMatch(stripBlockComments(stripSlashComments(raw)));

/// 가이드에서 튜토리얼 절을 잘라 돌려준다 — 없으면 빈 문자열이다.
String _readTutorial() => sliceMarkdownSection(
  readTrackedFile(_guidePath),
  _tutorialHeading,
  maxLevel: 2,
);

/// 마크다운 [text] 에서 0열 펜스(```` ``` ````) 안의 줄만 모아 돌려준다.
String _collectCodeBlocks(String text) {
  final code = <String>[];
  var inFence = false;
  for (final String line in text.split('\n')) {
    if (line.startsWith('```')) {
      inFence = !inFence;
      continue;
    }
    if (inFence) {
      code.add(line);
    }
  }
  return code.join('\n');
}

/// 공개 제외 목록에서 주석 · 빈 줄을 뺀 경로를 읽는다.
List<String> _readExcludedPaths() => readTrackedFile(_excludePath)
    .split('\n')
    .map((String line) => line.trim())
    .where((String line) => line.isNotEmpty && !line.startsWith('#'))
    .toList();

void main() {
  group('내 기능 추가하기 튜토리얼', () {
    test('T-21-TUT-01: 소절이 정한 순서로 한 번씩', () {
      final String tutorial = _readTutorial();
      expect(tutorial, isNotEmpty, reason: '튜토리얼 절이 없다');

      final List<String> headings = linesStartingWith(tutorial, '### ');
      final missingNames = <String>[
        for (final _KitDeclaration declaration in _kitDeclarations)
          if (!tutorial.contains(declaration.name)) declaration.name,
      ];
      final int violations =
          (listEquals(headings, _expectedSubsections) ? 0 : 1) +
          missingNames.length;
      // 결과 한 줄 — 여러 파일을 함께 돌려도 시험 로그에 이 시험 이름이 남는다.
      debugPrintSynchronously('소절 · 킷 이름 $_guidePath: 위반 $violations건');
      expect(
        headings,
        _expectedSubsections,
        reason: '튜토리얼 소절이 정한 12개 · 순서와 다르다',
      );
      expect(missingNames, isEmpty, reason: '튜토리얼에 나오지 않는 킷 이름이 있다');
    }, skip: _skipMaintainer);

    test('T-21-TUT-02: 튜토리얼이 쓰는 킷 이름의 선언이 주석 밖에 있다', () {
      // 양성 대조: 선언 꼴 표본은 찾고, 같은 표본을 주석에 넣으면 못 찾는다.
      for (final _KitDeclaration declaration in _kitDeclarations) {
        expect(_declares(declaration.sample, declaration.pattern), isTrue);
        expect(
          _declares('// ${declaration.sample}', declaration.pattern),
          isFalse,
        );
        expect(
          _declares('/* ${declaration.sample} */', declaration.pattern),
          isFalse,
        );
      }

      final missing = <String>[
        for (final _KitDeclaration declaration in _kitDeclarations)
          if (!_declares(
            readTrackedFile(declaration.path),
            declaration.pattern,
          ))
            '${declaration.name} (${declaration.path})',
      ];
      debugPrintSynchronously('킷 선언 튜토리얼 이름: 위반 ${missing.length}건');
      expect(missing, isEmpty, reason: '튜토리얼이 기대는 킷 선언이 없다');
    });

    test('T-21-TUT-03: 코드 블록의 킷 import 가 실제 lib 파일이다', () {
      // 양성 대조: 펜스 안의 import 만 모은다.
      const sample =
          "import 'package:flutter_starter_kit/a.dart';\n"
          '```dart\n'
          "import 'package:flutter_starter_kit/b.dart';\n"
          '```';
      expect(
        _kitImportPattern
            .allMatches(_collectCodeBlocks(sample))
            .map((RegExpMatch match) => match.group(1))
            .toList(),
        <String>['b.dart'],
      );

      final List<String> imported = _kitImportPattern
          .allMatches(_collectCodeBlocks(_readTutorial()))
          .map((RegExpMatch match) => match.group(1)!)
          .toList();
      final missing = <String>[
        for (final String path in imported)
          if (!path.startsWith(_tutorialFeaturePrefix) &&
              !File('lib/$path').existsSync())
            'lib/$path',
      ];
      debugPrintSynchronously('킷 import $_guidePath: 위반 ${missing.length}건');
      expect(imported.length, greaterThanOrEqualTo(3));
      expect(missing, isEmpty, reason: '코드 블록이 없는 킷 파일을 import 한다');
    }, skip: _skipMaintainer);

    test('T-21-TUT-04: 코드 생성 · 분석 · 시험 명령 줄이 있다', () {
      final String tutorial = _readTutorial();
      expect(tutorial, isNotEmpty, reason: '튜토리얼 절이 없다');

      final missing = <String>[
        for (final String line in _commandLines)
          if (countExactLines(tutorial, line) < 1) line,
      ];
      debugPrintSynchronously('명령 줄 $_guidePath: 위반 ${missing.length}건');
      expect(missing, isEmpty, reason: '튜토리얼에 단독 줄로 없는 명령이 있다');
    }, skip: _skipMaintainer);

    test('T-21-TUT-05: 코딩 규칙은 링크로 가리킨다', () {
      final String tutorial = _readTutorial();
      final List<String> excluded = _readExcludedPaths();
      // 양성 대조: 제외 목록이 비공개 작업 일지를 담는다.
      expect(excluded, contains('.planning'));

      final ProcessResult tracked = Process.runSync('git', <String>[
        'ls-files',
        '--',
        _codingRulesPath,
      ]);
      expect(tracked.exitCode, 0, reason: '${tracked.stderr}');
      final bool isExcluded = excluded.any(
        (String entry) =>
            _codingRulesPath == entry || _codingRulesPath.startsWith('$entry/'),
      );
      final int violations =
          (tutorial.contains(_codingRulesLink) ? 0 : 1) +
          ('${tracked.stdout}'.trim() == _codingRulesPath ? 0 : 1) +
          (isExcluded ? 1 : 0);
      debugPrintSynchronously('코딩 규칙 링크 $_guidePath: 위반 $violations건');
      expect(tutorial, contains(_codingRulesLink));
      expect('${tracked.stdout}'.trim(), _codingRulesPath);
      expect(isExcluded, isFalse, reason: '코딩 규칙 파일이 공개본에서 빠진다');
    }, skip: _skipMaintainerWithExcludes);
  });
}
