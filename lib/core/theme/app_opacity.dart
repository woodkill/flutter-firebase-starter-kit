import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 투명도 토큰을 제공하는 [ThemeExtension].
///
/// Material 3 상태 레이어 값(hover · focus · pressed · dragged)과 비활성 값
/// (disabled · disabledContainer), 킷 화면의 가림막 · 비활성 표시 값
/// (scrim · inactive), 킷 흐림 세 단계(veilSubtle · veilMedium · veilStrong)를
/// 한 곳에 모은다.
/// 킷 화면이 쓰는 값은 [scrim] · [inactive] 둘이고, 나머지는 직접 만드는
/// 위젯에 쓰는 값이다.
/// [const] 생성자로 기본값을 제공하며, [copyWith] 으로 커스터마이징 가능하다.
///
/// 흐림(veil)은 콘텐츠를 보이게 둔 채 뒤로 물릴 때 흰색 · 검정을 섞는 비율
/// (알파 하나)이다. 색은 쓰는 쪽이 [ColorScheme] 역할에서 고른다 — 흰색은 밝은
/// 테마의 [ColorScheme.surfaceContainerLowest] 이고, 검정은 [ColorScheme.scrim]
/// 이다. `ColorScheme.fromSeed` 에서 surfaceContainerLowest 는 밝은 테마 톤
/// 100(흰색) · 어두운 테마 톤 4 이하(거의 검정)라 같은 식이 두 테마에서 바탕
/// 쪽으로 물리기가 되고, scrim 은 두 테마 모두 톤 0 이다. [scrim] 은 모달 뒤를
/// 막는 가림막 한 값이고, 흐림은 콘텐츠를 보이게 둔 채 물리는 세 단계다.
/// Material 3 · Flutter SDK 토큰 데이터에 없는 킷 값이고, 킷 화면은 쓰지 않는다.
///
/// 사용 예:
/// ```dart
/// final opacity = context.appOpacity;
/// ColoredBox(color: colorScheme.scrim.withValues(alpha: opacity.scrim));
/// // 흐림 — 역할 색에 흐림 값을 얹는다(흰색 쪽).
/// ColoredBox(
///   color: colorScheme.surfaceContainerLowest.withValues(
///     alpha: opacity.veilMedium,
///   ),
/// );
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
    this.veilSubtle = 0.2,
    this.veilMedium = 0.4,
    this.veilStrong = 0.6,
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

  /// 킷 흐림 옅게 (0.2) — 정의는 클래스 문서 참고.
  final double veilSubtle;

  /// 킷 흐림 보통 (0.4) — 정의는 클래스 문서 참고.
  final double veilMedium;

  /// 킷 흐림 짙게 (0.6) — 정의는 클래스 문서 참고.
  final double veilStrong;

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
    double? veilSubtle,
    double? veilMedium,
    double? veilStrong,
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
      veilSubtle: veilSubtle ?? this.veilSubtle,
      veilMedium: veilMedium ?? this.veilMedium,
      veilStrong: veilStrong ?? this.veilStrong,
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
      veilSubtle: lerpDouble(veilSubtle, other.veilSubtle, t) ?? veilSubtle,
      veilMedium: lerpDouble(veilMedium, other.veilMedium, t) ?? veilMedium,
      veilStrong: lerpDouble(veilStrong, other.veilStrong, t) ?? veilStrong,
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
          other.inactive == inactive &&
          other.veilSubtle == veilSubtle &&
          other.veilMedium == veilMedium &&
          other.veilStrong == veilStrong;

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
    veilSubtle,
    veilMedium,
    veilStrong,
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
      ..add(DoubleProperty('inactive', inactive))
      ..add(DoubleProperty('veilSubtle', veilSubtle))
      ..add(DoubleProperty('veilMedium', veilMedium))
      ..add(DoubleProperty('veilStrong', veilStrong));
  }
}
