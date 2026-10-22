// README 첫 화면 계약 — 절 순서 · 들어 있는 것 · 전제.
//
// README 는 공개 저장소를 처음 연 사람이 보는 첫 화면이다. 절 순서와, 킷이 담은
// 로그인 수단 · 언어 · 전제를 말하는 글이 킷 코드와 맞는지 지킨다. 로그인 수단은
// 설정 위저드 카탈로그의 표시 이름에서, 언어는 `lib/l10n/` 의 ARB 파일에서 읽는다 —
// 킷이 수단 · 언어를 바꾸면 이 파일이 먼저 실패해 README 를 고치게 한다.
//
// 어디서 도는가: 세 시험 모두 킷 사용자가 README 를 자기 앱 소개로 바꾸면 깨지는
// 내용 검사라, 비공개 작업 일지(`.planning/`)가 있는 유지보수자 트리에서만 돈다.
//
// T-21-README-01: README 의 펜스 밖 `## ` 줄이 정한 다섯 절 순서와 같다.
// T-21-README-02: 「들어 있는 것」 절이 카탈로그 표시 이름 여섯을 모두 담고, ARB 파일
//   수(3)와 같은 세 언어 이름을 담는다. 양성 대조 — 카탈로그에서 읽은 이름이 6개다.
// T-21-README-03: 「전제」 절이 FVM · dev Firebase · `--flavor` · 켜고 끄기 ·
//   패키지명을 담는다.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/planning_docs.dart';
import '../helpers/source_text.dart';

/// README 경로.
const String _readmePath = 'README.md';

/// 설정 위저드의 로그인 수단 카탈로그 소스 경로.
const String _providerCatalogPath =
    'tool/setup/providers/provider_catalog.dart';

/// ARB 파일이 있는 디렉터리(직속 파일만 센다 — 생성 디렉터리는 세지 않는다).
const String _l10nDirectory = 'lib/l10n';

/// README 의 `## ` 절 — 첫 화면 순서 그대로.
const List<String> _expectedHeadings = <String>[
  '## 들어 있는 것',
  '## 전제',
  '## 빠른 시작',
  '## 문서',
  '## 판 · 업데이트 · Issues',
];

/// 「들어 있는 것」 절 헤딩.
const String _contentsHeading = '## 들어 있는 것';

/// 「전제」 절 헤딩.
const String _prerequisitesHeading = '## 전제';

/// 카탈로그의 로그인 수단 수.
const int _expectedProviderCount = 6;

/// ARB 언어 코드 → README 에 쓰는 언어 이름.
const Map<String, String> _languageNames = <String, String>{
  'ko': '한국어',
  'en': '영어',
  'ja': '일본어',
};

/// 「전제」 절이 담아야 하는 글자 — FVM · dev Firebase · flavor · 켜고 끄기 · 패키지명.
const List<String> _prerequisiteTokens = <String>[
  'fvm',
  'dev',
  '--flavor',
  '켜고 끄기',
  'flutter_starter_kit',
];

/// 카탈로그 소스의 표시 이름 줄(`displayName: '…'`)을 잡는다.
final RegExp _displayNamePattern = RegExp(r"displayName:\s*'([^']+)'");

/// ARB 파일 이름(`app_<언어>.arb`)을 잡는다.
final RegExp _arbFileNamePattern = RegExp(r'^app_([a-z]{2,3})\.arb$');

/// [markdown] 에서 0열 코드 펜스 밖의 `## ` 줄을 순서대로 모은다.
List<String> collectLevelTwoHeadings(String markdown) {
  final headings = <String>[];
  var inFence = false;
  for (final String line in markdown.split('\n')) {
    if (line.startsWith('```')) {
      inFence = !inFence;
      continue;
    }
    if (!inFence && line.startsWith('## ')) {
      headings.add(line);
    }
  }
  return headings;
}

/// [source] 에서 `displayName: '…'` 의 표시 이름을 순서대로 모은다.
List<String> collectDisplayNames(String source) => _displayNamePattern
    .allMatches(source)
    .map((RegExpMatch match) => match.group(1)!)
    .toList();

/// [directory] 직속의 `app_<언어>.arb` 파일에서 언어 코드를 정렬해 모은다.
List<String> collectArbLanguageCodes(String directory) {
  final codes = <String>[];
  for (final FileSystemEntity entity in Directory(directory).listSync()) {
    if (entity is! File) {
      continue;
    }
    final RegExpMatch? match = _arbFileNamePattern.firstMatch(
      entity.uri.pathSegments.last,
    );
    if (match != null) {
      codes.add(match.group(1)!);
    }
  }
  return codes..sort();
}

void main() {
  test('T-21-README-01: README 절이 첫 화면 순서다', () {
    final List<String> headings = collectLevelTwoHeadings(
      readTrackedFile(_readmePath),
    );
    // 결과 한 줄 — 여러 파일을 함께 돌려도 시험 로그에 이 시험 이름이 남는다.
    debugPrintSynchronously('README 절 ${headings.length}개: $headings');
    expect(headings, _expectedHeadings);
  }, skip: skipUnlessPlanningDocsExist(const <String>['.planning/ROADMAP.md']));

  test('T-21-README-02: 들어 있는 것이 로그인 수단 여섯과 세 언어를 말한다', () {
    final List<String> names = collectDisplayNames(
      readTrackedFile(_providerCatalogPath),
    );
    // 양성 대조: 카탈로그에서 표시 이름을 실제로 읽는다.
    expect(names, hasLength(_expectedProviderCount));

    final String contents = sliceMarkdownSection(
      readTrackedFile(_readmePath),
      _contentsHeading,
      maxLevel: 2,
    );
    expect(contents.trim(), isNotEmpty, reason: '들어 있는 것 절이 없다');
    for (final name in names) {
      expect(contents, contains(name), reason: '로그인 수단 $name 이 없다');
    }

    final List<String> codes = collectArbLanguageCodes(_l10nDirectory);
    expect(codes, hasLength(_languageNames.length));
    for (final code in codes) {
      final String? language = _languageNames[code];
      expect(language, isNotNull, reason: '언어 이름을 정하지 않은 ARB: $code');
      expect(contents, contains(language), reason: '언어 $language 이 없다');
    }
    // 결과 한 줄 — 여러 파일을 함께 돌려도 시험 로그에 이 시험 이름이 남는다.
    debugPrintSynchronously('들어 있는 것: 로그인 수단 $names · 언어 $codes');
  }, skip: skipUnlessPlanningDocsExist(const <String>['.planning/ROADMAP.md']));

  test('T-21-README-03: 전제가 FVM · dev Firebase · 켜고 끄기 · 패키지명을 담는다', () {
    final String prerequisites = sliceMarkdownSection(
      readTrackedFile(_readmePath),
      _prerequisitesHeading,
      maxLevel: 2,
    );
    expect(prerequisites.trim(), isNotEmpty, reason: '전제 절이 없다');
    final List<String> missing = _prerequisiteTokens
        .where((String token) => !prerequisites.contains(token))
        .toList();
    // 결과 한 줄 — 여러 파일을 함께 돌려도 시험 로그에 이 시험 이름이 남는다.
    debugPrintSynchronously('전제: 빠진 글자 ${missing.length}개');
    expect(missing, isEmpty, reason: '전제 절에 빠진 글자가 있다');
  }, skip: skipUnlessPlanningDocsExist(const <String>['.planning/ROADMAP.md']));
}
