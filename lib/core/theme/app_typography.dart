import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Material 3 [TextTheme]을 래핑하는 [ThemeExtension].
///
/// [fromTextTheme] 팩토리로 M3 TextTheme의 모든 스타일을 앱 디자인 토큰으로
/// 변환한다. 시스템 폰트를 기본 사용하며, 커스텀 font family는 없다.
///
/// 사용 예:
/// ```dart
/// final typography = context.appTypography;
/// Text('제목', style: typography.headlineLarge);
/// ```
class AppTypography extends ThemeExtension<AppTypography> with Diagnosticable {
  /// [AppTypography] 인스턴스를 생성한다.
  const AppTypography({
    required this.displayLarge,
    required this.displayMedium,
    required this.displaySmall,
    required this.headlineLarge,
    required this.headlineMedium,
    required this.headlineSmall,
    required this.titleLarge,
    required this.titleMedium,
    required this.titleSmall,
    required this.bodyLarge,
    required this.bodyMedium,
    required this.bodySmall,
    required this.labelLarge,
    required this.labelMedium,
    required this.labelSmall,
  });

  /// [TextTheme]의 각 스타일을 [AppTypography] 필드에 매핑한다.
  ///
  /// [TextTheme]의 스타일이 null인 경우 빈 [TextStyle]을 기본값으로 사용한다.
  factory AppTypography.fromTextTheme(TextTheme textTheme) {
    return AppTypography(
      displayLarge: textTheme.displayLarge ?? const TextStyle(),
      displayMedium: textTheme.displayMedium ?? const TextStyle(),
      displaySmall: textTheme.displaySmall ?? const TextStyle(),
      headlineLarge: textTheme.headlineLarge ?? const TextStyle(),
      headlineMedium: textTheme.headlineMedium ?? const TextStyle(),
      headlineSmall: textTheme.headlineSmall ?? const TextStyle(),
      titleLarge: textTheme.titleLarge ?? const TextStyle(),
      titleMedium: textTheme.titleMedium ?? const TextStyle(),
      titleSmall: textTheme.titleSmall ?? const TextStyle(),
      bodyLarge: textTheme.bodyLarge ?? const TextStyle(),
      bodyMedium: textTheme.bodyMedium ?? const TextStyle(),
      bodySmall: textTheme.bodySmall ?? const TextStyle(),
      labelLarge: textTheme.labelLarge ?? const TextStyle(),
      labelMedium: textTheme.labelMedium ?? const TextStyle(),
      labelSmall: textTheme.labelSmall ?? const TextStyle(),
    );
  }

  /// override 가 없는 빈 [AppTypography].
  ///
  /// 모든 필드가 빈 [TextStyle] 이라 [merge] 시 아무 속성도 덮어쓰지
  /// 않는다. `AppTheme` 이 등록하는 기본 override 레이어로, 스타터킷
  /// 사용자가 직접 등록하기 전까지는 테마 기본 타이포그래피를 그대로
  /// 따른다 (로케일별 기하 desync 방지).
  static const AppTypography empty = AppTypography(
    displayLarge: TextStyle(),
    displayMedium: TextStyle(),
    displaySmall: TextStyle(),
    headlineLarge: TextStyle(),
    headlineMedium: TextStyle(),
    headlineSmall: TextStyle(),
    titleLarge: TextStyle(),
    titleMedium: TextStyle(),
    titleSmall: TextStyle(),
    bodyLarge: TextStyle(),
    bodyMedium: TextStyle(),
    bodySmall: TextStyle(),
    labelLarge: TextStyle(),
    labelMedium: TextStyle(),
    labelSmall: TextStyle(),
  );

  /// Display large 텍스트 스타일.
  final TextStyle displayLarge;

  /// Display medium 텍스트 스타일.
  final TextStyle displayMedium;

  /// Display small 텍스트 스타일.
  final TextStyle displaySmall;

  /// Headline large 텍스트 스타일.
  final TextStyle headlineLarge;

  /// Headline medium 텍스트 스타일.
  final TextStyle headlineMedium;

  /// Headline small 텍스트 스타일.
  final TextStyle headlineSmall;

  /// Title large 텍스트 스타일.
  final TextStyle titleLarge;

  /// Title medium 텍스트 스타일.
  final TextStyle titleMedium;

  /// Title small 텍스트 스타일.
  final TextStyle titleSmall;

  /// Body large 텍스트 스타일.
  final TextStyle bodyLarge;

  /// Body medium 텍스트 스타일.
  final TextStyle bodyMedium;

  /// Body small 텍스트 스타일.
  final TextStyle bodySmall;

  /// Label large 텍스트 스타일.
  final TextStyle labelLarge;

  /// Label medium 텍스트 스타일.
  final TextStyle labelMedium;

  /// Label small 텍스트 스타일.
  final TextStyle labelSmall;

  /// [other] 의 non-null 스타일 속성을 이 인스턴스 위에 덮어쓴 결과를 반환한다.
  ///
  /// 각 필드는 [TextStyle.merge] 로 합성되므로, [other] 가 지정하지 않은
  /// 속성은 이 인스턴스의 값이 유지된다. [other] 가 null 이면 자기 자신을
  /// 그대로 반환한다 (override 미등록 테마 방어).
  AppTypography merge(AppTypography? other) {
    if (other == null) return this;

    return AppTypography(
      displayLarge: displayLarge.merge(other.displayLarge),
      displayMedium: displayMedium.merge(other.displayMedium),
      displaySmall: displaySmall.merge(other.displaySmall),
      headlineLarge: headlineLarge.merge(other.headlineLarge),
      headlineMedium: headlineMedium.merge(other.headlineMedium),
      headlineSmall: headlineSmall.merge(other.headlineSmall),
      titleLarge: titleLarge.merge(other.titleLarge),
      titleMedium: titleMedium.merge(other.titleMedium),
      titleSmall: titleSmall.merge(other.titleSmall),
      bodyLarge: bodyLarge.merge(other.bodyLarge),
      bodyMedium: bodyMedium.merge(other.bodyMedium),
      bodySmall: bodySmall.merge(other.bodySmall),
      labelLarge: labelLarge.merge(other.labelLarge),
      labelMedium: labelMedium.merge(other.labelMedium),
      labelSmall: labelSmall.merge(other.labelSmall),
    );
  }

  @override
  AppTypography copyWith({
    TextStyle? displayLarge,
    TextStyle? displayMedium,
    TextStyle? displaySmall,
    TextStyle? headlineLarge,
    TextStyle? headlineMedium,
    TextStyle? headlineSmall,
    TextStyle? titleLarge,
    TextStyle? titleMedium,
    TextStyle? titleSmall,
    TextStyle? bodyLarge,
    TextStyle? bodyMedium,
    TextStyle? bodySmall,
    TextStyle? labelLarge,
    TextStyle? labelMedium,
    TextStyle? labelSmall,
  }) {
    return AppTypography(
      displayLarge: displayLarge ?? this.displayLarge,
      displayMedium: displayMedium ?? this.displayMedium,
      displaySmall: displaySmall ?? this.displaySmall,
      headlineLarge: headlineLarge ?? this.headlineLarge,
      headlineMedium: headlineMedium ?? this.headlineMedium,
      headlineSmall: headlineSmall ?? this.headlineSmall,
      titleLarge: titleLarge ?? this.titleLarge,
      titleMedium: titleMedium ?? this.titleMedium,
      titleSmall: titleSmall ?? this.titleSmall,
      bodyLarge: bodyLarge ?? this.bodyLarge,
      bodyMedium: bodyMedium ?? this.bodyMedium,
      bodySmall: bodySmall ?? this.bodySmall,
      labelLarge: labelLarge ?? this.labelLarge,
      labelMedium: labelMedium ?? this.labelMedium,
      labelSmall: labelSmall ?? this.labelSmall,
    );
  }

  @override
  AppTypography lerp(AppTypography? other, double t) {
    if (other is! AppTypography) return this;

    return AppTypography(
      displayLarge:
          TextStyle.lerp(displayLarge, other.displayLarge, t) ?? displayLarge,
      displayMedium:
          TextStyle.lerp(displayMedium, other.displayMedium, t) ??
          displayMedium,
      displaySmall:
          TextStyle.lerp(displaySmall, other.displaySmall, t) ?? displaySmall,
      headlineLarge:
          TextStyle.lerp(headlineLarge, other.headlineLarge, t) ??
          headlineLarge,
      headlineMedium:
          TextStyle.lerp(headlineMedium, other.headlineMedium, t) ??
          headlineMedium,
      headlineSmall:
          TextStyle.lerp(headlineSmall, other.headlineSmall, t) ??
          headlineSmall,
      titleLarge: TextStyle.lerp(titleLarge, other.titleLarge, t) ?? titleLarge,
      titleMedium:
          TextStyle.lerp(titleMedium, other.titleMedium, t) ?? titleMedium,
      titleSmall: TextStyle.lerp(titleSmall, other.titleSmall, t) ?? titleSmall,
      bodyLarge: TextStyle.lerp(bodyLarge, other.bodyLarge, t) ?? bodyLarge,
      bodyMedium: TextStyle.lerp(bodyMedium, other.bodyMedium, t) ?? bodyMedium,
      bodySmall: TextStyle.lerp(bodySmall, other.bodySmall, t) ?? bodySmall,
      labelLarge: TextStyle.lerp(labelLarge, other.labelLarge, t) ?? labelLarge,
      labelMedium:
          TextStyle.lerp(labelMedium, other.labelMedium, t) ?? labelMedium,
      labelSmall: TextStyle.lerp(labelSmall, other.labelSmall, t) ?? labelSmall,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppTypography &&
          other.displayLarge == displayLarge &&
          other.displayMedium == displayMedium &&
          other.displaySmall == displaySmall &&
          other.headlineLarge == headlineLarge &&
          other.headlineMedium == headlineMedium &&
          other.headlineSmall == headlineSmall &&
          other.titleLarge == titleLarge &&
          other.titleMedium == titleMedium &&
          other.titleSmall == titleSmall &&
          other.bodyLarge == bodyLarge &&
          other.bodyMedium == bodyMedium &&
          other.bodySmall == bodySmall &&
          other.labelLarge == labelLarge &&
          other.labelMedium == labelMedium &&
          other.labelSmall == labelSmall;

  @override
  int get hashCode => Object.hash(
    displayLarge,
    displayMedium,
    displaySmall,
    headlineLarge,
    headlineMedium,
    headlineSmall,
    titleLarge,
    titleMedium,
    titleSmall,
    bodyLarge,
    bodyMedium,
    bodySmall,
    labelLarge,
    labelMedium,
    labelSmall,
  );

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<TextStyle>('displayLarge', displayLarge))
      ..add(DiagnosticsProperty<TextStyle>('displayMedium', displayMedium))
      ..add(DiagnosticsProperty<TextStyle>('displaySmall', displaySmall))
      ..add(DiagnosticsProperty<TextStyle>('headlineLarge', headlineLarge))
      ..add(DiagnosticsProperty<TextStyle>('headlineMedium', headlineMedium))
      ..add(DiagnosticsProperty<TextStyle>('headlineSmall', headlineSmall))
      ..add(DiagnosticsProperty<TextStyle>('titleLarge', titleLarge))
      ..add(DiagnosticsProperty<TextStyle>('titleMedium', titleMedium))
      ..add(DiagnosticsProperty<TextStyle>('titleSmall', titleSmall))
      ..add(DiagnosticsProperty<TextStyle>('bodyLarge', bodyLarge))
      ..add(DiagnosticsProperty<TextStyle>('bodyMedium', bodyMedium))
      ..add(DiagnosticsProperty<TextStyle>('bodySmall', bodySmall))
      ..add(DiagnosticsProperty<TextStyle>('labelLarge', labelLarge))
      ..add(DiagnosticsProperty<TextStyle>('labelMedium', labelMedium))
      ..add(DiagnosticsProperty<TextStyle>('labelSmall', labelSmall));
  }
}
