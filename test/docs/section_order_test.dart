// 사용자 문서 절 템플릿 순서 계약.
//
// 절 하나의 바로 아래 단계 소절 가운데 이름이 템플릿 표지(언제 필요한가 · 전제 · 단계
// · 확인 방법 · 문제 해결 · 되돌리기)인 것은 이 순서를 거스르지 않는다
// (`.claude/rules/docs-user-manual.md` §5). 없는 표지는 건너뛰어도 되고 같은 표지가
// 이어서 나와도 된다.
//
// 어디서 도는가: 순서 검사 함수 표본(ORDER-01)은 어디서나 돈다. 파일별 순서 검사
// (ORDER-02)는 킷 사용자가 자기 문서를 고치면 깨지는 내용 검사라 비공개 작업 일지가
// 있는 유지보수자 트리에서만 돈다.
//
// T-21-ORDER-01: 순서 검사 함수의 양성 · 음성 표본.
// T-21-ORDER-02: 대상 md 마다 하나 — 순서 위반 0.
// T-21-ORDER-03: 두 가이드에서 바로 아래 표지 소절이 둘 이상인 절이 10개 이상이다 —
//   순서 검사가 공허하지 않다(유지보수자 트리 전용).

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/planning_docs.dart';
import '../helpers/source_text.dart';
import '../helpers/user_docs.dart';

/// 유지보수자 트리에서만 도는 내용 검사의 skip 값이다.
final Object _skipMaintainer = skipUnlessMaintainerTree();

/// 절 템플릿 표지 이름 — 소절은 이 순서를 지킨다.
const List<String> _templateLabels = <String>[
  '언제 필요한가',
  '전제',
  '단계',
  '확인 방법',
  '문제 해결',
  '되돌리기',
];

/// 표지 소절이 둘 이상인 절을 세는 문서 — 두 가이드다.
const List<String> _guidePaths = <String>['docs/setup.md', 'docs/guide.md'];

/// 두 가이드에서 표지 소절이 둘 이상인 절의 최소 개수다.
const int _minLabeledSections = 10;

/// 마크다운 제목 줄(`#` 1 ~ 6개 뒤 공백)과 그 텍스트다.
final RegExp _headingLine = RegExp(r'^(#{1,6}) (.*)$');

/// 아직 닫히지 않은 제목 — 그 바로 아래 소절에서 지금까지 본 가장 뒤 표지를 든다.
class _OpenHeading {
  _OpenHeading(this.level);

  /// 제목 단계(`#` 개수 · 문서 머리는 0)다.
  final int level;

  /// 바로 아래 소절에서 본 가장 뒤 표지의 순번이다(없으면 -1).
  int lastLabelIndex = -1;

  /// 바로 아래 소절 가운데 이름이 표지인 것의 개수다.
  int labelCount = 0;
}

/// 제목 하나를 만난 자리 — 줄 순번 · 제목 텍스트 · 가장 가까운 상위 제목이다.
class _HeadingVisit {
  _HeadingVisit(this.lineIndex, this.title, this.parent);

  /// 제목 줄의 순번(0부터)이다.
  final int lineIndex;

  /// 제목 텍스트다.
  final String title;

  /// 가장 가까운 상위 제목이다(없으면 문서 머리).
  final _OpenHeading parent;
}

/// 마크다운 [markdown] 의 제목을 차례로 돌려준다 — 코드 펜스 안의 `#` 줄은 제목이
/// 아니다.
Iterable<_HeadingVisit> _visitHeadings(String markdown) sync* {
  final open = <_OpenHeading>[_OpenHeading(0)];
  final List<String> lines = markdown.split('\n');
  var inFence = false;
  for (var i = 0; i < lines.length; i++) {
    final String line = lines[i];
    if (line.trimLeft().startsWith('```')) {
      inFence = !inFence;
      continue;
    }
    final RegExpMatch? match = inFence ? null : _headingLine.firstMatch(line);
    if (match == null) {
      continue;
    }
    final int level = match.group(1)!.length;
    while (open.last.level >= level) {
      open.removeLast();
    }
    yield _HeadingVisit(i, match.group(2)!.trim(), open.last);
    open.add(_OpenHeading(level));
  }
}

/// 마크다운 [markdown] 에서 절 템플릿 순서를 거스르는 소절을 `'<줄>: <표지>'`
/// 목록으로 돌려준다.
///
/// 제목마다 바로 아래 단계 소절(그 제목을 가장 가까운 상위 제목으로 둔 소절) 가운데
/// 이름이 표지인 것만 보고, 앞에서 본 표지보다 앞 순번의 표지가 나오면 위반이다. 같은
/// 표지가 이어지는 것과 표지가 아닌 소절이 끼는 것은 허용한다. 코드 펜스 안의 `#`
/// 줄은 제목이 아니다.
List<String> findTemplateOrderViolations(String markdown) {
  final violations = <String>[];
  for (final _HeadingVisit visit in _visitHeadings(markdown)) {
    final int labelIndex = _templateLabels.indexOf(visit.title);
    if (labelIndex == -1) {
      continue;
    }
    if (labelIndex < visit.parent.lastLabelIndex) {
      violations.add('${visit.lineIndex + 1}: ${visit.title}');
    } else {
      visit.parent.lastLabelIndex = labelIndex;
    }
  }
  return violations;
}

/// 마크다운 [markdown] 에서 바로 아래 소절 가운데 이름이 표지인 것이 둘 이상인 제목의
/// 개수를 센다.
///
/// 제목 트리는 [findTemplateOrderViolations] 와 같다(가장 가까운 상위 제목이 부모 ·
/// 코드 펜스 안의 `#` 줄 제외). 문서 머리 바로 아래 표지도 문서 머리 하나로 센다.
int countSectionsWithTemplateLabels(String markdown) {
  var count = 0;
  for (final _HeadingVisit visit in _visitHeadings(markdown)) {
    if (!_templateLabels.contains(visit.title)) {
      continue;
    }
    visit.parent.labelCount++;
    if (visit.parent.labelCount == 2) {
      count++;
    }
  }
  return count;
}

void main() {
  test('T-21-ORDER-01: 순서 검사 함수 표본', () {
    // 순서를 지킨 절 — 표지를 건너뛰어도 되고 표지가 아닌 소절이 끼어도 된다.
    expect(
      findTemplateOrderViolations(
        <String>[
          '## Kakao 로그인 켜기',
          '### 언제 필요한가',
          '### 단계',
          '### 참고',
          '### 확인 방법',
          '### 되돌리기',
        ].join('\n'),
      ),
      isEmpty,
    );

    // `되돌리기` 뒤의 `확인 방법` 은 위반 하나다.
    expect(
      findTemplateOrderViolations(
        <String>['## 알림 켜기', '### 단계', '### 되돌리기', '### 확인 방법'].join('\n'),
      ),
      hasLength(1),
    );

    // 손자 단계의 표지는 부모 절의 순서에 들지 않는다 · 같은 표지가 이어져도 된다.
    expect(
      findTemplateOrderViolations(
        <String>[
          '## 빌드',
          '### 단계',
          '#### 되돌리기',
          '### 단계',
          '### 확인 방법',
          '## 배포',
          '### 되돌리기',
        ].join('\n'),
      ),
      isEmpty,
    );

    // 코드 펜스 안의 `#` 줄(셸 주석)은 제목이 아니다.
    expect(
      findTemplateOrderViolations(
        <String>[
          '## 설정',
          '### 문제 해결',
          '```bash',
          '### 확인 방법',
          '# 단계',
          '```',
          '### 되돌리기',
        ].join('\n'),
      ),
      isEmpty,
    );
  });

  group('파일별 절 순서', () {
    for (final String path in collectUserDocTargets().where(
      (String path) => path.endsWith('.md'),
    )) {
      test('T-21-ORDER-02: 절 템플릿 순서 — $path', () {
        final List<String> violations = findTemplateOrderViolations(
          readTrackedFile(path),
        );
        // 결과 한 줄 — 여러 파일을 함께 돌려도 시험 로그에 이 시험 이름이 남는다.
        debugPrintSynchronously('절 템플릿 순서 $path: 위반 ${violations.length}건');
        expect(violations, isEmpty, reason: '절 템플릿 순서를 거스르는 소절이 있다');
      }, skip: _skipMaintainer);
    }
  });

  test('T-21-ORDER-03: 두 가이드에 표지 소절 둘 이상인 절이 10개 이상', () {
    // 표본: 표지 둘 이상인 절만 세고, 손자 단계 표지 · 펜스 안 줄은 부모에 들지 않는다.
    expect(
      countSectionsWithTemplateLabels(
        <String>[
          '## 알림 켜기',
          '### 언제 필요한가',
          '### 단계',
          '#### 확인 방법',
          '#### 되돌리기',
          '## 빌드',
          '### 단계',
          '```bash',
          '### 되돌리기',
          '```',
          '### 참고',
        ].join('\n'),
      ),
      2,
    );

    final counts = <String, int>{
      for (final path in _guidePaths)
        path: countSectionsWithTemplateLabels(readTrackedFile(path)),
    };
    final int total = counts.values.fold(0, (int sum, int n) => sum + n);
    // 결과 한 줄 — 여러 파일을 함께 돌려도 시험 로그에 이 시험 이름이 남는다.
    debugPrintSynchronously('표지 소절 둘 이상인 절: $counts · 합 $total');
    expect(
      total,
      greaterThanOrEqualTo(_minLabeledSections),
      reason: '표지 소절이 둘 이상인 절이 적다 — 순서 검사가 공허하다',
    );
  }, skip: _skipMaintainer);
}
