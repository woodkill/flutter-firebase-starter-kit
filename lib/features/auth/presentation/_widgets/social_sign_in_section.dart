import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../../../core/auth/auth_strategies_registry.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../apple_sign_in_notifier.dart';
import '../facebook_sign_in_notifier.dart';
import '../google_sign_in_notifier.dart';
import '../kakao_sign_in_notifier.dart';
import 'or_divider.dart';
import 'social_button.dart';

/// 활성화된 [AuthStrategy] 들을 [SocialButton] 으로 렌더링하는 공통 섹션
/// (Phase 11 D-11, Pattern H).
///
/// LoginScreen / SignupScreen / LoginPromptSheet 양쪽에서 동일하게 사용한다.
/// 활성 Strategy 목록은 [activeStrategiesProvider] (정적 config + Remote
/// Config kill switch overlay 합산, D-26) 가 제공한다. 인라인 Google/Apple/
/// Facebook 빌더는 [SocialButton] 으로 통합되어 본 섹션에서 제거되었다.
///
/// 진행 중 상태 ([isAnyLoading]) 는 Phase 11 단계에서 3개 Provider
/// (`google` / `apple` / `facebook`) 를 직접 watch 한다. Phase 12+ 에서 신규
/// provider 추가 시 helper Provider 로 추출 검토 (corrections 4번).
class SocialSignInSection extends ConsumerWidget {
  /// [SocialSignInSection]을 생성한다.
  const SocialSignInSection({
    required this.isFormLoading,
    this.errorBanner,
    this.showOrDivider = true,
    super.key,
  });

  /// 이메일 폼이 로딩 중인지 여부. true면 소셜 버튼도 비활성화한다.
  final bool isFormLoading;

  /// 소셜 버튼과 [OrDivider] 사이에 표시할 에러 배너.
  ///
  /// 소셜 로그인 에러는 소셜 버튼 바로 아래에 표시되어야 의미가 명확하다.
  /// null 또는 [SizedBox.shrink] 일 때는 공간을 차지하지 않는다.
  final Widget? errorBanner;

  /// 소셜 버튼 아래 [OrDivider] 노출 여부 (Phase 10 D-10).
  ///
  /// - `true` (기본값): LoginScreen/SignupScreen 처럼 소셜 → Divider →
  ///   이메일 폼으로 이어지는 화면에서 사용.
  /// - `false`: [LoginPromptSheet] 처럼 Divider 없이 소셜 버튼만 노출하는
  ///   Bottom Sheet에서 사용 (뒤에 "이메일로 계속" TextButton 이 이어짐).
  final bool showOrDivider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.appSpacing;
    final locale = Localizations.localeOf(context);

    // 이메일/Google/Apple/Facebook/Kakao 중 어느 하나라도 진행 중이면 이중
    // 제출 방지. Phase 11 단계는 3개 Provider 직접 watch (corrections 4번),
    // Phase 12 에서 kakaoSignInProvider 추가 (D-25 / 12-UI-SPEC line 472-477).
    final isAnyLoading =
        isFormLoading ||
        ref.watch(googleSignInProvider).isLoading ||
        ref.watch(appleSignInProvider).isLoading ||
        ref.watch(facebookSignInProvider).isLoading ||
        ref.watch(kakaoSignInProvider).isLoading;

    // 활성화된 Strategy 만 — 정적 config + RC overlay 합산 (D-26).
    final strategies = ref.watch(activeStrategiesProvider(locale));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var i = 0; i < strategies.length; i++) ...[
          if (i > 0) Gap(spacing.md),
          SocialButton(strategy: strategies[i], isDisabled: isAnyLoading),
        ],
        if (errorBanner != null) ...[Gap(spacing.md), errorBanner!],
        if (showOrDivider) ...[
          Gap(spacing.lg),
          const OrDivider(),
          Gap(spacing.lg),
        ],
      ],
    );
  }
}
