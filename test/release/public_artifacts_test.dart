// 공개본 루트 산출물(LICENSE · CHANGELOG · CONTRIBUTING)의 모양을 고정한다
// (Phase 17.4 D-19 · D-21 · D-23 · D-26 · D-33 — see ROADMAP.md).
//
// T-174-ART-01: LICENSE 가 MIT 원문(첫 줄 · 저작권 줄 · 본문 3단락 글자 그대로)으로
//   시작하고, 본문 뒤에 제3자 자산 절이 따로 있다.
// T-174-ART-02: CHANGELOG 가 Keep a Changelog 한국어판 형식이고 `## [Unreleased]` 가
//   첫 절이다. 판 절 제목 · `###` 유형 이름 · `KIT_VERSION` 과 판 번호의 일치를 본다.
// T-174-ART-03: tracked 자산 라이선스 파일 목록 == LICENSE 제3자 절의 경로 목록.
// T-174-ART-04: CONTRIBUTING · CHANGELOG 본문에 사용자 문서 금지 패턴이 0 건이고,
//   CONTRIBUTING 이 발행본 · PR · Issues · 보안 안내를 담는다.
//
// **tracked 파일만 읽는다** — 모두 키 · secret 값이 없는 tracked 파일이다.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_text.dart';

/// LICENSE 경로.
const String _licensePath = 'LICENSE';

/// CHANGELOG 경로.
const String _changelogPath = 'CHANGELOG.md';

/// CONTRIBUTING 경로.
const String _contributingPath = 'CONTRIBUTING.md';

/// 킷 판 번호 파일 경로 (릴리스 컷 때 생긴다).
const String _kitVersionPath = 'KIT_VERSION';

/// LICENSE 저작권 줄 (정확히 한 줄).
const String _copyrightLine = 'Copyright (c) 2026 Woody Moon';

/// LICENSE 제3자 자산 절 제목 줄 (정확히 한 줄).
const String _thirdPartyTitle =
    'Third-party assets (not covered by the MIT License above)';

/// MIT 본문 3단락 (GitHub 라이선스 템플릿 원문 그대로 · 80열 줄바꿈).
const List<String> _mitParagraphs = <String>[
  'Permission is hereby granted, free of charge, to any person obtaining a copy\n'
      'of this software and associated documentation files (the "Software"), to deal\n'
      'in the Software without restriction, including without limitation the rights\n'
      'to use, copy, modify, merge, publish, distribute, sublicense, and/or sell\n'
      'copies of the Software, and to permit persons to whom the Software is\n'
      'furnished to do so, subject to the following conditions:',
  'The above copyright notice and this permission notice shall be included in all\n'
      'copies or substantial portions of the Software.',
  'THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR\n'
      'IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,\n'
      'FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE\n'
      'AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER\n'
      'LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,\n'
      'OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE\n'
      'SOFTWARE.',
];

/// MIT 본문 단락마다 첫 문구 (등장 횟수 단언용).
const List<String> _mitParagraphOpenings = <String>[
  'Permission is hereby granted, free of charge,',
  'The above copyright notice and this permission notice shall be included in all',
  'THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,',
];

/// CHANGELOG 판 절에 허용하는 `###` 유형 이름 (Keep a Changelog 6종 + 킷 전용 1종).
const Set<String> _allowedChangeTypes = <String>{
  '사용자 조치',
  'Added',
  'Changed',
  'Deprecated',
  'Removed',
  'Fixed',
  'Security',
};

/// 판 절 제목 모양 — `## [1.0.0-rc.1] - 날짜`.
final RegExp _releaseHeading = RegExp(
  r'^## \[(\d+\.\d+\.\d+(?:-rc\.\d+)?)\] - \d{4}-\d{2}-\d{2}$',
);

/// `KIT_VERSION` 파일 내용 모양 — 한 줄 · `v` 없음 · 끝 줄바꿈 1개.
final RegExp _kitVersionContent = RegExp(r'^(\d+\.\d+\.\d+(?:-rc\.\d+)?)\n$');

/// 공개 repo 주소 (compare · releases 링크의 앞부분).
const String _publicRepoUrl =
    'https://github.com/woodkill/flutter-firebase-starter-kit';

/// 릴리스 컷 규칙 (ART-02 reason 공통 문구).
const String _releaseCutRule = '릴리스 컷은 KIT_VERSION 과 판 절을 함께 만든다';

/// CHANGELOG 에서 금지 패턴 검사 대상이 아닌 줄 — 판 절 제목(날짜)과 링크 정의 줄.
final RegExp _changelogExemptLine = RegExp(r'^## \[|^\[[^\]]+\]: https://');

/// CONTRIBUTING 이 담아야 하는 토큰 (발행본 · PR 반영 불가 · 이슈 · 보안 경로).
const List<String> _contributingTokens = <String>['발행본', 'PR', 'Issues', '보안'];

/// [text] 에서 사용자 문서 금지 패턴에 맞는 문자열을 모두 돌려준다.
List<String> _findForbidden(String text) => RegExp(
  kUserDocForbiddenPatternSource,
).allMatches(text).map((RegExpMatch m) => m.group(0)!).toList();

void main() {
  group('공개 릴리스 산출물', () {
    test(
      'T-174-ART-01: LICENSE = MIT 원문(첫 줄 · 저작권 줄 · 본문 3단락) + 본문 뒤 제3자 절',
      () {
        final String license = readTrackedFile(_licensePath);
        final List<String> lines = license.split('\n');

        expect(lines.first, 'MIT License');
        expect(
          lines.where((String line) => line == _copyrightLine).length,
          1,
          reason: '저작권 줄 `$_copyrightLine` 이 정확히 한 줄이어야 한다',
        );
        for (final String opening in _mitParagraphOpenings) {
          expect(
            countOccurrences(license, opening),
            1,
            reason: 'MIT 본문 단락 첫 문구가 정확히 한 번이어야 한다: $opening',
          );
        }

        // 본문은 단어 · 줄바꿈까지 원문 그대로다 — 첫 문구만 맞고 중간이 바뀐 경우를 잡는다.
        final String expectedHead = <String>[
          'MIT License',
          _copyrightLine,
          ..._mitParagraphs,
        ].join('\n\n');
        expect(
          license.startsWith('$expectedHead\n'),
          isTrue,
          reason: 'LICENSE 머리가 MIT 원문(GitHub 템플릿)과 글자 그대로 같아야 한다',
        );

        final int titleIndex = lines.indexOf(_thirdPartyTitle);
        expect(
          lines.where((String line) => line == _thirdPartyTitle).length,
          1,
          reason: '제3자 자산 절 제목 줄이 정확히 한 줄이어야 한다',
        );
        final int lastParagraphIndex = license.indexOf(
          _mitParagraphOpenings.last,
        );
        expect(
          license.indexOf(_thirdPartyTitle),
          greaterThan(lastParagraphIndex),
          reason: '제3자 자산 절은 MIT 본문 셋째 단락 뒤에 있어야 한다(본문 변형 금지)',
        );
        expect(titleIndex, greaterThan(0));
      },
    );

    test('T-174-ART-02: CHANGELOG = Keep a Changelog 한국어 · Unreleased 첫 절 · '
        '판 절 모양 · KIT_VERSION 일치', () {
      final String changelog = readTrackedFile(_changelogPath);
      final List<String> lines = changelog.split('\n');

      expect(lines.first, '# Changelog');
      expect(
        countOccurrences(changelog, 'keepachangelog.com/ko/1.1.0'),
        1,
        reason: 'Keep a Changelog 한국어판 1.1.0 링크가 정확히 한 번이어야 한다',
      );

      final List<String> sectionHeadings = linesStartingWith(changelog, '## ');
      // 양성 대조: 절이 하나도 없으면 아래 「첫 절」 단언이 공허해진다.
      expect(sectionHeadings, isNotEmpty);
      expect(sectionHeadings.first, '## [Unreleased]');
      expect(
        sectionHeadings
            .where((String line) => line == '## [Unreleased]')
            .length,
        1,
      );

      final List<String> releaseHeadings = sectionHeadings
          .where((String line) => line != '## [Unreleased]')
          .toList();
      for (final String heading in releaseHeadings) {
        expect(
          _releaseHeading.hasMatch(heading),
          isTrue,
          reason: '판 절 제목은 `## [x.y.z(-rc.N)] - YYYY-MM-DD` 모양이어야 한다: $heading',
        );
      }

      // 머리(첫 `## ` 앞)에는 `###` 헤딩을 두지 않는다 — 판 번호 규칙은 굵은 머리로 쓴다.
      final int firstSectionLine = lines.indexWhere(
        (String line) => line.startsWith('## '),
      );
      expect(
        lines
            .take(firstSectionLine)
            .where((String line) => line.startsWith('### '))
            .toList(),
        isEmpty,
        reason: 'CHANGELOG 머리에는 `###` 헤딩이 없어야 한다',
      );

      for (final String heading in sectionHeadings) {
        final List<String> typeHeadings = linesStartingWith(
          sliceMarkdownSection(changelog, heading, maxLevel: 2),
          '### ',
        ).map((String line) => line.substring(4)).toList();
        for (final String type in typeHeadings) {
          expect(
            _allowedChangeTypes.contains(type),
            isTrue,
            reason:
                '$heading 절의 `### $type` 은 허용 유형이 아니다: $_allowedChangeTypes',
          );
        }
        if (typeHeadings.contains('사용자 조치')) {
          expect(
            typeHeadings.first,
            '사용자 조치',
            reason: '$heading 절의 `### 사용자 조치` 는 그 절의 첫 `###` 이어야 한다',
          );
        }
      }

      final File kitVersionFile = File(_kitVersionPath);
      if (kitVersionFile.existsSync()) {
        final String raw = kitVersionFile.readAsStringSync();
        final RegExpMatch? match = _kitVersionContent.firstMatch(raw);
        expect(
          match,
          isNotNull,
          reason: 'KIT_VERSION 은 `v` 없는 semver 한 줄이어야 한다 — $_releaseCutRule',
        );
        final String version = match!.group(1)!;
        expect(
          releaseHeadings,
          isNotEmpty,
          reason: 'KIT_VERSION 이 있는데 판 절이 없다 — $_releaseCutRule',
        );
        expect(
          _releaseHeading.firstMatch(releaseHeadings.first)!.group(1),
          version,
          reason: '첫 판 절 번호가 KIT_VERSION 과 다르다 — $_releaseCutRule',
        );
        final String compareLine =
            '[Unreleased]: $_publicRepoUrl/compare/v$version...HEAD';
        final String tagLine =
            '[$version]: $_publicRepoUrl/releases/tag/v$version';
        for (final String link in <String>[compareLine, tagLine]) {
          expect(
            lines.where((String line) => line == link).length,
            1,
            reason: '링크 줄이 정확히 한 줄이어야 한다: $link — $_releaseCutRule',
          );
        }
      } else {
        expect(
          releaseHeadings,
          isEmpty,
          reason: 'KIT_VERSION 이 없는데 판 절이 있다 — $_releaseCutRule',
        );
      }
    });

    test('T-174-ART-03: tracked 자산 라이선스 파일 목록 == LICENSE 제3자 절 경로 목록', () {
      final ProcessResult result = Process.runSync(
        'git',
        <String>['ls-files', 'assets'],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      expect(
        result.exitCode,
        0,
        reason: 'git ls-files assets 실패 — git 이 PATH 에 없거나 저장소 밖에서 실행됐다.',
      );
      final RegExp licenseName = RegExp('licen|ofl', caseSensitive: false);
      final Set<String> tracked = (result.stdout as String)
          .split('\n')
          .where((String path) => path.isNotEmpty)
          .where(licenseName.hasMatch)
          .toSet();
      // 양성 대조: 목록이 비면 아래 집합 비교가 공허하게 참이 될 수 있다.
      expect(tracked, isNotEmpty);

      final String license = readTrackedFile(_licensePath);
      final int titleIndex = license.indexOf(_thirdPartyTitle);
      expect(titleIndex, isNot(-1), reason: 'LICENSE 에 제3자 자산 절이 없다');
      final List<String> listed = linesStartingWith(
        license.substring(titleIndex),
        '- ',
      ).map((String line) => line.substring(2).split(' ').first).toList();

      expect(listed.length, 10, reason: 'LICENSE 제3자 절은 10경로를 나열한다: $listed');
      expect(
        listed.toSet(),
        tracked,
        reason:
            'tracked 자산 라이선스 파일과 LICENSE 제3자 절 목록이 다르다 — 자산을 더하거나 '
            '뺐다면 LICENSE 도 같이 고친다',
      );
      for (final String path in listed) {
        expect(
          File(path).existsSync(),
          isTrue,
          reason: 'LICENSE 가 가리키는 파일이 없다: $path',
        );
      }
    });

    test(
      'T-174-ART-04: CONTRIBUTING · CHANGELOG 본문 금지 패턴 0 · CONTRIBUTING 필수 안내',
      () {
        // 양성 대조: 같은 정규식이 phase 번호와 planning 경로를 잡는다(리터럴은 조각으로).
        expect(_findForbidden('Phase 9'), isNotEmpty);
        expect(_findForbidden(<String>['.plan', 'ning'].join()), isNotEmpty);

        final String contributing = readTrackedFile(_contributingPath);
        final List<String> contributingHits = _findForbidden(contributing);
        expect(
          contributingHits,
          isEmpty,
          reason: 'CONTRIBUTING 에 금지 패턴이 있다: $contributingHits',
        );

        final String changelogBody = readTrackedFile(_changelogPath)
            .split('\n')
            .where((String line) => !_changelogExemptLine.hasMatch(line))
            .join('\n');
        expect(changelogBody.trim(), isNotEmpty);
        final List<String> changelogHits = _findForbidden(changelogBody);
        expect(
          changelogHits,
          isEmpty,
          reason: 'CHANGELOG 본문(판 제목 · 링크 줄 제외)에 금지 패턴이 있다: $changelogHits',
        );

        for (final String token in _contributingTokens) {
          expect(
            countOccurrences(contributing, token),
            greaterThanOrEqualTo(1),
            reason: 'CONTRIBUTING 에 `$token` 안내가 없다',
          );
        }
      },
    );
  });
}
