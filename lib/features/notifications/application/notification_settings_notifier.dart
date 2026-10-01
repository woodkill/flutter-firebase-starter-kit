import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
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
  @override
  Future<bool> build() async {
    if (!ref.watch(isFirebaseInitializedProvider)) return false;
    final messaging = ref.watch(messagingServiceProvider);
    final uid = await ref.watch(authStateProvider.selectAsync(_regularUidOf));
    if (uid == null) return false;

    final prefs = await SharedPreferences.getInstance();
    final optIn = prefs.getBool(kNotificationsOptInKey) ?? false;
    if (!optIn) return false;
    final status = await messaging.getAuthorizationStatus();
    return status == AuthorizationStatus.authorized;
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
    state = const AsyncData(false);
    return NotificationToggleResult.disabled;
  }

  /// 현 기기 토큰을 받아 `users/{uid}/fcmTokens/{token}` 에 쓰고 등록 키에
  /// 기억한다. 성공하면 true.
  ///
  /// 권한 `authorized` 를 확인한 호출부만 부른다(Pitfall 3).
  Future<bool> _register(String uid, {required String localeCode}) async {
    final token = await ref.read(messagingServiceProvider).getToken();
    if (token == null) return false;

    final result = await _writeWithTimeout(
      () => ref
          .read(fcmTokenRepositoryProvider)
          .upsert(
            uid: uid,
            token: FcmToken.forDevice(
              token: token,
              platform: _devicePlatform(),
              locale: normalizeFcmLocale(localeCode),
              now: DateTime.now(),
            ),
          ),
    );
    if (result is! Success<void>) return false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kNotificationsRegisteredTokenKey, token);
    return true;
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
