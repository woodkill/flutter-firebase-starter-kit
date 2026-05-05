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
import 'naver_sign_in_notifier.dart';
import 'signup_notifier.dart';

/// 이메일/비밀번호 + Google + Apple + Facebook 회원가입 화면 (D-01, D-04, D-05).
///
/// 폼 필드 3종(displayName / email / password) + Form validation +
/// [SignupNotifier] 위임 구조로 동작한다. Google 로그인은
/// [GoogleSignInNotifier], Apple 로그인은 [AppleSignInNotifier],
/// Facebook 로그인은 [FacebookSignInNotifier] 가 별도 관리한다
/// (D-03, D-13, Phase 8, Phase 9).
/// 소셜 로그인 성공 시 [context.go] 로 Home 이동을 명시적으로 호출한다
/// (Issue #3 safety net). authRedirect 가 정상 동작하면 중복 호출이며,
/// GoRouter redirect 타이밍 경합 시 fallback 으로 동작한다.
/// 이메일 가입 성공 시에는 authRedirect 에 위임한다 (D-05).
/// 실패 시 [FormErrorBanner] 에 inline 으로 표시한다. 이메일 자동 채움은
/// LoginScreen에만 적용하고 SignupScreen은 에러 배너만 표시한다.
class SignupScreen extends ConsumerStatefulWidget {
  /// [SignupScreen] 을 생성한다.
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  /// 소셜 로그인(Google/Apple/Facebook) 에러를 소셜 버튼 영역에 표시하기 위한 상태.
  AppException? _socialError;

  /// 이메일/비밀번호 가입 에러를 이메일 필드 영역에 표시하기 위한 상태.
  AppException? _emailError;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _nameFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  /// displayName validator (D-22).
  ///
  /// 트림 후 빈 값은 [errorDisplayNameRequired], 32자 초과는
  /// [errorDisplayNameTooLong] 키를 반환한다.
  String? _validateDisplayName(String? value) {
    final l10n = context.l10n;
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) return l10n.errorDisplayNameRequired;
    if (trimmed.length > 32) return l10n.errorDisplayNameTooLong;
    return null;
  }

  /// 폼 제출 핸들러.
  ///
  /// Google/Apple/Facebook 로그인 진행 중이면 제출을 차단한다 (T-07-05, T-08-60).
  /// validator 통과 시 키보드를 내리고 [SignupNotifier.submit] 을 호출한다.
  /// 성공/실패 전이는 [ref.listen] 으로 감시되며 이메일 가입 성공 시
  /// navigation 은 authRedirect 에 위임한다 (D-05).
  Future<void> _handleSubmit() async {
    if (ref.read(googleSignInProvider).isLoading) return;
    if (ref.read(appleSignInProvider).isLoading) return;
    if (ref.read(facebookSignInProvider).isLoading) return;
    if (ref.read(kakaoSignInProvider).isLoading) return;
    if (ref.read(naverSignInProvider).isLoading) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _socialError = null;
      _emailError = null;
    });
    await ref
        .read(signupProvider.notifier)
        .submit(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          displayName: _nameController.text.trim(),
        );
    // defense-in-depth: await 후 setState/context 호출이 추가될 경우를
    // 대비해 mounted 가드를 미리 배치한다 (WR-02).
    if (!mounted) return;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    final state = ref.watch(signupProvider);
    final googleState = ref.watch(googleSignInProvider);
    final appleState = ref.watch(appleSignInProvider);
    final facebookState = ref.watch(facebookSignInProvider);
    final kakaoState = ref.watch(kakaoSignInProvider);
    final naverState = ref.watch(naverSignInProvider);
    // 소셜 OAuth 진행 (Phase 11-04 hotfix UX gap): LoginScreen 과 동일한
    // 화면 전체 오버레이 패턴. Phase 12 — kakaoState 합산,
    // Phase 13 — naverState 합산 (Plan 13-06).
    final isSocialLoading =
        googleState.isLoading ||
        appleState.isLoading ||
        facebookState.isLoading ||
        kakaoState.isLoading ||
        naverState.isLoading;
    final isLoading = state.isLoading || isSocialLoading;

    // 이메일/비밀번호 가입 에러 → _emailError (이메일 필드 영역 배너).
    //
    // Issue #5 safety net 미적용 (의도적 — Plan 10-09): 신규 가입 직후
    // emailVerified=false 가 일반적이며, authRedirect 분기 (4) 가
    // /verify-email 로 강제 리다이렉트한다. safety net 을 추가하면 분기 (4)
    // 와 충돌하여 깜빡임이 발생한다 (LoginScreen 의 emailVerified 가드와
    // 다른 결정 — SignupScreen 은 emailVerified=false race 가 정상 흐름).
    ref.listen<AsyncValue<void>>(signupProvider, (previous, next) {
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
    // SignupScreen은 이메일 자동 채움(D-10)을 적용하지 않는다.
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
          title: l10n.authSignupTitle,
          showBackButton: true,
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
                  TextFormField(
                    controller: _nameController,
                    focusNode: _nameFocus,
                    autofillHints: const [AutofillHints.name],
                    keyboardType: TextInputType.name,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: l10n.authSignupDisplayNameLabel,
                    ),
                    validator: _validateDisplayName,
                    onFieldSubmitted: (_) => _emailFocus.requestFocus(),
                  ),
                  Gap(spacing.md),
                  EmailField(
                    controller: _emailController,
                    focusNode: _emailFocus,
                    onSubmitted: (_) => _passwordFocus.requestFocus(),
                  ),
                  Gap(spacing.md),
                  PasswordField(
                    controller: _passwordController,
                    focusNode: _passwordFocus,
                    isNewPassword: true,
                    onSubmitted: (_) => _handleSubmit(),
                  ),
                  Gap(spacing.md),
                  FormErrorBanner(exception: _emailError),
                  Gap(spacing.xl),
                  PrimaryCta(
                    label: l10n.authSignupCta,
                    isLoading: isLoading,
                    onPressed: _handleSubmit,
                  ),
                  Gap(spacing.md),
                  TextButton(
                    onPressed: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.push(AppRoutes.login);
                      }
                    },
                    child: Text(l10n.authSignupHasAccount),
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
