import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/theme/theme_extensions.dart';
import '../data/auth_repository.dart';
import '_widgets/auth_scaffold.dart';
import '_widgets/form_error_banner.dart';
import '_widgets/primary_cta.dart';
import 'verify_email_notifier.dart';

/// 이메일 인증 대기 화면.
///
/// 가입 후 또는 emailVerified==false 상태에서 접근되는 화면이다.
/// 3초 간격 자동 폴링(5분 타임아웃)과 수동 "인증 확인" 버튼을 병행하여
/// 이메일 인증 완료를 감지한다 (D-07, D-08, D-09).
/// 인증 완료 시 GoRouter redirect가 자동으로 Home으로 이동시킨다.
class VerifyEmailScreen extends ConsumerWidget {
  /// [VerifyEmailScreen]을 생성한다.
  const VerifyEmailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    final colors = context.colorScheme;
    final typography = context.appTypography;

    final asyncState = ref.watch(verifyEmailProvider);
    final currentUser = ref.watch(currentUserProvider);
    final userEmail = currentUser?.email ?? '';

    return AuthScaffold(
      title: l10n.authVerifyEmailTitle,
      child: asyncState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (state) => Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Gap(spacing.xxl),
            // 상단 메일 아이콘 (48dp, primary)
            Semantics(
              label: l10n.authVerifyEmailTitle,
              child: Icon(
                Icons.mark_email_unread_outlined,
                size: 48,
                color: colors.primary,
              ),
            ),
            Gap(spacing.xl),
            // 설명문 (이메일 주소 포함)
            Text(
              l10n.authVerifyEmailDescription(userEmail),
              style: typography.bodyMedium.copyWith(
                color: colors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            Gap(spacing.md),
            // 스팸 안내 Container
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: spacing.md,
                vertical: spacing.sm,
              ),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(spacing.sm),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: colors.onSurfaceVariant,
                  ),
                  Gap(spacing.xs),
                  Flexible(
                    child: Text(
                      l10n.authVerifyEmailSpamHint,
                      style: typography.bodySmall.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Gap(spacing.md),
            // 에러 배너 (재전송 실패 시)
            FormErrorBanner(exception: state.error),
            Gap(spacing.xl),
            // 폴링 상태 표시
            if (state.isPolling) ...[
              Semantics(
                label: l10n.commonLoading,
                child: const LinearProgressIndicator(),
              ),
              Gap(spacing.sm),
            ],
            // "인증 확인" Primary CTA
            PrimaryCta(
              label: l10n.authVerifyEmailCheck,
              onPressed: () => ref
                  .read(verifyEmailProvider.notifier)
                  .checkManually(),
              isLoading: state.isChecking,
            ),
            Gap(spacing.md),
            // "재전송" 버튼 (쿨다운 상태 분기)
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: state.cooldownRemaining > 0
                    ? null
                    : () => ref
                        .read(verifyEmailProvider.notifier)
                        .resendVerification(),
                child: Text(
                  state.cooldownRemaining > 0
                      ? l10n.authVerifyEmailResendCooldown(
                          state.cooldownRemaining,
                        )
                      : l10n.authVerifyEmailResend,
                ),
              ),
            ),
            Gap(spacing.md),
            // "다른 계정으로 로그인" 링크
            TextButton(
              onPressed: () =>
                  ref.read(verifyEmailProvider.notifier).logout(),
              child: Text(
                l10n.authVerifyEmailLogout,
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
