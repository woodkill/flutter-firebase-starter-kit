import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../../core/theme/theme_extensions.dart';

/// 온보딩 공통 슬라이드 레이아웃 (UI-SPEC § OnboardingSlide).
///
/// 아이콘 원형 배지 (96dp = `xxxl * 2`, [ColorScheme.primaryContainer]) +
/// 헤드라인 + 본문 텍스트의 세로 중앙 정렬 구조.
///
/// `xxxl * 2 = 96dp` 는 UI-SPEC Exception 3 의 명시적 식이며, 디자인 토큰
/// 스케일 외 값을 직접 쓰지 않기 위한 계산이다.
class OnboardingSlide extends StatelessWidget {
  /// [OnboardingSlide] 를 생성한다.
  const OnboardingSlide({
    required this.icon,
    required this.title,
    required this.body,
    super.key,
  });

  /// 슬라이드 중앙에 표시할 아이콘.
  final IconData icon;

  /// 슬라이드 제목 텍스트.
  final String title;

  /// 슬라이드 본문 텍스트.
  final String body;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final spacing = context.appSpacing;
    final typography = context.appTypography;
    final badgeSize = spacing.xxxl * 2; // UI-SPEC Exception 3: 96dp

    return Semantics(
      label: '$title. $body',
      container: true,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: spacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: badgeSize,
              height: badgeSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.primaryContainer,
              ),
              child: Icon(
                icon,
                size: spacing.xxxl,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            Gap(spacing.xl),
            Text(
              title,
              style: typography.headlineMedium.copyWith(
                color: colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            Gap(spacing.md),
            Text(
              body,
              style: typography.bodyMedium.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
