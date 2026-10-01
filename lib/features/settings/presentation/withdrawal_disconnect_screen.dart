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
import '../../../shared/widgets/error_snack_bar.dart';
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
/// 행 목록 서버 조회 중에는 소개 문단 아래 원형 스피너를 보인다(review
/// IN-02 — iteration 3). 행 목록 서버 조회가 실패하면 재시도 안내와 함께(WR-01), 끊을 행이 0 이면
/// 안내 없이(IN-04 · Q6-A) 이전 화면으로 돌아간다.
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

  /// 5분 창 초과로 삭제가 거부된 뒤 신선도를 되찾는다 (D-07 · C-02 · C-09).
  ///
  /// 판정은 서버 거부뿐이다(C-02 — 클라이언트 사전 점검 0). 해제한 provider 로
  /// 다시 로그인하면 provider 측 연결이 다시 생기고(재동의), 재인증 화면은
  /// 어느 provider 로 로그인했는지 돌려주지 않는다. 그래서:
  /// - (a) 「해제됨」 재로그인 행이 있으면 그 행을 다시 로그인 대기로 연다 —
  ///   그 행의 로그인이 신선도 갱신과 재해제를 한 번에 한다(재인증 화면 0).
  ///   재로그인 custom token 로그인에 실패했던 행은 대상이 아니다 (review
  ///   IN-01 — iteration 2 · 같은 실패 반복 루프 방지).
  /// - (b) 없으면 재인증 화면을 push 하고, 돌아오면 결과와 무관하게(취소 ·
  ///   실패한 재인증도 provider 단계에서 이미 재동의했을 수 있다) 이 화면에서
  ///   해제됐던 행을 다시 끊는다.
  ///
  /// 다시 연 행이 끝날 때까지 「탈퇴」 는 비활성이다 — 되살아난 연결을 남긴 채
  /// 삭제로 넘어가지 않는다.
  Future<void> _recoverFreshness() async {
    final notifier = _notifier;
    if (notifier.reopenRowForFreshness()) return;
    final router = GoRouter.of(context);
    // 재인증 목적 push 라 표시를 붙여야 guard 가 로그인 화면을 홈으로
    // 튕기지 않는다 (R_EXTRA_G3_REAUTH_LOGIN_BOUNCE).
    await router.push<bool>(AppRoutes.buildReauthLocation(AppRoutes.login));
    if (!mounted) return;
    await notifier.redisconnectAfterReauth();
  }

  /// 이 화면을 닫고 이전 화면(없으면 설정)으로 돌아간다.
  void _leave() {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
    } else {
      router.go(AppRoutes.settings);
    }
  }

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

    // 16.10 review WR-01: 행 목록 서버 조회가 실패하면 삭제로 이어지지 않게
    // 재시도를 안내하고 나간다(fail-closed). 다시 들어오면 처음부터다(D-14).
    ref.listen<WithdrawalDisconnectState>(withdrawalDisconnectProvider, (
      prev,
      next,
    ) {
      if (prev?.load == next.load) return;
      if (next.load == DisconnectRowsLoad.failed) {
        _showSnackBar(l10n.withdrawalFailureTransient);
        _leave();
        return;
      }
      // 16.10 review IN-04: 서버 조회로 확정된 행이 0 이면 이 화면은 「탈퇴」 가
      // 영구 비활성인 막다른 화면이다(`allDone` 은 행 ≥ 1 요구). UI-SPEC Q6-A
      // (「행 0 = 진행 화면 미표시 · 다이얼로그에서 바로 삭제」) 대로 나간다 —
      // 딥링크 · 라우터 복원 · 다이얼로그 판정 뒤 연결이 바뀐 경우다. 삭제는
      // 사용자가 다이얼로그에서 다시 확인할 때만 한다.
      if (next.load == DisconnectRowsLoad.loaded && next.rows.isEmpty) {
        _leave();
      }
    });

    // Phase 17 D-43 · UI-SPEC (A) — 같은 원인 같은 안내 · 실패 전이 1회당 1번.
    // 행 표시(「해제하지 못했습니다」 + 재시도)는 그대로 두고, 행이 App Check
    // 차단으로 실패 상태에 「들어서는」 전이에서만 SnackBar 를 띄운다 — 같은
    // 실패 상태의 재빌드 · 다른 행 갱신에는 다시 띄우지 않는다.
    ref.listen<WithdrawalDisconnectState>(withdrawalDisconnectProvider, (
      prev,
      next,
    ) {
      if (_enteredAppCheckFailure(prev?.rows ?? const [], next.rows)) {
        showErrorSnackBar(context, const AppCheckFailedException());
      }
    });

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
          unawaited(_recoverFreshness());
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
                    // 16.10 review IN-02 (iteration 3 · UI-SPEC §Surface W
                    // 「목록 조회 중」): 행 목록 서버 조회 중에는 행이 올
                    // 자리에 원형 스피너 1개를 둔다. pending 은 busy 가
                    // 아니라 back 을 막지 않는다(D-14).
                    if (state.load == DisconnectRowsLoad.pending)
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: spacing.lg),
                        child: Center(
                          child: CircularProgressIndicator(
                            semanticsLabel: l10n.commonLoading,
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
              // 같은 식이며 목록이 넘치지 않아도 항상 그린다. 두께는 인자 없이
              // M3 기본값(`_DividerDefaultsM3.thickness` 1.0)을 따른다 (16.10
              // review IN-04 — iteration 2).
              Container(
                decoration: BoxDecoration(
                  border: Border(top: Divider.createBorderSide(context)),
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

  /// [next] 에 App Check 차단([AppCheckFailedException])으로 실패 상태에
  /// 새로 들어선 행이 있는가 (Phase 17 D-43 · UI-SPEC (A) 행 4).
  ///
  /// 같은 provider 의 [prev] 행이 이미 실패였으면 전이가 아니다 — 재시도는
  /// 실패 → 해제 중 → 실패로 지나가므로 다시 전이로 센다.
  static bool _enteredAppCheckFailure(
    List<DisconnectRow> prev,
    List<DisconnectRow> next,
  ) {
    for (final row in next) {
      if (row.status != DisconnectRowStatus.failed ||
          row.failure is! AppCheckFailedException) {
        continue;
      }
      final before = prev.where((p) => p.provider == row.provider).firstOrNull;
      if (before?.status != DisconnectRowStatus.failed) return true;
    }
    return false;
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
