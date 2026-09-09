// Phase 16 D-01/D-02/D-03 — LoginPromptSheet mirror (RESEARCH Pattern 6
// verbatim). 동일 이메일 충돌 직후 노출되는 modal bottom sheet — 기존
// provider 단일 강조 (D-02 single button) + cancel 시 state 손실 0 (D-03).
//
// Plan 16-04 (Task 4.2) — Plan 16-01 placeholder 본체 채움 완료.
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/provider_id.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/error/result.dart';
import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../data/auth_repository.dart';
import 'auth_in_progress_overlay.dart';
import 'branded_social_button.dart';

/// step 1 "기존 provider 로 로그인" 결과 override 콜백 시그니처
/// (Phase 16 Plan 16-19 seam).
///
/// 반환 `true` = step 1 로그인 성공, `false` = 취소 또는 실패. 테스트 / 호출처
/// 커스텀 override 전용 seam 이며 **프로덕션 호출처는 주입하지 않는다** —
/// 미주입 시 sheet 가 [AuthRepository.signInWithExistingProvider] 를 직접
/// 호출한다 (실 repository 경로).
typedef ExistingProviderSignInCallback =
    Future<bool> Function(AccountProvider existingProvider);

/// 계정 연동 Bottom Sheet (Phase 16 D-01 / D-02 / D-03).
///
/// 동일 이메일이 다른 provider 로 이미 가입된 상황을 감지하면 (D-12 의
/// `lookupSignInMethods` callable wiring 또는 identity_index conflictKind
/// existingProvider 응답) login_screen 의 catch path 가 본 sheet 를
/// 즉시 노출한다.
///
/// **레이아웃 (top → bottom):**
/// 1. Drag handle (Material 3 기본, `showDragHandle: true`)
/// 2. [Gap] lg
/// 3. 헤더 텍스트 (`accountLinkingSheetTitle` 또는 fallback)
/// 4. [Gap] sm
/// 5. 본문 텍스트 (`errorAccountExistsWithProvider({provider})` 또는 unknown
///    fallback)
/// 6. [Gap] xl
/// 7. 단일 BrandedSocialButton — [existingProvider] 에 매핑된 brand button
///    (email 인 경우 FilledButton fallback)
/// 8. [Gap] md
/// 9. TextButton "다른 방식으로 로그인" — 탭 시 Navigator.pop(false) (D-03)
/// 10. [Gap] lg (safe-area 하단)
///
/// **D-02 single button assertion:** 7 BrandedSocialButton factory (Phase 13.3 +
/// Phase 15 yahoojp) 중 정확히 1 개만 노출 — widget test W4 가 sentinel.
///
/// **2단계 reactive 플로우 (Phase 16 Plan 16-19, CR-02 close):** CTA 는 더 이상
/// 무조건 link 를 시도하지 않는다. 충돌 시점의 caller 는 정의상 미인증이거나
/// 익명이라 link arm 이 구조적으로 성공할 수 없기 때문이다. 분기는 4 경로다
/// (mockup `surface-a-two-step-reactive.md`):
/// - **경로 C** — [existingProvider] 가 email: pop(false) + `/login` (변경 0).
/// - **경로 A** — [pendingCredential] 이 존재하는 native 충돌 (client-side
///   `account-exists-with-different-credential`): 기존
///   [AuthRepository.linkPendingNativeCredential] 흐름 그대로 (A1 회귀 0).
/// - **경로 B** — 그 외 (서버 `already-exists` 로 pendingCredential 부재):
///   [AuthRepository.signInWithExistingProvider] 로 **기존 provider 에 로그인**
///   (step 1). 성공 시 안내 SnackBar 로 step 2 위치를 알린다.
/// - **경로 D** — step 1 취소는 silent no-op, 실패는 SnackBar 후 sheet 유지.
///
/// **step 2 는 Settings "계정 연결"** (proactive arm — `SettingsNotifier.
/// linkProvider` → [AuthRepository.linkCustomTokenProviderArm]) 이 담당한다.
/// 그 메서드는 본 sheet 에서만 호출이 사라졌을 뿐 orphan 이 아니다.
///
/// **Naver:** step 1 **로그인 대상**으로 완전히 지원된다. deployed callable
/// OIDC 미지원은 link *target* 에 한정된 제약이며 Phase 17+ carry-forward —
/// 따라서 과거의 naver 전용 graceful 차단 분기는 제거되었다.
class AccountLinkingSheet extends ConsumerStatefulWidget {
  /// [AccountLinkingSheet] 를 생성한다.
  const AccountLinkingSheet({
    required this.existingProvider,
    required this.collisionEmail,
    this.pendingCredential,
    this.onExistingProviderSignIn,
    super.key,
  });

  /// 기존에 가입된 provider — D-09 양방향 식별 결과 (8 값 enum).
  ///
  /// `lookupSignInMethods` callable 또는 identity_index conflictKind 응답
  /// 으로 채워진다. unknown 인 경우 본 sheet 는 노출되지 않고 unknown
  /// fallback 메시지 (`errorAccountExistsWithUnknownProvider`) 가 직접
  /// inline 노출되어야 한다 (LoginScreen 책임).
  final AccountProvider existingProvider;

  /// 충돌이 발생한 이메일 주소 — UI 본문 메시지의 컨텍스트 (단, 사용자
  /// 본인 데이터이므로 PII redaction 의무는 적용되지 않는다).
  final String collisionEmail;

  /// 충돌 시점에 보존된 native pending credential (Phase 16 16-08).
  ///
  /// `AccountExistsWithDifferentCredential.pendingCredential` 에서 추출해
  /// LoginScreen / SignupScreen 이 전달한다. native 3값
  /// (google/apple/facebook) link 버튼 tap 시
  /// [AuthRepository.linkPendingNativeCredential] 의 입력으로 사용한다.
  /// `null` 인 경우 (email-existing / unknown) link action 은 재로그인
  /// 유도 fallback 으로 동작한다.
  final Object? pendingCredential;

  /// 경로 B step 1 로그인 결과 override 콜백 (Phase 16 Plan 16-19 seam).
  ///
  /// 주입되면 경로 B 가 [AuthRepository.signInWithExistingProvider] 대신 본
  /// 콜백의 bool 결과를 사용한다 (`true` = 성공, `false` = 취소·실패).
  /// **프로덕션 호출처 (LoginScreen / SignupScreen) 는 주입하지 않는다** —
  /// 테스트 / 호출처 커스텀 override 전용 seam 이며, 미주입이 실 repository
  /// 경로 (기본값) 다.
  final ExistingProviderSignInCallback? onExistingProviderSignIn;

  /// [AccountLinkingSheet] 를 modal bottom sheet 로 표시한다.
  ///
  /// 반환값:
  /// - `true` — 경로 A link 성공 또는 경로 B step 1 로그인 성공. 두 경우 모두
  ///   sheet 가 직접 `/home` 으로 이동한다.
  /// - `false` — 사용자 cancel (TextButton 탭 또는 dismiss, D-03) /
  ///   email-existing redirect (경로 C) / 경로 A link 실패.
  /// - `null` — 미정 (dismiss 외 경로 미도달).
  static Future<bool?> show(
    BuildContext context, {
    required AccountProvider existingProvider,
    required String collisionEmail,
    Object? pendingCredential,
    ExistingProviderSignInCallback? onExistingProviderSignIn,
  }) {
    final size = MediaQuery.sizeOf(context);
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      constraints: BoxConstraints(maxHeight: size.height * 0.75),
      builder: (_) => AccountLinkingSheet(
        existingProvider: existingProvider,
        collisionEmail: collisionEmail,
        pendingCredential: pendingCredential,
        onExistingProviderSignIn: onExistingProviderSignIn,
      ),
    );
  }

  @override
  ConsumerState<AccountLinkingSheet> createState() =>
      _AccountLinkingSheetState();
}

class _AccountLinkingSheetState extends ConsumerState<AccountLinkingSheet> {
  /// CTA 진행 중 — section-level modal overlay (UI-SPEC Surface A State:
  /// native linkWithCredential / step 1 기존 provider 로그인 진행) +
  /// 이중 탭 차단.
  bool _isLinking = false;

  /// CTA tap 핸들러 (Phase 16 Plan 16-19 — 2단계 reactive 플로우).
  ///
  /// 분기 순서는 경로 C → 경로 A → 경로 B 다.
  /// - **경로 C (email-existing):** 비밀번호 입력 화면이 필요하므로 pop(false)
  ///   후 `/login` redirect (현행 정책 변경 0).
  /// - **경로 A (native + pendingCredential 존재):** client-side
  ///   `account-exists-with-different-credential` 로 credential 이 보존된
  ///   충돌 — [AuthRepository.linkPendingNativeCredential] 흐름 그대로
  ///   (A1 시나리오 회귀 0). pendingCredential 이 없는 native 충돌은 이 경로에
  ///   들어오지 않는다 — 항상 실패하던 CTA 를 없애기 위한 진입 조건이다.
  /// - **경로 B (그 외 = 서버 already-exists):** [AccountLinkingSheet.
  ///   onExistingProviderSignIn] 이 주입되었으면 그 bool 결과를, 아니면
  ///   [AuthRepository.signInWithExistingProvider] 결과를 사용해 **기존
  ///   provider 로 로그인** (step 1) 한다. 성공 시 pop(true) → 안내 SnackBar
  ///   (step 2 = 설정 > 계정 연결) → `/home`.
  /// - **경로 D:** 취소(null) 는 silent no-op (sheet 유지), 실패는 SnackBar
  ///   후 sheet 유지 — 익명 caller 재충돌(A-16-19-01) 도 이 경로로 흡수되어
  ///   crash 0 · 네비게이션 0 이다.
  Future<void> _onLinkPressed() async {
    if (_isLinking) return; // 이중 탭 가드.
    final navigator = Navigator.of(context);
    final router = GoRouter.of(context);
    // await 이후 build context 사용 회피 — 진행 전 capture (PII 0: 라벨/ARB만).
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final provider = widget.existingProvider;
    final providerLabel = _providerLabel(l10n, provider);

    // 경로 C — email-existing 은 sheet 안에서 완결 불가 (/login redirect).
    if (provider == AccountProvider.email) {
      navigator.pop(false);
      router.go(AppRoutes.login);
      return;
    }

    // 경로 B — 서버 already-exists (pendingCredential 부재) 또는 Custom Token
    // 충돌: link 가 아니라 기존 provider 로 **로그인** (step 1).
    if (!provider.isNative || widget.pendingCredential == null) {
      setState(() => _isLinking = true);
      final outcome = await _signInWithExistingProvider(provider);
      if (!mounted) return;
      switch (outcome) {
        case _ExistingProviderSignInOutcome.success:
          navigator.pop(true);
          // step 2 안내 — 나머지 로그인 수단은 설정 > 계정 연결에서 추가
          // (PII 0: ARB + provider 라벨만).
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                l10n.accountLinkingSignInThenLinkHint(providerLabel),
              ),
            ),
          );
          router.go(AppRoutes.home);
        case _ExistingProviderSignInOutcome.cancelledOrFailed:
          // 취소(silent) / 실패(SnackBar 표시 완료) — sheet 유지 (재시도 가능).
          setState(() => _isLinking = false);
      }
      return;
    }

    // 경로 A — native 3값 (google/apple/facebook) + pendingCredential 보존:
    // 기존 link 흐름 그대로 (변경 0).
    setState(() => _isLinking = true);
    final result = await ref
        .read(authRepositoryProvider)
        .linkPendingNativeCredential(
          existingProvider: provider,
          pendingCredential: widget.pendingCredential,
        );
    if (!mounted) return;

    // 사용자가 재인증을 취소 (null) — no-op, sheet 유지 (재시도 가능).
    if (result == null) {
      setState(() => _isLinking = false);
      return;
    }
    switch (result) {
      case Success<dynamic>():
        navigator.pop(true);
        router.go(AppRoutes.home);
      case Failure<dynamic>(:final exception):
        // WR-01 (1차 리뷰): proactive arm (AccountLinkingSection) 과 동일
        // 피드백 — reauth-expired 는 재로그인 라우팅, 그 외는 user-visible
        // SnackBar (PII 0: ARB only). 기존엔 mute pop(false) 로 무피드백
        // dead-end 였다. non-reauth arm 의 원인별 분기는 WR-02 (4차 리뷰).
        navigator.pop(false);
        if (exception is ReauthenticationRequiredException) {
          // WR-04: 인증 도메인 공용 키. withdrawalReauthRequired 는 소비처
          // 계약이 UI-SPEC Surface C (탈퇴 다이얼로그) 1곳으로 못 박혀 있어,
          // 그 문구가 탈퇴 맥락에 특화되면 본 시트에 엉뚱한 문구가 새어
          // 나간다 (문구 자체는 현재 동일).
          messenger.showSnackBar(
            SnackBar(content: Text(l10n.authReauthRequired)),
          );
          router.go(AppRoutes.login);
        } else {
          // 4차 WR-02 — 경로 A 도 경로 B / Surface D 와 동일한 원인별 분기를
          // 쓴다. 이전에는 errorAccountExistsWithUnknownProvider ("처음 가입한
          // 방식으로 다시 로그인해 주세요") 로 collapse 했는데, 경로 A 는
          // 정의상 그 "처음 가입한 방식" 으로 재인증까지 마친 뒤 실패한
          // 지점이라 지시가 자기 자신을 가리키는 순환이었다. 게다가 이 arm 의
          // 대표 예외인 AccountAlreadyLinked(credential-already-in-use) 의 실제
          // 원인은 "그 자격증명을 **다른 계정**이 쓰고 있다" 이므로 이메일 문구
          // 는 사실과도 다르다 — @settingsLinkFailedAlreadyLinked.description
          // 이 Surface D 에서 이미 제거한 collapse 다.
          final message = switch (exception) {
            ProviderAlreadyLinkedToThisAccount() =>
              l10n.settingsLinkFailedAlreadyLinkedHere,
            AccountAlreadyLinked() => l10n.settingsLinkFailedAlreadyLinked,
            EmailAlreadyInUse() || AccountExistsWithDifferentCredential() =>
              l10n.settingsLinkFailedEmailInUse,
            NetworkException() || TooManyRequests() || ServiceUnavailable() =>
              l10n.settingsLinkFailedTransient,
            _ => l10n.settingsLinkFailedUnknown,
          };
          messenger.showSnackBar(SnackBar(content: Text(message)));
        }
    }
  }

  /// 경로 B step 1 — 기존 provider 로 로그인 (Phase 16 Plan 16-19).
  ///
  /// [AccountLinkingSheet.onExistingProviderSignIn] 이 주입되어 있으면 그
  /// bool 결과를 사용하고, 없으면 [AuthRepository.signInWithExistingProvider]
  /// 를 직접 호출한다 (실 repository 경로 — 프로덕션 기본값).
  ///
  /// 실패 피드백 표시 책임은 본 메서드가 지고, navigation 분기는 호출처
  /// [_onLinkPressed] 가 [_ExistingProviderSignInOutcome] 로 결정한다.
  ///
  /// - 사용자 취소 (`null`) — silent no-op (피드백 0, sheet 유지).
  /// - [Failure] — 재시도 가능(transient) 과 그 외를 분리해 안내한다 (WR-01,
  ///   3차 리뷰 — IN-07 에서 정정. WR-03 은
  ///   `ProviderAlreadyLinkedToThisAccount` 의 ARB 키 교체다). 이전에는 `errorAccountExistsWithUnknownProvider` ("이 이메일은
  ///   다른 방식으로 가입되어 있습니다. 처음 가입한 방식으로 다시 로그인해
  ///   주세요") 로 collapse 했는데, 사용자는 바로 그 순간 시트가 지목한 "처음
  ///   가입한 방식" 으로 로그인을 시도해 실패한 상태다 — 지시가 자기 자신을
  ///   가리키는 순환이며 복구 행동을 알려주지 않는다. 익명 caller
  ///   재충돌(A-16-19-01) 도 이 분기로 흡수되어 crash 0 · linkedProviders
  ///   변경 0 이다.
  ///
  /// **분기 값은 3개다** (`authSignInFailedTransient` /
  /// `authSignInBlockedByGuestSession` / `authSignInFailedUnknown`) —
  /// 세 키 모두 step 1 전용이다. IN-06 (4차 리뷰) 이전에는 앞뒤 두 값이
  /// Surface D 의 `settingsLinkFailed*` ("연결하지 못했습니다") 를 재사용했는데,
  /// 그 순간 사용자가 수행한 동작은 link 가 아니라 *로그인* 이라 소비처 계약
  /// (ARB description) 과 어휘가 어긋났다. —
  /// proactive `AccountLinkingSection` 의 5값 outcome switch (transientFailure /
  /// emailInUse / alreadyLinked / alreadyLinkedHere / failed) 의 **부분집합**
  /// 이며 mirror 가 아니다. step 1 은 link 가 아니라 *로그인* 이므로
  /// already-linked / email-in-use 계열은 이 경로의 실패 원인이 될 수 없다.
  ///
  /// **결정적 실패의 분리 (4차 WR-01):** 이 경로의 *지배적* 실패 원인인
  /// A-16-19-01 (익명 caller 재충돌) 은 [AccountExistsWithDifferentCredential]
  /// 로 도착하며 재시도로 해소되지 않는다. transient 와 catch-all 어느 쪽에
  /// 넣어도 "잠시 후 다시 시도" 문구가 붙어 무한 왕복을 유도하므로 전용 arm
  /// 으로 분리해 실 탈출구(하단 dismiss)를 안내한다.
  ///
  /// **PII invariant (T-16-19-02):** 실패 로그는 `kDebugMode` 가드 하에
  /// runtimeType 만 1줄 출력한다 — collisionEmail / ID Token / provider token
  /// 본문 0 (`linkCustomTokenProviderArm` 로그 형식 mirror).
  Future<_ExistingProviderSignInOutcome> _signInWithExistingProvider(
    AccountProvider provider,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;

    final callback = widget.onExistingProviderSignIn;
    if (callback != null) {
      // 주입된 seam (테스트/호출처 override) 은 bool 계약만 노출한다.
      final ok = await callback(provider);
      return ok
          ? _ExistingProviderSignInOutcome.success
          : _ExistingProviderSignInOutcome.cancelledOrFailed;
    }

    final result = await ref
        .read(authRepositoryProvider)
        .signInWithExistingProvider(provider: provider);
    // 사용자 취소 (no-op, silent).
    if (result == null) return _ExistingProviderSignInOutcome.cancelledOrFailed;
    if (!mounted) return _ExistingProviderSignInOutcome.cancelledOrFailed;
    switch (result) {
      case Success<dynamic>():
        return _ExistingProviderSignInOutcome.success;
      case Failure<dynamic>(:final exception):
        if (kDebugMode) {
          debugPrint(
            'AccountLinkingSheet step1 sign-in failed: '
            'type=${exception.runtimeType}',
          );
        }
        // 실패 — user-visible 안내 (stuck sheet 방지). 순환 안내 대신
        // 원인별 문구를 쓴다 (3차 WR-01 + 4차 WR-01 / IN-06). transient 타입
        // 집합은 Surface D `SettingsNotifier._mapLinkFailure` 의 transient arm
        // 과 동일하지만, 문구는 step 1 전용 키다 (동작이 link 가 아니라
        // 로그인 — IN-06).
        final message = switch (exception) {
          NetworkException() || TooManyRequests() || ServiceUnavailable() =>
            l10n.authSignInFailedTransient,
          // 4차 WR-01 — A-16-19-01 익명 caller 재충돌. 서버 resolveIdentity 의
          // R12(anonymous_existing_collision) 재거부가 이 타입으로 매핑되며,
          // 익명 세션이 유지되는 한 **재시도로 절대 해소되지 않는 결정적
          // 실패**다. catch-all 의 "잠시 후 다시 시도" 문구로 흡수하면 매 탭
          // 마다 실 IdP OAuth 왕복을 반복하는 무한 루프가 된다
          // (auth_repository.dart 의 1차 리뷰 WR-06 과 동일한 오분류).
          // AR-16-07 이 수용한 유일한 탈출구(하단 dismiss)를 안내한다.
          AccountExistsWithDifferentCredential() =>
            l10n.authSignInBlockedByGuestSession,
          _ => l10n.authSignInFailedUnknown,
        };
        messenger.showSnackBar(SnackBar(content: Text(message)));
        return _ExistingProviderSignInOutcome.cancelledOrFailed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    final typography = context.appTypography;
    final colorScheme = context.colorScheme;

    final providerLabel = _providerLabel(l10n, widget.existingProvider);

    return Stack(
      children: <Widget>[
        SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: spacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Gap(spacing.lg),
                  Text(
                    l10n.errorAccountExistsWithProvider(providerLabel),
                    style: typography.bodyLarge.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                  Gap(spacing.xl),
                  _BrandedLinkButton(
                    provider: widget.existingProvider,
                    label: providerLabel,
                    // IN-04: 진행 중에는 null 로 **비활성** 상태를 표현한다.
                    // no-op 클로저는 위젯이 활성으로 보이고 접근성 트리
                    // 에서도 enabled 로 노출되어, 같은 조건에서 null 을
                    // 넘기는 아래 취소 TextButton 과 비대칭이었다
                    // (AuthInProgressOverlay 가 탭을 막더라도 시각/시맨틱
                    // 상태는 일치해야 한다).
                    onPressed: _isLinking ? null : _onLinkPressed,
                  ),
                  Gap(spacing.md),
                  TextButton(
                    onPressed: _isLinking
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: Text(
                      l10n.accountLinkingDismiss,
                      style: typography.labelLarge.copyWith(
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                  Gap(spacing.lg),
                ],
              ),
            ),
          ),
        ),
        // UI-SPEC Surface A State — native linkWithCredential / Custom Token
        // linkCustomTokenProvider 진행 (section-level modal overlay).
        if (_isLinking) const AuthInProgressOverlay(),
      ],
    );
  }
}

/// 경로 B (step 1 기존 provider 로그인) 의 navigation 분기 신호
/// (Phase 16 Plan 16-19).
///
/// `_signInWithExistingProvider` 가 실패 피드백 (SnackBar) 표시 책임을 지고,
/// 본 enum 으로 호출처 [_AccountLinkingSheetState._onLinkPressed] 의 navigation
/// (pop / route) 분기를 결정한다 — proactive `AccountLinkOutcome` mirror.
enum _ExistingProviderSignInOutcome {
  /// step 1 로그인 성공 — sheet pop(true) + 안내 SnackBar + /home.
  success,

  /// 사용자 취소(silent) / 로그인 실패(SnackBar 표시 완료) — sheet 유지.
  cancelledOrFailed,
}

/// [existingProvider] 에 매핑된 provider 라벨 (8 ARB key) 을 반환한다.
String _providerLabel(AppLocalizations l10n, AccountProvider provider) {
  return switch (provider) {
    AccountProvider.google => l10n.authAccountProviderGoogle,
    AccountProvider.apple => l10n.authAccountProviderApple,
    AccountProvider.facebook => l10n.authAccountProviderFacebook,
    AccountProvider.email => l10n.authAccountProviderEmailPassword,
    AccountProvider.kakao => l10n.authAccountProviderKakao,
    AccountProvider.naver => l10n.authAccountProviderNaver,
    AccountProvider.line => l10n.authAccountProviderLine,
    AccountProvider.yahoojp => l10n.authAccountProviderYahooJp,
  };
}

/// 단일 provider 강조 link 버튼 (D-02 single button).
///
/// 8 [AccountProvider] 중 7 은 Phase 13.3 / Phase 15 의 [BrandedSocialButton]
/// factory 로 위임 (변경 0). `email` 만 native social 이 아니므로
/// FilledButton fallback (이메일/비밀번호 진입 trigger) 으로 처리한다.
class _BrandedLinkButton extends StatelessWidget {
  const _BrandedLinkButton({
    required this.provider,
    required this.label,
    required this.onPressed,
  });

  final AccountProvider provider;
  final String label;

  /// `null` = 비활성 (IN-04) — [BrandedSocialButton] / [FilledButton] 모두
  /// `onPressed == null` 을 disabled 시각·시맨틱 상태로 해석한다.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return switch (provider) {
      AccountProvider.google => BrandedSocialButton.google(
        label: label,
        onPressed: onPressed,
      ),
      AccountProvider.apple => BrandedSocialButton.apple(
        label: label,
        onPressed: onPressed,
      ),
      AccountProvider.facebook => BrandedSocialButton.facebook(
        label: label,
        onPressed: onPressed,
      ),
      AccountProvider.email => FilledButton(
        onPressed: onPressed,
        child: Text(label),
      ),
      AccountProvider.kakao => BrandedSocialButton.kakao(
        label: label,
        onPressed: onPressed,
      ),
      AccountProvider.naver => BrandedSocialButton.naver(
        label: label,
        onPressed: onPressed,
      ),
      AccountProvider.line => BrandedSocialButton.line(
        label: label,
        onPressed: onPressed,
      ),
      AccountProvider.yahoojp => BrandedSocialButton.yahoojp(
        label: label,
        onPressed: onPressed,
      ),
    };
  }
}
