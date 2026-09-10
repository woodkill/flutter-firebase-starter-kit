import 'package:flutter/material.dart';

import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/theme/theme_extensions.dart';

/// "이메일로 계속" 공유 CTA 위젯 (Phase 16.1 Surface S).
///
/// 호출 지점은 2곳이다 — `LoginScreen` chooser (`/login`) 와
/// `LoginPromptSheet`. 두 surface 의 CTA 외관을 구조적으로 일치시키기 위해
/// 얇은 [TextButton] wrapper 로 공유한다.
///
/// 라벨은 위젯 내부에서 [context.l10n] 의 `authContinueWithEmail` 로
/// 고정하며 외부 주입을 받지 않는다 (라벨 drift 차단). 라우팅도 하지 않고
/// [onPressed] 를 그대로 위임한다.
///
/// 기하(min height 40dp / radius 20dp / horizontal padding 12dp) 와 48dp
/// 터치 영역은 M3 기본값이 보장하므로 별도 지정하지 않는다.
class EmailAuthCta extends StatelessWidget {
  /// [EmailAuthCta] 를 생성한다.
  const EmailAuthCta({required this.onPressed, super.key});

  /// 탭 콜백. 라우팅은 호출자 책임이다.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TextButton(
      onPressed: onPressed,
      child: Text(
        l10n.authContinueWithEmail,
        style: context.appTypography.labelLarge.copyWith(
          color: context.colorScheme.primary,
        ),
      ),
    );
  }
}
