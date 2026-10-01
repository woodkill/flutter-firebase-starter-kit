import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../application/notification_route.dart';

part 'local_notifications_service.g.dart';

/// 알림 강조색 — UI-SPEC §Color 예외 1건(OS 알림 색).
///
/// OS 가 그리는 알림이라 Flutter 테마 토큰을 읽을 수 없어 리소스 상수
/// `@color/notification_color`(#673AB7 = `AppTheme.seedColor`)와 같은 값을
/// 상수로 둔다.
const Color _kNotificationColor = Color(0xFF673AB7);

/// `flutter_local_notifications` 를 감싸는 Android 전용 래퍼 (Phase 17 D-01).
///
/// Android 는 앱이 포그라운드일 때 FCM 알림을 표시하지 않으므로 이 래퍼가
/// 같은 채널 · 아이콘 · 색으로 로컬 알림을 띄운다. iOS 는 presentation
/// options 로 OS 가 표시하므로 모든 메서드가 Android 밖에서는 no-op 이다 —
/// iOS 에서 이 플러그인을 초기화하지 않아 권한 프롬프트 · 알림 delegate 를
/// 건드리지 않는다.
///
/// 작은 아이콘은 `res/drawable/ic_notification.xml` 이다 — manifest
/// `default_notification_icon` 과 같은 리소스라 교체하면 백그라운드 ·
/// 포그라운드 알림이 함께 바뀐다(커스터마이징 포인트).
///
/// 플러그인 호출 실패는 best-effort 로 접는다. 진단은 `kDebugMode` 로그에
/// 예외 타입 이름만 남긴다 — 알림 본문이 섞이지 않게 한다.
class LocalNotificationsService {
  /// [LocalNotificationsService] 를 생성한다.
  LocalNotificationsService(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  /// 마지막으로 등록한 채널 이름 · 설명 — [showRemote] 의 채널 인자.
  ///
  /// 채널이 이미 있으면 OS 는 등록된 이름을 쓰므로 이 값은 채널이 아직 없을
  /// 때만 쓰인다.
  String _channelName = kNotificationChannelId;
  String? _channelDescription;

  /// 플러그인을 초기화하고 로컬 알림 탭을 [onTap] 으로 전달한다.
  Future<void> initialize({required void Function(String? payload) onTap}) =>
      _runBestEffort('initialize', () async {
        await _plugin.initialize(
          settings: const InitializationSettings(
            android: AndroidInitializationSettings('ic_notification'),
          ),
          onDidReceiveNotificationResponse: (response) =>
              onTap(response.payload),
        );
      });

  /// 알림 채널을 앱 언어 [name] · [description] 으로 등록한다 (D-31).
  ///
  /// 같은 id 로 다시 등록하면 OS 알림 설정에 보이는 이름 · 설명이 갱신된다.
  Future<void> ensureGeneralChannel({
    required String name,
    required String description,
  }) => _runBestEffort('createNotificationChannel', () async {
    _channelName = name;
    _channelDescription = description;
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          AndroidNotificationChannel(
            kNotificationChannelId,
            name,
            description: description,
            importance: Importance.high,
          ),
        );
  });

  /// 수신 메시지의 [title] · [body] 로 로컬 알림을 띄운다 (D-01).
  ///
  /// 탭하면 [route] 가 payload 로 [initialize] 의 탭 콜백에 돌아온다.
  Future<void> showRemote({
    required String? title,
    required String? body,
    required String? route,
  }) => _runBestEffort('show', () async {
    await _plugin.show(
      id: _nextNotificationId(),
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          kNotificationChannelId,
          _channelName,
          channelDescription: _channelDescription,
          icon: 'ic_notification',
          color: _kNotificationColor,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: route,
    );
  });

  /// 로컬 알림 탭으로 앱이 시작됐다면 그 payload 를 돌려준다. 아니면 null.
  Future<String?> launchPayload() async {
    String? payload;
    await _runBestEffort('getNotificationAppLaunchDetails', () async {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp ?? false) {
        payload = details?.notificationResponse?.payload;
      }
    });
    return payload;
  }

  /// 알림 id — 초 단위 시각으로 만들어 이전 알림을 덮어쓰지 않게 한다.
  int _nextNotificationId() =>
      DateTime.now().millisecondsSinceEpoch ~/ 1000 % 0x7FFFFFFF;

  /// Android 에서만 [call] 을 실행하고 실패하면 조용히 접는다.
  Future<void> _runBestEffort(
    String label,
    Future<void> Function() call,
  ) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await call();
    } on Object catch (e) {
      if (kDebugMode) {
        debugPrint('local notifications $label failed: ${e.runtimeType}');
      }
    }
  }
}

/// [LocalNotificationsService] Provider (Phase 17 D-01).
@Riverpod(keepAlive: true)
LocalNotificationsService localNotificationsService(Ref ref) =>
    LocalNotificationsService(FlutterLocalNotificationsPlugin());
