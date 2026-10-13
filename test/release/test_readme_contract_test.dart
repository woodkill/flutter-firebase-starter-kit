// 테스트 안내 문서(`test/README.md`)의 모양을 고정한다.
//
// T-18-README-01: README 에 적은 `test/` 경로가 모두 실재한다 — 인라인 백틱과
//   코드 블록(명령 예시) 모두. 예제 파일 · 헬퍼 파일 · golden 테스트의 이름이
//   바뀌면 README 도 함께 고쳐야 한다. `<기능>` 처럼 `<…>` placeholder 가 든
//   경로는 독자가 채울 자리라 실재 검사에서 뺀다.
// T-18-README-02: README 에 사용자 문서 금지 패턴이 0 건이다.
// T-18-README-03: README 의 「커밋 전에 돌릴 검사」 명령 4줄이 단독 줄로 있다.
//
// 세 단언 모두 킷을 clone 한 저장소에서도 참이어야 하는 내용이라 건너뛰지 않고
// 어디서나 돈다. 읽는 파일은 README 와 README 가 가리키는 `test/` 경로뿐이다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_text.dart';

/// 테스트 안내 문서 경로.
const String _readmePath = 'test/README.md';

/// README 가 반드시 가리키는 unit 예제 경로.
const String _unitExamplePath =
    'test/examples/login_notifier_example_test.dart';

/// README 「커밋 전에 돌릴 검사」 절의 명령 4줄.
const List<String> _precommitCommands = <String>[
  'fvm dart format --output=none --set-exit-if-changed lib test bin',
  'fvm flutter analyze',
  'fvm dart analyze',
  'fvm flutter test',
];

/// README 코드 블록에만 적힌 iOS golden 재생성 명령의 대상 경로.
const String _iosGoldenTestPath =
    'test/features/auth/presentation/_widgets/branded_social_button_golden_test.dart';

/// `test/` 로 시작하는 경로 토큰을 잡는 정규식.
///
/// 백틱 · 코드 블록 구분 없이 잡고, 공백 · 따옴표 · 괄호 · 백틱에서 끊는다.
/// 앞 글자가 단어 문자 · `/` · `.` · `-` 이면 다른 경로의 일부라 잡지 않는다.
final RegExp _testPathToken = RegExp(
  r"""(?<![\w./-])test/[^\s`'"()\[\]{},;:]*""",
);

/// [path] 가 독자가 채울 `<…>` placeholder 를 담았는지 돌려준다.
bool _isPlaceholderPath(String path) =>
    path.contains('<') || path.contains('>');

/// [text] 에 적힌 `test/` 경로 토큰을 중복 없이 돌려준다(끝의 마침표는 뗀다).
Set<String> _extractTestPaths(String text) => _testPathToken
    .allMatches(text)
    .map((RegExpMatch m) => m.group(0)!.replaceFirst(RegExp(r'\.+$'), ''))
    .toSet();

/// [text] 에서 사용자 문서 금지 패턴에 맞는 문자열을 모두 돌려준다.
List<String> _findForbidden(String text) => RegExp(
  kUserDocForbiddenPatternSource,
).allMatches(text).map((RegExpMatch m) => m.group(0)!).toList();

/// [path] 가 `/` 로 끝나면 디렉터리, 아니면 파일로 보고 실재 여부를 돌려준다.
bool _existsInRepo(String path) =>
    path.endsWith('/') ? Directory(path).existsSync() : File(path).existsSync();

void main() {
  group('test/README.md 계약', () {
    test('T-18-README-01: 적은 test/ 경로가 모두 실재한다(코드 블록 포함 · '
        'placeholder 제외)', () {
      // 양성 대조: 코드 블록 안 경로를 잡고, placeholder 경로를 가려낸다.
      final Set<String> sample = _extractTestPaths(
        '```\ncp test/a/b_test.dart test/c/<기능>/d_test.dart\n```\n'
        '`test/e/` 와 lib/test/f.dart',
      );
      expect(sample, <String>{
        'test/a/b_test.dart',
        'test/c/<기능>/d_test.dart',
        'test/e/',
      });
      expect(sample.where(_isPlaceholderPath), <String>[
        'test/c/<기능>/d_test.dart',
      ]);

      final String readme = readTrackedFile(_readmePath);
      final Set<String> found = _extractTestPaths(readme);

      // 양성 대조: 인라인 백틱 경로와 코드 블록에만 있는 경로를 둘 다 찾고,
      // README 의 복사 예시 placeholder 경로를 걸러 낸다.
      expect(
        found,
        containsAll(<String>[_unitExamplePath, _iosGoldenTestPath]),
      );
      expect(found.where(_isPlaceholderPath), isNotEmpty);

      final List<String> missing = found
          .where((String path) => !_isPlaceholderPath(path))
          .where((String path) => !_existsInRepo(path))
          .toList();
      expect(missing, isEmpty, reason: 'README 가 가리키는 경로가 없다: $missing');
    });

    test('T-18-README-02: 사용자 문서 금지 패턴이 0 건이다', () {
      // 양성 대조: 같은 정규식이 phase 번호와 planning 경로를 잡는다(리터럴은 조각으로).
      expect(_findForbidden('Phase 9'), isNotEmpty);
      expect(_findForbidden(<String>['.plan', 'ning'].join()), isNotEmpty);

      final List<String> hits = _findForbidden(readTrackedFile(_readmePath));
      expect(hits, isEmpty, reason: 'README 에 금지 패턴이 있다: $hits');
    });

    test('T-18-README-03: 커밋 전 검사 명령 4줄이 단독 줄로 있다', () {
      final String readme = readTrackedFile(_readmePath);
      for (final String command in _precommitCommands) {
        expect(
          countExactLines(readme, command),
          greaterThanOrEqualTo(1),
          reason: 'README 에 `$command` 줄이 없다',
        );
      }
    });
  });
}
