// Phase 17.2 성공 기준 4 (문서 부분) — docs/guide.md 의 홈 하위 중첩 안내 계약.
// (FIRE-01 · Nyquist gap-fill · Plan 17.2-04 Task 1/2 의 `<automated>` shell grep 대체)
//
// 가이드(docs/guide.md)의 동작 서술과 회귀 가드 지도
// (docs/maintainer/regression-guards.md)의 시험 ID 인용을 반복 실행 가능한
// test 로 고정해 bullet 삭제 · 헤딩 이름 변경 · 메시지 어긋남 · 끊어진 test ID
// 포인터를 막는다. 각 슬라이스는 양성 대조(비어 있지 않고 자기 헤딩을 담는다)를
// 함께 세워 빈 슬라이스가 공허하게 통과하지 못하게 한다.
//
// T-172-DOCS-01: 「FCM 알림」 결과 스택 bullet (홈 → (설정) → 대상) · 지도의 T-172-STACK-01.
// T-172-DOCS-02: 「바꿀 수 있는 지점」 표 「알림 탭으로 열 화면」 행 1개 · 지도의 ID.
// T-172-DOCS-03: ④ 의 실패 메시지가 T-172-ROUTER-01 의 실제 메시지와 같다.
// T-172-DOCS-04(GA4 안내)는 지웠다 — 가이드에 그 안내가 없다.
// T-172-DOCS-05: ② 의 6번째 배선(routes:) · 지도의 T-172-ROUTER-01.
// T-172-DOCS-06: 회귀 가드 지도 · 코드 주석이 인용한 test ID 가 실제 test 이름이다
//   (범위 표기 `T-…-XXX-NN~MM` 은 펼쳐서 모두 본다).
// T-172-DOCS-07: ③ 의 데모 위치(설정 하위 조각) · 지우는 법 토큰.
//
// 킷 사용자 안전 규칙(가이드 절차가 이 파일을 건드리지 않게):
// - 옛 홈 파일 · 클래스 이름은 쓰지 않는다(② 의 이름 바꾸기 grep).
// - 경로 개수는 하드코딩하지 않는다(④ 가 route 를 더해도 깨지지 않게).
// - ③ 데모 상수 이름은 리터럴 없이 조각을 이어 만든다(③ 4단계 끝의 grep 0 건).
// - 예외: 가이드에서 ③ 절 자체를 지울 때는 T-172-DOCS-07 과 그 전용 선언 ·
//   ③ 을 가리키는 주석을 함께 지운다(③ 「지우는 법」 4단계). ③ 을 남기면 그대로 둔다.

import 'dart:io';

import 'package:flutter_starter_kit/features/notifications/application/notification_route.dart'
    show kNotificationRoutableRoutes;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/route_tree.dart' show describeRouteNotUnderHome;
import '../../helpers/source_text.dart';

/// 사용 가이드 경로.
const String _guidePath = 'docs/guide.md';

/// 회귀 가드 지도(유지보수자 문서) 경로 — 동작을 지키는 시험 ID 를 인용한다.
const String _guardsPath = 'docs/maintainer/regression-guards.md';

/// 알림 허용 목록 코드 파일 — 주석이 T-172-ROUTER-01 을 인용한다.
const String _notificationRoutePath =
    'lib/features/notifications/application/notification_route.dart';

/// 구조 불변식 test 파일 — 지도가 T-172-STACK-01 · LISTENER-01 · ROUTER-01 을 인용한다.
const String _nestingTestPath = 'test/core/router/app_router_nesting_test.dart';

/// 허용 목록 test 파일 — 지도가 T-17-PUSH-01 을 인용한다.
const String _notificationRouteTestPath =
    'test/features/notifications/application/notification_route_test.dart';

/// 결과 스택 bullet 의 시작.
const String _stackBulletPrefix = '- **결과 스택:**';

/// 「바꿀 수 있는 지점」 표 행의 시작.
const String _customizationRowPrefix = '| 알림 탭으로 열 화면 |';

/// 「홈 화면 바꾸기」 하위 헤딩들.
const String _replaceHeading = '### ② 화면을 통째로 바꿀 때 — 옮길 배선 체크리스트';
const String _demoHeading = '### ③ 데모 화면 — 위치 · 노출 조건 · 지우는 법';
const String _allowlistHeading = '### ④ 알림 탭으로 열 화면 — 허용 목록';

/// 데모 상수 이름 조각 — 이어 붙여야 이름이 된다(리터럴 0).
const List<String> _demoSegmentParts = <String>[
  'AppRoutes.',
  'developer',
  'Demo',
  'Segment',
];

/// 가이드에서 [heading] 줄부터 다음 `## ` · `### ` 헤딩 직전까지를 돌려준다.
///
/// 자르기 규칙은 `test/helpers/source_text.dart` 의 [sliceMarkdownSection] 한
/// 곳에 있다 — 이 파일은 `### ` 하위 절을 자르므로 경계 수준 3 을 쓴다.
String _sliceFromHeading(String guide, String heading) =>
    sliceMarkdownSection(guide, heading, maxLevel: 3);

/// [text] 안에서 [idPattern] 에 맞는 시험 ID 와 범위 표기 `…-NN~MM` 을 개별
/// ID 로 펼쳐 중복 없이 모은다.
///
/// [idPattern] 은 그룹 1 = ID 의 숫자 앞 접두(`T-172-ROUTER-` 꼴), 그룹 2 =
/// 두 자리 번호, 그룹 3 = 범위 끝 번호(선택)를 잡아야 한다. 범위 표기(예:
/// `T-172-ROUTES-01~03`)는 01 · 02 · 03 을 모두 인용한 것으로 본다 — 첫 ID 만
/// 뽑으면 02 · 03 의 이름이 바뀌어도 포인터 검사가 통과한다. 역순 범위(`NN~MM`
/// 에서 MM < NN)는 문서 오타로 보고 test 를 실패시킨다 — 그대로 펼치면 ID 를
/// 하나도 모으지 않아 검사가 조용히 빈다.
Set<String> _collectIds(String text, RegExp idPattern) {
  final ids = <String>{};
  for (final RegExpMatch match in idPattern.allMatches(text)) {
    final String prefix = match.group(1)!;
    final int first = int.parse(match.group(2)!);
    final int last = int.parse(match.group(3) ?? match.group(2)!);
    expect(
      last >= first,
      isTrue,
      reason: '범위 표기 `${match.group(0)}` 가 역순이다 — NN~MM 은 NN <= MM 이어야 한다',
    );
    for (var number = first; number <= last; number++) {
      ids.add('$prefix${number.toString().padLeft(2, '0')}');
    }
  }
  return ids;
}

/// [text] 안의 `T-172-XXX-NN` 과 범위 표기 `T-172-XXX-NN~MM` 을 개별 ID 로 모은다.
Set<String> _collectTest172Ids(String text) =>
    _collectIds(text, RegExp(r'(T-172-[A-Z]+-)(\d\d)(?:~(\d\d))?'));

/// [text] 안의 모든 시험 ID(`T-<수>(.<수>)*-<대문자>-NN` 과 범위 표기)를 개별
/// ID 로 모은다 — `T-16.3-SPM-01` 처럼 점이 든 번호도 받는다.
Set<String> _collectAllTestIds(String text) =>
    _collectIds(text, RegExp(r'(T-\d+(?:\.\d+)*-[A-Z]+-)(\d\d)(?:~(\d\d))?'));

/// [id] 가 [source] 안에서 test · group 이름으로 선언됐는지 본다.
///
/// `test(` · `testWidgets(` · `group(` 의 첫 인자 문자열이 [id] 로 시작하고
/// 바로 뒤가 `:` · 공백 · `(` 인 경우만 센다 — `reason: 'ID: …'` 같은 다른
/// 문자열 리터럴은 선언이 아니다. 공백 · `(` 는 `'T-16.3-SPM-01 build phase …'`
/// 처럼 ID 뒤에 콜론이 없는 기존 이름을 받기 위한 것이다. `group(` 은 디자인 토큰
/// 시험처럼 ID 를 group 이름에 둔 파일을 받는다.
bool _declaresTestName(String source, String id) => RegExp(
  "\\b(?:test|testWidgets|group)\\(\\s*['\"]${RegExp.escape(id)}[:\\s(]",
).hasMatch(source);

/// 지도 [guards] 에서 [id] 를 담은 줄을 모은다.
List<String> _guardLinesCiting(String guards, String id) =>
    guards.split('\n').where((String line) => line.contains(id)).toList();

/// 지도 [guards] 가 [id] 를 [testPath] 와 같은 줄(표 행)에서 인용하는지 본다.
void _expectGuardCites(String guards, String id, String testPath) {
  final List<String> lines = _guardLinesCiting(guards, id);
  expect(lines, isNotEmpty, reason: '회귀 가드 지도($_guardsPath)에 `$id` 가 없다');
  expect(
    lines.any((String line) => line.contains(testPath)),
    isTrue,
    reason: '회귀 가드 지도가 `$id` 를 $testPath 와 같은 행에서 인용하지 않는다',
  );
}

void main() {
  final String guide = readTrackedFile(_guidePath);
  final String guards = readTrackedFile(_guardsPath);
  final String replaceSection = _sliceFromHeading(guide, _replaceHeading);
  final String demoSection = _sliceFromHeading(guide, _demoHeading);
  final String allowlistSection = _sliceFromHeading(guide, _allowlistHeading);

  group('가이드 홈 하위 중첩 안내 계약 (T-172-DOCS)', () {
    test('T-172-DOCS-01: FCM 알림 절에 결과 스택 bullet 이 1개 있다 (SC4)', () {
      final List<String> bullets = linesStartingWith(guide, _stackBulletPrefix);
      expect(bullets, hasLength(1), reason: '결과 스택 bullet 이 없거나 중복이다');
      final String bullet = bullets.single;
      expect(bullet.length, greaterThan(_stackBulletPrefix.length));
      expect(
        bullet.contains('홈 → (설정) → 대상'),
        isTrue,
        reason: '결과 스택 bullet 에 `홈 → (설정) → 대상` 이 없다',
      );

      // 이 동작을 지키는 시험은 회귀 가드 지도가 인용한다.
      _expectGuardCites(guards, 'T-172-STACK-01', _nestingTestPath);
    });

    test('T-172-DOCS-02: 「바꿀 수 있는 지점」 표 「알림 탭으로 열 화면」 행이 1개다 (SC4)', () {
      final List<String> rows = linesStartingWith(
        guide,
        _customizationRowPrefix,
      );
      expect(rows, hasLength(1), reason: '「알림 탭으로 열 화면」 행이 없거나 중복이다');
      expect(
        rows.single.contains('routes'),
        isTrue,
        reason: '「알림 탭으로 열 화면」 행에 `routes` 가 없다',
      );

      _expectGuardCites(guards, 'T-172-ROUTER-01', _nestingTestPath);
      _expectGuardCites(guards, 'T-17-PUSH-01', _notificationRouteTestPath);
    });

    test('T-172-DOCS-03: ④ 의 실패 메시지가 T-172-ROUTER-01 의 실제 메시지다 (SC4)', () {
      // 양성 대조: ④ 슬라이스가 실제 절이다.
      expect(allowlistSection.trim(), isNotEmpty, reason: '④ 슬라이스가 비었다');
      expect(countOccurrences(allowlistSection, _allowlistHeading), 1);

      // 코드 쪽과 같은 출처 — 테스트가 쓰는 헬퍼가 만든 문자열 그대로여야 한다.
      final String message = describeRouteNotUnderHome('/notices', '/notices');
      expect(message, contains('/notices'), reason: '헬퍼가 경로를 메시지에 넣지 않는다');
      expect(
        allowlistSection.contains(message),
        isTrue,
        reason:
            '가이드 ④ 의 실패 메시지가 T-172-ROUTER-01 의 실제 메시지와 다르다 — '
            'describeRouteNotUnderHome 과 ④ 의 코드 블록을 함께 맞춘다',
      );
    });

    // T-172-DOCS-04(GA4 안내)는 지웠다 — 가이드에 그 안내가 없다.

    test('T-172-DOCS-05: ② 에 6번째 배선(routes:)이 있다 (SC4)', () {
      expect(replaceSection.trim(), isNotEmpty, reason: '② 슬라이스가 비었다');
      expect(countOccurrences(replaceSection, _replaceHeading), 1);
      expect(
        replaceSection.contains('routes:'),
        isTrue,
        reason: '② 에 `routes:` 가 없다',
      );

      // ② 의 배선을 빠뜨렸을 때 실패하는 구조 시험은 지도가 인용한다.
      _expectGuardCites(guards, 'T-172-ROUTER-01', _nestingTestPath);
    });

    // ③ 을 가이드에서 지우면 이 test 를 함께 지운다(③ 「지우는 법」 4단계).
    test('T-172-DOCS-07: ③ 에 데모 위치(설정 하위 조각)와 지우는 법이 있다 (SC4)', () {
      expect(demoSection.trim(), isNotEmpty, reason: '③ 슬라이스가 비었다');
      expect(countOccurrences(demoSection, _demoHeading), 1);
      final String demoSegment = _demoSegmentParts.join();
      for (final token in <String>[demoSegment, 'buildRoutesWithoutNamed']) {
        expect(
          demoSection.contains(token),
          isTrue,
          reason: '③ 에 `$token` 이 없다',
        );
      }
    });

    test('T-172-DOCS-06: 회귀 가드 지도가 인용한 test ID 가 실제 test 이름이다 (포인터 무결성)', () {
      // 선언을 찾는 소스는 `//` 행 주석을 걷어낸다 — 주석 처리로 비활성화한
      // test 는 선언이 아니다. 인용을 모으는 notification_route.dart 는 주석이
      // 곧 인용이므로 원문을 쓴다.
      final String nestingSource = stripSlashComments(
        readTrackedFile(_nestingTestPath),
      );
      final String notificationRouteSource = readTrackedFile(
        _notificationRoutePath,
      );

      // 지도 전체가 인용한 ID — 지도에는 동작 가드만 있고, 데모를 지울 때
      // 함께 지우는 시험의 ID 는 없다.
      final Set<String> cited = _collectAllTestIds(guards);
      // 양성 대조: 인용 집합이 비어 있지 않고 핵심 ID 를 담는다.
      expect(
        cited.containsAll(<String>{
          'T-172-STACK-01',
          'T-172-ROUTER-01',
          'T-17-PUSH-01',
          'T-176-ANDROID-02',
          'T-16.3-SPM-01',
        }),
        isTrue,
        reason: '지도에서 시험 ID 추출이 실패했다: $cited',
      );

      // test/ 아래 모든 dart test 파일을 한 번 읽어 선언을 찾는다. `//` 로
      // 주석 처리한 test 도 선언으로 세지 않도록 행 주석을 걷어낸 뒤 찾는다.
      final List<String> testSources = Directory('test')
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) => f.path.endsWith('_test.dart'))
          .map((File f) => stripSlashComments(f.readAsStringSync()))
          .toList();
      expect(testSources, isNotEmpty, reason: 'test/ 파일을 못 찾았다');

      for (final id in cited) {
        expect(
          testSources.any((String src) => _declaresTestName(src, id)),
          isTrue,
          reason: '회귀 가드 지도가 인용한 `$id` 가 어떤 test · group 이름으로도 선언돼 있지 않다',
        );
      }

      // 지도가 app_router_nesting_test.dart 의 것이라고 한 ID 는 그 파일에 있다.
      for (final id in <String>[
        'T-172-STACK-01',
        'T-172-LISTENER-01',
        'T-172-ROUTER-01',
      ]) {
        _expectGuardCites(guards, id, _nestingTestPath);
        expect(
          _declaresTestName(nestingSource, id),
          isTrue,
          reason: '`$id` 가 $_nestingTestPath 에 없다 — 지도 인용이 끊겼다',
        );
      }

      // 코드 주석이 인용한 T-172-ROUTER-01 도 그 파일에 있다.
      expect(
        notificationRouteSource.contains(_nestingTestPath),
        isTrue,
        reason: 'notification_route.dart 주석이 $_nestingTestPath 를 인용하지 않는다',
      );
      for (final String id in _collectTest172Ids(notificationRouteSource)) {
        expect(
          _declaresTestName(nestingSource, id),
          isTrue,
          reason:
              'notification_route.dart 주석이 인용한 `$id` 가 $_nestingTestPath 에 없다',
        );
      }
      expect(
        _collectTest172Ids(notificationRouteSource),
        contains('T-172-ROUTER-01'),
      );

      // 허용 목록이 비어 있지 않아야 ④ 구조 불변식이 의미가 있다.
      expect(kNotificationRoutableRoutes, isNotEmpty);
    });
  });
}
