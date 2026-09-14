import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

import '../../../core/crashlytics/crashlytics_service.dart';
import '../../../core/error/result.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/theme_extensions.dart';
import 'splash_error_code.dart';
import 'splash_initializer.dart';

/// 스플래시 로고 자산 경로 (IN-02 — 프로젝트별 커스터마이징 포인트).
///
/// 다른 로고로 교체하려면 `assets/images/splash/` 아래에 동일 경로의 PNG 를
/// 배치하거나 본 상수를 갱신한다. Image.asset 본체와 [Image.errorBuilder]
/// 양쪽에서 공유한다.
const String _kLogoAsset = 'assets/images/splash/logo.png';

/// 스플래시 로고 변/높이 (logical pixel, IN-02 — 프로젝트별 커스터마이징 포인트).
///
/// 디자인 시스템 변경 시 본 값만 갱신하면 정상 표시 + 에러 placeholder
/// 양쪽이 동기된다.
const double _kLogoSize = 128.0;

/// 앱 스플래시 화면 (Phase 10 AUTH-08, D-22, D-25, WARNING #13).
///
/// 흐름:
/// 1. [SplashInitializer.initialize] 호출 -> 최소 표시 시간 대기 + 필요 시
///    `signInAnonymously`.
/// 2. 성공 -> [context.go]([AppRoutes.home]) -> [resolveAuthRedirect] 가 최종 경로
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

  /// 오프라인 분기 fail-safe 재entry 카운터 (WR-04).
  ///
  /// "Sign in later" → `/login` → (예상치 못한 redirect 로 인한) `/splash`
  /// 복귀 시 `_triggerReinit` 을 1회까지만 발동한다. 카운터가 1 이상이면
  /// 후속 addPostFrameCallback 자체를 스킵해 다이얼로그 → 오프라인 →
  /// /splash 무한 루프를 차단한다. `_runInit` 성공 시 0 으로 리셋되어
  /// 정상 세션에서는 다음 splash 진입까지 영향이 없다.
  int _offlineFallbackReentryCount = 0;

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
    // IN-05: 초기 null 은 initState 의 addPostFrameCallback 이 별도로 _runInit
    // 을 트리거함 — 본 분기는 재entry (다른 location 으로 갔다가 /splash 복귀)
    // 만 담당. 향후 initState 의 트리거를 옮기는 리팩토링 시 본 가드도 함께
    // 점검해야 첫 init 이 누락되지 않는다.
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
  /// 3. `build` 안 `ref.listen(authStateProvider, ...)` 에서 auth 스트림이
  ///    `User -> null` 로 전이한 경우 (보조 신호 — quick 260914-f1p 로 listen
  ///    대상 교체, 근거는 Phase 16 deferred-items 항목 1).
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
    // 10-REVIEW CR-02: catch 안에서 provider 를 읽으면 위젯이 이미 해체된
    // 경우 그 ref.read 자체가 StateError 를 던져 새 누출 경로가 된다.
    // try 진입 전에 핸들을 담을 지역 변수를 두고 try 본체 첫 줄에서 캡처한다
    // (캡처가 실패하면 null 로 남아 emit 을 생략 — best-effort).
    CrashlyticsService? crashlytics;
    try {
      crashlytics = ref.read(crashlyticsServiceProvider);
      final initializer = ref.read(splashInitializerProvider);
      final result = await initializer.initialize();
      if (!mounted) return;
      if (result is Failure<void>) {
        setState(() => _hasFailure = true);
        // WR-03: SplashInitializer 와 동일한 [extractSplashErrorCode] 사용.
        final code = extractSplashErrorCode(result.exception);
        await _showFailureDialog(code);
        return;
      }
      if (!mounted) return;
      // WR-04: 정상 진행 시 fail-safe 카운터 리셋 — 새 splash 세션 (예: 로그아웃
      // 후 재진입) 에서 다시 1회 fail-safe 가 허용된다.
      _offlineFallbackReentryCount = 0;
      context.go(AppRoutes.home);
    } on Object catch (e, st) {
      // 10-REVIEW CR-02: Result.failure 가 아닌 예상 외 throw 도 사용자에게
      // 탈출구를 제공한다 (무한 스피너 금지 — 재설치 외 탈출 경로가 없었다).
      // 코드는 타입명만 노출한다 — extractSplashErrorCode 는 AppException 만
      // 받으므로 임의 throw 에 쓸 수 없고, runtimeType 문자열은 PII 를
      // 포함하지 않는다 (T-x0r-04).
      //
      // IN-02: `--obfuscate` 빌드에서는 이 타입명이 난독화되어 fingerprint
      // 가치를 잃는다 — extractSplashErrorCode 의 doc 에 적힌 교체 지침을
      // 따를 것.
      final emitFuture = crashlytics?.recordError(
        e,
        st,
        reason: 'splash_init_threw',
      );
      if (emitFuture != null) {
        unawaited(emitFuture);
      }
      if (!mounted) return;
      setState(() => _hasFailure = true);
      await _showFailureDialog(e.runtimeType.toString());
    } finally {
      _initInFlight = false;
    }
  }

  /// 오류 코드 fingerprint 를 클립보드에 복사하고 SnackBar 로 안내한다
  /// (D-10 / D-12 / WR-19).
  ///
  /// [messenger] 는 **outer SplashScreen** 의 ScaffoldMessenger 여야 한다 —
  /// dialogContext 의 messenger 는 dialog overlay 하위라 SnackBar 가 가려진다
  /// (Phase 10.1 Pattern D / Risk R5).
  ///
  /// 클립보드 payload 는 `splash_auto_signin: <code>` 형식이며 code 외의
  /// 정보(단말 주소 / SDK message)는 포함하지 않는다 (D-10 PII invariant).
  Future<void> _copyErrorCode(
    String code,
    ScaffoldMessengerState messenger,
  ) async {
    await Clipboard.setData(ClipboardData(text: 'splash_auto_signin: $code'));
    // mounted 가드 — async gap 동안 위젯이 해체됐을 수 있음.
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(context.l10n.commonCopied)));
  }

  Future<void> _showFailureDialog(String code) async {
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    final colorScheme = context.colorScheme;
    final typography = context.appTypography;
    // Phase 10.1 Pattern D / T-10.1-02 mitigation: outer SplashScreen 의
    // context 를 다이얼로그 빌더 이전 시점에 캡처. dialogContext 의
    // ScaffoldMessenger 는 dialog overlay 상위라 SnackBar 가 가려지므로,
    // tap-to-copy SnackBar 는 반드시 outer messenger 로 표시한다 (Risk R5).
    final outerMessenger = ScaffoldMessenger.of(context);
    final selected = await showDialog<_SplashFailureAction>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          icon: Icon(Icons.cloud_off, color: colorScheme.onErrorContainer),
          iconColor: colorScheme.errorContainer,
          title: Text(l10n.splashFailureTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.splashFailureMessage),
              Gap(spacing.sm),
              // WR-19: InkWell 이 일반 Text 만 감싸면 스크린 리더 사용자는 이
              // 문구가 탭 가능한 복사 액션임을 알 수 없다. 오류 리포팅 경로라
              // 접근성 영향이 실질적이다. 기존 ARB 키만으로 button role 과
              // 액션 의미를 부여한다 (신규 ARB 키 0).
              //
              // container/excludeSemantics 를 함께 지정해야 라벨이 자체 노드로
              // 선다 — 미지정 시 자식 Text 노드와 라벨이 중복 병합된다
              // (danger_zone_section.dart 의 동일 패턴 mirror). 탭 액션은
              // Semantics.onTap 과 InkWell.onTap 양쪽이 같은 핸들러를 공유한다.
              Semantics(
                container: true,
                excludeSemantics: true,
                button: true,
                label: l10n.splashErrorCodeFingerprint(code),
                onTap: () => unawaited(_copyErrorCode(code, outerMessenger)),
                child: InkWell(
                  onTap: () => _copyErrorCode(code, outerMessenger),
                  child: Text(
                    l10n.splashErrorCodeFingerprint(code),
                    style: typography.bodySmall.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
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
        // CR-01: 외곽 `_runInit` 의 `finally` 가 아직 `_initInFlight = true` 인
        // 시점에 본 분기가 실행된다. 여기서 `_runInit` 을 재귀 호출하면
        // 재entry 가드 `if (_initInFlight) return;` 가 즉시 단락시켜 retry 가
        // no-op 가 된다. 한 frame 양보 후 — 즉 외곽 `_runInit` 의 `finally`
        // 가 `_initInFlight` 를 false 로 리셋한 다음 — 새 init 을 트리거한다.
        // `_hasFailure` 리셋도 새 init 시작 직전에 수행한다.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() => _hasFailure = false);
          _runInit();
        });
      case _SplashFailureAction.offline:
      case null:
        if (!mounted) return;
        // Phase 10.1 D-05: '/home' → '/login' 변경 — 익명 UID 부재 시 사용자가
        // 직접 로그인 액션 선택 (D-06 _unauthRoutes 자연 호환, GC-04 trigger
        // 안 됨). 아래 Gap A fail-safe 의미는 약화되었으나 다른 redirect path
        // 등장 시 안전망 보존 (PATTERNS §2.1).
        context.go(AppRoutes.login);
        // WR-04: 다이얼로그 → 오프라인 → /splash 무한 루프 방지. fail-safe
        // 재진입은 splash 세션 동안 1회로 제한 (1회 후에는 사용자가 /login
        // 화면에서 직접 retry/sign-in 액션 선택). `_runInit` 성공 시 카운터
        // 리셋되어 다음 splash 세션에는 영향 없음.
        if (_offlineFallbackReentryCount >= 1) return;
        _offlineFallbackReentryCount++;
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
    // Gap A (quick-260425-01g) 보조 신호 — 대상 교체: quick 260914-f1p.
    // `authStateProvider` (`FirebaseAuth.userChanges` 래핑 스트림) 에서
    // **사용자 소멸 전이**(User -> null) 를 관측해 splash 재초기화를 발동한다.
    // RouterDelegate listener 만으로 잡히지 않는 entry 경로 (동일 location
    // 유지 + auth 상태만 변화) 를 커버하려는 의도는 그대로다. ref.listen 은
    // 반드시 build 안에서 호출 (Riverpod 규칙).
    //
    // 옛 대상 `firebaseAuthProvider` 는 싱글톤 인스턴스를 반환해 값이 한 번도
    // 바뀌지 않았고(콜백 미호출), 설령 호출됐더라도 prev 와 next 가 같은
    // 객체라 전이 조건이 동시에 참이 될 수 없어 두 겹으로 죽어 있었다. 근거 =
    // `.planning/phases/16-account-linking-withdrawal/deferred-items.md`
    // 항목 1 (2026-09-13 실 단말 재현).
    //
    // 판정 규칙 — prev/next 양쪽에서 `hasValue` 를 함께 본다. [AsyncValue.value]
    // 는 loading/error 상태에서 **직전 값을 반환**하므로, hasValue 를 같이
    // 보면 (a) 최초 로딩 프레임(값 이력 없음)과 (b) 사용자 보유 중의 일시적
    // loading/error(직전 user 유지) 가 둘 다 로그아웃으로 오인되지 않는다.
    // (Riverpod 3.2.1 에 `valueOrNull` 게터는 없다 — `hasValue` + `value`.)
    //
    // **Phase 1 D-13 가드가 여기에 없는 이유 (의도적 제거):**
    // (i) `authStateProvider` 가 스스로 `isFirebaseInitializedProvider` 를
    // watch 해 미초기화 시 빈 스트림을 반환하므로(`firebase_providers.dart`
    // 97-98행) `FirebaseAuth.instance` 접근이 던지는 `[core/no-app]` 는 이
    // 경로로 도달 불가다 — 가드가 중복이다. (ii) 조건부 ref.listen 은 조건이
    // 거짓인 동안 구독이 조용히 사라지는 형태이며, 그것이 바로 본 수정이
    // 제거하려는 「죽은 훅」 부류다.
    ref.listen<AsyncValue<fb.User?>>(authStateProvider, (prev, next) {
      if (prev != null &&
          prev.hasValue &&
          prev.value != null &&
          next.hasValue &&
          next.value == null &&
          mounted) {
        _triggerReinit();
      }
    });

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
                _kLogoAsset,
                width: _kLogoSize,
                height: _kLogoSize,
                errorBuilder: (_, _, _) =>
                    const SizedBox(width: _kLogoSize, height: _kLogoSize),
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
