import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/providers/firebase_providers.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../data/local_notifications_service.dart';
import '../data/messaging_service.dart';
import 'pending_notification_route.dart';

part 'notification_tap_handler.g.dart';

/// 처리한 FCM 초기 메시지 id 목록 저장 키 (SharedPreferences · quick
/// 261003-cti).
///
/// 최근 앱 복원 때 같은 초기 메시지가 다시 와도 이동하지 않게 하는 재생
/// 방지용이다. 불투명한 `messageId` 만 담고 알림 내용은 담지 않는다. 계정
/// 데이터가 아니라 기기 단위 기록이라 로그아웃 · 탈퇴에서 지우지 않는다.
/// 값은 로그에 싣지 않는다.
const String kNotificationsHandledInitialMessageIdsKey =
    'notifications_handled_initial_message_ids';

/// [kNotificationsHandledInitialMessageIdsKey] 에 남기는 최근 id 개수 상한.
///
/// firebase_messaging 16.7.0 Android 저장본 상한(`MAX_SIZE_NOTIFICATIONS`)과
/// 같은 값이다. 저장본에서 밀려난 메시지는 새 프로세스가 다시 돌려줄 수
/// 없으므로 더 오래 기억할 필요가 없다. 플러그인을 올릴 때 이 값을 대조한다.
const int kNotificationsHandledInitialMessageIdsLimit = 100;

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
/// 저장하거나 목록으로 남기지 않는다(D-06 — 앱 내 알림함 없음). 종료 상태 탭
/// 재생 방지용 messageId 만 기기에 기록한다
/// ([kNotificationsHandledInitialMessageIdsKey]).
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
  /// 하지 않는다. FCM 초기 메시지는 처리한 messageId 기록
  /// ([kNotificationsHandledInitialMessageIdsKey])에 이미 있으면 건너뛰고
  /// 끝낸다 — 로컬 알림 launch payload 도 보지 않는다(FCM 알림 intent 라
  /// 대상이 아니다).
  ///
  /// `ref.mounted` 가드는 **provider dispose 만** 걸러 낸다 — keepAlive
  /// notifier 의 `ref` 는 요소의 현재 Ref 라 재빌드 뒤에도 true 다(riverpod
  /// 3.2.1 · 리뷰 WR-06). 여기서는 그것이 맞다: `getInitialMessage` 는 같은
  /// 엔진 안에서 1회만 값을 준다(Android 플러그인 인스턴스가 꺼낸 메시지를
  /// 소비 처리) — 재빌드 중에 받은 경로를 빌드 세대로 버리면 종료 상태 탭
  /// 이동이 사라진다. 보관 대상 [PendingNotificationRoute] 는 별도 provider 라
  /// 이전 세대가 넣어도 안전하다.
  ///
  /// 「1회」 는 엔진 단위다. firebase_messaging 16.7.0 Android 는 소비 기록을
  /// 플러그인 인스턴스 메모리에만 두고, 콜드 탭의 메모리 경로 소비는 디스크
  /// 저장본을 지우지 않는다. 알림 탭으로 연 task 를 홈 버튼으로 내린 뒤
  /// 프로세스가 죽고 최근 앱 카드로 복원하면, Android 는 처음 연 알림
  /// intent(최근 앱 재실행 플래그 없음)로 Activity 를 다시 만든다. 그러면 새
  /// 엔진의 이 메서드가 같은 메시지를 다시 받는다. 2026-10-03 SM-S942N 에서
  /// 탭 없이 옛 경로로 재생됐고, 저장본이 남아 복원마다 같은 조건이 된다.
  /// 그래서 처리한 messageId 를 기록해 건너뛴다.
  ///
  /// 로컬 알림 탭으로 콜드 시작한 경우도 같은 복원에서 launch payload 가 다시
  /// 나올 수 있다(flutter_local_notifications 22.3.1
  /// `getNotificationAppLaunchDetails` 도 최근 앱 재실행 플래그만 거른다). 소스
  /// 추론 · 미관측이라 막지 않는다 —
  /// `.planning/todos/completed/2026-10-03-fcm-initial-message-history-replay.md`.
  Future<void> _startLocalNotifications(
    MessagingService messaging,
    LocalNotificationsService local,
  ) async {
    await local.initialize(onTap: _savePendingRoute);
    final initialMessage = await messaging.getInitialMessage();
    if (!ref.mounted) return;
    if (initialMessage != null) {
      // 기록이 끝난 뒤에만 보관한다 — 보관 뒤 프로세스가 죽어도 재생 0(at-most-once).
      final isFirstDelivery = await _claimInitialMessage(
        initialMessage.messageId,
      );
      if (!ref.mounted || !isFirstDelivery) return;
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

  /// [messageId] 를 처음 보는 초기 메시지로 기록하고 true 를 돌려준다.
  ///
  /// 이미 기록된 id 면 false(최근 앱 복원 재생)다. id 가 null · 빈 문자열이면
  /// 기록 없이 true 다. 저장소 읽기 · 쓰기 실패도 true 다 — 재생 방지는
  /// best-effort 이고 탭 이동을 막지 않는다. 기록은 최근
  /// [kNotificationsHandledInitialMessageIdsLimit] 개만 남기고 오래된 id 부터
  /// 밀어낸다. 로그에는 id · route · payload 를 싣지 않는다.
  Future<bool> _claimInitialMessage(String? messageId) async {
    if (messageId == null || messageId.isEmpty) return true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final handledIds =
          prefs.getStringList(kNotificationsHandledInitialMessageIdsKey) ??
          const <String>[];
      if (handledIds.contains(messageId)) {
        _debugLog('notification initial message replay skipped');
        return false;
      }
      final updatedIds = <String>[...handledIds, messageId];
      final overflow =
          updatedIds.length - kNotificationsHandledInitialMessageIdsLimit;
      await prefs.setStringList(
        kNotificationsHandledInitialMessageIdsKey,
        overflow > 0 ? updatedIds.sublist(overflow) : updatedIds,
      );
      _debugLog('notification initial message recorded');
      return true;
    } on Object catch (e) {
      _debugLog('notification initial message guard failed: ${e.runtimeType}');
      return true;
    }
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

/// debug 빌드에서만 재생 방지 단계 [message] 를 남긴다 (id · release 로그 0).
void _debugLog(String message) {
  if (kDebugMode) debugPrint(message);
}
