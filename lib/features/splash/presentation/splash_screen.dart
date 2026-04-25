import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/result.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/providers/firebase_providers.dart';
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

  /// init 시퀀스 동시 실행 가드 (Gap A — quick-260425-01g).
  ///
  /// `didChangeDependencies` / RouterDelegate listener / `ref.listen` 이
  /// 동시에 `_triggerReinit` 을 호출해도 `_runInit` 본체가 1회만 실행되도록
  /// 한다.
  bool _initInFlight = false;

  /// 직전 관측한 GoRouter location (Gap A 재entry 감지용 — quick-260425-01g).
  ///
  /// RouterDelegate listener 와 `didChangeDependencies` 양쪽에서 현재
  /// location 과 비교하여 `/splash` 로 새로 진입한 시점 (예: GC-04 fail-safe
  /// redirect) 을 식별한다. 첫 호출 (null 인 경우) 은 `initState` 의 init
  /// 트리거에서 처리되므로 skip.
  String? _lastObservedLocation;

  /// 현재 attach 된 GoRouter (Gap A 재entry 감지용 — quick-260425-01g).
  ///
  /// RouterDelegate 는 [Listenable] 이며 모든 navigation (redirect 포함) 시
  /// listener 를 알린다. GC-04 fail-safe redirect 처럼 현재 location 과 동일한
  /// path 로 redirect 하는 경우 `didChangeDependencies` 가 fire 되지 않는
  /// case 를 1차 신호로 커버한다.
  GoRouter? _attachedRouter;

  @override
  void initState() {
    super.initState();
    // build 완료 후 비동기로 init 시퀀스를 시작한다 (mounted 가드 필요).
    WidgetsBinding.instance.addPostFrameCallback((_) => _runInit());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Gap A (quick-260425-01g) — RouterDelegate listener attach (initial mount).
    // didChangeDependencies 는 InheritedWidget 이 변경될 때 fire 하므로
    // GoRouter 가 attach 된 후 첫 호출 시점에 listener 등록한다.
    final router = GoRouter.of(context);
    if (!identical(_attachedRouter, router)) {
      _attachedRouter?.routerDelegate.removeListener(_onRouterChanged);
      _attachedRouter = router;
      _attachedRouter?.routerDelegate.addListener(_onRouterChanged);
    }
    _maybeTriggerReinitFromLocation();
  }

  @override
  void dispose() {
    _attachedRouter?.routerDelegate.removeListener(_onRouterChanged);
    _attachedRouter = null;
    super.dispose();
  }

  /// RouterDelegate change listener (Gap A — quick-260425-01g).
  ///
  /// GoRouter 가 navigation 또는 redirect 로 currentConfiguration 을 갱신할
  /// 때 호출된다. location 변화를 직접 비교하여 `/splash` 재entry 를 감지.
  void _onRouterChanged() {
    if (!mounted) return;
    _maybeTriggerReinitFromLocation();
  }

  /// 현재 GoRouter location 을 [_lastObservedLocation] 과 비교하여 `/splash`
  /// 재entry 시 [_triggerReinit] 을 호출한다 (Gap A — quick-260425-01g).
  void _maybeTriggerReinitFromLocation() {
    if (!mounted) return;
    final router = _attachedRouter;
    if (router == null) return;
    final currentLocation = router.routerDelegate.currentConfiguration.uri.path;
    if (_lastObservedLocation != null &&
        _lastObservedLocation != currentLocation &&
        currentLocation == AppRoutes.splash) {
      _triggerReinit();
    }
    _lastObservedLocation = currentLocation;
  }

  /// Splash 재entry 시점에 splashInitializerProvider 를 invalidate 하고
  /// `_runInit` 을 재실행하는 hook (Gap A — quick-260425-01g).
  ///
  /// 호출 경로:
  /// 1. RouterDelegate listener (`_onRouterChanged`) — GC-04 fail-safe redirect
  ///    처럼 GoRouter 가 currentConfiguration 을 갱신한 경우 (1차 신호).
  /// 2. `didChangeDependencies` (`_maybeTriggerReinitFromLocation`) — InheritedWidget
  ///    변경으로 위젯이 dependency 재평가하는 경우 (백업 신호).
  /// 3. `build` 안 `ref.listen(firebaseAuthProvider, ...)` 에서 currentUser 가
  ///    null 로 전이된 경우 (보조 신호).
  ///
  /// `_initInFlight` 가드로 세 경로가 동시에 trigger 해도 race 없음.
  void _triggerReinit() {
    if (_initInFlight) return;
    ref.invalidate(splashInitializerProvider);
    if (mounted) {
      setState(() => _hasFailure = false);
    }
    // invalidate 가 다음 frame 에 적용되도록 한 frame 양보 후 _runInit 재실행.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _runInit();
    });
  }

  Future<void> _runInit() async {
    if (_initInFlight) return;
    _initInFlight = true;
    try {
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
    } finally {
      _initInFlight = false;
    }
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
        // Gap A (quick-260425-01g): GoRouter 의 GC-04 fail-safe redirect 가
        // /splash 에 다시 머물게 만든 경우 RouterDelegate.setNewRoutePath 가
        // 동일 configuration 으로 단락 (short-circuit) 되어 listener 가 발화
        // 하지 않는다. 한 frame 양보 후 현재 location 이 여전히 /splash 이면
        // redirect 가 일어난 것이므로 splashInitializerProvider 를 invalidate
        // 하고 _runInit 을 재실행하여 사용자에게 retry 진입점을 다시 제공한다.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final router = _attachedRouter;
          if (router == null) return;
          final currentLocation =
              router.routerDelegate.currentConfiguration.uri.path;
          if (currentLocation == AppRoutes.splash) {
            _triggerReinit();
          }
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Gap A (quick-260425-01g) 보조 신호: currentUser 가 변하면 (예: 외부
    // logout 또는 익명 세션 만료) splash 재초기화 의미가 있다. RouterDelegate
    // listener 만으로 잡히지 않는 entry 경로 (동일 location 유지 + auth 상태만
    // 변화) 도 커버한다. ref.listen 은 반드시 build 안에서 호출 (Riverpod 규칙).
    //
    // **Phase 1 D-13 가드:** Firebase 미초기화 시 firebaseAuthProvider 는
    // FirebaseAuth.instance 호출에서 throw 한다. isFirebaseInitialized 가
    // true 일 때만 listen 등록.
    final isFirebaseInitialized = ref.watch(isFirebaseInitializedProvider);
    if (isFirebaseInitialized) {
      ref.listen<fb.FirebaseAuth>(firebaseAuthProvider, (prev, next) {
        if (prev != null &&
            prev.currentUser != null &&
            next.currentUser == null &&
            mounted) {
          _triggerReinit();
        }
      });
    }

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
