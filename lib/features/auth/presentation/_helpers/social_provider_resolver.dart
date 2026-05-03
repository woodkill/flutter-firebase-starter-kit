import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart' show ProviderListenable;

import '../../../../core/auth/provider_id.dart';
import '../apple_sign_in_notifier.dart';
import '../facebook_sign_in_notifier.dart';
import '../google_sign_in_notifier.dart';
import '../kakao_sign_in_notifier.dart';

/// `Strategy.providerId` → 기존 `*SignInProvider` 매핑 helper
/// (Phase 11 D-12, Pitfall 6 / corrections 3번).
///
/// LoginScreen / SignupScreen / LoginPromptSheet 3곳에서 동일한 매핑이
/// 필요하므로 단일 모듈로 추출한다. Phase 12+ 신규 provider 추가 시 본
/// switch 의 case 1곳만 갱신하면 3곳 모두 자동 반영.
///
/// 반환 타입은 `ProviderListenable<AsyncValue<void>>` — `ref.listen` 의
/// 첫 인자에 직접 전달 가능하다.
ProviderListenable<AsyncValue<void>> resolveSocialProvider(String providerId) =>
    switch (providerId) {
      kProviderIdGoogle => googleSignInProvider,
      kProviderIdApple => appleSignInProvider,
      kProviderIdFacebook => facebookSignInProvider,
      // Phase 12 (D-27 / Pitfall 6 helper 단일 진실원) — 본 1줄로
      // LoginScreen / SignupScreen / LoginPromptSheet 의 ref.listen
      // for-loop 가 자동 반영된다.
      kProviderIdKakao => kakaoSignInProvider,
      _ => throw UnsupportedError('Unknown providerId: $providerId'),
    };
