import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/app_exception.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/theme_extensions.dart';
import '_widgets/auth_scaffold.dart';
import '_widgets/email_field.dart';
import '_widgets/form_error_banner.dart';
import '_widgets/password_field.dart';
import '_widgets/primary_cta.dart';
import 'login_notifier.dart';

/// 이메일/비밀번호 로그인 전용 화면 (Phase 16.1 D-01, `/login/email`).
///
/// Phase 16.1 이메일 격하(relegation) 로 [LoginScreen] 의 chooser 에서
/// 분리된 form 전용 surface 다. 소셜 로그인 진입점은 이 화면에 존재하지
/// 않으며 (A 단독 책임), 이 화면은 push 로 진입하므로 back 버튼을 노출한다.
///
/// 폼 제출 결과는 [LoginNotifier] 가 [AsyncValue] (void) 로 노출한다.
/// 성공 + `emailVerified` 시 [context.go] 로 Home 이동을 명시적으로 호출한다
/// (Issue #5 safety net). `emailVerified=false` 인 신규 가입 직후 race 는
/// `authRedirect` 분기 (4) `/verify-email` redirect 에 위임한다.
/// 실패 시 [FormErrorBanner] 에 inline 으로 표시한다 (Dialog/SnackBar 0).
class EmailLoginScreen extends ConsumerStatefulWidget {
  /// [EmailLoginScreen] 을 생성한다.
  const EmailLoginScreen({super.key});

  @override
  ConsumerState<EmailLoginScreen> createState() => _EmailLoginScreenState();
}

class _EmailLoginScreenState extends ConsumerState<EmailLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  /// 이메일/비밀번호 로그인 에러를 이메일 필드 영역에 표시하기 위한 상태.
  AppException? _emailError;

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
  /// validator 통과 시 키보드를 내리고 [LoginNotifier.submit] 을 호출한다.
  /// 성공 + emailVerified 시 [context.go] 로 Home 이동을 명시적으로 호출한다
  /// (Issue #5 safety net — Plan 10-08 패턴 확장). emailVerified=false 인
  /// 신규 가입 직후 race 에서는 분기 (4) /verify-email redirect 에 위임한다.
  ///
  /// Phase 16.1 D-07: 원본 [LoginScreen] 이 갖고 있던 7개 소셜 provider
  /// `isLoading` guard (T-07-05 / T-08-60) 는 이식하지 않는다 — 이 화면에는
  /// 소셜 진입점이 0 이라 조건이 성립할 수 없다. 이중 제출 방어는 chooser
  /// 화면의 소셜 섹션 `isFormLoading` 과 이 화면의 [PrimaryCta.isLoading]
  /// disabled 로 각각 유지된다.
  Future<void> _handleSubmit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    final state = ref.watch(loginProvider);

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
          });
        }
      }
    });

    return AuthScaffold(
      title: l10n.authLoginTitle,
      showBackButton: true,
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Gap(spacing.xxl),
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
                isLoading: state.isLoading,
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
    );
  }
}
