// 매뉴얼 「로그인 수단에서 이메일 받기」 계약 (quick 261011-c5c).
// 헤딩 · 목차 · 본문 순서 · 사용자 문서 금지 패턴 · provider 표 · 내부 링크 대상.
//
// 어디서 도는가: 매뉴얼(`docs/manual.md`) 내부 구조와 배포 함수 목록
// (`scripts/functions_manifest.json`)의 provider 이름만 읽는다. config · 콘솔 값 ·
// 버전 같은 값 대조가 없으므로 킷 사용자 저장소에서도 그대로 돈다.
//
// C5C-DOCS-01: 절 헤딩 1개 · 목차 블록 안 항목 1개 · 목차와 본문 모두 「킷 업데이트
//   반영」 바로 다음이다.
// C5C-DOCS-02: 절에 사용자 문서 금지 패턴(`.claude/rules/docs-user-manual.md` §4)과
//   연락 채널을 가정하는 단어가 0 건이고, `###` 소절이 절 템플릿 순서다.
// C5C-DOCS-03: provider 표의 첫 칸 집합이 배포 함수 목록의 provider 키 집합과 같다
//   (provider 마다 한 줄 · 중복 없음).
// C5C-DOCS-04: 절의 내부 링크(`](#…)`)가 모두 매뉴얼에 정확히 1개 있는 헤딩을
//   가리킨다.
// C5C-DOCS-05: 「로그인 수단 켜고 끄기」 「켜기」 ① 줄이 이 절을 링크 1개로
//   가리키고, 카카오계정 이메일을 비즈앱 의무 없음으로 적은 표 행이 매뉴얼에 없다.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/source_text.dart';

/// 매뉴얼 경로.
const String _manualPath = 'docs/manual.md';

/// 배포 함수 목록(provider 이름의 진실원).
const String _manifestPath = 'scripts/functions_manifest.json';

/// 절 헤딩 (정확히 한 줄).
const String _sectionHeading = '## 로그인 수단에서 이메일 받기';

/// 본문에서 이 절 바로 앞에 오는 `##` 헤딩.
const String _previousHeading = '## 킷 업데이트 반영';

/// 절 헤딩의 앵커(GitHub 헤딩 앵커 규칙을 적용한 값).
const String _sectionAnchor = '로그인-수단에서-이메일-받기';

/// 목차 항목 줄 (번호는 목차 위치에 따라 바뀌므로 정규식으로 본다).
final RegExp _tocEntryPattern = RegExp(
  r'^\d+\. \[로그인 수단에서 이메일 받기\]\(#로그인-수단에서-이메일-받기\)$',
);

/// 목차에서 이 절 바로 앞에 오는 항목 줄.
final RegExp _previousTocEntryPattern = RegExp(
  r'^\d+\. \[킷 업데이트 반영\]\(#킷-업데이트-반영\)$',
);

/// 절의 `###` 소절 — 절 템플릿(단계 · 확인 · 문제 해결 · 되돌리기) 순서.
const List<String> _subsectionHeadings = <String>[
  '### provider 별 설정',
  '### 확인 방법',
  '### 문제 해결',
  '### 되돌리기',
];

/// provider 표 헤더 줄.
const String _providerTableHeader = '| provider | 이메일을 필수로 받는 설정 | 할 일 |';

/// 킷에 없는 연락 채널을 가정하는 단어 — 이어 붙여야 단어가 된다(리터럴 0).
final List<String> _contactChannelWords = <String>[
  <String>['고객', '센터'].join(),
  <String>['문', '의'].join(),
];

/// 매뉴얼 내부 링크(`](#앵커)`)의 앵커를 잡는다.
final RegExp _internalLinkPattern = RegExp(r'\]\(#([^)\s]+)\)');

/// 앵커가 붙는 헤딩 줄(`##` ~ `####`).
final RegExp _headingLinePattern = RegExp(r'^#{2,4} ');

/// 헤딩을 앵커로 바꿀 때 지우는 문자 — 글자 · 숫자 · 결합 기호 · 하이픈 · 밑줄 ·
/// 공백이 아닌 것 전부.
final RegExp _anchorDroppedCharacters = RegExp(
  r'[^\p{L}\p{N}\p{M}\-_ ]',
  unicode: true,
);

/// 「로그인 수단 켜고 끄기」 절 헤딩 — 이 절로 오는 진입 문장이 있는 곳.
const String _providerOnOffHeading = '## 로그인 수단 켜고 끄기';

/// 「켜기」 ① 줄의 머리 — 그 절에서 정확히 한 줄이 이것으로 시작한다.
const String _consoleStepHead = '**① 콘솔 등록 · 키 발급.**';

/// 이 절을 가리키는 내부 링크 조각.
const String _sectionLink = '](#$_sectionAnchor)';

/// 카카오계정 이메일을 비즈앱 의무 없음(`X`)으로 적은 표 행 — 넷째 칸 값은 보지
/// 않는다.
final RegExp _kakaoEmailNoBizRowPattern = RegExp(
  r'^\| 카카오계정 이메일 \| `account_email` \| X \|',
  multiLine: true,
);

/// 헤딩 줄 [line] 을 GitHub 헤딩 앵커 규칙으로 바꾼다.
///
/// 줄 머리의 `#` 들과 공백을 떼고, 앞뒤 공백을 지우고, 소문자로 바꾸고,
/// [_anchorDroppedCharacters] 에 맞는 문자를 지운 뒤 공백을 하이픈으로 바꾼다.
/// 같은 헤딩이 여러 개일 때 GitHub 가 붙이는 숫자 꼬리(`-1` · `-2`)는 만들지
/// 않는다 — 호출자가 「그 앵커의 헤딩이 정확히 1개」 를 단언한다.
String _slugifyHeading(String line) => line
    .replaceFirst(RegExp(r'^#+\s*'), '')
    .trim()
    .toLowerCase()
    .replaceAll(_anchorDroppedCharacters, '')
    .replaceAll(' ', '-');

/// 매뉴얼 [manual] 의 헤딩 줄을 앵커로 바꿔 앵커마다 등장 횟수를 센다.
Map<String, int> _countHeadingAnchors(String manual) {
  final counts = <String, int>{};
  for (final String line in manual.split('\n')) {
    if (!_headingLinePattern.hasMatch(line)) {
      continue;
    }
    final String anchor = _slugifyHeading(line);
    counts[anchor] = (counts[anchor] ?? 0) + 1;
  }
  return counts;
}

void main() {
  final String manual = readTrackedFile(_manualPath);
  final String section = sliceMarkdownSection(
    manual,
    _sectionHeading,
    maxLevel: 2,
  );

  group('매뉴얼 「로그인 수단에서 이메일 받기」 계약 (C5C-DOCS)', () {
    test('C5C-DOCS-01: 절 헤딩 1개 · 목차 항목 1개 · 킷 업데이트 반영 다음이다', () {
      expect(
        countExactLines(manual, _sectionHeading),
        1,
        reason: '절 헤딩이 없거나 중복이다',
      );

      final List<String> tocLines = sliceTocBlock(manual).split('\n');
      final int tocIndex = tocLines.indexWhere(_tocEntryPattern.hasMatch);
      expect(
        tocLines.where(_tocEntryPattern.hasMatch).length,
        1,
        reason: '목차 블록 안 「로그인 수단에서 이메일 받기」 항목이 없거나 중복이다',
      );
      expect(
        _previousTocEntryPattern.hasMatch(
          tocIndex > 0 ? tocLines[tocIndex - 1] : '',
        ),
        isTrue,
        reason: '목차에서 이 항목이 「킷 업데이트 반영」 바로 다음이 아니다',
      );

      final List<String> bodyHeadings = linesStartingWith(manual, '## ');
      final int bodyIndex = bodyHeadings.indexOf(_sectionHeading);
      expect(
        bodyIndex > 0 ? bodyHeadings[bodyIndex - 1] : '',
        _previousHeading,
        reason: '본문에서 이 절이 「킷 업데이트 반영」 절 바로 다음이 아니다',
      );
    });

    test('C5C-DOCS-02: 금지 패턴 · 연락 채널 가정 단어 0 건 · 소절이 템플릿 순서다', () {
      expect(section.trim(), isNotEmpty, reason: '절 슬라이스가 비었다');

      final forbidden = RegExp(kUserDocForbiddenPatternSource);
      // 양성 대조: 금지 패턴 정규식이 실제로 phase 번호를 잡는다.
      expect(forbidden.hasMatch('Phase 9'), isTrue);
      final List<String> hits = forbidden
          .allMatches(section)
          .map((RegExpMatch m) => m.group(0)!)
          .toList();
      expect(hits, isEmpty, reason: '금지 패턴이 절에 있다: $hits');

      for (final String word in _contactChannelWords) {
        expect(
          countOccurrences(section, word),
          0,
          reason: '절이 연락 채널을 가정한다: $word',
        );
      }

      expect(
        linesStartingWith(section, '### '),
        _subsectionHeadings,
        reason: '절의 ### 소절이 템플릿 순서 4개와 다르다',
      );
    });

    test('C5C-DOCS-03: provider 표가 배포 함수 목록의 provider 마다 한 줄이다', () {
      final manifest =
          jsonDecode(readTrackedFile(_manifestPath)) as Map<String, Object?>;
      final List<String> providerKeys =
          (manifest['providers']! as Map<String, Object?>).keys.toList();
      // 양성 대조: 배포 함수 목록에서 provider 키를 실제로 읽었다.
      expect(providerKeys, isNotEmpty);

      // 표의 앞 2줄은 헤더 · 구분선이다.
      final List<String> rowProviders =
          collectTableLines(section, _providerTableHeader)
              .skip(2)
              .map((String row) => row.split('|')[1].trim().toLowerCase())
              .toList();
      expect(
        rowProviders.toSet(),
        hasLength(rowProviders.length),
        reason: 'provider 표에 같은 provider 가 두 줄 있다: $rowProviders',
      );
      expect(
        rowProviders.toSet(),
        providerKeys.toSet(),
        reason: 'provider 표의 provider 집합이 배포 함수 목록과 다르다',
      );
    });

    test('C5C-DOCS-04: 절의 내부 링크가 모두 정확히 1개 있는 헤딩을 가리킨다', () {
      // 양성 대조: 앵커 규칙이 구두점을 지우고 공백을 하이픈으로 바꾼다.
      expect(_slugifyHeading('### A — b (C 1.2) / d_e'), 'a--b-c-12--d_e');
      // 양성 대조: 절 헤딩이 절 앵커가 된다.
      expect(_slugifyHeading(_sectionHeading), _sectionAnchor);

      final List<String> anchors = _internalLinkPattern
          .allMatches(section)
          .map((RegExpMatch m) => m.group(1)!)
          .toList();
      expect(anchors, isNotEmpty, reason: '절에 내부 링크가 없다');

      final Map<String, int> headingAnchors = _countHeadingAnchors(manual);
      for (final anchor in anchors) {
        expect(
          headingAnchors[anchor] ?? 0,
          1,
          reason: '절의 링크 #$anchor 가 가리키는 헤딩이 없거나 중복이다',
        );
      }
    });

    test('C5C-DOCS-05: 「켜기」 ① 이 이 절을 가리키고 Kakao 이메일 행이 비즈앱 의무 없음 표에 없다', () {
      final String providerOnOff = sliceMarkdownSection(
        manual,
        _providerOnOffHeading,
        maxLevel: 2,
      );
      final List<String> consoleSteps = linesStartingWith(
        providerOnOff,
        _consoleStepHead,
      );
      expect(
        consoleSteps,
        hasLength(1),
        reason: '「로그인 수단 켜고 끄기」 절에 「켜기」 ① 줄이 없거나 중복이다',
      );
      expect(
        countOccurrences(consoleSteps.single, _sectionLink),
        1,
        reason: '「켜기」 ① 줄에 이 절로 가는 링크가 없거나 중복이다',
      );

      // 양성 대조: 정규식이 비즈앱 의무 없음으로 적은 이메일 표 행을 잡는다.
      expect(
        _kakaoEmailNoBizRowPattern.hasMatch(
          '| 카카오계정 이메일 | `account_email` | X | X |',
        ),
        isTrue,
      );
      expect(
        _kakaoEmailNoBizRowPattern.allMatches(manual).length,
        0,
        reason: '매뉴얼에 카카오계정 이메일을 비즈앱 의무 없음으로 적은 표 행이 있다',
      );
    });
  });
}
