import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart'
    show ProviderListenable;

import '../../../../core/auth/auth_strategies_registry.dart';
import '../../../../core/auth/provider_id.dart';
import '../apple_sign_in_notifier.dart';
import '../facebook_sign_in_notifier.dart';
import '../google_sign_in_notifier.dart';
import '../kakao_sign_in_notifier.dart';
import '../line_sign_in_notifier.dart';
import '../naver_sign_in_notifier.dart';
import '../yahoojp_sign_in_notifier.dart';

/// `Strategy.providerId` → 기존 `*SignInProvider` 매핑 helper
/// (Phase 11 D-12, Pitfall 6 / corrections 3번).
///
/// LoginScreen / LoginPromptSheet 2곳에서 동일한 매핑이 필요하므로 단일
/// 모듈로 추출한다 (Phase 16.1 — 소셜 섹션을 함께 담던 구 가입 화면
/// 삭제로 3곳 → 2곳).
/// Phase 12+ 신규 provider 추가 시 본 switch 의 case 1곳만 갱신하면
/// 2곳 모두 자동 반영.
///
/// 반환 타입은 `ProviderListenable<AsyncValue<void>>` — `ref.listen` 의
/// 첫 인자에 직접 전달 가능하다.
ProviderListenable<AsyncValue<void>> resolveSocialProvider(String providerId) =>
    switch (providerId) {
      kProviderIdGoogle => googleSignInProvider,
      kProviderIdApple => appleSignInProvider,
      kProviderIdFacebook => facebookSignInProvider,
      // Phase 12 (D-27 / Pitfall 6 helper 단일 진실원) — 본 1줄로
      // LoginScreen / LoginPromptSheet 의 ref.listen for-loop 가 자동
      // 반영된다.
      kProviderIdKakao => kakaoSignInProvider,
      // Phase 13 — see ROADMAP.md (Pitfall 6 helper 단일 진실원 확장).
      kProviderIdNaver => naverSignInProvider,
      // Phase 14 — see ROADMAP.md (SOCL-09 registry add-only 자동 통합).
      kProviderIdLine => lineSignInProvider,
      // Phase 15 — see ROADMAP.md (SOCL-09 registry add-only 자동 통합).
      kProviderIdYahooJp => yahoojpSignInProvider,
      _ => throw UnsupportedError('Unknown providerId: $providerId'),
    };

/// 활성 소셜 Strategy 중 **하나라도** sign-in 진행 중이면 `true`
/// (WR-08 — Phase 7 review).
///
/// **도입 이유 (복제 제거):** 같은 7 provider `isLoading` 합산 목록이
/// `social_sign_in_section` / `login_prompt_sheet` / `login_screen` **3곳에
/// 복제**되어 있었다. 이 목록은 `SocialLinkInProgress` 의 bool 플래그
/// (counter 아님) 가 동시 실행으로 깨지지 않게 막는 유일한 방어선이므로,
/// provider 추가 시 3곳 중 한 곳만 갱신되면 이중 제출 잠금이 **silent 로**
/// 무너진다. [activeStrategiesProvider] + [resolveSocialProvider] 조합으로
/// 계산해 복제를 제거하고, registry 등록만으로 3 surface 가 자동 반영되게
/// 한다.
///
/// **조기 return 금지 (구독 누락 회귀 가드):** 첫 번째 loading 발견 시
/// 곧바로 반환하면 나머지 provider 에 대한 `ref.watch` 구독이 등록되지
/// 않아, 이후 다른 provider 가 로딩을 시작해도 rebuild 가 일어나지 않는다.
/// 반드시 전부 watch 한 뒤 판정한다.
bool watchAnySocialSignInLoading(WidgetRef ref) {
  var anyLoading = false;
  for (final strategy in ref.watch(activeStrategiesProvider)) {
    if (ref.watch(resolveSocialProvider(strategy.providerId)).isLoading) {
      anyLoading = true;
    }
  }
  return anyLoading;
}
