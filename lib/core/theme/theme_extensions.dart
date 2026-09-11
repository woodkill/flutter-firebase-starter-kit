import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// [BuildContext]에서 디자인 토큰에 편리하게 접근하기 위한 확장.
///
/// [Theme.of(context).extension<T>()]를 매번 호출하는 대신,
/// `context.appColors`, `context.appTypography` 등으로 간결하게 접근한다.
///
/// **타이포그래피 접근 경로:** [appTypography] 와 [textTheme] 는 동일한 값을
/// 돌려주며(override 미등록 기준), 앱 코드는 [appTypography] 를 권장 경로로
/// 사용한다 — 사용자가 `AppTypography` extension 으로 부분 override 한 경우까지
/// 반영하는 유일한 경로이기 때문이다.
///
/// 세 토큰 getter 는 extension 이 등록되지 않은 테마에서도 테마 기본값으로
/// 폴백하므로, 사용자 자체 [ThemeData] 나 맨몸 `MaterialApp()` 에서도
/// 크래시하지 않는다.
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

  /// 현재 테마의 타이포그래피 토큰을 반환한다.
  ///
  /// 로케일별 기하가 적용된 [ThemeData.textTheme] 을 밑바탕으로, 등록된
  /// [AppTypography] extension 을 override 로 얹어 합성한다. 따라서
  /// `context.appTypography.bodyMedium` 과 `Theme.of(context).textTheme.bodyMedium`
  /// 은 항상 같은 값이며(override 미등록 기준), ko/ja 로케일의 dense
  /// 기하(`textBaseline: ideographic`)도 그대로 반영된다.
  ///
  /// extension 이 등록되지 않은 테마(사용자 자체 [ThemeData], 위젯 테스트의
  /// 맨몸 `MaterialApp()` 등)에서도 테마 기본값으로 동작한다.
  AppTypography get appTypography {
    final theme = Theme.of(this);
    return AppTypography.fromTextTheme(
      theme.textTheme,
    ).merge(theme.extension<AppTypography>());
  }

  /// 현재 테마의 [AppSpacing] ThemeExtension을 반환한다.
  AppSpacing get appSpacing => Theme.of(this).extension<AppSpacing>()!;

  /// 현재 테마의 [ColorScheme]을 반환한다.
  ColorScheme get colorScheme => Theme.of(this).colorScheme;

  /// 현재 테마의 [TextTheme]을 반환한다.
  ///
  /// [appTypography] 와 동일한 값을 돌려주지만, `AppTypography` extension
  /// override 는 반영하지 않는다 — 앱 코드는 [appTypography] 를 쓴다.
  TextTheme get textTheme => Theme.of(this).textTheme;
}
