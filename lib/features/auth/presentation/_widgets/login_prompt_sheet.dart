import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/auth_strategies_registry.dart';
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
import '../naver_sign_in_notifier.dart';
import 'auth_in_progress_overlay.dart';
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
/// 소셜 로그인 성공 시 sheet 를 닫고 [context.go] 로 Home 이동을
/// 명시적으로 호출한다 (Issue #3 safety net). authRedirect 가 정상
/// 동작하면 중복 호출이며, GoRouter redirect 타이밍 경합 시 fallback
/// 으로 동작한다.
///
/// 레이아웃 (top -> bottom):
/// 1. Drag handle (Material 3 기본, `showDragHandle: true`)
/// 2. [Gap] lg=16
/// 3. 헤더 텍스트 (`authPromptSheetTitle` -- headlineMedium, onSurface)
/// 4. [Gap] sm=8
/// 5. 본문 텍스트 (`authPromptSheetBody` -- bodyMedium, onSurfaceVariant)
/// 6. [Gap] xl=24
/// 7. [SocialSignInSection] (`showOrDivider: false`) -- Google / Apple / Facebook
/// 8. [Gap] lg=16
/// 9. TextButton (`authContinueWithEmail`) -- primary color. 탭 시
///    Bottom Sheet 를 닫고 `${AppRoutes.login}?focus=email` 로 이동하여
///    LoginScreen 이메일 필드에 포커스한다 (D-31 / WARNING #12).
/// 10. [Gap] lg=16 (safe-area 하단)
class LoginPromptSheet extends ConsumerStatefulWidget {
  /// [LoginPromptSheet] 를 생성한다.
  const LoginPromptSheet({super.key});

  @override
  ConsumerState<LoginPromptSheet> createState() => _LoginPromptSheetState();
}

class _LoginPromptSheetState extends ConsumerState<LoginPromptSheet> {
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
      ref.listen<AsyncValue<void>>(
        resolveSocialProvider(strategy.providerId),
        (previous, next) {
          if (previous is AsyncLoading && next is AsyncData) {
            if (!mounted) return;
            final user = ref.read(firebaseAuthProvider).currentUser;
            if (user != null && !user.isAnonymous) {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
              context.go(AppRoutes.home);
            }
          }
        },
      );
    }

    // 소셜 OAuth 진행 (Phase 11-04 hotfix UX gap): sheet 안에서만 overlay
    // 표시 — sheet 가 OAuth 성공 직후 pop 되므로 표시 시간은 짧지만
    // signInWithCredential / Firestore mirror 구간을 시각적으로 메운다.
    // Phase 12 — kakaoSignInProvider 합산 (D-25),
    // Phase 13 — naverSignInProvider 합산 (Plan 13-06).
    final isSocialLoading =
        ref.watch(googleSignInProvider).isLoading ||
        ref.watch(appleSignInProvider).isLoading ||
        ref.watch(facebookSignInProvider).isLoading ||
        ref.watch(kakaoSignInProvider).isLoading ||
        ref.watch(naverSignInProvider).isLoading;

    return SafeArea(
      child: Stack(
        children: <Widget>[
          Padding(
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
                const SocialSignInSection(
                  isFormLoading: false,
                  showOrDivider: false,
                ),
                Gap(spacing.lg),
                TextButton(
                  onPressed: () => _handleContinueWithEmail(context),
                  child: Text(
                    l10n.authContinueWithEmail,
                    style: typography.labelLarge.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
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
  /// Bottom Sheet 를 닫고 `/login?focus=email` 로 이동한다. LoginScreen 은
  /// `focus=email` 쿼리 파라미터를 감지하여 이메일 [FocusNode] 에
  /// `requestFocus` 를 호출한다 (Phase 10 D-31, WARNING #12).
  ///
  /// T-10-27 방어: LoginScreen 은 `focus == 'email'` 단일 값만 검사하므로
  /// 임의 쿼리 주입으로 UI 동작을 변경할 수 없다.
  void _handleContinueWithEmail(BuildContext context) {
    Navigator.of(context).pop();
    context.push('${AppRoutes.login}?focus=email');
  }
}
