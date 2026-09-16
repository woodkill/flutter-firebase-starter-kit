// Phase 16 16-11 / Surface D — Proactive Account Linking (Settings) section.
//
// LOCKED mockup (mockups/surface-d-account-linking.md, 사용자 시각 sign-off
// 2026-06-02 — email EXCLUDE) verbatim 구현:
// - heading (settingsAccountLinkingSection "계정 연결") + available-provider
//   "연결" 버튼 vertical list.
// - available = (소셜 AccountProvider 6값) ∩ 활성 Strategy − 이미 link 된 소셜
//   provider. email (mockup §0) 과 naver (WR-15 — 항상 미지원) 는 후보 제외.
// - 버튼 tap → 16-10/16-09 proactive link 메서드 dispatch (settings_notifier).
//   성공 → accountLinkingSucceededSnackbar + linkedProviders 자동 refresh +
//   버튼 사라짐. reauth → 재로그인 라우팅 (withdrawal D-06 mirror). already-
//   linked/실패 → graceful SnackBar. 취소 → no-op.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/auth_strategies_registry.dart';
import '../../../../core/auth/provider_id.dart';
import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../auth/presentation/_widgets/auth_in_progress_overlay.dart';
import '../../../auth/presentation/_widgets/branded_social_button.dart';
import '../../application/account_link_in_progress.dart';
import '../settings_notifier.dart';

/// Surface D 의 소셜 proactive 후보 (email / naver EXCLUDE).
///
/// `available = _kProactiveLinkCandidates ∩ 활성 Strategy − 이미 link 된 소셜
/// provider`. 표시 순서는 mockup §2 의 cross-provider 비교 배열을 따른다.
///
/// **제외 대상 2종:**
/// - `email` — 사용자 시각 sign-off 2026-06-02 (mockup §0 EXCLUDE).
/// - `naver` — deployed callable 이 OIDC 를 지원하지 않아
///   [SettingsNotifier.linkProvider] 가 100% [AccountLinkOutcome.unsupported]
///   로 끝난다 (10-REVIEW WR-15). 성공 확률 0 인 affordance 는 사용자에게
///   고장난 버튼이므로 후보 집합에서 뺀다. `linkProvider` 의 naver arm 은
///   방어적 분기로 유지되어 다른 경로에서 도달해도 graceful 하다. naver
///   proactive link 자체는 Phase 17+ carry-forward.
const List<AccountProvider> _kProactiveLinkCandidates = <AccountProvider>[
  AccountProvider.google,
  AccountProvider.apple,
  AccountProvider.facebook,
  AccountProvider.kakao,
  AccountProvider.line,
  AccountProvider.yahoojp,
];

/// 계정 연결 섹션 위젯 (Phase 16 16-11 / Surface D / SOCL-12).
///
/// 로그인된 사용자가 아직 link 안 된 소셜 provider 의 "연결" 버튼을 탭하면
/// 16-10(native) / 16-09(Custom Token) 의 proactive link 메서드가 호출되어
/// 계정 연결이 수행된다. email(이메일/비밀번호) 은 mockup §0 사용자 시각
/// sign-off 에 따라, naver 는 항상 미지원으로 끝나므로 (WR-15) 본 목록에서
/// **제외**된다.
///
/// **available-provider 규칙:** `available = (소셜 6값) ∩ 활성 Strategy −
/// 이미 link 된 소셜 provider`. 본인 [currentUserProvider] linkedProviders
/// 기반 — 타 계정 정보 0 (threat T-16-11-01 mitigate).
///
/// available 집합이 비면 (모든 활성 소셜 provider link 완료) 섹션 전체를
/// 미노출한다 (mockup §2 — 빈 set graceful).
class AccountLinkingSection extends ConsumerWidget {
  /// [AccountLinkingSection] 을 생성한다.
  const AccountLinkingSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    // WR-07: appTypography 가 AppTypography override 를 반영하는 유일한 경로.
    final typography = context.appTypography;

    // (1) 이미 link 된 소셜 provider set (본인 linkedProviders 기반).
    final user = ref.watch(currentUserProvider);
    final linked = _linkedSocialProviders(user?.providerIds);

    // (2) 활성 Strategy set (정적 + RC overlay — login/signup mirror).
    final activeSlugs = ref
        .watch(activeStrategiesProvider)
        .map((s) => s.providerId)
        .toSet();

    // (3) available = 소셜 6값 ∩ 활성 − linked (email / naver 후보 미포함).
    final available = <AccountProvider>[
      for (final provider in _kProactiveLinkCandidates)
        if (activeSlugs.contains(provider.slug) && !linked.contains(provider))
          provider,
    ];

    // 진행 중 overlay (UI-SPEC Surface D State variant — link in-progress).
    // WR-02: 탈퇴용 settingsProvider 가 아니라 link 전용 플래그를 본다 —
    // 종전에는 탈퇴 진행 중에도 본 섹션 전체가 잠기고 오버레이가 떴다.
    final isLinking = ref.watch(accountLinkInProgressProvider);

    // available 빈 set → 섹션 미노출 (mockup §2 graceful).
    if (available.isEmpty) return const SizedBox.shrink();

    return Stack(
      children: <Widget>[
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // heading — danger_zone_section.dart 패턴 mirror.
            Padding(
              padding: EdgeInsets.fromLTRB(
                spacing.lg,
                spacing.sm,
                spacing.lg,
                spacing.xs,
              ),
              child: Text(
                l10n.settingsAccountLinkingSection,
                // settings_screen.dart heading 과 동일 role·색 (accent 토큰
                // 미사용 — UI-SPEC Layout Contract Surface D).
                style: typography.labelMedium.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            // available-provider 버튼 vertical list (mockup §2 gap = sm).
            for (final provider in available) ...<Widget>[
              Padding(
                padding: EdgeInsets.symmetric(horizontal: spacing.lg),
                child: _LinkProviderButton(
                  provider: provider,
                  label: l10n.settingsLinkProviderCta(
                    _providerLabel(l10n, provider),
                  ),
                  onPressed: isLinking
                      ? null
                      : () => _onLinkPressed(context, ref, provider),
                ),
              ),
              Gap(spacing.sm),
            ],
          ],
        ),
        if (isLinking) const AuthInProgressOverlay(),
      ],
    );
  }

  /// [provider] proactive link 트리거 + 결과별 UI 분기 (Phase 16 16-11).
  ///
  /// settings_notifier 의 [SettingsNotifier.linkProvider] 에 비즈니스 로직을
  /// 위임하고 (flutter.md — UI 로직 위임), 반환된 [AccountLinkOutcome] 에 따라
  /// 성공 snackbar / reauth 라우팅 / graceful 안내 / no-op 을 처리한다.
  Future<void> _onLinkPressed(
    BuildContext context,
    WidgetRef ref,
    AccountProvider provider,
  ) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final providerLabel = _providerLabel(l10n, provider);

    final outcome = await ref
        .read(settingsProvider.notifier)
        .linkProvider(provider);
    if (!context.mounted) return;

    switch (outcome) {
      case AccountLinkOutcome.success:
        // 성공 snackbar — provider 라벨만 (PII 0, threat T-16-11-04).
        // currentUserProvider 가 linkedProviders stream 으로 자동 refresh →
        // 버튼이 available 집합에서 제거.
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.accountLinkingSucceededSnackbar(providerLabel)),
          ),
        );
      case AccountLinkOutcome.reauthRequired:
        // 재인증 필요 — 재로그인 라우팅 (withdrawal D-06 reauth gate mirror).
        // WR-05 (4차 리뷰): 도메인 중립 공용 키를 쓴다. withdrawalReauthRequired
        // 는 소비처 계약이 UI-SPEC Surface C (탈퇴 다이얼로그) 1곳으로 못 박혀
        // 있어, 그 문구를 탈퇴 어휘로 다듬으면 계정 연결 화면에 "탈퇴하려면…"
        // 이 새어 나간다 (문구 자체는 현재 verbatim 동일).
        // 재인증 표시를 붙여야 guard 분기 (6) 이 push 한 로그인 화면을 홈으로
        // 튕기지 않는다 (R_EXTRA_G3_REAUTH_LOGIN_BOUNCE).
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.authReauthRequired)),
        );
        unawaited(router.push(AppRoutes.buildReauthLocation(AppRoutes.login)));
      case AccountLinkOutcome.alreadyLinked:
        // `credential-already-in-use` / Custom Token callable
        // `already-exists` — 해당 신원이 **다른 계정** 소유 (A6 실측).
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.settingsLinkFailedAlreadyLinked)),
        );
      case AccountLinkOutcome.alreadyLinkedHere:
        // WR-04: `provider-already-linked` — 이미 **현재 계정에** 연결됨.
        // alreadyLinked 문구 ("다른 계정에 연결됨 → 먼저 해제") 는 이 경우
        // 사실과 반대이고 수행도 불가능하다.
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.settingsLinkFailedAlreadyLinkedHere)),
        );
      case AccountLinkOutcome.emailInUse:
        // `email-already-in-use` / `account-exists-with-different-credential`
        // — 이메일 충돌. 문구에 email 값 자체는 넣지 않는다 (T-16-15-02).
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.settingsLinkFailedEmailInUse)),
        );
      case AccountLinkOutcome.transientFailure:
        // `network-request-failed` / `too-many-requests` / ServiceUnavailable
        // — 재시도로 해소 가능한 일시 오류.
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.settingsLinkFailedTransient)),
        );
      case AccountLinkOutcome.failed:
        // 미분류 실패 catch-all — 정확한 코드는 repository 의 kDebugMode
        // `code=` 로그로 logcat 에 남는다 (T-16-15-01).
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.settingsLinkFailedUnknown)),
        );
      case AccountLinkOutcome.unsupported:
        // naver (deployed callable OIDC 부재) / email (Surface D EXCLUDE) —
        // 실패가 아니라 미지원. providerLabel 은 기존 authAccountProvider{X}
        // brand verbatim 라벨 (brand 라벨 신규 0, T-16-15-03).
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.settingsLinkUnsupportedProvider(providerLabel)),
          ),
        );
      case AccountLinkOutcome.cancelled:
        // 사용자 취소 — no-op (snackbar 0, 버튼 유지).
        break;
    }
  }
}

/// `User.providerIds` (URI 형식 native + slug 형식 Custom Token 합집합) 를
/// 이미 link 된 소셜 [AccountProvider] set 으로 변환한다 (Phase 16 16-11).
///
/// **두 형식 공존 (Phase 12 D-16):** native 3 provider 는 Firebase Auth URI
/// 형식 (`google.com` / `apple.com` / `facebook.com`), Custom Token provider
/// 는 도메인 slug (`kakao` / `naver` / `line` / `yahoojp`). [AccountProvider.tryParse]
/// 는 slug + `password` 만 인식하므로 URI 형식은 본 함수가 별도 매핑한다.
/// `password`(email) 는 소셜이 아니므로 제외한다 (mockup §0 email EXCLUDE).
Set<AccountProvider> _linkedSocialProviders(List<String>? providerIds) {
  if (providerIds == null) return const <AccountProvider>{};
  final result = <AccountProvider>{};
  for (final id in providerIds) {
    final provider = switch (id) {
      'google.com' => AccountProvider.google,
      'apple.com' => AccountProvider.apple,
      'facebook.com' => AccountProvider.facebook,
      _ => AccountProvider.tryParse(id),
    };
    // email(=password slug) 은 소셜 아님 → 제외 (mockup §0).
    if (provider != null && provider != AccountProvider.email) {
      result.add(provider);
    }
  }
  return result;
}

/// [provider] 의 brand verbatim ARB 라벨 (authAccountProvider{X}) 을 반환한다.
///
/// `settingsLinkProviderCta({provider})` placeholder 에 주입할 provider 라벨.
/// account_linking_sheet.dart 의 `_providerLabel` 패턴 mirror (소셜 7값만 —
/// email 은 후보 미포함이나 exhaustive switch 보강).
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

/// 단일 소셜 provider 의 "연결" 버튼 (Phase 16 16-11 / Surface D §2).
///
/// 7 [AccountProvider] 소셜 값을 Phase 13.3 / Phase 15 의 [BrandedSocialButton]
/// factory 로 dispatch 한다 (brand verbatim, M3 토큰 의존 0 — starter kit brand
/// drift 회피). account_linking_sheet.dart 의 `_BrandedLinkButton` 패턴 mirror
/// (단, email 분기 제외 — Surface D email EXCLUDE).
class _LinkProviderButton extends StatelessWidget {
  const _LinkProviderButton({
    required this.provider,
    required this.label,
    required this.onPressed,
  });

  final AccountProvider provider;
  final String label;
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
      // email 은 Surface D 후보 미포함 (mockup §0 EXCLUDE) — 도달 시 비표시
      // 방어 (exhaustive switch 보강, FilledButton fallback 미사용).
      AccountProvider.email => const SizedBox.shrink(),
    };
  }
}
