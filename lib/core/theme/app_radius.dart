import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 모서리 둥글기 토큰을 제공하는 [ThemeExtension].
///
/// 다섯 단계 이름(xs ~ xl)은 간격 토큰 `AppSpacing` 과 같은 꼴이고, 값은
/// Material 3 모양 단계(`md.sys.shape.corner.*` — extraSmall 4 · small 8 ·
/// medium 12 · large 16 · extraLarge 28)와 같다.
/// 완전히 둥근 모양(알약 꼴)은 토큰 대신 [StadiumBorder] 를 쓴다.
/// 간격 토큰과 따로 두므로 `AppSpacing` 을 바꿔도 모서리는 그대로다.
/// [const] 생성자로 기본값을 제공하며, [copyWith] 으로 커스터마이징 가능하다.
///
/// 사용 예:
/// ```dart
/// final radius = context.appRadius;
/// BoxDecoration(borderRadius: BorderRadius.circular(radius.sm)); // 8.0
/// ```
class AppRadius extends ThemeExtension<AppRadius> with Diagnosticable {
  /// [AppRadius] 인스턴스를 Material 3 모양 단계 값으로 생성한다.
  const AppRadius({
    this.xs = 4.0,
    this.sm = 8.0,
    this.md = 12.0,
    this.lg = 16.0,
    this.xl = 28.0,
  });

  /// 가장 작은 둥글기 (4px · M3 extraSmall) — 약관 동의의 필수 · 선택 배지.
  final double xs;

  /// 작은 둥글기 (8px · M3 small) — 오류 배너 · 메일 확인 안내 상자.
  final double sm;

  /// 중간 둥글기 (12px · M3 medium) — 킷 화면은 쓰지 않는다.
  final double md;

  /// 큰 둥글기 (16px · M3 large) — 킷 화면은 쓰지 않는다.
  final double lg;

  /// 매우 큰 둥글기 (28px · M3 extraLarge) — 아래 시트의 위 모서리.
  final double xl;

  @override
  AppRadius copyWith({
    double? xs,
    double? sm,
    double? md,
    double? lg,
    double? xl,
  }) {
    return AppRadius(
      xs: xs ?? this.xs,
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      xl: xl ?? this.xl,
    );
  }

  @override
  AppRadius lerp(AppRadius? other, double t) {
    if (other is! AppRadius) return this;

    return AppRadius(
      xs: lerpDouble(xs, other.xs, t) ?? xs,
      sm: lerpDouble(sm, other.sm, t) ?? sm,
      md: lerpDouble(md, other.md, t) ?? md,
      lg: lerpDouble(lg, other.lg, t) ?? lg,
      xl: lerpDouble(xl, other.xl, t) ?? xl,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppRadius &&
          other.xs == xs &&
          other.sm == sm &&
          other.md == md &&
          other.lg == lg &&
          other.xl == xl;

  @override
  int get hashCode => Object.hash(xs, sm, md, lg, xl);

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DoubleProperty('xs', xs))
      ..add(DoubleProperty('sm', sm))
      ..add(DoubleProperty('md', md))
      ..add(DoubleProperty('lg', lg))
      ..add(DoubleProperty('xl', xl));
  }
}
