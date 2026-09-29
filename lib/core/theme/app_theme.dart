import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// 앱의 라이트/다크 [ThemeData]를 조립하는 유틸리티 클래스.
///
/// [seedColor]를 기반으로 [ColorScheme.fromSeed]를 사용하여 M3 팔레트를 생성하고,
/// [AppColors], [AppTypography], [AppSpacing] ThemeExtension을 등록한다.
/// [seedColor]를 변경하면 전체 팔레트가 교체된다.
///
/// **타이포그래피 계약:** 등록되는 [AppTypography] 는 기하를 포함하지 않는
/// **override 레이어**([AppTypography.empty])다. 로케일별 기하(ko/ja 는
/// `ScriptCategory.dense` — `textBaseline: ideographic`)는 Flutter 가
/// `Theme.build` 에서 `ThemeData.localize` 로 적용하므로, 완전한 스타일은
/// 반드시 `context.appTypography` (또는 `Theme.of(context).textTheme`) 로 얻어야
/// 한다. 사용자는 `copyWith(extensions: [AppTypography(...)])` 로 이 레이어를
/// 채워 타이포그래피를 부분 override 할 수 있다.
abstract final class AppTheme {
  /// 앱 전체 테마의 기본 시드 컬러.
  ///
  /// 이 값을 변경하면 [ColorScheme.fromSeed]를 통해 전체 팔레트가 교체된다.
  ///
  /// **커스터마이징 포인트:** 소스를 고치지 않고도 [light]/[dark] 의
  /// `seedColor` 인자로 주입할 수 있다 — 예:
  /// `AppTheme.light(seedColor: Colors.teal)`.
  static const MaterialColor seedColor = Colors.deepPurple;

  /// 라이트 모드 [ThemeData]를 생성한다.
  ///
  /// [AppColors], [AppTypography], [AppSpacing] 3개 ThemeExtension을 포함한다.
  /// [seedColor]를 넘기면 그 시드로 M3 팔레트를 생성한다 (기본값
  /// [AppTheme.seedColor]).
  static ThemeData light({Color seedColor = AppTheme.seedColor}) {
    final colorScheme = ColorScheme.fromSeed(seedColor: seedColor);
    // useMaterial3 미지정 — Flutter 3.41 기준 기본값이 true 다.
    final base = ThemeData(colorScheme: colorScheme);

    return base.copyWith(
      extensions: <ThemeExtension<dynamic>>[
        AppColors.fromBrightness(Brightness.light),
        AppTypography.empty,
        const AppSpacing(),
      ],
    );
  }

  /// 다크 모드 [ThemeData]를 생성한다.
  ///
  /// [AppColors], [AppTypography], [AppSpacing] 3개 ThemeExtension을 포함한다.
  /// [seedColor]를 넘기면 그 시드로 M3 팔레트를 생성한다 (기본값
  /// [AppTheme.seedColor]). [light] 와 동일한 시드를 넘겨야 두 모드의
  /// 팔레트가 일관된다.
  static ThemeData dark({Color seedColor = AppTheme.seedColor}) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    );
    // brightness 미지정 — colorScheme 이 있으면 거기서 파생된다.
    final base = ThemeData(colorScheme: colorScheme);

    return base.copyWith(
      extensions: <ThemeExtension<dynamic>>[
        AppColors.fromBrightness(Brightness.dark),
        AppTypography.empty,
        const AppSpacing(),
      ],
    );
  }
}
