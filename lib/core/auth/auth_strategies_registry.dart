import 'dart:ui' show Locale;

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../config/app_config.dart';
import '../providers/firebase_providers.dart' show firebaseRemoteConfigProvider;
import 'auth_strategy.dart';
import 'provider_id.dart';
import 'strategies/apple_auth_strategy.dart';
import 'strategies/facebook_auth_strategy.dart';
import 'strategies/google_auth_strategy.dart';

part 'auth_strategies_registry.g.dart';

/// 등록된 모든 [AuthStrategy].
///
/// Phase 12~16 에서 5개 추가 (Kakao / Naver / LINE / Yahoo!JP / WeChat —
/// 각 Custom Token Strategy). 추가 절차는 add-only:
/// 1. [kAllProviderIds] 갱신 (이미 8개 등록됨)
/// 2. `lib/core/auth/strategies/{provider}_auth_strategy.dart` 신규
/// 3. 본 리스트 끝에 `const {Provider}AuthStrategy()` 추가
const List<AuthStrategy> _allStrategies = <AuthStrategy>[
  GoogleAuthStrategy(),
  AppleAuthStrategy(),
  FacebookAuthStrategy(),
];

/// 활성화된 [AuthStrategy] 만 반환한다 (정적 + RC overlay 합산, D-26).
///
/// Phase 11 단계 정렬 미적용 — [_allStrategies] 등록 순서 그대로 (D-13).
/// Phase 16.1 (SOCL-10) 에서 `..sortByPriority(locale)` 추가 진입점.
///
/// **Pitfall 5 (D-26 truth table 핵심):**
/// | static | rc (or default) | result |
/// | ------ | --------------- | ------ |
/// | true   | true            | true   |
/// | true   | false           | false  |
/// | false  | *               | false  |  ← 정적 false 절대 우위
///
/// `kDebugMode` invariant: [_allStrategies] 의 `providerId` 가 모두
/// [kAllProviderIds] 에 포함되어야 한다 (T-11-STR-02). 위반 시 즉시 throw.
@Riverpod(keepAlive: true)
List<AuthStrategy> activeStrategies(Ref ref, Locale locale) {
  // 디버그 invariant (T-11-STR-02): Strategy.providerId ⊆ kAllProviderIds.
  assert(() {
    final unknown = _allStrategies
        .map((s) => s.providerId)
        .where((id) => !kAllProviderIds.contains(id))
        .toList();
    if (unknown.isNotEmpty) {
      throw StateError(
        'AuthStrategy.providerId 가 kAllProviderIds 에 없음: $unknown',
      );
    }
    return true;
  }());

  final staticEnabled = ref.watch(staticAuthProvidersProvider);
  final rc = ref.watch(firebaseRemoteConfigProvider);

  return <AuthStrategy>[
    for (final strategy in _allStrategies)
      if (_isEnabled(strategy.providerId, staticEnabled, rc)) strategy,
  ];
}

/// 합산 규칙 (D-26):
/// - 정적 누락 또는 false → disabled (RC 로 켤 수 없음, Pitfall 5)
/// - 정적 true + RC false → disabled (kill switch)
/// - 정적 true + RC true → enabled
/// - 정적 true + RC 키 없음 → enabled (D-25 fallback, T-11-RC-03)
bool _isEnabled(
  String providerId,
  Map<String, bool> staticEnabled,
  FirebaseRemoteConfig rc,
) {
  if (!(staticEnabled[providerId] ?? false)) return false;
  final key = 'auth_provider_${providerId}_enabled';
  // RC 미초기화 / 키 없음 시 default true (정적 enabled 존중).
  if (!rc.getAll().containsKey(key)) return true;
  return rc.getBool(key);
}
