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
/// - 표시 조건: 자손 focus 보유 **그리고**
///   `FocusManager.highlightMode == FocusHighlightMode.traditional`
///   (키보드 조작). 터치·프로그램적 focus 에서는 표시하지 않는다.
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
  /// wrapper 의 focus 노드. 자신은 focus 를 받지 않고(자손 관찰자 역할),
  /// a11y focus 요청을 자손으로 위임하기 위해 참조를 보관한다.
  final FocusNode _node = FocusNode(
    debugLabel: 'BrandFocusWrapper',
    canRequestFocus: false,
    skipTraversal: true,
  );

  /// 자손이 focus 를 보유 중인지 여부 (outline 표시 조건 1).
  bool _hasFocus = false;

  /// outline 을 실제로 그릴지 여부.
  ///
  /// `_hasFocus` 와 `FocusManager.highlightMode == traditional` 의 AND 다.
  bool _showOutline = false;

  @override
  void initState() {
    super.initState();
    // highlightMode 는 입력 수단(키보드/터치)에 따라 런타임에 바뀐다. 전환 시
    // outline 이 stale 로 남지 않도록 구독한다.
    FocusManager.instance.addHighlightModeListener(_handleHighlightModeChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(
      _handleHighlightModeChanged,
    );
    _node.dispose();
    super.dispose();
  }

  void _handleHighlightModeChanged(FocusHighlightMode mode) {
    _syncOutline(hasFocus: _hasFocus, mode: mode);
  }

  /// outline 표시 여부를 재계산하고, 값이 바뀐 경우에만 리빌드한다.
  void _syncOutline({
    required bool hasFocus,
    required FocusHighlightMode mode,
  }) {
    // 키보드 조작(traditional)에서만 outline 을 노출한다. 터치 단말에서
    // 다이얼로그 닫힘 후 focus 복원 / `requestFocus()` / directional
    // navigation 으로 focus 가 들어와도 터치 사용자에게는 표시하지 않는다.
    final show = hasFocus && mode == FocusHighlightMode.traditional;
    if (!mounted || _showOutline == show) return;
    setState(() {
      _showOutline = show;
    });
  }

  /// a11y 서비스(TalkBack/VoiceOver/Switch Access)의 focus 요청을 첫 번째
  /// traversal 가능한 자손(brand button 의 `InkWell`)으로 위임한다.
  ///
  /// 자손이 없으면(레이아웃 미완료 등) 아무 것도 하지 않는다 — 엣지 케이스 방어.
  void _requestDescendantFocus() {
    for (final descendant in _node.traversalDescendants) {
      descendant.requestFocus();
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // hardcode — M3 token 의존 0 (starter kit brand drift 회피).
    final outlineColor = isDark
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF000000);
    return Focus(
      focusNode: _node,
      // wrapper 자신은 focus 를 받지 않는다 — traversal 정지점을 추가하면
      // child(InkWell) 앞에 "Enter 가 먹지 않는" 죽은 Tab stop 이 생긴다.
      // (`FocusableActionDetector` 는 내부적으로 `canRequestFocus: enabled`
      // + `skipTraversal: false` 인 Focus 를 만들기 때문에 이 결함이 있었다.)
      canRequestFocus: false,
      skipTraversal: true,
      // isEnabled=false 면 자손 focus 진입 자체를 차단 (disabled button).
      descendantsAreFocusable: widget.isEnabled,
      // wrapper 의 focus 의미론(`focusable: false`)은 노출하지 않는다 —
      // 병합된 button SemanticsNode 를 "focus 불가" 로 오도한다.
      includeSemantics: false,
      // 자손(InkWell)이 focus 를 받으면 hasFocus=true 로 전달된다.
      onFocusChange: (hasFocus) {
        _hasFocus = hasFocus;
        _syncOutline(
          hasFocus: hasFocus,
          mode: FocusManager.instance.highlightMode,
        );
      },
      child: Semantics(
        // brand button 은 `Semantics(excludeSemantics: true)` 로 자손 `InkWell`
        // 의 focus 의미론을 차단하므로, wrapper 가 대신 노출한다. focus 요청은
        // 실제 focus 노드(자손 InkWell)로 위임한다.
        focusable: widget.isEnabled,
        onFocus: widget.isEnabled ? _requestDescendantFocus : null,
        child: Container(
          // 2dp offset — outline 이 button 경계를 침범하지 않도록 별도 layer.
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius + 4),
            border: Border.all(
              color: _showOutline ? outlineColor : Colors.transparent,
              width: 2,
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
