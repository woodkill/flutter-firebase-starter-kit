import 'package:flutter/material.dart';

/// 키보드 focus 시 button 외곽에 visible outline 을 그려주는 wrapper widget.
///
/// **Phase 13.3 X2 (2026-05-17, 260517-uv4) — 옵션 B 의무 (token 의존 0):**
/// WCAG 2.1 SC 2.4.7 (Focus Visible) Level AA 부합. 5 social provider button
/// 의 outer wrapper 로 적용하여 `Tab` 키 focus 도착 시 2dp solid outline
/// + 2dp offset 시각 표시. M3 `colorScheme`/`textTheme` 토큰 의존 0 패턴 —
/// 사용자가 `ThemeData` override (예: `primary` 색상 바꿈) 해도 focus
/// indicator drift 면역 (starter kit brand drift 회피 원칙).
///
/// **옵션 A (`ThemeData.focusColor` / `colorScheme.primary`) 금지** — token
/// 의존 패턴은 사용자 ThemeData override 시 focus indicator 가 design
/// theme tint 로 변경되어 brand button 의 contrast 회귀 위험.
///
/// **외관 spec (hardcode, token 의존 0):**
/// - outline 두께: 2dp solid
/// - outline offset: 2dp (button 바깥쪽 — overlay 가 button 경계를 침범 안
///   하도록 별도 layer)
/// - outline 색: light theme 에서는 검정 (`Color(0xFF000000)`), dark theme
///   에서는 흰 (`Color(0xFFFFFFFF)`) — 양 theme contrast 보장
/// - corner radius: 매개변수 [borderRadius] 따름 (5 provider 각각의
///   `BrandSpec.borderRadius` 매핑)
///
/// **회귀 가드:** `test/features/auth/presentation/_widgets/
/// focus_visible_test.dart` 의 `T-13.3-FOCUS-VISIBLE-THEME-01`.
class BrandFocusWrapper extends StatefulWidget {
  /// [BrandFocusWrapper] 를 생성한다.
  ///
  /// [child] 는 focus 대상 button (예: `Semantics > SizedBox > Material >
  /// InkWell` 구조의 social button). [borderRadius] 는 button 의 corner
  /// radius 와 일치시켜 outline 모서리를 맞춤 (`BrandSpec.borderRadius` 매핑).
  /// [isEnabled] 가 false 면 focus 진입 자체를 차단 (disabled button).
  const BrandFocusWrapper({
    required this.child,
    required this.borderRadius,
    this.isEnabled = true,
    super.key,
  });

  /// focus 대상 button widget.
  final Widget child;

  /// outline corner radius (button 의 `BrandSpec.borderRadius` 매핑, dp).
  final double borderRadius;

  /// button 활성 여부. false 면 focus 진입 차단.
  final bool isEnabled;

  @override
  State<BrandFocusWrapper> createState() => _BrandFocusWrapperState();
}

class _BrandFocusWrapperState extends State<BrandFocusWrapper> {
  bool _hasFocus = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // hardcode — M3 token 의존 0 (starter kit brand drift 회피).
    final outlineColor = isDark
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF000000);
    return FocusableActionDetector(
      enabled: widget.isEnabled,
      onFocusChange: (hasFocus) {
        if (mounted && _hasFocus != hasFocus) {
          setState(() {
            _hasFocus = hasFocus;
          });
        }
      },
      child: Container(
        // 2dp offset — outline 이 button 경계를 침범하지 않도록 별도 layer.
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius + 4),
          border: Border.all(
            color: _hasFocus ? outlineColor : Colors.transparent,
            width: 2,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}
