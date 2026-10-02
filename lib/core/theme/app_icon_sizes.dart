import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 아이콘 크기 토큰을 제공하는 [ThemeExtension] (Phase 17 리뷰 IN-10).
///
/// 위젯에 아이콘 크기 숫자 리터럴을 쓰지 않도록 한 곳에 모은다. 값은 쓰는 곳이
/// 있는 것만 둔다 — 지금은 [sm] 1단계다. 기본 아이콘 크기(24)는
/// [IconThemeData] 가 이미 정하므로 토큰을 두지 않는다(`size` 생략).
/// [const] 생성자로 기본값을 제공하며, [copyWith] 으로 커스터마이징 가능하다.
///
/// 사용 예:
/// ```dart
/// final iconSizes = context.appIconSizes;
/// Icon(Icons.error_outline, size: iconSizes.sm); // 20.0
/// ```
class AppIconSizes extends ThemeExtension<AppIconSizes> with Diagnosticable {
  /// [AppIconSizes] 인스턴스를 기본값으로 생성한다.
  const AppIconSizes({this.sm = 20.0});

  /// 작은 아이콘 (20px) — 본문 줄과 나란히 놓이는 인라인 아이콘(오류 배너 등).
  final double sm;

  @override
  AppIconSizes copyWith({double? sm}) {
    return AppIconSizes(sm: sm ?? this.sm);
  }

  @override
  AppIconSizes lerp(AppIconSizes? other, double t) {
    if (other is! AppIconSizes) return this;

    return AppIconSizes(sm: lerpDouble(sm, other.sm, t) ?? sm);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AppIconSizes && other.sm == sm;

  @override
  int get hashCode => sm.hashCode;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DoubleProperty('sm', sm));
  }
}
