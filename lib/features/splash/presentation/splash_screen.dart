import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/result.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/theme_extensions.dart';
import 'splash_initializer.dart';

/// 앱 스플래시 화면 (Phase 10 AUTH-08, D-22, D-25, WARNING #13).
///
/// 흐름:
/// 1. [SplashInitializer.initialize] 호출 -> 최소 표시 시간 대기 + 필요 시
///    `signInAnonymously`.
/// 2. 성공 -> [context.go]([AppRoutes.home]) -> [authRedirect] 가 최종 경로
///    결정 (게스트면 Home, 미인증+미시청이면 /onboarding 등).
/// 3. 실패 -> [_showFailureDialog] 표시 -> 사용자가 재시도 또는
///    오프라인으로 계속 (D-27).
///
/// 테스트 시 [SplashConfig.overrideMinDuration] = `Duration(milliseconds: 1)`
/// 로 실대기를 1ms 로 단축한다 (WARNING #13 seam pattern).
class SplashScreen extends ConsumerStatefulWidget {
  /// [SplashScreen] 을 생성한다.
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _hasFailure = false;

  @override
  void initState() {
    super.initState();
    // build 완료 후 비동기로 init 시퀀스를 시작한다 (mounted 가드 필요).
    WidgetsBinding.instance.addPostFrameCallback((_) => _runInit());
  }

  Future<void> _runInit() async {
    final initializer = ref.read(splashInitializerProvider);
    final result = await initializer.initialize();
    if (!mounted) return;
    if (result is Failure<void>) {
      setState(() => _hasFailure = true);
      await _showFailureDialog();
      return;
    }
    if (!mounted) return;
    context.go(AppRoutes.home);
  }

  Future<void> _showFailureDialog() async {
    final l10n = context.l10n;
    final selected = await showDialog<_SplashFailureAction>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final colorScheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          icon: Icon(Icons.cloud_off, color: colorScheme.onErrorContainer),
          iconColor: colorScheme.errorContainer,
          title: Text(l10n.splashFailureTitle),
          content: Text(l10n.splashFailureMessage),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_SplashFailureAction.offline),
              child: Text(l10n.splashContinueOffline),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_SplashFailureAction.retry),
              child: Text(l10n.commonRetry),
            ),
          ],
        );
      },
    );
    if (!mounted) return;
    switch (selected) {
      case _SplashFailureAction.retry:
        setState(() => _hasFailure = false);
        await _runInit();
      case _SplashFailureAction.offline:
      case null:
        if (!mounted) return;
        context.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    final colorScheme = context.colorScheme;
    final typography = context.appTypography;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/splash/logo.png',
                width: 128,
                height: 128,
                errorBuilder: (_, _, _) =>
                    const SizedBox(width: 128, height: 128),
              ),
              Gap(spacing.xxl),
              if (!_hasFailure)
                SizedBox.square(
                  dimension: spacing.xl,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                ),
              Gap(spacing.sm),
              Text(
                l10n.splashPreparing,
                style: typography.bodyMedium.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _SplashFailureAction { retry, offline }
