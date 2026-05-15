// Phase 13.1 — see ROADMAP.md (D-62 Apple SDK 위임 + D-64 Google 명시 매개변수)
// Phase 13.3 — see ROADMAP.md (R6 caller-side breaking change — theme/style
//             parameter 폐기 흡수, Wave 3 D-117)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_strategy.dart';
import '../../../../core/auth/provider_id.dart';
import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../l10n/generated/app_localizations.dart';
import 'branded_social_button.dart';

/// 단일 [AuthStrategy] 를 [BrandedSocialButton] 위제로 렌더링하는 공용 버튼
/// (Phase 11 D-11, Pattern G).
///
/// **Phase 13.1 변경 (D-62 / D-64 / R5 / R6):**
/// - Apple 분기 → [BrandedSocialButton.apple] 위임 (1st-party
///   `sign_in_with_apple.SignInWithAppleButton` 사용)
/// - Google 분기 → [BrandedSocialButton.google] 위임 (공식 SVG 6종)
/// - Naver 분기 → [BrandedSocialButton.naver] (theme 매개변수 명시)
/// - Kakao 분기 → [BrandedSocialButton.kakao] (Phase 13 D-55 기존 위임)
///
/// **Phase 13.2 변경 (R7 / R8 — Meta 공식 자상 마이그):**
/// - Facebook 분기 → [BrandedSocialButton.facebook] 위임 (Meta 공식 'f' 마크
///   PNG + Apple `SignInWithAppleButton` 패턴 mirror 의 자체 위제 구현).
///   Phase 13.2 완료 — 모든 provider 가 [BrandedSocialButton] 단일 진실원으로
///   일관 위임.
///
/// **Phase 13.3 변경 (R6 — caller-side breaking change 흡수):**
/// - Naver/Google factory 의 `theme:` parameter + Apple factory 의 `style:`
///   parameter 모두 폐기. caller 측 `Theme.of(context).brightness` 자동 매핑
///   로직 제거 — Theme.brightness 자동 분기는 [BrandedSocialButton] 위제 내부
///   책임으로 일관 (Naver 는 BI 단일 색 강제, Google 은 `_renderGoogleButton`
///   내부 분기, Apple 은 HIG 권장값 자동 매핑).
///
/// **Brand Guideline 단일 진실원:**
/// `lib/features/auth/presentation/_widgets/branded_social_button.dart`.
///
/// **위임 invariant (D-11/D-12):** 탭 시 [strategy].signIn 으로 직접 위임한다.
/// 기존 `*SignInNotifier` 가 `AsyncValue<void>` 로 success/error 를 노출하므로
/// UI 는 `ref.listen(*SignInProvider, ...)` 으로 분기한다.
class SocialButton extends ConsumerWidget {
  /// [SocialButton] 을 생성한다.
  const SocialButton({
    required this.strategy,
    required this.isDisabled,
    super.key,
  });

  /// 렌더링·위임 대상 [AuthStrategy].
  final AuthStrategy strategy;

  /// 다른 사회적 로그인 / 폼 로딩 등으로 인한 비활성 상태.
  ///
  /// 모든 provider 분기에서 `onPressed` 에 `null` 을 전달해 [BrandedSocialButton]
  /// 의 Material default disabled 외관으로 만든다 (Phase 13.2 완료 — Facebook
  /// 분기도 [BrandedSocialButton.facebook] 위임 일관).
  final bool isDisabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final label = _resolveLabel(l10n, strategy.labelKey);
    final onPressed = isDisabled
        ? null
        : () {
            FocusManager.instance.primaryFocus?.unfocus();
            strategy.signIn(ref);
          };

    // Phase 13.3 — see ROADMAP.md (R6 caller-side breaking change —
    // theme/style parameter 폐기 흡수). Naver/Google/Apple 분기 모두
    // Theme.brightness 자동 분기는 BrandedSocialButton 위제 내부 책임.
    // D-67 — provider switch (BrandedSocialButton 위임 + Facebook fallback).
    switch (strategy.providerId) {
      case kProviderIdKakao:
        return BrandedSocialButton.kakao(label: label, onPressed: onPressed);
      case kProviderIdNaver:
        // Phase 13.3 R3 — Naver BI 단일 그린 #03A94D 강제, theme: parameter
        // 폐기. caller 측 brightness 분기 책임 0.
        return BrandedSocialButton.naver(label: label, onPressed: onPressed);
      case kProviderIdGoogle:
        // Phase 13.3 R1 — theme: parameter 폐기. `_renderGoogleButton` 내부
        // Theme.brightness 자동 분기로 차원 축소.
        return BrandedSocialButton.google(label: label, onPressed: onPressed);
      case kProviderIdApple:
        // Phase 13.3 R5 — style: parameter 폐기. AppleSpec build() 가
        // Theme.brightness 자동 매핑 (HIG 권장값 light → .black / dark → .white).
        return BrandedSocialButton.apple(label: label, onPressed: onPressed);
      case kProviderIdFacebook:
        // Phase 13.2 R7 / R8 (옵션 A pivot, Wave 0 lock D-94) — Meta 공식
        // 자상 마이그. `BrandedSocialButton.facebook` 이 Apple
        // `SignInWithAppleButton` 패턴 mirror 의 자체 위제 (`_renderFacebookButton`)
        // 로 18dp 'f' 아이콘 + ARB 라벨 + Theme.brightness 자동 분기 + 1dp
        // outline + Material disabled 외관 일관 표현. Phase 13.1 의 dim wrapper
        // 패턴은 위제 내부의 Material disabled 외관으로 자연 해소.
        //
        // **Phase 13.2 REVIEW IN-02 정정 (2026-05-13):** D-94 lock 명시 —
        // FacebookSpec 의 theme 필드 부재 (Primary Logo 단독 채택, Kakao
        // 패턴 mirror). 따라서 본 분기는 `brightness` 매개변수 미전달.
        // Theme.brightness 자동 분기는 `_renderFacebookButton` 위제 내부
        // 책임 — Naver/Google 의 caller-side `brightness` 매개변수 전달
        // 패턴과 분리. 미래 reader 가 Facebook 분기의 brightness 사용 누락을
        // "미완성 implementation" 으로 오해 차단.
        return BrandedSocialButton.facebook(label: label, onPressed: onPressed);
      default:
        throw UnsupportedError('Unknown providerId: ${strategy.providerId}');
    }
  }

  /// ARB 키를 [AppLocalizations] getter 로 매핑한다.
  ///
  /// **Phase 13.1 Gap-1 X2 (2026-05-09 재설계 후 책임 변경):**
  /// Kakao/Naver/Google 자상은 wide 자상 통째 buttons 패턴 (자상 자체에
  /// 라벨/로고/배경 모두 baked-in) 으로 재설계되어, 본 메서드가 반환하는
  /// `authKakaoSignIn` / `authNaverSignIn` / `authGoogleSignIn` 라벨은
  /// **시각 layer 에 렌더되지 않고** [BrandedSocialButton] 내부에서 무시된다
  /// (label 매개변수는 보존 — 호출자 호환 + 미래 fallback 가능성).
  ///
  /// 의미 있는 라벨 매핑:
  /// - `authAppleSignIn` — [SignInWithAppleButton] 의 `text` 매개변수에 주입
  ///   (Apple HIG ko/en/ja 변형 모두 표시).
  /// - `authFacebookSignIn` — `_renderFacebookButton` 내부 [Text] 위제로 주입
  ///   (Phase 13.2 완료 — Meta 공식 자상 + 라벨 외부 layer).
  ///
  /// 무시되는 라벨 매핑 (자상 baked-in):
  /// - `authKakaoSignIn` / `authNaverSignIn` / `authGoogleSignIn`. 단
  ///   접근성 (Semantics) layer 에서 향후 활용 가능.
  ///
  /// Phase 12 — `authKakaoSignIn` 추가 (D-29).
  /// Phase 13 Plan 13-06 — `authNaverSignIn` 추가 (Wave 4 atomic 분리 —
  /// Plan 13-05 의 임시 라벨 → ARB 키 교체).
  /// Phase 13.1 Gap-1 X2 — Kakao/Naver/Google 라벨 시각 layer 폐기 (자상
  /// baked-in), 본 메서드 매핑 자체는 보존 (회귀 차단).
  String _resolveLabel(AppLocalizations l10n, String key) => switch (key) {
    'authGoogleSignIn' => l10n.authGoogleSignIn,
    'authAppleSignIn' => l10n.authAppleSignIn,
    'authFacebookSignIn' => l10n.authFacebookSignIn,
    'authKakaoSignIn' => l10n.authKakaoSignIn,
    'authNaverSignIn' => l10n.authNaverSignIn,
    // Phase 13.1 REVIEW WR-06 정정 (2026-05-10): default branch fail-soft
    // (raw key 반환) → fail-loud (UnsupportedError). Phase 14 (LINE) /
    // Phase 15 (Yahoo!JP) / Phase 16 (WeChat) 진입 시 strategy 가
    // labelKey: 'authLineSignIn' 등을 호출했을 때 본 switch 갱신 누락 시
    // raw ARB 키 ('authLineSignIn') 그대로 사용자 노출 회귀 방지. 미래
    // provider 추가 시 본 switch 의 case 추가 의무가 컴파일 / runtime
    // 경계에서 명시되도록 강제.
    _ => throw UnsupportedError(
      'Unknown labelKey: $key — Phase 14+ provider 추가 시 본 switch 갱신 의무. '
      'social_button.dart:_resolveLabel',
    ),
  };
}
