/// 앱 맨 바깥에서 Android 내비게이션 바와 상태 표시줄의 기본 값을 정한다.
///
/// **왜** — 앱은 화면을 시스템 바 뒤까지 펴고(edge-to-edge), 화면마다
/// 내비게이션 바 값을 따로 두지 않는다. 그래서 앱 맨 바깥 영역
/// ([AppSystemBarsRegion]) 하나가 내비게이션 바 값을 두지 않은 화면의
/// 내비게이션 바를 맡는다.
///
/// **세 필드를 늘 채운다** — 엔진은 null 필드를 건너뛰어 앞 화면이 건 값을 그대로
/// 둔다. 스플래시 화면이 내비게이션 바의 색 · 대비 강제 · 아이콘 밝기 세 필드를
/// 바꾸므로, 이 영역도 같은 세 필드를 모두 null 이 아닌 값으로 보내야 다음 화면이
/// 기본 값으로 돌아온다.
///
/// **Android 에서는 상태 표시줄 기본 값도 둔다** — 화면 맨 위에 다른 영역이 없는
/// 화면(AppBar 없는 화면)에서는 이 영역이 상태 표시줄 값까지 맡는다. 이 값에
/// 상태 표시줄 필드가 없으면 앱이 다시 앞에 올 때 엔진이 상태 표시줄 아이콘
/// 밝기를 지운 채 되살리지 않아, 밝은 바탕 위에 흰 아이콘이 남는다. AppBar ·
/// 화면 영역이 있는 화면은 그 영역의 상태 표시줄 값이 이긴다. iOS 는 상태 표시줄
/// 필드를 두지 않는다 — iOS 엔진은 상태 표시줄 밝기가 null 이면 아무것도 하지
/// 않아 OS 기본 동작이 남는다.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 내비게이션 바 막 색 · 아이콘 밝기를 정할 기준 밝기를 돌려준다.
///
/// OS 밝기 설정을 따른다 — 막 색과 아이콘이 같은 기준을 본다.
Brightness resolveNavigationBarBrightness(BuildContext context) =>
    MediaQuery.platformBrightnessOf(context);

/// 기기가 제스처 내비게이션을 쓰는지 판별한다.
///
/// 화면 왼쪽 시스템 제스처 영역([MediaQuery.systemGestureInsetsOf] 의 `left`)이
/// 0 보다 크면 제스처 내비게이션이다 — 제스처 내비게이션에서만 화면 옆에 뒤로
/// 가기 제스처 영역이 생기고, 3버튼 내비게이션에서는 0 이다.
bool usesGestureNavigation(BuildContext context) =>
    MediaQuery.systemGestureInsetsOf(context).left > 0;

/// [brightness] 에 맞는 내비게이션 바 기본 값을 만든다.
///
/// 내비게이션 바의 색 · 대비 강제 · 아이콘 밝기 세 필드만 담는다. 아이콘은
/// 어두운 기준에서 밝게, 밝은 기준에서 어둡게 둔다.
///
/// [isGestureNavigation] 이 true 면 색은 투명이다 — Android 15 이상처럼 제스처
/// 띠 아래에 막을 깔지 않는다. 색을 null 로 두지 않는 까닭은 파일 머리의 「세
/// 필드를 늘 채운다」 다. 대비 강제 · 아이콘 밝기는 내비게이션 방식과 무관하다.
SystemUiOverlayStyle buildDefaultNavigationBarStyle(
  Brightness brightness, {
  required bool isGestureNavigation,
}) {
  final isDark = brightness == Brightness.dark;
  final Color barColor = switch ((isGestureNavigation, isDark)) {
    // 제스처 내비게이션 — 막 없이 투명이다.
    (true, _) => const Color(0x00000000),
    // Android 15 이상 OS 가 그리는 3버튼 다크 막(검정 약 80%)에 맞춘 값이다.
    (false, true) => const Color(0xCC000000),
    // androidx activity `EdgeToEdge` 의 라이트 막 상수(DefaultLightScrim)다.
    (false, false) => const Color(0xE6FFFFFF),
  };
  return SystemUiOverlayStyle(
    systemNavigationBarColor: barColor,
    systemNavigationBarContrastEnforced: true,
    systemNavigationBarIconBrightness: isDark
        ? Brightness.light
        : Brightness.dark,
  );
}

/// [surfaceBrightness] 에 맞는 Android 상태 표시줄 기본 값을 만든다.
///
/// 상태 표시줄 바탕 색 · 아이콘 밝기 두 필드만 담는다. 바탕은 투명이고, 아이콘은
/// 어두운 바탕에서 밝게, 밝은 바탕에서 어둡게 둔다. `statusBarBrightness` 는 iOS
/// 용 필드라 담지 않는다.
SystemUiOverlayStyle buildDefaultStatusBarStyle(Brightness surfaceBrightness) {
  final isDark = surfaceBrightness == Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: const Color(0x00000000),
    statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
  );
}

/// 앱 맨 바깥에서 내비게이션 바 · 상태 표시줄 기본 값을 알리는 영역.
///
/// [resolveNavigationBarBrightness] 가 돌려준 밝기와 [usesGestureNavigation] 의
/// 판별로 [buildDefaultNavigationBarStyle] 이 만든 값을 [AnnotatedRegion] 하나로
/// 알린다. Android 에서는 [buildDefaultStatusBarStyle] 이 만든 상태 표시줄
/// 필드를 더한다 — 상태 표시줄 기준은 OS 밝기가 아니라 앱 바탕
/// (`colorScheme.surface`) 밝기다. 투명한 상태 표시줄 뒤로 보이는 것이 앱
/// 바탕이기 때문이다 — 판정은 [ThemeData.estimateBrightnessForColor] 다. 그림은
/// 바꾸지 않고 [child] 를 그대로 그린다.
class AppSystemBarsRegion extends StatelessWidget {
  /// [AppSystemBarsRegion] 을 생성한다.
  const AppSystemBarsRegion({required this.child, super.key});

  /// 영역 안에 그릴 위젯.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final SystemUiOverlayStyle navigationBarStyle =
        buildDefaultNavigationBarStyle(
          resolveNavigationBarBrightness(context),
          isGestureNavigation: usesGestureNavigation(context),
        );
    if (defaultTargetPlatform != TargetPlatform.android) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: navigationBarStyle,
        child: child,
      );
    }
    final SystemUiOverlayStyle statusBarStyle = buildDefaultStatusBarStyle(
      ThemeData.estimateBrightnessForColor(
        Theme.of(context).colorScheme.surface,
      ),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: navigationBarStyle.copyWith(
        statusBarColor: statusBarStyle.statusBarColor,
        statusBarIconBrightness: statusBarStyle.statusBarIconBrightness,
      ),
      child: child,
    );
  }
}
