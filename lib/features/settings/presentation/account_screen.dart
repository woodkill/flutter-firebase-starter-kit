// Phase 17.1 D-02 · D-05 — 계정 정보 화면. 설정 「내 계정」 블록(사진 · 이메일 ·
// 가입 수단 · 연결된 계정 · 계정 연결 · Danger zone)과 옛 홈 계정 카드의 표시
// 이름 · 가입일 · 로그아웃을 한 화면으로 모은다 (UI-SPEC §(A) · Q3-A · Q5-A).
//
// - 묶음 제목: 「프로필」(사진 · 표시 이름 · 이메일 · 가입일) · 「로그인 수단」
//   (가입 수단 · 연결된 계정 · 계정 연결).
// - 연결된 계정 값의 밑줄 provider 이름 tap → UnlinkConfirmationDialog.show →
//   결과별 SnackBar (Phase 16.8 D-07 · D-10 · UI-SPEC §N · Phase 16.10 §N′ —
//   설정 화면 매핑 verbatim 이동).
// - 로그아웃 = 목록 한 줄(기본 색) → 확인 다이얼로그 →
//   AuthRepository.signOutAndResetOnboarding (10.2 D-A4 — 단일 진리원).
// - 계정 연결 섹션은 보일 때만 앞 간격 xxl 을 가진다 (UI-SPEC §Spacing).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/intl_extensions.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../shared/auth/provider_label_formatter.dart';
import '../../auth/data/auth_repository.dart';
import '../application/unlink_eligibility.dart';
import '_widgets/account_linking_section.dart';
import '_widgets/danger_zone_section.dart';
import '_widgets/linked_accounts_value.dart';
import '_widgets/profile_photo_tile.dart';
import '_widgets/settings_heading.dart';
import '_widgets/unlink_confirmation_dialog.dart';
import 'settings_notifier.dart';

/// 계정 정보 화면 — 정식 사용자 전용 (Phase 17.1 D-02 · D-05).
///
/// 진입 = 설정 맨 위 계정 행(D-03) · 게스트 직접 진입은 guard 가 설정으로
/// 돌린다(D-07). 행 순서는 「프로필」 heading · 프로필 사진 행 · 표시 이름 ·
/// 이메일 · 가입일 · 「로그인 수단」 heading · 가입 수단 · 연결된 계정 ·
/// (연결 가능 provider 가 있을 때만) 계정 연결 · 로그아웃 · Danger zone 이다.
///
/// 값이 없는 행은 숨기지 않고 「-」 를 보여 행 위치를 고정한다(UI-SPEC E5
/// partial). 표시 행의 값은 동기 `currentUserProvider` 라 loading 이 없다.
class AccountScreen extends ConsumerWidget {
  /// [AccountScreen] 을 생성한다.
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    // WR-07: textTheme 은 AppTypography extension override 를 반영하지 않는다
    // — 스타터킷 사용자가 타이포를 교체하면 계정 화면만 drift 한다.
    final typography = context.appTypography;
    final user = ref.watch(currentUserProvider);
    final locale = ref.watch(localeProvider);

    // quick 260928-fp6 D-01 · D-02: user null · email null 모두 「-」 — 도메인
    // email 이 nullable 이라 빈 문자열 sentinel 은 없다.
    final email = user?.email ?? '-';
    // Phase 16.7 — 가입 수단 · 연결된 계정 분리(D-11 기록 없음 = 「-」 · 연결 =
    // 보유 전부, D-12 미보유 기록값 그대로).
    final split = splitAccountProviders(user);
    final signUpValue = formatSignUpMethod(split.signUpProviderId, l10n);
    // 제목 = 라벨 style · 값 = titleMedium. 각 Text 에 명시한다 (UI-SPEC
    // §Typography (R1)).
    final titleStyle = typography.bodySmall.copyWith(
      color: context.colorScheme.onSurfaceVariant,
    );
    final valueStyle = typography.titleMedium;
    // WidgetSpan 안 라벨 Text 도 valueStyle — 바깥 문단과 같은 style 이어야
    // mockup 과 byte 동일(UI-SPEC §Typography (R1)).
    // Phase 16.8 — 해제 가능 변형. id · label 을 쌍으로 넘겨 버튼 여부
    // (canUnlinkProvider)와 다이얼로그 라벨을 정한다 (라벨 switch 신설 0).
    final linkedLabels = formatProviderLabels(split.linkedProviderIds, l10n);
    final linkedSpan = buildUnlinkableLinkedAccountsValue(
      entries: [
        for (final (i, id) in split.linkedProviderIds.indexed)
          (id: id, label: linkedLabels[i]),
      ],
      none: l10n.authAccountLinkedAccountsNone,
      valueStyle: valueStyle,
      canUnlink: (id) => canUnlinkProvider(user, id),
      onUnlinkTap: (id, label) =>
          _onUnlinkPressed(context, providerId: id, providerLabel: label),
      l10n: l10n,
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsAccountSection)),
      // SafeArea — 최하단 회원탈퇴 ListTile 이 시스템 내비게이션 바에 가려져
      // 탭 불가가 되는 것을 방지한다 (설정 화면과 같은 이유 · G-16-A6-1).
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.symmetric(vertical: spacing.md),
          children: [
            SettingsHeading(label: l10n.accountProfileSection),
            // Phase 17 D-18 · UI-SPEC (P) Q2-A — 프로필 사진 행(17.1 D-02 —
            // 정식 사용자 계정 화면의 첫 행).
            const ProfilePhotoTile(),
            ListTile(
              leading: const Icon(Icons.badge),
              title: Text(l10n.authAccountDisplayName, style: titleStyle),
              subtitle: Text(
                user?.displayName ?? '-',
                softWrap: true,
                style: valueStyle,
              ),
            ),
            // WR-14: 280dp 최소 뷰포트 방어 — 이메일 주소만 maxLines 2 +
            // softWrap + ellipsis(주소는 provider 이름 규칙 대상이 아님).
            ListTile(
              leading: const Icon(Icons.alternate_email),
              title: Text(l10n.authAccountEmail, style: titleStyle),
              subtitle: Text(
                l10n.settingsAccountEmail(email),
                maxLines: 2,
                softWrap: true,
                overflow: TextOverflow.ellipsis,
                style: valueStyle,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: Text(l10n.authAccountCreatedAt, style: titleStyle),
              subtitle: Text(
                user == null
                    ? '-'
                    : user.createdAt.formatYMD(locale.languageCode),
                softWrap: true,
                style: valueStyle,
              ),
            ),
            Gap(spacing.xxl),
            SettingsHeading(label: l10n.accountSignInMethodsSection),
            // 가입 수단 · 연결된 계정 값은 줄 수 제한 없이 전부 표시(16.7 D-02
            // 개정 (R1)) — 줄바꿈은 provider 사이에서만(D-04) · 가입 수단 값
            // 1줄은 golden harness 가드가 고정.
            ListTile(
              leading: const Icon(Icons.how_to_reg),
              title: Text(l10n.authAccountSignUpMethod, style: titleStyle),
              subtitle: Text(signUpValue, softWrap: true, style: valueStyle),
            ),
            // 연결된 계정 — maxLines · overflow 없음. semanticsLabel 을 주지
            // 않는다: 주면 안쪽 해제 버튼 노드가 지워진다. 대신 이름마다
            // container 노드(버튼 = 「{provider} 연결 해제」 · 해제 불가 = 이름만)
            // 를 두고 사이 공백은 빈 semantics 라 WidgetSpan 자리표시 문자가
            // 낭독되지 않는다 (UI-SPEC §Semantics (16.8)).
            ListTile(
              leading: const Icon(Icons.link),
              title: Text(l10n.authAccountLinkedAccounts, style: titleStyle),
              subtitle: Text.rich(
                linkedSpan,
                softWrap: true,
                style: valueStyle,
              ),
            ),
            // 계정 연결 section (Surface D — 16-11). 연결 가능 provider 가
            // 없으면 SizedBox.shrink 이고 앞 간격도 0 (UI-SPEC §Spacing).
            const AccountLinkingSection(leadingGap: true),
            Gap(spacing.xxl),
            // Phase 17.1 D-05 · Q5-A — 로그아웃 = 목록 한 줄(기본 색).
            ListTile(
              leading: const Icon(Icons.logout),
              title: Text(l10n.authAccountSignOut, style: valueStyle),
              onTap: () => _confirmSignOut(context, ref),
            ),
            Gap(spacing.xxl),
            // Danger zone — UI-SPEC line 261~275 (항상 최하단 격리).
            const DangerZoneSection(),
          ],
        ),
      ),
    );
  }

  /// 밑줄 provider 이름 tap — 확인 다이얼로그를 열고 결과별 SnackBar ·
  /// 재로그인 라우팅을 처리한다 (Phase 16.8 D-07 · UI-SPEC §N).
  ///
  /// 해제 실행은 다이얼로그 → [SettingsNotifier.disconnectAndUnlinkProvider]
  /// 에 위임한다 (UI 로직 위임 · Phase 16.10 D-09 — provider 측 끊기 성공
  /// 뒤에만 킷 해제). 다이얼로그 취소 · barrier · back 은 `null` →
  /// [AccountUnlinkOutcome.cancelled] (SnackBar 0). 재로그인은 계정 화면에서
  /// 출발해 계정 화면으로 돌아온다(Phase 17.1 RESEARCH §R-02).
  Future<void> _onUnlinkPressed(
    BuildContext context, {
    required String providerId,
    required String providerLabel,
  }) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);

    final outcome =
        await UnlinkConfirmationDialog.show(
          context,
          providerId: providerId,
          providerLabel: providerLabel,
        ) ??
        AccountUnlinkOutcome.cancelled;
    if (!context.mounted) return;

    switch (outcome) {
      case AccountUnlinkOutcome.success:
        // provider 라벨만 (PII 0) · 목록은 user stream 재방출로 갱신.
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.accountUnlinkSucceededSnackbar(providerLabel)),
          ),
        );
      case AccountUnlinkOutcome.reauthRequired:
        // D-06 으로 기대하지 않는 방어 매핑 — Surface D 와 같은 재로그인
        // 라우팅 (R_EXTRA_G3_REAUTH_LOGIN_BOUNCE: 재인증 표시 필수).
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.authReauthRequired)),
        );
        // await 전 캡처를 안 하는 이유 = router 없는 harness(golden)에서
        // 탭 → 다이얼로그 경로가 예외 없이 열려야 하고, 이 arm 만 router 가 필요하다.
        final router = GoRouter.of(context);
        unawaited(router.push(AppRoutes.buildReauthLocation(AppRoutes.login)));
      case AccountUnlinkOutcome.lastCredential:
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.settingsUnlinkFailedLastCredential)),
        );
      case AccountUnlinkOutcome.alreadyUnlinked:
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.settingsUnlinkFailedAlreadyUnlinked)),
        );
      case AccountUnlinkOutcome.transientFailure:
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.settingsUnlinkFailedTransient)),
        );
      case AccountUnlinkOutcome.appCheckFailed:
        // Phase 17 D-42 · D-43 — 해제 callable · provider 측 끊기의 App Check
        // 차단 · 재로그인 라우팅 0 · 연결 유지(같은 화면에서 재시도).
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.errorAppCheckFailed)),
        );
      case AccountUnlinkOutcome.failed:
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.settingsUnlinkFailedUnknown)),
        );
      case AccountUnlinkOutcome.identityMismatch:
        // Phase 16.10 D-08 — 다른 provider 계정으로 로그인함 · 연결 유지.
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              l10n.settingsUnlinkFailedIdentityMismatch(providerLabel),
            ),
          ),
        );
      case AccountUnlinkOutcome.disconnectFailed:
        // Phase 16.10 D-11 — provider 측 끊기 실패로 킷 해제 중단 · 연결 유지.
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.settingsUnlinkFailedDisconnect(providerLabel)),
          ),
        );
      case AccountUnlinkOutcome.unlinkFailedAfterDisconnect:
        // 16.10 review IN-03 (iteration 3) — provider 측은 끊겼고 킷 해제만
        // 실패한 부분 상태 · 킷 연결 유지.
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              l10n.settingsUnlinkFailedAfterDisconnect(providerLabel),
            ),
          ),
        );
      case AccountUnlinkOutcome.providerConfigFailed:
        // 16.10 review IN-04 (iteration 3) — 서버 provider 설정 결함 · 재시도로
        // 풀리지 않아 재시도 안내 없는 문구 · 연결 유지.
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              l10n.settingsUnlinkFailedProviderConfig(providerLabel),
            ),
          ),
        );
      case AccountUnlinkOutcome.cancelled:
        // 다이얼로그 닫힘 · provider 로그인 취소(16.10 D-11) — SnackBar 0.
        break;
    }
  }

  /// 로그아웃 확인 다이얼로그를 표시하고 확인 시
  /// [AuthRepository.signOutAndResetOnboarding] 을 호출한다 (10.2 D-A4).
  ///
  /// 이후 화면 이동은 authStateChanges → AuthRefresh → resolveAuthRedirect
  /// 분기 (2) 가 /onboarding 으로 처리한다 (Phase 10.2 D-B1, I2 invariant
  /// 단일 진리원). navigation 명시 호출 없음 (자연 redirect).
  ///
  /// **WR-18:** 다이얼로그 `await` 이후 `ref` 를 쓰기 전에 `context.mounted`
  /// 를 확인한다.
  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.authLogoutConfirmTitle),
        content: Text(l10n.authLogoutConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.authAccountSignOut),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      // WR-18: showDialog await 이후 라우팅이 일어났다면 WidgetRef 가 이미
      // disposed 일 수 있다.
      if (!context.mounted) return;
      await ref.read(authRepositoryProvider).signOutAndResetOnboarding();
    }
  }
}
