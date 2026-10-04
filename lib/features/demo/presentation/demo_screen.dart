// Phase 17.1 D-14 · D-16 · D-17 — 개발 · 데모 화면.
//
// 옛 홈(Phase 17.1 이전 `/` 화면)에서 production 기능(알림 탭 리스너 · 공지
// 배너 · 게스트 바 · 로그인 버튼 · 설정 아이콘 → 새 홈 / 계정 정보 → 계정 화면)을
// 뺀 나머지다. 테마 토글 · 언어 드롭다운은 없다(D-04 — 바꾸는 곳은 설정 하나).
// GoRoute 는 `app_router.dart` 에서 const `!kReleaseMode` 일 때만 등록되고, 이
// 파일을 import 하는 lib 파일도 라우터 하나뿐이다(release tree-shake · D-14).

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../../core/analytics/analytics_service.dart';
import '../../../core/config/app_config.dart';
import '../../../core/crashlytics/crashlytics_service.dart';
import '../../../core/l10n/intl_extensions.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/auth/provider_label_formatter.dart';
import '../../../shared/widgets/error_snack_bar.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/_widgets/auth_required.dart';
import '../../notifications/data/test_push_client.dart';
import '../../onboarding/presentation/onboarding_notifier.dart';

// IN-03 — 매직 넘버를 저장소의 지배적 규약 2가지(설계 토큰 유도 / 파일 상단
// 명명 상수)로 정리한다. 아래 값들은 `spacing.*` 스케일(4/8/12/16/24/32/48)
// 에서 유도되지 않는 컴포넌트 고유 치수이므로 명명 상수로 승격한다. 이
// 프로젝트에는 `AppIconSizes` / `AppComponentSizes` extension 이 없으므로
// 토큰 신설 대신 상수 규약(splash_screen.dart 의 `_kLogoSize` 선례) 을 따른다.

/// 컬러 스와치 한 변의 길이 (logical pixel, IN-03).
const double _kSwatchSize = 40.0;

/// 스페이싱 쇼케이스 막대의 높이 (logical pixel, IN-03).
const double _kSpacingBarHeight = 24.0;

/// photoUrl 썸네일 한 변의 길이 (logical pixel, IN-03).
const double _kThumbnailSize = 48.0;

/// 환경 카드 leading 아이콘의 크기 (logical pixel, IN-03).
const double _kEnvCardIconSize = 32.0;

/// 개발 · 데모 화면 — release 가 아닌 빌드에서만 등록된다(D-14).
///
/// 빌드 환경 카드 4 · 언어별 날짜 · 숫자 · 복수형 예시 · 컬러 · 타이포 ·
/// 스페이싱 쇼케이스 · 계정 디버그 정보 · 보호 예시 · Dev Tools(kDebugMode)를
/// 한 목록으로 보여 준다. production 배선(알림 탭 리스너 · 공지 배너 · 게스트
/// 바 · 로그인 버튼 · 설정 아이콘)은 없다(D-17). push 로 열리므로 AppBar 는
/// 뒤로가기만 둔다.
class DemoScreen extends ConsumerWidget {
  /// 데모 화면을 만든다.
  const DemoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 표시값도 [AppConfig] 를 단일 진실원으로 읽는다 — 화면이 자체
    // defaultValue 로 'dev' 를 보여주면 dart-define 누락을 화면에서 검출할
    // 수 없다. 미주입 시 빈 문자열이므로 경고 chip 으로 노출한다.
    final flavor = AppConfig.flavor;
    final appName = AppConfig.appName;
    const firebaseProjectId = String.fromEnvironment(
      'firebaseProjectId',
      defaultValue: '-',
    );
    final isFirebaseInitialized = ref.watch(isFirebaseInitializedProvider);

    final spacing = context.appSpacing;
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.demoScreenTitle)),
      // 옛 홈 ListView 그대로(UI-SPEC E7 — 넘치면 스크롤 · 하단 inset padding).
      body: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
        child: ListView(
          physics: const ClampingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            spacing.lg,
            spacing.lg,
            spacing.lg,
            spacing.lg + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            Text(
              l10n.homeBuildEnvironment,
              style: context.appTypography.titleLarge,
            ),
            Gap(spacing.md),
            _EnvironmentCard(
              icon: Icons.layers,
              label: l10n.homeEnvFlavor,
              // 미주입 시 '-' + warn chip — dart-define 누락을 육안 검출.
              value: flavor.isEmpty ? '-' : flavor.toUpperCase(),
              status: flavor.isEmpty ? _EnvStatus.warn : _EnvStatus.none,
            ),
            Gap(spacing.md),
            _EnvironmentCard(
              icon: Icons.app_settings_alt,
              label: l10n.homeEnvAppName,
              // 미주입 시 '-' + warn chip — flavor 카드와 동일 패턴.
              value: appName.isEmpty ? '-' : appName,
              status: appName.isEmpty ? _EnvStatus.warn : _EnvStatus.none,
            ),
            Gap(spacing.md),
            _EnvironmentCard(
              icon: isFirebaseInitialized ? Icons.cloud_done : Icons.cloud_off,
              label: l10n.homeEnvFirebase,
              value: isFirebaseInitialized
                  ? l10n.homeFirebaseConnected
                  : l10n.homeFirebaseNotConnected,
              status: isFirebaseInitialized ? _EnvStatus.ok : _EnvStatus.warn,
              semanticLabel: isFirebaseInitialized
                  ? l10n.homeFirebaseStatusConnected
                  : l10n.homeFirebaseStatusNotConnected,
            ),
            Gap(spacing.md),
            _EnvironmentCard(
              icon: Icons.folder,
              label: l10n.homeEnvFirebaseProjectId,
              value: firebaseProjectId,
              // WR-01: placeholder (`your-...`) 프로젝트 ID 가 남아있으면
              // warn chip 으로 표시해 사용자가 실제 값으로 오인하지 않도록 경고.
              status: firebaseProjectId.startsWith('your-')
                  ? _EnvStatus.warn
                  : _EnvStatus.none,
              semanticLabel: firebaseProjectId.startsWith('your-')
                  ? l10n.homeFirebaseProjectIdPlaceholderWarning
                  : null,
            ),
            Gap(spacing.md),
            const Divider(),
            Gap(spacing.md),
            const _LanguageFormatSection(),
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
            const _AccountDebugSection(),
            Gap(spacing.md),
            const Divider(),
            Gap(spacing.md),
            // Phase 10 D-11: 보호 예시 섹션 (항상 렌더, 버튼은 AuthRequired 래핑).
            const _ProtectedExampleSection(),
            if (kDebugMode) ...[
              Gap(spacing.md),
              const Divider(),
              Gap(spacing.md),
              // Phase 10 D-32/D-33: Dev Tools (디버그 빌드 전용).
              const _DevToolsSection(),
            ],
            Gap(spacing.xl),
          ],
        ),
      ),
    );
  }
}

/// 현재 locale 의 날짜 · 숫자 · 복수형 형식 예시를 보여 주는 섹션.
///
/// 언어를 바꾸는 곳은 설정 하나다(D-04) — 이 섹션은 [localeProvider] 를 읽기만
/// 하고, 날짜/숫자/plural 포맷의 라이브 예제와 현재 locale 코드를 표시한다.
class _LanguageFormatSection extends ConsumerWidget {
  const _LanguageFormatSection();

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
        _colorGroup(context, context.l10n.homeColorGroupPrimary, [
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
        _colorGroup(context, context.l10n.homeColorGroupSecondary, [
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
        _colorGroup(context, context.l10n.homeColorGroupTertiary, [
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
        _colorGroup(context, context.l10n.homeColorGroupError, [
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
        _colorGroup(context, context.l10n.homeColorGroupSurface, [
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
        _colorGroup(context, context.l10n.homeColorGroupOutline, [
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
            width: _kSwatchSize,
            height: _kSwatchSize,
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

/// 타이포그래피 스타일명을 메타 라벨로 표시하고, 영문(라틴) + 한국어(CJK)
/// 패가그램(Pangram)으로 폰트 메트릭/가독성을 비교 가능한 위젯.
///
/// 라벨 행은 작은 메타 typography 로 스타일명(예: `displayLarge`)을 표시하고,
/// 그 아래에 동일한 [style] 로 라틴 패가그램과 한국어 패가그램을 렌더한다.
/// 이를 통해 단일 화면에서 영문/CJK 의 fontSize·lineHeight·letterSpacing
/// 효과를 함께 비교할 수 있다 (03-UI-REVIEW Top 3 #3 권고).
///
/// 패가그램 자체는 다국어 무관 fixed string 으로 i18n 키 대상에서 제외한다
/// — 폰트 비교가 목적이므로 모든 로케일에서 동일하게 표시되어야 한다.
class _TypographySample extends StatelessWidget {
  const _TypographySample({required this.label, required this.style});

  /// M3 공식 라틴 패가그램. 모든 알파벳을 1회 이상 포함한다.
  static const String _latinPangram =
      'The quick brown fox jumps over the lazy dog';

  /// CJK 폰트 메트릭 비교용 한국어 패가그램.
  static const String _koreanPangram = '다람쥐 헌 쳇바퀴에 타고파';

  final String label;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final spacing = context.appSpacing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: context.appTypography.labelSmall.copyWith(
            color: context.colorScheme.onSurfaceVariant,
          ),
        ),
        Gap(spacing.xs),
        Text(_latinPangram, style: style),
        Gap(spacing.xs),
        Text(_koreanPangram, style: style),
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
          height: _kSpacingBarHeight,
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

/// 계정 디버그 정보 카드 묶음 (Phase 17.1 D-16 — 옛 홈 계정 섹션의 데모 몫).
///
/// [currentUserProvider] 가 null(비인증)이면 숨긴다. UID(탭 복사) · photoUrl
/// 썸네일 · 가입 수단 · 연결된 계정(Phase 16.7 D-01) · ID 토큰 복사 버튼
/// (kDebugMode)을 보여 준다. 게스트(익명)도 같은 규칙이라 보인다. 이름 · 이메일 ·
/// 가입일 · 로그아웃은 계정 화면이 맡는다(D-01).
class _AccountDebugSection extends ConsumerWidget {
  const _AccountDebugSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();

    final spacing = context.appSpacing;
    final l10n = context.l10n;
    // Phase 16.7 — 가입 수단 · 연결된 계정 분리 (D-11 추론 0 · D-12 미보유
    // 기록값 그대로). 게스트(익명)도 같은 규칙이라 isAnonymous 분기가 없다
    // (D-06).
    final split = splitAccountProviders(user);
    final signUpValue = formatSignUpMethod(split.signUpProviderId, l10n);
    final linked = buildLinkedAccountsValue(
      formatProviderLabels(split.linkedProviderIds, l10n),
      none: l10n.authAccountLinkedAccountsNone,
      style: context.appTypography.titleMedium,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.demoAccountDebugSection,
          style: context.appTypography.titleLarge,
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
        // Photo URL: photoUrl이 존재하면 썸네일 이미지로 표시.
        if (user.photoUrl != null) ...[
          Gap(spacing.md),
          _EnvironmentCard(
            icon: Icons.image,
            label: l10n.authAccountPhotoUrl,
            child: ClipRRect(
              // IN-03: 반경은 spacing 스케일에서 유도한다 (sm = 8).
              borderRadius: BorderRadius.circular(spacing.sm),
              child: CachedNetworkImage(
                imageUrl: user.photoUrl!,
                width: _kThumbnailSize,
                height: _kThumbnailSize,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => const Icon(Icons.broken_image),
              ),
            ),
          ),
        ],
        Gap(spacing.md),
        // Phase 16.7 D-01 첫 카드 — 가입 수단. 기록 없음(null)이면 '-'
        // (D-11 — 추론 0), 미지 값은 formatProviderIds 의 errorUnknownProvider
        // (D-12). value 경로라 maxLines 2 · ellipsis 방어가 그대로 적용된다.
        _EnvironmentCard(
          icon: Icons.how_to_reg,
          label: l10n.authAccountSignUpMethod,
          value: signUpValue,
        ),
        Gap(spacing.md),
        // Phase 16.7 D-01 둘째 카드 — 연결된 계정(보유 − 가입 수단, D-05
        // 고정 순서). 0개면 숨기지 않고 「없음」 (D-03). 값은 provider 라벨마다
        // WidgetSpan 이라 라벨 내부에서 줄이 바뀌지 않고 maxLines 없이 전부
        // 보인다 (D-02 개정 · D-04 보강). child 슬롯은 fallback semantics 에서
        // 값이 빠지므로 semanticLabel 을 plain join 으로 반드시 명시한다
        // (UI-SPEC §Semantics).
        _EnvironmentCard(
          icon: Icons.link,
          label: l10n.authAccountLinkedAccounts,
          semanticLabel:
              '${l10n.authAccountLinkedAccounts}: ${linked.semantics}',
          child: Text.rich(
            linked.display,
            softWrap: true,
            style: context.appTypography.titleMedium,
          ),
        ),
        if (kDebugMode) ...[
          Gap(spacing.md),
          OutlinedButton.icon(
            onPressed: () => _copyIdToken(context, ref, l10n),
            icon: const Icon(Icons.key),
            label: Text(l10n.authAccountCopyToken),
          ),
        ],
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
  ///
  /// **IN-05:** 복사 성공 SnackBar 는 `debugAuthTokenCopiedWarning` (디버그
  /// 전용 + 공유 금지 + 1시간 만료 경고) 를 쓴다. 호출부가 `kDebugMode` 로
  /// 가드되어 릴리스 표면은 아니지만, 클립보드는 타 앱이 읽을 수 있고 ID
  /// 토큰은 bearer 자격증명이다.
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
    // IN-05: 클립보드는 다른 앱이 읽을 수 있고 Firebase ID 토큰은 1시간
    // 유효한 bearer 자격증명이다. generic "복사되었습니다" 대신 공유 금지 +
    // 만료 창을 명시한 전용 문구를 쓴다 (authAccountCopied 는 비밀이 아닌
    // uid 를 복사하는 _copyUid 전용으로 남긴다). 문구 자체에는 토큰/이메일/
    // uid 를 넣지 않는다.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.debugAuthTokenCopiedWarning),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// 환경 카드 값(value) 의 시맨틱 상태.
///
/// chip 패턴으로 렌더될 때 배경/전경 색 토큰 페어링을 강제하여
/// 호출자가 토큰 계약([AppColors.success]+[AppColors.onSuccess],
/// [AppColors.warning]+[AppColors.onWarning]) 을 깨뜨릴 수 없도록 한다.
/// WCAG AA 대비비를 자동으로 만족한다 (light/dark 양 모드).
enum _EnvStatus {
  /// 상태 배지 없음 (기본). 일반 텍스트 스타일로 값을 표시한다.
  none,

  /// 정상/연결됨 상태. [AppColors.success] 배경 + [AppColors.onSuccess]
  /// 전경의 chip 컨테이너로 값을 감싼다.
  ok,

  /// 경고/미연결 상태. [AppColors.warning] 배경 + [AppColors.onWarning]
  /// 전경의 chip 컨테이너로 값을 감싼다.
  warn,
}

/// AuthRequired 래퍼 패턴의 사용법을 보여주는 예시 섹션 (Phase 10 D-11).
///
/// - 항상 렌더 (isAnonymous 관계없이).
/// - 버튼은 [AuthRequired] 로 래핑되어 익명 사용자는 [LoginPromptSheet],
///   정식 사용자는 SnackBar 피드백을 받는다.
/// - 버튼의 `onPressed` 는 null 컨벤션 (AuthRequired 가 탭 가로챔).
class _ProtectedExampleSection extends ConsumerWidget {
  const _ProtectedExampleSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    final typography = context.appTypography;
    final colorScheme = context.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.homeProtectedExampleTitle, style: typography.titleLarge),
        Gap(spacing.sm),
        Text(
          l10n.homeProtectedExampleBody,
          style: typography.bodyMedium.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        Gap(spacing.md),
        AuthRequired(
          onAuthenticated: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l10n.homeProtectedExampleCta),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
          child: OutlinedButton.icon(
            // AuthRequired 가 GestureDetector + AbsorbPointer 로 가로챔.
            onPressed: null,
            icon: const Icon(Icons.lock_outline),
            label: Text(l10n.homeProtectedExampleCta),
          ),
        ),
      ],
    );
  }
}

/// 개발자 편의용 디버그 도구 섹션 (Phase 10 D-32, D-33).
///
/// [kDebugMode] 가드는 호출부 ([DemoScreen] build 메서드) 에서
/// 수행되므로 본 위젯은 디버그 빌드에서만 빌드된다. Dart 컴파일러는
/// release 빌드에서 `kDebugMode == false` 상수 분기를 tree-shake 한다
/// (T-10-16 방어).
///
/// 제공 기능 5종:
/// 1. Reset onboarding — [OnboardingNotifier.reset] 호출 (Plan 03 public,
///    `@visibleForTesting` 없음; WARNING #8 lint clean).
/// 2. Trigger error — [CrashlyticsService.recordError] 호출.
/// 3. Trigger analytics — [AnalyticsService.logEvent] 호출.
/// 4. Send test push — [TestPushClient.send] 호출 (Phase 17 D-05 ·
///    [_SendTestPushButton]).
/// 5. Force sign out — [AuthRepository.signOutAndResetOnboarding] 호출
///    (Phase 10.2 D-A4 — 계정 화면 로그아웃 확인 뒤 동작과 완전 동일,
///    I2 invariant 단일 진리원). destructive 계열이라 계속 마지막이다.
class _DevToolsSection extends ConsumerWidget {
  const _DevToolsSection();

  /// 온보딩 상태를 초기화한다 (D-33).
  Future<void> _handleResetOnboarding(
    BuildContext context,
    WidgetRef ref,
  ) async {
    // Plan 03 수정판: OnboardingNotifier.reset 은 public (WARNING #8).
    await ref.read(onboardingProvider.notifier).reset();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.devToolsResetOnboardingDone),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Crashlytics 에 테스트 에러를 전송한다 (D-33).
  Future<void> _handleTriggerError(BuildContext context, WidgetRef ref) async {
    final err = Exception('Dev Tools test error');
    await ref
        .read(crashlyticsServiceProvider)
        .recordError(err, StackTrace.current, reason: 'dev_tools_test');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.devToolsTriggerErrorDone),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Analytics 에 테스트 이벤트를 전송한다 (D-33).
  Future<void> _handleTriggerAnalytics(
    BuildContext context,
    WidgetRef ref,
  ) async {
    await ref.read(analyticsServiceProvider).logEvent('dev_tools_test_event');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.devToolsTriggerAnalyticsDone),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 즉시 강제 로그아웃 후 onboarding reset 한다 (Phase 10.2 D-A4).
  ///
  /// 확인 다이얼로그 없음 (D-33 기본 정책). 계정 화면 로그아웃 확인 뒤
  /// 동작과 완전 동일 (I2 단일 진리원). 화면 이동은 resolveAuthRedirect 분기 (2)
  /// 자연 redirect (Phase 10.2 D-B1).
  ///
  /// **D-A6: SnackBar / Loading indicator 의도적 미제공.** logout 은 정상
  /// 흐름이므로 over-instrumentation 회피. 시그니처에 [context] 를 유지하는
  /// 이유는 같은 `_DevToolsSection` 의 4 핸들러
  /// (`_handleResetOnboarding` / `_handleTriggerError` /
  /// `_handleTriggerAnalytics` / `_handleForceSignOut`) 통일성이며,
  /// 본 함수에서 [context] 를 사용해 SnackBar 등을 표시하면 D-A6 결정을
  /// silent 위배하는 것이므로 추후 변경 시 `docs/manual.md`
  /// `## App Entry State Machine (Phase 10.2)` 단락의 D-A6 항목을 함께
  /// 확인할 의무가 있다.
  ///
  /// Phase 10.2 review WR-01 정정 — context 미사용에 대한 명시적 정책 anchor.
  // ignore: unused_element_parameter
  Future<void> _handleForceSignOut(BuildContext context, WidgetRef ref) async {
    await ref.read(authRepositoryProvider).signOutAndResetOnboarding();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    final colorScheme = context.colorScheme;
    final typography = context.appTypography;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.devToolsSectionTitle, style: typography.titleLarge),
        Gap(spacing.sm),
        Text(
          l10n.devToolsSectionDescription,
          style: typography.bodyMedium.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        Gap(spacing.md),
        OutlinedButton(
          onPressed: () => _handleResetOnboarding(context, ref),
          child: Text(l10n.devToolsResetOnboarding),
        ),
        Gap(spacing.md),
        OutlinedButton(
          onPressed: () => _handleTriggerError(context, ref),
          style: OutlinedButton.styleFrom(foregroundColor: colorScheme.error),
          child: Text(l10n.devToolsTriggerError),
        ),
        Gap(spacing.md),
        OutlinedButton(
          onPressed: () => _handleTriggerAnalytics(context, ref),
          child: Text(l10n.devToolsTriggerAnalytics),
        ),
        Gap(spacing.md),
        // Phase 17 D-05 · UI-SPEC (T) — Analytics 다음 · 강제 로그아웃 앞.
        const _SendTestPushButton(),
        Gap(spacing.md),
        OutlinedButton(
          onPressed: () => _handleForceSignOut(context, ref),
          style: OutlinedButton.styleFrom(foregroundColor: colorScheme.error),
          child: Text(l10n.devToolsForceSignOut),
        ),
      ],
    );
  }
}

/// Dev Tools 「나에게 테스트 알림 보내기」 버튼 (Phase 17 D-05 · UI-SPEC (T)).
///
/// 탭하면 [TestPushClient.send] 로 내 계정의 모든 기기에 테스트 알림을
/// 요청하고 결과를 floating SnackBar 로 알린다. 요청 중에는 버튼을 비활성화해
/// 중복 탭을 막는다(라벨 · 크기 불변 · 서버 rate limit 과 짝).
class _SendTestPushButton extends ConsumerStatefulWidget {
  // 버튼 순서는 위젯 테스트(T-17-SEND-03 — 트리 순서)가 잠근다 (리뷰 IN-11).
  const _SendTestPushButton();

  @override
  ConsumerState<_SendTestPushButton> createState() =>
      _SendTestPushButtonState();
}

class _SendTestPushButtonState extends ConsumerState<_SendTestPushButton> {
  /// 요청 진행 중 여부 — true 면 버튼이 비활성이다.
  bool _sending = false;

  /// 테스트 알림을 요청하고 결과 SnackBar 를 띄운다 (UI-SPEC (T) · E7).
  ///
  /// 결과 5종: 성공 `devToolsSendTestPushDone(count)` · 기기 없음
  /// `devToolsSendTestPushNoDevice` · 게스트 거부
  /// `devToolsSendTestPushAnonymous`(리뷰 IN-22) · 운영 거부
  /// `devToolsSendTestPushDisabled` ·
  /// 그 밖 [showErrorSnackBar] (App Check 차단 = `errorAppCheckFailed`). 모두
  /// floating 이고, 연속 요청 시 직전 SnackBar 를 닫고 마지막 결과만 보인다.
  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      final outcome = await ref.read(testPushClientProvider).send();
      if (!mounted) return;
      final l10n = context.l10n;
      switch (outcome) {
        case TestPushSent(:final count):
          _showResult(l10n.devToolsSendTestPushDone(count));
        case TestPushNoDevice():
          _showResult(l10n.devToolsSendTestPushNoDevice);
        case TestPushAnonymous():
          _showResult(l10n.devToolsSendTestPushAnonymous);
        case TestPushDisabled():
          _showResult(l10n.devToolsSendTestPushDisabled);
        case TestPushFailed(:final exception):
          showErrorSnackBar(
            context,
            exception,
            behavior: SnackBarBehavior.floating,
          );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// 결과 [message] 를 floating SnackBar 로 띄운다 (직전 SnackBar 는 닫는다).
  void _showResult(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: _sending ? null : _send,
      child: Text(context.l10n.devToolsSendTestPush),
    );
  }
}

/// 환경 정보를 아이콘, 라벨, 값으로 표시하는 카드.
///
/// 카드 전체를 [Semantics] 컨테이너로 묶어 스크린 리더에 단일 노드로
/// 노출한다. [semanticLabel] 미지정 시 `"$label: $value"` 형태의
/// fallback 라벨이 자동 적용된다 (예: `"Flavor: DEV"`).
///
/// [status] 가 [_EnvStatus.ok] 또는 [_EnvStatus.warn] 인 경우 값을
/// chip 컨테이너로 감싸 토큰 계약 (배경/전경 페어링) 을 강제한다.
/// 기본값([_EnvStatus.none]) 은 일반 텍스트 스타일로 값을 표시한다.
class _EnvironmentCard extends StatelessWidget {
  const _EnvironmentCard({
    required this.icon,
    required this.label,
    this.value = '',
    this.child,
    this.status = _EnvStatus.none,
    this.semanticLabel,
  });

  final IconData icon;
  final String label;
  final String value;

  /// value 대신 커스텀 위젯을 표시할 때 사용한다 (예: 이미지 썸네일).
  final Widget? child;

  /// 값(value) 의 시맨틱 상태. chip 패턴 렌더 여부를 결정한다.
  final _EnvStatus status;

  /// Semantics 라벨. null이면 `"$label: $value"` fallback이 자동 적용된다.
  ///
  /// Firebase 카드처럼 상태에 따라 라벨이 달라지는 경우 호출부에서
  /// l10n 기반 완성 문자열을 전달한다.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final spacing = context.appSpacing;
    final colors = context.appColors;
    final typography = context.appTypography;
    // semanticLabel 미지정 시 "$label: $value" fallback 자동 생성.
    final resolvedSemanticLabel =
        semanticLabel ?? '$label: ${child != null ? '' : value}';

    final Widget valueWidget;
    if (status == _EnvStatus.none) {
      valueWidget = Text(
        value,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        softWrap: true,
        style: typography.titleMedium,
      );
    } else {
      final bg = status == _EnvStatus.ok ? colors.success : colors.warning;
      final fg = status == _EnvStatus.ok ? colors.onSuccess : colors.onWarning;
      valueWidget = Container(
        padding: EdgeInsets.symmetric(
          horizontal: spacing.sm,
          vertical: spacing.xs,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(spacing.xs),
        ),
        child: Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          softWrap: true,
          style: typography.labelLarge.copyWith(color: fg),
        ),
      );
    }

    return Semantics(
      container: true,
      excludeSemantics: true,
      label: resolvedSemanticLabel,
      child: Card(
        child: Padding(
          padding: EdgeInsets.all(spacing.lg),
          child: Row(
            children: [
              Icon(
                icon,
                size: _kEnvCardIconSize,
                color: context.colorScheme.primary,
              ),
              Gap(spacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: typography.bodySmall.copyWith(
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Gap(spacing.xs),
                    child ?? valueWidget,
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
