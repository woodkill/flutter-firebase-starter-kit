import 'package:flutter/widgets.dart';

/// Material 3 window size class 5단계 화면 폭 breakpoint.
///
/// 각 단계는 하한([minWidth])만 갖는다 — 다음 단계의 하한 전까지가 그 단계다:
/// - [compact]: 0dp 이상 600dp 미만
/// - [medium]: 600dp 이상 840dp 미만
/// - [expanded]: 840dp 이상 1200dp 미만
/// - [large]: 1200dp 이상 1600dp 미만
/// - [extraLarge]: 1600dp 이상
///
/// 킷은 모바일 전용(지원 폭 280 ~ 674dp)이라 실제로 만나는 단계는 [compact] 와
/// [medium] 의 앞부분이다 — 지원 폭은 이 enum 의 값이 아니라 문서 문장이다.
enum AppBreakpoint {
  /// Compact — 0dp 이상 600dp 미만(휴대폰 세로).
  compact(0),

  /// Medium — 600dp 이상 840dp 미만(작은 태블릿 · 펼친 폴더블 세로).
  medium(600),

  /// Expanded — 840dp 이상 1200dp 미만(태블릿 가로).
  expanded(840),

  /// Large — 1200dp 이상 1600dp 미만(큰 태블릿 · 데스크톱).
  large(1200),

  /// Extra-large — 1600dp 이상(아주 큰 화면).
  extraLarge(1600);

  /// 하한 너비 [minWidth] 로 단계를 만든다.
  const AppBreakpoint(this.minWidth);

  /// 이 단계의 하한 너비 (dp, 포함).
  final double minWidth;

  /// [width] 에 해당하는 [AppBreakpoint] 를 돌려준다.
  ///
  /// 하한이 [width] 이하인 마지막 단계다. NaN · 음수는 모든 하한 비교가 거짓이라
  /// [compact] 로 떨어지고, 무한대는 [extraLarge] 다.
  static AppBreakpoint fromWidth(double width) =>
      values.lastWhere((bp) => width >= bp.minWidth, orElse: () => compact);
}

/// [BuildContext]에서 반응형 정보에 접근하기 위한 확장.
///
/// 킷 화면에는 사용처가 없다 — 내 화면이 화면 폭이나 방향으로 갈릴 때 쓰는
/// 공개 계약이다.
///
/// [MediaQuery.sizeOf]와 [MediaQuery.orientationOf]를 사용하여
/// 불필요한 리빌드를 최소화한다.
///
/// **주의 — 화면 전체 폭 기준:** [breakpoint] 는 [MediaQuery.sizeOf] (화면
/// 전체 폭) 를 쓴다. 폭이 제한된 컨테이너(sheet, 분할 레이아웃, 패딩된
/// 칼럼) 안에서는 실제 가용 폭과 어긋난다. 지역 제약 기준이 필요하면
/// [LayoutBuilder] 와 [AppBreakpoint.fromWidth] 를 직접 쓴다.
///
/// 사용 예:
/// ```dart
/// // 화면 전체 폭 기준 — medium 이상이면 두 칸 레이아웃
/// final bp = context.breakpoint;
/// if (bp.index >= AppBreakpoint.medium.index) {
///   // 600dp 이상 레이아웃
/// }
///
/// // 지역 제약 기준
/// LayoutBuilder(
///   builder: (context, constraints) {
///     final bp = AppBreakpoint.fromWidth(constraints.maxWidth);
///     return bp == AppBreakpoint.compact ? const _Narrow() : const _Wide();
///   },
/// );
/// ```
extension ResponsiveX on BuildContext {
  /// 현재 화면 너비에 해당하는 [AppBreakpoint]를 반환한다.
  AppBreakpoint get breakpoint =>
      AppBreakpoint.fromWidth(MediaQuery.sizeOf(this).width);

  /// 현재 기기가 landscape orientation인지 반환한다.
  bool get isLandscape =>
      MediaQuery.orientationOf(this) == Orientation.landscape;

  /// 현재 기기가 portrait orientation인지 반환한다.
  ///
  /// [isLandscape]에서 파생된다 — 두 getter 가 각자 [MediaQuery] 를 읽으면
  /// 진실원이 둘로 갈라진다.
  bool get isPortrait => !isLandscape;
}
