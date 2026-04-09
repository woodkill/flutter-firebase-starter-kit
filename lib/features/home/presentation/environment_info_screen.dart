import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../../core/l10n/intl_extensions.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/l10n/locale_display_names.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../auth/data/auth_repository.dart';

/// 현재 빌드 환경 정보와 디자인 토큰 쇼케이스를 표시하는 화면.
///
/// Flavor, App Name, Firebase 연결 상태, Firebase Project ID를
/// 카드 형태로 표시하고, 디자인 토큰(컬러, 타이포그래피, 스페이싱)의
/// 시각적 쇼케이스와 테마 전환 토글, 언어 선택 드롭다운을 제공한다.
/// 개발/QA 환경에서 현재 빌드 환경과 디자인 시스템, i18n 동작을
/// 확인하는 용도이다.
class EnvironmentInfoScreen extends ConsumerWidget {
  /// 환경 정보 화면을 생성한다.
  const EnvironmentInfoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const flavor = String.fromEnvironment('flavor', defaultValue: 'dev');
    const appName = String.fromEnvironment(
      'appName',
      defaultValue: 'StarterKit',
    );
    const firebaseProjectId = String.fromEnvironment(
      'firebaseProjectId',
      defaultValue: '-',
    );
    final isFirebaseInitialized = ref.watch(isFirebaseInitializedProvider);

    final spacing = context.appSpacing;
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.homeEnvironmentInfo),
        backgroundColor: context.colorScheme.inversePrimary,
      ),
      body: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
        child: ListView(
          physics: const ClampingScrollPhysics(),
          padding: EdgeInsets.all(spacing.lg),
          children: [
            Text(
              l10n.homeBuildEnvironment,
              style: context.appTypography.titleLarge,
            ),
            Gap(spacing.md),
            _EnvironmentCard(
              icon: Icons.layers,
              label: 'Flavor',
              value: flavor.toUpperCase(),
            ),
            Gap(spacing.md),
            const _EnvironmentCard(
              icon: Icons.app_settings_alt,
              label: 'App Name',
              value: appName,
            ),
            Gap(spacing.md),
            _EnvironmentCard(
              icon: isFirebaseInitialized ? Icons.cloud_done : Icons.cloud_off,
              label: 'Firebase',
              value: isFirebaseInitialized
                  ? l10n.homeFirebaseConnected
                  : l10n.homeFirebaseNotConnected,
              valueColor: isFirebaseInitialized
                  ? context.appColors.success
                  : context.appColors.warning,
              semanticLabel: isFirebaseInitialized
                  ? l10n.homeFirebaseStatusConnected
                  : l10n.homeFirebaseStatusNotConnected,
            ),
            Gap(spacing.md),
            const _EnvironmentCard(
              icon: Icons.folder,
              label: 'Firebase Project ID',
              value: firebaseProjectId,
            ),
            Gap(spacing.md),
            const Divider(),
            Gap(spacing.md),
            const _ThemeToggleSection(),
            Gap(spacing.md),
            const Divider(),
            Gap(spacing.md),
            const _LanguageSection(),
            Gap(spacing.md),
            const Divider(),
            Gap(spacing.md),
            const _ColorPaletteSection(),
            Gap(spacing.md),
            const Divider(),
            Gap(spacing.md),
            const _TypographySection(),
            Gap(spacing.md),
            const Divider(),
            Gap(spacing.md),
            const _SpacingSection(),
            Gap(spacing.md),
            const Divider(),
            Gap(spacing.md),
            const _AccountSection(),
            Gap(spacing.xl),
          ],
        ),
      ),
    );
  }
}

/// 라이트/시스템/다크 테마를 전환하는 [SegmentedButton] 토글 섹션.
class _ThemeToggleSection extends ConsumerWidget {
  const _ThemeToggleSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMode = ref.watch(themeProvider);
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.homeThemeMode, style: context.appTypography.titleLarge),
        Gap(context.appSpacing.md),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<ThemeMode>(
            segments: [
              ButtonSegment(
                value: ThemeMode.light,
                icon: const Icon(Icons.light_mode),
                label: Text(l10n.homeThemeLight),
              ),
              ButtonSegment(
                value: ThemeMode.system,
                icon: const Icon(Icons.brightness_auto),
                label: Text(l10n.homeThemeSystem),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: const Icon(Icons.dark_mode),
                label: Text(l10n.homeThemeDark),
              ),
            ],
            selected: {currentMode},
            onSelectionChanged: (modes) {
              ref.read(themeProvider.notifier).setThemeMode(modes.first);
            },
          ),
        ),
      ],
    );
  }
}

/// 언어 선택 드롭다운과 i18n 포맷 쇼케이스를 표시하는 섹션.
///
/// [AppLocalizations.supportedLocales] 기반의 드롭다운으로 언어를 전환하고,
/// 날짜/숫자/plural 포맷의 라이브 예제를 표시한다.
class _LanguageSection extends ConsumerWidget {
  const _LanguageSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLocale = ref.watch(localeProvider);
    final spacing = context.appSpacing;
    final l10n = context.l10n;
    final now = DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.homeLanguage, style: context.appTypography.titleLarge),
        Gap(spacing.md),
        // 언어 선택 드롭다운
        DropdownButton<Locale>(
          value: currentLocale,
          isExpanded: true,
          items: AppLocalizations.supportedLocales.map((locale) {
            return DropdownMenuItem(
              value: locale,
              child: Text(localeDisplayName(locale)),
            );
          }).toList(),
          onChanged: (locale) async {
            if (locale == null) return;
            await ref.read(localeProvider.notifier).setLocale(locale);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(context.l10n.languageChanged),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        ),
        Gap(spacing.lg),
        // 날짜 포맷 라이브 예제
        Text(l10n.showcaseDateFormat, style: context.appTypography.titleSmall),
        Gap(spacing.sm),
        Text(
          '${l10n.showcaseDateShort}: '
          '${now.formatYMD(currentLocale.languageCode)}',
          style: context.appTypography.bodyMedium,
        ),
        Gap(spacing.xs),
        Text(
          '${l10n.showcaseDateLong}: '
          '${now.formatYMMMMd(currentLocale.languageCode)}',
          style: context.appTypography.bodyMedium,
        ),
        Gap(spacing.xs),
        Text(
          '${l10n.showcaseDateTime}: '
          '${now.formatJm(currentLocale.languageCode)}',
          style: context.appTypography.bodyMedium,
        ),
        Gap(spacing.lg),
        // 숫자 포맷 라이브 예제
        Text(
          l10n.showcaseNumberFormat,
          style: context.appTypography.titleSmall,
        ),
        Gap(spacing.sm),
        Text(
          '${l10n.showcaseNumberCompact}: '
          '${1234567.formatCompact(currentLocale.languageCode)}',
          style: context.appTypography.bodyMedium,
        ),
        Gap(spacing.xs),
        Text(
          '${l10n.showcaseNumberDecimal}: '
          '${1234567.formatDecimal(currentLocale.languageCode)}',
          style: context.appTypography.bodyMedium,
        ),
        Gap(spacing.lg),
        // Plural 예제
        Text(
          l10n.showcaseItemCount(0),
          style: context.appTypography.bodyMedium,
        ),
        Gap(spacing.xs),
        Text(
          l10n.showcaseItemCount(1),
          style: context.appTypography.bodyMedium,
        ),
        Gap(spacing.xs),
        Text(
          l10n.showcaseItemCount(42),
          style: context.appTypography.bodyMedium,
        ),
        Gap(spacing.lg),
        // 현재 로케일 표시
        Text(
          '${l10n.showcaseCurrentLocale}: ${currentLocale.languageCode}',
          style: context.appTypography.labelMedium,
        ),
      ],
    );
  }
}

/// [ColorScheme] 주요 색상과 [AppColors] 시맨틱 컬러를 표시하는 섹션.
class _ColorPaletteSection extends StatelessWidget {
  const _ColorPaletteSection();

  Widget _colorGroup(
    BuildContext context,
    String title,
    List<Widget> swatches,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: context.appTypography.titleSmall),
        Gap(context.appSpacing.sm),
        ...swatches,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final colorScheme = context.colorScheme;
    final spacing = context.appSpacing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.homeColorPalette,
          style: context.appTypography.titleLarge,
        ),
        Gap(spacing.md),
        _colorGroup(context, 'Primary', [
          _ColorSwatch(color: colorScheme.primary, label: 'primary'),
          _ColorSwatch(color: colorScheme.onPrimary, label: 'onPrimary'),
          _ColorSwatch(
            color: colorScheme.primaryContainer,
            label: 'primaryContainer',
          ),
          _ColorSwatch(
            color: colorScheme.onPrimaryContainer,
            label: 'onPrimaryContainer',
          ),
          _ColorSwatch(color: colorScheme.primaryFixed, label: 'primaryFixed'),
          _ColorSwatch(
            color: colorScheme.primaryFixedDim,
            label: 'primaryFixedDim',
          ),
          _ColorSwatch(
            color: colorScheme.onPrimaryFixed,
            label: 'onPrimaryFixed',
          ),
          _ColorSwatch(
            color: colorScheme.onPrimaryFixedVariant,
            label: 'onPrimaryFixedVariant',
          ),
        ]),
        Gap(spacing.md),
        _colorGroup(context, 'Secondary', [
          _ColorSwatch(color: colorScheme.secondary, label: 'secondary'),
          _ColorSwatch(color: colorScheme.onSecondary, label: 'onSecondary'),
          _ColorSwatch(
            color: colorScheme.secondaryContainer,
            label: 'secondaryContainer',
          ),
          _ColorSwatch(
            color: colorScheme.onSecondaryContainer,
            label: 'onSecondaryContainer',
          ),
          _ColorSwatch(
            color: colorScheme.secondaryFixed,
            label: 'secondaryFixed',
          ),
          _ColorSwatch(
            color: colorScheme.secondaryFixedDim,
            label: 'secondaryFixedDim',
          ),
          _ColorSwatch(
            color: colorScheme.onSecondaryFixed,
            label: 'onSecondaryFixed',
          ),
          _ColorSwatch(
            color: colorScheme.onSecondaryFixedVariant,
            label: 'onSecondaryFixedVariant',
          ),
        ]),
        Gap(spacing.md),
        _colorGroup(context, 'Tertiary', [
          _ColorSwatch(color: colorScheme.tertiary, label: 'tertiary'),
          _ColorSwatch(color: colorScheme.onTertiary, label: 'onTertiary'),
          _ColorSwatch(
            color: colorScheme.tertiaryContainer,
            label: 'tertiaryContainer',
          ),
          _ColorSwatch(
            color: colorScheme.onTertiaryContainer,
            label: 'onTertiaryContainer',
          ),
          _ColorSwatch(
            color: colorScheme.tertiaryFixed,
            label: 'tertiaryFixed',
          ),
          _ColorSwatch(
            color: colorScheme.tertiaryFixedDim,
            label: 'tertiaryFixedDim',
          ),
          _ColorSwatch(
            color: colorScheme.onTertiaryFixed,
            label: 'onTertiaryFixed',
          ),
          _ColorSwatch(
            color: colorScheme.onTertiaryFixedVariant,
            label: 'onTertiaryFixedVariant',
          ),
        ]),
        Gap(spacing.md),
        _colorGroup(context, 'Error', [
          _ColorSwatch(color: colorScheme.error, label: 'error'),
          _ColorSwatch(color: colorScheme.onError, label: 'onError'),
          _ColorSwatch(
            color: colorScheme.errorContainer,
            label: 'errorContainer',
          ),
          _ColorSwatch(
            color: colorScheme.onErrorContainer,
            label: 'onErrorContainer',
          ),
        ]),
        Gap(spacing.md),
        _colorGroup(context, 'Surface', [
          _ColorSwatch(
            color: colorScheme.surface,
            label: 'surface',
            borderColor: colorScheme.outline,
          ),
          _ColorSwatch(color: colorScheme.onSurface, label: 'onSurface'),
          _ColorSwatch(
            color: colorScheme.surfaceDim,
            label: 'surfaceDim',
            borderColor: colorScheme.outline,
          ),
          _ColorSwatch(
            color: colorScheme.surfaceBright,
            label: 'surfaceBright',
            borderColor: colorScheme.outline,
          ),
          _ColorSwatch(
            color: colorScheme.surfaceContainerLowest,
            label: 'containerLowest',
            borderColor: colorScheme.outline,
          ),
          _ColorSwatch(
            color: colorScheme.surfaceContainerLow,
            label: 'containerLow',
            borderColor: colorScheme.outline,
          ),
          _ColorSwatch(
            color: colorScheme.surfaceContainer,
            label: 'container',
            borderColor: colorScheme.outline,
          ),
          _ColorSwatch(
            color: colorScheme.surfaceContainerHigh,
            label: 'containerHigh',
          ),
          _ColorSwatch(
            color: colorScheme.surfaceContainerHighest,
            label: 'containerHighest',
          ),
          _ColorSwatch(
            color: colorScheme.onSurfaceVariant,
            label: 'onSurfaceVariant',
          ),
          _ColorSwatch(color: colorScheme.surfaceTint, label: 'surfaceTint'),
        ]),
        Gap(spacing.md),
        _colorGroup(context, 'Outline & Utility', [
          _ColorSwatch(color: colorScheme.outline, label: 'outline'),
          _ColorSwatch(
            color: colorScheme.outlineVariant,
            label: 'outlineVariant',
          ),
          _ColorSwatch(color: colorScheme.shadow, label: 'shadow'),
          _ColorSwatch(color: colorScheme.scrim, label: 'scrim'),
          _ColorSwatch(
            color: colorScheme.inverseSurface,
            label: 'inverseSurface',
          ),
          _ColorSwatch(
            color: colorScheme.onInverseSurface,
            label: 'onInverseSurface',
          ),
          _ColorSwatch(
            color: colorScheme.inversePrimary,
            label: 'inversePrimary',
          ),
        ]),
        Gap(spacing.md),
        _colorGroup(context, 'Semantic (AppColors)', [
          _ColorSwatch(color: colors.success, label: 'success'),
          _ColorSwatch(color: colors.onSuccess, label: 'onSuccess'),
          _ColorSwatch(color: colors.warning, label: 'warning'),
          _ColorSwatch(color: colors.onWarning, label: 'onWarning'),
          _ColorSwatch(color: colors.info, label: 'info'),
          _ColorSwatch(color: colors.onInfo, label: 'onInfo'),
        ]),
      ],
    );
  }
}

/// 단일 컬러를 가로 행(컬러바 + 라벨)으로 표시하는 위젯.
class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.label,
    this.borderColor,
  });

  final Color color;
  final String label;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final spacing = context.appSpacing;

    return Padding(
      padding: EdgeInsets.only(bottom: spacing.xs),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(spacing.sm),
              border: borderColor != null
                  ? Border.all(color: borderColor!)
                  : null,
            ),
          ),
          Gap(spacing.md),
          Expanded(child: Text(label, style: context.appTypography.bodyMedium)),
        ],
      ),
    );
  }
}

/// [AppTypography] 주요 스타일 샘플을 표시하는 섹션.
class _TypographySection extends StatelessWidget {
  const _TypographySection();

  @override
  Widget build(BuildContext context) {
    final typography = context.appTypography;
    final spacing = context.appSpacing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.l10n.homeTypography, style: typography.titleLarge),
        Gap(spacing.md),
        _TypographySample(
          label: 'displayLarge',
          style: typography.displayLarge,
        ),
        Gap(spacing.sm),
        _TypographySample(
          label: 'displayMedium',
          style: typography.displayMedium,
        ),
        Gap(spacing.sm),
        _TypographySample(
          label: 'displaySmall',
          style: typography.displaySmall,
        ),
        Gap(spacing.sm),
        _TypographySample(
          label: 'headlineLarge',
          style: typography.headlineLarge,
        ),
        Gap(spacing.sm),
        _TypographySample(
          label: 'headlineMedium',
          style: typography.headlineMedium,
        ),
        Gap(spacing.sm),
        _TypographySample(
          label: 'headlineSmall',
          style: typography.headlineSmall,
        ),
        Gap(spacing.sm),
        _TypographySample(label: 'titleLarge', style: typography.titleLarge),
        Gap(spacing.sm),
        _TypographySample(label: 'titleMedium', style: typography.titleMedium),
        Gap(spacing.sm),
        _TypographySample(label: 'titleSmall', style: typography.titleSmall),
        Gap(spacing.sm),
        _TypographySample(label: 'bodyLarge', style: typography.bodyLarge),
        Gap(spacing.sm),
        _TypographySample(label: 'bodyMedium', style: typography.bodyMedium),
        Gap(spacing.sm),
        _TypographySample(label: 'bodySmall', style: typography.bodySmall),
        Gap(spacing.sm),
        _TypographySample(label: 'labelLarge', style: typography.labelLarge),
        Gap(spacing.sm),
        _TypographySample(label: 'labelMedium', style: typography.labelMedium),
        Gap(spacing.sm),
        _TypographySample(label: 'labelSmall', style: typography.labelSmall),
      ],
    );
  }
}

/// 타이포그래피 스타일명을 해당 스타일로 직접 표시하는 위젯.
class _TypographySample extends StatelessWidget {
  const _TypographySample({required this.label, required this.style});

  final String label;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Text(label, style: style);
  }
}

/// [AppSpacing] 각 단계를 가로 막대로 시각화하는 섹션.
class _SpacingSection extends StatelessWidget {
  const _SpacingSection();

  @override
  Widget build(BuildContext context) {
    final spacing = context.appSpacing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.l10n.homeSpacing, style: context.appTypography.titleLarge),
        Gap(spacing.md),
        _SpacingBar(label: 'xs', width: spacing.xs, value: 4),
        Gap(spacing.sm),
        _SpacingBar(label: 'sm', width: spacing.sm, value: 8),
        Gap(spacing.sm),
        _SpacingBar(label: 'md', width: spacing.md, value: 12),
        Gap(spacing.sm),
        _SpacingBar(label: 'lg', width: spacing.lg, value: 16),
        Gap(spacing.sm),
        _SpacingBar(label: 'xl', width: spacing.xl, value: 24),
        Gap(spacing.sm),
        _SpacingBar(label: 'xxl', width: spacing.xxl, value: 32),
        Gap(spacing.sm),
        _SpacingBar(label: 'xxxl', width: spacing.xxxl, value: 48),
      ],
    );
  }
}

/// 단일 간격 값을 가로 막대로 시각화하는 위젯.
class _SpacingBar extends StatelessWidget {
  const _SpacingBar({
    required this.label,
    required this.width,
    required this.value,
  });

  final String label;
  final double width;
  final int value;

  @override
  Widget build(BuildContext context) {
    final spacing = context.appSpacing;

    return Row(
      children: [
        Container(
          width: width,
          height: 24,
          decoration: BoxDecoration(
            color: context.colorScheme.primary,
            borderRadius: BorderRadius.circular(spacing.xs),
          ),
        ),
        Gap(spacing.sm),
        Text('$label (${value}px)', style: context.appTypography.labelMedium),
      ],
    );
  }
}

/// Phase 6 Account 섹션 (D-33 ~ D-36).
///
/// [currentUserProvider]를 watch하여 인증 상태에 따라 사용자 정보를 표시한다.
/// 비인증 상태일 경우 섹션 자체를 숨긴다 (D-36).
/// 인증 상태일 경우 displayName/email/uid/createdAt/providers/ID 토큰 복사
/// 버튼(kDebugMode)/로그아웃 버튼을 표시한다.
class _AccountSection extends ConsumerWidget {
  const _AccountSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();

    final spacing = context.appSpacing;
    final l10n = context.l10n;
    final locale = ref.watch(localeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.authAccountSectionTitle,
          style: context.appTypography.titleLarge,
        ),
        Gap(spacing.md),
        _EnvironmentCard(
          icon: Icons.person,
          label: l10n.authAccountDisplayName,
          value: user.displayName ?? '-',
        ),
        Gap(spacing.md),
        _EnvironmentCard(
          icon: Icons.email,
          label: l10n.authAccountEmail,
          value: user.email,
        ),
        Gap(spacing.md),
        InkWell(
          onTap: () => _copyUid(context, l10n, user.uid),
          child: _EnvironmentCard(
            icon: Icons.fingerprint,
            label: l10n.authAccountUid,
            value: user.uid.length > 8
                ? '${user.uid.substring(0, 8)}...'
                : user.uid,
          ),
        ),
        Gap(spacing.md),
        _EnvironmentCard(
          icon: Icons.calendar_today,
          label: l10n.authAccountCreatedAt,
          value: user.createdAt.formatYMD(locale.languageCode),
        ),
        // Photo URL: 옵션 B (D-35 Phase 6 축소). user.photoUrl 이 null 이
        // 아닐 때만 카드를 표시하여 User 모델 변경 없이 UI-SPEC 의 photoUrl
        // 표시 요구를 만족한다.
        if (user.photoUrl != null) ...[
          Gap(spacing.md),
          _EnvironmentCard(
            icon: Icons.image,
            label: l10n.authAccountPhotoUrl,
            value: user.photoUrl!,
          ),
        ],
        Gap(spacing.md),
        // Providers: 옵션 B (D-35 Phase 6 축소). User 모델에 providerIds
        // 필드를 도입하지 않고 Phase 6 범위에서 authAccountProviderEmailPassword
        // 고정 라벨로 표시한다. 추후 소셜 로그인 phase 에서 User 모델 확장과
        // 함께 실제 providerData 매핑으로 교체 예정.
        _EnvironmentCard(
          icon: Icons.security,
          label: l10n.authAccountProviders,
          value: l10n.authAccountProviderEmailPassword,
        ),
        if (kDebugMode) ...[
          Gap(spacing.md),
          OutlinedButton.icon(
            onPressed: () => _copyIdToken(context, ref, l10n),
            icon: const Icon(Icons.key),
            label: Text(l10n.authAccountCopyToken),
          ),
        ],
        Gap(spacing.md),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: context.colorScheme.error,
            side: BorderSide(color: context.colorScheme.error),
          ),
          onPressed: () => _confirmSignOut(context, ref),
          icon: const Icon(Icons.logout),
          label: Text(l10n.authAccountSignOut),
        ),
      ],
    );
  }

  /// uid 전체를 클립보드에 복사하고 SnackBar로 안내한다.
  Future<void> _copyUid(
    BuildContext context,
    AppLocalizations l10n,
    String uid,
  ) async {
    await Clipboard.setData(ClipboardData(text: uid));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.authAccountCopied),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Firebase ID 토큰을 클립보드에 복사한다 (디버그 모드 전용).
  ///
  /// [firebaseAuthProvider] 경유로 정적 싱글톤 직접 접근을 회피한다
  /// (D-12 + Q4 RESOLVED).
  ///
  /// `getIdToken()` 이 null 을 반환하면 (currentUser 가 null 이거나
  /// 토큰 조회 실패) 디버그 SnackBar + debugPrint 로 사유를 안내한다.
  Future<void> _copyIdToken(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final auth = ref.read(firebaseAuthProvider);
    final token = await auth.currentUser?.getIdToken();
    if (!context.mounted) return;
    if (token == null) {
      if (kDebugMode) {
        debugPrint('_copyIdToken: getIdToken() returned null');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.debugAuthTokenUnavailable),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: token));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.authAccountCopied),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 로그아웃 확인 다이얼로그를 표시하고 확인 시 [signOut]을 호출한다.
  ///
  /// 이후 화면 이동은 authStateChanges → AuthChangeNotifier → authRedirect
  /// 가 /login 으로 처리한다 (D-05).
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
      await ref.read(authRepositoryProvider).signOut();
    }
  }
}

/// 환경 정보를 아이콘, 라벨, 값으로 표시하는 카드.
///
/// 카드 전체를 [Semantics] 컨테이너로 묶어 스크린 리더에 단일 노드로
/// 노출한다. [semanticLabel] 미지정 시 `"$label: $value"` 형태의
/// fallback 라벨이 자동 적용된다 (예: `"Flavor: DEV"`).
class _EnvironmentCard extends StatelessWidget {
  const _EnvironmentCard({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.semanticLabel,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  /// Semantics 라벨. null이면 `"$label: $value"` fallback이 자동 적용된다.
  ///
  /// Firebase 카드처럼 상태에 따라 라벨이 달라지는 경우 호출부에서
  /// l10n 기반 완성 문자열을 전달한다.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final spacing = context.appSpacing;
    // semanticLabel 미지정 시 "$label: $value" fallback 자동 생성.
    final resolvedSemanticLabel = semanticLabel ?? '$label: $value';

    return Semantics(
      container: true,
      excludeSemantics: true,
      label: resolvedSemanticLabel,
      child: Card(
        child: Padding(
          padding: EdgeInsets.all(spacing.lg),
          child: Row(
            children: [
              Icon(icon, size: 32, color: context.colorScheme.primary),
              Gap(spacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Gap(spacing.xs),
                    Text(
                      value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      softWrap: true,
                      style: context.textTheme.titleMedium?.copyWith(
                        color: valueColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
