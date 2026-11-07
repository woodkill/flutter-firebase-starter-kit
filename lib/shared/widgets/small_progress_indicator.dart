import 'package:flutter/material.dart';

/// 작은 진행 표시의 선 굵기 (logical pixel).
// design-literal: Material 3 기본 굵기 4 는 지름 48 기준이라 지름 24 이하 작은 스피너는 2 로 둔다
const double _kStrokeWidth = 2;

/// 버튼 안 · 스플래시처럼 아이콘 크기 자리에 두는 작은 원형 진행 표시.
///
/// 지름은 호출부가 `context.appIconSizes` 의 값으로 넘긴다. 선 굵기는 지름과
/// 상관없이 2 로 고정이며, 테마의 진행 표시 테마는 건드리지 않는다.
class SmallProgressIndicator extends StatelessWidget {
  /// [SmallProgressIndicator] 를 생성한다.
  const SmallProgressIndicator({
    super.key,
    required this.dimension,
    this.color,
  });

  /// 진행 표시의 지름 (logical pixel).
  final double dimension;

  /// 진행 표시의 색 — null 이면 테마 기본 색을 쓴다.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: dimension,
      child: CircularProgressIndicator(
        strokeWidth: _kStrokeWidth,
        color: color,
      ),
    );
  }
}
