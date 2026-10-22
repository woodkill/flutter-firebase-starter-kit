// 사용자 문서 실 값 계약 — gitignored 실 설정 값과 키 · 팀 ID · 채널 ID · 메일
// 모양이 사용자 문서와 예시 파일에 없다.
//
// 어디서 도는가: 차집합 · 모양 검사 함수 표본(REAL-03)은 어디서나 돈다. 실 값 대조
// (REAL-01)는 비공개 작업 일지와 gitignored 실 설정 파일 여섯이 모두 있는 유지보수자
// 트리에서만 돌고, 모양 검사(REAL-02)는 킷 사용자가 자기 문서에 자기 값을 적어도
// 깨지지 않게 유지보수자 트리에서만 돈다. 두 검사의 출발점은 대상에서 지울 원본
// 매뉴얼([kRetiringManualPath])을 뺀 목록이다.
//
// T-21-REAL-01: 실 값 가운데 예시 값 · 이름 바꾸기 기본값과 다르고 6자 이상이며
//   자리표시가 아닌 값이 대상 파일 어디에도 없다. 실패 사유에는 파일 · flavor · 키
//   이름만 나온다.
// T-21-REAL-02: API 키 · 팀 ID · 채널 ID · 메일 모양이 대상 파일에 없다(예시 0 값
//   꼴은 허용).
// T-21-REAL-03: 차집합 함수와 모양 검사 함수 표본.
//
// **값 모양 리터럴을 두지 않는다** — 표본은 조각을 이어 붙여 만들고, 허용 꼴도 인접
// 문자열로 끊는다. 이 파일도 공개 이력에 들어가 같은 치환 규칙 · 스캔을 거친다.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/planning_docs.dart';
import '../helpers/source_text.dart';
import '../helpers/user_docs.dart';

/// 실 값을 대조하는 flavor 다.
const List<String> _flavors = <String>['dev', 'stg', 'prod'];

/// `config/<flavor>.json` 에서 대조하는 식별자 키다.
const List<String> _configKeys = <String>[
  'firebaseProjectId',
  'firebaseWebApiKey',
  'googleServerClientId',
  'facebookAppId',
  'facebookClientToken',
  'kakaoNativeAppKey',
  'naverClientId',
  'naverClientSecret',
  'naverUrlScheme',
  'lineChannelId',
  'appCheckDebugToken',
];

/// `ios/Flutter/<flavor>.xcconfig` 에서 대조하는 변수다.
const List<String> _xcconfigKeys = <String>[
  'PRODUCT_BUNDLE_IDENTIFIER',
  'REVERSED_CLIENT_ID',
  'FACEBOOK_APP_ID',
  'FACEBOOK_CLIENT_TOKEN',
  'KAKAO_NATIVE_APP_KEY',
  'NAVER_URL_SCHEME',
  'NAVER_CLIENT_ID',
  'NAVER_CLIENT_SECRET',
  'LINE_CHANNEL_ID',
  'DEVELOPMENT_TEAM',
];

/// 이름 바꾸기 도구 — 킷 기본 식별자 상수가 있는 곳이다.
const String _renameToolPath = 'bin/rename.dart';

/// 이름 바꾸기 도구의 `const current… = '…';` 줄이다.
final RegExp _renameConstantLine = RegExp(
  r"^const current\w+ = '([^']+)';",
  multiLine: true,
);

/// xcconfig 의 `KEY = value` 줄이다.
final RegExp _xcconfigEntry = RegExp(r'^([A-Z_]+)\s*=\s*(.*)$');

/// flavor [flavor] 의 gitignored 실 설정 파일 두 개다.
List<String> _realConfigPaths(String flavor) => <String>[
  'config/$flavor.json',
  'ios/Flutter/$flavor.xcconfig',
];

/// 실 값 대조의 skip 값 — 비공개 작업 일지와 실 설정 파일 여섯이 다 있어야 돈다.
Object _skipUnlessRealConfigExists() {
  final Object planning = skipUnlessPlanningDocsExist(<String>[
    '.planning/ROADMAP.md',
  ]);
  if (planning != false) {
    return planning;
  }
  for (final String flavor in _flavors) {
    for (final String path in _realConfigPaths(flavor)) {
      if (!File(path).existsSync()) {
        return '실 설정 파일($path)이 없는 트리(공개 mirror · 새 clone) — 유지보수자 검사 건너뜀';
      }
    }
  }
  return false;
}

/// JSON 설정 파일 [path] 에서 문자열 · 숫자 값을 키 → 문자열로 읽는다.
Map<String, String> _readJsonValues(String path) {
  final Object? decoded = jsonDecode(File(path).readAsStringSync());
  if (decoded is! Map<String, Object?>) {
    fail('JSON 객체가 아니다: $path');
  }
  return <String, String>{
    for (final MapEntry<String, Object?> entry in decoded.entries)
      if (entry.value is String || entry.value is num)
        entry.key: '${entry.value}',
  };
}

/// xcconfig 파일 [path] 에서 `KEY = value` 를 키 → 값으로 읽는다(행 주석 제외).
Map<String, String> _readXcconfigValues(String path) => <String, String>{
  for (final String line in stripSlashComments(
    File(path).readAsStringSync(),
  ).split('\n'))
    if (_xcconfigEntry.firstMatch(line.trim()) case final RegExpMatch match)
      match.group(1)!: match.group(2)!.trim(),
};

/// 이름 바꾸기 도구의 킷 기본 식별자 값을 읽는다.
Set<String> _readRenameConstants() => _renameConstantLine
    .allMatches(readTrackedFile(_renameToolPath))
    .map((RegExpMatch match) => match.group(1)!)
    .toSet();

/// 대상에서 지울 원본 매뉴얼을 뺀 검사 출발점이다.
List<String> _collectCheckedTargets() => collectUserDocTargets()
    .where((String path) => path != kRetiringManualPath)
    .toList();

/// 자리표시 값의 머리다.
const List<String> _placeholderPrefixes = <String>[
  'your-',
  'YOUR_',
  'REPLACE_WITH_',
];

/// 금지 값으로 치는 최소 길이 — 이보다 짧은 값은 문서의 다른 낱말과 겹친다.
const int _minForbiddenValueLength = 6;

/// [value] 가 자리표시인지 돌려준다 — 비었거나 · 자리표시 머리로 시작하거나 ·
/// `unset` 이거나 · 빌드 변수 참조(`$(`)를 담거나 · `<` 로 시작하는 값이다.
bool _isPlaceholder(String value) =>
    value.isEmpty ||
    _placeholderPrefixes.any(value.startsWith) ||
    value == 'unset' ||
    value.contains(r'$(') ||
    value.startsWith('<');

/// 실 값 [real] 에서 [keys] 의 값 가운데 사용자 문서에 있으면 안 되는 값을 키 →
/// 값으로 돌려준다.
///
/// 자리표시이거나, 6자 미만이거나, 그 키의 예시 값([example])과 같거나, 킷 기본
/// 식별자([allowedValues])인 값은 뺀다 — 문서가 예시 파일과 글자 그대로 적어야 하는
/// 값이다. [real] 에 없는 키는 건너뛴다. 돌려준 값은 시험 출력에 내지 않는다.
Map<String, String> collectForbiddenLocalValues({
  required Map<String, String> real,
  required Map<String, String> example,
  required Iterable<String> keys,
  required Set<String> allowedValues,
}) {
  final forbidden = <String, String>{};
  for (final key in keys) {
    final String? raw = real[key];
    if (raw == null) {
      continue;
    }
    final String value = raw.trim();
    if (_isPlaceholder(value) ||
        value.length < _minForbiddenValueLength ||
        value == example[key]?.trim() ||
        allowedValues.contains(value)) {
      continue;
    }
    forbidden[key] = value;
  }
  return forbidden;
}

/// 값 모양 하나 — 이름 · 정규식 · 허용하는 일치 글자(없으면 `null`)다.
typedef _ValueShape = ({String name, RegExp pattern, String? allowedMatch});

/// 사용자 문서에 있으면 안 되는 값 모양이다.
///
/// 공개 배포 스크립트(`scripts/publish_kit.sh`)의 검사 정규식과 같은 뜻이다. 팀 ID ·
/// 채널 ID 는 0 으로 채운 예시 꼴만 허용한다 — 허용 꼴도 조각으로 만든다.
final List<_ValueShape> _valueShapes = <_ValueShape>[
  (
    name: 'api-key',
    pattern: RegExp('AIza[0-9A-Za-z_-]{35}'),
    allowedMatch: null,
  ),
  (
    name: 'team-id',
    pattern: RegExp('DEVELOPMENT_TEAM = [A-Z0-9]{10};'),
    allowedMatch: <String>['DEVELOPMENT_TEAM = 00000', '00000;'].join(),
  ),
  (
    name: 'channel-id',
    pattern: RegExp(r'\(예: `[0-9]{10}`\)'),
    allowedMatch: <String>['(예: `00000', '00000`)'].join(),
  ),
  (
    name: 'email',
    pattern: RegExp(r'[A-Za-z0-9._%+-]+@(naver|gmail)\.com'),
    allowedMatch: null,
  ),
];

/// 대상 [text] 에서 값 모양을 줄마다 찾아 `'<path>:<줄> — <모양 이름>'` 목록으로
/// 돌려준다.
///
/// 한 줄에서 허용 꼴이 아닌 일치가 하나라도 있으면 그 모양의 위반이다. 일치한 글자와
/// 줄 내용은 내지 않는다.
List<String> findShapeHits(String path, String text) {
  final hits = <String>[];
  final List<String> lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    for (final _ValueShape shape in _valueShapes) {
      final bool hasHit = shape.pattern
          .allMatches(lines[i])
          .any((RegExpMatch match) => match.group(0) != shape.allowedMatch);
      if (hasHit) {
        hits.add('$path:${i + 1} — ${shape.name}');
      }
    }
  }
  return hits;
}

void main() {
  test('T-21-REAL-01: gitignored 실 값이 사용자 문서 · 예시에 없다', () {
    final Set<String> allowed = _readRenameConstants();
    expect(allowed, isNotEmpty, reason: '이름 바꾸기 기본값을 읽지 못했다');

    // (flavor 키 이름) → 금지 값. 값은 출력하지 않는다.
    final forbidden = <String, String>{};
    for (final String flavor in _flavors) {
      final Map<String, String> config = collectForbiddenLocalValues(
        real: _readJsonValues('config/$flavor.json'),
        example: _readJsonValues('config/$flavor.example.json'),
        keys: _configKeys,
        allowedValues: allowed,
      );
      final Map<String, String> xcconfig = collectForbiddenLocalValues(
        real: _readXcconfigValues('ios/Flutter/$flavor.xcconfig'),
        example: _readXcconfigValues('ios/Flutter/$flavor.example.xcconfig'),
        keys: _xcconfigKeys,
        allowedValues: allowed,
      );
      for (final entry in <MapEntry<String, String>>[
        ...config.entries,
        ...xcconfig.entries,
      ]) {
        forbidden['$flavor ${entry.key}'] = entry.value;
      }
    }
    // 양성 대조: 실 값이 하나도 없으면 대조가 공허하다.
    expect(forbidden.isNotEmpty, isTrue, reason: '대조할 실 값이 0개다');

    final List<String> targets = _collectCheckedTargets();
    expect(targets, isNotEmpty, reason: '대상이 비었다');
    final hits = <String>[];
    for (final path in targets) {
      final String text = readTrackedFile(path);
      for (final MapEntry<String, String> entry in forbidden.entries) {
        if (text.contains(entry.value)) {
          hits.add('$path: ${entry.key}');
        }
      }
    }
    // 결과 한 줄(개수만) — 여러 파일을 함께 돌려도 시험 로그에 이 시험 이름이 남는다.
    debugPrintSynchronously(
      '실 값 대조: 값 ${forbidden.length}개 · 대상 ${targets.length}개 · '
      '일치 ${hits.length}건',
    );
    expect(hits, isEmpty, reason: '실 값이 대상 파일에 있다(파일: flavor 키)');
  }, skip: _skipUnlessRealConfigExists());

  test('T-21-REAL-02: 키 · 팀 ID · 채널 ID · 메일 모양이 사용자 문서 · 예시에 없다', () {
    final List<String> targets = _collectCheckedTargets();
    expect(targets, isNotEmpty, reason: '대상이 비었다');
    final hits = <String>[
      for (final String path in targets)
        ...findShapeHits(path, readTrackedFile(path)),
    ];
    expect(hits, isEmpty, reason: '값 모양이 대상 파일에 있다(파일:줄 — 모양 이름)');
  }, skip: skipUnlessPlanningDocsExist(<String>['.planning/ROADMAP.md']));

  test('T-21-REAL-03: 실 값 차집합 · 모양 검사 표본', () {
    // 차집합: 예시와 같은 값 · 빈 값 · 자리표시 · 5자 값 · 이름 바꾸기 기본값은 빠지고,
    // 다른 값(6자 이상)만 남는다.
    final String otherValue = <String>['zq', '9x81', 'mw40'].join();
    final String sixChars = <String>['k7', 'p2', 'w9'].join();
    final Map<String, String> result = collectForbiddenLocalValues(
      real: <String, String>{
        'same': 'shared-example-value',
        'empty': '  ',
        'yourLower': 'your-project-id',
        'yourUpper': 'YOUR_FACEBOOK_APP_ID_HERE',
        'replace': 'REPLACE_WITH_DEV_KEY',
        'unset': 'unset',
        'variable': r'$(inherited)',
        'angle': '<your-team-id>',
        'short': 'ab3de',
        'renamed': 'com.example.kit',
        'other': otherValue,
        'six': sixChars,
        'notListed': <String>['zz', '7781', 'qq'].join(),
      },
      example: <String, String>{'same': 'shared-example-value'},
      keys: <String>[
        'same',
        'empty',
        'yourLower',
        'yourUpper',
        'replace',
        'unset',
        'variable',
        'angle',
        'short',
        'renamed',
        'other',
        'six',
        'missing',
      ],
      allowedValues: <String>{'com.example.kit'},
    );
    expect(result.keys.toSet(), <String>{'other', 'six'});

    // 모양 검사: 조각으로 만든 네 모양을 잡고, 예시 0 값 꼴 둘은 놓친다.
    final String shapes = <String>[
      <String>['key: AI', 'za', 'Ab1_-' * 7].join(),
      <String>['DEVELOPMENT_TEAM = ', 'AB12CD34EF', ';'].join(),
      <String>['채널 (예: `', '1234567890', '`)'].join(),
      <String>['메일: someone', '@', 'gmail', '.com'].join(),
      <String>['DEVELOPMENT_TEAM = 00000', '00000;'].join(),
      <String>['채널 (예: `00000', '00000`)'].join(),
    ].join('\n');
    expect(findShapeHits('README.md', shapes), <String>[
      'README.md:1 — api-key',
      'README.md:2 — team-id',
      'README.md:3 — channel-id',
      'README.md:4 — email',
    ]);
  });
}
