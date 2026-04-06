import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// [BuildContext]에서 디자인 토큰에 편리하게 접근하기 위한 확장.
///
/// [Theme.of(context).extension<T>()]를 매번 호출하는 대신,
/// `context.appColors`, `context.appTypography` 등으로 간결하게 접근한다.
///
/// 사용 예:
/// ```dart
/// Widget build(BuildContext context) {
///   final colors = context.appColors;
///   final spacing = context.appSpacing;
///   return Container(
///     color: colors.success,
///     padding: EdgeInsets.all(spacing.md),
///   );
/// }
/// ```
extension ThemeX on BuildContext {
  /// 현재 테마의 [AppColors] ThemeExtension을 반환한다.
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;

  /// 현재 테마의 [AppTypography] ThemeExtension을 반환한다.
  AppTypography get appTypography =>
      Theme.of(this).extension<AppTypography>()!;

  /// 현재 테마의 [AppSpacing] ThemeExtension을 반환한다.
  AppSpacing get appSpacing =>
      Theme.of(this).extension<AppSpacing>()!;

  /// 현재 테마의 [ColorScheme]을 반환한다.
  ColorScheme get colorScheme => Theme.of(this).colorScheme;

  /// 현재 테마의 [TextTheme]을 반환한다.
  TextTheme get textTheme => Theme.of(this).textTheme;
}
