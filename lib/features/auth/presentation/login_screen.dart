import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/app_exception.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/theme_extensions.dart';
import '_widgets/auth_scaffold.dart';
import '_widgets/email_field.dart';
import '_widgets/form_error_banner.dart';
import '_widgets/password_field.dart';
import '_widgets/primary_cta.dart';
import '_widgets/social_sign_in_section.dart';
import 'apple_sign_in_notifier.dart';
import 'google_sign_in_notifier.dart';
import 'login_notifier.dart';

/// 이메일/비밀번호 + Google + Apple 로그인 화면 (D-01, D-04, D-05).
///
/// 폼 제출 결과는 [LoginNotifier] 가 [AsyncValue] (void) 로 노출하고,
/// Google 로그인은 [GoogleSignInNotifier], Apple 로그인은
/// [AppleSignInNotifier] 가 별도 관리한다 (D-03, D-13, Phase 8).
/// 성공 시 화면 이동은 authRedirect 가 자동 처리한다 (D-05). 본 화면은
/// 성공 시 navigation 을 직접 호출하지 않으며 redirect 가드에 위임한다.
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

  /// Firebase 에러를 [FormErrorBanner] 로 노출하기 위한 로컬 상태.
  AppException? _bannerError;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  /// 폼 제출 핸들러.
  ///
  /// Google/Apple 로그인 진행 중이면 제출을 차단한다 (T-07-05, T-08-60).
  /// validator 통과 시 키보드를 내리고 [LoginNotifier.submit] 을 호출한다.
  /// 성공/실패 전이는 [ref.listen] 으로 감시되며 본 메서드는 navigation 을
  /// 호출하지 않는다 (D-05).
  Future<void> _handleSubmit() async {
    if (ref.read(googleSignInProvider).isLoading) return;
    if (ref.read(appleSignInProvider).isLoading) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _bannerError = null);
    await ref.read(loginProvider.notifier).submit(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
    // defense-in-depth: await 후 setState/context 호출이 추가될 경우를
    // 대비해 mounted 가드를 미리 배치한다 (WR-02).
    if (!mounted) return;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    final state = ref.watch(loginProvider);
    final googleState = ref.watch(googleSignInProvider);
    final appleState = ref.watch(appleSignInProvider);
    final isLoading =
        state.isLoading || googleState.isLoading || appleState.isLoading;

    ref.listen<AsyncValue<void>>(loginProvider, (previous, next) {
      if (next is AsyncError) {
        final err = next.error;
        if (err is AppException) {
          setState(() => _bannerError = err);
        }
      }
    });

    // Google 로그인 에러 감지 + D-10 이메일 자동 채움.
    ref.listen<AsyncValue<void>>(googleSignInProvider, (previous, next) {
      if (next is AsyncError) {
        final err = next.error;
        if (err is AppException) {
          setState(() => _bannerError = err);
        }
        // D-10: 이메일 충돌 시 이메일 자동 채움.
        if (err is AccountExistsWithDifferentCredential &&
            err.email != null) {
          _emailController.text = err.email!;
          _emailFocus.requestFocus();
        }
      }
    });

    // Apple 로그인 에러 감지 + D-10 이메일 자동 채움 (Phase 8 신규).
    // Google 패턴 1:1 미러링. Apple 'Hide My Email' 릴레이 이메일도 그대로
    // 채움 (D-08).
    ref.listen<AsyncValue<void>>(appleSignInProvider, (previous, next) {
      if (next is AsyncError) {
        final err = next.error;
        if (err is AppException) {
          setState(() => _bannerError = err);
        }
        // D-10: 이메일 충돌 시 이메일 자동 채움.
        if (err is AccountExistsWithDifferentCredential &&
            err.email != null) {
          _emailController.text = err.email!;
          _emailFocus.requestFocus();
        }
      }
    });

    return AuthScaffold(
      title: l10n.authLoginTitle,
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Gap(spacing.xxl),
              SocialSignInSection(isFormLoading: state.isLoading),
              FormErrorBanner(exception: _bannerError),
              Gap(spacing.sm),
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
              Gap(spacing.xl),
              PrimaryCta(
                label: l10n.authLoginCta,
                isLoading: isLoading,
                onPressed: _handleSubmit,
              ),
              Gap(spacing.md),
              TextButton(
                onPressed: () =>
                    context.push(AppRoutes.forgotPassword),
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
    );
  }
}
