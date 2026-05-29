// Phase 16 D-05/D-06/D-07/D-08 — Material 3 AlertDialog destructive UX 가드.
//
// UI-SPEC Surface C (line 277~314) verbatim 채택:
// - 3-line GDPR 경고 (withdrawalDialogBodyLine1/2/3).
// - confirmTextField verbatim 입력 가드 — 시각 hint (withdrawalConfirmFieldHint)
//   와 정확히 일치해야 confirm FilledButton 활성화.
// - destructive FilledButton (Theme.colorScheme.error 배경).
// - barrierDismissible:false during loading (D-08 UX 가드).
// - Semantics — withdrawalConfirmActionSemantic 으로 destructive intent
//   스크린리더 명시 (UI-SPEC line 332 Warning 7 채택).
//
// 분기 처리 (ref.listen):
// - AsyncValue.data → withdrawalSuccess SnackBar + Navigator.pop(true) +
//   router 가 signOut 후 /onboarding 으로 자동 reset.
// - AsyncValue.error(ReauthenticationRequiredException) →
//   withdrawalReauthRequired SnackBar + Navigator.pop(false) + /login push.
// - AsyncValue.error(기타) → withdrawalFailure SnackBar (dialog 유지 — 재시도).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../settings_notifier.dart';

/// 탈퇴 확인 다이얼로그 (Phase 16 D-05~D-08 / UI-SPEC Surface C).
///
/// AlertDialog + 3-line GDPR + confirmTextField verbatim 입력 가드 +
/// destructive FilledButton + Semantics destructive intent.
///
/// **D-08 UX 가드:**
/// - barrierDismissible:false (loading 중 backdrop tap 무시).
/// - confirmTextField 가 [AppLocalizations.withdrawalConfirmFieldHint] 와
///   정확히 일치 (verbatim match) 해야 confirm 버튼 활성화.
/// - destructive intent — Semantics label 가
///   [AppLocalizations.withdrawalConfirmActionSemantic] (영구 삭제 명시).
class WithdrawalConfirmationDialog extends ConsumerStatefulWidget {
  /// [WithdrawalConfirmationDialog] 를 생성한다.
  const WithdrawalConfirmationDialog({super.key});

  /// 다이얼로그를 표시하고 사용자 확인 결과를 반환한다.
  ///
  /// 반환값:
  /// - `true`: 사용자가 확인 → 탈퇴 호출 + 성공.
  /// - `false` / `null`: 사용자가 취소 또는 reauth fail (재로그인 요구).
  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const WithdrawalConfirmationDialog(),
    );
  }

  @override
  ConsumerState<WithdrawalConfirmationDialog> createState() =>
      _WithdrawalConfirmationDialogState();
}

class _WithdrawalConfirmationDialogState
    extends ConsumerState<WithdrawalConfirmationDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _verbatimMatch = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged(String value, String hint) {
    final next = value == hint;
    if (next != _verbatimMatch) {
      setState(() => _verbatimMatch = next);
    }
  }

  Future<void> _onConfirm() async {
    await ref.read(settingsProvider.notifier).requestAccountDeletion();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    final errorColor = context.colorScheme.error;
    final state = ref.watch(settingsProvider);
    final isLoading = state.isLoading;

    // ref.listen 으로 success/error 분기 처리.
    ref.listen<AsyncValue<void>>(settingsProvider, (prev, next) {
      // 직전이 loading 이고 next 가 data → success path.
      if (prev?.isLoading == true && next.hasValue && !next.hasError) {
        _showSnackBar(context, l10n.withdrawalSuccess);
        Navigator.of(context).pop(true);
        return;
      }
      if (next.hasError) {
        final error = next.error;
        if (error is ReauthenticationRequiredException) {
          _showSnackBar(context, l10n.withdrawalReauthRequired);
          Navigator.of(context).pop(false);
          context.push(AppRoutes.login);
        } else {
          // 기타 (UnknownException 포함) — SnackBar 만, dialog 유지 (재시도).
          _showSnackBar(context, l10n.withdrawalFailure);
        }
      }
    });

    return AlertDialog(
      title: Text(
        l10n.withdrawalDialogTitle,
        style: context.textTheme.titleLarge?.copyWith(color: errorColor),
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.withdrawalDialogBodyLine1,
              style: context.textTheme.bodyLarge,
            ),
            Gap(spacing.sm),
            Text(
              l10n.withdrawalDialogBodyLine2,
              style: context.textTheme.bodyLarge?.copyWith(
                color: errorColor,
                fontWeight: FontWeight.w500,
              ),
            ),
            Gap(spacing.sm),
            Text(
              l10n.withdrawalDialogBodyLine3,
              style: context.textTheme.bodyMedium?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
            Gap(spacing.xl),
            Text(
              l10n.withdrawalConfirmFieldLabel(l10n.withdrawalConfirmFieldHint),
              style: context.textTheme.bodyMedium,
            ),
            Gap(spacing.sm),
            TextField(
              controller: _controller,
              enabled: !isLoading,
              decoration: InputDecoration(
                hintText: l10n.withdrawalConfirmFieldHint,
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) =>
                  _onTextChanged(v, l10n.withdrawalConfirmFieldHint),
            ),
            if (isLoading) ...[
              Gap(spacing.md),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: isLoading ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        Semantics(
          button: true,
          label: l10n.withdrawalConfirmActionSemantic,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: errorColor,
              foregroundColor: context.colorScheme.onError,
            ),
            onPressed: (_verbatimMatch && !isLoading) ? _onConfirm : null,
            child: Text(l10n.withdrawalConfirmAction),
          ),
        ),
      ],
    );
  }

  void _showSnackBar(BuildContext context, String message) {
    // dialog 가 같은 BuildContext 위에 떠 있어 ScaffoldMessenger 는 root 의
    // 것을 자동 사용 — root context 의 SnackBar 노출.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
