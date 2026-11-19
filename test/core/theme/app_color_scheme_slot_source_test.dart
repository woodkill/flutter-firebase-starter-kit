// 색 역할 자리 소스 계약 — 사용자 파일을 바꿔 끼우지 않고는 닿지 않는 갈래와,
// 킷 트리에서는 값이 같아 지워도 티가 나지 않는 주입 자리를 소스 글자로 고정한다.
//
// T-29-SLOT-10: 기본 builder 갈래(`colorSchemeBuilder == null`)의 밝기 assert 메시지가
//   받은 밝기 · 돌려받은 밝기를 모두 담는다.
// T-29-SLOT-11: golden 시험 · golden harness 의 모든 테마 호출과, 테마 시험 파일의 주입이
//   필요한 시험 범위의 모든 테마 호출이 받은 팔레트 그대로 쓰는 builder 를 넘긴다.
//
// 두 시험 모두 adopter 가 고치는 파일을 읽으므로 유지보수자 트리에서만 돈다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/planning_docs.dart';
import '../../helpers/source_text.dart';

/// 테마 생성 호출 이름 — `AppTheme.light(` · `AppTheme.dark(` 의 머리다.
final RegExp _themeCallHead = RegExp(r'AppTheme\s*\.\s*(light|dark)\s*\(');

/// 주입 인자 — 공백을 흡수해 맞춘다.
final RegExp _injectedBuilder = RegExp(
  r'colorSchemeBuilder\s*:\s*keepReceivedColorScheme\b',
);

/// golden 비교 호출 이름 — 이 파일 자신이 걸리지 않게 이어 붙여 적는다.
const String _goldenMarker =
    'matchesGolden'
    'File';

/// golden 호출이 없어도 훑는 설정 harness 경로.
const String _settingsHarnessPath =
    'test/features/settings/presentation/settings_golden_harness.dart';

/// 테마 시험 파일 경로.
const String _themeTestPath = 'test/core/theme/app_theme_test.dart';

/// 소스 [raw] 에서 행 · 블록 주석을 걷어낸다.
String _stripComments(String raw) =>
    stripBlockComments(stripSlashComments(raw));

/// [code] 의 [open] 자리 여는 괄호에서 짝 닫는 괄호까지의 안쪽을 돌려준다.
///
/// 문자열 리터럴 안의 괄호와 줄 끝 주석 안의 괄호는 세지 않는다. 짝이 없으면
/// 시험을 실패시킨다.
String _readBalancedParens(String code, int open) {
  expect(code[open], '(');
  var depth = 0;
  String? quote;
  for (var i = open; i < code.length; i++) {
    final String ch = code[i];
    if (quote != null) {
      if (ch == r'\') {
        i++;
      } else if (ch == quote) {
        quote = null;
      }
      continue;
    }
    if (ch == "'" || ch == '"') {
      quote = ch;
    } else if (ch == '/' && i + 1 < code.length && code[i + 1] == '/') {
      final int eol = code.indexOf('\n', i);
      if (eol == -1) {
        break;
      }
      i = eol;
    } else if (ch == '(') {
      depth++;
    } else if (ch == ')') {
      depth--;
      if (depth == 0) {
        return code.substring(open + 1, i);
      }
    }
  }
  fail('짝이 맞는 닫는 괄호가 없다');
}

/// [code] 의 테마 생성 호출마다 인자 목록 원문을 모은다.
List<String> _collectThemeCallArgs(String code) => <String>[
  for (final Match head in _themeCallHead.allMatches(code))
    _readBalancedParens(code, head.end - 1),
];

/// [code] 에서 제목이 [title] 로 시작하는 `group(` · `test(` 호출의 안쪽을 돌려준다.
///
/// 제목을 찾지 못하면 실패시킨다 — 제목을 바꿔도 시험이 공허하게 통과하지 않는다.
String _sliceCallByTitle(String code, String title) {
  final head = RegExp(r"(group|test)\(\s*'" + RegExp.escape(title));
  final List<RegExpMatch> found = head.allMatches(code).toList();
  expect(found, hasLength(1), reason: '제목을 하나만 찾아야 한다: $title');
  return _readBalancedParens(code, code.indexOf('(', found.single.start));
}

/// [calls] 가운데 주입 인자가 빠진 호출의 인자 원문을 돌려준다.
List<String> _findCallsWithoutInjection(List<String> calls) => <String>[
  for (final String args in calls)
    if (!_injectedBuilder.hasMatch(args)) args,
];

void main() {
  test(
    'T-29-SLOT-10: 기본 builder 갈래의 밝기 assert 메시지가 받은 밝기와 돌려받은 밝기를 담는다',
    () {
      final String code = _stripComments(
        readTrackedFile('lib/core/theme/app_theme.dart'),
      );

      // `== null ?` 와 `:` 사이 — 기본 builder 갈래의 문자열만 본다.
      expect(
        RegExp(
          r'colorSchemeBuilder\s*==\s*null\s*\?\s*'
          r"'buildAppColorScheme \(\$\{seedScheme\.brightness\.name\}\) returned a '\s*"
          r"'\$\{scheme\.brightness\.name\} ColorScheme — keep the brightness\.'\s*:",
        ).hasMatch(code),
        isTrue,
      );
    },
    // adopter 가 고치는 파일이라 유지보수자 트리에서만 본다.
    skip: skipUnlessMaintainerTree(),
  );

  group('T-29-SLOT-11: 테마 호출이 받은 팔레트 그대로 쓰는 builder 를 넘긴다', () {
    test('golden 시험 · golden harness 의 모든 테마 호출이 넘긴다', () {
      final scanned = <String, List<String>>{};
      final files = <File>[
        for (final FileSystemEntity entity in Directory(
          'test',
        ).listSync(recursive: true))
          if (entity is File && entity.path.endsWith('.dart')) entity,
        File(_settingsHarnessPath),
      ];
      for (final file in files) {
        final String code = _stripComments(file.readAsStringSync());
        final bool isTarget =
            code.contains(_goldenMarker) || file.path == _settingsHarnessPath;
        if (!isTarget) {
          continue;
        }
        final List<String> calls = _collectThemeCallArgs(code);
        if (calls.isNotEmpty) {
          scanned[file.path.replaceAll(r'\', '/')] = calls;
        }
      }

      // 양성 대조 — 훑은 집합이 비어 있으면 아래 단언이 공허하다.
      expect(
        scanned.keys,
        containsAll(<String>[
          _settingsHarnessPath,
          'test/features/auth/presentation/auth_surfaces_golden_test.dart',
          'test/features/auth/presentation/_widgets/branded_social_button_golden_test.dart',
        ]),
      );
      for (final MapEntry<String, List<String>> entry in scanned.entries) {
        expect(
          _findCallsWithoutInjection(entry.value),
          isEmpty,
          reason: '${entry.key}: 주입이 빠진 테마 호출',
        );
      }
    }, skip: skipUnlessMaintainerTree());

    test('테마 시험의 대비 · 색 변형 시험과 다른 seed 시험이 넘긴다', () {
      final String code = _stripComments(readTrackedFile(_themeTestPath));
      final scopes = <String, String>{
        'T-24-THM 묶음': _sliceCallByTitle(code, 'T-24-THM:'),
        '다른 seed light': _sliceCallByTitle(code, '다른 seed 로 light() 를'),
        '다른 seed dark': _sliceCallByTitle(code, '다른 seed 로 dark() 를'),
      };

      for (final MapEntry<String, String> scope in scopes.entries) {
        final List<String> calls = _collectThemeCallArgs(scope.value);
        // 양성 대조 — 범위 안에 호출이 있어야 단언이 공허하지 않다.
        expect(calls, isNotEmpty, reason: '${scope.key}: 테마 호출을 못 찾음');
        expect(
          _findCallsWithoutInjection(calls),
          isEmpty,
          reason: '${scope.key}: 주입이 빠진 테마 호출',
        );
      }
    }, skip: skipUnlessMaintainerTree());
  });
}
