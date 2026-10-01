import 'dart:async';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../auth/auth_strategies_registry.dart';
import '../crashlytics/crashlytics_service.dart';
import '../providers/firebase_providers.dart';
import 'feature_flag.dart';

part 'feature_flags_provider.g.dart';

/// Remote Config 의 [FeatureFlag] 값을 노출하는 Notifier (Phase 17 D-08).
///
/// 동기 keepAlive Notifier 다 — Remote Config 기본값이 항상 있으므로 loading
/// · error 상태가 없다(D-23 정정). Firebase 미초기화(Phase 1 D-13)거나 Remote
/// Config 를 읽지 못하면 [FeatureFlagValues.defaults] 를 돌려주고 throw 하지
/// 않는다(Pitfall 14).
///
/// **실시간 반영 (D-10):** [FirebaseRemoteConfig.onConfigUpdated] 를 구독해
/// 콘솔 변경이 오면 `activate()` 뒤 state 를 다시 읽고, 인증 provider kill
/// switch([activeStrategiesProvider])도 다시 평가하게 한다. 구독 · 적용 오류는
/// 앱을 멈추지 않고 non-fatal 로만 기록한다(T-17-45). 구독은 provider 가
/// 해제될 때 함께 해제된다.
@Riverpod(keepAlive: true)
class FeatureFlagsNotifier extends _$FeatureFlagsNotifier {
  /// 실시간 구독 · 적용 오류의 Crashlytics reason (코드 경로 식별자).
  static const String updateErrorReason = 'feature_flags_on_config_updated';

  @override
  FeatureFlagValues build() {
    if (!ref.watch(isFirebaseInitializedProvider)) {
      return FeatureFlagValues.defaults;
    }
    final FirebaseRemoteConfig rc;
    try {
      rc = ref.watch(firebaseRemoteConfigProvider);
    } on Object catch (e) {
      _debugLog('instance', e);
      return FeatureFlagValues.defaults;
    }
    _subscribe(rc);
    try {
      return _readFlags(rc);
    } on Object catch (e) {
      _debugLog('read', e);
      return FeatureFlagValues.defaults;
    }
  }

  /// [rc] 의 실시간 변경을 구독한다 — 구독 자체가 실패하면 현재 값만 쓴다.
  void _subscribe(FirebaseRemoteConfig rc) {
    try {
      final sub = rc.onConfigUpdated.listen(
        (_) => unawaited(_applyUpdate(rc)),
        onError: _recordUpdateError,
      );
      ref.onDispose(sub.cancel);
    } on Object catch (e) {
      // 미초기화 · 플랫폼 미지원 — 실시간 반영 없이 가져온 값으로 동작한다.
      _debugLog('listen', e);
    }
  }

  /// 콘솔 변경을 활성화하고 state · kill switch 를 갱신한다.
  Future<void> _applyUpdate(FirebaseRemoteConfig rc) async {
    try {
      await rc.activate();
      if (!ref.mounted) return;
      state = _readFlags(rc);
      ref.invalidate(activeStrategiesProvider);
    } on Object catch (e, st) {
      _recordUpdateError(e, st);
    }
  }

  /// 실시간 반영 오류를 non-fatal 로 기록한다 — state 는 바꾸지 않는다.
  void _recordUpdateError(Object error, StackTrace stack) {
    _debugLog('update', error);
    if (!ref.mounted) return;
    // recordError 자체의 실패는 CrashlyticsService 래퍼가 흡수한다 (WR-01).
    unawaited(
      ref
          .read(crashlyticsServiceProvider)
          .recordError(error, stack, reason: updateErrorReason),
    );
  }
}

/// debug 빌드에서만 실패 단계와 오류 타입을 남긴다 (release 로그 0).
void _debugLog(String stage, Object error) {
  if (kDebugMode) {
    debugPrint('feature_flags $stage failed: ${error.runtimeType}');
  }
}

/// [rc] 의 활성 값으로 모든 [FeatureFlag] 를 읽는다.
FeatureFlagValues _readFlags(FirebaseRemoteConfig rc) {
  return FeatureFlagValues(<FeatureFlag, Object>{
    for (final flag in FeatureFlag.values)
      flag: switch (flag.defaultValue) {
        bool() => rc.getBool(flag.key),
        _ => rc.getString(flag.key),
      },
  });
}
