import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../../core/l10n/intl_extensions.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../l10n/generated/app_localizations.dart';

/// 현재 빌드 환경 정보와 디자인 토큰 쇼케이스를 표시하는 화면.
///
/// Flavor, App Name, Firebase 연결 상태, Firebase Project ID를
/// 카드 형태로 표시하고, 디자인 토큰(컬러, 타이포그래피, 스페이싱)의
/// 시각적 쇼케이스와 테마 전환 토글, 언어 선택 드롭다운을 제공한다.
/// 개발/QA 환경에서 현재 빌드 환경과 디자인 시스템, i18n 동작을
/// 확인하는 용도이다.
class EnvironmentInfoScreen extends ConsumerWidget {
  /// 환경 정보 화면을 생성한다.
  const EnvironmentInfoScreen({
    required this.isFirebaseInitialized,
    super.key,
  });

  /// Firebase 초기화 성공 여부.
  final bool isFirebaseInitialized;

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

    final spacing = context.appSpacing;
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.homeEnvironmentInfo),
        backgroundColor: context.colorScheme.inversePrimary,
      ),
      body: ScrollConfiguration(
        behavior:
            ScrollConfiguration.of(context).copyWith(overscroll: false),
        child: ListView(
          physics: const ClampingScrollPhysics(),
          padding: EdgeInsets.all(spacing.lg),
          children: [
            Text(
              'Build Environment',
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
              icon: isFirebaseInitialized
                  ? Icons.cloud_done
                  : Icons.cloud_off,
              label: 'Firebase',
              value: isFirebaseInitialized
                  ? l10n.homeFirebaseConnected
                  : l10n.homeFirebaseNotConnected,
              valueColor: isFirebaseInitialized
                  ? context.appColors.success
                  : context.appColors.warning,
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
        Text(
          l10n.homeThemeMode,
          style: context.appTypography.titleLarge,
        ),
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
              ref
                  .read(themeProvider.notifier)
                  .setThemeMode(modes.first);
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
        Text(
          l10n.homeLanguage,
          style: context.appTypography.titleLarge,
        ),
        Gap(spacing.md),
        // 언어 선택 드롭다운
        DropdownButton<Locale>(
          value: currentLocale,
          isExpanded: true,
          items: AppLocalizations.supportedLocales.map((locale) {
            return DropdownMenuItem(
              value: locale,
              child: Text(_localeDisplayName(locale)),
            );
          }).toList(),
          onChanged: (locale) {
            if (locale != null) {
              ref.read(localeProvider.notifier).setLocale(locale);
            }
          },
        ),
        Gap(spacing.lg),
        // 날짜 포맷 라이브 예제
        Text(
          l10n.showcaseDateFormat,
          style: context.appTypography.titleSmall,
        ),
        Gap(spacing.sm),
        Text(
          'yMd: ${now.formatYMD(currentLocale.languageCode)}',
          style: context.appTypography.bodyMedium,
        ),
        Gap(spacing.xs),
        Text(
          'yMMMMd: ${now.formatYMMMMd(currentLocale.languageCode)}',
          style: context.appTypography.bodyMedium,
        ),
        Gap(spacing.xs),
        Text(
          'jm: ${now.formatJm(currentLocale.languageCode)}',
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
          'compact: ${1234567.formatCompact(currentLocale.languageCode)}',
          style: context.appTypography.bodyMedium,
        ),
        Gap(spacing.xs),
        Text(
          'decimal: ${1234567.formatDecimal(currentLocale.languageCode)}',
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

  /// [Locale]을 사용자 친화적인 표시 이름으로 변환한다.
  String _localeDisplayName(Locale locale) {
    return switch (locale.languageCode) {
      'en' => 'English',
      'ko' => '한국어',
      _ => locale.languageCode,
    };
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
          _ColorSwatch(
            color: colorScheme.primaryFixed,
            label: 'primaryFixed',
          ),
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
          _ColorSwatch(
            color: colorScheme.onSecondary,
            label: 'onSecondary',
          ),
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
          _ColorSwatch(
            color: colorScheme.onTertiary,
            label: 'onTertiary',
          ),
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
          _ColorSwatch(
            color: colorScheme.surfaceTint,
            label: 'surfaceTint',
          ),
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
          Expanded(
            child: Text(
              label,
              style: context.appTypography.bodyMedium,
            ),
          ),
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
        Text(
          context.l10n.homeTypography,
          style: typography.titleLarge,
        ),
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
        _TypographySample(
          label: 'titleLarge',
          style: typography.titleLarge,
        ),
        Gap(spacing.sm),
        _TypographySample(
          label: 'titleMedium',
          style: typography.titleMedium,
        ),
        Gap(spacing.sm),
        _TypographySample(
          label: 'titleSmall',
          style: typography.titleSmall,
        ),
        Gap(spacing.sm),
        _TypographySample(
          label: 'bodyLarge',
          style: typography.bodyLarge,
        ),
        Gap(spacing.sm),
        _TypographySample(
          label: 'bodyMedium',
          style: typography.bodyMedium,
        ),
        Gap(spacing.sm),
        _TypographySample(
          label: 'bodySmall',
          style: typography.bodySmall,
        ),
        Gap(spacing.sm),
        _TypographySample(
          label: 'labelLarge',
          style: typography.labelLarge,
        ),
        Gap(spacing.sm),
        _TypographySample(
          label: 'labelMedium',
          style: typography.labelMedium,
        ),
        Gap(spacing.sm),
        _TypographySample(
          label: 'labelSmall',
          style: typography.labelSmall,
        ),
      ],
    );
  }
}

/// 타이포그래피 스타일명을 해당 스타일로 직접 표시하는 위젯.
class _TypographySample extends StatelessWidget {
  const _TypographySample({
    required this.label,
    required this.style,
  });

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
        Text(
          context.l10n.homeSpacing,
          style: context.appTypography.titleLarge,
        ),
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
        _SpacingBar(
          label: 'xxxl',
          width: spacing.xxxl,
          value: 48,
        ),
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
        Text(
          '$label (${value}px)',
          style: context.appTypography.labelMedium,
        ),
      ],
    );
  }
}

/// 환경 정보를 아이콘, 라벨, 값으로 표시하는 카드.
class _EnvironmentCard extends StatelessWidget {
  const _EnvironmentCard({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final spacing = context.appSpacing;

    return Card(
      child: Padding(
        padding: EdgeInsets.all(spacing.lg),
        child: Row(
          children: [
            Icon(
              icon,
              size: 32,
              color: context.colorScheme.primary,
            ),
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
    );
  }
}
