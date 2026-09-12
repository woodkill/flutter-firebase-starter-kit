import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/theme_extensions.dart';

/// 약관 체크박스 그룹 (Phase 10 D-15, D-17, D-21).
///
/// "전체 동의" 체크박스 + 이용약관(필수) + 개인정보처리방침(필수) +
/// 마케팅(선택) 4종 체크박스로 구성된다. 필수/선택 배지와 "상세 보기"
/// 링크를 포함한다.
///
/// **10-REVIEW WR-16 — 단일 진실원:** 본 위젯은 상태를 보유하지 않는
/// [StatelessWidget] 이며, 3 플래그와 [allChecked] 를 부모(OnboardingScreen)
/// 에게서 받아 렌더만 한다. 이전에는 동일한 3 플래그를 자식 State 와 부모
/// State 가 각각 보유하고 콜백으로 동기화했는데, 그 구조에서는 (a) 부모가
/// `setState` 로 자식을 재생성하는 변경(`key` 부여, 조건부 렌더 등)에서
/// 즉시 desync 하고 (b) "전체 동의" 판정이 자식에만 있어 부모가 marketing
/// 포함 여부를 재계산할 수 없었다.
class TermsCheckboxGroup extends StatelessWidget {
  /// [TermsCheckboxGroup] 를 생성한다.
  const TermsCheckboxGroup({
    required this.service,
    required this.privacy,
    required this.marketing,
    required this.allChecked,
    required this.onServiceChanged,
    required this.onPrivacyChanged,
    required this.onMarketingChanged,
    required this.onAllChanged,
    super.key,
  });

  /// 이용약관(필수) 동의 여부.
  final bool service;

  /// 개인정보처리방침(필수) 동의 여부.
  final bool privacy;

  /// 마케팅(선택) 동의 여부.
  final bool marketing;

  /// "전체 동의" 체크박스의 표시 값.
  ///
  /// 부모가 계산해 내려보낸다 (WR-16) — 자식이 3 플래그로 재유도하면 "전체
  /// 동의" 의 의미(마케팅 포함 여부)가 두 곳에 존재하게 된다.
  final bool allChecked;

  /// 이용약관 체크 변경 콜백.
  final ValueChanged<bool?> onServiceChanged;

  /// 개인정보처리방침 체크 변경 콜백.
  final ValueChanged<bool?> onPrivacyChanged;

  /// 마케팅 체크 변경 콜백.
  final ValueChanged<bool?> onMarketingChanged;

  /// "전체 동의" 체크 변경 콜백 — 3 플래그를 한 번에 설정한다.
  final ValueChanged<bool?> onAllChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    final typography = context.appTypography;
    final spacing = context.appSpacing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CheckboxListTile(
          value: allChecked,
          onChanged: onAllChanged,
          title: Text(l10n.termsAcceptAll, style: typography.labelLarge),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        Divider(
          color: colorScheme.outlineVariant,
          indent: spacing.lg,
          endIndent: spacing.lg,
        ),
        _TermsRow(
          value: service,
          onChanged: onServiceChanged,
          label: l10n.termsService,
          isRequired: true,
          onViewDetail: () => context.push(AppRoutes.termsService),
        ),
        _TermsRow(
          value: privacy,
          onChanged: onPrivacyChanged,
          label: l10n.termsPrivacy,
          isRequired: true,
          onViewDetail: () => context.push(AppRoutes.termsPrivacy),
        ),
        _TermsRow(
          value: marketing,
          onChanged: onMarketingChanged,
          label: l10n.termsMarketing,
          isRequired: false,
          onViewDetail: null,
        ),
      ],
    );
  }
}

/// 단일 약관 행 (체크박스 + 라벨 + 필수/선택 배지 + 상세 보기 링크).
class _TermsRow extends StatelessWidget {
  const _TermsRow({
    required this.value,
    required this.onChanged,
    required this.label,
    required this.isRequired,
    required this.onViewDetail,
  });

  final bool value;
  final ValueChanged<bool?> onChanged;
  final String label;
  final bool isRequired;
  final VoidCallback? onViewDetail;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    final typography = context.appTypography;
    final spacing = context.appSpacing;

    final badge = Container(
      // IN-03: 매직 넘버 대신 spacing 스케일에서 유도한다 — 세로 여백은
      // xs 의 절반(2), 모서리 반경은 xs(4). 사용자가 AppSpacing 을 교체하면
      // 배지도 함께 따라간다.
      padding: EdgeInsets.symmetric(
        horizontal: spacing.sm,
        vertical: spacing.xs / 2,
      ),
      decoration: BoxDecoration(
        color: isRequired
            ? colorScheme.errorContainer
            : colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(spacing.xs),
      ),
      child: Text(
        isRequired ? l10n.termsRequired : l10n.termsOptional,
        style: typography.bodyMedium.copyWith(
          color: isRequired
              ? colorScheme.onErrorContainer
              : colorScheme.onSurfaceVariant,
        ),
      ),
    );

    return CheckboxListTile(
      value: value,
      onChanged: onChanged,
      title: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: typography.bodyMedium.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
          ),
          Gap(spacing.sm),
          badge,
        ],
      ),
      secondary: onViewDetail != null
          ? TextButton(
              onPressed: onViewDetail,
              child: Text(l10n.termsViewDetail),
            )
          : null,
      controlAffinity: ListTileControlAffinity.leading,
    );
  }
}
