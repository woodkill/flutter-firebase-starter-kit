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
import 'signup_notifier.dart';

/// 이메일/비밀번호 회원가입 전용 화면 (Phase 16.1 Surface C, `/signup`).
///
/// 폼 필드 3종(displayName / email / password) + Form validation +
/// [SignupNotifier] 위임 구조로 동작한다 (Phase 6 D-01, D-22 동작 delta 0).
/// 이메일 가입 성공 시 navigation 은 authRedirect 에 위임하고 (D-05),
/// 실패 시 [FormErrorBanner] 에 inline 으로 표시한다.
///
/// **소셜 진입점은 본 화면에 없다 (Phase 16.1).** 소셜 로그인은 `/login`
/// chooser 와 `LoginPromptSheet` 두 surface 로 단일화되어, 이 화면에는 소셜
/// 버튼 섹션 · 소셜 결과 리스너 루프 · 계정 연결 시트 트리거 · 인증 진행
/// 오버레이가 존재하지 않는다 — 소셜 에러가 도달할 경로 자체가 없다.
class EmailSignupScreen extends ConsumerStatefulWidget {
  /// [EmailSignupScreen] 을 생성한다.
  const EmailSignupScreen({super.key});

  @override
  ConsumerState<EmailSignupScreen> createState() => _EmailSignupScreenState();
}

class _EmailSignupScreenState extends ConsumerState<EmailSignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

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
  /// validator 통과 시 키보드를 내리고 [SignupNotifier.submit] 을 호출한다.
  /// 성공/실패 전이는 [ref.listen] 으로 감시되며 이메일 가입 성공 시
  /// navigation 은 authRedirect 에 위임한다 (D-05).
  ///
  /// Phase 16.1 — 본 화면에는 소셜 진입점이 없으므로 소셜 `isLoading` guard
  /// (T-07-05 / T-08-60) 를 두지 않는다. 이중 제출 방어는 [PrimaryCta] 의
  /// `isLoading` disabled 가 담당한다.
  Future<void> _handleSubmit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
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

    // 이메일/비밀번호 가입 에러 → _emailError (이메일 필드 영역 배너).
    //
    // Issue #5 safety net 미적용 (의도적 — Plan 10-09): 신규 가입 직후
    // emailVerified=false 가 일반적이며, authRedirect 분기 (4) 가
    // /verify-email 로 강제 리다이렉트한다. safety net 을 추가하면 분기 (4)
    // 와 충돌하여 깜빡임이 발생한다.
    ref.listen<AsyncValue<void>>(signupProvider, (previous, next) {
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
                isLoading: state.isLoading,
                onPressed: _handleSubmit,
              ),
              Gap(spacing.md),
              // D-02 (UI-SPEC §Open Items #2) — 현행 canPop() 분기 구조를
              // 유지하고 target 만 이메일 로그인 전용 화면으로 교체한다.
              // B → C → B 왕복은 pop 으로 되돌아가 스택이 자라지 않는다.
              //
              // WR-03 — 진입 경로가 2곳이므로 pop 의 도착지도 2가지다:
              // - A(chooser) → C 진입 후 탭: **chooser 로 복귀한다.**
              //   라벨이 가리키는 이메일 form 은 아니지만, 스택을 키우지
              //   않고 사용자가 직전에 있던 화면으로 되돌리는 쪽을
              //   의도적으로 택했다 (D-02). 이메일 form 은 chooser 의
              //   "이메일로 계속" 1탭으로 도달한다.
              // - B(/login/email) → C 진입 후 탭: 이메일 form 으로 복귀.
              // - 딥링크로 C 에 직접 진입(canPop() == false): 이메일 form
              //   을 push 한다.
              // 세 경로 모두 email_signup_screen_test.dart 가 고정한다.
              TextButton(
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.push(AppRoutes.emailLogin);
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
