// 매뉴얼 「로그인 수단 켜고 끄기」 계약 (Phase 17.3 D-11 — see ROADMAP.md).
// 헤딩 · 목차 · 사용자 문서 금지 패턴 · 예시 일치 · 배포 함수 목록 대조.
//
// T-173-DOCS-01: 절 헤딩 1개 · 목차 블록 안 항목 1개 · 목차 번호 0부터 연속.
// T-173-DOCS-02: 절에 사용자 문서 금지 패턴(`.claude/rules/docs-user-manual.md`
//   §4 표 전체)이 0 건이다.
// T-173-DOCS-03: 절의 JSON 예시 값 == example 파일 값(enabledAuthProviders 제외) ·
//   provider config 키 8개 · xcconfig 변수 8개가 절과 example 파일 양쪽에 있다.
// T-173-DOCS-04: manifest 의 함수 이름 · provider secret 8개 · 배포 명령 2줄 ·
//   provider 토큰 6개가 절에 있다.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/source_text.dart';

/// 사용자 문서 금지 패턴 (원칙 §4 표 전체 — 플랜 verify 의 `FP` 와 글자 그대로 같다).
const String _forbiddenPatternSource =
    r'Phase [0-9]|\bD-[0-9]{2}\b|\bD-[A-Z]+-[0-9]|\b(WR|IN|CR|BL)-[0-9]|\b[0-9]+(\.[0-9]+)?-(CONTEXT|RESEARCH|PATTERNS|PLAN|SUMMARY|LEDGER|VERIFICATION|VALIDATION|REVIEW|UAT)\b|\.planning|\bquick [0-9]{6}|\b[0-9]{6}-[a-z0-9]{3}\b|\b[0-9a-f]{7,40}\b|\bUAT|실측|재현됐|\bmemory\b|\b(project|feedback|reference)_[a-z0-9_]+|\bgsd[-:]|20[0-9]{2}-[0-9]{2}-[0-9]{2}';

/// 매뉴얼 경로.
const String _manualPath = 'docs/manual.md';

/// 배포 함수 목록(진실원).
const String _manifestPath = 'scripts/functions_manifest.json';

/// config 예시 파일(진실원).
const String _exampleConfigPath = 'config/dev.example.json';

/// xcconfig 예시 파일(진실원).
const String _exampleXcconfigPath = 'ios/Flutter/dev.example.xcconfig';

/// 절 헤딩 (정확히 한 줄).
const String _sectionHeading = '## 로그인 수단 켜고 끄기';

/// 목차 항목 줄 (번호는 목차 위치에 따라 바뀌므로 정규식으로 본다).
final RegExp _tocEntryPattern = RegExp(
  r'^\d+\. \[로그인 수단 켜고 끄기\]\(#로그인-수단-켜고-끄기\)$',
  multiLine: true,
);

/// 켤 때 값을 넣는 provider config 키 8개.
const List<String> _providerConfigKeys = <String>[
  'googleServerClientId',
  'facebookAppId',
  'facebookClientToken',
  'kakaoNativeAppKey',
  'naverClientId',
  'naverClientSecret',
  'naverUrlScheme',
  'lineChannelId',
];

/// 켤 때 값을 넣는 provider xcconfig 변수 8개.
const List<String> _providerXcconfigVars = <String>[
  'REVERSED_CLIENT_ID',
  'FACEBOOK_APP_ID',
  'FACEBOOK_CLIENT_TOKEN',
  'KAKAO_NATIVE_APP_KEY',
  'NAVER_CLIENT_ID',
  'NAVER_CLIENT_SECRET',
  'NAVER_URL_SCHEME',
  'LINE_CHANNEL_ID',
];

/// provider 함수가 쓰는 secret 8개
/// (`functions/test/deploy_manifest.test.ts` 의 소유 맵과 같은 목록).
const List<String> _providerSecrets = <String>[
  'KAKAO_NATIVE_APP_KEY',
  'KAKAO_ADMIN_KEY',
  'NAVER_CLIENT_ID',
  'NAVER_CLIENT_SECRET',
  'LINE_CHANNEL_ID',
  'LINE_CHANNEL_SECRET',
  'FACEBOOK_APP_ID',
  'FACEBOOK_APP_SECRET',
];

/// 절에 줄 단위로 있어야 하는 배포 명령 2줄.
const List<String> _deployCommandLines = <String>[
  'bash scripts/deploy_functions.sh dev',
  'bash scripts/deploy_functions.sh dev --apply',
];

/// `enabledAuthProviders` 에서 쓸 수 있는 토큰 6개.
const List<String> _providerTokens = <String>[
  'google',
  'apple',
  'facebook',
  'kakao',
  'naver',
  'line',
];

/// 절의 JSON 예시 `"<key>": "<value>"` 쌍.
final RegExp _jsonPairPattern = RegExp(r'"([A-Za-z]+)":\s*"([^"]*)"');

/// 매뉴얼에서 `## 목차` 다음 줄부터 그 뒤 첫 `---` 줄 앞까지를 돌려준다.
///
/// 목차 링크 문자열은 본문에도 다시 나오므로(다른 절의 안내 링크) 목차 블록
/// 안에서만 센다. 블록이 없으면 빈 문자열이다.
String _tocBlock(String manual) {
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

/// [text] 의 줄 가운데 [line] 과 정확히 같은 줄의 수를 센다.
int _countExactLines(String text, String line) =>
    text.split('\n').where((String l) => l == line).length;

void main() {
  final String manual = readTrackedFile(_manualPath);
  final String section = sliceMarkdownSection(
    manual,
    _sectionHeading,
    maxLevel: 2,
  );
  final Map<String, Object?> manifest =
      jsonDecode(readTrackedFile(_manifestPath)) as Map<String, Object?>;
  final Map<String, Object?> exampleConfig =
      jsonDecode(readTrackedFile(_exampleConfigPath)) as Map<String, Object?>;
  final String exampleXcconfig = readTrackedFile(_exampleXcconfigPath);

  group('매뉴얼 「로그인 수단 켜고 끄기」 계약 (T-173-DOCS)', () {
    test('T-173-DOCS-01: 절 헤딩 1개 · 목차 항목 1개 · 목차 번호가 0부터 연속이다', () {
      expect(
        _countExactLines(manual, _sectionHeading),
        1,
        reason: '절 헤딩이 없거나 중복이다',
      );

      final String toc = _tocBlock(manual);
      expect(toc.trim(), isNotEmpty, reason: '목차 블록을 찾지 못했다');
      expect(
        _tocEntryPattern.allMatches(toc).length,
        1,
        reason: '목차 블록 안 「로그인 수단 켜고 끄기」 항목이 없거나 중복이다',
      );

      final List<int> numbers = RegExp(
        r'^(\d+)\. ',
        multiLine: true,
      ).allMatches(toc).map((RegExpMatch m) => int.parse(m.group(1)!)).toList();
      expect(numbers, isNotEmpty, reason: '목차 번호 줄이 없다');
      expect(
        numbers,
        List<int>.generate(numbers.length, (int i) => i),
        reason: '목차 번호가 0부터 빠짐없이 이어지지 않는다',
      );
    });

    test('T-173-DOCS-02: 절에 사용자 문서 금지 패턴이 0 건이다', () {
      expect(section.trim(), isNotEmpty, reason: '절 슬라이스가 비었다');
      final List<String> hits = RegExp(
        _forbiddenPatternSource,
      ).allMatches(section).map((RegExpMatch m) => m.group(0)!).toList();
      expect(hits, isEmpty, reason: '금지 패턴이 절에 있다: $hits');
    });

    test('T-173-DOCS-03: 예시 값 · 키 · 변수가 example 파일과 일치한다', () {
      final List<RegExpMatch> pairs = _jsonPairPattern
          .allMatches(section)
          .toList();
      expect(pairs, isNotEmpty, reason: '절에 JSON 예시가 없다(양성 대조)');
      for (final RegExpMatch pair in pairs) {
        final String key = pair.group(1)!;
        final String value = pair.group(2)!;
        expect(
          exampleConfig.containsKey(key),
          isTrue,
          reason: '절의 예시 키 $key 가 $_exampleConfigPath 에 없다',
        );
        if (key == 'enabledAuthProviders') {
          continue;
        }
        expect(
          value,
          '${exampleConfig[key]}',
          reason: '절의 예시 값 $key 가 $_exampleConfigPath 값과 다르다',
        );
      }

      for (final String key in _providerConfigKeys) {
        expect(section, contains('`$key`'), reason: '절에 config 키 $key 가 없다');
        expect(
          exampleConfig.containsKey(key),
          isTrue,
          reason: '$_exampleConfigPath 에 $key 가 없다',
        );
      }

      for (final String name in _providerXcconfigVars) {
        expect(
          section,
          contains('`$name`'),
          reason: '절에 xcconfig 변수 $name 이 없다',
        );
        expect(
          RegExp('^$name\\s*=', multiLine: true).hasMatch(exampleXcconfig),
          isTrue,
          reason: '$_exampleXcconfigPath 에 $name 이 없다',
        );
      }
    });

    test('T-173-DOCS-04: 배포 함수 · secret · 배포 명령 · 토큰이 절에 있다', () {
      final Map<String, Object?> providers =
          manifest['providers']! as Map<String, Object?>;
      final List<String> providerFunctions = <String>[
        for (final Object? list in providers.values)
          ...(list! as List<Object?>).cast<String>(),
      ];
      expect(
        providerFunctions,
        isNotEmpty,
        reason: 'manifest 의 provider 함수를 읽지 못했다(양성 대조)',
      );
      final List<String> commonFunctions =
          (manifest['common']! as List<Object?>).cast<String>();
      for (final String name in <String>[
        ...providerFunctions,
        ...commonFunctions,
      ]) {
        expect(
          section,
          contains('`$name`'),
          reason: 'manifest 의 함수 $name 이 절에 없다',
        );
      }

      for (final String secret in _providerSecrets) {
        expect(section, contains(secret), reason: '절에 secret $secret 이 없다');
      }

      for (final String line in _deployCommandLines) {
        expect(
          _countExactLines(section, line),
          greaterThanOrEqualTo(1),
          reason: '절에 배포 명령 줄 「$line」 이 없다',
        );
      }

      expect(
        providers.keys.toList(),
        _providerTokens,
        reason: 'manifest providers 키가 토큰 목록과 다르다',
      );
      for (final String token in _providerTokens) {
        expect(section, contains('`$token`'), reason: '절에 토큰 $token 이 없다');
      }
    });
  });
}
