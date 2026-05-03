import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/theme/theme_extensions.dart';

/// 소셜 OAuth 흐름 진행 중 화면 전체를 덮는 오버레이 (Phase 11-04 hotfix).
///
/// **목적:** OAuth 외부 인증 (Custom Tab / 시스템 브라우저) 에서 앱으로 복귀한
/// 직후 `signInWithCredential` / Firestore mirror / 라우팅까지의 구간 동안
/// 사용자에게 명시적인 진행 신호를 제공한다. 11-04 검증 4 의 UAT 에서
/// "외부 인증 후 앱 복귀 시 LoginScreen 이 멈춘 듯 보이는" UX gap 의 결정적
/// 차단 장치.
///
/// **설계 결정 (옵션 B):**
/// - `AbsorbPointer`: 입력 흡수로 이중 제출 방지 (탭 차단).
/// - `ColoredBox(scrim 32%)`: M3 토큰 기반 dim — 화면 컨텐츠가 비활성임을
///   시각적으로 전달하면서도 컨텍스트 (어느 화면이었는지) 유지.
/// - 중앙 [CircularProgressIndicator] + i18n 라벨: 진행 신호 강도 강.
///
/// 부모 화면이 [Stack] 으로 감싸 본 위젯을 마지막 child 로 push 한다 —
/// `LoginScreen` / `SignupScreen` / `LoginPromptSheet` 3곳에 적용.
class AuthInProgressOverlay extends StatelessWidget {
  /// 오버레이를 생성한다.
  const AuthInProgressOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    final typography = context.appTypography;
    final spacing = context.appSpacing;

    return Positioned.fill(
      child: AbsorbPointer(
        child: ColoredBox(
          // M3 scrim 토큰 — Modal 컨텍스트 표준 dim.
          color: colorScheme.scrim.withValues(alpha: 0.32),
          child: Center(
            child: Semantics(
              container: true,
              liveRegion: true,
              label: l10n.authSocialSigningIn,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const CircularProgressIndicator(),
                  Gap(spacing.md),
                  Text(
                    l10n.authSocialSigningIn,
                    style: typography.bodyMedium.copyWith(
                      color: colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
