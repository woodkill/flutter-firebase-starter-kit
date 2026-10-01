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
// - AsyncValue.error(AppCheckFailedException) → errorAppCheckFailed SnackBar
//   (Phase 17 D-42 · D-43 — 재로그인 라우팅 0 · dialog 유지).
// - AsyncValue.error(NetworkException 계열 / TooManyRequests /
//   ServiceUnavailable) → withdrawalFailureTransient SnackBar (WR-03 — 원인별
//   문구 · Phase 17 D-40 사진 삭제 실패 포함).
// - AsyncValue.error(그 외) → withdrawalFailure SnackBar (dialog 유지 — 재시도).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/data/auth_repository.dart';
import '../../data/disconnect/disconnect_steps.dart';
import '../settings_notifier.dart';
import '../withdrawal_disconnect_notifier.dart';

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
  /// - `true`: 사용자가 확인 → 탈퇴 호출 + 성공 (끊을 행 0 — 바로 삭제).
  /// - `false`: 다음 셋 중 하나 — 계정 삭제는 **호출되지 않았거나 실패**했다.
  ///   - 사용자가 취소.
  ///   - reauth fail (재로그인 요구 — 로그인 화면으로 push).
  ///   - 끊을 provider 행이 있어 탈퇴 진행 화면으로 넘김(Phase 16.10 D-05 —
  ///     삭제 미호출 · 진행 화면이 마지막에 삭제한다).
  /// - `null`: 다이얼로그가 결과 없이 닫힘(back 등).
  ///
  /// 행 목록 서버 조회가 실패하면(16.10 review WR-01) 다이얼로그는 닫히지 않고
  /// 재시도를 안내하므로 반환값이 없다.
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

  /// 확인 뒤 provider 목록을 서버에서 읽는 중인가 (16.10 review WR-01).
  ///
  /// 삭제 중(`settingsProvider` loading)과 같은 잠금 · 스피너를 쓴다 — 조회
  /// 중 이중 탭 · 이탈을 막는다.
  bool _resolvingRows = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 입력값 [value] 가 확인 문구 [hint] 와 일치하는지 갱신한다 (WR-06).
  ///
  /// 비교는 `trim()` + `toLowerCase()` 로 정규화한다. 정확 일치만 허용하면
  /// en 로케일 소문자 hint(`delete`) 에 키보드 자동완성/붙여넣기가 넣은
  /// trailing space 나 `Delete` 가 들어왔을 때 확인 버튼이 **영구 disabled**
  /// 이면서 사유 안내가 전혀 없다. 정규화해도 "문구를 그대로 입력한다" 는
  /// D-08 의도(의도적 마찰)는 유지된다 — 부분 입력은 여전히 불일치다.
  void _onTextChanged(String value, String hint) {
    final next = value.trim().toLowerCase() == hint.trim().toLowerCase();
    if (next != _verbatimMatch) {
      setState(() => _verbatimMatch = next);
    }
  }

  /// 「탈퇴」 확인을 처리한다 (Phase 16.10 D-05 · UI-SPEC §Surface W 진입).
  ///
  /// 끊을 provider 행이 하나 이상이면 다이얼로그를 닫고 탈퇴 진행 화면을
  /// 연다 — 이 시점에는 계정 삭제를 부르지 않는다. 행이 없으면(이메일/비밀번호만
  /// · 로그인 사용자 부재) 지금처럼 바로 삭제한다(Q6-A).
  ///
  /// 행의 입력은 서버 1회 조회다 (16.10 review WR-01). `currentUserProvider`
  /// 캐시는 연결 목록 읽기 실패 · 첫 emit 전을 빈 목록으로 흡수하므로, 그
  /// 값으로 「행 0 = 바로 삭제」 를 판정하면 필수 끊기(Kakao · LINE) 없이 계정이
  /// 삭제될 수 있다. 조회가 실패하면 삭제하지 않고 재시도를 안내한다
  /// (fail-closed · 다이얼로그 유지).
  ///
  /// 조회 reader 생성(Firebase 인스턴스 watch)의 throw 도 같은 실패로
  /// 흡수한다 (16.10 review IN-02 — iteration 2) — 확인 버튼이 잡히지 않은
  /// 예외로 끝나지 않고 재시도 안내가 뜬다.
  Future<void> _onConfirm() async {
    if (_resolvingRows) return;
    // await 전에 캡처한다.
    final steps = ref.read(disconnectStepsProvider);
    setState(() => _resolvingRows = true);
    final List<String> providerIds;
    try {
      // reader 읽기는 첫 await 전이라 mounted 상태에서 한다.
      final readProviderIds = ref.read(serverProviderIdsReaderProvider);
      providerIds = await readProviderIds();
    } on Object catch (e) {
      // PII 0 — runtimeType 만.
      if (kDebugMode) {
        debugPrint(
          'WithdrawalConfirmationDialog: provider 목록 서버 조회 실패 '
          'runtimeType=${e.runtimeType}',
        );
      }
      if (!mounted) return;
      setState(() => _resolvingRows = false);
      _showSnackBar(context, context.l10n.withdrawalFailureTransient);
      return;
    }
    if (!mounted) return;
    setState(() => _resolvingRows = false);
    final rows = buildDisconnectRows(providerIds, steps);
    if (rows.isEmpty) {
      await ref.read(settingsProvider.notifier).requestAccountDeletion();
      return;
    }
    // 다이얼로그를 닫으면 이 context 가 사라지므로 router 를 먼저 캡처한다.
    final router = GoRouter.of(context);
    Navigator.of(context).pop(false);
    unawaited(router.push(AppRoutes.withdrawalDisconnect));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    // WR-07: appTypography 가 AppTypography override 를 반영하는 유일한 경로.
    final typography = context.appTypography;
    final errorColor = context.colorScheme.error;
    final state = ref.watch(settingsProvider);
    // 삭제 중 또는 확인 뒤 서버 조회 중 (16.10 review WR-01) — 같은 잠금.
    final isLoading = state.isLoading || _resolvingRows;

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
          // 재인증 목적 push 라 표시를 붙여야 guard 분기 (6) 이 로그인 화면을
          // 홈으로 튕기지 않는다 (R_EXTRA_G3_REAUTH_LOGIN_BOUNCE).
          context.push(AppRoutes.buildReauthLocation(AppRoutes.login));
        } else {
          // 기타 — SnackBar 만, dialog 유지 (재시도).
          //
          // **WR-03:** 원인별 문구를 렌더한다. `SettingsRepository`
          // `_mapDeleteError` 가 `unavailable` / `deadline-exceeded` 를
          // [NoInternetConnection] ([NetworkException] 하위) 로,
          // `resource-exhausted` 를 [TooManyRequests] 로 분리해 두었는데
          // 표면이 모두 generic `withdrawalFailure` 로 collapse 되어 있어
          // taxonomy 분리가 사용자에게 아무 변화도 만들지 못했다
          // (2026-09-07 실측: dev Cloud Run 할당량 차단이 "회원탈퇴에
          // 실패했습니다" 로 표시되어 원인 오인 유발). Surface D 의
          // outcome 별 문구 분기와 동일한 정책이다.
          _showSnackBar(context, resolveWithdrawalFailureMessage(l10n, error));
        }
      }
    });

    // WR-05: barrierDismissible:false 는 backdrop tap 만 막는다. Android 의
    // 하드웨어 back / predictive back 은 여전히 다이얼로그를 pop 하므로,
    // 되돌릴 수 없는 삭제가 진행되는 동안 화면이 사라져 사용자가 성공/실패
    // 피드백을 전혀 받지 못한다 (D-08 "loading 중 이탈 차단" 미완성).
    //
    // **적용 전제 (CR-04):** 성공 emit 이 사후 정리(6개 소셜 SDK logout) 뒤에
    // 갇혀 있던 동안에는 이 back 제스처가 유일한 탈출구였다. CR-04 로 emit 이
    // 서버 삭제 확정 직후로 옮겨진 뒤에야 canPop 차단이 안전하다.
    return PopScope(
      canPop: !isLoading,
      child: AlertDialog(
        title: Text(
          l10n.withdrawalDialogTitle,
          style: typography.titleLarge.copyWith(color: errorColor),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.withdrawalDialogBodyLine1, style: typography.bodyLarge),
              Gap(spacing.sm),
              Text(
                l10n.withdrawalDialogBodyLine2,
                style: typography.bodyLarge.copyWith(
                  color: errorColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Gap(spacing.sm),
              Text(
                l10n.withdrawalDialogBodyLine3,
                style: typography.bodyMedium.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
              Gap(spacing.xl),
              Text(
                l10n.withdrawalConfirmFieldLabel(
                  l10n.withdrawalConfirmFieldHint,
                ),
                style: typography.bodyMedium,
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
            onPressed: isLoading
                ? null
                : () => Navigator.of(context).pop(false),
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
      ),
    );
  }

  void _showSnackBar(BuildContext context, String message) {
    // dialog 가 같은 BuildContext 위에 떠 있어 ScaffoldMessenger 는 root 의
    // 것을 자동 사용 — root context 의 SnackBar 노출.
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// 탈퇴 실패 [error] 를 원인별 SnackBar 문구로 변환한다 (WR-03).
///
/// 탈퇴 다이얼로그와 탈퇴 진행 화면(Phase 16.10 Surface W)이 공유한다.
///
/// 입력 계약은 `SettingsRepository._mapDeleteError` 가 만든 [AppException]
/// 서브타입이다. [ReauthenticationRequiredException] 은 호출처가 라우팅
/// 분기로 먼저 처리하므로 본 함수에 도달하지 않는다.
///
/// - [AppCheckFailedException] (SDK 계층 거부 · App Check 차단) —
///   [AppLocalizations.errorAppCheckFailed] (Phase 17 D-42 · D-43 · UI-SPEC
///   (A)). 재로그인 안내 · 라우팅이 아니다. transient arm 보다 앞에 둔다
///   ([AppCheckFailedException] 은 [ServiceUnavailable] 과 같은
///   [ServerException] 계열이라 순서가 의미를 가진다).
/// - [NetworkException] 계열 (`unavailable` / `deadline-exceeded`) /
///   [TooManyRequests] (`resource-exhausted`) / [ServiceUnavailable]
///   (사진 삭제 실패 `storage_cleanup_failed` · Phase 17 D-40 · UI-SPEC (W))
///   — 재시도로 해소 가능한 일시 오류이므로
///   [AppLocalizations.withdrawalFailureTransient].
/// - 그 외 ([UnknownException] 등) — 기존 generic
///   [AppLocalizations.withdrawalFailure] (UI-SPEC Surface C verbatim).
String resolveWithdrawalFailureMessage(AppLocalizations l10n, Object? error) {
  return switch (error) {
    AppCheckFailedException() => l10n.errorAppCheckFailed,
    NetworkException() ||
    TooManyRequests() ||
    ServiceUnavailable() => l10n.withdrawalFailureTransient,
    _ => l10n.withdrawalFailure,
  };
}
