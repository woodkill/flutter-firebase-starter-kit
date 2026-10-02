import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/providers/firebase_providers.dart';

part 'messaging_service.g.dart';

/// FCM 토큰 폐기([MessagingService.deleteToken]) 대기 상한.
///
/// 폐기는 FCM 서버 왕복이 필요해 오프라인이면 끝나지 않을 수 있다. 상한을
/// 넘으면 실패(false)로 접는다 — 호출부는 폐기 대기 표식을 남겨 다음 기회에
/// 다시 시도한다.
const Duration kFcmDeleteTokenTimeout = Duration(seconds: 10);

/// Firebase Cloud Messaging SDK 를 감싸는 no-op 래퍼 (Phase 17 D-01 · D-15).
///
/// `CrashlyticsService` 와 같은 형식이다.
/// 1. Firebase 미초기화([isEnabled]=false)면 SDK 를 건드리지 않고 기본값을
///    돌려준다 — 권한 `notDetermined` · 토큰 null · 스트림 empty · 초기 메시지
///    null (Phase 1 D-13 — Firebase 없이도 앱 정상 실행).
/// 2. 초기화 이후 SDK 호출이 실패해도 같은 기본값으로 접는다(best-effort).
///    진단은 `kDebugMode` 로그에 **예외 타입 이름만** 남긴다 — 예외 message 에
///    토큰이 섞일 수 있어서다.
///
/// 이 래퍼는 권한 확인 없이 [getToken] 을 스스로 부르지 않는다. 호출 시점은
/// 알림 설정 notifier(plan 15)가 권한 `authorized` 를 확인한 뒤로 한정한다
/// (Pitfall 3).
class MessagingService {
  /// [MessagingService] 를 생성한다.
  const MessagingService(this._messaging, {required this.isEnabled});

  final FirebaseMessaging? _messaging;

  /// Firebase 초기화 상태. false 이면 모든 메서드가 no-op 이다.
  final bool isEnabled;

  /// 현재 알림 권한 상태를 돌려준다 — 권한 프롬프트를 띄우지 않는다.
  ///
  /// no-op · 실패 시 [AuthorizationStatus.notDetermined].
  Future<AuthorizationStatus> getAuthorizationStatus() => _runBestEffort(
    'getNotificationSettings',
    AuthorizationStatus.notDetermined,
    (messaging) async =>
        (await messaging.getNotificationSettings()).authorizationStatus,
  );

  /// 알림 권한을 요청하고 결과 상태를 돌려준다.
  ///
  /// Android 13+ 는 `POST_NOTIFICATIONS` 런타임 권한, iOS 는 alert · badge ·
  /// sound 권한을 요청한다. no-op · 실패 시 [AuthorizationStatus.notDetermined].
  Future<AuthorizationStatus> requestPermission() => _runBestEffort(
    'requestPermission',
    AuthorizationStatus.notDetermined,
    (messaging) async =>
        (await messaging.requestPermission()).authorizationStatus,
  );

  /// 이 기기의 FCM registration token 을 돌려준다.
  ///
  /// **권한이 `authorized` 인 것을 확인한 뒤에만 부를 것** — 미허용 상태에서
  /// 부르면 SDK 가 권한 프롬프트를 스스로 띄울 수 있다(Pitfall 3).
  /// 반환값은 그 기기로 알림을 보낼 수 있는 주소이므로 로그 · Crashlytics ·
  /// 화면에 싣지 않는다. no-op · 실패 시 null.
  Future<String?> getToken() => _runBestEffort<String?>(
    'getToken',
    null,
    (messaging) => messaging.getToken(),
  );

  /// 이 기기의 FCM registration token 을 폐기한다. 폐기가 확정되면 true.
  ///
  /// 폐기된 토큰으로 보낸 발송은 실패한다(SDK 문서 「Messages sent by the
  /// server to this token will fail.」). 다음 [getToken] 은 새 토큰을 준다.
  /// 로그아웃 정리가 이전 계정의 토큰 문서를 지우지 못했을 때, 그 문서가 같은
  /// 기기의 다음 계정에 알림을 흘리지 않게 하려고 쓴다 (Phase 17 리뷰 WR-03).
  /// [kFcmDeleteTokenTimeout] 을 넘거나 no-op · 실패면 false.
  Future<bool> deleteToken() =>
      _runBestEffort<bool>('deleteToken', false, (messaging) async {
        await messaging.deleteToken().timeout(kFcmDeleteTokenTimeout);
        return true;
      });

  /// 토큰이 새로 발급될 때마다 새 토큰을 흘린다.
  ///
  /// 앱 시작 때마다 한 번 · 토큰 교체 때 emit 된다. 스트림 오류는 흡수한다.
  /// no-op 이면 즉시 끝나는 빈 스트림.
  Stream<String> get onTokenRefresh => _guardStream(
    'onTokenRefresh',
    () => _messaging?.onTokenRefresh ?? const Stream<String>.empty(),
  );

  /// 앱이 포그라운드일 때 받은 메시지를 흘린다.
  ///
  /// no-op 이면 즉시 끝나는 빈 스트림.
  Stream<RemoteMessage> get onMessage =>
      _guardStream('onMessage', () => FirebaseMessaging.onMessage);

  /// 백그라운드 상태에서 알림을 탭해 앱이 열릴 때 메시지를 흘린다.
  ///
  /// no-op 이면 즉시 끝나는 빈 스트림.
  Stream<RemoteMessage> get onMessageOpenedApp => _guardStream(
    'onMessageOpenedApp',
    () => FirebaseMessaging.onMessageOpenedApp,
  );

  /// 종료 상태에서 알림을 탭해 앱이 시작됐다면 그 메시지를 돌려준다.
  ///
  /// no-op · 실패 · 해당 없음이면 null.
  Future<RemoteMessage?> getInitialMessage() => _runBestEffort<RemoteMessage?>(
    'getInitialMessage',
    null,
    (messaging) => messaging.getInitialMessage(),
  );

  /// iOS 포그라운드 알림 표시 옵션(alert · badge · sound)을 켠다 (D-01).
  ///
  /// iOS 는 이 옵션이 꺼져 있으면 포그라운드에서 알림을 표시하지 않는다.
  /// Android 에서는 SDK 가 무시한다. no-op · 실패 시 아무것도 하지 않는다.
  Future<void> setForegroundPresentationOptions() => _runBestEffort<void>(
    'setForegroundNotificationPresentationOptions',
    null,
    (messaging) => messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    ),
  );

  /// SDK 호출을 실행하고 실패하면 [fallback] 으로 접는다.
  Future<T> _runBestEffort<T>(
    String label,
    T fallback,
    Future<T> Function(FirebaseMessaging messaging) call,
  ) async {
    final messaging = _messaging;
    if (!isEnabled || messaging == null) return fallback;
    try {
      return await call(messaging);
    } on Object catch (e) {
      _logFailure(label, e);
      return fallback;
    }
  }

  /// SDK 스트림을 열고, 여는 중 throw 와 스트림 오류를 흡수한다.
  Stream<T> _guardStream<T>(String label, Stream<T> Function() open) {
    if (!isEnabled || _messaging == null) return Stream<T>.empty();
    try {
      return open().handleError((Object e) => _logFailure(label, e));
    } on Object catch (e) {
      _logFailure(label, e);
      return Stream<T>.empty();
    }
  }

  /// 실패 진단을 debug 로그에 남긴다 — 예외 타입 이름만 (PII 0).
  void _logFailure(String label, Object error) {
    if (kDebugMode) {
      debugPrint('messaging $label failed: ${error.runtimeType}');
    }
  }
}

/// [MessagingService] Provider (Phase 17 D-01).
///
/// Firebase 미초기화 시 `isEnabled=false` 로 생성되어 모든 메서드가 no-op 이다.
@Riverpod(keepAlive: true)
MessagingService messagingService(Ref ref) {
  final isInitialized = ref.watch(isFirebaseInitializedProvider);
  if (!isInitialized) {
    return const MessagingService(null, isEnabled: false);
  }
  return MessagingService(
    ref.watch(firebaseMessagingProvider),
    isEnabled: true,
  );
}
