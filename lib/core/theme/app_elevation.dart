import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Material 3 elevation 단계 토큰을 제공하는 [ThemeExtension].
///
/// Material 3 시스템 elevation 6단계(level0 ~ level5)를 한 곳에 모은다.
/// 킷 화면은 이 값을 쓰지 않는다 — 직접 만드는 위젯에 쓰는 Material 3
/// 표준값이다. 카드 · 앱 바 · 다이얼로그 같은 컴포넌트의 기본 elevation 은
/// 각 위젯과 컴포넌트 테마가 갖는다.
/// [const] 생성자로 기본값을 제공하며, [copyWith] 으로 커스터마이징 가능하다.
///
/// 사용 예:
/// ```dart
/// final elevation = context.appElevation;
/// Material(elevation: elevation.level1, child: child);
/// ```
class AppElevation extends ThemeExtension<AppElevation> with Diagnosticable {
  /// [AppElevation] 인스턴스를 기본값으로 생성한다.
  const AppElevation({
    this.level0 = 0,
    this.level1 = 1,
    this.level2 = 3,
    this.level3 = 6,
    this.level4 = 8,
    this.level5 = 12,
  });

  /// 첫 번째 단계 — 그림자 없음 (0 · `md.sys.elevation.level0`).
  final double level0;

  /// 두 번째 단계 (1 · `md.sys.elevation.level1`).
  final double level1;

  /// 세 번째 단계 (3 · `md.sys.elevation.level2`).
  final double level2;

  /// 네 번째 단계 (6 · `md.sys.elevation.level3`).
  final double level3;

  /// 다섯 번째 단계 (8 · `md.sys.elevation.level4`).
  final double level4;

  /// 여섯 번째 단계 (12 · `md.sys.elevation.level5`).
  final double level5;

  @override
  AppElevation copyWith({
    double? level0,
    double? level1,
    double? level2,
    double? level3,
    double? level4,
    double? level5,
  }) {
    return AppElevation(
      level0: level0 ?? this.level0,
      level1: level1 ?? this.level1,
      level2: level2 ?? this.level2,
      level3: level3 ?? this.level3,
      level4: level4 ?? this.level4,
      level5: level5 ?? this.level5,
    );
  }

  @override
  AppElevation lerp(AppElevation? other, double t) {
    if (other is! AppElevation) return this;

    return AppElevation(
      level0: lerpDouble(level0, other.level0, t) ?? level0,
      level1: lerpDouble(level1, other.level1, t) ?? level1,
      level2: lerpDouble(level2, other.level2, t) ?? level2,
      level3: lerpDouble(level3, other.level3, t) ?? level3,
      level4: lerpDouble(level4, other.level4, t) ?? level4,
      level5: lerpDouble(level5, other.level5, t) ?? level5,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppElevation &&
          other.level0 == level0 &&
          other.level1 == level1 &&
          other.level2 == level2 &&
          other.level3 == level3 &&
          other.level4 == level4 &&
          other.level5 == level5;

  @override
  int get hashCode =>
      Object.hash(level0, level1, level2, level3, level4, level5);

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DoubleProperty('level0', level0))
      ..add(DoubleProperty('level1', level1))
      ..add(DoubleProperty('level2', level2))
      ..add(DoubleProperty('level3', level3))
      ..add(DoubleProperty('level4', level4))
      ..add(DoubleProperty('level5', level5));
  }
}
