import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../../../../shared/widgets/keep_hangul_words_text.dart';
import '../app_terms_confirmation_slot.dart';

/// 약관 체크박스 그룹 (Phase 10 D-15, D-17, D-21 · 약관 링크 자리는 quick 261118-ocx · 261125-she 개정).
///
/// "전체 동의" 체크박스 + 이용약관(필수) + 개인정보처리방침(필수) +
/// 마케팅(선택) 4종 체크박스로 구성된다. 앱이 더한 필수 확인 행
/// ([confirmations])은 개인정보처리방침 다음 · 마케팅 앞에 [필수] 배지와 함께
/// 그리고, 안내 표시 중이면 체크하지 않은 행의 안내를 그 행 제목 아래에 오류
/// 색으로 둔다.
///
/// 각 약관 행은 이름 바로 뒤에 필수/선택 배지를 붙인다(한 줄에 안 들어가면
/// 다음 줄). 약관 본문이 있는 이용약관 · 개인정보처리방침 행은 이름 자체가
/// 강조색(`colorScheme.primary`) 밑줄 링크다 — 이름을 누르면 약관 화면이 열리고
/// 체크는 바뀌지 않으며, 체크는 체크박스 · 배지 · 행의 빈 자리 · "전체 동의"
/// 로 한다. 확인 행 · 마케팅 행 이름은 링크가 아니다(본문 색 · 밑줄 없음).
/// 스크린 리더는 체크 항목(행)과 링크를 따로 읽는다 — 링크는 약관 이름을
/// 읽고 "상세 보기"(`termsViewDetail`)를 안내로 읽는다.
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

/// 링크 행의 위아래 최소 여백 — (Material 3 한 줄 목표 높이 56 −
/// [kMinInteractiveDimension]) / 2.
///
/// 48 dp 링크 상자를 제목에 넣고도 행이 56 이다. 다른 행은 [ListTile] 기본값
/// (8)을 그대로 쓴다 — 모든 행을 4 로 줄이면 배지가 다음 줄로 내려간 행(en
/// 마케팅 64)까지 낮아져 행 높이가 승인 배치와 달라진다.
const double _linkRowMinVerticalPadding = 4;

/// 단일 약관 행 — 체크박스 + 제목 묶음(이름 · 배지 줄과 그 아래 안내).
///
/// 행은 [ListTile] 을 [Semantics] 로 감싼 꼴이다. [CheckboxListTile] 은 자식
/// semantics 를 `MergeSemantics` 로 하나로 합쳐 제목 안 링크가 행 노드에
/// 흡수되므로 쓰지 않는다 — 여기서는 행 노드가 체크 상태 · 이름 · 배지를 맡고,
/// 링크는 그 아래 자기 노드(link · 이름 label · "상세 보기" hint)가 된다.
/// 체크박스는 [ExcludeSemantics] · [ExcludeFocus] 로 감싸 행 노드와 겹치는
/// 작은 체크 노드 · 초점을 만들지 않는다(행 전체가 그 역할을 한다).
///
/// [onViewDetail] 이 있는 행은 이름이 링크다. 링크는 48 × 48 dp 이상 누르는
/// 상자([kMinInteractiveDimension])를 갖고, 그 상자가 행 높이 56 안에 들도록
/// 그 행만 위아래 여백을 [_linkRowMinVerticalPadding] 로 줄인다. 링크를 타일
/// 오른쪽 보조 자리에 두면 글자 배율만큼 폭을 먼저 가져가 이름 칸이 0 까지
/// 줄어든다 — 그래서 이름 자리에 둔다(quick 261118-ocx). 배지는 한 줄 폭보다
/// 넓을 때만 [FittedBox] 로 줄여 그린다.
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

  /// 약관 화면을 여는 콜백 — 있으면 이름이 링크가 된다.
  final VoidCallback? onViewDetail;

  /// 제목 아래에 오류 색으로 보일 안내 — null 이면 그리지 않는다.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    final typography = context.appTypography;
    final spacing = context.appSpacing;
    // 지역 변수로 받아 null 검사 뒤 승격한다(필드는 승격되지 않는다).
    final link = onViewDetail;
    final onRow = onChanged;

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

    // 이름은 행 노드 label 이 읽으므로 글리프 자체의 semantics 는 뺀다(두 번
    // 읽히지 않게). 링크는 자기 노드에서 이름을 읽는다.
    final Widget title = link == null
        ? ExcludeSemantics(
            child: KeepHangulWordsText(
              label,
              style: typography.bodyMedium.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
          )
        : Semantics(
            container: true,
            link: true,
            label: label,
            hint: l10n.termsViewDetail,
            child: InkWell(
              onTap: link,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: kMinInteractiveDimension,
                  minHeight: kMinInteractiveDimension,
                ),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: 1,
                  child: ExcludeSemantics(
                    child: KeepHangulWordsText(
                      label,
                      style: typography.bodyMedium.copyWith(
                        color: colorScheme.primary,
                        decoration: TextDecoration.underline,
                        decorationColor: colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );

    return Semantics(
      container: true,
      checked: value,
      label: label,
      child: ListTile(
        leading: ExcludeSemantics(
          child: ExcludeFocus(
            child: Checkbox(
              value: value,
              onChanged: onRow,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: spacing.sm,
              runSpacing: spacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [title, badge],
            ),
            if (hint != null)
              KeepHangulWordsText(
                hint!,
                style: typography.bodyMedium.copyWith(color: colorScheme.error),
              ),
          ],
        ),
        enabled: onRow != null,
        onTap: onRow == null ? null : () => onRow(!value),
        minVerticalPadding: link == null ? null : _linkRowMinVerticalPadding,
        // CheckboxListTile 과 같은 semantics — 행 노드에 button 표시를 붙이지
        // 않는다. SDK 가 임시 인자(temporary flag)로 적은 값이라 SDK 가 이
        // 인자를 지우면 이 줄도 지운다.
        internalAddSemanticForOnTap: false,
      ),
    );
  }
}
