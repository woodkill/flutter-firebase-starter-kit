import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../application/pending_notification_route.dart';

/// 알림 탭 경로를 홈에서 소비해 이동시키는 크기 0 위젯 (Phase 17 D-04).
///
/// 홈 화면 트리에 1개 둔다. 홈은 스플래시 · 인증 redirect 를 통과해야 그려지므로
/// 소비는 항상 그 뒤다 — 종료 상태 탭도 스플래시 → redirect → 홈 → 대상 화면
/// 순서가 된다. 이동은 `context.go` 라 대상 경로에도 redirect 가 다시 적용된다
/// (인증 가드 우회 0 · Phase 10.2 invariant).
///
/// - 홈이 처음 그려진 뒤 이미 쌓인 경로를 소비한다(종료 · 백그라운드 탭).
/// - 홈이 트리에 있는 동안(다른 화면 아래에 있어도) 새 경로가 들어오면
///   곧바로 소비한다(포그라운드 탭) — `ref.listen` 은 TickerMode 에 pause
///   되지 않는다(T-17-PUSH-08 · 리뷰 IN-24).
/// - 결과 스택은 홈 → (설정) → 대상이다(Phase 17.2 todo 결정 1) — 대상 route 가
///   홈 하위라 `go` 라도 홈이 맨 아래에 남고, 이 위젯의 `State` 도 유지된다(T-172-STACK-01).
///   중간 화면도 보이지 않는 아래 장으로 build 된다(설정 화면도 build 된다 —
///   그 화면의 provider 초기화가 이 이동 시점에 일어난다).
/// - 경로가 홈이면 이동하지 않는다(허용 목록 밖 payload 포함).
class PendingNotificationRouteListener extends ConsumerStatefulWidget {
  /// [PendingNotificationRouteListener] 를 생성한다.
  const PendingNotificationRouteListener({super.key});

  @override
  ConsumerState<PendingNotificationRouteListener> createState() =>
      _PendingNotificationRouteListenerState();
}

class _PendingNotificationRouteListenerState
    extends ConsumerState<PendingNotificationRouteListener> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _consume());
  }

  /// pending 경로를 꺼내 홈이 아니면 그 화면으로 이동한다.
  void _consume() {
    if (!mounted) return;
    final route = ref.read(pendingNotificationRouteProvider.notifier).consume();
    if (route == null || route == AppRoutes.home) return;
    context.go(route);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(pendingNotificationRouteProvider, (previous, next) {
      // 알림 상태 변경 통지 중에 같은 provider 를 다시 바꾸지 않도록 소비는
      // 다음 microtask 로 미룬다.
      if (next != null) scheduleMicrotask(_consume);
    });
    return const SizedBox.shrink();
  }
}
