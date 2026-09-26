// Phase 16.8 D-07 — 연결된 계정 해제 확인 다이얼로그 (UI-SPEC §Surface U).
//
// 회원탈퇴 다이얼로그보다 가볍다: 체크박스 · 텍스트 입력 없이 [취소] [해제]
// 2 액션뿐이고, 두 액션 모두 M3 기본 `TextButton` 이다(error 색 0 — Q2-A).
// barrierDismissible 은 기본값(true)이며, 처리 중에는 `PopScope` 가 back ·
// barrier 닫힘을 막는다.
//
// 결과는 `Navigator.pop<AccountUnlinkOutcome?>` 로 돌려주고 SnackBar · 재로그인
// 라우팅은 설정 화면이 맡는다(콜백형). 취소 · barrier · back = `null`.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../settings_notifier.dart';

/// 연결된 계정 해제 확인 다이얼로그 (Phase 16.8 D-07 · UI-SPEC §Surface U).
///
/// 「해제」 를 누르면 다이얼로그가 닫히지 않고 두 액션 비활성 + 본문 아래
/// 스피너를 표시한 채 [SettingsNotifier.unlinkProvider] 를 기다린 뒤, 그 결과
/// [AccountUnlinkOutcome] 을 `pop` 으로 돌려준다.
class UnlinkConfirmationDialog extends ConsumerStatefulWidget {
  /// [UnlinkConfirmationDialog] 를 생성한다.
  const UnlinkConfirmationDialog({
    super.key,
    required this.providerId,
    required this.providerLabel,
  });

  /// 해제할 provider id (`User.providerIds` 원소 — native URI 또는 CT slug).
  final String providerId;

  /// 제목 · 본문에 넣을 provider 라벨 (`formatProviderLabels` 결과).
  final String providerLabel;

  /// 다이얼로그를 표시하고 해제 결과를 반환한다.
  ///
  /// 반환값:
  /// - [AccountUnlinkOutcome] — 「해제」 를 눌러 notifier 가 돌려준 결과.
  /// - `null` — 취소 · barrier 탭 · back (호출자는 `cancelled` 로 다룬다).
  static Future<AccountUnlinkOutcome?> show(
    BuildContext context, {
    required String providerId,
    required String providerLabel,
  }) {
    return showDialog<AccountUnlinkOutcome>(
      context: context,
      builder: (_) => UnlinkConfirmationDialog(
        providerId: providerId,
        providerLabel: providerLabel,
      ),
    );
  }

  @override
  ConsumerState<UnlinkConfirmationDialog> createState() =>
      _UnlinkConfirmationDialogState();
}

class _UnlinkConfirmationDialogState
    extends ConsumerState<UnlinkConfirmationDialog> {
  /// 해제 진행 중 여부 — 탈퇴 전용 notifier state 와 공유하지 않는다 (WR-02).
  bool _busy = false;

  /// 「해제」 — 진행 표시 후 notifier 에 위임하고 결과로 닫는다.
  Future<void> _onConfirm() async {
    setState(() => _busy = true);
    final outcome = await ref
        .read(settingsProvider.notifier)
        .unlinkProvider(widget.providerId);
    if (!mounted) return;
    Navigator.of(context).pop(outcome);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    // WR-07: appTypography 가 AppTypography override 를 반영하는 유일한 경로.
    final typography = context.appTypography;
    final body = Text(
      l10n.settingsUnlinkDialogBody(widget.providerLabel),
      style: typography.bodyMedium,
    );

    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(
          l10n.settingsUnlinkDialogTitle(widget.providerLabel),
          style: typography.headlineSmall,
        ),
        content: _busy
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  body,
                  Gap(spacing.md),
                  const Center(child: CircularProgressIndicator()),
                ],
              )
            : body,
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: _busy ? null : _onConfirm,
            child: Text(l10n.settingsUnlinkConfirmAction),
          ),
        ],
      ),
    );
  }
}
