import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/theme/theme_extensions.dart';

/// 게스트 사용자에게 화면 상단에 고정 노출되는 안내 배너 (Phase 10 D-13).
///
/// 익명 로그인 상태일 때만 [HomeScreen] 의 본문 바깥(AppBar · 공지 배너
/// 아래)에 렌더되어, 본문을 끝까지 내려도 AppBar 아래에 계속 남는다.
/// Material 3 [ColorScheme.surfaceContainerHigh] 배경을 좌우 끝까지 채우고
/// 하단의 hairline [Divider] 로 본문과 분리해, 주의를 끌지 않으면서도 상태를
/// 전달한다. Phase 10 UI-REVIEW Top Fix #2 (홈 화면 focal point 부재) 를 코드
/// 차원에서 닫는 변경이다.
///
/// Phase 17.1 — 옛 홈의 private 배너를 렌더 그대로 옮겨 public 위젯으로
/// 승격했다(D-10 · golden byte 동일 목표라 [ConsumerWidget] 형태도 유지).
class GuestBanner extends ConsumerWidget {
  /// 게스트 안내 배너를 만든다.
  const GuestBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    final colorScheme = context.colorScheme;
    final typography = context.appTypography;
    return Material(
      color: colorScheme.surfaceContainerHigh,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: spacing.lg,
              vertical: spacing.sm,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: spacing.lg,
                  color: colorScheme.onSurfaceVariant,
                ),
                Gap(spacing.sm),
                Expanded(
                  child: Text(
                    l10n.homeGuestBanner,
                    style: typography.bodyMedium.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: colorScheme.outlineVariant),
        ],
      ),
    );
  }
}
