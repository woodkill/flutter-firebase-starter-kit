import 'package:flutter/widgets.dart';

/// 모바일 전용 반응형 breakpoint (280dp~674dp).
///
/// M3 가이드라인 기준 3단계로 분류한다 (하한 포함, 상한 배타):
/// - [compact]: 280dp~360dp (소형 디바이스)
/// - [medium]: 360dp~600dp (일반 모바일)
/// - [expanded]: 600dp~674dp (대형 모바일/폴더블)
///
/// [minWidth]/[maxWidth] 범위가 **단일 진실원**이며, [contains] 와
/// [fromWidth] 는 모두 여기서 파생된다. 지원 범위(280dp~674dp) 밖의
/// 너비는 [fromWidth] 가 양끝으로 포화시킨다.
enum AppBreakpoint {
  /// 소형 디바이스 (280dp~360dp).
  compact(280, 360),

  /// 일반 모바일 (360dp~600dp).
  medium(360, 600),

  /// 대형 모바일/폴더블 (600dp~674dp).
  expanded(600, 674);

  const AppBreakpoint(this.minWidth, this.maxWidth);

  /// 이 breakpoint의 최소 너비 (dp, 포함).
  final double minWidth;

  /// 이 breakpoint의 최대 너비 (dp, 배타).
  final double maxWidth;

  /// [width]가 이 breakpoint 범위에 속하는지 반환한다.
  ///
  /// 하한은 포함([minWidth] 이상), 상한은 배타([maxWidth] 미만) 다.
  /// 따라서 인접한 두 breakpoint 가 동시에 true 를 돌려주는 경계값은 없다.
  bool contains(double width) => width >= minWidth && width < maxWidth;

  /// [width]에 해당하는 [AppBreakpoint]를 반환한다.
  ///
  /// 범위 필드([contains])에서 파생되며, 지원 범위 밖은 양끝으로
  /// 포화한다:
  /// - `width < compact.minWidth` (280dp 미만) -> [compact]
  /// - `width >= expanded.maxWidth` (674dp 이상 — 가로 모드 등) -> [expanded]
  ///
  /// 포화 정책상 [maxWidth] 는 "선언된 지원 상한" 이지 실제 가용 폭이
  /// 아니므로, 레이아웃 계산(clamp 등)에 그대로 쓰지 말 것.
  static AppBreakpoint fromWidth(double width) {
    if (width < compact.minWidth) return compact;
    if (width >= expanded.maxWidth) return expanded;

    return values.firstWhere(
      (bp) => bp.contains(width),
      // 도달 불가 — 범위가 연속이므로 포화 이후에는 항상 매치된다.
      // width 가 NaN 인 병리적 입력만 여기로 떨어진다 (엣지 케이스 방어).
      orElse: () => compact,
    );
  }
}

/// [BuildContext]에서 반응형 정보에 접근하기 위한 확장.
///
/// [MediaQuery.sizeOf]와 [MediaQuery.orientationOf]를 사용하여
/// 불필요한 리빌드를 최소화한다.
///
/// 사용 예:
/// ```dart
/// final bp = context.breakpoint;
/// if (bp == AppBreakpoint.expanded) {
///   // 대형 모바일/폴더블 레이아웃
/// }
/// ```
extension ResponsiveX on BuildContext {
  /// 현재 화면 너비에 해당하는 [AppBreakpoint]를 반환한다.
  AppBreakpoint get breakpoint =>
      AppBreakpoint.fromWidth(MediaQuery.sizeOf(this).width);

  /// 현재 기기가 landscape orientation인지 반환한다.
  bool get isLandscape =>
      MediaQuery.orientationOf(this) == Orientation.landscape;

  /// 현재 기기가 portrait orientation인지 반환한다.
  bool get isPortrait => MediaQuery.orientationOf(this) == Orientation.portrait;
}
