import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/theme/theme_extensions.dart';

/// 하단 페이지 인디케이터 도트 (Phase 10 D-04).
///
/// 활성 도트는 [ColorScheme.primary] 색상, 비활성 도트는
/// [ColorScheme.onSurfaceVariant] 의 30% 투명도. 가로로 [count] 개를
/// 중앙 정렬하며 도트 사이 [AppSpacing.sm] 간격을 둔다.
///
/// 접근성: `Semantics(label: onboardingPageIndicator, liveRegion: true)` 로
/// 페이지 변경 시 스크린 리더가 안내한다. 라벨은 **반드시 ARB 키**를 거친다
/// (WR-09) — 하드코딩 영어 리터럴은 ko/ja 로케일에서도 영어로 읽히며,
/// `liveRegion: true` 라 페이지 전환마다 발화되어 영향이 크다.
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
      // WR-09: 1-based 페이지 번호를 전달한다 — 사용자가 듣는 숫자는
      // 0-based [activeIndex] 가 아니다.
      label: context.l10n.onboardingPageIndicator(activeIndex + 1, count),
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
