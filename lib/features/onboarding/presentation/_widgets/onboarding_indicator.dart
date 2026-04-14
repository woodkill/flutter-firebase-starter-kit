import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../../core/theme/theme_extensions.dart';

/// 하단 페이지 인디케이터 도트 (Phase 10 D-04).
///
/// 활성 도트는 [ColorScheme.primary] 색상, 비활성 도트는
/// [ColorScheme.onSurfaceVariant] 의 30% 투명도. 가로로 [count] 개를
/// 중앙 정렬하며 도트 사이 [AppSpacing.sm] 간격을 둔다.
///
/// 접근성: `Semantics(label: 'Page X of Y', liveRegion: true)` 로
/// 페이지 변경 시 스크린 리더가 안내한다.
class OnboardingIndicator extends StatelessWidget {
  /// [OnboardingIndicator] 를 생성한다.
  const OnboardingIndicator({
    required this.count,
    required this.activeIndex,
    super.key,
  });

  /// 도트 개수.
  final int count;

  /// 활성 도트 인덱스 (0-based).
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final spacing = context.appSpacing;
    return Semantics(
      label: 'Page ${activeIndex + 1} of $count',
      liveRegion: true,
      container: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (int i = 0; i < count; i++) ...[
            if (i > 0) Gap(spacing.sm),
            Container(
              width: spacing.sm,
              height: spacing.sm,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i == activeIndex
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
