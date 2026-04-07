import 'package:flutter/material.dart';

import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/theme/theme_extensions.dart';

/// Phase 6 인증 화면 공통 Primary CTA 버튼.
///
/// [isLoading] 이 true 이면 라벨을 [CircularProgressIndicator] 로 교체하고
/// 버튼을 disabled 상태로 만든다 (D-31). 버튼 크기(높이 48dp +
/// width double.infinity) 는 변하지 않는다 (06-UI-SPEC.md / Component
/// Inventory / Buttons).
class PrimaryCta extends StatelessWidget {
  /// [PrimaryCta] 를 생성한다.
  const PrimaryCta({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  /// 버튼에 표시할 텍스트 라벨.
  final String label;

  /// 탭 콜백. [isLoading] 이 true 이거나 null 이면 disabled.
  final VoidCallback? onPressed;

  /// 로딩 상태. true 이면 라벨이 spinner 로 교체된다.
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton(
        onPressed: isLoading ? null : onPressed,
        child: isLoading
            ? Semantics(
                label: context.l10n.commonLoading,
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.onPrimary,
                  ),
                ),
              )
            : Text(label),
      ),
    );
  }
}
