// Phase 17.1 D-02 · D-03 · D-04 · D-07 · D-15 — 설정 화면 = 하나의 목록.
//
// UI-SPEC §(S) 트리 그대로 (Q3-A 묶음 제목 · Q4-A 「내 계정」 라벨 + 이름):
// - 맨 위 행: 정식 = 계정 행(아바타 · 「내 계정」 · 표시 이름 → 이메일 → 「-」 ·
//   탭 = 계정 정보 화면 push — 계정 화면 진입점은 이 행 하나, D-03) · 게스트 =
//   「게스트로 이용 중 / 로그인 · 가입」 행(탭 = 로그인 화면).
// - 「일반」: 테마 · 언어 행 → 아래 시트 선택창 (D-04 · Q1-A · Q2-A).
// - 알림 섹션: 정식만 (D-07 · 17 D-02 정정 — 알림 토큰 = 정식 사용자).
// - 「개발자」 데모 행: release 가 아닌 빌드만 (D-14 · D-15).
// 「내 계정」 상세(사진 · 이메일 · 가입 수단 · 연결된 계정) · 계정 연결 ·
// Danger zone · 연결 해제 결과 매핑은 계정 정보 화면(account_screen.dart)에만
// 있다 (D-02 — Phase 16 D-05~D-08 · 16.7 · 16.8 · 16.10 · 17 D-03 · D-18 의
// 설정 쪽 코드를 옮겼다). 계정 화면 위젯은 import 하지 않는다 — 경로만 push 한다.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/l10n/locale_display_names.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../auth/data/auth_repository.dart';
import '_widgets/choice_sheet.dart';
import '_widgets/notifications_section.dart';
import '_widgets/profile_avatar.dart';
import '_widgets/settings_heading.dart';

/// 설정 화면 (Phase 17.1 D-02 · D-03 · D-04 · D-07 · D-15).
///
/// 정식 · 게스트가 같은 목록을 쓴다 — 맨 위 행 · 「일반」(테마 · 언어) ·
/// (정식만) 알림 섹션 · (release 가 아닌 빌드) 「개발자」 데모 행. 게스트 판정은
/// `authStateProvider` 값의 `isAnonymous` 다.
///
/// 정식 사용자의 맨 위 행은 계정 행([_AccountRow])이고 탭하면 계정 정보 화면
/// (`AppRoutes.account`)으로 간다 — 계정 상세 · 계정 연결 · 회원탈퇴는 그 화면에
/// 있다 (D-02).
class SettingsScreen extends ConsumerWidget {
  /// [SettingsScreen] 을 생성한다.
  const SettingsScreen({this.showsDemoRow = !kReleaseMode, super.key});

  /// release 가 아닌 빌드에서 데모 행을 보인다(D-14 · D-15) · 테스트는 false 로
  /// release 를 검증한다.
  ///
  /// 기본값은 const `!kReleaseMode` 라 release 빌드는 데모 행 · 「개발자」
  /// heading 을 그리지 않는다. 라우터의 `const SettingsScreen()` 호출부는 그대로
  /// 컴파일된다.
  final bool showsDemoRow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    // Phase 17.1 D-07 — 게스트 판정. loading · error 는 익명 아님으로 취급한다
    // (홈 AppBar 와 같은 식 · UI-SPEC E2).
    final isAnonymous = ref
        .watch(authStateProvider)
        .maybeWhen(
          data: (authUser) => authUser?.isAnonymous ?? false,
          orElse: () => false,
        );
    return _SettingsListScaffold(
      children: [
        if (isAnonymous) const _GuestRow() else const _AccountRow(),
        Gap(spacing.xxl),
        SettingsHeading(label: l10n.settingsGeneralSection),
        const _ThemeRow(),
        const _LanguageRow(),
        // 17 D-02 정정 — 알림 섹션(heading 「알림」 포함)은 정식 사용자만.
        if (!isAnonymous) ...[Gap(spacing.xxl), const NotificationsSection()],
        if (showsDemoRow) ...[
          Gap(spacing.xxl),
          SettingsHeading(label: l10n.settingsDeveloperSection),
          const _DemoRow(),
        ],
      ],
    );
  }
}

/// 설정 화면 바깥 트리 — AppBar(설정) › SafeArea › ListView(vertical md).
///
/// 게스트 · 정식 트리가 같이 쓴다 (Phase 17.1 D-07 — 분기는 children 만).
class _SettingsListScaffold extends StatelessWidget {
  const _SettingsListScaffold({required this.children});

  /// ListView 행 목록.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settingsTitle)),
      // SafeArea — 최하단 행(Phase 16 당시 회원탈퇴 · 지금은 데모 행 또는 알림
      // 섹션)이 시스템 내비게이션 바에 가려져 탭 불가가 되는 것을 방지한다. Android 15(API 35)+ 는 edge-to-edge 가
      // 강제되어 Scaffold body 가 내비게이션 바 영역까지 확장되며, 3버튼
      // 내비게이션(48dp)은 ListView 하단 padding(spacing.md=12dp)보다 크다.
      // AuthScaffold / TermsDetailScreen 의 `body: SafeArea(child: scrollable)`
      // 패턴 mirror.
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.symmetric(vertical: context.appSpacing.md),
          children: children,
        ),
      ),
    );
  }
}

/// 행 라벨(title) 문구 style — 계정 행 · 일반 행 공통 (UI-SPEC §Typography (R1)).
TextStyle _resolveLabelStyle(BuildContext context) => context
    .appTypography
    .bodySmall
    .copyWith(color: context.colorScheme.onSurfaceVariant);

/// 탭 가능한 설정 행의 trailing chevron (accent 화이트리스트).
Widget _buildChevron(BuildContext context) =>
    Icon(Icons.chevron_right, color: context.colorScheme.primary);

/// 계정 행 — 「내 계정」 + 표시 이름 · 탭 = 계정 정보 화면 push
/// (Phase 17.1 D-03 · UI-SPEC §(S) Q4-A).
///
/// 값 = 표시 이름 → 이메일 → 「-」 순(줄 수 제한 없이 softWrap). 아바타는
/// 표시 사진(`user.photoUrl` · 17 D-17 — 사진 행과 같은 값)이고 장식이라
/// semantics 에서 뺀다 — 낭독은 ListTile 병합 label 「내 계정\n이름」 이 맡는다.
/// 계정 화면 위젯은 import 하지 않는다 — 경로 상수만 쓴다.
class _AccountRow extends ConsumerWidget {
  const _AccountRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    return ListTile(
      leading: ExcludeSemantics(child: ProfileAvatar(photoUrl: user?.photoUrl)),
      title: Text(
        context.l10n.settingsAccountSection,
        style: _resolveLabelStyle(context),
      ),
      subtitle: Text(
        user?.displayName ?? user?.email ?? '-',
        softWrap: true,
        style: context.appTypography.titleMedium,
      ),
      trailing: _buildChevron(context),
      onTap: () => context.push(AppRoutes.account),
    );
  }
}

/// 게스트 행 — 「게스트로 이용 중 / 로그인 · 가입」 · 탭 = 로그인 화면 push
/// (Phase 17.1 D-07 · UI-SPEC §(S)).
class _GuestRow extends StatelessWidget {
  const _GuestRow();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListTile(
      leading: const ExcludeSemantics(child: ProfileAvatar(photoUrl: null)),
      title: Text(l10n.settingsGuestLabel, style: _resolveLabelStyle(context)),
      subtitle: Text(
        l10n.settingsSignInOrSignUp,
        softWrap: true,
        style: context.appTypography.titleMedium,
      ),
      trailing: _buildChevron(context),
      onTap: () => context.push(AppRoutes.login),
    );
  }
}

/// 테마 선택창 항목 순서 — 기본값(시스템)을 맨 위 (UI-SPEC (P)).
const List<ThemeMode> _kThemeModeOrder = [
  ThemeMode.system,
  ThemeMode.light,
  ThemeMode.dark,
];

/// [mode] 의 표시 라벨 (`settingsTheme{System,Light,Dark}`).
String _formatThemeMode(AppLocalizations l10n, ThemeMode mode) =>
    switch (mode) {
      ThemeMode.system => l10n.settingsThemeSystem,
      ThemeMode.light => l10n.settingsThemeLight,
      ThemeMode.dark => l10n.settingsThemeDark,
    };

/// 테마 행 — 현재값 표시 · 탭 = 테마 선택창 (D-04 · Q1-A · Q2-A).
///
/// `themeProvider` 가 loading · error 이면 값은 「시스템」(`ThemeMode.system`
/// fallback · UI-SPEC E3) — 행 단위 스피너 · 오류 표시는 없다. 저장은 기존
/// provider 의 optimistic 저장 그대로이고 변경 뒤 SnackBar 는 없다.
class _ThemeRow extends ConsumerWidget {
  const _ThemeRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final themeMode = ref
        .watch(themeProvider)
        .maybeWhen(data: (mode) => mode, orElse: () => ThemeMode.system);
    return ListTile(
      leading: const Icon(Icons.brightness_6),
      title: Text(l10n.settingsTheme, style: _resolveLabelStyle(context)),
      subtitle: Text(
        _formatThemeMode(l10n, themeMode),
        softWrap: true,
        style: context.appTypography.titleMedium,
      ),
      trailing: _buildChevron(context),
      onTap: () => _onTap(context, ref, current: themeMode),
    );
  }

  /// 선택창을 열고, 현재와 다른 값을 고르면 저장한다.
  Future<void> _onTap(
    BuildContext context,
    WidgetRef ref, {
    required ThemeMode current,
  }) async {
    final l10n = context.l10n;
    final picked = await showChoiceSheet<ThemeMode>(
      context,
      title: l10n.settingsTheme,
      options: [
        for (final mode in _kThemeModeOrder)
          (mode, _formatThemeMode(l10n, mode)),
      ],
      selected: current,
    );
    // null = 바깥 탭 · back · 현재값 다시 탭 — 변화 없음.
    if (picked == null || picked == current || !context.mounted) return;
    await ref.read(themeProvider.notifier).setThemeMode(picked);
  }
}

/// 언어 행 — 현재 언어 endonym · 탭 = 언어 선택창 (D-04 · Q1-A · Q2-A).
///
/// 항목 = `AppLocalizations.supportedLocales` 순서 · 라벨 = endonym. 값은 동기
/// `localeProvider` 라 loading · error 표시가 없고, 변경 뒤 SnackBar 는 없다
/// (Q2-A — 옛 홈 SnackBar 는 바꾸기 전 언어로 뜨던 결함).
class _LanguageRow extends ConsumerWidget {
  const _LanguageRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final locale = ref.watch(localeProvider);
    return ListTile(
      leading: const Icon(Icons.language),
      title: Text(l10n.settingsLanguage, style: _resolveLabelStyle(context)),
      subtitle: Text(
        localeDisplayName(locale),
        softWrap: true,
        style: context.appTypography.titleMedium,
      ),
      trailing: _buildChevron(context),
      onTap: () => _onTap(context, ref, current: locale),
    );
  }

  /// 선택창을 열고, 현재와 다른 언어를 고르면 저장한다.
  Future<void> _onTap(
    BuildContext context,
    WidgetRef ref, {
    required Locale current,
  }) async {
    final picked = await showChoiceSheet<Locale>(
      context,
      title: context.l10n.settingsLanguage,
      options: [
        for (final locale in AppLocalizations.supportedLocales)
          (locale, localeDisplayName(locale)),
      ],
      selected: current,
    );
    // null = 바깥 탭 · back · 현재값 다시 탭 — 변화 없음.
    if (picked == null || picked == current || !context.mounted) return;
    await ref.read(localeProvider.notifier).setLocale(picked);
  }
}

/// 데모 행 — 「개발자 · 데모 화면」 · 탭 = 데모 경로 push (D-14 · D-15).
///
/// 데모 화면 위젯은 import 하지 않는다 — 경로 상수만 쓴다.
class _DemoRow extends StatelessWidget {
  const _DemoRow();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final typography = context.appTypography;
    return ListTile(
      leading: const Icon(Icons.developer_mode),
      title: Text(l10n.demoScreenTitle, style: typography.titleMedium),
      subtitle: Text(
        l10n.settingsDemoScreenSubtitle,
        style: typography.bodyMedium.copyWith(
          color: context.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: _buildChevron(context),
      onTap: () => context.push(AppRoutes.developerDemo),
    );
  }
}
