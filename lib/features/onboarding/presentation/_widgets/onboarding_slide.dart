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
///
/// 높이가 제한된 부모(PageView 페이지)에서는 내용이 넘칠 때만 세로 스크롤하고,
/// 맞으면 `minHeight` 제약으로 지금처럼 세로 중앙 정렬한다 — 가로 모드 오버플로우
/// 방지(Phase 3 D-09 · quick 260929-pze). 높이 제한이 없는 부모(스크롤 뷰 안 —
/// 슬라이드 3)에서는 스크롤 없이 그대로 렌더한다. 무조건 스크롤 뷰로 감싸면
/// unbounded 높이 안에 viewport 가 들어가 런타임 assertion 이 나기 때문이다.
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

    final content = Semantics(
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

    return LayoutBuilder(
      builder: (context, constraints) {
        // 높이 제한 없음(스크롤 뷰 안 — 슬라이드 3)이면 기존 트리 그대로.
        if (!constraints.hasBoundedHeight) {
          return content;
        }
        // 높이 제한 있음(PageView 페이지)이면 넘칠 때만 스크롤, 맞으면 중앙 정렬.
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: content,
          ),
        );
      },
    );
  }
}
