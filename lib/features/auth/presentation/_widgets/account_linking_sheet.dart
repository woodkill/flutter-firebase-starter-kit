// Phase 16 D-01/D-02/D-03 — LoginPromptSheet mirror (RESEARCH Pattern 6
// verbatim). 동일 이메일 충돌 직후 노출되는 modal bottom sheet — 기존
// provider 단일 강조 (D-02 single button) + cancel 시 state 손실 0 (D-03).
//
// Plan 16-04 (Task 4.2) — Plan 16-01 placeholder 본체 채움 완료.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../../../core/auth/provider_id.dart';
import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../../../../l10n/generated/app_localizations.dart';
import 'branded_social_button.dart';

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
class AccountLinkingSheet extends ConsumerStatefulWidget {
  /// [AccountLinkingSheet] 를 생성한다.
  const AccountLinkingSheet({
    required this.existingProvider,
    required this.collisionEmail,
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

  /// [AccountLinkingSheet] 를 modal bottom sheet 로 표시한다.
  ///
  /// 반환값:
  /// - `true` — link 성공 (현재 task scope 외 — Plan 16 의 향후 wiring 책임)
  /// - `false` — 사용자 cancel (TextButton 탭 또는 dismiss, D-03)
  /// - `null` — 미정 (다음 단계 미실행)
  static Future<bool?> show(
    BuildContext context, {
    required AccountProvider existingProvider,
    required String collisionEmail,
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
      ),
    );
  }

  @override
  ConsumerState<AccountLinkingSheet> createState() =>
      _AccountLinkingSheetState();
}

class _AccountLinkingSheetState extends ConsumerState<AccountLinkingSheet> {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    final typography = context.appTypography;
    final colorScheme = context.colorScheme;

    final providerLabel = _providerLabel(l10n, widget.existingProvider);

    return SafeArea(
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
                onPressed: () => Navigator.of(context).pop(true),
              ),
              Gap(spacing.md),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
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
    );
  }
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
  final VoidCallback onPressed;

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
