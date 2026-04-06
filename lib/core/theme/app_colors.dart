import 'package:flutter/material.dart';

/// 앱 전용 시맨틱 컬러 토큰을 제공하는 [ThemeExtension].
///
/// [ColorScheme]에 포함되지 않는 앱 고유 시맨틱 컬러(success, warning, info)를
/// 정의한다. [fromBrightness] 팩토리로 라이트/다크 모드별 컬러를 생성한다.
///
/// 사용 예:
/// ```dart
/// final colors = Theme.of(context).extension<AppColors>()!;
/// // 또는 ThemeX extension 사용:
/// final colors = context.appColors;
/// ```
class AppColors extends ThemeExtension<AppColors> {
  /// [AppColors] 인스턴스를 생성한다.
  const AppColors({
    required this.success,
    required this.warning,
    required this.info,
    required this.onSuccess,
    required this.onWarning,
    required this.onInfo,
  });

  /// [brightness]에 따라 라이트/다크 시맨틱 컬러를 생성한다.
  factory AppColors.fromBrightness(Brightness brightness) {
    return switch (brightness) {
      Brightness.light => const AppColors(
        success: Color(0xFF2E7D32),
        warning: Color(0xFFF57F17),
        info: Color(0xFF1565C0),
        onSuccess: Color(0xFFFFFFFF),
        onWarning: Color(0xFF000000),
        onInfo: Color(0xFFFFFFFF),
      ),
      Brightness.dark => const AppColors(
        success: Color(0xFF81C784),
        warning: Color(0xFFFFD54F),
        info: Color(0xFF64B5F6),
        onSuccess: Color(0xFF000000),
        onWarning: Color(0xFF000000),
        onInfo: Color(0xFF000000),
      ),
    };
  }

  /// 성공 상태를 나타내는 컬러.
  final Color success;

  /// 경고 상태를 나타내는 컬러.
  final Color warning;

  /// 정보 상태를 나타내는 컬러.
  final Color info;

  /// [success] 위에 표시되는 텍스트/아이콘 컬러.
  final Color onSuccess;

  /// [warning] 위에 표시되는 텍스트/아이콘 컬러.
  final Color onWarning;

  /// [info] 위에 표시되는 텍스트/아이콘 컬러.
  final Color onInfo;

  @override
  AppColors copyWith({
    Color? success,
    Color? warning,
    Color? info,
    Color? onSuccess,
    Color? onWarning,
    Color? onInfo,
  }) {
    return AppColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      info: info ?? this.info,
      onSuccess: onSuccess ?? this.onSuccess,
      onWarning: onWarning ?? this.onWarning,
      onInfo: onInfo ?? this.onInfo,
    );
  }

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other is! AppColors) return this;

    return AppColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      info: Color.lerp(info, other.info, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      onInfo: Color.lerp(onInfo, other.onInfo, t)!,
    );
  }
}
