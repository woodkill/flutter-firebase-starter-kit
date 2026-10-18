// README Getting Started 의 위저드 옵션 줄 계약.
//
// T-20-DOCS-04: Getting Started 절에 `./setup.sh --providers` 줄 1개 ·
//   `./setup.sh --flavor stg` 줄 1개가 있다.
// T-20-DOCS-05: 절의 모든 `./setup.sh --<이름>[ <값>]` 줄의 옵션 이름이
//   `bin/setup.dart` 파서에 선언돼 있고, `--flavor` 값은 `Flavor.tryParse` 로 읽힌다.
// T-20-DOCS-06: 판정 함수의 양성 · 음성 대조 — 가짜 옵션 이름 · 값이 걸러진다.
//
// README 는 template 을 쓴 뒤 사용자 소유라 04 · 05 는 유지보수자 트리에서만 돈다.
// 06 은 `bin/setup.dart` 만 읽어 어디서나 돈다.

import 'package:flutter_test/flutter_test.dart';

import '../../tool/setup/flavor.dart';
import '../helpers/planning_docs.dart';
import '../helpers/source_text.dart';

/// README 경로.
const String _readmePath = 'README.md';

/// 위저드 진입점 소스 경로.
const String _setupBinPath = 'bin/setup.dart';

/// Getting Started 절 헤딩.
const String _sectionHeading = '## Getting Started';

/// 옵션 줄 정규식 — `./setup.sh --이름` 뒤에 선택적 값 하나.
final RegExp _optionLinePattern = RegExp(
  r'^\./setup\.sh --([a-z][a-z-]*)(?: (\S+))?$',
);

/// [readme] 에서 Getting Started 절(다음 `## ` 앞까지)을 돌려준다.
String extractGettingStarted(String readme) {
  final int start = readme.indexOf('\n$_sectionHeading\n');
  expect(start, isNonNegative, reason: '$_sectionHeading 헤딩 부재');
  final int bodyStart = start + 1 + _sectionHeading.length;
  final int next = readme.indexOf('\n## ', bodyStart);
  return readme.substring(bodyStart, next < 0 ? readme.length : next);
}

/// [section] 의 `./setup.sh --…` 줄을 (옵션 이름, 값) 쌍으로 모은다.
List<({String name, String? value})> collectOptionLines(String section) =>
    <({String name, String? value})>[
      for (final String line in section.split('\n'))
        if (_optionLinePattern.firstMatch(line) case final RegExpMatch m)
          (name: m.group(1)!, value: m.group(2)),
    ];

/// [source] 의 파서가 옵션 [name] 을 선언하는지 본다(공백 · 줄바꿈 무관).
bool isOptionDeclared(String source, String name) => RegExp(
  "add(?:Flag|Option)\\(\\s*'${RegExp.escape(name)}'",
).hasMatch(source);

/// 옵션 줄 하나가 파서 선언과 맞는지 — 이름이 선언됐고 flavor 값이 읽힌다.
bool isOptionLineValid(String source, ({String name, String? value}) option) {
  if (!isOptionDeclared(source, option.name)) return false;
  if (option.name == 'flavor') {
    final String? value = option.value;
    return value != null && Flavor.tryParse(value) != null;
  }
  return option.value == null;
}

void main() {
  final Object skip = skipUnlessPlanningDocsExist(const <String>[
    '.planning/ROADMAP.md',
  ]);

  test(
    'T-20-DOCS-04: Getting Started 에 --providers · --flavor stg 줄이 하나씩 있다',
    () {
      final String section = extractGettingStarted(
        readTrackedFile(_readmePath),
      );

      expect(countExactLines(section, './setup.sh --providers'), 1);
      expect(countExactLines(section, './setup.sh --flavor stg'), 1);
    },
    skip: skip,
  );

  test('T-20-DOCS-05: README 옵션 줄의 이름 · 값이 bin/setup.dart 파서와 맞는다', () {
    final String section = extractGettingStarted(readTrackedFile(_readmePath));
    final String source = readTrackedFile(_setupBinPath);

    final options = collectOptionLines(section);
    expect(options, isNotEmpty);
    for (final option in options) {
      expect(
        isOptionLineValid(source, option),
        isTrue,
        reason: '--${option.name} ${option.value ?? ''}',
      );
    }
  }, skip: skip);

  test('T-20-DOCS-06: 대조 — 가짜 옵션 이름 · 값은 걸러진다', () {
    final String source = readTrackedFile(_setupBinPath);

    // 양성 대조: 실제 선언은 통과한다.
    expect(isOptionDeclared(source, 'providers'), isTrue);
    expect(isOptionDeclared(source, 'flavor'), isTrue);
    expect(isOptionLineValid(source, (name: 'flavor', value: 'prod')), isTrue);
    // 음성 대조: 없는 이름 · 허용 밖 값 · 값 누락은 막힌다.
    expect(isOptionDeclared(source, 'provider'), isFalse);
    expect(isOptionLineValid(source, (name: 'flavor', value: 'qa')), isFalse);
    expect(isOptionLineValid(source, (name: 'flavor', value: null)), isFalse);
    expect(
      collectOptionLines('./setup.sh --fake x\n./setup.sh\ntext'),
      hasLength(1),
    );
  });
}
