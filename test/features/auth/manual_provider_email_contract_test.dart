// 설정 문서(`docs/setup.md`) 「로그인 수단에서 이메일 받기」 계약.
// 헤딩 · 절 위치 · 사용자 문서 금지 패턴 · provider 표 · 내부 링크 대상.
//
// 어디서 도는가: setup.md 의 절 순서 · 문장과 배포 함수 목록
// (`scripts/functions_manifest.json`)의 provider 이름을 읽는다. 절 순서 · 문장은 킷
// 사용자가 자기 문서에서 고칠 수 있으므로 유지보수자 트리에서만 돈다 — 비공개 작업
// 일지가 없는 트리(공개본 · 킷 사용자 저장소)에서는 최상위 group 이 건너뛰어진다.
//
// C5C-DOCS-01: 절 헤딩 1개 · 「로그인 수단 켜기」 절의 마지막 `###` 소절이고, 그
//   다음 `##` 절이 「알림(APNs) · App Check」 이다.
// C5C-DOCS-02: 절에 사용자 문서 금지 패턴(`.claude/rules/docs-user-manual.md` §4)과
//   연락 채널을 가정하는 단어가 0 건이고, `####` 소절이 절 템플릿 순서다.
// C5C-DOCS-03: provider 표의 첫 칸 집합이 배포 함수 목록의 provider 키 집합과 같다
//   (provider 마다 한 줄 · 중복 없음).
// C5C-DOCS-04: 절의 내부 링크(`](#…)`)가 모두 setup.md 에 정확히 1개 있는 헤딩을
//   가리킨다(앵커는 GitHub 렌더 규칙 — 공용 앵커 헬퍼).
// C5C-DOCS-05: Kakao · Naver · Facebook 켜기 절이 이 절을 링크로 가리키고,
//   카카오계정 이메일을 비즈앱 의무 없음으로 적은 표 행이 두 가이드에 없다.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/markdown_anchor.dart';
import '../../helpers/planning_docs.dart';
import '../../helpers/source_text.dart';

/// 설정 문서 경로 — 이 절과 「로그인 수단 켜기」 절이 있다.
const String _setupPath = 'docs/setup.md';

/// 직접 하는 일 문서 경로 — 부재 단언(비즈앱 의무 없음 행)의 대상에 함께 든다.
const String _guidePath = 'docs/guide.md';

/// 배포 함수 목록(provider 이름의 진실원).
const String _manifestPath = 'scripts/functions_manifest.json';

/// 절 헤딩 (정확히 한 줄).
const String _sectionHeading = '### 로그인 수단에서 이메일 받기';

/// 이 절을 소절로 담는 「로그인 수단 켜기」 절 헤딩.
const String _providerOnHeading = '## 로그인 수단 켜기';

/// 이 절 다음에 오는 `##` 헤딩.
const String _nextHeading = '## 알림(APNs) · App Check';

/// 절 헤딩의 앵커(GitHub 헤딩 앵커 규칙을 적용한 값).
const String _sectionAnchor = '로그인-수단에서-이메일-받기';

/// 절의 `####` 소절 — 절 템플릿(단계 · 확인 · 문제 해결 · 되돌리기) 순서.
const List<String> _subsectionHeadings = <String>[
  '#### provider 별 설정',
  '#### 확인 방법',
  '#### 문제 해결',
  '#### 되돌리기',
];

/// provider 표 헤더 줄.
const String _providerTableHeader = '| provider | 이메일을 필수로 받는 설정 | 할 일 |';

/// 킷에 없는 연락 채널을 가정하는 단어 — 이어 붙여야 단어가 된다(리터럴 0).
final List<String> _contactChannelWords = <String>[
  <String>['고객', '센터'].join(),
  <String>['문', '의'].join(),
];

/// 문서 내부 링크(`](#앵커)`)의 앵커를 잡는다.
final RegExp _internalLinkPattern = RegExp(r'\]\(#([^)\s]+)\)');

/// 이 절을 가리켜야 하는 수단별 켜기 절 헤딩 — 이메일 받기 설정이 필요한 수단이다.
const List<String> _linkingProviderHeadings = <String>[
  '### Kakao 로그인 켜기',
  '### Naver 로그인 켜기',
  '### Facebook 로그인 켜기',
];

/// 이 절을 가리키는 내부 링크 조각.
const String _sectionLink = '](#$_sectionAnchor)';

/// 카카오계정 이메일을 비즈앱 의무 없음(`X`)으로 적은 표 행 — 넷째 칸 값은 보지
/// 않는다.
final RegExp _kakaoEmailNoBizRowPattern = RegExp(
  r'^\| 카카오계정 이메일 \| `account_email` \| X \|',
  multiLine: true,
);

void main() {
  final String setup = readTrackedFile(_setupPath);
  final String section = sliceMarkdownSection(
    setup,
    _sectionHeading,
    maxLevel: 3,
  );

  group('설정 문서 「로그인 수단에서 이메일 받기」 계약 (C5C-DOCS)', () {
    test('C5C-DOCS-01: 절 헤딩 1개 · 로그인 수단 켜기 절의 마지막 소절 · 다음 절이 알림이다', () {
      expect(
        countExactLines(setup, _sectionHeading),
        1,
        reason: '절 헤딩이 없거나 중복이다',
      );

      final String providerOn = sliceMarkdownSection(
        setup,
        _providerOnHeading,
        maxLevel: 2,
      );
      final List<String> subsections = linesStartingWith(providerOn, '### ');
      expect(subsections, isNotEmpty, reason: '「로그인 수단 켜기」 절의 ### 소절을 찾지 못했다');
      expect(
        subsections.last,
        _sectionHeading,
        reason: '이 절이 「로그인 수단 켜기」 절의 마지막 ### 소절이 아니다',
      );

      final List<String> lines = setup.split('\n');
      final int headingIndex = lines.indexOf(_sectionHeading);
      expect(headingIndex, greaterThanOrEqualTo(0));
      final String nextLevelTwo = lines
          .skip(headingIndex + 1)
          .firstWhere(
            (String line) => line.startsWith('## '),
            orElse: () => '',
          );
      expect(
        nextLevelTwo,
        _nextHeading,
        reason: '이 절 다음 ## 절이 「알림(APNs) · App Check」 가 아니다',
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
        linesStartingWith(section, '#### '),
        _subsectionHeadings,
        reason: '절의 #### 소절이 템플릿 순서 4개와 다르다',
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
      expect(buildGithubAnchor('A — b (C 1.2) / d_e'), 'a--b-c-12--d_e');
      // 양성 대조: 절 헤딩 텍스트가 절 앵커가 된다.
      expect(buildGithubAnchor('로그인 수단에서 이메일 받기'), _sectionAnchor);

      final List<String> anchors = _internalLinkPattern
          .allMatches(section)
          .map((RegExpMatch m) => m.group(1)!)
          .toList();
      expect(anchors, isNotEmpty, reason: '절에 내부 링크가 없다');

      // 같은 앵커의 헤딩이 둘이면 둘째가 `-1` 꼬리를 받는다 — 꼬리 앵커가 없어야
      // 헤딩이 정확히 1개다.
      final Set<String> headingAnchors = collectHeadingAnchors(setup);
      for (final anchor in anchors) {
        expect(
          headingAnchors.contains(anchor),
          isTrue,
          reason: '절의 링크 #$anchor 가 가리키는 헤딩이 없다',
        );
        expect(
          headingAnchors.contains('$anchor-1'),
          isFalse,
          reason: '절의 링크 #$anchor 가 가리키는 헤딩이 둘 이상이다',
        );
      }
    });

    test('C5C-DOCS-05: 수단별 켜기 절이 이 절을 가리키고 Kakao 이메일 행이 비즈앱 의무 없음 표에 없다', () {
      for (final String heading in _linkingProviderHeadings) {
        final String providerSection = sliceMarkdownSection(
          setup,
          heading,
          maxLevel: 3,
        );
        expect(
          providerSection.trim(),
          isNotEmpty,
          reason: '「$heading」 절을 찾지 못했다',
        );
        expect(
          countOccurrences(providerSection, _sectionLink),
          greaterThanOrEqualTo(1),
          reason: '「$heading」 절에 이 절로 가는 링크가 없다',
        );
      }

      // 양성 대조: 정규식이 비즈앱 의무 없음으로 적은 이메일 표 행을 잡는다.
      expect(
        _kakaoEmailNoBizRowPattern.hasMatch(
          '| 카카오계정 이메일 | `account_email` | X | X |',
        ),
        isTrue,
      );
      final String guide = readTrackedFile(_guidePath);
      expect(
        _kakaoEmailNoBizRowPattern.allMatches('$setup\n$guide').length,
        0,
        reason: '두 가이드에 카카오계정 이메일을 비즈앱 의무 없음으로 적은 표 행이 있다',
      );
    });
  }, skip: skipUnlessPlanningDocsExist(const <String>['.planning/ROADMAP.md']));
}
