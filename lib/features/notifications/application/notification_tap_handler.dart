import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/providers/firebase_providers.dart';
import '../data/local_notifications_service.dart';
import '../data/messaging_service.dart';
import 'pending_notification_route.dart';

part 'notification_tap_handler.g.dart';

/// 알림 수신 표시 · 탭 경로를 앱 수명 동안 잇는 핸들러 (Phase 17 D-01 · D-04).
///
/// `app.dart` 가 앱 시작 때 1회 깨운다(keepAlive).
/// - **포그라운드 수신:** Android 에서 notification 메시지를 로컬 알림으로
///   띄운다(채널 `general` · payload = `data.route`). iOS 는 OS 가 표시한다.
/// - **탭:** 로컬 알림 탭 payload 를 [PendingNotificationRoute] 로 보낸다 —
///   이동은 홈 화면 리스너가 한다.
///
/// Firebase 미초기화면 아무것도 구독하지 않는다(Phase 1 D-13). 수신 알림을
/// 저장하거나 목록으로 남기지 않는다(D-06 — 앱 내 알림함 없음).
@Riverpod(keepAlive: true)
class NotificationTapHandler extends _$NotificationTapHandler {
  @override
  void build() {
    if (!ref.watch(isFirebaseInitializedProvider)) return;
    final messaging = ref.watch(messagingServiceProvider);
    final local = ref.watch(localNotificationsServiceProvider);

    unawaited(local.initialize(onTap: _savePendingRoute));

    final foreground = messaging.onMessage.listen(
      (message) => _showForeground(local, message),
    );
    ref.onDispose(() => unawaited(foreground.cancel()));
  }

  /// 탭한 알림의 route [raw] 를 pending 으로 보관한다.
  void _savePendingRoute(Object? raw) {
    ref.read(pendingNotificationRouteProvider.notifier).set(raw);
  }

  /// 포그라운드 수신 [message] 를 Android 로컬 알림으로 띄운다 (D-01).
  ///
  /// iOS 는 presentation options 로 OS 가 띄우므로 건너뛴다(중복 0).
  /// notification 없는 data-only 메시지는 표시할 문구가 없어 건너뛴다.
  void _showForeground(LocalNotificationsService local, RemoteMessage message) {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final notification = message.notification;
    if (notification == null) return;
    unawaited(
      local.showRemote(
        title: notification.title,
        body: notification.body,
        route: message.data['route']?.toString(),
      ),
    );
  }
}
