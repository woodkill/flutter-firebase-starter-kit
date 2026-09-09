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
///
/// 탈퇴 ListTile 은 [Semantics] 로 감싸 스크린리더에 button 으로 노출하며,
/// 라벨은 탈퇴 라벨과 섹션명 두 기존 ARB 키를 `' | '` 로 이은 값이다 —
/// 신규 ARB 키를 만들지 않으므로 3 locale 이 자동으로 함께 따라간다.
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
            // Layout Contract Surface B verbatim — role 자체가 이미
            // Medium weight 라 별도 override 를 두지 않는다.
            style: context.textTheme.labelMedium?.copyWith(
              color: errorColor,
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
            style: context.textTheme.bodyMedium?.copyWith(
              color: context.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Gap(spacing.xs),
        Semantics(
          // container/excludeSemantics 를 함께 지정해야 라벨이 자체 노드로
          // 선다 — 미지정 시 heading·explainer 와 한 노드로 병합돼 버튼이
          // 아닌 컨테이너 문구가 된다. 탭 액션은 아래 onTap 으로 유지한다.
          container: true,
          excludeSemantics: true,
          button: true,
          label:
              '${l10n.settingsWithdrawalLabel} | '
              '${l10n.settingsDangerZoneSection}',
          onTap: () => WithdrawalConfirmationDialog.show(context),
          child: ListTile(
            leading: Icon(Icons.delete_forever, color: errorColor),
            title: Text(
              l10n.settingsWithdrawalLabel,
              style: context.textTheme.titleMedium?.copyWith(color: errorColor),
            ),
            // chevron 은 Settings list item 공통 accent 대상 (UI-SPEC 의
            // accent 화이트리스트 첫 항목) — destructive 강조는 leading
            // icon + title 2요소가 유지한다.
            trailing: Icon(
              Icons.chevron_right,
              color: context.colorScheme.primary,
            ),
            onTap: () => WithdrawalConfirmationDialog.show(context),
          ),
        ),
      ],
    );
  }
}
