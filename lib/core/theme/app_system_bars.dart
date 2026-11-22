/// 앱 맨 바깥에서 Android 내비게이션 바의 기본 값을 정한다.
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
/// **상태 표시줄 필드는 두지 않는다** — 상태 표시줄은 AppBar 와 화면 영역이
/// 맡는다.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 내비게이션 바 막 색 · 아이콘 밝기를 정할 기준 밝기를 돌려준다.
///
/// OS 밝기 설정을 따른다 — 막 색과 아이콘이 같은 기준을 본다.
Brightness resolveNavigationBarBrightness(BuildContext context) =>
    MediaQuery.platformBrightnessOf(context);

/// [brightness] 에 맞는 내비게이션 바 기본 값을 만든다.
///
/// 내비게이션 바의 색 · 대비 강제 · 아이콘 밝기 세 필드만 담는다. 아이콘은
/// 어두운 기준에서 밝게, 밝은 기준에서 어둡게 둔다.
SystemUiOverlayStyle buildDefaultNavigationBarStyle(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  return SystemUiOverlayStyle(
    systemNavigationBarColor: isDark
        // Android 15 이상 OS 가 그리는 3버튼 다크 막(검정 약 80%)에 맞춘 값이다.
        ? const Color(0xCC000000)
        // androidx activity `EdgeToEdge` 의 라이트 막 상수(DefaultLightScrim)다.
        : const Color(0xE6FFFFFF),
    systemNavigationBarContrastEnforced: true,
    systemNavigationBarIconBrightness: isDark
        ? Brightness.light
        : Brightness.dark,
  );
}

/// 앱 맨 바깥에서 내비게이션 바 기본 값을 알리는 영역.
///
/// [resolveNavigationBarBrightness] 가 돌려준 밝기로
/// [buildDefaultNavigationBarStyle] 이 만든 값을 [AnnotatedRegion] 하나로
/// 알린다. 그림은 바꾸지 않고 [child] 를 그대로 그린다.
class AppSystemBarsRegion extends StatelessWidget {
  /// [AppSystemBarsRegion] 을 생성한다.
  const AppSystemBarsRegion({required this.child, super.key});

  /// 영역 안에 그릴 위젯.
  final Widget child;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: buildDefaultNavigationBarStyle(
      resolveNavigationBarBrightness(context),
    ),
    child: child,
  );
}
