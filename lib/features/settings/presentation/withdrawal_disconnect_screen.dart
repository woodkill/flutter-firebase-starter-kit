// Phase 16.10 — see ROADMAP.md
//
// 탈퇴 진행 화면 (UI-SPEC §Surface W · D-05 · D-06 · D-07 · D-12 · D-13 · D-14).
//
// 탈퇴 다이얼로그(16 Surface C) 확인 뒤 push 된다. 이 계정에 연결된 provider 마다
// 행 1개를 보이고, 행마다 provider 측 연결을 끊은 뒤 모든 행이 해제됨 · 건너뜀이
// 되면 아래 고정 「탈퇴」 로 기존 계정 삭제를 1회 부른다.
//
// 픽셀 계약 = UI-SPEC §Surface W 트리 + harness `_ProgressScreen`(variant `a` ·
// `footer: border` · `sep: divider`). 치환: `_t(lang, …)` → ARB getter ·
// `_label` → [formatProviderLabels] · `_brandButton` → [SocialButton] ·
// `_RS.active` → [DisconnectRowStatus.needsSignIn].
//
// 진행 표시는 행 아이콘 자리 스피너다 — `AuthInProgressOverlay` 는 라벨이
// 로그인 문구라 쓰지 않는다(UI-SPEC Claude's Discretion).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_strategy.dart';
import '../../../core/auth/provider_id.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../shared/auth/provider_label_formatter.dart';
import '../../auth/presentation/_widgets/social_button.dart';
import '../data/disconnect/disconnect_step.dart';
import '../data/disconnect/disconnect_steps.dart';
import '_widgets/withdrawal_confirmation_dialog.dart';
import 'settings_notifier.dart';
import 'withdrawal_disconnect_notifier.dart';

/// 탈퇴 진행 화면 (Phase 16.10 UI-SPEC §Surface W).
///
/// 첫 프레임 뒤 [WithdrawalDisconnect.start] 를 1회 불러 행을 스냅샷하고
/// 서버 행을 자동 시작한다. 처리 중(어떤 행이 해제 중 · 계정 삭제 중)에는
/// back 이 막히고, 그 밖에는 확인 없이 나갈 수 있다(D-14 — 계정은 그대로).
class WithdrawalDisconnectScreen extends ConsumerStatefulWidget {
  /// [WithdrawalDisconnectScreen] 을 생성한다.
  const WithdrawalDisconnectScreen({super.key});

  @override
  ConsumerState<WithdrawalDisconnectScreen> createState() =>
      _WithdrawalDisconnectScreenState();
}

class _WithdrawalDisconnectScreenState
    extends ConsumerState<WithdrawalDisconnectScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_notifier.start());
    });
  }

  /// 진행 notifier — 이벤트 핸들러에서만 읽는다.
  WithdrawalDisconnect get _notifier =>
      ref.read(withdrawalDisconnectProvider.notifier);

  /// 삭제 결과 SnackBar 를 root messenger 에 띄운다.
  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    final typography = context.appTypography;
    final scheme = context.colorScheme;
    final state = ref.watch(withdrawalDisconnectProvider);
    final deleting = ref.watch(settingsProvider).isLoading;
    final busy = state.anyWorking || deleting;
    final steps = ref.watch(disconnectStepsProvider);
    final disabled = state.actionsLocked || deleting;

    ref.listen<AsyncValue<void>>(settingsProvider, (prev, next) {
      if (prev?.isLoading == true && next.hasValue && !next.hasError) {
        // 성공 — router 가 사후 정리(signOut) 뒤 /onboarding 으로 reset 한다.
        _showSnackBar(l10n.withdrawalSuccess);
        return;
      }
      if (next.hasError) {
        final error = next.error;
        if (error is ReauthenticationRequiredException) {
          _showSnackBar(l10n.withdrawalReauthRequired);
          // 재인증 목적 push 라 표시를 붙여야 guard 가 로그인 화면을 홈으로
          // 튕기지 않는다 (R_EXTRA_G3_REAUTH_LOGIN_BOUNCE).
          unawaited(
            GoRouter.of(
              context,
            ).push(AppRoutes.buildReauthLocation(AppRoutes.login)),
          );
        } else {
          // 원인별 문구 · 화면 유지 — 재시도 = 「탈퇴」 다시.
          _showSnackBar(resolveWithdrawalFailureMessage(l10n, error));
        }
      }
    });

    final rows = state.rows;
    final lastIndex = rows.length - 1;
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.withdrawalDialogTitle)),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: EdgeInsets.symmetric(vertical: spacing.md),
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        spacing.lg,
                        spacing.sm,
                        spacing.lg,
                        spacing.sm,
                      ),
                      child: Text(
                        l10n.withdrawalDisconnectIntro,
                        style: typography.bodyMedium.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    for (final (i, row) in rows.indexed)
                      _separate(
                        context,
                        isLast: i == lastIndex,
                        child: _DisconnectRowTile(
                          key: ValueKey<AccountProvider>(row.provider),
                          row: row,
                          isCurrent:
                              row.kind == DisconnectKind.relogin &&
                              identical(row, state.currentReloginRow),
                          signInStrategy: disconnectStepFor(
                            steps,
                            row.provider,
                          )?.signInStrategy,
                          disabled: disabled,
                          onSignIn: () => unawaited(
                            _notifier.signInAndDisconnect(row.provider),
                          ),
                          onSkip: () => _notifier.skip(row.provider),
                          onRetry: () =>
                              unawaited(_notifier.retry(row.provider)),
                        ),
                      ),
                  ],
                ),
              ),
              // Q9-A 아래 영역 위 선 — SDK Scaffold persistentFooter 기본 장식과
              // 같은 식이며 목록이 넘치지 않아도 항상 그린다.
              Container(
                decoration: BoxDecoration(
                  border: Border(
                    top: Divider.createBorderSide(context, width: 1.0),
                  ),
                ),
                child: _FinalBar(
                  allDone: state.allDone,
                  deleting: deleting,
                  enabled: state.allDone && !busy && !state.actionsLocked,
                  onDelete: () => unawaited(_notifier.requestDeletion()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 마지막 행이 아니면 행 아래 1dp 구분선을 foreground 로 그린다 (Q10).
  ///
  /// SDK `ListTile.divideTiles` 와 같은 장식 — 행 높이 · 좌표를 바꾸지 않는다.
  Widget _separate(
    BuildContext context, {
    required bool isLast,
    required Widget child,
  }) {
    if (isLast) return child;
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        border: Border(bottom: Divider.createBorderSide(context)),
      ),
      child: child,
    );
  }
}

/// 진행 화면 provider 1행 (UI-SPEC §Surface W `_DisconnectRow`).
class _DisconnectRowTile extends StatelessWidget {
  const _DisconnectRowTile({
    super.key,
    required this.row,
    required this.isCurrent,
    required this.signInStrategy,
    required this.disabled,
    required this.onSignIn,
    required this.onSkip,
    required this.onRetry,
  });

  final DisconnectRow row;
  final bool isCurrent;
  final AuthStrategy? signInStrategy;
  final bool disabled;
  final VoidCallback onSignIn;
  final VoidCallback onSkip;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    final typography = context.appTypography;
    final scheme = context.colorScheme;
    final iconSize = IconTheme.of(context).size!;
    final label = formatProviderLabels(<String>[row.providerId], l10n).single;
    final muted = typography.bodyMedium.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final errorStyle = typography.bodyMedium.copyWith(color: scheme.error);

    final (
      Widget icon,
      String status,
      TextStyle statusStyle,
    ) = switch (row.status) {
      DisconnectRowStatus.waiting => (
        Icon(Icons.radio_button_unchecked, color: scheme.onSurfaceVariant),
        l10n.withdrawalDisconnectStatusWaiting,
        muted,
      ),
      DisconnectRowStatus.needsSignIn => (
        Icon(Icons.login, color: scheme.onSurfaceVariant),
        l10n.withdrawalDisconnectStatusNeedsSignIn,
        muted,
      ),
      DisconnectRowStatus.working => (
        const CircularProgressIndicator(),
        l10n.withdrawalDisconnectStatusWorking,
        muted,
      ),
      DisconnectRowStatus.done => (
        Icon(Icons.check_circle, color: context.appColors.success),
        l10n.withdrawalDisconnectStatusDone,
        muted,
      ),
      DisconnectRowStatus.failed => (
        Icon(Icons.error_outline, color: scheme.error),
        l10n.withdrawalDisconnectStatusFailed,
        errorStyle,
      ),
      DisconnectRowStatus.mismatch => (
        Icon(Icons.error_outline, color: scheme.error),
        l10n.withdrawalDisconnectStatusMismatch(label),
        errorStyle,
      ),
      DisconnectRowStatus.skipped => (
        Icon(Icons.remove_circle_outline, color: scheme.onSurfaceVariant),
        l10n.withdrawalDisconnectStatusSkipped,
        muted,
      ),
    };

    // 행 머리 — 아이콘은 장식이라 낭독 0, 상태가 바뀌면 label 이 바뀐다.
    final header = Semantics(
      container: true,
      label: l10n.withdrawalDisconnectRowSemantic(label, status),
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(dimension: iconSize, child: icon),
          Gap(spacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: typography.titleMedium),
                Text(status, style: statusStyle),
              ],
            ),
          ),
        ],
      ),
    );

    final strategy = signInStrategy;
    final showSignIn =
        strategy != null &&
        isCurrent &&
        (row.status == DisconnectRowStatus.needsSignIn ||
            row.status == DisconnectRowStatus.mismatch ||
            row.status == DisconnectRowStatus.failed);
    final serverFailed =
        row.kind == DisconnectKind.server &&
        row.status == DisconnectRowStatus.failed;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: spacing.lg,
        vertical: spacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          if (row.status == DisconnectRowStatus.skipped)
            Padding(
              padding: EdgeInsetsDirectional.only(start: iconSize + spacing.lg),
              // container — 없으면 행 전체 폭 노드로 병합돼 행 머리보다 먼저
              // 낭독된다 (UI-SPEC §Semantics 함정 1).
              child: Semantics(
                container: true,
                child: Text(
                  l10n.withdrawalDisconnectSkippedGuide(label),
                  style: muted,
                ),
              ),
            ),
          if (showSignIn) ...[
            Gap(spacing.sm),
            // 브랜드 버튼 semantics 가 행 전체 노드로 병합되지 않게 세운다
            // (UI-SPEC §Semantics 함정 2).
            Semantics(
              container: true,
              child: SocialButton(
                strategy: strategy,
                isDisabled: disabled,
                onPressed: (_) => onSignIn(),
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: _SkipButton(
                label: label,
                onPressed: disabled ? null : onSkip,
              ),
            ),
          ],
          if (serverFailed)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _SkipButton(label: label, onPressed: disabled ? null : onSkip),
                _RetryButton(
                  label: label,
                  onPressed: disabled ? null : onRetry,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// 「건너뛰기」 버튼 — button + tap semantics 노드 (UI-SPEC §Semantics 함정 3).
class _SkipButton extends StatelessWidget {
  const _SkipButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Semantics(
      container: true,
      button: true,
      enabled: onPressed != null,
      label: l10n.withdrawalDisconnectSkipSemantic(label),
      onTap: onPressed,
      excludeSemantics: true,
      child: TextButton(
        onPressed: onPressed,
        child: Text(l10n.withdrawalDisconnectSkip),
      ),
    );
  }
}

/// 서버 행 「재시도」 버튼 — 건너뛰기 오른쪽 (M3 액션 순서).
class _RetryButton extends StatelessWidget {
  const _RetryButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Semantics(
      container: true,
      button: true,
      enabled: onPressed != null,
      label: l10n.withdrawalDisconnectRetrySemantic(label),
      onTap: onPressed,
      excludeSemantics: true,
      child: TextButton(onPressed: onPressed, child: Text(l10n.commonRetry)),
    );
  }
}

/// 아래 고정 영역 — 삭제 중 스피너 · 안내 · 「탈퇴」 (UI-SPEC §마지막 「탈퇴」).
class _FinalBar extends StatelessWidget {
  const _FinalBar({
    required this.allDone,
    required this.deleting,
    required this.enabled,
    required this.onDelete,
  });

  final bool allDone;
  final bool deleting;
  final bool enabled;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    final typography = context.appTypography;
    final scheme = context.colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        spacing.lg,
        spacing.sm,
        spacing.lg,
        spacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (deleting) ...[
            const Center(child: CircularProgressIndicator()),
            Gap(spacing.md),
          ],
          if (!allDone) ...[
            Text(
              l10n.withdrawalDisconnectFinalHint,
              style: typography.bodyMedium.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            Gap(spacing.sm),
          ],
          Semantics(
            container: true,
            button: true,
            enabled: enabled,
            label: l10n.withdrawalConfirmActionSemantic,
            onTap: enabled ? onDelete : null,
            excludeSemantics: true,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: enabled ? onDelete : null,
              child: Text(l10n.withdrawalConfirmAction),
            ),
          ),
        ],
      ),
    );
  }
}
