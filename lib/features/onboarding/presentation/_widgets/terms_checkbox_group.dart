import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../../../../shared/widgets/keep_hangul_words_text.dart';
import '../app_terms_confirmation_slot.dart';

/// 약관 체크박스 그룹 (Phase 10 D-15, D-17, D-21 · 「상세 보기」 자리는 quick 261118-ocx 개정).
///
/// "전체 동의" 체크박스 + 이용약관(필수) + 개인정보처리방침(필수) +
/// 마케팅(선택) 4종 체크박스로 구성된다. 필수/선택 배지와 "상세 보기"
/// 링크를 포함한다. 앱이 더한 필수 확인 행([confirmations])은 개인정보처리방침
/// 다음 · 마케팅 앞에 [필수] 배지와 함께 「상세 보기」 없이 그리고, 안내
/// 표시 중이면 체크하지 않은 행의 안내를 그 행 제목 아래에 오류 색으로 둔다.
///
/// 각 약관 행은 이름 바로 뒤에 필수/선택 배지를 붙이고(한 줄에 안 들어가면
/// 다음 줄), "상세 보기" 글자 버튼을 이름 아래 줄에 이름과 같은 시작선으로
/// 둔다.
///
/// **10-REVIEW WR-16 — 단일 진실원:** 본 위젯은 상태를 보유하지 않는
/// [StatelessWidget] 이며, 3 플래그와 [allChecked] 를 부모(OnboardingScreen)
/// 에게서 받아 렌더만 한다. 이전에는 동일한 3 플래그를 자식 State 와 부모
/// State 가 각각 보유하고 콜백으로 동기화했는데, 그 구조에서는 (a) 부모가
/// `setState` 로 자식을 재생성하는 변경(`key` 부여, 조건부 렌더 등)에서
/// 즉시 desync 하고 (b) "전체 동의" 판정이 자식에만 있어 부모가 marketing
/// 포함 여부를 재계산할 수 없었다. 확인 행 목록 · 체크 값 · 안내 표시 여부도
/// 부모가 내려보낸다(행은 부모가 사용자 파일에서 받아 넘긴다).
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
    this.confirmations = const <AppTermsConfirmation>[],
    this.confirmationChecks = const <bool>[],
    this.onConfirmationChanged,
    this.showConfirmationHints = false,
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

  /// "전체 동의" 체크 변경 콜백 — 3 플래그와 확인 행을 한 번에 설정한다.
  final ValueChanged<bool?> onAllChanged;

  /// 앱이 더한 필수 확인 행 — 위에서부터 화면 순서다. 기본값은 빈 목록이다.
  final List<AppTermsConfirmation> confirmations;

  /// [confirmations] 각 행의 체크 값 — 같은 index 끼리 짝이다.
  final List<bool> confirmationChecks;

  /// 확인 행 체크 변경 콜백 — 바뀐 행의 index 와 새 값을 넘긴다.
  ///
  /// null 이면 확인 행 타일을 끈다 — 켜진 모양인데 눌러도 바뀌지 않는 행을
  /// 그리지 않는다.
  final void Function(int index, bool? value)? onConfirmationChanged;

  /// 체크하지 않은 확인 행의 안내를 보일지 — 부모가 필수 미충족 오류를 보일
  /// 때 켠다.
  final bool showConfirmationHints;

  /// 확인 행 [index] 아래에 보일 안내 — 보이지 않을 때는 null 이다.
  String? _hintFor(int index) =>
      showConfirmationHints && !confirmationChecks[index]
      ? confirmations[index].missingHint
      : null;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final typography = context.appTypography;
    final spacing = context.appSpacing;
    // 길이 검사는 생성자 assert 대신 여기서 한다 — 생성자 assert 의 List.length 는
    // const 생성 자리(시험의 const 묶음)에서 상수 식이 아니라 컴파일 오류가 난다.
    assert(
      confirmationChecks.length == confirmations.length,
      'confirmationChecks 는 confirmations 와 길이가 같아야 한다.',
    );
    // 지역 변수로 받아 null 검사 뒤 승격한다(필드는 승격되지 않는다).
    final onConfirmation = onConfirmationChanged;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CheckboxListTile(
          value: allChecked,
          onChanged: onAllChanged,
          title: KeepHangulWordsText(
            l10n.termsAcceptAll,
            style: typography.labelLarge,
          ),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        Divider(indent: spacing.lg, endIndent: spacing.lg),
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
        for (var i = 0; i < confirmations.length; i++)
          _TermsRow(
            value: confirmationChecks[i],
            onChanged: onConfirmation == null
                ? null
                : (v) => onConfirmation(i, v),
            label: confirmations[i].label,
            isRequired: true,
            onViewDetail: null,
            hint: _hintFor(i),
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

/// 단일 약관 행 — 체크박스 + 제목 묶음(이름 · 배지 줄과 그 아래 "상세 보기").
///
/// "상세 보기" 를 타일 오른쪽 보조 자리에 두면 그 버튼이 글자 배율만큼 폭을
/// 먼저 가져가 이름 칸이 0 까지 줄어든다 — 그래서 제목 안 아래 줄에 둔다
/// (quick 261118-ocx). 배지는 한 줄 폭보다 넓을 때만 [FittedBox] 로 줄여
/// 그린다.
class _TermsRow extends StatelessWidget {
  const _TermsRow({
    required this.value,
    required this.onChanged,
    required this.label,
    required this.isRequired,
    required this.onViewDetail,
    this.hint,
  });

  final bool value;

  /// 체크 변경 콜백 — null 이면 타일이 꺼진다.
  final ValueChanged<bool?>? onChanged;
  final String label;
  final bool isRequired;
  final VoidCallback? onViewDetail;

  /// 제목 아래에 오류 색으로 보일 안내 — null 이면 그리지 않는다.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    final typography = context.appTypography;
    final spacing = context.appSpacing;

    final badge = FittedBox(
      fit: BoxFit.scaleDown,
      child: Container(
        // IN-03: 매직 넘버 대신 토큰에서 유도한다 — 세로 여백은 간격 xs 의
        // 절반(2), 모서리 반경은 둥글기 xs(4). 사용자가 토큰을 바꾸면 배지도
        // 함께 따라간다.
        padding: EdgeInsets.symmetric(
          horizontal: spacing.sm,
          vertical: spacing.xs / 2,
        ),
        decoration: BoxDecoration(
          color: isRequired
              ? colorScheme.errorContainer
              : colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(context.appRadius.xs),
        ),
        child: KeepHangulWordsText(
          isRequired ? l10n.termsRequired : l10n.termsOptional,
          style: typography.bodyMedium.copyWith(
            color: isRequired
                ? colorScheme.onErrorContainer
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );

    return CheckboxListTile(
      value: value,
      onChanged: onChanged,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: spacing.sm,
            runSpacing: spacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              KeepHangulWordsText(
                label,
                style: typography.bodyMedium.copyWith(
                  color: colorScheme.onSurface,
                ),
              ),
              badge,
            ],
          ),
          if (onViewDetail != null)
            TextButton(
              onPressed: onViewDetail,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                // Material 3 TextButton 기본 최소 높이(Size(64, 40))의 높이 —
                // 승인 렌더 값.
                minimumSize: const Size(kMinInteractiveDimension, 40),
                alignment: AlignmentDirectional.centerStart,
              ),
              child: KeepHangulWordsText(l10n.termsViewDetail),
            ),
          if (hint != null)
            KeepHangulWordsText(
              hint!,
              style: typography.bodyMedium.copyWith(color: colorScheme.error),
            ),
        ],
      ),
      controlAffinity: ListTileControlAffinity.leading,
    );
  }
}
