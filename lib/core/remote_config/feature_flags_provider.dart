import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../providers/firebase_providers.dart';
import 'feature_flag.dart';

part 'feature_flags_provider.g.dart';

/// Remote Config 의 [FeatureFlag] 값을 노출하는 Notifier (Phase 17 D-08).
///
/// 동기 keepAlive Notifier 다 — Remote Config 기본값이 항상 있으므로 loading
/// · error 상태가 없다(D-23 정정). Firebase 미초기화(Phase 1 D-13)거나 Remote
/// Config 를 읽지 못하면 [FeatureFlagValues.defaults] 를 돌려주고 throw 하지
/// 않는다(Pitfall 14).
@Riverpod(keepAlive: true)
class FeatureFlagsNotifier extends _$FeatureFlagsNotifier {
  @override
  FeatureFlagValues build() {
    if (!ref.watch(isFirebaseInitializedProvider)) {
      return FeatureFlagValues.defaults;
    }
    try {
      return _readFlags(ref.watch(firebaseRemoteConfigProvider));
    } on Object catch (e) {
      if (kDebugMode) {
        debugPrint('feature_flags read failed: ${e.runtimeType}');
      }
      return FeatureFlagValues.defaults;
    }
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
