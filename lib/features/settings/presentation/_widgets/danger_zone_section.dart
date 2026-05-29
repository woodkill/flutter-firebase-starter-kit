// Phase 16 D-05~D-08 — Danger Zone section (UI-SPEC Surface B line 261~275).
//
// 위험 작업 (회원탈퇴) 를 격리한 시각적 section. Material 3 ListTile +
// Theme.colorScheme.error 강조 + WithdrawalConfirmationDialog 진입 path.
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/theme/theme_extensions.dart';
import 'withdrawal_confirmation_dialog.dart';

/// 위험 영역 격리 섹션 위젯 (Phase 16 D-05~D-08).
///
/// "Danger zone" heading + explainer 안내 + 회원탈퇴 ListTile 의 3-element
/// 구성. 탈퇴 ListTile 은 [ColorScheme.error] 로 destructive intent 를
/// 강조하며 탭 시 [WithdrawalConfirmationDialog.show] 호출.
class DangerZoneSection extends StatelessWidget {
  /// [DangerZoneSection] 을 생성한다.
  const DangerZoneSection({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    final errorColor = context.colorScheme.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            spacing.lg,
            spacing.sm,
            spacing.lg,
            spacing.xs,
          ),
          child: Text(
            l10n.settingsDangerZoneSection,
            style: context.textTheme.titleSmall?.copyWith(
              color: errorColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            spacing.lg,
            0,
            spacing.lg,
            spacing.sm,
          ),
          child: Text(
            l10n.settingsDangerZoneExplainer,
            style: context.textTheme.bodySmall?.copyWith(
              color: context.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Gap(spacing.xs),
        ListTile(
          leading: Icon(Icons.delete_forever, color: errorColor),
          title: Text(
            l10n.settingsWithdrawalLabel,
            style: context.textTheme.titleMedium?.copyWith(color: errorColor),
          ),
          trailing: Icon(Icons.chevron_right, color: errorColor),
          onTap: () => WithdrawalConfirmationDialog.show(context),
        ),
      ],
    );
  }
}
