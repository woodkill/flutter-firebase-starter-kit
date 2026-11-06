import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_theme.dart';

/// 앱 전용 컬러 토큰을 제공하는 [ThemeExtension].
///
/// 브랜드 원색 [brand] 와 [ColorScheme]에 포함되지 않는 앱 고유 시맨틱 컬러
/// 6종(success, warning, info 와 그 위 글자 색)을 정의한다. [fromBrightness]
/// 팩토리로 라이트/다크 모드별 컬러를 생성한다.
///
/// 사용 예:
/// ```dart
/// final colors = Theme.of(context).extension<AppColors>()!;
/// // 또는 ThemeX extension 사용:
/// final colors = context.appColors;
/// // 브랜드 hex 그대로가 필요한 곳(로고 · 지도 강조 등):
/// final brand = context.appColors.brand;
/// ```
class AppColors extends ThemeExtension<AppColors> with Diagnosticable {
  /// [AppColors] 인스턴스를 생성한다.
  const AppColors({
    required this.success,
    required this.warning,
    required this.info,
    required this.onSuccess,
    required this.onWarning,
    required this.onInfo,
    this.brand = AppTheme.seedColor,
  });

  /// [brightness]에 따라 라이트/다크 시맨틱 컬러를 생성한다.
  ///
  /// [brand] 를 넘기지 않으면 config `brandColor` 의 색([AppTheme.brandColor])을
  /// 넣는다. 넘긴 색은 불투명 [Color] 로 정규화한다 — [MaterialColor] 를 넘겨도
  /// `==` 가 런타임 타입에 흔들리지 않는다.
  factory AppColors.fromBrightness(Brightness brightness, {Color? brand}) {
    final AppColors semantic = switch (brightness) {
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
    return semantic.copyWith(
      brand: Color((brand ?? AppTheme.brandColor).toARGB32()),
    );
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

  /// 브랜드 원색 — config `brandColor` 의 hex 그대로다.
  ///
  /// [ColorScheme.primary] 와 달리 시드에서 다시 계산하지 않는다. 라이트 · 다크가
  /// 같은 값이고, 위에 올릴 글자 색 · 대비는 쓰는 쪽이 정한다.
  final Color brand;

  @override
  AppColors copyWith({
    Color? success,
    Color? warning,
    Color? info,
    Color? onSuccess,
    Color? onWarning,
    Color? onInfo,
    Color? brand,
  }) {
    return AppColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      info: info ?? this.info,
      onSuccess: onSuccess ?? this.onSuccess,
      onWarning: onWarning ?? this.onWarning,
      onInfo: onInfo ?? this.onInfo,
      brand: brand ?? this.brand,
    );
  }

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other is! AppColors) return this;

    return AppColors(
      success: Color.lerp(success, other.success, t) ?? success,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      info: Color.lerp(info, other.info, t) ?? info,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t) ?? onSuccess,
      onWarning: Color.lerp(onWarning, other.onWarning, t) ?? onWarning,
      onInfo: Color.lerp(onInfo, other.onInfo, t) ?? onInfo,
      brand: Color.lerp(brand, other.brand, t) ?? brand,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppColors &&
          other.success == success &&
          other.warning == warning &&
          other.info == info &&
          other.onSuccess == onSuccess &&
          other.onWarning == onWarning &&
          other.onInfo == onInfo &&
          other.brand == brand;

  @override
  int get hashCode =>
      Object.hash(success, warning, info, onSuccess, onWarning, onInfo, brand);

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(ColorProperty('success', success))
      ..add(ColorProperty('warning', warning))
      ..add(ColorProperty('info', info))
      ..add(ColorProperty('onSuccess', onSuccess))
      ..add(ColorProperty('onWarning', onWarning))
      ..add(ColorProperty('onInfo', onInfo))
      ..add(ColorProperty('brand', brand));
  }
}
