import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
/// [onStateChanged] 콜백으로 상위 위젯(OnboardingScreen)에 (service,
/// privacy, marketing) 3개 플래그를 전달하여 "시작하기" CTA 활성화 여부를
/// 결정하게 한다.
class TermsCheckboxGroup extends ConsumerStatefulWidget {
  /// [TermsCheckboxGroup] 를 생성한다.
  const TermsCheckboxGroup({required this.onStateChanged, super.key});

  /// (service, privacy, marketing) 3개 플래그를 부모에게 통지하는 콜백.
  final void Function(bool service, bool privacy, bool marketing)
  onStateChanged;

  @override
  ConsumerState<TermsCheckboxGroup> createState() => _TermsCheckboxGroupState();
}

class _TermsCheckboxGroupState extends ConsumerState<TermsCheckboxGroup> {
  bool _service = false;
  bool _privacy = false;
  bool _marketing = false;

  bool get _allChecked => _service && _privacy && _marketing;

  void _notify() => widget.onStateChanged(_service, _privacy, _marketing);

  void _toggleAll(bool? value) {
    final next = value ?? false;
    setState(() {
      _service = next;
      _privacy = next;
      _marketing = next;
    });
    _notify();
  }

  void _toggleService(bool? v) {
    setState(() => _service = v ?? false);
    _notify();
  }

  void _togglePrivacy(bool? v) {
    setState(() => _privacy = v ?? false);
    _notify();
  }

  void _toggleMarketing(bool? v) {
    setState(() => _marketing = v ?? false);
    _notify();
  }

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
          value: _allChecked,
          onChanged: _toggleAll,
          title: Text(l10n.termsAcceptAll, style: typography.labelLarge),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        Divider(
          color: colorScheme.outlineVariant,
          indent: spacing.lg,
          endIndent: spacing.lg,
        ),
        _TermsRow(
          value: _service,
          onChanged: _toggleService,
          label: l10n.termsService,
          isRequired: true,
          onViewDetail: () => context.push(AppRoutes.termsService),
        ),
        _TermsRow(
          value: _privacy,
          onChanged: _togglePrivacy,
          label: l10n.termsPrivacy,
          isRequired: true,
          onViewDetail: () => context.push(AppRoutes.termsPrivacy),
        ),
        _TermsRow(
          value: _marketing,
          onChanged: _toggleMarketing,
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
