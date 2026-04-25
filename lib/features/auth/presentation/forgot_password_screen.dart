import 'dart:async';

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
import '_widgets/primary_cta.dart';
import 'forgot_password_notifier.dart';

/// 비밀번호 재설정 메일 발송 화면 (D-37, D-38).
///
/// 단일 이메일 필드 + 발송 버튼 + inline 성공/실패 메시지로 구성된다.
/// 성공 시 [Duration] 2 초 후 자동으로 pop 한다 (D-37).
///
/// EEP(Email Enumeration Protection) 활성 환경에서는
/// `sendPasswordResetEmail` 이 존재하지 않는 이메일에 대해서도
/// 성공 응답을 반환할 수 있다. 따라서 본 화면의 성공 메시지는
/// "메일을 보냈다" 가 아니라 중립적인 [authForgotSent] 표현을 사용한다
/// (RESEARCH.md Pitfall 1 회피).
///
/// D-05 강제: 화면은 redirect 가드에 navigation 을 위임하므로
/// `context.go` / `context.replace` 를 사용하지 않는다. back navigation
/// 만 [context.pop] 으로 허용한다.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  /// [ForgotPasswordScreen] 을 생성한다.
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _emailFocus = FocusNode();

  /// Firebase 에러를 [FormErrorBanner] 로 노출하기 위한 로컬 상태.
  AppException? _bannerError;

  /// 성공 inline 메시지 표시 여부.
  bool _sentSuccessfully = false;

  /// 성공 후 자동 pop 예약 타이머. dispose 에서 cancel 한다.
  Timer? _autoPopTimer;

  @override
  void dispose() {
    _autoPopTimer?.cancel();
    _emailController.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  /// 폼 제출 핸들러.
  ///
  /// 성공 상태에서는 재제출을 차단한다. validator 통과 시 키보드를
  /// 내리고 [ForgotPasswordNotifier.submit] 을 호출한다.
  Future<void> _handleSubmit() async {
    if (_sentSuccessfully) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _bannerError = null);
    await ref
        .read(forgotPasswordProvider.notifier)
        .submit(email: _emailController.text.trim());
    // defense-in-depth: await 후 setState/context 호출이 추가될 경우를
    // 대비해 mounted 가드를 미리 배치한다 (WR-02).
    if (!mounted) return;
  }

  /// 성공 응답 수신 시 inline 메시지를 표시하고 2 초 후 자동 pop 한다.
  ///
  /// production 환경에서는 GoRouter 의 [context.pop] 을 사용한다.
  /// 단, `/forgot-password` 가 딥링크로 직접 진입되어 pop 할 스택이
  /// 없는 경우에는 `/login` 으로 명시 이동하여 사용자가 화면에 갇히는
  /// dead-end 를 회피한다 (WR-03). GoRouter context 부재(예: 위젯 단위
  /// 테스트) 시에는 [Navigator] API 로 graceful fallback 하며,
  /// Navigator 로도 pop 이 불가한 경우 [_sentSuccessfully] 를 false 로
  /// 되돌려 재제출을 허용한다. D-05 강제: `context.go` /
  /// `context.replace` 는 사용하지 않되, 본 케이스는 인증 성공이 아닌
  /// 폼 완료 후 UX flow 종료이므로 명시 go 를 예외로 허용한다.
  void _onSuccess() {
    if (!mounted || _sentSuccessfully) return;
    setState(() => _sentSuccessfully = true);
    _autoPopTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      final goRouter = GoRouter.maybeOf(context);
      if (goRouter != null) {
        if (context.canPop()) {
          context.pop();
        } else {
          // 딥링크로 진입한 최상위 forgot 화면 — login 으로 명시 이동.
          context.go(AppRoutes.login);
        }
      } else {
        final popped = Navigator.of(context).maybePop();
        // Navigator 로도 pop 이 불가한 경우 사용자가 dead-end 에 갇히지
        // 않도록 성공 상태를 되돌려 재제출을 허용한다.
        // ignore: discarded_futures
        popped.then((didPop) {
          if (!mounted || didPop) return;
          setState(() => _sentSuccessfully = false);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    final colors = context.colorScheme;
    final state = ref.watch(forgotPasswordProvider);
    final isLoading = state.isLoading;

    ref.listen<AsyncValue<void>>(forgotPasswordProvider, (previous, next) {
      if (next is AsyncError) {
        final err = next.error;
        if (err is AppException) {
          setState(() => _bannerError = err);
        }
      } else if (previous is AsyncLoading && next is AsyncData) {
        _onSuccess();
      }
    });

    return AuthScaffold(
      title: l10n.authForgotTitle,
      showBackButton: true,
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Gap(spacing.xxl),
            Text(
              l10n.authForgotDescription,
              style: context.appTypography.bodyMedium.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            Gap(spacing.lg),
            EmailField(
              controller: _emailController,
              focusNode: _emailFocus,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _handleSubmit(),
            ),
            Gap(spacing.sm),
            FormErrorBanner(exception: _bannerError),
            if (_sentSuccessfully) ...[
              Gap(spacing.sm),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: spacing.md,
                  vertical: spacing.sm,
                ),
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(spacing.sm),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      color: colors.onPrimaryContainer,
                      size: 20,
                    ),
                    SizedBox(width: spacing.sm),
                    Expanded(
                      child: Text(
                        l10n.authForgotSent,
                        style: context.appTypography.bodyMedium.copyWith(
                          color: colors.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            Gap(spacing.xl),
            PrimaryCta(
              label: l10n.authForgotCta,
              isLoading: isLoading,
              onPressed: _sentSuccessfully ? null : _handleSubmit,
            ),
          ],
        ),
      ),
    );
  }
}
