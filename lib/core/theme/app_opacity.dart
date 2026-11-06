import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 투명도 토큰을 제공하는 [ThemeExtension].
///
/// Material 3 상태 레이어 값(hover · focus · pressed · dragged)과 비활성 값
/// (disabled · disabledContainer), 킷 화면의 가림막 · 비활성 표시 값
/// (scrim · inactive)을 한 곳에 모은다.
/// 킷 화면이 쓰는 값은 [scrim] · [inactive] 둘이고, 나머지는 직접 만드는
/// 위젯에 쓰는 값이다.
/// [const] 생성자로 기본값을 제공하며, [copyWith] 으로 커스터마이징 가능하다.
///
/// 사용 예:
/// ```dart
/// final opacity = context.appOpacity;
/// ColoredBox(color: colorScheme.scrim.withValues(alpha: opacity.scrim));
/// ```
class AppOpacity extends ThemeExtension<AppOpacity> with Diagnosticable {
  /// [AppOpacity] 인스턴스를 기본값으로 생성한다.
  const AppOpacity({
    this.hover = 0.08,
    this.focus = 0.1,
    this.pressed = 0.1,
    this.dragged = 0.16,
    this.disabled = 0.38,
    this.disabledContainer = 0.12,
    this.scrim = 0.32,
    this.inactive = 0.3,
  });

  /// 마우스를 올린 상태 레이어 (0.08 · `md.sys.state.hover.state-layer-opacity`).
  final double hover;

  /// 포커스 상태 레이어 (0.1 · `md.sys.state.focus.state-layer-opacity`).
  final double focus;

  /// 누르는 중 상태 레이어 (0.1 · `md.sys.state.pressed.state-layer-opacity`).
  final double pressed;

  /// 끄는 중 상태 레이어 (0.16 · `md.sys.state.dragged.state-layer-opacity`).
  final double dragged;

  /// 비활성 글자 · 아이콘 (0.38 · Material 3 컴포넌트 토큰 `*.disabled.*.opacity`).
  final double disabled;

  /// 비활성 바탕 · 외곽선 (0.12 · Material 3 컴포넌트 토큰의 disabled container ·
  /// outline 값).
  final double disabledContainer;

  /// 킷 가림막 (0.32) — 로그인 진행 오버레이가 [ColorScheme.scrim] 위에 얹는다.
  ///
  /// 이 값을 쓰던 자리의 주석은 Material 3 scrim 값이라고 적었지만, Flutter SDK
  /// 토큰 데이터에서 출처를 찾지 못했다. Flutter 기본 가림막은 `Colors.black54`
  /// 다.
  final double scrim;

  /// 킷 비활성 표시 (0.3) — 온보딩에서 현재 페이지가 아닌 점.
  ///
  /// Material 3 상태 값 목록에 없는 킷 값이다.
  final double inactive;

  @override
  AppOpacity copyWith({
    double? hover,
    double? focus,
    double? pressed,
    double? dragged,
    double? disabled,
    double? disabledContainer,
    double? scrim,
    double? inactive,
  }) {
    return AppOpacity(
      hover: hover ?? this.hover,
      focus: focus ?? this.focus,
      pressed: pressed ?? this.pressed,
      dragged: dragged ?? this.dragged,
      disabled: disabled ?? this.disabled,
      disabledContainer: disabledContainer ?? this.disabledContainer,
      scrim: scrim ?? this.scrim,
      inactive: inactive ?? this.inactive,
    );
  }

  @override
  AppOpacity lerp(AppOpacity? other, double t) {
    if (other is! AppOpacity) return this;

    return AppOpacity(
      hover: lerpDouble(hover, other.hover, t) ?? hover,
      focus: lerpDouble(focus, other.focus, t) ?? focus,
      pressed: lerpDouble(pressed, other.pressed, t) ?? pressed,
      dragged: lerpDouble(dragged, other.dragged, t) ?? dragged,
      disabled: lerpDouble(disabled, other.disabled, t) ?? disabled,
      disabledContainer:
          lerpDouble(disabledContainer, other.disabledContainer, t) ??
          disabledContainer,
      scrim: lerpDouble(scrim, other.scrim, t) ?? scrim,
      inactive: lerpDouble(inactive, other.inactive, t) ?? inactive,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppOpacity &&
          other.hover == hover &&
          other.focus == focus &&
          other.pressed == pressed &&
          other.dragged == dragged &&
          other.disabled == disabled &&
          other.disabledContainer == disabledContainer &&
          other.scrim == scrim &&
          other.inactive == inactive;

  @override
  int get hashCode => Object.hash(
    hover,
    focus,
    pressed,
    dragged,
    disabled,
    disabledContainer,
    scrim,
    inactive,
  );

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DoubleProperty('hover', hover))
      ..add(DoubleProperty('focus', focus))
      ..add(DoubleProperty('pressed', pressed))
      ..add(DoubleProperty('dragged', dragged))
      ..add(DoubleProperty('disabled', disabled))
      ..add(DoubleProperty('disabledContainer', disabledContainer))
      ..add(DoubleProperty('scrim', scrim))
      ..add(DoubleProperty('inactive', inactive));
  }
}
