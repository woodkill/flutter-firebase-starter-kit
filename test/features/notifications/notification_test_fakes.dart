// Phase 17 Plan 17-16 — 알림 수신 · 탭 테스트 공용 fake (T-17-PUSH).
//
// firebase_messaging 의 `onMessage` · `onMessageOpenedApp` 은 static getter 라
// 인스턴스 mock 이 불가하다 — 래퍼 [MessagingService] 를 통째로 fake 로 바꾼다
// (STATE Wave 4 메모 ①). 로컬 알림 플러그인도 래퍼
// [LocalNotificationsService] 를 fake 로 바꿔 호출 인자를 기록한다.

import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_starter_kit/core/router/app_routes.dart';
import 'package:flutter_starter_kit/features/notifications/data/local_notifications_service.dart';
import 'package:flutter_starter_kit/features/notifications/data/messaging_service.dart';
import 'package:flutter_starter_kit/features/notifications/presentation/pending_notification_route_listener.dart';
import 'package:go_router/go_router.dart';

/// 스트림을 테스트가 직접 흘리는 [MessagingService] fake.
class FakeMessagingService implements MessagingService {
  /// [initialMessage] 는 [getInitialMessage] 가 돌려줄 종료 상태 탭 메시지다.
  FakeMessagingService({this.initialMessage});

  /// 포그라운드 수신 스트림 (테스트가 add 한다).
  final StreamController<RemoteMessage> foreground =
      StreamController<RemoteMessage>.broadcast();

  /// 백그라운드 탭 스트림 (테스트가 add 한다).
  final StreamController<RemoteMessage> openedApp =
      StreamController<RemoteMessage>.broadcast();

  /// [getInitialMessage] 반환값.
  RemoteMessage? initialMessage;

  /// [getInitialMessage] 호출 횟수.
  int initialMessageCalls = 0;

  /// [setForegroundPresentationOptions] 호출 횟수.
  int presentationOptionsCalls = 0;

  @override
  bool get isEnabled => true;

  @override
  Stream<RemoteMessage> get onMessage => foreground.stream;

  @override
  Stream<RemoteMessage> get onMessageOpenedApp => openedApp.stream;

  @override
  Future<RemoteMessage?> getInitialMessage() async {
    initialMessageCalls++;
    return initialMessage;
  }

  @override
  Future<void> setForegroundPresentationOptions() async {
    presentationOptionsCalls++;
  }

  @override
  Stream<String> get onTokenRefresh => const Stream<String>.empty();

  @override
  Future<AuthorizationStatus> getAuthorizationStatus() async =>
      AuthorizationStatus.notDetermined;

  @override
  Future<AuthorizationStatus> requestPermission() async =>
      AuthorizationStatus.notDetermined;

  @override
  Future<String?> getToken() async => null;

  /// 스트림을 닫는다.
  Future<void> close() async {
    await foreground.close();
    await openedApp.close();
  }
}

/// [LocalNotificationsService.showRemote] 1회 호출 기록.
typedef ShownNotification = ({String? title, String? body, String? route});

/// [LocalNotificationsService.ensureGeneralChannel] 1회 호출 기록.
typedef RegisteredChannel = ({String name, String description});

/// 호출을 기록하는 [LocalNotificationsService] fake.
class FakeLocalNotificationsService implements LocalNotificationsService {
  /// [launchPayloadValue] 는 [launchPayload] 가 돌려줄 값이다.
  FakeLocalNotificationsService({this.launchPayloadValue});

  /// [launchPayload] 반환값 (로컬 알림 탭으로 앱이 시작됐을 때의 payload).
  String? launchPayloadValue;

  /// [initialize] 에 넘어온 탭 콜백 — 테스트가 탭 응답을 흉내 낼 때 부른다.
  void Function(String? payload)? onTap;

  /// [showRemote] 호출 기록.
  final List<ShownNotification> shown = <ShownNotification>[];

  /// [ensureGeneralChannel] 호출 기록.
  final List<RegisteredChannel> channels = <RegisteredChannel>[];

  /// [launchPayload] 호출 횟수.
  int launchPayloadCalls = 0;

  @override
  Future<void> initialize({
    required void Function(String? payload) onTap,
  }) async {
    this.onTap = onTap;
  }

  @override
  Future<void> ensureGeneralChannel({
    required String name,
    required String description,
  }) async {
    channels.add((name: name, description: description));
  }

  @override
  Future<void> showRemote({
    required String? title,
    required String? body,
    required String? route,
  }) async {
    shown.add((title: title, body: body, route: route));
  }

  @override
  Future<String?> launchPayload() async {
    launchPayloadCalls++;
    return launchPayloadValue;
  }
}

/// 알림 제목 · 본문 · data 로 [RemoteMessage] 를 만든다.
RemoteMessage buildRemoteMessage({
  String? title,
  String? body,
  Map<String, dynamic> data = const <String, dynamic>{},
}) => RemoteMessage(
  notification: title == null && body == null
      ? null
      : RemoteNotification(title: title, body: body),
  data: data,
);

/// 홈 화면 표지 문구 (테스트 라우터).
const String kTestHomeLabel = 'home-screen';

/// 스플래시 화면 표지 문구 (테스트 라우터).
const String kTestSplashLabel = 'splash-screen';

/// 설정 화면 표지 문구 (테스트 라우터).
const String kTestSettingsLabel = 'settings-screen';

/// 홈에 [PendingNotificationRouteListener] 를 단 테스트 라우터를 만든다.
///
/// 실제 홈처럼 리스너는 홈 트리 안에만 있다 — 스플래시 · 설정에는 없다.
GoRouter buildNotificationTestRouter({
  String initialLocation = AppRoutes.home,
}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    GoRoute(
      path: AppRoutes.home,
      builder: (context, state) => const Scaffold(
        body: Column(
          children: [PendingNotificationRouteListener(), Text(kTestHomeLabel)],
        ),
      ),
    ),
    GoRoute(
      path: AppRoutes.splash,
      builder: (context, state) => const Scaffold(body: Text(kTestSplashLabel)),
    ),
    GoRoute(
      path: AppRoutes.settings,
      builder: (context, state) =>
          const Scaffold(body: Text(kTestSettingsLabel)),
    ),
  ],
);
