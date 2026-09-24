import 'dart:async';

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
/// **표시 조건 (debug facebook-login-double-spinner, L1+d):**
/// - scrim · `AbsorbPointer` 는 등장 첫 프레임부터 사라질 때까지 항상 유지한다.
/// - 스피너 + 라벨은 등장 후 [indicatorDelay] 가 지났고 **그리고** 앱
///   lifecycle 이 `resumed` 일 때만 그린다 (`lifecycleState == null` 은
///   `resumed` 로 취급 — flutter_test 기본값).
/// - 근거: Facebook(`FacebookActivity`) · LINE · Naver 같은 네이티브 SDK 는
///   투명 Activity 를 앱 위에 띄우고 자기 로딩 표시를 켠다. 그동안 앱은
///   `inactive`/`paused` 이므로 우리 스피너를 접어 이중 스피너를 막는다.
///   지연은 탭 직후 네이티브 Activity 가 뜨기 전(실측 ≈93ms) 스피너가
///   한 번 떴다 사라지는 깜빡임을 없앤다. 복귀(`resumed`) 시점엔 지연이 이미
///   지나 있어 스피너가 즉시 다시 보인다.
///
/// 부모 화면이 [Stack] 으로 감싸 본 위젯을 마지막 child 로 push 한다 —
/// 사용처 5곳:
/// - `LoginScreen` 일반 로그인
/// - `LoginScreen` 재인증 chooser (`_ReauthChooser`)
/// - `LoginPromptSheet`
/// - `AccountLinkingSheet`
/// - 설정 `AccountLinkingSection`
///
/// (Phase 16.1 에서 삭제된 구 가입 화면의 후임 `EmailSignupScreen` 은 소셜
/// 진입점이 없어 사용하지 않는다.)
class AuthInProgressOverlay extends StatefulWidget {
  /// 오버레이를 생성한다.
  const AuthInProgressOverlay({super.key});

  /// 오버레이 등장 후 스피너 + 라벨을 그리기 시작할 때까지의 지연.
  ///
  /// scrim · 입력 차단에는 적용되지 않는다 (둘은 즉시 표시).
  static const Duration indicatorDelay = Duration(milliseconds: 300);

  @override
  State<AuthInProgressOverlay> createState() => _AuthInProgressOverlayState();
}

class _AuthInProgressOverlayState extends State<AuthInProgressOverlay> {
  late final AppLifecycleListener _lifecycleListener;
  Timer? _delayTimer;
  bool _isDelayElapsed = false;
  bool _isResumed = true;

  @override
  void initState() {
    super.initState();
    _isResumed = _checkResumed(WidgetsBinding.instance.lifecycleState);
    _lifecycleListener = AppLifecycleListener(
      onStateChange: _handleLifecycleStateChange,
    );
    _delayTimer = Timer(
      AuthInProgressOverlay.indicatorDelay,
      _handleDelayElapsed,
    );
  }

  @override
  void dispose() {
    // 타이머가 남으면 flutter_test 가 "A Timer is still pending" 으로 실패한다.
    _delayTimer?.cancel();
    _lifecycleListener.dispose();
    super.dispose();
  }

  /// `null`(flutter_test 기본 · 엔진 보고 전) 은 `resumed` 로 취급한다.
  static bool _checkResumed(AppLifecycleState? state) =>
      state == null || state == AppLifecycleState.resumed;

  void _handleDelayElapsed() {
    if (!mounted) {
      return;
    }
    setState(() => _isDelayElapsed = true);
  }

  void _handleLifecycleStateChange(AppLifecycleState state) {
    final isResumed = _checkResumed(state);
    if (!mounted || isResumed == _isResumed) {
      return;
    }
    setState(() => _isResumed = isResumed);
  }

  @override
  Widget build(BuildContext context) {
    final shouldShowIndicator = _isDelayElapsed && _isResumed;

    return Positioned.fill(
      child: AbsorbPointer(
        child: ColoredBox(
          // M3 scrim 토큰 — Modal 컨텍스트 표준 dim.
          color: context.colorScheme.scrim.withValues(alpha: 0.32),
          // Positioned.fill 의 tight 제약이라 child 가 없어도 화면 전체를 덮는다.
          child: shouldShowIndicator ? const _ProgressIndicatorLabel() : null,
        ),
      ),
    );
  }
}

/// 중앙 [CircularProgressIndicator] + 「로그인 처리 중…」 라벨.
class _ProgressIndicatorLabel extends StatelessWidget {
  const _ProgressIndicatorLabel();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    final typography = context.appTypography;
    final spacing = context.appSpacing;

    return Center(
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
    );
  }
}
