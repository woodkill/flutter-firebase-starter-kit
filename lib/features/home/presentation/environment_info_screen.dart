import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../../core/providers/theme_provider.dart';
import '../../../core/theme/theme_extensions.dart';

/// 현재 빌드 환경 정보와 디자인 토큰 쇼케이스를 표시하는 화면.
///
/// Flavor, App Name, Firebase 연결 상태, Firebase Project ID를
/// 카드 형태로 표시하고, 디자인 토큰(컬러, 타이포그래피, 스페이싱)의
/// 시각적 쇼케이스와 테마 전환 토글을 제공한다.
/// 개발/QA 환경에서 현재 빌드 환경과 디자인 시스템을 확인하는 용도이다.
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Environment Info'),
        backgroundColor: context.colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: EdgeInsets.all(spacing.lg),
        children: [
          _ThemeToggleSection(ref: ref),
          Gap(spacing.xl),
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
                ? 'Connected'
                : 'Not Connected',
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
          Gap(spacing.xl),
          const _ColorPaletteSection(),
          Gap(spacing.xl),
          const _TypographySection(),
          Gap(spacing.xl),
          const _SpacingSection(),
          Gap(spacing.xl),
        ],
      ),
    );
  }
}

/// 라이트/시스템/다크 테마를 전환하는 [SegmentedButton] 토글 섹션.
class _ThemeToggleSection extends StatelessWidget {
  const _ThemeToggleSection({required this.ref});

  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final currentMode = ref.watch(themeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Theme Mode',
          style: context.appTypography.titleLarge,
        ),
        Gap(context.appSpacing.md),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.light,
                icon: Icon(Icons.light_mode),
                label: Text('Light'),
              ),
              ButtonSegment(
                value: ThemeMode.system,
                icon: Icon(Icons.brightness_auto),
                label: Text('System'),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: Icon(Icons.dark_mode),
                label: Text('Dark'),
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

/// [ColorScheme] 주요 색상과 [AppColors] 시맨틱 컬러를 표시하는 섹션.
class _ColorPaletteSection extends StatelessWidget {
  const _ColorPaletteSection();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final colorScheme = context.colorScheme;
    final spacing = context.appSpacing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Color Palette',
          style: context.appTypography.titleLarge,
        ),
        Gap(spacing.md),
        Text(
          'ColorScheme',
          style: context.appTypography.titleSmall,
        ),
        Gap(spacing.sm),
        Wrap(
          spacing: spacing.sm,
          runSpacing: spacing.sm,
          children: [
            _ColorSwatch(
              color: colorScheme.primary,
              label: 'primary',
            ),
            _ColorSwatch(
              color: colorScheme.secondary,
              label: 'secondary',
            ),
            _ColorSwatch(
              color: colorScheme.tertiary,
              label: 'tertiary',
            ),
            _ColorSwatch(
              color: colorScheme.error,
              label: 'error',
            ),
            _ColorSwatch(
              color: colorScheme.surface,
              label: 'surface',
              borderColor: colorScheme.outline,
            ),
            _ColorSwatch(
              color: colorScheme.onSurface,
              label: 'onSurface',
            ),
          ],
        ),
        Gap(spacing.lg),
        Text(
          'Semantic Colors (AppColors)',
          style: context.appTypography.titleSmall,
        ),
        Gap(spacing.sm),
        Wrap(
          spacing: spacing.sm,
          runSpacing: spacing.sm,
          children: [
            _ColorSwatch(
              color: colors.success,
              label: 'success',
              textColor: colors.onSuccess,
            ),
            _ColorSwatch(
              color: colors.warning,
              label: 'warning',
              textColor: colors.onWarning,
            ),
            _ColorSwatch(
              color: colors.info,
              label: 'info',
              textColor: colors.onInfo,
            ),
          ],
        ),
      ],
    );
  }
}

/// 단일 컬러 스와치를 표시하는 위젯.
class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.label,
    this.textColor,
    this.borderColor,
  });

  final Color color;
  final String label;
  final Color? textColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final spacing = context.appSpacing;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(spacing.sm),
            border: borderColor != null
                ? Border.all(color: borderColor!)
                : null,
          ),
          child: textColor != null
              ? Center(
                  child: Text(
                    'Aa',
                    style: context.appTypography.labelSmall
                        .copyWith(color: textColor),
                  ),
                )
              : null,
        ),
        Gap(spacing.xs),
        Text(
          label,
          style: context.appTypography.labelSmall,
        ),
      ],
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
          'Typography',
          style: typography.titleLarge,
        ),
        Gap(spacing.md),
        _TypographySample(
          label: 'displayLarge',
          style: typography.displayLarge,
        ),
        Gap(spacing.sm),
        _TypographySample(
          label: 'headlineMedium',
          style: typography.headlineMedium,
        ),
        Gap(spacing.sm),
        _TypographySample(
          label: 'titleLarge',
          style: typography.titleLarge,
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
          label: 'labelLarge',
          style: typography.labelLarge,
        ),
      ],
    );
  }
}

/// 단일 타이포그래피 스타일의 라벨과 샘플 텍스트를 표시하는 위젯.
class _TypographySample extends StatelessWidget {
  const _TypographySample({
    required this.label,
    required this.style,
  });

  final String label;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: context.appTypography.labelSmall.copyWith(
            color: context.colorScheme.onSurfaceVariant,
          ),
        ),
        Gap(context.appSpacing.xs),
        Text('Sample Text', style: style),
      ],
    );
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
          'Spacing',
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
