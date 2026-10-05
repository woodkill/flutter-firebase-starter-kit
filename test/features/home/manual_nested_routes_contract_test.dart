// Phase 17.2 성공 기준 4 (문서 부분) — 매뉴얼의 홈 하위 중첩 안내 계약.
// (FIRE-01 · Nyquist gap-fill · Plan 17.2-04 Task 1/2 의 `<automated>` shell grep 대체)
//
// Plan 04 는 이 사실들을 shell grep 으로 한 번만, 그것도 plan 커밋 시점 사본에
// 대해 확인했다. 이 파일은 같은 의미를 HEAD 의 docs/manual.md 에 대해 반복
// 실행 가능한 test 로 고정해 bullet 삭제 · 헤딩 이름 변경 · 메시지 어긋남 ·
// 끊어진 test ID 포인터를 막는다. 각 슬라이스는 양성 대조(비어 있지 않고 자기
// 헤딩을 담는다)를 함께 세워 빈 슬라이스가 공허하게 통과하지 못하게 한다.
//
// T-172-DOCS-01: 「FCM 알림」 결과 스택 bullet (홈 → (설정) → 대상 · T-172-STACK-01).
// T-172-DOCS-02: 커스터마이징 표 「알림 탭으로 열 화면」 행 1개 · 필수 토큰.
// T-172-DOCS-03: ④ 의 실패 메시지가 T-172-ROUTER-01 의 실제 메시지와 같다.
// T-172-DOCS-04: GA4 안내 4항(알림으로 연 화면 · settings · account).
// T-172-DOCS-05: ② 의 6번째 배선(routes:).
// T-172-DOCS-06: 매뉴얼 · 코드 주석이 인용한 T-172 test ID 가 실제 test 이름이다
//   (범위 표기 `T-172-XXX-NN~MM` 은 펼쳐서 모두 본다).
// T-172-DOCS-07: ③ 의 데모 위치(설정 하위 조각) · 지우는 법 토큰.
//
// 킷 사용자 안전 규칙(매뉴얼 ② · ③ 절차가 이 파일을 건드리지 않게):
// - 데모 상수 이름은 리터럴 없이 조각을 이어 만든다(③ 의 grep 0 건 확인).
// - 옛 홈 파일 · 클래스 이름은 쓰지 않는다(② 의 이름 바꾸기 grep).
// - 경로 개수는 하드코딩하지 않는다(④ 가 route 를 더해도 깨지지 않게).
// - 예외: 매뉴얼에서 ③ 절 자체를 지울 때는 T-172-DOCS-07 과 그 전용 선언을
//   함께 지운다(③ 「지우는 법」 4단계에 적혀 있다). ③ 을 남기면 그대로 둔다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/features/notifications/application/notification_route.dart'
    show kNotificationRoutableRoutes;

import '../../helpers/route_tree.dart' show describeRouteNotUnderHome;
import '../../helpers/source_text.dart';

/// 매뉴얼 경로.
const String _manualPath = 'docs/manual.md';

/// 알림 허용 목록 코드 파일 — 주석이 T-172-ROUTER-01 을 인용한다.
const String _notificationRoutePath =
    'lib/features/notifications/application/notification_route.dart';

/// 구조 불변식 test 파일 — 매뉴얼이 T-172-STACK-01 · LISTENER-01 · ROUTER-01 을 인용한다.
const String _nestingTestPath = 'test/core/router/app_router_nesting_test.dart';

/// 결과 스택 bullet 의 시작.
const String _stackBulletPrefix = '- **결과 스택 (Phase 17.2):**';

/// 커스터마이징 표 행의 시작.
const String _customizationRowPrefix = '| 알림 탭으로 열 화면 |';

/// GA4 안내 헤딩 (이 헤딩은 파일에 1번).
const String _ga4Heading =
    '### ⚠ adopter breaking 안내 — Analytics(GA4) screen name';

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

/// 매뉴얼에서 [heading] 줄부터 다음 `## ` · `### ` 헤딩 직전까지를 돌려준다.
///
/// 자르기 규칙은 `test/helpers/source_text.dart` 의 [sliceMarkdownSection] 한
/// 곳에 있다 — 이 파일은 `### ` 하위 절을 자르므로 경계 수준 3 을 쓴다.
String _sliceFromHeading(String manual, String heading) =>
    sliceMarkdownSection(manual, heading, maxLevel: 3);

/// [text] 안의 `T-172-XXX-NN` 과 범위 표기 `T-172-XXX-NN~MM` 을 개별 ID 로
/// 펼쳐 중복 없이 모은다.
///
/// 범위 표기(예: `T-172-ROUTES-01~03`)는 01 · 02 · 03 을 모두 인용한 것으로
/// 본다 — 첫 ID 만 뽑으면 02 · 03 의 이름이 바뀌어도 포인터 검사가 통과한다.
Set<String> _collectTest172Ids(String text) {
  final Set<String> ids = <String>{};
  for (final RegExpMatch match in RegExp(
    r'(T-172-[A-Z]+-)(\d\d)(?:~(\d\d))?',
  ).allMatches(text)) {
    final String prefix = match.group(1)!;
    final int first = int.parse(match.group(2)!);
    final int last = int.parse(match.group(3) ?? match.group(2)!);
    for (int number = first; number <= last; number++) {
      ids.add('$prefix${number.toString().padLeft(2, '0')}');
    }
  }
  return ids;
}

/// [id] 가 [source] 안에서 test 이름으로 선언됐는지 본다.
///
/// `test(` · `testWidgets(` 의 첫 인자 문자열이 [id] 로 시작하고 바로 뒤가
/// `:` · 공백 · `(` 인 경우만 센다 — `reason: 'ID: …'` 같은 다른 문자열
/// 리터럴은 선언이 아니다. 공백 · `(` 는 `'T-172-WITHDRAW-02 (Phase 17.2 …'`
/// 처럼 ID 뒤에 괄호가 오는 기존 이름을 받기 위한 것이다.
bool _declaresTestName(String source, String id) => RegExp(
  "\\b(?:test|testWidgets)\\(\\s*['\"]${RegExp.escape(id)}[:\\s(]",
).hasMatch(source);

void main() {
  final String manual = readTrackedFile(_manualPath);
  final String ga4 = _sliceFromHeading(manual, _ga4Heading);
  final String replaceSection = _sliceFromHeading(manual, _replaceHeading);
  final String demoSection = _sliceFromHeading(manual, _demoHeading);
  final String allowlistSection = _sliceFromHeading(manual, _allowlistHeading);

  group('매뉴얼 홈 하위 중첩 안내 계약 (T-172-DOCS)', () {
    test('T-172-DOCS-01: FCM 알림 절에 결과 스택 bullet 이 1개 있다 (SC4)', () {
      final List<String> bullets = linesStartingWith(
        manual,
        _stackBulletPrefix,
      );
      expect(bullets, hasLength(1), reason: '결과 스택 bullet 이 없거나 중복이다');
      final String bullet = bullets.single;
      expect(bullet.length, greaterThan(_stackBulletPrefix.length));
      for (final String token in <String>['홈 → (설정) → 대상', 'T-172-STACK-01']) {
        expect(
          bullet.contains(token),
          isTrue,
          reason: '결과 스택 bullet 에 `$token` 이 없다',
        );
      }
    });

    test('T-172-DOCS-02: 커스터마이징 표 「알림 탭으로 열 화면」 행이 1개다 (SC4)', () {
      final List<String> rows = linesStartingWith(
        manual,
        _customizationRowPrefix,
      );
      expect(rows, hasLength(1), reason: '「알림 탭으로 열 화면」 행이 없거나 중복이다');
      for (final String token in <String>[
        'routes',
        'T-172-ROUTER-01',
        'T-17-PUSH-01',
      ]) {
        expect(
          rows.single.contains(token),
          isTrue,
          reason: '「알림 탭으로 열 화면」 행에 `$token` 이 없다',
        );
      }
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
            '매뉴얼 ④ 의 실패 메시지가 T-172-ROUTER-01 의 실제 메시지와 다르다 — '
            'describeRouteNotUnderHome 과 ④ 의 코드 블록을 함께 맞춘다',
      );
    });

    test('T-172-DOCS-04: GA4 안내 4항이 알림으로 연 화면의 2건을 적는다 (SC4)', () {
      expect(ga4.trim(), isNotEmpty, reason: 'GA4 슬라이스가 비었다');
      expect(countOccurrences(ga4, _ga4Heading), 1);
      for (final String token in <String>[
        'Phase 17.2',
        '`settings`',
        '`account`',
        'T-172-ANALYTICS-01',
      ]) {
        expect(ga4.contains(token), isTrue, reason: 'GA4 안내에 `$token` 이 없다');
      }
    });

    test('T-172-DOCS-05: ② 에 6번째 배선(routes:)이 있다 (SC4)', () {
      expect(replaceSection.trim(), isNotEmpty, reason: '② 슬라이스가 비었다');
      expect(countOccurrences(replaceSection, _replaceHeading), 1);
      for (final String token in <String>['routes:', 'T-172-ROUTER-01']) {
        expect(
          replaceSection.contains(token),
          isTrue,
          reason: '② 에 `$token` 이 없다',
        );
      }
    });

    // ③ 을 매뉴얼에서 지우면 이 test 를 함께 지운다(③ 「지우는 법」 4단계).
    test('T-172-DOCS-07: ③ 에 데모 위치(설정 하위 조각)와 지우는 법이 있다 (SC4)', () {
      expect(demoSection.trim(), isNotEmpty, reason: '③ 슬라이스가 비었다');
      expect(countOccurrences(demoSection, _demoHeading), 1);
      final String demoSegment = _demoSegmentParts.join();
      for (final String token in <String>[
        demoSegment,
        'buildRoutesWithoutNamed',
      ]) {
        expect(
          demoSection.contains(token),
          isTrue,
          reason: '③ 에 `$token` 이 없다',
        );
      }
    });

    test('T-172-DOCS-06: 인용된 T-172 test ID 가 실제 test 이름이다 (포인터 무결성)', () {
      final String nestingSource = readTrackedFile(_nestingTestPath);
      final String notificationRouteSource = readTrackedFile(
        _notificationRoutePath,
      );

      // 매뉴얼 슬라이스가 인용한 ID (삭제 안내 대상 T-171-* 는 대상이 아니다).
      final String bullet = linesStartingWith(
        manual,
        _stackBulletPrefix,
      ).join();
      final String row = linesStartingWith(
        manual,
        _customizationRowPrefix,
      ).join();
      final Set<String> cited = <String>{
        ..._collectTest172Ids(bullet),
        ..._collectTest172Ids(row),
        ..._collectTest172Ids(ga4),
        ..._collectTest172Ids(replaceSection),
        ..._collectTest172Ids(demoSection),
        ..._collectTest172Ids(allowlistSection),
      };
      // 양성 대조: 인용 집합이 비어 있지 않고 핵심 ID 를 담는다.
      expect(
        cited.containsAll(<String>{
          'T-172-STACK-01',
          'T-172-ROUTER-01',
          'T-172-ANALYTICS-01',
        }),
        isTrue,
        reason: '슬라이스에서 T-172 ID 추출이 실패했다: $cited',
      );

      // test/ 아래 모든 dart test 파일을 한 번 읽어 선언을 찾는다. 이 파일도
      // 포함한다 — 매뉴얼 ③ 이 이 파일의 T-172-DOCS-07 을 인용하고,
      // [_declaresTestName] 은 `test(` 의 첫 인자만 선언으로 세므로 이 파일의
      // ID 목록 · reason 문자열이 선언으로 잘못 잡히지 않는다.
      final List<String> testSources = Directory('test')
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) => f.path.endsWith('_test.dart'))
          .map((File f) => f.readAsStringSync())
          .toList();
      expect(testSources, isNotEmpty, reason: 'test/ 파일을 못 찾았다');

      for (final String id in cited) {
        expect(
          testSources.any((String src) => _declaresTestName(src, id)),
          isTrue,
          reason: '매뉴얼이 인용한 `$id` 가 어떤 test 이름으로도 선언돼 있지 않다',
        );
      }

      // 매뉴얼이 app_router_nesting_test.dart 의 것이라고 한 ID 는 그 파일에 있다.
      for (final String id in <String>[
        'T-172-STACK-01',
        'T-172-LISTENER-01',
        'T-172-ROUTER-01',
      ]) {
        expect(
          _declaresTestName(nestingSource, id),
          isTrue,
          reason: '`$id` 가 $_nestingTestPath 에 없다 — 매뉴얼 인용이 끊겼다',
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
