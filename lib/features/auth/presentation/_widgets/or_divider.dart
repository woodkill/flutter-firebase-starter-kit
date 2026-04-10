import 'package:flutter/material.dart';

import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/theme/theme_extensions.dart';

/// "또는" 텍스트 구분선 위젯 (D-02).
///
/// Row[Expanded(Divider), Padding(Text("또는")), Expanded(Divider)] 패턴.
/// [context.l10n.authOrDivider]로 다국어 "또는" 텍스트를 렌더한다.
/// Phase 8(Apple), 9(Facebook)에서도 재사용.
class OrDivider extends StatelessWidget {
  /// [OrDivider]를 생성한다.
  const OrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    return Semantics(
      label: l10n.authOrDivider,
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: spacing.lg),
            child: Text(
              l10n.authOrDivider,
              style: context.appTypography.bodyMedium.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }
}
