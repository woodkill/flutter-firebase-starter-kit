// 디자인 토큰 안내 계약 — docs/guide.md 「디자인 토큰 바꾸기」 의 「무엇에 어떤
// 토큰을 쓰나」 절을 디자인 리터럴 가드(`test/helpers/design_literal_scan.dart`)와
// 묶는다.
//
// 가이드 표의 「쓰지 않는 것」 열이 가드 패턴 이름과 1:1 이고, 가드 문단이 가드가
// 보지 않는 경로를 모두 적는지 고정한다 — 가드 패턴이나 제외 목록을 바꾸고 가이드를
// 그대로 두면 이 시험이 실패한다. 각 슬라이스는 양성 대조(비어 있지 않고 자기
// 헤딩으로 시작한다)를 함께 세워 빈 슬라이스가 공허하게 통과하지 못하게 한다.
//
// T-24-DOC-01: 절이 1번 · 1번 절보다 앞이고 표 행 12개의 첫 칸이 정한 순서다.
// T-24-DOC-02: 표 「쓰지 않는 것」 열의 가드 이름 목록 == 가드 패턴 이름 집합 · 각 1번.
// T-24-DOC-03: 규칙 번호 줄 셋과 카드 나쁨 / 좋음 dart 예시 한 쌍이 있다.
// T-24-DOC-04: 가드 문단이 가드 시험 · 표시 상수 · 제외 경로를 모두 적는다.
//
// 디자인 리터럴 가드를 쓰지 않으려고 `test/core/theme/design_literal_scan_test.dart`
// 를 지우면 이 파일도 함께 지운다(가이드 「무엇에 어떤 토큰을 쓰나」 의 가드 문단).

import 'package:flutter_test/flutter_test.dart';

import '../helpers/design_literal_scan.dart'
    show
        DesignLiteralPattern,
        kDesignLiteralExcludedFiles,
        kDesignLiteralExcludedPrefixes,
        kDesignLiteralPatterns;
import '../helpers/source_text.dart';

/// 사용 가이드 경로.
const String _guidePath = 'docs/guide.md';

/// 디자인 리터럴 가드 시험 경로 — 표시 주석 총수 상수를 선언한다.
const String _scanTestPath = 'test/core/theme/design_literal_scan_test.dart';

/// 가드 패턴 · 제외 목록을 둔 헬퍼 경로.
const String _scanHelperPath = 'test/helpers/design_literal_scan.dart';

/// 표시 주석 총수 상수 이름.
const String _markerCountName = '_designLiteralMarkerCount';

/// 「디자인 토큰 바꾸기」 절 헤딩.
const String _tokensHeading = '## 디자인 토큰 바꾸기';

/// 「무엇에 어떤 토큰을 쓰나」 절 헤딩.
const String _tableHeading = '### 무엇에 어떤 토큰을 쓰나';

/// 「디자인 토큰 바꾸기」 1번 절 헤딩.
const String _firstStepHeading = '### 1. 시드 컬러 교체 — M3 팔레트 전체 전환';

/// 「무엇에 어떤 토큰을 쓰나」 표 머리.
const String _tableHeader = '| 디자인 속성 | 쓰는 것 | 쓰지 않는 것 | 기본값 출처 |';

/// 표 행 첫 칸(디자인 속성)의 순서.
const List<String> _expectedProperties = <String>[
  '색',
  '글자',
  '간격',
  '둥글기',
  '아이콘 크기',
  '투명도',
  'elevation',
  'motion',
  '테두리 굵기',
  '화면 폭',
  '컴포넌트 모양',
  '한 컴포넌트만의 치수',
];

/// 표 아래 규칙 번호 줄 셋.
const List<String> _ruleLines = <String>[
  '1. **시스템 값은 토큰 getter 나 SDK 상수로 읽는다.**',
  '2. **컴포넌트 역할 값은 `ThemeData` 의 컴포넌트 테마에 한 번 둔다.**',
  '3. **한 컴포넌트만의 치수는 이름 붙인 상수로 두고 바로 윗줄에 `// design-literal: <이유>` 를 단다.**',
];

/// 가드 범위 줄 — 테마 조립 파일은 가드 밖이다.
const String _appFileOutsideLine = '테마 조립 파일 `lib/app.dart` 는 가드 밖이다';

/// 백틱 안 글자를 모으는 정규식.
final RegExp _backtickSpan = RegExp('`([^`]+)`');

/// 가드 패턴 이름 꼴 — 소문자 · 숫자 묶음을 하이픈으로 이은 글자 전체.
final RegExp _guardNameShape = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)+$');

/// dart 펜스 본문을 모으는 정규식.
final RegExp _dartFence = RegExp(r'```dart\n(.*?)\n```', dotAll: true);

/// 가이드에서 「무엇에 어떤 토큰을 쓰나」 절을 잘라 돌려준다.
///
/// 「디자인 토큰 바꾸기」 절과 그 안의 이 절이 비어 있지 않고 자기 헤딩으로
/// 시작하는지 함께 단언한다.
String _readTableSection() {
  final String guide = readTrackedFile(_guidePath);
  final String tokens = sliceMarkdownSection(
    guide,
    _tokensHeading,
    maxLevel: 2,
  );
  expect(tokens, startsWith(_tokensHeading), reason: '「디자인 토큰 바꾸기」 절이 없다');
  final String section = sliceMarkdownSection(
    tokens,
    _tableHeading,
    maxLevel: 3,
  );
  expect(section, startsWith(_tableHeading), reason: '「무엇에 어떤 토큰을 쓰나」 절이 없다');
  return section;
}

/// 표 행(머리 · 구분 줄 뒤)을 칸 목록으로 돌려준다.
///
/// 칸은 `|` 로 나눈 뒤 앞뒤 공백을 지운 글자다 — 맨 앞 · 맨 뒤 빈 칸은 뺀다.
List<List<String>> _readTableRows(String section) {
  final List<String> table = collectTableLines(section, _tableHeader);
  expect(table, isNotEmpty, reason: '표 머리 `$_tableHeader` 가 없다');
  return table.skip(2).map((String line) {
    final List<String> cells = line.split('|');
    return cells
        .sublist(1, cells.length - 1)
        .map((String cell) => cell.trim())
        .toList();
  }).toList();
}

void main() {
  test('T-24-DOC-01: 「무엇에 어떤 토큰을 쓰나」 절이 1번 절 앞에 한 번 있고 표 행 12개가 정한 순서다', () {
    final String guide = readTrackedFile(_guidePath);
    final String tokens = sliceMarkdownSection(
      guide,
      _tokensHeading,
      maxLevel: 2,
    );
    expect(tokens, startsWith(_tokensHeading));
    expect(countExactLines(tokens, _tableHeading), 1);
    expect(countExactLines(tokens, _firstStepHeading), 1);
    expect(
      tokens.indexOf('$_tableHeading\n'),
      lessThan(tokens.indexOf('$_firstStepHeading\n')),
      reason: '표 절은 1번 절보다 앞이다',
    );

    final List<List<String>> rows = _readTableRows(_readTableSection());
    expect(
      rows.map((List<String> cells) => cells.first).toList(),
      _expectedProperties,
    );
    for (final cells in rows) {
      expect(cells, hasLength(4), reason: '행 칸 수가 4 가 아니다: $cells');
    }
  });

  test('T-24-DOC-02: 표 「쓰지 않는 것」 열의 가드 이름이 가드 패턴 이름과 1:1 이다', () {
    final List<List<String>> rows = _readTableRows(_readTableSection());
    final names = <String>[
      for (final List<String> cells in rows)
        for (final RegExpMatch match in _backtickSpan.allMatches(cells[2]))
          if (_guardNameShape.hasMatch(match.group(1)!)) match.group(1)!,
    ];
    final List<String> patternNames = kDesignLiteralPatterns
        .map((DesignLiteralPattern p) => p.name)
        .toList();

    expect(patternNames, isNotEmpty, reason: '가드 패턴 목록이 비었다');
    expect(names.toSet(), patternNames.toSet());
    expect(names, hasLength(patternNames.length), reason: '같은 이름이 두 번 있다');
  });

  test('T-24-DOC-03: 규칙 번호 줄 셋과 카드 나쁨 / 좋음 dart 예시 한 쌍이 있다', () {
    final String section = _readTableSection();
    for (final String line in _ruleLines) {
      expect(countExactLines(section, line), 1, reason: '규칙 줄이 없다: $line');
    }

    final List<String> fences = _dartFence
        .allMatches(section)
        .map((RegExpMatch m) => m.group(1)!)
        .toList();
    final int goodIndex = fences.indexWhere(
      (String body) =>
          body.contains('cardTheme: CardThemeData(') && body.contains('Card('),
    );
    final int badIndex = fences.indexWhere(
      (String body) => body.contains('Card(elevation:'),
    );
    expect(goodIndex, isNot(-1), reason: '「좋음」 펜스(cardTheme + Card)가 없다');
    expect(badIndex, isNot(-1), reason: '「나쁨」 펜스(Card(elevation:)가 없다');
    expect(goodIndex, isNot(badIndex), reason: '나쁨 · 좋음은 다른 펜스다');
  });

  test('T-24-DOC-04: 가드 문단이 가드 시험 · 표시 상수 · 제외 경로를 모두 적는다', () {
    final String section = _readTableSection();
    expect(section, contains(_scanTestPath));
    expect(section, contains(_scanHelperPath));
    expect(section, contains(_markerCountName));
    expect(section, contains(_appFileOutsideLine));
    expect(section, contains('생성 파일'));

    final String scanTest = readTrackedFile(_scanTestPath);
    expect(
      RegExp('const\\s+int\\s+$_markerCountName\\s*=').hasMatch(scanTest),
      isTrue,
      reason: '$_scanTestPath 에 $_markerCountName 선언이 없다',
    );

    final excluded = <String>[
      ...kDesignLiteralExcludedPrefixes,
      ...kDesignLiteralExcludedFiles,
    ];
    expect(excluded, isNotEmpty, reason: '가드 제외 목록이 비었다');
    for (final path in excluded) {
      expect(section, contains('`$path`'), reason: '가드 문단에 제외 경로가 없다: $path');
    }
  });
}
