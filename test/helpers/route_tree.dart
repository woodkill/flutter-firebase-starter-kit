// 라우트 트리 순회 공용 헬퍼 (Phase 17.2 todo 결정 1 — 홈 하위 중첩).
//
// 하위 GoRoute 의 path 는 상대 조각이라 최상위 route 목록을 걸러 전체 경로와
// 비교하면 0건이다(RESEARCH §R-04 실패 6건의 공통 원인). 전체 경로로 GoRoute 를
// 찾을 때는 이 헬퍼를 쓴다 — 최상위 검색을 test/ 에 다시 넣지 않는다.
//
// 여기 한 번만 정의하고 모든 호출자가 import 한다 — 파일마다 순회 규칙을 복제하면
// 사본 하나만 바뀌었을 때 같은 이름의 검색이 파일마다 다르게 동작한다.

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// 트리 전체의 [GoRoute] 를 깊이 우선으로 모은다.
///
/// [GoRoute] 가 아닌 [RouteBase](ShellRoute 등)는 내보내지 않지만 그 하위
/// `routes` 는 따라 내려간다. Test 2 · 3 의 재귀 개수 · name 수집에 쓴다.
Iterable<GoRoute> collectGoRoutes(List<RouteBase> routes) sync* {
  for (final RouteBase route in routes) {
    if (route is GoRoute) {
      yield route;
    }
    yield* collectGoRoutes(route.routes);
  }
}

/// 전체 경로 [fullPath] 가 가리키는 [GoRoute] 를 `findMatch` 로 찾는다.
///
/// 하위 route 의 `path` 는 상대 조각이므로 path 문자열 비교 대신 go_router 의
/// 실제 매칭 결과(마지막 [RouteMatch])를 쓴다 — 트리 깊이와 무관하게 같은
/// GoRoute 를 돌려준다.
///
/// 표에 없는 경로면 경로를 알리며 테스트를 실패시킨다.
///
/// **부재 단언에는 쓰지 않는다** — 경로가 없을 때 `fail()` 하므로 「이 경로가
/// 없어야 한다」 는 검사를 할 수 없다. 그 경우는 `findMatch(...).isError` 를 직접
/// 본다.
GoRoute findGoRouteByPath(RouteConfiguration configuration, String fullPath) {
  final RouteMatchList matchList = configuration.findMatch(Uri.parse(fullPath));
  if (matchList.isError || matchList.matches.isEmpty) {
    fail('route 표에 없는 전체 경로: $fullPath');
  }
  final RouteMatchBase last = matchList.matches.last;
  if (last is! RouteMatch) {
    fail('전체 경로 $fullPath 의 마지막 match 가 GoRoute 가 아니다: ${last.runtimeType}');
  }
  return last.route;
}

/// [matchList] 를 match 의 `matchedLocation` 목록(아래 → 위 스택)으로 읽는다.
///
/// 띄운 라우터의 현재 스택은 `router.routerDelegate.currentConfiguration` 을,
/// 위젯 없이 특정 경로의 스택은 `configuration.findMatch(uri)` 결과를 넘긴다.
List<String> readMatchedLocations(RouteMatchList matchList) =>
    matchList.matches.map((match) => match.matchedLocation).toList();

/// name 이 [dropName] 인 [GoRoute] 를 재귀적으로 뺀 복사본을 만든다.
///
/// T-171-ROUTER-03 release 시뮬레이션용(17.1 D-14 · RESEARCH §R-03 실측) —
/// `if (!kReleaseMode)` 로 빠지는 데모 GoRoute 가 트리 어느 깊이에 있어도 뺀다.
///
/// `GoRoute.routes` 는 final 이라 제자리 수정이 안 되므로 새 [GoRoute] 를 만든다.
/// production GoRoute 는 `path` · `name` · `builder` 만 쓰지만 생성자 인자 전부
/// (`pageBuilder` · `redirect` · `onExit` · `parentNavigatorKey` ·
/// `caseSensitive`)를 그대로 넘기고 `routes` 만 재귀 결과로 바꾼다.
///
/// [GoRoute] 가 아닌 [RouteBase] 를 만나면 조용히 남기지 않고 실패시킨다 — 복사
/// 규칙이 없는 노드를 그대로 두면 그 아래 데모 GoRoute 를 놓친 채 release 표가
/// 만들어진다.
List<RouteBase> buildRoutesWithoutNamed(
  List<RouteBase> routes,
  String dropName,
) {
  final List<RouteBase> copied = <RouteBase>[];
  for (final RouteBase route in routes) {
    if (route is! GoRoute) {
      fail(
        'GoRoute 밖 RouteBase(${route.runtimeType}) 는 복사 규칙이 없다 — '
        '이 헬퍼에 규칙을 더한다',
      );
    }
    if (route.name == dropName) {
      continue;
    }
    copied.add(
      GoRoute(
        path: route.path,
        name: route.name,
        builder: route.builder,
        pageBuilder: route.pageBuilder,
        redirect: route.redirect,
        onExit: route.onExit,
        parentNavigatorKey: route.parentNavigatorKey,
        caseSensitive: route.caseSensitive,
        routes: buildRoutesWithoutNamed(route.routes, dropName),
      ),
    );
  }
  return copied;
}

/// T-172-ROUTER-01 의 「홈 하위 route 가 아니다」 실패 메시지를 만든다.
///
/// [path] 는 알림 허용 목록 경로, [firstMatchedLocation] 은 그 경로의 첫 match 의
/// `matchedLocation` 이다. 이 문장은 사용자에게 「고치는 법」 을 알려 주는 메시지라
/// 매뉴얼 「홈 화면 바꾸기」 ④ 가 그대로 인용한다 — 구조 불변식 test 와 매뉴얼 계약
/// test(`manual_nested_routes_contract_test.dart`)가 같은 출처를 쓰게 여기 한 번만
/// 정의한다. 문구를 바꾸면 매뉴얼 ④ 의 코드 블록도 함께 고친다.
String describeRouteNotUnderHome(String path, String firstMatchedLocation) =>
    '알림 허용 목록 경로 $path 가 홈 하위 route 가 아니다 '
    '(첫 match = $firstMatchedLocation). '
    'lib/core/router/app_router.dart 의 홈 GoRoute routes 안으로 옮긴다'
    ' — docs/manual.md 「홈 화면 바꾸기」 ④';
