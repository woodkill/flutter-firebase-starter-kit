import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../config/app_config.dart';
import '../providers/firebase_providers.dart' show firebaseRemoteConfigProvider;
import 'auth_strategy.dart';
import 'provider_id.dart';
import 'strategies/apple_auth_strategy.dart';
import 'strategies/facebook_auth_strategy.dart';
import 'strategies/google_auth_strategy.dart';
import 'strategies/kakao_auth_strategy.dart';
import 'strategies/line_auth_strategy.dart'; // Phase 14 — see ROADMAP.md
import 'strategies/naver_auth_strategy.dart'; // Phase 13 — see ROADMAP.md
import 'strategies/yahoojp_auth_strategy.dart'; // Phase 15 — see ROADMAP.md

part 'auth_strategies_registry.g.dart';

/// 등록된 모든 [AuthStrategy].
///
/// Phase 12~15 에서 4개 추가 (Kakao / Naver / LINE / Yahoo!JP — 각 Custom
/// Token Strategy). 추가 절차는 add-only:
/// 1. [kAllProviderIds] 갱신 (이미 7개 등록됨)
/// 2. `lib/core/auth/strategies/{provider}_auth_strategy.dart` 신규
/// 3. 본 리스트 끝에 `const {Provider}AuthStrategy()` 추가
const List<AuthStrategy> _allStrategies = <AuthStrategy>[
  GoogleAuthStrategy(),
  AppleAuthStrategy(),
  FacebookAuthStrategy(),
  KakaoAuthStrategy(), // Phase 12 추가 (D-26 add-only)
  NaverAuthStrategy(), // Phase 13 — see ROADMAP.md, D-26 add-only
  LineAuthStrategy(), // Phase 14 — see ROADMAP.md, SOCL-09 add-only
  YahoojpAuthStrategy(), // Phase 15 — see ROADMAP.md, SOCL-09 add-only
];

/// 활성화된 [AuthStrategy] 만 반환한다 (정적 + RC overlay 합산, D-26).
///
/// Phase 11 단계 정렬 미적용 — [_allStrategies] 등록 순서 그대로 (D-13).
/// 로케일별 우선순위 정책 (SOCL-10) 은 2026-05-22 Out of Scope 로 폐기됐다
/// (진실원 .planning/REQUIREMENTS.md Out of Scope) — 정렬 없이
/// [_allStrategies] 등록 순서를 유지하는 것이 현재 계약이다.
///
/// **`Locale` family 인자 제거 (WR-09 — Phase 7 review):** SOCL-10 폐기 후
/// 본 함수 본문은 `locale` 을 읽지 않았는데 `keepAlive` family 의 캐시 key
/// 로만 남아 (1) Locale 마다 동일 결과의 인스턴스가 영구 중복 보존되고
/// (2) 호출자 전원이 의미 없는 `Localizations.localeOf(context)` 를 이
/// 목적만으로 조회했으며 (3) 독자에게 "이 목록은 로케일에 따라 달라진다"
/// 는 잘못된 신호를 줬다. **재도입 진입점:** 정책 부활 시 본 provider 를
/// 다시 family 로 되돌리고 [AuthStrategy.defaultPriorityFor] 로 정렬한다.
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
List<AuthStrategy> activeStrategies(Ref ref) {
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
  final key = rcKeyForProvider(providerId);
  // RC 미초기화 / 키 없음 시 default true (정적 enabled 존중).
  if (!rc.getAll().containsKey(key)) return true;
  return rc.getBool(key);
}
