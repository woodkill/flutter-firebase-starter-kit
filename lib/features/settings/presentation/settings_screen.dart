// Phase 16 D-05/D-06/D-07/D-08 — Material 3 ListView + Danger zone 격리
// section + Withdrawal 진입 path.
//
// UI-SPEC Surface B (line 248~275) verbatim 채택:
// - 계정 section: 이메일 + 연결된 로그인 (linkedProviders join).
// - Danger zone section: explainer + 회원탈퇴 ListTile (destructive color).
// - 탈퇴 ListTile tap → WithdrawalConfirmationDialog.show.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../auth/data/auth_repository.dart';
import '../../home/presentation/provider_label_formatter.dart';
import '_widgets/danger_zone_section.dart';

/// 설정 화면 (Phase 16 D-05~D-08).
///
/// Material 3 ListView 기반 — 계정 section + Danger zone section 의 2-section
/// 구성. Danger zone 의 탈퇴 ListTile 은 `Theme.colorScheme.error` 로 강조
/// 표시되며 탭 시 `WithdrawalConfirmationDialog` 가 표시된다.
///
/// **UI-SPEC Surface B verbatim mirror** (16-UI-SPEC.md line 248~275):
/// - 계정 section (settingsAccountSection) — 이메일 + 연결된 로그인.
/// - Danger zone section (settingsDangerZoneSection) — explainer +
///   회원탈퇴 ListTile (Icons.delete_forever + destructive 색상).
class SettingsScreen extends ConsumerWidget {
  /// [SettingsScreen] 을 생성한다.
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    final user = ref.watch(currentUserProvider);

    final email = user?.email ?? '-';
    final providerIds = user?.providerIds ?? const <String>[];
    final providersLabel = formatProviderIds(providerIds, l10n);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: EdgeInsets.symmetric(vertical: spacing.md),
        children: [
          // 계정 section heading.
          Padding(
            padding: EdgeInsets.fromLTRB(
              spacing.lg,
              spacing.sm,
              spacing.lg,
              spacing.xs,
            ),
            child: Text(
              l10n.settingsAccountSection,
              style: context.textTheme.titleSmall?.copyWith(
                color: context.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.alternate_email),
            title: Text(l10n.settingsAccountEmail(email)),
          ),
          ListTile(
            leading: const Icon(Icons.link),
            title: Text(l10n.settingsLinkedProviders(providersLabel)),
          ),
          Gap(spacing.xxl),
          // Danger zone — UI-SPEC line 261~275.
          const DangerZoneSection(),
        ],
      ),
    );
  }
}
