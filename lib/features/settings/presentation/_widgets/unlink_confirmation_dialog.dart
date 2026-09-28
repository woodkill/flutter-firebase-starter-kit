// Phase 16.8 D-07 — 연결된 계정 해제 확인 다이얼로그 (UI-SPEC §Surface U).
//
// 회원탈퇴 다이얼로그보다 가볍다: 체크박스 · 텍스트 입력 없이 [취소] [해제]
// 2 액션뿐이고, 두 액션 모두 M3 기본 `TextButton` 이다(error 색 0 — Q2-A).
// barrierDismissible 은 기본값(true)이며, 처리 중에는 `PopScope` 가 back ·
// barrier 닫힘을 막는다.
//
// 결과는 `Navigator.pop<AccountUnlinkOutcome?>` 로 돌려주고 SnackBar · 재로그인
// 라우팅은 설정 화면이 맡는다(콜백형). 취소 · barrier · back = `null`.
//
// Phase 16.10 D-09 · D-10 · D-11 · D-19 (UI-SPEC §Surface U′ · Q7-A) — 새
// 화면 없이 content 만 확장한다. 「해제」 는 provider 측 끊기 → 성공 시에만 킷
// 해제이며(16.8 D-08 「킷 쪽만 해제」 폐기), 본문 아래에 앱 연결(권한) 해제
// 고지(provider 6종 공통)와 재로그인 provider 의 로그인 안내가 붙는다. 재로그인
// 여부는 끊기 레지스트리의 행 종류로 판정한다 — 다이얼로그 안에 provider 별
// 분기를 두지 않는다(C-08). 제목 · 액션 · `PopScope` · 결과 pop 구조는 16.8
// 그대로다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../../../core/auth/provider_id.dart';
import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../../data/disconnect/disconnect_step.dart';
import '../../data/disconnect/disconnect_steps.dart';
import '../settings_notifier.dart';

/// 연결된 계정 해제 확인 다이얼로그 (Phase 16.8 D-07 · UI-SPEC §Surface U).
///
/// 「해제」 를 누르면 다이얼로그가 닫히지 않고 두 액션 비활성 + 본문 아래
/// 스피너를 표시한 채 [SettingsNotifier.disconnectAndUnlinkProvider] (provider
/// 로그인 · 끊기 · 킷 해제)를 기다린 뒤, 그 결과 [AccountUnlinkOutcome] 을
/// `pop` 으로 돌려준다 (Phase 16.10 D-10 · D-11).
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
  ///
  /// provider 로그인 · 끊기 · 킷 해제가 끝날 때까지 busy 를 유지한다 (UI-SPEC
  /// E5 loading). provider 로그인 취소도 결과(`cancelled`)로 닫힌다.
  Future<void> _onConfirm() async {
    setState(() => _busy = true);
    final outcome = await ref
        .read(settingsProvider.notifier)
        .disconnectAndUnlinkProvider(widget.providerId);
    if (!mounted) return;
    Navigator.of(context).pop(outcome);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    // WR-07: appTypography 가 AppTypography override 를 반영하는 유일한 경로.
    final typography = context.appTypography;
    final label = widget.providerLabel;
    // 끊기 레지스트리 조회 — 행이 없으면(이메일/비밀번호) provider 측 연결이
    // 없어 고지 · 안내를 붙이지 않는다 (D-09 범위 = provider 6종).
    final provider = AccountProvider.tryParse(widget.providerId);
    final step = provider == null
        ? null
        : disconnectStepFor(ref.watch(disconnectStepsProvider), provider);
    final paragraphs = <String>[
      l10n.settingsUnlinkDialogBody(label),
      // 앱 연결(권한) 해제 고지 — provider 6종 공통 (D-19 · C-09).
      if (step != null) l10n.settingsUnlinkDialogDisclosure(label),
      // 해제에 provider 로그인 1회가 필요한 행만 안내한다 (D-10 · Q7-A).
      if (step?.kind == DisconnectKind.relogin)
        l10n.settingsUnlinkDialogSignInGuide(label),
    ];

    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(
          l10n.settingsUnlinkDialogTitle(label),
          style: typography.headlineSmall,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < paragraphs.length; i++) ...[
              if (i > 0) Gap(spacing.sm),
              Text(paragraphs[i], style: typography.bodyMedium),
            ],
            if (_busy) ...[
              Gap(spacing.md),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
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
