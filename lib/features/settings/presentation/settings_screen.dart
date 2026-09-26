// Phase 16 D-05/D-06/D-07/D-08 — Material 3 ListView + Danger zone 격리
// section + Withdrawal 진입 path.
//
// UI-SPEC Surface B (line 248~275) verbatim 채택:
// - 계정 section: 이메일 + 가입 수단 + 연결된 계정 (Phase 16.7 D-02 · D-09).
// - Danger zone section: explainer + 회원탈퇴 ListTile (destructive color).
// - 탈퇴 ListTile tap → WithdrawalConfirmationDialog.show.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../auth/data/auth_repository.dart';
import '../../home/presentation/provider_label_formatter.dart';
import '_widgets/account_linking_section.dart';
import '_widgets/danger_zone_section.dart';

/// 「연결된 계정」 행 템플릿을 자르는 sentinel (Phase 16.7 D-04 보강).
///
/// `settingsLinkedAccounts` 템플릿에 이 값을 넣고 split 해 앞 · 뒤 문구
/// 사이에 provider 별 span 을 끼운다. 사용자 영역(PUA) 문자라 ARB 번역
/// 문구에 나올 수 없다 — 템플릿의 placeholder 가 정확히 1회라는 전제는
/// 위젯 테스트 16.7-S05 가 3 locale 로 고정한다.
const String _kLinkedAccountsSentinel = '\u{E000}';

/// 설정 화면 (Phase 16 D-05~D-08).
///
/// Material 3 ListView 기반 — 계정 section + Danger zone section 의 2-section
/// 구성. Danger zone 의 탈퇴 ListTile 은 `Theme.colorScheme.error` 로 강조
/// 표시되며 탭 시 `WithdrawalConfirmationDialog` 가 표시된다.
///
/// **UI-SPEC Surface B verbatim mirror** (16-UI-SPEC.md line 248~275):
/// - 계정 section (settingsAccountSection) — 이메일 + 가입 수단 + 연결된
///   계정 (Phase 16.7 D-02 · D-09).
/// - Danger zone section (settingsDangerZoneSection) — explainer +
///   회원탈퇴 ListTile (Icons.delete_forever + destructive 색상).
class SettingsScreen extends ConsumerWidget {
  /// [SettingsScreen] 을 생성한다.
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    // WR-07: textTheme 은 AppTypography extension override 를 반영하지 않는다
    // — 스타터킷 사용자가 타이포를 교체하면 Settings 계열만 drift 한다.
    final typography = context.appTypography;
    final user = ref.watch(currentUserProvider);

    final email = user?.email ?? '-';
    // Phase 16.7 — 가입 수단 · 연결된 계정 분리. 홈 계정 카드와 같은 helper
    // (D-11 기록 없음 = 「-」 · 연결 = 보유 전부, D-12 미보유 기록값 그대로).
    final split = splitAccountProviders(user);
    final signUpValue = formatProviderIds(
      split.signUpProviderId == null
          ? const <String>[]
          : <String>[split.signUpProviderId!],
      l10n,
    );
    // style 미지정 — WidgetSpan 안 라벨도 ListTile title 의 DefaultTextStyle 을
    // 상속해 바깥 문단과 같은 스타일이 된다.
    final linked = buildLinkedAccountsValue(
      formatProviderLabels(split.linkedProviderIds, l10n),
      none: l10n.authAccountLinkedAccountsNone,
    );
    // 템플릿을 sentinel 로 잘라 앞 · 뒤 문구를 얻는다 (ko/en/ja 는 뒤가 빈 문자열).
    final parts = l10n
        .settingsLinkedAccounts(_kLinkedAccountsSentinel)
        .split(_kLinkedAccountsSentinel);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      // SafeArea — 최하단 회원탈퇴 ListTile 이 시스템 내비게이션 바에 가려져
      // 탭 불가가 되는 것을 방지한다. Android 15(API 35)+ 는 edge-to-edge 가
      // 강제되어 Scaffold body 가 내비게이션 바 영역까지 확장되며, 3버튼
      // 내비게이션(48dp)은 ListView 하단 padding(spacing.md=12dp)보다 크다.
      // AuthScaffold / TermsDetailScreen 의 `body: SafeArea(child: scrollable)`
      // 패턴 mirror.
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.symmetric(vertical: spacing.md),
          children: [
            // 계정 section heading.
            Padding(
              padding: EdgeInsets.fromLTRB(
                spacing.lg,
                spacing.sm,
                spacing.lg,
                spacing.xs,
              ),
              child: Text(
                l10n.settingsAccountSection,
                // UI-SPEC Layout Contract verbatim — accent 토큰은 chevron
                // 전용 화이트리스트라 heading 에서 걷어냈다.
                style: typography.labelMedium.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            // WR-14: 280dp 최소 뷰포트 오버플로 방어. 긴 이메일 · 가입 수단 행은
            // 같은 scope 의 _EnvironmentCard 가 쓰는 maxLines 2 + softWrap +
            // ellipsis 방어를 유지한다. 연결된 계정 행은 스크롤 ListView 안에서
            // 소셜 전체 + 이메일 목록을 줄이지 않고 전부 표시한다(D-02 개정) —
            // 줄바꿈은 provider 사이에서만 일어난다(D-04 보강).
            ListTile(
              leading: const Icon(Icons.alternate_email),
              title: Text(
                l10n.settingsAccountEmail(email),
                maxLines: 2,
                softWrap: true,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.how_to_reg),
              title: Text(
                l10n.settingsSignUpMethod(signUpValue),
                maxLines: 2,
                softWrap: true,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 연결된 계정 — maxLines · overflow 없음. 표시 span 의 WidgetSpan
            // 자리표시 문자가 낭독되지 않도록 semanticsLabel 을 plain join 으로
            // 명시한다 (UI-SPEC §Semantics).
            ListTile(
              leading: const Icon(Icons.link),
              title: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: parts.first),
                    linked.display,
                    TextSpan(text: parts.length > 1 ? parts.last : ''),
                  ],
                ),
                softWrap: true,
                semanticsLabel: l10n.settingsLinkedAccounts(linked.semantics),
              ),
            ),
            Gap(spacing.xxl),
            // 계정 연결 section (Surface D — 16-11). 계정 section 다음 /
            // Danger zone 전 (mockup 배치 verbatim, add-only). available 빈
            // set 시 SizedBox.shrink 로 graceful 미노출.
            const AccountLinkingSection(),
            Gap(spacing.xxl),
            // Danger zone — UI-SPEC line 261~275 (항상 최하단 격리).
            const DangerZoneSection(),
          ],
        ),
      ),
    );
  }
}
