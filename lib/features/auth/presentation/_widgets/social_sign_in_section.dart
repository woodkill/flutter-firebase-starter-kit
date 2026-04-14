import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:sign_in_button/sign_in_button.dart';

import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../apple_sign_in_notifier.dart';
import '../facebook_sign_in_notifier.dart';
import '../google_sign_in_notifier.dart';
import 'or_divider.dart';

/// Google + Apple + Facebook 버튼 + [OrDivider]를 감싸는 공통 위젯.
///
/// LoginScreen과 SignupScreen 양쪽에서 동일하게 사용한다.
/// 버튼 순서는 플랫폼 무관하게 Google -> Apple -> Facebook 통일 (D-04).
///
/// Apple 버튼 다크모드 변형은 `Theme.of(context).brightness`로 분기한다
/// (D-06, Apple HIG 준수): 라이트 모드는 [Buttons.apple](검정 배경),
/// 다크 모드는 [Buttons.appleDark](흰색 배경).
///
/// Facebook 버튼은 [Buttons.facebookNew] 단일 변형을 사용한다.
/// Facebook 브랜드 가이드라인은 블루(#1877F2)를 모드 무관하게 사용하므로
/// 라이트/다크 분기가 불필요하다 (D-05).
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
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    final googleState = ref.watch(googleSignInProvider);
    final appleState = ref.watch(appleSignInProvider);
    final facebookState = ref.watch(facebookSignInProvider);
    final isGoogleLoading = googleState.isLoading;
    final isAppleLoading = appleState.isLoading;
    final isFacebookLoading = facebookState.isLoading;
    // 이메일/Google/Apple/Facebook 중 어느 하나라도 진행 중이면 이중 제출 방지.
    final isAnyLoading = isFormLoading ||
        isGoogleLoading ||
        isAppleLoading ||
        isFacebookLoading;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Google 버튼 (Phase 7 패턴 유지).
    final googleButton = SizedBox(
      width: double.infinity,
      height: 48,
      child: SignInButton(
        isDark ? Buttons.googleDark : Buttons.google,
        text: l10n.authGoogleSignIn,
        onPressed: isAnyLoading
            ? () {} // sign_in_button의 onPressed는 non-nullable
            : () {
                FocusManager.instance.primaryFocus?.unfocus();
                ref
                    .read(googleSignInProvider.notifier)
                    .signInWithGoogle();
              },
      ),
    );

    // Apple 버튼 (Phase 8).
    // D-06: 라이트 -> Buttons.apple(검정), 다크 -> Buttons.appleDark(흰색).
    final appleButton = SizedBox(
      width: double.infinity,
      height: 48,
      child: SignInButton(
        isDark ? Buttons.appleDark : Buttons.apple,
        text: l10n.authAppleSignIn,
        onPressed: isAnyLoading
            ? () {}
            : () {
                FocusManager.instance.primaryFocus?.unfocus();
                ref
                    .read(appleSignInProvider.notifier)
                    .signInWithApple();
              },
      ),
    );

    // Facebook 버튼 (Phase 9 신규, D-05).
    // Buttons.facebookNew는 라이트/다크 분기 불필요 (브랜드 가이드라인 동일 블루).
    final facebookButton = SizedBox(
      width: double.infinity,
      height: 48,
      child: SignInButton(
        Buttons.facebookNew,
        text: l10n.authFacebookSignIn,
        onPressed: isAnyLoading
            ? () {}
            : () {
                FocusManager.instance.primaryFocus?.unfocus();
                ref
                    .read(facebookSignInProvider.notifier)
                    .signInWithFacebook();
              },
      ),
    );

    // D-04: 플랫폼 무관 통일 순서 Google -> Apple -> Facebook.
    final socialButtons = <Widget>[
      googleButton,
      Gap(spacing.md),
      appleButton,
      Gap(spacing.md),
      facebookButton,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...socialButtons,
        if (errorBanner != null) ...[
          Gap(spacing.md),
          errorBanner!,
        ],
        if (showOrDivider) ...[
          Gap(spacing.lg),
          const OrDivider(),
          Gap(spacing.lg),
        ],
      ],
    );
  }
}
