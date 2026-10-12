// 테스트 안내 문서(`test/README.md`)의 모양을 고정한다.
//
// T-18-README-01: README 에 백틱으로 적은 `test/` 경로가 모두 실재한다 — 예제
//   파일 · 헬퍼 파일의 이름이 바뀌면 README 도 함께 고쳐야 한다.
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

/// 백틱으로 감싼 `test/` 경로를 잡는 정규식.
final RegExp _backtickTestPath = RegExp(r'`(test/[A-Za-z0-9_./-]+)`');

/// [text] 에서 사용자 문서 금지 패턴에 맞는 문자열을 모두 돌려준다.
List<String> _findForbidden(String text) => RegExp(
  kUserDocForbiddenPatternSource,
).allMatches(text).map((RegExpMatch m) => m.group(0)!).toList();

/// [path] 가 `/` 로 끝나면 디렉터리, 아니면 파일로 보고 실재 여부를 돌려준다.
bool _existsInRepo(String path) =>
    path.endsWith('/') ? Directory(path).existsSync() : File(path).existsSync();

void main() {
  group('test/README.md 계약', () {
    test('T-18-README-01: 백틱으로 적은 test/ 경로가 모두 실재한다', () {
      final String readme = readTrackedFile(_readmePath);
      final List<String> paths = _backtickTestPath
          .allMatches(readme)
          .map((RegExpMatch m) => m.group(1)!)
          .toSet()
          .toList();

      // 양성 대조: 경로 정규식이 unit 예제 경로를 찾는다.
      expect(paths, contains(_unitExamplePath));

      final List<String> missing = paths
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
