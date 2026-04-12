import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:sign_in_button/sign_in_button.dart';

import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../apple_sign_in_notifier.dart';
import '../google_sign_in_notifier.dart';
import 'or_divider.dart';

/// Google + Apple 버튼 + [OrDivider]를 감싸는 공통 위젯 (D-04, D-05).
///
/// LoginScreen과 SignupScreen 양쪽에서 동일하게 사용한다.
/// Phase 9에서 Facebook 버튼 추가 시 이 위젯 내부만 확장.
///
/// 버튼 순서는 플랫폼에 따라 분기한다 (D-05):
/// - iOS: Apple → Google (Apple HIG 권장)
/// - Android: Google → Apple (사용자 친숙도)
///
/// 플랫폼 판별은 `dart:io`의 runtime Platform API가 아닌
/// [defaultTargetPlatform]을 사용한다. 위젯 테스트에서
/// `debugDefaultTargetPlatformOverride`로 분기 검증이 가능하기 때문이다
/// (RESEARCH Pitfall 6 / DS-05).
///
/// Apple 버튼 다크모드 변형은 `Theme.of(context).brightness`로 분기한다
/// (D-06, Apple HIG 준수): 라이트 모드는 [Buttons.apple](검정 배경),
/// 다크 모드는 [Buttons.appleDark](흰색 배경).
class SocialSignInSection extends ConsumerWidget {
  /// [SocialSignInSection]을 생성한다.
  const SocialSignInSection({
    required this.isFormLoading,
    this.errorBanner,
    super.key,
  });

  /// 이메일 폼이 로딩 중인지 여부. true면 소셜 버튼도 비활성화한다.
  final bool isFormLoading;

  /// 소셜 버튼과 [OrDivider] 사이에 표시할 에러 배너.
  ///
  /// 소셜 로그인 에러는 소셜 버튼 바로 아래에 표시되어야 의미가 명확하다.
  /// null 또는 [SizedBox.shrink] 일 때는 공간을 차지하지 않는다.
  final Widget? errorBanner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    final googleState = ref.watch(googleSignInProvider);
    final appleState = ref.watch(appleSignInProvider);
    final isGoogleLoading = googleState.isLoading;
    final isAppleLoading = appleState.isLoading;
    // 이메일/Google/Apple 중 어느 하나라도 진행 중이면 이중 제출 방지.
    final isAnyLoading =
        isFormLoading || isGoogleLoading || isAppleLoading;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isIOS = defaultTargetPlatform == TargetPlatform.iOS;

    // Google 버튼 (Phase 7 패턴 유지, isAnyLoading 집계에만 Apple 추가).
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

    // Apple 버튼 (Phase 8 신규).
    // D-06: 라이트 → Buttons.apple(검정), 다크 → Buttons.appleDark(흰색).
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

    // D-05: iOS는 Apple → Google, Android 등은 Google → Apple.
    //       사이 간격은 spacing.md(12dp, UI-SPEC §Spacing Scale).
    final socialButtons = isIOS
        ? <Widget>[appleButton, Gap(spacing.md), googleButton]
        : <Widget>[googleButton, Gap(spacing.md), appleButton];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...socialButtons,
        if (errorBanner != null) ...[
          Gap(spacing.md),
          errorBanner!,
        ],
        Gap(spacing.lg),
        const OrDivider(),
        Gap(spacing.lg),
      ],
    );
  }
}
