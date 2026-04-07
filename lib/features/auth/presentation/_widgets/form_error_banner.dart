import 'package:flutter/material.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../core/l10n/exception_l10n.dart';
import '../../../../core/theme/theme_extensions.dart';

/// 폼 상단 Firebase 에러 배너 (D-30).
///
/// [exception] 이 null 이면 [SizedBox.shrink] 를 반환하고,
/// non-null 이면 errorContainer 배경 + 에러 아이콘 + 번역 메시지를
/// 표시한다. 화면 차단 컴포넌트(Dialog/SnackBar) 를 사용하지 않는
/// inline 에러 표시 패턴 (D-32).
///
/// 보안: ARB 키 raw 노출(Pitfall 7) 을 방지하기 위해
/// [resolveExceptionMessage] 를 강제 경유한다 (T-06.03-05 mitigation).
class FormErrorBanner extends StatelessWidget {
  /// [FormErrorBanner] 를 생성한다.
  const FormErrorBanner({super.key, required this.exception});

  /// 표시할 [AppException]. null 이면 위젯이 비워진다.
  final AppException? exception;

  @override
  Widget build(BuildContext context) {
    final ex = exception;
    if (ex == null) return const SizedBox.shrink();

    final colors = context.colorScheme;
    final spacing = context.appSpacing;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: spacing.md,
          vertical: spacing.sm,
        ),
        decoration: BoxDecoration(
          color: colors.errorContainer,
          borderRadius: BorderRadius.circular(spacing.sm),
        ),
        child: Row(
          children: [
            Icon(
              Icons.error_outline,
              color: colors.onErrorContainer,
              size: 20,
            ),
            SizedBox(width: spacing.sm),
            Expanded(
              child: Text(
                resolveExceptionMessage(context, ex),
                style: context.appTypography.bodyMedium.copyWith(
                  color: colors.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
