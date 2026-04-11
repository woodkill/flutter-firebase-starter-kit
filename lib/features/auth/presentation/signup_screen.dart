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
import 'signup_notifier.dart';

/// 이메일/비밀번호 + Google + Apple 회원가입 화면 (D-01, D-04, D-05).
///
/// 폼 필드 3종(displayName / email / password) + Form validation +
/// [SignupNotifier] 위임 구조로 동작한다. Google 로그인은
/// [GoogleSignInNotifier], Apple 로그인은 [AppleSignInNotifier] 가
/// 별도 관리한다 (D-03, D-13, Phase 8).
/// 성공 시 화면 이동은 Phase 5 redirect 가드가 처리하므로 본 화면은
/// 직접 navigation 을 호출하지 않으며 redirect 가드에 위임한다 (D-05).
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

  /// Firebase 에러를 [FormErrorBanner] 로 노출하기 위한 로컬 상태.
  AppException? _bannerError;

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
  /// Google/Apple 로그인 진행 중이면 제출을 차단한다 (T-07-05, T-08-60).
  /// validator 통과 시 키보드를 내리고 [SignupNotifier.submit] 을 호출한다.
  /// 성공/실패 전이는 [ref.listen] 으로 감시되며 본 메서드는 navigation 을
  /// 호출하지 않는다 (D-05).
  Future<void> _handleSubmit() async {
    if (ref.read(googleSignInProvider).isLoading) return;
    if (ref.read(appleSignInProvider).isLoading) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _bannerError = null);
    await ref.read(signupProvider.notifier).submit(
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
    final isLoading =
        state.isLoading || googleState.isLoading || appleState.isLoading;

    ref.listen<AsyncValue<void>>(signupProvider, (previous, next) {
      if (next is AsyncError) {
        final err = next.error;
        if (err is AppException) {
          setState(() => _bannerError = err);
        }
      }
    });

    // Google 로그인 에러 감지. SignupScreen에서는 에러 배너만 표시.
    ref.listen<AsyncValue<void>>(googleSignInProvider, (previous, next) {
      if (next is AsyncError) {
        final err = next.error;
        if (err is AppException) {
          setState(() => _bannerError = err);
        }
      }
    });

    // Apple 로그인 에러 감지 (Phase 8 신규). LoginScreen과 달리
    // SignupScreen은 이메일 자동 채움(D-10)을 적용하지 않고 에러 배너만
    // 표시한다. 입력 중인 폼 필드에 임의로 쓰는 UX는 SignupScreen에서
    // 어색하므로 Google listener와 동일 정책을 유지한다.
    ref.listen<AsyncValue<void>>(appleSignInProvider, (previous, next) {
      if (next is AsyncError) {
        final err = next.error;
        if (err is AppException) {
          setState(() => _bannerError = err);
        }
      }
    });

    return AuthScaffold(
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
              SocialSignInSection(isFormLoading: state.isLoading),
              FormErrorBanner(exception: _bannerError),
              Gap(spacing.sm),
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
    );
  }
}
