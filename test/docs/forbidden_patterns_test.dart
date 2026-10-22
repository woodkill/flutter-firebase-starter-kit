// 사용자 문서 금지 패턴 계약 — 대상 수집 · 이름 붙인 패턴 · 파일별 0 건 · 다시 쓰기
// 목록.
//
// 어디서 도는가: 패턴 표본(DOCS-03)과 대상 규칙 표본(DOCS-05)은 어디서나 돈다. 대상
// 목록 · 파일별 0 건 · 다시 쓰기 목록 단언(DOCS-01 · 02 · 04)은 킷 사용자가 자기
// 문서를 고치거나 지우면 깨지는 내용 검사라, 비공개 작업 일지가 있는 유지보수자
// 트리에서만 돈다.
//
// T-21-DOCS-01: 대상이 필수 사용자 md 와 예시 파일 넷을 담고, 모두 실재하고, 22개
//   이상이다.
// T-21-DOCS-02: 다시 쓰기 목록 밖 대상 파일마다 하나 — 금지 패턴 0 건.
// T-21-DOCS-03: 패턴마다 조각으로 만든 표본을 잡고, 오탐 표본 · 예외 줄은 놓친다.
// T-21-DOCS-04: 다시 쓰기 목록의 파일은 대상이고 아직 금지 패턴이 1건 이상 있다.
// T-21-DOCS-05: 대상 규칙 함수 표본과, 수집 결과에 제외 규칙에 걸리는 경로가 없음.
//
// **표본 리터럴을 두지 않는다** — 금지 패턴에 맞는 표본은 조각을 이어 붙여 만든다.
// 이 파일도 공개 이력에 들어가 같은 규칙 · 스캔을 거친다.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/planning_docs.dart';
import '../helpers/source_text.dart';
import '../helpers/user_docs.dart';

/// 유지보수자 트리에서만 도는 내용 검사의 skip 값이다.
final Object _skipMaintainer = skipUnlessPlanningDocsExist(<String>[
  '.planning/ROADMAP.md',
]);

/// 대상 목록이 반드시 담아야 하는 사용자 md 다(예시 파일은 [kUserExampleFiles]).
const List<String> _requiredUserDocs = <String>[
  'README.md',
  'CHANGELOG.md',
  'CONTRIBUTING.md',
  'config/README.md',
  'test/README.md',
  'ios/Runner/Assets.xcassets/LaunchImage.imageset/README.md',
];

/// 대상 수의 하한 — 수집기가 빈 목록으로 공허하게 통과하지 않게 한다.
const int _minTargetCount = 22;

/// 사용자 문서로 고르는 경로 표본이다.
const List<String> _userDocSamples = <String>[
  'docs/setup.md',
  'assets/brand/kakao/README.md',
  '.github/ISSUE_TEMPLATE/x.md',
];

/// 사용자 문서로 고르지 않는 경로 표본이다.
const List<String> _nonUserDocSamples = <String>[
  '.planning/ROADMAP.md',
  '.claude/rules/x.md',
  'docs/maintainer/x.md',
  'functions/CLAUDE.md',
  'CLAUDE.md',
];

/// 표본을 검사할 때 쓰는 일반 사용자 문서 경로(예외 규칙이 없는 곳)다.
const String _plainDocPath = 'README.md';

/// 판 머리 날짜 예외가 있는 경로다.
const String _changelogPath = 'CHANGELOG.md';

/// 시험 ID 꼴을 검사하고 데모 지우는 법 소절 예외가 있는 가이드 경로다.
const String _guidePath = 'docs/guide.md';

/// 시험 ID 꼴을 검사하지만 소절 예외가 없는 가이드 경로다.
const String _setupPath = 'docs/setup.md';

/// 패턴 이름마다 그 패턴에 맞는 한 줄 표본 — 조각을 이어 붙여야 표본이 된다.
///
/// 금지 패턴 목록에 패턴을 더하면 여기에 표본 한 줄을 더한다(DOCS-03 이 목록과 이
/// 표의 이름 집합이 같은지 본다).
final Map<String, String> _positiveSamples = <String, String>{
  'phase-number': <String>['Pha', 'se 9 에서 바꿨다'].join(),
  'decision-id': <String>['결정 D', '-17 참고'].join(),
  'area-decision-id': <String>['D-LI', 'NE-08 기준'].join(),
  'review-id': <String>['리뷰 W', 'R-01 반영'].join(),
  'planning-doc-name': <String>['17', '-CONTEXT 참고'].join(),
  'planning-path': <String>['`.plan', 'ning/todos/x.md`'].join(),
  'quick-id': <String>['quick ', '260924 작업'].join(),
  'session-id': <String>['260924', '-lw2 세션'].join(),
  'commit-hash': <String>['커밋 c890', '3f6a 에서'].join(),
  'uat-word': <String>['UA', 'T PASS'].join(),
  'measured-word': <String>['실', '측 결과'].join(),
  'reproduced-word': <String>['재현', '됐다'].join(),
  'memory-word': <String>['mem', 'ory 참조'].join(),
  'memory-name': <String>['`feedback_', 'doc_sync`'].join(),
  'gsd-command': <String>['/gs', 'd-plan-phase'].join(),
  'date': <String>['20', '26-09-24 부터'].join(),
  'roadmap-reference': <String>['(see ROAD', 'MAP.md)'].join(),
  'history-heading': <String>['## 옛 절 (DEPRE', 'CATED)'].join(),
  'label-slot': <String>['[[LA', 'BEL: 콘솔 — 칸]]'].join(),
};

/// 시험 ID 꼴 표본 — 조각을 이어 붙여야 시험 ID 가 된다.
String _buildTestIdSample(String area) =>
    <String>['T-', '172', '-', area, '-01'].join();

/// [path] · [text] 의 위반에서 패턴 이름만 모은다.
Set<String> _collectHitNames(String path, String text) =>
    findForbiddenPatternHits(
      path,
      text,
    ).map((String hit) => hit.split(' — ').last).toSet();

void main() {
  final List<String> targets = collectUserDocTargets();

  group('대상 수집', () {
    test('T-21-DOCS-01: 대상 = 규칙으로 고른 사용자 md + 예시 파일 4개', () {
      for (final path in <String>[..._requiredUserDocs, ...kUserExampleFiles]) {
        expect(targets, contains(path), reason: '대상에 없다: $path');
        expect(File(path).existsSync(), isTrue, reason: '파일이 없다: $path');
      }
      final List<String> missing = targets
          .where((String path) => !File(path).existsSync())
          .toList();
      expect(missing, isEmpty, reason: '대상인데 파일이 없다');
      expect(targets.length, greaterThanOrEqualTo(_minTargetCount));
    }, skip: _skipMaintainer);

    test('T-21-DOCS-05: 대상 규칙 표본(isUserDocPath)', () {
      for (final String path in _userDocSamples) {
        expect(isUserDocPath(path), isTrue, reason: '대상이어야 한다: $path');
      }
      for (final String path in _nonUserDocSamples) {
        expect(isUserDocPath(path), isFalse, reason: '대상이 아니어야 한다: $path');
      }
      // 양성 대조: 수집 결과가 비지 않는다.
      expect(targets, isNotEmpty, reason: '대상 수집 결과가 비었다');
      final List<String> excluded = targets
          .where(
            (String path) =>
                kUserDocExcludedPrefixes.any(path.startsWith) ||
                path.split('/').last == kClaudeInstructionFileName,
          )
          .toList();
      expect(excluded, isEmpty, reason: '제외 규칙에 걸리는 경로가 대상에 있다');
    });
  });

  group('파일별 금지 패턴', () {
    for (final String path in targets.where(
      (String path) => !kDocsAwaitingRewrite.contains(path),
    )) {
      test('T-21-DOCS-02: 금지 패턴 0 — $path', () {
        final List<String> hits = findForbiddenPatternHits(
          path,
          readTrackedFile(path),
        );
        // 결과 한 줄 — 여러 파일을 함께 돌려도 시험 로그에 이 시험 이름이 남는다.
        debugPrintSynchronously('금지 패턴 $path: 위반 ${hits.length}건');
        expect(hits, isEmpty, reason: '금지 패턴이 남았다(파일:줄 — 패턴 이름)');
      }, skip: _skipMaintainer);
    }
  });

  group('패턴 표본', () {
    test('T-21-DOCS-03: 패턴마다 조각 표본을 잡고 오탐 표본은 놓친다', () {
      // 목록의 이름이 겹치지 않고, 이름마다 표본이 하나씩 있다.
      final List<String> names = kUserDocForbiddenPatterns
          .map((NamedPattern named) => named.name)
          .toList();
      expect(names.toSet().length, names.length, reason: '패턴 이름이 겹친다');
      expect(names.length, greaterThanOrEqualTo(18));
      expect(names.toSet(), _positiveSamples.keys.toSet());

      // 패턴마다 자기 표본을 잡는다.
      for (final MapEntry<String, String> sample in _positiveSamples.entries) {
        expect(
          findForbiddenPatternHits(_plainDocPath, sample.value),
          contains('$_plainDocPath:1 — ${sample.key}'),
          reason: '패턴 ${sample.key} 가 자기 표본을 놓쳤다',
        );
      }

      // commit-hash: 숫자만 · a-f 없는 채움 값 · 64자 지문은 놓치고, 해시는 잡는다.
      for (final miss in <String>[
        '--default-background-color=00000000',
        <String>['M15.709', '9491,14.8846154'].join(),
        '0123456789abcdef' * 4,
      ]) {
        expect(
          _collectHitNames(_plainDocPath, miss),
          isNot(contains('commit-hash')),
          reason: 'commit-hash 오탐 표본을 잡았다',
        );
      }

      // memory-name: 조각 둘 이상은 잡고, 설정 키는 놓친다.
      expect(
        _collectHitNames(
          _plainDocPath,
          <String>['project_', 'firebase_dev_only'].join(),
        ),
        contains('memory-name'),
      );
      for (final key in <String>['project_number', 'project_id']) {
        expect(
          _collectHitNames(_plainDocPath, '`$key` 값을 넣는다'),
          isEmpty,
          reason: '설정 키 $key 를 금지 패턴으로 잡았다',
        );
      }

      // history-heading: 제목 줄만 잡는다(대소문자 무시) · 본문 줄은 놓친다.
      expect(
        _collectHitNames(
          _plainDocPath,
          <String>['### 고친 절 (hot', 'fix)'].join(),
        ),
        contains('history-heading'),
      );
      expect(
        _collectHitNames(
          _plainDocPath,
          <String>['본문의 DEPRE', 'CATED 경고'].join(),
        ),
        isNot(contains('history-heading')),
      );

      // CHANGELOG 판 머리 줄의 날짜는 위반이 아니고, 본문 줄 · 다른 파일은 위반이다.
      final String releaseHeading = <String>[
        '## [1.0.0-rc.3] - ',
        '20',
        '26-10-12',
      ].join();
      final String datedBody = <String>['- 20', '26-10-12 에 바꿨다'].join();
      expect(findForbiddenPatternHits(_changelogPath, releaseHeading), isEmpty);
      expect(
        findForbiddenPatternHits(_changelogPath, datedBody),
        contains('$_changelogPath:1 — date'),
      );
      expect(
        _collectHitNames(_plainDocPath, releaseHeading),
        contains('date'),
        reason: '판 머리 예외는 CHANGELOG 에만 있다',
      );

      // test-id: 두 가이드에서만 잡고, 사용 가이드의 데모 지우는 법 소절(시작 줄부터
      // 다음 제목 줄 앞까지)에서는 시험 ID 꼴만 놓친다.
      final outside = '본문의 ${_buildTestIdSample('HOME')} 인용';
      final inside = '- `home_test.dart` 의 ${_buildTestIdSample('ROUTER')}';
      final String datedInside = <String>['  - 20', '26-10-12 에 지웠다'].join();
      final String guide = <String>[
        '## 홈 화면 바꾸기',
        outside,
        kDemoRemovalStartLine,
        inside,
        '```bash',
        '# 펜스 안의 셸 주석은 제목이 아니다',
        '```',
        inside,
        datedInside,
        '### 다음 소절',
        inside,
      ].join('\n');

      expect(findForbiddenPatternHits(_guidePath, guide), <String>[
        '$_guidePath:2 — test-id',
        '$_guidePath:9 — date',
        '$_guidePath:11 — test-id',
      ], reason: '소절 밖 시험 ID 와 소절 안의 다른 패턴만 잡아야 한다');
      // 소절 예외가 없는 가이드는 시험 ID 줄을 모두 잡는다.
      final List<String> setupHits = findForbiddenPatternHits(
        _setupPath,
        guide,
      ).where((String hit) => hit.endsWith(' — test-id')).toList();
      expect(setupHits, hasLength(4));
      // 가이드가 아닌 사용자 문서는 시험 ID 를 잡지 않는다.
      expect(
        _collectHitNames(_changelogPath, guide),
        isNot(contains('test-id')),
      );
    });
  });

  group('다시 쓰기 목록', () {
    test('T-21-DOCS-04: 다시 쓰기 목록의 파일은 대상이고 아직 금지 패턴이 있다', () {
      for (final String path in kDocsAwaitingRewrite) {
        expect(targets, contains(path), reason: '목록의 파일이 대상이 아니다: $path');
        expect(
          findForbiddenPatternHits(path, readTrackedFile(path)),
          isNotEmpty,
          reason: '$path 에 금지 패턴이 없다 — 다시 쓴 파일은 목록에서 뺀다',
        );
      }
    }, skip: _skipMaintainer);
  });
}
