import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_strategies_registry.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/providers/firebase_providers.dart'
    hide googleSignInProvider;
import '../../../core/router/app_routes.dart';
import '../../../core/theme/theme_extensions.dart';
import '_helpers/social_provider_resolver.dart';
import '_widgets/account_linking_sheet.dart';
import '_widgets/auth_in_progress_overlay.dart';
import '_widgets/auth_scaffold.dart';
import '_widgets/email_field.dart';
import '_widgets/form_error_banner.dart';
import '_widgets/password_field.dart';
import '_widgets/primary_cta.dart';
import '_widgets/social_sign_in_section.dart';
import 'apple_sign_in_notifier.dart';
import 'facebook_sign_in_notifier.dart';
import 'google_sign_in_notifier.dart';
import 'kakao_sign_in_notifier.dart';
import 'line_sign_in_notifier.dart';
import 'login_notifier.dart';
import 'naver_sign_in_notifier.dart';
import 'yahoojp_sign_in_notifier.dart';

/// 이메일/비밀번호 + Google + Apple + Facebook 로그인 화면 (D-01, D-04, D-05).
///
/// 폼 제출 결과는 [LoginNotifier] 가 [AsyncValue] (void) 로 노출하고,
/// Google 로그인은 [GoogleSignInNotifier], Apple 로그인은
/// [AppleSignInNotifier], Facebook 로그인은 [FacebookSignInNotifier] 가
/// 별도 관리한다 (D-03, D-13, Phase 8, Phase 9).
/// 소셜 로그인 성공 시 [context.go] 로 Home 이동을 명시적으로 호출한다
/// (Issue #3 safety net). authRedirect 가 정상 동작하면 중복 호출이며,
/// GoRouter redirect 타이밍 경합 시 fallback 으로 동작한다.
/// 이메일 로그인 성공 시에도 [context.go] 로 Home 이동을 명시적으로 호출한다
/// (Issue #5 safety net). emailVerified=false 인 신규 가입 직후 race 는
/// 분기 (4) /verify-email redirect 에 위임한다 (D-05 + Plan 10-08 패턴).
/// 실패 시 [FormErrorBanner] 에 inline 으로 표시한다.
/// 이메일 충돌(D-10) 시 이메일 자동 채움 + 포커스 이동 (Google/Apple 공통).
class LoginScreen extends ConsumerStatefulWidget {
  /// [LoginScreen] 을 생성한다.
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  /// 소셜 로그인(Google/Apple/Facebook) 에러를 소셜 버튼 영역에 표시하기 위한 상태.
  AppException? _socialError;

  /// 이메일/비밀번호 로그인 에러를 이메일 필드 영역에 표시하기 위한 상태.
  AppException? _emailError;

  /// Phase 10 D-31 / WARNING #12 : `?focus=email` 쿼리로 진입 시 이메일
  /// 필드에 자동 포커스를 1회만 적용하도록 재호출 방지 플래그.
  bool _didFocusFromQuery = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didFocusFromQuery) return;
    // Phase 10 D-31 / WARNING #12: Bottom Sheet "이메일로 계속" 진입 시
    // 이메일 필드에 자동 포커스 + 스크롤 보장.
    //
    // T-10-27 방어: `focus == 'email'` 단일 값만 검사하므로 임의 쿼리
    // 주입으로 다른 위젯에 포커스를 강제할 수 없다.
    //
    // 기존 테스트 (MaterialApp.home 직접 주입) 호환: GoRouter 가 위젯 트리
    // 상위에 없으면 GoRouterState.of 는 GoError(Error 서브클래스) 를 throw.
    // WR-03: `on Object` 로 모든 예외를 삼키되 debug 빌드에서는 원인을
    // debugPrint 로 남겨 localization delegate race 등 비정상 케이스를
    // 숨기지 않도록 한다.
    final GoRouterState state;
    try {
      state = GoRouterState.of(context);
    } on Object catch (e) {
      if (kDebugMode) {
        debugPrint(
          'LoginScreen.didChangeDependencies: GoRouterState.of 실패 (무시): $e',
        );
      }
      return;
    }
    if (state.uri.queryParameters['focus'] != 'email') return;
    _didFocusFromQuery = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _emailFocus.requestFocus();
      final ctx = _emailFocus.context;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.3,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// 폼 제출 핸들러.
  ///
  /// Google/Apple/Facebook 로그인 진행 중이면 제출을 차단한다 (T-07-05, T-08-60).
  /// validator 통과 시 키보드를 내리고 [LoginNotifier.submit] 을 호출한다.
  /// 성공 + emailVerified 시 [context.go] 로 Home 이동을 명시적으로 호출한다
  /// (Issue #5 safety net — Plan 10-08 패턴 확장). emailVerified=false 인
  /// 신규 가입 직후 race 에서는 분기 (4) /verify-email redirect 에 위임한다.
  Future<void> _handleSubmit() async {
    if (ref.read(googleSignInProvider).isLoading) return;
    if (ref.read(appleSignInProvider).isLoading) return;
    if (ref.read(facebookSignInProvider).isLoading) return;
    if (ref.read(kakaoSignInProvider).isLoading) return;
    if (ref.read(naverSignInProvider).isLoading) return;
    if (ref.read(lineSignInProvider).isLoading) return;
    if (ref.read(yahoojpSignInProvider).isLoading) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      // 이메일 에러만 reset — 소셜 에러는 사용자가 직접 다음 소셜 시도로
      // 갱신하거나 email submit 성공 후 Home navigate 으로 자연 dismiss 될
      // 때까지 보존한다 (Phase 9.2 R2 / Path A-narrow recovery prompt
      // 의무 — CR-01). loginProvider AsyncError 리스너 (line 186-196) 가
      // 이메일 실패 시 _socialError = null 로 갱신하므로 이메일 성공 후
      // Home 이동 직전까지만 소셜 배너가 유지된다.
      _emailError = null;
    });
    await ref
        .read(loginProvider.notifier)
        .submit(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
    // 본 메서드의 state 전이 (성공 시 Home navigate, 실패 시 _emailError
    // 배너 갱신) 는 build() 안 ref.listen<AsyncValue<void>>(loginProvider)
    // 가 담당하므로 await 후 setState / context 호출 미필요.
    //
    // 만약 향후 post-await 액션 (setState / context.go / context.push 등)
    // 을 추가한다면 그 줄 바로 위에 `if (!mounted) return;` 가드를 새로
    // 배치할 것 — 본 위치에 mounted 가드를 미리 두는 dead-defense 패턴은
    // use_build_context_synchronously 린트 가 새 가드 누락을 감지할 수
    // 있도록 의도적으로 제거 (WR-05).
  }

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
        collisionEmail: err.email ?? '',
        pendingCredential: err.pendingCredential,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    final state = ref.watch(loginProvider);
    final googleState = ref.watch(googleSignInProvider);
    final appleState = ref.watch(appleSignInProvider);
    final facebookState = ref.watch(facebookSignInProvider);
    final kakaoState = ref.watch(kakaoSignInProvider);
    final naverState = ref.watch(naverSignInProvider);
    final lineState = ref.watch(lineSignInProvider);
    final yahoojpState = ref.watch(yahoojpSignInProvider);
    // 소셜 OAuth 진행 (Phase 11-04 hotfix UX gap): 외부 인증 복귀 후
    // signInWithCredential / Firestore mirror 동안 화면을 막아 명시적 진행
    // 신호를 제공한다. Phase 12 — kakaoState 합산 (D-25 / 12-UI-SPEC),
    // Phase 13 — naverState 합산 (Plan 13-06 / 13-UI-SPEC),
    // Phase 14 — lineState 합산 (Plan 14-05 / SOCL-03),
    // Phase 15 — yahoojpState 합산 (Plan 15-03 / SOCL-04).
    final isSocialLoading =
        googleState.isLoading ||
        appleState.isLoading ||
        facebookState.isLoading ||
        kakaoState.isLoading ||
        naverState.isLoading ||
        lineState.isLoading ||
        yahoojpState.isLoading;
    final isLoading = state.isLoading || isSocialLoading;

    // 이메일/비밀번호 로그인 결과: 성공 + emailVerified -> Home safety net
    // (Issue #5 — Plan 10-08 패턴 확장), 에러 -> _emailError 배너.
    ref.listen<AsyncValue<void>>(loginProvider, (previous, next) {
      // Issue #5 safety net: AsyncLoading -> AsyncData 전이 + 정식 인증 +
      // emailVerified 가드. emailVerified=false 인 신규 가입 직후 race 에서는
      // 분기 (4) /verify-email redirect 가 우선되어야 하므로 Home 이동 차단.
      if (previous is AsyncLoading && next is AsyncData) {
        if (!mounted) return;
        final user = ref.read(firebaseAuthProvider).currentUser;
        if (user != null && !user.isAnonymous && user.emailVerified) {
          context.go(AppRoutes.home);
        }
        return;
      }
      if (next is AsyncError) {
        // WR-04 hotfix: dispose 후 ref.listen 콜백 race 방어.
        if (!mounted) return;
        final err = next.error;
        if (err is AppException) {
          setState(() {
            _emailError = err;
            _socialError = null;
          });
        }
      }
    });

    // 소셜 로그인 결과 (Google/Apple/Facebook): activeStrategiesProvider 가
    // 반환한 활성 Strategy 들을 순회하여 단일 ref.listen 패턴으로 통합한다
    // (Phase 11-04 Pattern I, corrections 3번 / Pitfall 6 — 4곳 중 1곳).
    // 성공 -> Home safety net (Issue #3), 에러 -> 배너 + D-10.
    final locale = Localizations.localeOf(context);
    final strategies = ref.watch(activeStrategiesProvider(locale));
    for (final strategy in strategies) {
      ref.listen<AsyncValue<void>>(
        resolveSocialProvider(strategy.providerId),
        (previous, next) {
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
            if (err is AppException) {
              setState(() {
                _socialError = err;
                _emailError = null;
              });
            }
          }
        },
      );
    }

    return Stack(
      children: <Widget>[
        AuthScaffold(
          title: l10n.authLoginTitle,
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Gap(spacing.xxl),
                  SocialSignInSection(
                    isFormLoading: state.isLoading,
                    errorBanner: FormErrorBanner(exception: _socialError),
                  ),
                  EmailField(
                    controller: _emailController,
                    focusNode: _emailFocus,
                    onSubmitted: (_) => _passwordFocus.requestFocus(),
                  ),
                  Gap(spacing.md),
                  PasswordField(
                    controller: _passwordController,
                    focusNode: _passwordFocus,
                    isNewPassword: false,
                    onSubmitted: (_) => _handleSubmit(),
                  ),
                  Gap(spacing.md),
                  FormErrorBanner(exception: _emailError),
                  Gap(spacing.xl),
                  PrimaryCta(
                    label: l10n.authLoginCta,
                    isLoading: isLoading,
                    onPressed: _handleSubmit,
                  ),
                  Gap(spacing.md),
                  TextButton(
                    onPressed: () => context.push(AppRoutes.forgotPassword),
                    child: Text(l10n.authLoginForgotPassword),
                  ),
                  Gap(spacing.sm),
                  TextButton(
                    onPressed: () => context.push(AppRoutes.signup),
                    child: Text(l10n.authLoginNoAccount),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (isSocialLoading) const AuthInProgressOverlay(),
      ],
    );
  }
}
