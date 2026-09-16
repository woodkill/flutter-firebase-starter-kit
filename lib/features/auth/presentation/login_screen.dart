import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_strategies_registry.dart';
import '../../../core/auth/auth_strategy.dart';
import '../../../core/auth/provider_id.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/providers/firebase_providers.dart'
    hide googleSignInProvider;
import '../../../core/router/app_routes.dart';
import '../../../core/theme/theme_extensions.dart';
import '../data/auth_repository.dart' show currentUserProvider;
import '_helpers/social_provider_resolver.dart';
import '_widgets/account_linking_sheet.dart';
import '_widgets/auth_in_progress_overlay.dart';
import '_widgets/auth_scaffold.dart';
import '_widgets/email_auth_cta.dart';
import '_widgets/form_error_banner.dart';
import '_widgets/social_sign_in_section.dart';
import 'login_notifier.dart';
import 'reauth_notifier.dart';

/// 소셜 provider chooser 화면 (Phase 16.1 Surface A).
///
/// 이메일/비밀번호 form 은 본 화면에서 제거되어 `/login/email`
/// ([EmailLoginScreen]) 전용 화면으로 격하됐다 (Phase 16.1 SC 1/2 — Option C).
/// 본 화면은 활성 소셜 provider 버튼 stack + [EmailAuthCta] ("이메일로 계속")
/// + 하단 가입 링크 3요소만 렌더하며, 이메일 진입은 CTA 탭 →
/// [AppRoutes.emailLogin] push 로 위임한다.
///
/// 소셜 로그인은 provider 별 Notifier 가 관리하고 (Phase 8/9/11~15),
/// 결과는 [activeStrategiesProvider] 를 순회하는 단일 `ref.listen` 패턴으로
/// 수신한다. 성공 시 [context.go] 로 Home 이동을 명시적으로 호출한다
/// (Issue #3 safety net) — resolveAuthRedirect 가 정상 동작하면 중복 호출이며,
/// GoRouter redirect 타이밍 경합 시 fallback 으로 동작한다.
/// 실패 시 [FormErrorBanner] 에 inline 으로 표시하고, 이메일 충돌
/// ([AccountExistsWithDifferentCredential]) 은 [AccountLinkingSheet] 로
/// 안내한다 (Phase 16 16-19 2단계 reactive 플로우).
///
/// **재인증 모드 ([isReauth]):** 설정(탈퇴 · 계정 연결)이 `/login?reauth=1` 로
/// push 하면 라우터가 `isReauth: true` 로 만든다. 이때는 일반 로그인 대신
/// 현재 계정 재인증 전용 화면을 그린다 (debug reauth-login-auto-merge, 사용자
/// sign-off Q1~Q7) — 연결된 provider 만 노출하고 `AuthRepository.reauthenticate`
/// 를 호출하며, 가입 링크는 없고, 성공 시 설정으로 돌아가 SnackBar 를 띄운다.
class LoginScreen extends ConsumerStatefulWidget {
  /// [LoginScreen] 을 생성한다.
  const LoginScreen({this.isReauth = false, super.key});

  /// 재인증 모드 여부 — 라우터가 `/login?reauth=1` 표시로 결정한다.
  final bool isReauth;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  /// 소셜 로그인 에러를 소셜 버튼 영역에 표시하기 위한 상태.
  AppException? _socialError;

  /// account-exists 충돌 시 [AccountLinkingSheet] 를 노출한다 (Phase 16 16-08
  /// native arm + 16-19 2단계 reactive 플로우).
  ///
  /// `ref.listen` 콜백 (build 동안) 안에서 직접 `showModalBottomSheet` 를
  /// 호출하면 build 중 navigator 변경 위반이 발생하므로 post-frame callback
  /// 으로 1 frame 미룬다. sheet 가 성공(true) 시 /home 이동은 sheet 가
  /// 직접 담당하므로 (context.go) 본 메서드는 추가 navigation 미수행.
  ///
  /// **2단계 플로우 (16-19):** native + pendingCredential 보존 충돌은 시트가
  /// [AuthRepository.linkPendingNativeCredential] 로 link 하고, 그 외(서버
  /// already-exists / Custom Token) 는
  /// [AuthRepository.signInWithExistingProvider] 로 **기존 provider 에
  /// 로그인**한 뒤 설정 > 계정 연결로 안내한다. naver 는 로그인 대상으로 완전
  /// 지원 (link *target* 만 Phase 17+ 이월) — 본 screen 은 sheet 노출만
  /// 담당한다.
  void _showAccountLinkingSheet(AccountExistsWithDifferentCredential err) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AccountLinkingSheet.show(
        context,
        existingProvider: err.existingProvider!,
        pendingCredential: err.pendingCredential,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // 재인증 모드는 일반 로그인 listener 를 등록하지 않는다 — 같은 route
    // 인스턴스 안에서 isReauth 는 바뀌지 않으므로 조건부 등록이 안전하다.
    if (widget.isReauth) return const _ReauthChooser();
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    // 소셜 OAuth 진행 (Phase 11-04 hotfix UX gap): 외부 인증 복귀 후
    // signInWithCredential / Firestore mirror 동안 화면을 막아 명시적 진행
    // 신호를 제공한다.
    // WR-08 (Phase 7 review): 7 provider 하드코딩 합산을 registry 기반
    // helper 로 대체 — 같은 목록이 3곳에 복제되어 provider 추가 시 한 곳만
    // 갱신되면 이중 제출 잠금이 silent 로 깨졌다.
    final isSocialLoading = watchAnySocialSignInLoading(ref);
    // 이메일 제출 ↔ 소셜 로그인 교차 잠금 (WR-01 — T-07-05 / T-08-60
    // invariant 복원). 이메일 form 은 `/login/email` 로 분리됐지만 그
    // 화면은 chooser **위에** push 되므로 본 화면은 계속 mount 상태이고,
    // 사용자는 제출 진행 중에도 back 으로 chooser 에 복귀할 수 있다.
    // 그 순간 소셜 버튼을 누르면 signInWithEmail 과 signInWith{소셜} 이
    // 동시 in-flight 가 되어 auth state 가 마지막 완료자에 좌우된다.
    // chooser 가 loginProvider 를 watch 하면 (a) autoDispose 인 이 provider
    // 가 push/pop 경계에서 살아남고 (b) 제출 중 소셜 버튼이 비활성화된다.
    final isEmailSubmitting = ref.watch(loginProvider).isLoading;

    // 소셜 로그인 결과 (**등록된 활성 Strategy 전체**): activeStrategiesProvider
    // 가 반환한 활성 Strategy 들을 순회하여 단일 ref.listen 패턴으로 통합한다.
    // IN-03 정정 (Phase 09 review): 이전 주석은 "Google/Apple/Facebook" 3개만
    // 열거했으나 실제로는 registry 전체(기본 7개)를 순회한다 — provider 수를
    // 문장에 박지 않는다 (07 IN-06 에서 채택한 방식 동일).
    // (Phase 11-04 Pattern I, corrections 3번 / Pitfall 6 — 4곳 중 1곳).
    // 성공 -> Home safety net (Issue #3), 에러 -> 배너 + D-10.
    final strategies = ref.watch(activeStrategiesProvider);
    for (final strategy in strategies) {
      ref.listen<AsyncValue<void>>(resolveSocialProvider(strategy.providerId), (
        previous,
        next,
      ) {
        // IN-04 (Phase 09 review): 새 시도가 시작되면 직전 provider 의 실패
        // 배너를 비운다. `_socialError` 는 set 만 있고 clear 가 없어서,
        // Google 실패 배너가 뜬 뒤 Kakao 를 눌러 취소하면 (notifier 는 조용히
        // AsyncData 로 복귀) 화면에는 Google 실패 배너가 그대로 남아 사용자가
        // Kakao 가 실패했다고 오해했다. 이메일 폼 화면들은 제출 시작 시
        // `_emailError = null` 로 반드시 비우므로 그 규약에 일치시킨다.
        if (next is AsyncLoading) {
          if (mounted && _socialError != null) {
            setState(() => _socialError = null);
          }
          return;
        }
        // Issue #3 safety net: AsyncLoading -> AsyncData 전이 + 정식 인증 확인.
        if (previous is AsyncLoading && next is AsyncData) {
          if (!mounted) return;
          final user = ref.read(firebaseAuthProvider).currentUser;
          if (user != null && !user.isAnonymous) {
            context.go(AppRoutes.home);
          }
          return;
        }
        if (next is AsyncError) {
          // WR-04 hotfix: dispose 후 ref.listen 콜백 race 방어.
          if (!mounted) return;
          final err = next.error;
          // Phase 16 16-08 native arm + 16-19 2단계 reactive 플로우 —
          // existingProvider 식별 시 (native + Custom Token 모두)
          // AccountLinkingSheet 노출. native + pendingCredential 보존은
          // sheet 가 linkPendingNativeCredential, 그 외는
          // signInWithExistingProvider 로 **기존 provider 에 로그인** (step
          // 1) 후 설정 > 계정 연결 안내 (step 2). naver 도 로그인 대상으로
          // 정상 수행된다.
          // existingProvider == null (unknown) 만 FormErrorBanner inline 으로
          // fallback (R2 회귀 0).
          if (err is AccountExistsWithDifferentCredential &&
              err.existingProvider != null) {
            _showAccountLinkingSheet(err);
            return;
          }
          // IN-07 (Phase 09 review): `is AppException` 는 현재 항상 참인
          // dead guard 다 (Result.failure 시그니처가 AppException 으로
          // 제한되므로). 문제는 방어의 **방향**이다 — 조건이 거짓이 되는 날
          // (예: 향후 notifier 가 raw 예외를 싣는 변경) 배너도 로그도 없이
          // 조용히 사라진다. verify_email_screen.dart 가 이미 쓰는 fallback
          // 패턴으로 통일해 에러가 무음 폐기되지 않게 한다.
          setState(() {
            _socialError = err is AppException
                ? err
                : ServiceUnavailable(cause: err);
          });
        }
      });
    }

    return Stack(
      children: <Widget>[
        AuthScaffold(
          title: l10n.authLoginTitle,
          // push 로 연 경우(홈 데모 · 탈퇴/계정 연결 재인증)만 AppBar 가 표준
          // 뒤로가기를 그린다. go 루트 교체 · 딥링크 · 최초 진입에서는 AppBar 가
          // 스스로 숨긴다 (R_EXTRA_G2_IOS_BACK_NAV).
          showBackButton: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Gap(spacing.xxl),
              // 본 화면에 이메일 form 은 없지만 (Phase 16.1 SC 1) `/login/email`
              // 제출이 진행 중이면 소셜 버튼을 잠근다 (WR-01). "또는" divider
              // 는 소셜 섹션의 기본값 (표시) 을 그대로 쓰며 명시 지정하지
              // 않는다 (Sketch 003 winner A — divider 유지).
              SocialSignInSection(
                isFormLoading: isEmailSubmitting,
                errorBanner: FormErrorBanner(exception: _socialError),
              ),
              // WR-08 — 소셜 OAuth 진행 중에는 null 을 넘겨 disabled 시각·
              // 시맨틱을 AuthInProgressOverlay 의 탭 차단과 일치시킨다.
              EmailAuthCta(
                // 재인증 표시 전달 (R_EXTRA_G3_REAUTH_LOGIN_BOUNCE). GoRouterState
                // 는 탭 시점에만 읽는다 — build 에서 읽으면 GoRouter 없이 pump
                // 하는 화면 테스트가 GoError 로 깨진다.
                onPressed: isSocialLoading
                    ? null
                    : () => context.push(
                        AppRoutes.forwardReauthMarker(
                          AppRoutes.emailLogin,
                          from: GoRouterState.of(context).uri,
                        ),
                      ),
              ),
              Gap(spacing.sm),
              TextButton(
                onPressed: () => context.push(
                  AppRoutes.forwardReauthMarker(
                    AppRoutes.signup,
                    from: GoRouterState.of(context).uri,
                  ),
                ),
                child: Text(l10n.authLoginNoAccount),
              ),
            ],
          ),
        ),
        if (isSocialLoading) const AuthInProgressOverlay(),
      ],
    );
  }
}

/// 재인증 모드 선택 화면 (debug reauth-login-auto-merge).
///
/// 사용자 sign-off 된 렌더(Q1~Q7)의 구조를 그대로 따른다 — 제목 · 안내 문구 ·
/// 현재 계정에 연결된 소셜 버튼 · (비밀번호 연결 시) divider + 「이메일로
/// 계속」. 가입 링크는 없다 (새 계정 생성 = 다른 계정 전환).
///
/// - 버튼 탭 → [SocialReauthNotifier] → `AuthRepository.reauthenticate`.
/// - 성공 → SnackBar(`authReauthSucceeded`) + 이전 화면(설정)으로 pop (Q6).
///   SnackBar 는 root [ScaffoldMessenger] 에 띄우므로 pop 뒤 설정 화면에 남는다.
/// - 취소 → 이동 없음. 실패 → 인라인 [FormErrorBanner] (다른 계정 = Q2 문구).
/// - 쓸 수 있는 수단 0 → [ReauthMethodUnavailable] 배너 (Q7). 연결 안 된
///   provider 를 대안으로 노출하지 않는다.
///
/// 오류가 없을 때 배너 자리를 `null` 로 넘겨 (빈 [FormErrorBanner] 대신)
/// 승인 렌더와 같은 간격을 유지한다.
class _ReauthChooser extends ConsumerStatefulWidget {
  const _ReauthChooser();

  @override
  ConsumerState<_ReauthChooser> createState() => _ReauthChooserState();
}

class _ReauthChooserState extends ConsumerState<_ReauthChooser> {
  /// 마지막 소셜 재인증 실패. 새 시도가 시작되면 비운다.
  AppException? _error;

  void _onStrategyPressed(AuthStrategy strategy) {
    final provider = AccountProvider.tryParse(strategy.providerId);
    if (provider == null) return;
    ref.read(socialReauthProvider.notifier).reauthenticate(provider);
  }

  /// 비밀번호 재인증 화면을 열고, 성공(`true`) 으로 돌아오면 완료 처리한다.
  ///
  /// 이메일 화면이 직접 설정까지 pop 하지 않는 이유: 선택 화면이 완료 처리
  /// (SnackBar + pop) 단일 지점이어야 두 화면이 같은 성공 신호로 이중 이동하지
  /// 않는다.
  Future<void> _openPasswordReauth() async {
    final isReauthenticated = await context.push<bool>(
      AppRoutes.buildReauthLocation(AppRoutes.emailLogin),
    );
    if (!mounted || isReauthenticated != true) return;
    _completeReauth();
  }

  /// 재인증 완료 — SnackBar 후 재인증을 요청한 화면으로 돌아간다 (Q6).
  void _completeReauth() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.authReauthSucceeded)));
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop(true);
    } else {
      // 딥링크 등으로 루트에서 열린 예외 경로 — 돌아갈 화면이 없다.
      context.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    final methods = resolveReauthMethods(
      ref.watch(currentUserProvider),
      ref.watch(activeStrategiesProvider),
    );
    final isSocialLoading = ref.watch(socialReauthProvider).isLoading;
    // 이메일 화면은 본 화면 위에 push 되므로, 제출 중 뒤로 와도 소셜 버튼이
    // 잠겨 있어야 한다 (일반 로그인 WR-01 교차 잠금과 같은 이유).
    final isPasswordSubmitting = ref.watch(passwordReauthProvider).isLoading;

    ref.listen<AsyncValue<bool>>(socialReauthProvider, (previous, next) {
      if (next is AsyncLoading) {
        if (mounted && _error != null) setState(() => _error = null);
        return;
      }
      if (previous is AsyncLoading && next is AsyncData<bool>) {
        if (!mounted) return;
        if (next.value) _completeReauth();
        return;
      }
      if (next is AsyncError) {
        if (!mounted) return;
        final err = next.error;
        setState(() {
          _error = err is AppException ? err : ServiceUnavailable(cause: err);
        });
      }
    });

    final hasAnyMethod = methods.strategies.isNotEmpty || methods.hasPassword;
    final bannerException = hasAnyMethod
        ? _error
        : const ReauthMethodUnavailable();
    final banner = bannerException == null
        ? null
        : FormErrorBanner(exception: bannerException);

    return Stack(
      children: <Widget>[
        AuthScaffold(
          title: l10n.authReauthTitle,
          showBackButton: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Gap(spacing.xxl),
              Text(
                l10n.authReauthGuide,
                style: context.appTypography.bodyMedium.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
              Gap(spacing.lg),
              if (methods.strategies.isNotEmpty)
                SocialSignInSection(
                  isFormLoading: isSocialLoading || isPasswordSubmitting,
                  errorBanner: banner,
                  showOrDivider: methods.hasPassword,
                  strategies: methods.strategies,
                  onStrategyPressed: _onStrategyPressed,
                )
              else
                ?banner,
              if (methods.hasPassword)
                EmailAuthCta(
                  onPressed: isSocialLoading ? null : _openPasswordReauth,
                ),
            ],
          ),
        ),
        if (isSocialLoading) const AuthInProgressOverlay(),
      ],
    );
  }
}
