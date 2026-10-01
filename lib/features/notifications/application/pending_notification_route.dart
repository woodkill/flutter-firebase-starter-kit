import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'notification_route.dart';

part 'pending_notification_route.g.dart';

/// 알림 탭으로 열 화면 경로를 홈 도달 전까지 보관하는 저장소 (Phase 17 D-04).
///
/// 탭 3경로(포그라운드 로컬 알림 payload · 백그라운드 `onMessageOpenedApp` ·
/// 종료 `getInitialMessage` + 로컬 알림 launch details)가 모두 [set] 으로
/// 모인다. 값은 홈 화면의 `PendingNotificationRouteListener` 가 [consume]
/// 해서 이동한다 — 스플래시 · 인증 redirect 가 끝나 홈이 그려진 뒤라서 인증
/// 가드를 건너뛰지 않는다(Phase 10.2 invariant).
///
/// 값은 [resolveNotificationRoute] 로 판정한 경로(허용 목록 밖이면 홈)이고,
/// 소비 전이면 마지막 탭이 이긴다.
@Riverpod(keepAlive: true)
class PendingNotificationRoute extends _$PendingNotificationRoute {
  @override
  String? build() => null;

  /// 알림 payload 의 route [raw] 를 판정해 보관한다.
  void set(Object? raw) {
    state = resolveNotificationRoute(raw);
  }

  /// 보관한 경로를 돌려주고 비운다. 없으면 null.
  String? consume() {
    final route = state;
    state = null;
    return route;
  }
}
