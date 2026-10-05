// Phase 17.1 성공 기준 5 (문서 부분) — 매뉴얼 「홈 화면 바꾸기」 절 계약.
// (AUTH-13 · Nyquist gap-fill · Plan 10 Task 1/2 의 `<automated>` shell grep 대체)
//
// ROADMAP SC5: 「매뉴얼에 「홈 화면 바꾸기」 절이 있고 옛 Account 카드 참조가 0 이다」.
// Plan 10 은 이를 shell grep 으로 한 번만 확인했다. 이 파일은 같은 의미를 반복
// 실행 가능한 test 로 고정해 헤딩 이름 변경 · 절 비우기 · 옛 이름 재유입을 막는다.
//
// T-171-DOCS-01: 헤딩 · TOC 항목이 각각 정확히 1개.
// T-171-DOCS-02: 절 본문이 비어 있지 않고 필수 토큰을 모두 담는다.
// T-171-DOCS-03: 킷 문구는 문의 채널을 가정하지 않는다(「고객센터」 · 「문의」 0).
// T-171-DOCS-04: 절의 알림 이동 가능 경로 목록이 코드 상수와 어긋나지 않는다.
//   (Phase 17.2 — 코드 쪽은 상수 값 import 로 대조 · 조각 조합 · 앱의 경로 추가에도 깨지지 않는다)
// T-171-DOCS-05: 변경 이력 이전 본문에 옛 홈 · 옛 위치 표기가 0 이다.
// T-171-DOCS-06: 새 위치(계정 정보 화면 · 데모 화면 · 404 화면) 표기가 있다.
//
// 옛 홈 이름은 리터럴 없이 조각을 이어 만든다 — home_listener_source_guard_test 의
// T-171-HOME-17 부재 grep 에 이 파일이 걸리지 않게 하기 위해서다.

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_starter_kit/features/notifications/application/notification_route.dart'
    show kNotificationRoutableRoutes;

import '../../helpers/source_text.dart';

/// 매뉴얼 경로.
const String _manualPath = 'docs/manual.md';

/// 절 헤딩 (정확히 한 줄).
const String _sectionHeading = '## 홈 화면 바꾸기 (Phase 17.1)';

/// TOC 항목 (정확히 한 개).
const String _tocEntry = '[홈 화면 바꾸기 (Phase 17.1)](#홈-화면-바꾸기-phase-171)';

/// 변경 이력 헤딩 — 이 앞까지가 「본문」, 뒤는 옛 이름 허용.
const String _historyHeading = '## 변경 이력';

/// 옛 홈 클래스 이름 조각 — 이어 붙여야 이름이 된다(리터럴 0).
const List<String> _legacyParts = <String>['Environment', 'Info', 'Screen'];

/// 알림 이동 가능 경로 5개 — 코드 상수와 아래 테스트에서 교차 검증한다.
const List<String> _routableRoutes = <String>[
  '/',
  '/settings',
  '/settings/account',
  '/terms/service',
  '/terms/privacy',
];

/// 매뉴얼에서 [_sectionHeading] 부터 다음 `## ` 헤딩 직전까지를 돌려준다.
String _sliceSection(String manual) {
  final int start = manual.indexOf('$_sectionHeading\n');
  if (start == -1) {
    return '';
  }
  final int next = manual.indexOf('\n## ', start + _sectionHeading.length);
  return next == -1 ? manual.substring(start) : manual.substring(start, next);
}

/// 매뉴얼에서 [_historyHeading] 이전 본문을 돌려준다(헤딩 부재 시 빈 문자열).
String _sliceBodyBeforeHistory(String manual) {
  final int end = manual.indexOf('\n$_historyHeading\n');
  return end == -1 ? '' : manual.substring(0, end);
}

void main() {
  final String manual = readTrackedFile(_manualPath);
  final String section = _sliceSection(manual);
  final String body = _sliceBodyBeforeHistory(manual);

  group('매뉴얼 「홈 화면 바꾸기」 계약 (T-171-DOCS)', () {
    test('T-171-DOCS-01: 절 헤딩 1개 · TOC 항목 1개가 있다 (SC5)', () {
      final int headingLines = manual
          .split('\n')
          .where((String line) => line == _sectionHeading)
          .length;
      expect(headingLines, 1, reason: '절 헤딩이 없거나 중복이다');
      expect(countOccurrences(manual, _tocEntry), 1, reason: 'TOC 항목이 어긋났다');
    });

    test('T-171-DOCS-02: 절 본문이 비어 있지 않고 필수 토큰을 담는다 (SC5)', () {
      expect(section.trim(), isNotEmpty, reason: '절 슬라이스가 비었다');
      const List<String> required = <String>[
        'home_body.dart',
        'home_screen.dart',
        'PendingNotificationRouteListener',
        'AnnouncementBar',
        'GuestBanner',
        'kNotificationRoutableRoutes',
        '/settings/account',
        '/settings/developer',
        'lib/features/demo/presentation/demo_screen.dart',
        'profile',
        'release',
        'appName',
      ];
      for (final String token in required) {
        expect(
          section.contains(token),
          isTrue,
          reason: '「홈 화면 바꾸기」 절에 `$token` 이 없다',
        );
      }
    });

    test('T-171-DOCS-03: 절은 문의 채널을 가정하지 않는다 (킷 문구 규칙)', () {
      // 양성 대조: 같은 슬라이스가 비어 있지 않고 헤딩을 담는다.
      expect(countOccurrences(section, _sectionHeading), 1);
      expect(countOccurrences(section, '고객센터'), 0);
      expect(countOccurrences(section, '문의'), 0);
    });

    test('T-171-DOCS-04: 절의 알림 이동 가능 경로가 코드 상수와 같다 (SC5)', () {
      // 코드 쪽 교차 검증(Phase 17.2): 소스 리터럴 정규식 대신 상수 값을 import 해
      // 대조한다 — 전체 경로를 조각 상수로 조합해도(`'/$settingsSegment'`) 깨지지
      // 않고, 앱이 허용 목록에 경로를 더해도(매뉴얼 ④) 실패하지 않는다.
      expect(
        kNotificationRoutableRoutes.containsAll(_routableRoutes),
        isTrue,
        reason:
            '킷 기본 이동 가능 경로 5개가 코드 목록에 없다 — 매뉴얼 「홈 화면 바꾸기」 ④ 와 '
            '이 목록을 함께 갱신한다',
      );

      // 매뉴얼 쪽: 절이 5개 경로를 모두 코드 표기(백틱)로 언급한다.
      expect(section.trim(), isNotEmpty);
      for (final String route in _routableRoutes) {
        expect(
          section.contains('`$route`'),
          isTrue,
          reason: '절에 이동 가능 경로 `$route` 가 없다',
        );
      }
    });

    test('T-171-DOCS-05: 변경 이력 이전 본문에 옛 홈 · 옛 위치 표기가 없다 (SC5)', () {
      // 양성 대조: 본문 슬라이스가 실제 매뉴얼 본문이다(절 헤딩 1개 포함).
      expect(countOccurrences(body, '$_sectionHeading\n'), 1);
      expect(body.length, greaterThan(section.length));

      final String legacyClassName = _legacyParts.join();
      final String legacyFileStem = _legacyParts
          .map((String part) => part.toLowerCase())
          .join('_');
      final List<String> banned = <String>[
        legacyClassName,
        legacyFileStem,
        '홈 계정정보 카드',
        'Account 카드',
        'buildNotFoundScreen',
        '설정 「내 계정」',
      ];
      for (final String token in banned) {
        expect(
          countOccurrences(body, token),
          0,
          reason: '변경 이력 이전 본문에 옛 표기가 남아 있다: $token',
        );
      }
    });

    test('T-171-DOCS-06: 본문이 새 위치(계정 정보 · 데모 · 404 화면)를 안내한다 (SC5)', () {
      expect(countOccurrences(body, '$_sectionHeading\n'), 1);
      expect(
        countOccurrences(body, '/settings/account'),
        greaterThanOrEqualTo(2),
      );
      for (final String token in <String>[
        'NotFoundScreen',
        'account_screen.dart',
        'demo_screen.dart',
      ]) {
        expect(
          countOccurrences(body, token),
          greaterThanOrEqualTo(1),
          reason: '본문에 `$token` 안내가 없다',
        );
      }
    });
  });
}
