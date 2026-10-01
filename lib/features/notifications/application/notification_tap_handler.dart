import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/providers/firebase_providers.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../data/local_notifications_service.dart';
import '../data/messaging_service.dart';
import 'pending_notification_route.dart';

part 'notification_tap_handler.g.dart';

/// 알림 수신 표시 · 탭 경로를 앱 수명 동안 잇는 핸들러
/// (Phase 17 D-01 · D-04 · D-31).
///
/// `app.dart` 가 앱 시작 때 1회 깨운다(keepAlive).
/// - **포그라운드 수신:** Android 에서 notification 메시지를 로컬 알림으로
///   띄운다(채널 `general` · payload = `data.route`). iOS 는 presentation
///   options 를 켜 OS 가 표시한다(중복 0).
/// - **탭 3경로:** 로컬 알림 탭 payload · 백그라운드 `onMessageOpenedApp` ·
///   종료 `getInitialMessage`(없으면 로컬 알림 launch payload)가 모두
///   [PendingNotificationRoute] 로 모인다 — 이동은 홈 화면 리스너가 홈이
///   그려진 뒤에 한다.
/// - **채널 이름:** 앱 언어로 등록하고 언어가 바뀌면 같은 id 로 다시 등록한다.
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

    // D-31 — 채널 이름 · 설명을 앱 언어로 등록하고 언어 변경 때 갱신한다.
    ref.listen<Locale>(
      localeProvider,
      (previous, next) => _ensureChannel(local, next),
      fireImmediately: true,
    );
    // D-01 — iOS 는 이 옵션이 켜져야 포그라운드 알림을 OS 가 표시한다.
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      unawaited(messaging.setForegroundPresentationOptions());
    }

    unawaited(_startLocalNotifications(messaging, local));

    final foreground = messaging.onMessage.listen(
      (message) => _showForeground(local, message),
    );
    final openedApp = messaging.onMessageOpenedApp.listen(
      (message) => _savePendingRoute(message.data['route']),
    );
    ref.onDispose(() {
      unawaited(foreground.cancel());
      unawaited(openedApp.cancel());
    });
  }

  /// 로컬 알림을 초기화한 뒤 종료 상태 탭 경로를 1회 꺼낸다 (D-04).
  ///
  /// FCM 알림 탭으로 시작했으면 그 메시지의 route, 아니면 로컬 알림 탭으로
  /// 시작했을 때의 payload 를 pending 으로 보관한다. 둘 다 없으면 아무것도
  /// 하지 않는다.
  Future<void> _startLocalNotifications(
    MessagingService messaging,
    LocalNotificationsService local,
  ) async {
    await local.initialize(onTap: _savePendingRoute);
    final initialMessage = await messaging.getInitialMessage();
    if (!ref.mounted) return;
    if (initialMessage != null) {
      _savePendingRoute(initialMessage.data['route']);
      return;
    }
    final payload = await local.launchPayload();
    if (!ref.mounted || payload == null) return;
    _savePendingRoute(payload);
  }

  /// 앱 언어 [locale] 의 문구로 알림 채널을 등록한다 (D-31).
  void _ensureChannel(LocalNotificationsService local, Locale locale) {
    final l10n = lookupAppLocalizations(locale);
    unawaited(
      local.ensureGeneralChannel(
        name: l10n.notificationChannelGeneralName,
        description: l10n.notificationChannelGeneralDescription,
      ),
    );
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
