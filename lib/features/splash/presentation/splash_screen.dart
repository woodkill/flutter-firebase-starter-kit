import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/theme/theme_extensions.dart';

/// Splash placeholder 화면.
///
/// Phase 10에서 실제 스플래시 UI로 교체된다.
/// 라우팅 동작 검증 목적으로만 사용하며, [Icons.construction] 과
/// stub 마커 텍스트로 throwaway UI 임을 시각적으로 알린다.
class SplashScreen extends StatelessWidget {
  /// Splash placeholder 화면을 생성한다.
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    final colorScheme = context.colorScheme;
    final textTheme = context.textTheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.construction,
              size: 48,
              color: colorScheme.onSurfaceVariant,
            ),
            Gap(spacing.md),
            Text(
              l10n.splashPlaceholderTitle,
              style: textTheme.titleLarge,
            ),
            Gap(spacing.sm),
            Text(
              l10n.splashPlaceholderStub,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
