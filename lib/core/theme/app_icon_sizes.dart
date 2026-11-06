import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 아이콘 크기 토큰을 제공하는 [ThemeExtension] (Phase 17 리뷰 IN-10).
///
/// 위젯에 아이콘 크기 숫자 리터럴을 쓰지 않도록 한 곳에 모은다. 크기순
/// 6단계(xs 16 ~ xxl 64)다 — Material 3 에는 아이콘 크기 시스템 토큰이 없어
/// 단계는 킷이 정한다.
/// [md] 24 는 [IconThemeData] 기본 크기와 같은 값이다. [md] 를 바꿔도 `size` 를
/// 생략한 아이콘은 따라 바뀌지 않으므로, 테마 기본 크기까지 바꾸려면
/// `ThemeData.iconTheme` 를 바꾼다.
/// [const] 생성자로 기본값을 제공하며, [copyWith] 으로 커스터마이징 가능하다.
///
/// 사용 예:
/// ```dart
/// final iconSizes = context.appIconSizes;
/// Icon(Icons.error_outline, size: iconSizes.sm); // 20.0
/// ```
class AppIconSizes extends ThemeExtension<AppIconSizes> with Diagnosticable {
  /// [AppIconSizes] 인스턴스를 기본값으로 생성한다.
  const AppIconSizes({
    this.xs = 16.0,
    this.sm = 20.0,
    this.md = 24.0,
    this.lg = 32.0,
    this.xl = 48.0,
    this.xxl = 64.0,
  });

  /// 가장 작은 아이콘 (16px) — 안내 줄 앞 보조 아이콘(메일 확인 화면 등).
  final double xs;

  /// 작은 아이콘 (20px) — 본문 줄과 나란히 놓이는 인라인 아이콘(오류 · 완료 배너).
  final double sm;

  /// 중간 아이콘 (24px) — [IconThemeData] 기본 크기와 같은 값.
  final double md;

  /// 큰 아이콘 (32px) — 카드 앞 아이콘(데모 환경 카드 등).
  final double lg;

  /// 매우 큰 아이콘 (48px) — 화면 머리 아이콘(메일 확인 화면 등).
  final double xl;

  /// 특대 아이콘 (64px) — 빈 상태 · 오류 화면 아이콘(404 화면 등).
  final double xxl;

  @override
  AppIconSizes copyWith({
    double? xs,
    double? sm,
    double? md,
    double? lg,
    double? xl,
    double? xxl,
  }) {
    return AppIconSizes(
      xs: xs ?? this.xs,
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      xl: xl ?? this.xl,
      xxl: xxl ?? this.xxl,
    );
  }

  @override
  AppIconSizes lerp(AppIconSizes? other, double t) {
    if (other is! AppIconSizes) return this;

    return AppIconSizes(
      xs: lerpDouble(xs, other.xs, t) ?? xs,
      sm: lerpDouble(sm, other.sm, t) ?? sm,
      md: lerpDouble(md, other.md, t) ?? md,
      lg: lerpDouble(lg, other.lg, t) ?? lg,
      xl: lerpDouble(xl, other.xl, t) ?? xl,
      xxl: lerpDouble(xxl, other.xxl, t) ?? xxl,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppIconSizes &&
          other.xs == xs &&
          other.sm == sm &&
          other.md == md &&
          other.lg == lg &&
          other.xl == xl &&
          other.xxl == xxl;

  @override
  int get hashCode => Object.hash(xs, sm, md, lg, xl, xxl);

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DoubleProperty('xs', xs))
      ..add(DoubleProperty('sm', sm))
      ..add(DoubleProperty('md', md))
      ..add(DoubleProperty('lg', lg))
      ..add(DoubleProperty('xl', xl))
      ..add(DoubleProperty('xxl', xxl));
  }
}
