import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// 앱의 라이트/다크 [ThemeData]를 조립하는 유틸리티 클래스.
///
/// [seedColor]를 기반으로 [ColorScheme.fromSeed]를 사용하여 M3 팔레트를 생성하고,
/// [AppColors], [AppTypography], [AppSpacing] ThemeExtension을 등록한다.
/// [seedColor]를 변경하면 전체 팔레트가 교체된다.
abstract final class AppTheme {
  /// 앱 전체 테마의 시드 컬러.
  ///
  /// 이 값을 변경하면 [ColorScheme.fromSeed]를 통해 전체 팔레트가 교체된다.
  static const seedColor = Colors.deepPurple;

  /// 라이트 모드 [ThemeData]를 생성한다.
  ///
  /// [AppColors], [AppTypography], [AppSpacing] 3개 ThemeExtension을 포함한다.
  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(seedColor: seedColor);
    final base = ThemeData(colorScheme: colorScheme, useMaterial3: true);

    return base.copyWith(
      extensions: <ThemeExtension<dynamic>>[
        AppColors.fromBrightness(Brightness.light),
        AppTypography.fromTextTheme(_resolvedTextTheme(base)),
        const AppSpacing(),
      ],
    );
  }

  /// 다크 모드 [ThemeData]를 생성한다.
  ///
  /// [AppColors], [AppTypography], [AppSpacing] 3개 ThemeExtension을 포함한다.
  static ThemeData dark() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    );
    final base = ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      brightness: Brightness.dark,
    );

    return base.copyWith(
      extensions: <ThemeExtension<dynamic>>[
        AppColors.fromBrightness(Brightness.dark),
        AppTypography.fromTextTheme(_resolvedTextTheme(base)),
        const AppSpacing(),
      ],
    );
  }

  /// [ThemeData.textTheme]에서 fontSize가 resolve되지 않는 문제를 우회한다.
  ///
  /// Flutter의 M3 TextTheme은 fontSize를 [Typography] 레이어에서 merge하므로,
  /// [ThemeData.textTheme]의 개별 TextStyle에는 fontSize가 null일 수 있다.
  /// geometry TextTheme과 merge하여 완전한 TextStyle을 반환한다.
  static TextTheme _resolvedTextTheme(ThemeData base) {
    final geometry = Typography.material2021().englishLike;
    return geometry.merge(base.textTheme);
  }
}
