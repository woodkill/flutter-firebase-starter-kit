import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/crashlytics/crashlytics_service.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/error/guard_result.dart';
import '../../../core/error/result.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../../core/providers/locale_provider.dart';
import '../data/fcm_token_repository.dart';
import '../data/messaging_service.dart';
import '../domain/fcm_token.dart';

part 'notification_settings_notifier.g.dart';

/// 로컬 알림 opt-in 저장 키 (SharedPreferences · Phase 17 D-03).
///
/// 사용자가 「알림 받기」 를 켜려고 한 적이 있으면 true 다. 권한 거부로
/// 꺼짐에 머물러도 true 로 남아, 나중에 OS 설정에서 권한을 허용하면 앱 복귀
/// 동기화(D-32)가 조용히 켠다.
const String kNotificationsOptInKey = 'notifications_opt_in';

/// 현 기기에 등록한 FCM 토큰 저장 키 (SharedPreferences · Phase 17 D-30).
///
/// 끄기 · 로그아웃 · 권한 해제 · 토큰 교체 때 지울 토큰 문서 id 를 기억한다.
/// 값은 그 기기로 알림을 보낼 수 있는 주소이므로 로그에 싣지 않는다.
const String kNotificationsRegisteredTokenKey =
    'notifications_registered_token';

/// Firestore 토큰 문서 쓰기 대기 상한.
///
/// Firestore `set` · `delete` 는 오프라인이면 서버 ack 까지 끝나지 않는다.
/// 상한을 두지 않으면 스위치가 처리 중(비활성)에 머문다. 상한을 넘으면
/// 실패로 처리한다 — 쓰기 자체는 로컬 큐에 남아 연결되면 전송된다.
const Duration _kTokenWriteTimeout = Duration(seconds: 10);

/// 「알림 받기」 스위치 처리 결과 (Phase 17 D-03).
///
/// 섹션이 결과별 SnackBar 를 고른다 — 성공(`enabled` · `disabled`)은
/// SnackBar 없이 스위치 상태만 바뀐다.
enum NotificationToggleResult {
  /// 권한 허용 · 토큰 등록 완료 — 켜짐.
  enabled,

  /// 토큰 문서 삭제 완료 — 꺼짐.
  disabled,

  /// OS 권한 거부 — 꺼짐 유지 + 권한 안내 SnackBar.
  permissionDenied,

  /// 처리 실패 — 이전 값 유지 + `errorNotificationsUpdateFailed` SnackBar.
  failed,
}

/// 설정 「알림 받기」 스위치 상태 · 기기 토큰 등록을 관리하는 앱 수명
/// notifier (Phase 17 D-02 · D-03 · D-20 ②).
///
/// - **값** = OS 알림 권한 `authorized` ∧ 로컬 opt-in
///   ([kNotificationsOptInKey]).
/// - **정식 사용자만** 토큰을 저장한다. Firebase 미초기화 · 미로그인 · 익명이면
///   값은 false 이고 SDK · repository 를 부르지 않는다.
/// - **권한은 사용자가 스위치를 켤 때만 요청한다** — [enable] 안 1곳.
///   권한 `authorized` 를 확인하기 전에는 `getToken()` 을 부르지 않는다
///   (Pitfall 3 — 미허용 상태의 getToken 은 SDK 가 프롬프트를 띄울 수 있다).
/// - [enable] · [disable] 은 [guardAsyncValue] 로 감싼다 — 예상 못 한
///   non-AppException 은 Crashlytics 에 1회 기록하고 `failed` 를 돌려준다.
///   repository `Result` 실패는 throw 가 아니라 기록하지 않는다(D-20 ①).
///
/// **커스터마이징 포인트:** 토큰 문서 만료 기간은 `kFcmTokenTtl`, 문서
/// 경로 · 스키마는 `FcmTokenRepository` · `FcmToken` 이 정한다.
@Riverpod(keepAlive: true)
class NotificationSettingsNotifier extends _$NotificationSettingsNotifier {
  /// 켜진 동안 FCM 토큰 갱신을 듣는 구독 (D-33 · 토큰 교체).
  StreamSubscription<String>? _tokenRefreshSubscription;

  /// 정식 사용자면 OS 권한 · opt-in 을 읽고 현 기기 토큰 문서를 맞춘다.
  ///
  /// 앱 시작(`app.dart` 가 활성화) · 앱 복귀(`AppLifecycleState.resumed`) ·
  /// 앱 언어 변경 · 로그인 계정 변경 때마다 다시 실행된다 (D-31 · D-32 ·
  /// D-33):
  /// - 권한 `authorized` 아님 → 등록 토큰 문서 삭제(결과 무시) · 등록 키
  ///   제거 · false. opt-in 은 건드리지 않는다(사용자 의사 보존).
  /// - 권한 `authorized` ∧ opt-in → 토큰 재등록(`expireAt` = 지금 + 30일 ·
  ///   locale = 앱 언어) · 토큰 갱신 구독 · true.
  /// - 재등록 실패 → [NotificationSettingsUpdateException] (섹션 오류 배너 +
  ///   재시도 · Riverpod 기본 재시도도 적용된다).
  @override
  Future<bool> build() async {
    if (!ref.watch(isFirebaseInitializedProvider)) return false;
    // D-31 — 앱 언어가 바뀌면 재빌드되어 켜진 기기의 토큰 문서 locale 을 갱신한다.
    final localeCode = ref.watch(localeProvider).languageCode;
    final messaging = ref.watch(messagingServiceProvider);
    final uid = await ref.watch(authStateProvider.selectAsync(_regularUidOf));
    if (uid == null || !ref.mounted) return false;

    // D-32 — 앱 복귀 때마다 OS 권한을 다시 읽는다(앱 밖 설정 변경 반영).
    final lifecycle = AppLifecycleListener(onResume: _onResume);
    ref.onDispose(lifecycle.dispose);
    ref.onDispose(_stopTokenRefresh);

    final prefs = await SharedPreferences.getInstance();
    final status = await messaging.getAuthorizationStatus();
    if (!ref.mounted) return false;
    if (status != AuthorizationStatus.authorized) {
      await _forgetRegisteredToken(uid, prefs);
      return false;
    }
    if (!(prefs.getBool(kNotificationsOptInKey) ?? false)) return false;

    if (!await _register(uid, localeCode: localeCode)) {
      throw const NotificationSettingsUpdateException();
    }
    if (!ref.mounted) return false;
    _startTokenRefresh(uid);
    return true;
  }

  /// 「알림 받기」 를 켠다 — 권한 요청 → 토큰 등록 (D-03).
  ///
  /// 정식 사용자가 아니면 아무것도 부르지 않고 `failed`. 권한이 거부되면
  /// `permissionDenied` (opt-in 은 남긴다). 예상 못 한 오류는 Crashlytics 에
  /// 1회 기록하고 `failed` — state 는 이전 값 그대로다.
  Future<NotificationToggleResult> enable() async {
    final result = await guardAsyncValue<NotificationToggleResult>(
      _enable,
      reason: 'notification_settings_enable',
      crashlytics: ref.read(crashlyticsServiceProvider),
    );
    return _toToggleResult(result);
  }

  /// 「알림 받기」 를 끈다 — 현 기기 토큰 문서 삭제 (D-03).
  ///
  /// 삭제가 실패하면 `failed` 이고 state 는 이전 값(켜짐) 그대로다.
  Future<NotificationToggleResult> disable() async {
    final result = await guardAsyncValue<NotificationToggleResult>(
      _disable,
      reason: 'notification_settings_disable',
      crashlytics: ref.read(crashlyticsServiceProvider),
    );
    return _toToggleResult(result);
  }

  /// [enable] 본문.
  Future<NotificationToggleResult> _enable() async {
    final uid = _currentRegularUid();
    if (uid == null) return NotificationToggleResult.failed;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kNotificationsOptInKey, true);

    final status = await ref.read(messagingServiceProvider).requestPermission();
    if (status != AuthorizationStatus.authorized) {
      state = const AsyncData(false);
      return NotificationToggleResult.permissionDenied;
    }

    final registered = await _register(
      uid,
      localeCode: ref.read(localeProvider).languageCode,
    );
    if (!registered) return NotificationToggleResult.failed;
    _startTokenRefresh(uid);
    state = const AsyncData(true);
    return NotificationToggleResult.enabled;
  }

  /// [disable] 본문.
  Future<NotificationToggleResult> _disable() async {
    final uid = _currentRegularUid();
    if (uid == null) return NotificationToggleResult.failed;

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(kNotificationsRegisteredTokenKey);
    if (token != null) {
      final result = await _deleteTokenDocument(uid, token);
      if (result is! Success<void>) return NotificationToggleResult.failed;
    }
    await prefs.setBool(kNotificationsOptInKey, false);
    await prefs.remove(kNotificationsRegisteredTokenKey);
    _stopTokenRefresh();
    state = const AsyncData(false);
    return NotificationToggleResult.disabled;
  }

  /// 현 기기 토큰을 `users/{uid}/fcmTokens/{token}` 에 쓰고 등록 키에
  /// 기억한다. 성공하면 true (D-31 · D-33).
  ///
  /// [token] 이 없으면 SDK 에서 받는다 — 권한 `authorized` 를 확인한 호출부만
  /// 부른다(Pitfall 3). `expireAt` = 지금 + [kFcmTokenTtl] 로 다시 쓰고,
  /// 이전 등록 토큰과 다르면 그 문서를 지운다(결과 무시 — 남은 문서는 TTL ·
  /// 발송 실패 정리가 지운다).
  Future<bool> _register(
    String uid, {
    required String localeCode,
    String? token,
  }) async {
    final newToken =
        token ?? await ref.read(messagingServiceProvider).getToken();
    if (newToken == null) return false;

    final result = await _writeWithTimeout(
      () => ref
          .read(fcmTokenRepositoryProvider)
          .upsert(
            uid: uid,
            token: FcmToken.forDevice(
              token: newToken,
              platform: _devicePlatform(),
              locale: normalizeFcmLocale(localeCode),
              now: DateTime.now(),
            ),
          ),
    );
    if (result is! Success<void>) return false;

    final prefs = await SharedPreferences.getInstance();
    final previous = prefs.getString(kNotificationsRegisteredTokenKey);
    if (previous != null && previous != newToken) {
      await _deleteTokenDocument(uid, previous);
    }
    await prefs.setString(kNotificationsRegisteredTokenKey, newToken);
    return true;
  }

  /// 등록 토큰 문서를 지우고 등록 키를 제거한다 — 권한이 꺼졌을 때 (D-32).
  ///
  /// 문서 삭제는 기다리지 않는다(결과 무시 · 오프라인이면 연결 뒤 전송).
  /// opt-in 은 남긴다.
  Future<void> _forgetRegisteredToken(
    String uid,
    SharedPreferences prefs,
  ) async {
    final token = prefs.getString(kNotificationsRegisteredTokenKey);
    if (token == null) return;
    await prefs.remove(kNotificationsRegisteredTokenKey);
    unawaited(_deleteTokenDocument(uid, token));
  }

  /// FCM 토큰 갱신 구독을 (다시) 시작한다 — 새 토큰이 오면 재등록 (D-33).
  void _startTokenRefresh(String uid) {
    _stopTokenRefresh();
    _tokenRefreshSubscription = ref
        .read(messagingServiceProvider)
        .onTokenRefresh
        .listen((token) => unawaited(_onTokenRefreshed(uid, token)));
  }

  /// FCM 토큰 갱신 구독을 멈춘다.
  void _stopTokenRefresh() {
    unawaited(_tokenRefreshSubscription?.cancel());
    _tokenRefreshSubscription = null;
  }

  /// 새 토큰 [token] 을 등록하고 옛 문서를 지운다. 끈 뒤(opt-in false)에
  /// 도착한 갱신은 무시한다. best-effort — 실패는 다음 동기화가 맞춘다.
  Future<void> _onTokenRefreshed(String uid, String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(kNotificationsOptInKey) ?? false)) return;
      if (!ref.mounted) return;
      await _register(
        uid,
        localeCode: ref.read(localeProvider).languageCode,
        token: token,
      );
    } on Object catch (e) {
      // 토큰 · uid 는 싣지 않는다 — 예외 타입 이름만.
      if (kDebugMode) {
        debugPrint('notification refresh sync failed: ${e.runtimeType}');
      }
    }
  }

  /// 앱 복귀 — 권한 · opt-in 을 다시 읽도록 재빌드한다 (D-32).
  void _onResume() {
    ref.invalidateSelf();
  }

  /// `users/{uid}/fcmTokens/{token}` 문서를 지운다 (쓰기 대기 상한 적용).
  Future<Result<void>> _deleteTokenDocument(String uid, String token) =>
      _writeWithTimeout(
        () =>
            ref.read(fcmTokenRepositoryProvider).delete(uid: uid, token: token),
      );

  /// repository 쓰기를 [_kTokenWriteTimeout] 안에서 기다린다.
  ///
  /// 상한을 넘으면 [NotificationSettingsUpdateException] 실패로 접는다
  /// (오프라인 — 기록 대상 아님).
  Future<Result<void>> _writeWithTimeout(
    Future<Result<void>> Function() write,
  ) async {
    try {
      return await write().timeout(_kTokenWriteTimeout);
    } on TimeoutException catch (e) {
      return Result<void>.failure(
        NotificationSettingsUpdateException(cause: e),
      );
    }
  }

  /// 현재 정식(비익명) 사용자 uid. Firebase 미초기화 · 미로그인 · 익명이면
  /// null.
  String? _currentRegularUid() {
    if (!ref.read(isFirebaseInitializedProvider)) return null;
    return _regularUidOf(ref.read(authStateProvider).value);
  }
}

/// [user] 가 정식(비익명) 사용자면 uid, 아니면 null (D-02 정정).
String? _regularUidOf(fb.User? user) =>
    (user == null || user.isAnonymous) ? null : user.uid;

/// 토큰 문서 `platform` 값 — `ios` 또는 `android` (rules 지원 집합).
String _devicePlatform() =>
    defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

/// [guardAsyncValue] 결과를 토글 결과로 접는다 — 오류는 `failed`.
NotificationToggleResult _toToggleResult(
  AsyncValue<NotificationToggleResult> result,
) => switch (result) {
  AsyncData(:final value) => value,
  _ => NotificationToggleResult.failed,
};
