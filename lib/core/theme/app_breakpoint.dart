import 'package:flutter/widgets.dart';

/// 모바일 전용 반응형 breakpoint (280dp~674dp).
///
/// M3 가이드라인 기준 3단계로 분류한다:
/// - [compact]: ~360dp (소형 디바이스)
/// - [medium]: 360dp~600dp (일반 모바일)
/// - [expanded]: 600dp~674dp (대형 모바일/폴더블)
///
/// [fromWidth]로 화면 너비에 해당하는 breakpoint를 조회한다.
enum AppBreakpoint {
  /// 소형 디바이스 (~360dp).
  compact(0, 360),

  /// 일반 모바일 (360dp~600dp).
  medium(360, 600),

  /// 대형 모바일/폴더블 (600dp~674dp).
  expanded(600, 674);

  const AppBreakpoint(this.minWidth, this.maxWidth);

  /// 이 breakpoint의 최소 너비 (dp).
  final double minWidth;

  /// 이 breakpoint의 최대 너비 (dp).
  final double maxWidth;

  /// [width]에 해당하는 [AppBreakpoint]를 반환한다.
  ///
  /// - width >= 600 -> [expanded]
  /// - width >= 360 -> [medium]
  /// - 그 외 -> [compact]
  static AppBreakpoint fromWidth(double width) {
    if (width >= 600) return expanded;
    if (width >= 360) return medium;
    return compact;
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
  bool get isPortrait =>
      MediaQuery.orientationOf(this) == Orientation.portrait;
}
