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

/// 현 계정이 이 기기에 등록한 FCM 토큰 저장 키 (SharedPreferences · Phase 17
/// D-30).
///
/// 끄기 · 로그아웃 · 권한 해제 · 토큰 교체 때 지울 토큰 문서 id 를 기억한다.
/// 로그아웃 때 지운다 — 지우지 못한 문서의 재시도 근거는
/// [kNotificationsPendingTokenDeletionKey] 에 따로 둔다.
/// 값은 그 기기로 알림을 보낼 수 있는 주소이므로 로그에 싣지 않는다.
const String kNotificationsRegisteredTokenKey =
    'notifications_registered_token';

/// 삭제를 확정하지 못한 토큰 문서 기록 저장 키 — 값은 `[uid, token]`
/// (Phase 17 리뷰 WR-03).
///
/// 로그아웃 · 권한 해제 정리가 문서 삭제 **전에** 남기고, 삭제가 확정되면
/// 지운다. 같은 uid 로 다시 로그인한 [NotificationSettingsNotifier.build] 가
/// 삭제를 재시도한다. 다른 uid 의 기록은 그 계정 세션에서 rules 상 지울 수
/// 없으므로, 토큰 폐기([kNotificationsTokenRevokePendingKey])가 확정되면
/// 버린다.
const String kNotificationsPendingTokenDeletionKey =
    'notifications_pending_token_deletion';

/// FCM 토큰 폐기 대기 표식 저장 키 (Phase 17 리뷰 WR-03).
///
/// 이 기기 토큰을 가리키는 문서가 다른 계정 아래 남아 있을 수 있으면 true 다.
/// 표식이 있으면 다음 토큰 등록은 `getToken()` 전에 토큰을 먼저 폐기한다 —
/// 폐기된 토큰으로 보낸 발송은 `registration-token-not-registered` 로 실패하고
/// 서버 발송 정리가 그 문서를 지운다. 이전 계정 문서 삭제가 확정되면 지운다.
const String kNotificationsTokenRevokePendingKey =
    'notifications_token_revoke_pending';

/// Firestore 토큰 문서 쓰기 대기 상한.
///
/// Firestore `set` · `delete` 는 오프라인이면 서버 ack 까지 끝나지 않는다.
/// 상한을 두지 않으면 스위치가 처리 중(비활성)에 머문다. 상한을 넘으면
/// 실패로 처리한다. 로그아웃 경로에서는 바깥의 3초 상한
/// (`AuthRepository.signOutAndResetOnboarding` · D-30)이 먼저 끊으므로 이
/// 상한에 닿지 않는다 — 그 경로는 큐에 남은 쓰기에 기대지 않고, 네트워크
/// 호출 전에 남긴 삭제 대기 기록 · 토큰 폐기 표식으로 다음 기회에 다시
/// 시도한다(리뷰 WR-03).
const Duration _kTokenWriteTimeout = Duration(seconds: 10);

/// 삭제를 확정하지 못한 토큰 문서 하나 (`users/{uid}/fcmTokens/{token}`).
typedef _PendingTokenDeletion = ({String uid, String token});

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
///   값은 false 이고 토큰 등록 · repository 호출은 없다.
/// - **권한은 사용자가 스위치를 켤 때만 요청한다** — [enable] 안 1곳.
///   권한 `authorized` 를 확인하기 전에는 `getToken()` 을 부르지 않는다
///   (Pitfall 3 — 미허용 상태의 getToken 은 SDK 가 프롬프트를 띄울 수 있다).
/// - [enable] · [disable] 은 [guardAsyncValue] 로 감싼다 — 예상 못 한
///   non-AppException 은 Crashlytics 에 1회 기록하고 `failed` 를 돌려준다.
///   repository `Result` 실패는 throw 가 아니라 기록하지 않는다(D-20 ①).
/// - **stale build (리뷰 WR-06):** keepAlive notifier 의 `ref.mounted` 는
///   재빌드 뒤에도 true 다(riverpod 3.2.1 — `ref` 가 요소의 현재 Ref 를
///   돌려준다). 그래서 [build] 는 첫 `await` 전에 `ref.onDispose` 로 묶은
///   빌드 세대 플래그와 [clearForSignOut] 세대를 함께 보고, `await` 뒤마다
///   이전 세대면 부수효과 없이 멈춘다.
///
/// **커스터마이징 포인트:** 토큰 문서 만료 기간은 `kFcmTokenTtl`, 문서
/// 경로 · 스키마는 `FcmTokenRepository` · `FcmToken` 이 정한다.
@Riverpod(keepAlive: true)
class NotificationSettingsNotifier extends _$NotificationSettingsNotifier {
  /// 켜진 동안 FCM 토큰 갱신을 듣는 구독 (D-33 · 토큰 교체).
  StreamSubscription<String>? _tokenRefreshSubscription;

  /// [clearForSignOut] 이 불릴 때마다 1 늘어나는 세대 번호 (리뷰 WR-06).
  ///
  /// 로그아웃 정리가 시작되면 그 전에 시작한 [build] · [enable] · 토큰 갱신
  /// 등록은 이전 uid 로 문서 · 등록 키를 다시 쓰지 않고 멈춘다.
  int _signOutEpoch = 0;

  /// [enable] · [disable] 처리 중이면 true — 앱 복귀 재빌드를 보류한다
  /// (리뷰 WR-05).
  bool _isMutationInFlight = false;

  /// 진행 중인 FCM 토큰 폐기 — 동시 호출이 같은 폐기를 기다리게 한다.
  ///
  /// 폐기가 끝나기 전에 다른 경로가 `getToken()` 으로 받은 새 토큰을 뒤늦은
  /// 두 번째 폐기가 지워 버리는 순서를 막는다.
  Future<bool>? _revokeInFlight;

  /// 정식 사용자면 OS 권한 · opt-in 을 읽고 현 기기 토큰 문서를 맞춘다.
  ///
  /// 앱 시작(`app.dart` 가 활성화) · 앱 복귀(`AppLifecycleState.resumed`) ·
  /// 앱 언어 변경 · 로그인 계정 변경 때마다 다시 실행된다 (D-31 · D-32 ·
  /// D-33):
  /// - 같은 uid 의 삭제 대기 기록이 있으면 문서 삭제를 다시 시도한다 ·
  ///   토큰 폐기 표식이 있으면 폐기를 시도한다(리뷰 WR-03 · 결과 무시).
  /// - 권한 `authorized` 아님 → 등록 토큰 문서 삭제(결과 무시) · 등록 키
  ///   제거 · false. opt-in 은 건드리지 않는다(사용자 의사 보존).
  /// - 권한 `authorized` ∧ opt-in → 토큰 재등록(`expireAt` = 지금 + 30일 ·
  ///   locale = 앱 언어) · 토큰 갱신 구독 · true.
  /// - 재등록 실패 → [NotificationSettingsUpdateException] (섹션 오류 배너 +
  ///   재시도 · Riverpod 기본 재시도도 적용된다).
  @override
  Future<bool> build() async {
    // 리뷰 WR-06 — 첫 await 전에 세대를 묶는다. 재빌드 · dispose 때
    // runOnDispose 가 먼저 불려 이 빌드는 stale 이 된다.
    var isCurrentBuild = true;
    ref.onDispose(() => isCurrentBuild = false);
    final signOutEpoch = _signOutEpoch;
    bool isStale() => !isCurrentBuild || signOutEpoch != _signOutEpoch;

    if (!ref.watch(isFirebaseInitializedProvider)) return false;
    // D-31 — 앱 언어가 바뀌면 재빌드되어 켜진 기기의 토큰 문서 locale 을 갱신한다.
    final localeCode = ref.watch(localeProvider).languageCode;
    final messaging = ref.watch(messagingServiceProvider);
    final uid = await ref.watch(authStateProvider.selectAsync(_regularUidOf));
    if (isStale()) return false;
    if (uid == null) {
      // 로그아웃 정리가 끝내지 못한 토큰 폐기를 한 번 더 시도한다(결과 무시).
      // 다음 계정이 알림을 켜지 않아도 이전 계정 문서가 무효 토큰이 되게 한다.
      final prefs = await SharedPreferences.getInstance();
      _revokeInBackground(prefs, currentUid: null);
      return false;
    }

    // D-32 — 앱 복귀 때마다 OS 권한을 다시 읽는다(앱 밖 설정 변경 반영).
    final lifecycle = AppLifecycleListener(onResume: _onResume);
    ref.onDispose(lifecycle.dispose);
    ref.onDispose(_stopTokenRefresh);

    final prefs = await SharedPreferences.getInstance();
    if (isStale()) return false;
    await _retryPendingDeletion(uid, prefs);
    if (isStale()) return false;
    _revokeInBackground(prefs, currentUid: uid);

    final status = await messaging.getAuthorizationStatus();
    if (isStale()) return false;
    if (status != AuthorizationStatus.authorized) {
      await _forgetRegisteredToken(uid, prefs);
      return false;
    }
    if (!(prefs.getBool(kNotificationsOptInKey) ?? false)) return false;

    final registered = await _register(
      uid,
      localeCode: localeCode,
      isStale: isStale,
    );
    if (isStale()) return false;
    if (!registered) throw const NotificationSettingsUpdateException();
    _startTokenRefresh(uid, isStale);
    return true;
  }

  /// 「알림 받기」 를 켠다 — 권한 요청 → 토큰 등록 (D-03).
  ///
  /// 정식 사용자가 아니면 아무것도 부르지 않고 `failed`. 권한이 거부되면
  /// `permissionDenied` (opt-in 은 남긴다). 예상 못 한 오류는 Crashlytics 에
  /// 1회 기록하고 `failed` — state 는 이전 값 그대로다.
  Future<NotificationToggleResult> enable() =>
      _runToggle(_enable, reason: 'notification_settings_enable');

  /// 「알림 받기」 를 끈다 — 현 기기 토큰 문서 삭제 (D-03).
  ///
  /// 삭제가 실패하면 `failed` 이고 state · opt-in 은 이전 값(켜짐) 그대로다.
  Future<NotificationToggleResult> disable() =>
      _runToggle(_disable, reason: 'notification_settings_disable');

  /// 로그아웃 직전 기기 알림 상태를 처음으로 되돌린다 (Phase 17 D-30).
  ///
  /// `AuthRepository.signOutAndResetOnboarding` 이 3초 상한 · 실패 무시로
  /// 부른다(D-A2 콜백). 상한은 아무 때나 끊을 수 있으므로 **표식 먼저,
  /// 네트워크 나중** 순서다 (리뷰 WR-03):
  /// 1. 진행 중인 build · 등록을 멈추고 꺼짐으로 바꾼다.
  /// 2. 등록 토큰이 있으면 삭제 대기 기록(uid · token)과 토큰 폐기 표식을
  ///    남긴 뒤 opt-in · 등록 키를 지운다 — 다음 로그인 계정은 꺼짐으로
  ///    시작한다.
  /// 3. 토큰 문서를 지운다. 삭제가 확정되면 두 표식을 지운다 — 이전 계정
  ///    문서가 남지 않으므로 토큰을 폐기하지 않는다.
  /// 4. 삭제를 확정하지 못하면 토큰 폐기를 시도하고, 확정되면 폐기 표식만
  ///    지운다. 남은 표식은 같은 uid 재로그인(문서 삭제 재시도)과 다음 토큰
  ///    등록(폐기 먼저)이 이어받는다.
  ///
  /// OS 알림 권한은 건드리지 않는다. 어떤 예외도 던지지 않는다.
  Future<void> clearForSignOut() async {
    _signOutEpoch++;
    try {
      final uid = _currentRegularUid();
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(kNotificationsRegisteredTokenKey);
      _stopTokenRefresh();
      state = const AsyncData(false);
      final pending = (uid != null && token != null)
          ? (uid: uid, token: token)
          : null;
      if (pending != null) await _markPendingDeletion(prefs, pending);
      await prefs.remove(kNotificationsOptInKey);
      await prefs.remove(kNotificationsRegisteredTokenKey);
      if (pending == null) return;
      if (await _deletePendingDocument(prefs, pending)) return;
      await _revokePendingDeviceToken(prefs, currentUid: pending.uid);
    } on Object catch (e) {
      // 토큰 · uid 는 싣지 않는다 — 예외 타입 이름만.
      if (kDebugMode) {
        debugPrint('notification sign-out cleanup failed: ${e.runtimeType}');
      }
    }
  }

  /// [enable] · [disable] 공통 — 처리 중 표시 + [guardAsyncValue].
  Future<NotificationToggleResult> _runToggle(
    Future<NotificationToggleResult> Function() body, {
    required String reason,
  }) async {
    _isMutationInFlight = true;
    try {
      final result = await guardAsyncValue<NotificationToggleResult>(
        body,
        reason: reason,
        crashlytics: ref.read(crashlyticsServiceProvider),
      );
      return _toToggleResult(result);
    } finally {
      _isMutationInFlight = false;
    }
  }

  /// [enable] 본문.
  ///
  /// 첫 await 중에 로그아웃 정리([clearForSignOut])가 끝나면 opt-in 을 쓰지
  /// 않고 `failed` 다 (리뷰 IN-26 — 다음 계정은 꺼짐으로 시작).
  Future<NotificationToggleResult> _enable() async {
    final uid = _currentRegularUid();
    if (uid == null) return NotificationToggleResult.failed;
    final signOutEpoch = _signOutEpoch;
    bool isStale() => signOutEpoch != _signOutEpoch;

    final prefs = await SharedPreferences.getInstance();
    // 정리가 먼저 끝났으면 아무것도 쓰지 않는다 — 키 부재가 정리의 결과다
    // (리뷰 IN-26).
    if (isStale()) return NotificationToggleResult.failed;
    await prefs.setBool(kNotificationsOptInKey, true);

    final status = await ref.read(messagingServiceProvider).requestPermission();
    if (status != AuthorizationStatus.authorized) {
      state = const AsyncData(false);
      return NotificationToggleResult.permissionDenied;
    }

    final registered = await _register(
      uid,
      localeCode: ref.read(localeProvider).languageCode,
      isStale: isStale,
    );
    if (!registered || isStale()) return NotificationToggleResult.failed;
    _startTokenRefresh(uid, isStale);
    state = const AsyncData(true);
    return NotificationToggleResult.enabled;
  }

  /// [disable] 본문.
  ///
  /// opt-in 을 삭제 **전에** 내린다 (리뷰 WR-05) — 삭제 대기 중 재동기화가
  /// 돌더라도 같은 토큰을 다시 등록하지 않는다. 삭제가 실패하면 opt-in 을
  /// 되돌려 「켜짐 유지」 와 맞춘다. 로그아웃 정리([clearForSignOut])와
  /// 겹치면 되돌리지 않고 `failed` 다 (리뷰 WR-07 — 다음 계정은 꺼짐으로 시작).
  /// 정리가 첫 await 중에 끝났으면 opt-in 도 쓰지 않는다 (리뷰 IN-26).
  Future<NotificationToggleResult> _disable() async {
    final uid = _currentRegularUid();
    if (uid == null) return NotificationToggleResult.failed;
    final signOutEpoch = _signOutEpoch;
    bool isStale() => signOutEpoch != _signOutEpoch;

    final prefs = await SharedPreferences.getInstance();
    // 정리가 먼저 끝났으면 아무것도 쓰지 않는다 — 키 부재가 정리의 결과다
    // (리뷰 IN-26).
    if (isStale()) return NotificationToggleResult.failed;
    final token = prefs.getString(kNotificationsRegisteredTokenKey);
    await prefs.setBool(kNotificationsOptInKey, false);
    if (token != null) {
      var isDeleted = false;
      try {
        final result = await _deleteTokenDocument(uid, token);
        isDeleted = result is Success<void>;
      } finally {
        // 로그아웃 정리가 먼저 opt-in 을 지웠으면 되돌리지 않는다 — 다음
        // 계정은 꺼짐으로 시작해야 한다 (D-30 · 리뷰 WR-07).
        if (!isDeleted && !isStale()) {
          await prefs.setBool(kNotificationsOptInKey, true);
        }
      }
      if (!isDeleted || isStale()) return NotificationToggleResult.failed;
    }
    // 정리가 등록 키 · state 를 이미 처음으로 돌렸다 — 건드리지 않는다.
    if (isStale()) return NotificationToggleResult.failed;
    await prefs.remove(kNotificationsRegisteredTokenKey);
    _stopTokenRefresh();
    state = const AsyncData(false);
    return NotificationToggleResult.disabled;
  }

  /// 현 기기 토큰을 `users/{uid}/fcmTokens/{token}` 에 쓰고 등록 키에
  /// 기억한다. 성공하면 true (D-31 · D-33).
  ///
  /// - 토큰 폐기 표식이 있으면 `getToken()` 전에 폐기를 먼저 확정한다 —
  ///   실패하면 등록도 실패다(이전 토큰으로 새 계정을 등록하지 않는다 ·
  ///   리뷰 WR-03). 이때는 전달받은 [token] 도 쓰지 않고 새로 받는다.
  /// - [token] 이 없으면 SDK 에서 받는다 — 권한 `authorized` 를 확인한
  ///   호출부만 부른다(Pitfall 3).
  /// - 등록 키를 쓰기 **전에** 새 토큰으로 바꾼다 — 로그아웃 정리가 이 쓰기와
  ///   겹쳐도 지울 토큰을 안다.
  /// - `expireAt` = 지금 + [kFcmTokenTtl] 로 다시 쓰고, 이전 등록 토큰과
  ///   다르면 그 문서를 지운다(결과 무시 — 이전 토큰은 FCM 이 교체 · 폐기한
  ///   토큰이라 남아도 발송 실패 정리 · TTL 이 지운다).
  /// - [isStale] 이 true 가 되면(재빌드 · 로그아웃 정리) 쓰기 전에 멈추고
  ///   false 를 돌려준다 (리뷰 WR-06).
  Future<bool> _register(
    String uid, {
    required String localeCode,
    required bool Function() isStale,
    String? token,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final hadPendingRevoke =
        prefs.getBool(kNotificationsTokenRevokePendingKey) ?? false;
    if (!await _revokePendingDeviceToken(prefs, currentUid: uid)) return false;
    final newToken = (token != null && !hadPendingRevoke)
        ? token
        : await ref.read(messagingServiceProvider).getToken();
    if (newToken == null || isStale()) return false;

    final previous = prefs.getString(kNotificationsRegisteredTokenKey);
    await prefs.setString(kNotificationsRegisteredTokenKey, newToken);
    if (isStale()) return false;

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
    if (previous != null && previous != newToken) {
      await _deleteTokenDocument(uid, previous);
    }
    return !isStale();
  }

  /// 등록 토큰 문서를 지우고 등록 키를 제거한다 — 권한이 꺼졌을 때 (D-32).
  ///
  /// 삭제 대기 기록 · 토큰 폐기 표식을 먼저 남기고(리뷰 WR-03), 문서 삭제는
  /// 기다리지 않는다(확정되면 표식을 지운다). opt-in 은 남긴다.
  Future<void> _forgetRegisteredToken(
    String uid,
    SharedPreferences prefs,
  ) async {
    final token = prefs.getString(kNotificationsRegisteredTokenKey);
    if (token == null) return;
    final pending = (uid: uid, token: token);
    await _markPendingDeletion(prefs, pending);
    await prefs.remove(kNotificationsRegisteredTokenKey);
    unawaited(
      _deletePendingDocument(prefs, pending).then<void>(
        (_) {},
        onError: (Object e) => _logBackgroundFailure('forget', e),
      ),
    );
  }

  /// 같은 [uid] 의 삭제 대기 기록이 있으면 문서 삭제를 다시 시도한다
  /// (리뷰 WR-03). 결과는 무시한다 — 실패하면 기록이 남아 다음 build 가
  /// 다시 시도한다.
  Future<void> _retryPendingDeletion(
    String uid,
    SharedPreferences prefs,
  ) async {
    final pending = _readPendingDeletion(prefs);
    if (pending == null || pending.uid != uid) return;
    await _deletePendingDocument(prefs, pending);
  }

  /// 삭제 대기 기록 [pending] 과 토큰 폐기 표식을 남긴다 (네트워크 호출 전).
  Future<void> _markPendingDeletion(
    SharedPreferences prefs,
    _PendingTokenDeletion pending,
  ) async {
    await prefs.setStringList(kNotificationsPendingTokenDeletionKey, [
      pending.uid,
      pending.token,
    ]);
    await prefs.setBool(kNotificationsTokenRevokePendingKey, true);
  }

  /// [pending] 문서를 지운다. 삭제가 확정되면 true 이고, 저장된 기록이 아직
  /// [pending] 이면 기록과 토큰 폐기 표식을 지운다 — 이전 계정 문서가
  /// 남지 않으므로 폐기는 필요 없다.
  Future<bool> _deletePendingDocument(
    SharedPreferences prefs,
    _PendingTokenDeletion pending,
  ) async {
    final result = await _deleteTokenDocument(pending.uid, pending.token);
    if (result is! Success<void>) return false;
    if (_readPendingDeletion(prefs) == pending) {
      await prefs.remove(kNotificationsPendingTokenDeletionKey);
      await prefs.remove(kNotificationsTokenRevokePendingKey);
    }
    return true;
  }

  /// 저장된 삭제 대기 기록. 없거나 형식이 어긋나면 null.
  _PendingTokenDeletion? _readPendingDeletion(SharedPreferences prefs) {
    final raw = prefs.getStringList(kNotificationsPendingTokenDeletionKey);
    if (raw == null || raw.length != 2) return null;
    return (uid: raw[0], token: raw[1]);
  }

  /// 토큰 폐기 표식이 있으면 FCM 토큰을 폐기한다. 표식이 없거나 폐기가
  /// 확정되면 true (리뷰 WR-03).
  ///
  /// 폐기가 확정된 뒤 [currentUid] 와 다른 uid 의 삭제 대기 기록은 버린다 —
  /// 이 세션에서는 rules 상 지울 수 없고, 그 문서는 이제 무효 토큰이라 서버
  /// 발송 정리가 지운다. [currentUid] 가 null(로그아웃 상태)이면 누가 다시
  /// 로그인할지 모르므로 기록을 남긴다.
  Future<bool> _revokePendingDeviceToken(
    SharedPreferences prefs, {
    required String? currentUid,
  }) async {
    if (prefs.getBool(kNotificationsTokenRevokePendingKey) ?? false) {
      final isRevoked = await (_revokeInFlight ??= _revokeDeviceToken(prefs));
      if (!isRevoked) return false;
    }
    final pending = _readPendingDeletion(prefs);
    if (currentUid != null && pending != null && pending.uid != currentUid) {
      await prefs.remove(kNotificationsPendingTokenDeletionKey);
    }
    return true;
  }

  /// [_revokePendingDeviceToken] 을 기다리지 않고 시도한다 (결과 무시 ·
  /// 예외는 debug 로그로만 흡수).
  void _revokeInBackground(
    SharedPreferences prefs, {
    required String? currentUid,
  }) {
    unawaited(
      _revokePendingDeviceToken(prefs, currentUid: currentUid).then<void>(
        (_) {},
        onError: (Object e) => _logBackgroundFailure('revoke', e),
      ),
    );
  }

  /// 기다리지 않는 정리 작업 [label] 의 실패를 debug 로그에 남긴다 —
  /// 토큰 · uid 는 싣지 않는다(예외 타입 이름만).
  void _logBackgroundFailure(String label, Object error) {
    if (kDebugMode) {
      debugPrint('notification $label cleanup failed: ${error.runtimeType}');
    }
  }

  /// FCM 토큰을 폐기하고, 확정되면 폐기 표식을 지운다.
  Future<bool> _revokeDeviceToken(SharedPreferences prefs) async {
    try {
      final isRevoked = await ref.read(messagingServiceProvider).deleteToken();
      if (isRevoked) await prefs.remove(kNotificationsTokenRevokePendingKey);
      return isRevoked;
    } finally {
      _revokeInFlight = null;
    }
  }

  /// FCM 토큰 갱신 구독을 (다시) 시작한다 — 새 토큰이 오면 재등록 (D-33).
  ///
  /// [isStale] 은 구독을 시작한 build · [enable] 의 세대다 — 세대가 지나면
  /// 갱신을 등록하지 않는다 (리뷰 WR-06).
  void _startTokenRefresh(String uid, bool Function() isStale) {
    _stopTokenRefresh();
    _tokenRefreshSubscription = ref
        .read(messagingServiceProvider)
        .onTokenRefresh
        .listen((token) => unawaited(_onTokenRefreshed(uid, token, isStale)));
  }

  /// FCM 토큰 갱신 구독을 멈춘다.
  void _stopTokenRefresh() {
    unawaited(_tokenRefreshSubscription?.cancel());
    _tokenRefreshSubscription = null;
  }

  /// 새 토큰 [token] 을 등록하고 옛 문서를 지운다. 끈 뒤(opt-in false) ·
  /// 세대가 지난 뒤([isStale])에 도착한 갱신은 무시한다. best-effort — 실패는
  /// 다음 동기화가 맞춘다.
  Future<void> _onTokenRefreshed(
    String uid,
    String token,
    bool Function() isStale,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(kNotificationsOptInKey) ?? false)) return;
      if (isStale()) return;
      await _register(
        uid,
        localeCode: ref.read(localeProvider).languageCode,
        token: token,
        isStale: isStale,
      );
    } on Object catch (e) {
      // 토큰 · uid 는 싣지 않는다 — 예외 타입 이름만.
      if (kDebugMode) {
        debugPrint('notification refresh sync failed: ${e.runtimeType}');
      }
    }
  }

  /// 앱 복귀 — 권한 · opt-in 을 다시 읽도록 재빌드한다 (D-32).
  ///
  /// 스위치 처리 중이면 보류한다 (리뷰 WR-05) — 처리 끝에서 상태를 확정하고,
  /// Android 13+ 권한 다이얼로그가 일으키는 복귀로 등록이 2중 실행되지 않게
  /// 한다.
  void _onResume() {
    if (_isMutationInFlight) return;
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
