import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/theme_extensions.dart';
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
/// 레이아웃 (top → bottom):
/// 1. Drag handle (Material 3 기본, `showDragHandle: true`)
/// 2. [Gap] lg=16
/// 3. 헤더 텍스트 (`authPromptSheetTitle` — headlineMedium, onSurface)
/// 4. [Gap] sm=8
/// 5. 본문 텍스트 (`authPromptSheetBody` — bodyMedium, onSurfaceVariant)
/// 6. [Gap] xl=24
/// 7. [SocialSignInSection] (`showOrDivider: false`) — Google / Apple / Facebook
/// 8. [Gap] lg=16
/// 9. TextButton (`authContinueWithEmail`) — primary color. 탭 시
///    Bottom Sheet 를 닫고 `${AppRoutes.login}?focus=email` 로 이동하여
///    LoginScreen 이메일 필드에 포커스한다 (D-31 / WARNING #12).
/// 10. [Gap] lg=16 (safe-area 하단)
class LoginPromptSheet extends ConsumerWidget {
  /// [LoginPromptSheet] 를 생성한다.
  const LoginPromptSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    final typography = context.appTypography;
    final colorScheme = context.colorScheme;

    return SafeArea(
      child: Padding(
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
