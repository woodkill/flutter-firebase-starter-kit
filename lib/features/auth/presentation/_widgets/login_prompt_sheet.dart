import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/auth_strategies_registry.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/providers/firebase_providers.dart'
    hide googleSignInProvider;
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../_helpers/social_provider_resolver.dart';
import '../apple_sign_in_notifier.dart';
import '../facebook_sign_in_notifier.dart';
import '../google_sign_in_notifier.dart';
import '../kakao_sign_in_notifier.dart';
import '../line_sign_in_notifier.dart';
import '../naver_sign_in_notifier.dart';
import '../yahoojp_sign_in_notifier.dart';
import 'account_linking_sheet.dart';
import 'auth_in_progress_overlay.dart';
import 'email_auth_cta.dart';
import 'form_error_banner.dart';
import 'social_sign_in_section.dart';

/// 로그인 유도 Bottom Sheet 을 표시한다 (Phase 10 D-10).
///
/// 익명 또는 미인증 사용자가 보호 기능을 탭할 때 [AuthRequired] 가 호출한다.
/// Material 3 기본 drag handle + top rounded corner (28dp) 적용.
/// 최대 높이는 화면의 75%.
Future<void> showLoginPromptSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.75,
    ),
    builder: (_) => const LoginPromptSheet(),
  );
}

/// 로그인 유도 Bottom Sheet 본체 (Phase 10 D-10).
///
/// 소셜 로그인 **성공** 시 sheet 를 닫고 [context.go] 로 Home 이동을
/// 명시적으로 호출한다 (Issue #3 safety net). authRedirect 가 정상
/// 동작하면 중복 호출이며, GoRouter redirect 타이밍 경합 시 fallback
/// 으로 동작한다.
///
/// 소셜 로그인 **실패** 시에는 sheet 를 닫지 않고 소셜 버튼 바로 아래
/// [FormErrorBanner] 로 inline 표시한다. 이메일 충돌
/// ([AccountExistsWithDifferentCredential]) 이 기존 provider 를 식별한
/// 경우에는 [AccountLinkingSheet] 를 본 sheet **위에** 쌓아 안내하고,
/// 식별하지 못한 경우 (unknown) 는 배너 inline fallback 으로 남는다 --
/// Surface A (`login_screen.dart`) 와 동일한 정책이다
/// (quick 260910-uff -- AR-16.1-01 회수).
///
/// 레이아웃 (top -> bottom):
/// 1. Drag handle (Material 3 기본, `showDragHandle: true`)
/// 2. [Gap] lg=16
/// 3. 헤더 텍스트 (`authPromptSheetTitle` -- headlineMedium, onSurface)
/// 4. [Gap] sm=8
/// 5. 본문 텍스트 (`authPromptSheetBody` -- bodyMedium, onSurfaceVariant)
/// 6. [Gap] xl=24
/// 7. [SocialSignInSection] -- 활성 provider (기본 7개), "또는" 구분선 없음.
///    소셜 로그인 실패 시 provider 버튼 바로 아래에 에러 배너가 함께
///    렌더된다 (quick 260910-uff).
/// 8. [Gap] md=12
/// 9. [EmailAuthCta] (`authContinueWithEmail`) -- 탭 시 Bottom Sheet 를 닫고
///    `/login/email` (이메일 로그인 전용 화면) 로 push 한다 (Phase 16.1).
/// 10. [Gap] lg=16 (safe-area 하단)
///
/// 본문(2~10)은 스크롤 뷰 1겹으로 감싼다 -- provider 수가 늘어도 최대 높이
/// 75% 안에서 스크롤로 흡수되어 RenderFlex overflow 가 발생하지 않는다
/// (Phase 16.1 / Sketch 004 winner B). Drag handle 은 Bottom Sheet 이
/// builder 밖에 렌더하므로 스크롤과 무관하게 고정된다.
class LoginPromptSheet extends ConsumerStatefulWidget {
  /// [LoginPromptSheet] 를 생성한다.
  const LoginPromptSheet({super.key});

  @override
  ConsumerState<LoginPromptSheet> createState() => _LoginPromptSheetState();
}

class _LoginPromptSheetState extends ConsumerState<LoginPromptSheet> {
  /// 소셜 로그인 에러를 소셜 버튼 영역에 표시하기 위한 상태.
  AppException? _socialError;

  /// account-exists 충돌 시 계정 연결 시트를 본 sheet **위에** 노출한다
  /// (quick 260910-uff -- Surface A 의 동명 메서드 1:1 mirror).
  ///
  /// `ref.listen` 콜백 (build 동안) 안에서 직접 `showModalBottomSheet` 를
  /// 호출하면 build 중 navigator 변경 위반이 되므로 post-frame callback
  /// 으로 1 frame 미룬다. 본 sheet 의 `context` 를 넘기므로 연결 시트는
  /// 위에 쌓이고, 사용자가 취소하면 본 sheet 로 되돌아온다.
  ///
  /// 연결 시트가 link / 기존 provider 로그인 성공(`true`) 으로 스스로
  /// 닫히면 본 sheet 도 함께 닫는다 -- 시트가 `/home` 으로 이동한 뒤에도
  /// modal 이 홈 위에 떠 있는 상태를 남기지 않기 위함이다. 취소·실패
  /// (`false` / `null`) 에는 아무 동작도 하지 않아 사용자가 본 sheet 에서
  /// 다른 수단을 재시도할 수 있다.
  void _showAccountLinkingSheet(AccountExistsWithDifferentCredential err) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final navigator = Navigator.of(context);
      final linkResult = AccountLinkingSheet.show(
        context,
        existingProvider: err.existingProvider!,
        collisionEmail: err.email ?? '',
        pendingCredential: err.pendingCredential,
      );
      // ignore: discarded_futures
      linkResult.then((linked) {
        if (linked != true) return;
        if (!mounted) return;
        if (navigator.canPop()) navigator.pop();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    final typography = context.appTypography;
    final colorScheme = context.colorScheme;

    // Issue #3 safety net: 소셜 로그인 성공 시 Sheet pop + Home 이동.
    // activeStrategiesProvider 결과를 순회하여 단일 ref.listen 패턴으로 통합
    // (Phase 11-04 Pattern I, corrections 3번 / Pitfall 6 — 4곳 중 1곳).
    final locale = Localizations.localeOf(context);
    final strategies = ref.watch(activeStrategiesProvider(locale));
    for (final strategy in strategies) {
      ref.listen<AsyncValue<void>>(resolveSocialProvider(strategy.providerId), (
        previous,
        next,
      ) {
        if (previous is AsyncLoading && next is AsyncData) {
          if (!mounted) return;
          final user = ref.read(firebaseAuthProvider).currentUser;
          if (user != null && !user.isAnonymous) {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
            context.go(AppRoutes.home);
          }
          return;
        }
        if (next is AsyncError) {
          // dispose 후 ref.listen 콜백 race 방어 (Surface A WR-04 계승).
          if (!mounted) return;
          final err = next.error;
          // 기존 provider 를 식별한 충돌만 계정 연결 시트로 안내하고,
          // 식별 실패 (unknown) 는 배너 inline fallback 으로 남긴다
          // (Surface A 의 R2 회귀 0 계약 동형). 실패 경로는 본 sheet 를
          // pop 하지 않는다 -- 사용자는 현재 화면을 잃지 않는다.
          if (err is AccountExistsWithDifferentCredential &&
              err.existingProvider != null) {
            _showAccountLinkingSheet(err);
            return;
          }
          if (err is AppException) {
            setState(() {
              _socialError = err;
            });
          }
        }
      });
    }

    // 소셜 OAuth 진행 (Phase 11-04 hotfix UX gap): sheet 안에서만 overlay
    // 표시 — sheet 가 OAuth 성공 직후 pop 되므로 표시 시간은 짧지만
    // signInWithCredential / Firestore mirror 구간을 시각적으로 메운다.
    // Phase 12 — kakaoSignInProvider 합산 (D-25),
    // Phase 13 — naverSignInProvider 합산 (Plan 13-06),
    // Phase 14 — lineSignInProvider 합산 (Plan 14-05 / SOCL-03),
    // Phase 15 — yahoojpSignInProvider 합산 (Plan 15-03 / SOCL-04).
    final isSocialLoading =
        ref.watch(googleSignInProvider).isLoading ||
        ref.watch(appleSignInProvider).isLoading ||
        ref.watch(facebookSignInProvider).isLoading ||
        ref.watch(kakaoSignInProvider).isLoading ||
        ref.watch(naverSignInProvider).isLoading ||
        ref.watch(lineSignInProvider).isLoading ||
        ref.watch(yahoojpSignInProvider).isLoading;

    return SafeArea(
      child: Stack(
        children: <Widget>[
          SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: spacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Gap(spacing.lg),
                Text(
                  l10n.authPromptSheetTitle,
                  style: typography.headlineMedium.copyWith(
                    color: colorScheme.onSurface,
                  ),
                ),
                Gap(spacing.sm),
                Text(
                  l10n.authPromptSheetBody,
                  style: typography.bodyMedium.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                Gap(spacing.xl),
                SocialSignInSection(
                  isFormLoading: false,
                  showOrDivider: false,
                  errorBanner: FormErrorBanner(exception: _socialError),
                ),
                Gap(spacing.md),
                // WR-08 — 소셜 OAuth 진행 중에는 null 을 넘겨 disabled 시각·
                // 시맨틱을 AuthInProgressOverlay 의 탭 차단과 일치시킨다.
                EmailAuthCta(
                  onPressed: isSocialLoading
                      ? null
                      : () => _handleContinueWithEmail(context),
                ),
                Gap(spacing.lg),
              ],
            ),
          ),
          if (isSocialLoading) const AuthInProgressOverlay(),
        ],
      ),
    );
  }

  /// "이메일로 계속" 탭 핸들러.
  ///
  /// Bottom Sheet 를 닫고 `/login/email` (이메일 로그인 전용 화면) 로
  /// push 한다. Phase 16.1 — 쿼리 파라미터 기반 포커스 진입 계약은 전용
  /// route 로 대체됐다. 앱이 쿼리 문자열을 생성하는 지점이 사라지므로
  /// 임의 쿼리 주입으로 UI 동작을 바꿀 표면 자체가 없다 (T-16.1-02).
  void _handleContinueWithEmail(BuildContext context) {
    Navigator.of(context).pop();
    context.push(AppRoutes.emailLogin);
  }
}
