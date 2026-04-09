import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:sign_in_button/sign_in_button.dart';

import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../google_sign_in_notifier.dart';
import 'or_divider.dart';

/// Google 버튼 + OrDivider를 감싸는 공통 위젯 (D-05).
///
/// LoginScreen과 SignupScreen 양쪽에서 동일하게 사용한다.
/// Phase 8/9에서 Apple/Facebook 버튼 추가 시 이 위젯 내부만 확장.
class SocialSignInSection extends ConsumerWidget {
  /// [SocialSignInSection]을 생성한다.
  const SocialSignInSection({
    required this.isFormLoading,
    super.key,
  });

  /// 이메일 폼이 로딩 중인지 여부. true면 Google 버튼도 비활성화.
  final bool isFormLoading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    final googleState = ref.watch(googleSignInProvider);
    final isGoogleLoading = googleState.isLoading;
    final isAnyLoading = isFormLoading || isGoogleLoading;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
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
        ),
        Gap(spacing.lg),
        const OrDivider(),
        Gap(spacing.lg),
      ],
    );
  }
}
