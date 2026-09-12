import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../../core/error/app_exception.dart';
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
///
/// **Phase 9.2 Gap B Dart consumer (HUMAN-UAT 2026-05-11):**
/// `currentUser.email` 이 null 또는 빈 문자열인 경우 graceful fallback
/// 메시지([l10n.authVerifyEmailDescriptionNoEmail])를 표시한다. Cloud Function
/// (`naverCustomToken` / `kakaoCustomToken`) 의 충돌 detect 가 회귀해 email
/// 미설정 사용자가 진입한 경우의 user-visible PII 빈 표시를 차단한다.
/// redirect / 폴링 / 재전송 등 다른 동작은 변경 0 (Path A-narrow boundary).
/// Phase 17 (Account Linking) — see ROADMAP.md
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

    // (Phase 9.2 Gap B Dart consumer — HUMAN-UAT 2026-05-11):
    // currentUser.email 가 null/빈 문자열일 때 graceful fallback 분기.
    // Cloud Function (naverCustomToken / kakaoCustomToken) 의 충돌 detect 회귀로
    // email 미설정 user 가 진입할 가능성 차단. user-visible 메시지만 변경,
    // redirect/state 동작 unchanged.
    // Phase 17 (Account Linking) — see ROADMAP.md
    final description = userEmail.isEmpty
        ? l10n.authVerifyEmailDescriptionNoEmail
        : l10n.authVerifyEmailDescription(userEmail);

    return AuthScaffold(
      title: l10n.authVerifyEmailTitle,
      child: asyncState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        // IN-03: 본 화면의 verifyEmailProvider.build 는 동기 path 라 본
        // error 분기는 사실상 unreachable. 그러나 raw '$error' toString 이
        // 노출되면 FirebaseException 본문 (PII 가능) 이 그대로 보일 위험이
        // 있어 FormErrorBanner + AppException 매핑 패턴으로 일관화.
        error: (error, _) => Center(
          child: FormErrorBanner(
            exception: error is AppException
                ? error
                : ServiceUnavailable(cause: error),
          ),
        ),
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
            // 설명문 (이메일 주소 포함 — Gap B fallback 시 일반화 메시지)
            Text(
              description,
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
              onPressed: () =>
                  ref.read(verifyEmailProvider.notifier).checkManually(),
              isLoading: state.isChecking,
            ),
            Gap(spacing.md),
            // "재전송" 버튼 (쿨다운 상태 분기)
            //
            // WR-03: 비활성 조건에 `isResending` 을 포함한다. 쿨다운은
            // 네트워크 왕복이 **끝난 뒤에야** 세팅되므로 `cooldownRemaining`
            // 단독으로는 왕복 구간(2~3초)의 연타를 막지 못했다 — 중복 메일 +
            // `too-many-requests` 유발. 위 "인증 확인" CTA 가 `isChecking` 으로
            // 이중 탭을 막는 것과 대칭.
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: state.cooldownRemaining > 0 || state.isResending
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
              onPressed: () => ref.read(verifyEmailProvider.notifier).logout(),
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
