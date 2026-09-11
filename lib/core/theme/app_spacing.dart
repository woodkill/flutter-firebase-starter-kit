import 'dart:ui';

import 'package:flutter/material.dart';

/// 4px 기반 간격 스케일을 제공하는 [ThemeExtension].
///
/// 7단계 간격(xs:4 ~ xxxl:48)을 정의한다.
/// [const] 생성자로 기본값을 제공하며, [copyWith]으로 커스터마이징 가능하다.
///
/// 사용 예:
/// ```dart
/// final spacing = context.appSpacing;
/// SizedBox(height: spacing.md); // 12.0
/// ```
class AppSpacing extends ThemeExtension<AppSpacing> {
  /// [AppSpacing] 인스턴스를 기본 4px 스케일로 생성한다.
  const AppSpacing({
    this.xs = 4.0,
    this.sm = 8.0,
    this.md = 12.0,
    this.lg = 16.0,
    this.xl = 24.0,
    this.xxl = 32.0,
    this.xxxl = 48.0,
  });

  /// 가장 작은 간격 (4px).
  final double xs;

  /// 작은 간격 (8px).
  final double sm;

  /// 중간 간격 (12px).
  final double md;

  /// 큰 간격 (16px).
  final double lg;

  /// 매우 큰 간격 (24px).
  final double xl;

  /// 특대 간격 (32px).
  final double xxl;

  /// 최대 간격 (48px).
  final double xxxl;

  @override
  AppSpacing copyWith({
    double? xs,
    double? sm,
    double? md,
    double? lg,
    double? xl,
    double? xxl,
    double? xxxl,
  }) {
    return AppSpacing(
      xs: xs ?? this.xs,
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      xl: xl ?? this.xl,
      xxl: xxl ?? this.xxl,
      xxxl: xxxl ?? this.xxxl,
    );
  }

  @override
  AppSpacing lerp(AppSpacing? other, double t) {
    if (other is! AppSpacing) return this;

    return AppSpacing(
      xs: lerpDouble(xs, other.xs, t) ?? xs,
      sm: lerpDouble(sm, other.sm, t) ?? sm,
      md: lerpDouble(md, other.md, t) ?? md,
      lg: lerpDouble(lg, other.lg, t) ?? lg,
      xl: lerpDouble(xl, other.xl, t) ?? xl,
      xxl: lerpDouble(xxl, other.xxl, t) ?? xxl,
      xxxl: lerpDouble(xxxl, other.xxxl, t) ?? xxxl,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSpacing &&
          other.xs == xs &&
          other.sm == sm &&
          other.md == md &&
          other.lg == lg &&
          other.xl == xl &&
          other.xxl == xxl &&
          other.xxxl == xxxl;

  @override
  int get hashCode => Object.hash(xs, sm, md, lg, xl, xxl, xxxl);
}
