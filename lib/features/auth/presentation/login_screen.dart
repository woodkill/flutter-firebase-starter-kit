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
import '_widgets/email_auth_cta.dart';
import '_widgets/form_error_banner.dart';
import '_widgets/social_sign_in_section.dart';
import 'login_notifier.dart';

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
class LoginScreen extends ConsumerStatefulWidget {
  /// [LoginScreen] 을 생성한다.
  const LoginScreen({super.key});

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

    // 소셜 로그인 결과 (Google/Apple/Facebook): activeStrategiesProvider 가
    // 반환한 활성 Strategy 들을 순회하여 단일 ref.listen 패턴으로 통합한다
    // (Phase 11-04 Pattern I, corrections 3번 / Pitfall 6 — 4곳 중 1곳).
    // 성공 -> Home safety net (Issue #3), 에러 -> 배너 + D-10.
    final strategies = ref.watch(activeStrategiesProvider);
    for (final strategy in strategies) {
      ref.listen<AsyncValue<void>>(resolveSocialProvider(strategy.providerId), (
        previous,
        next,
      ) {
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
            });
          }
        }
      });
    }

    return Stack(
      children: <Widget>[
        AuthScaffold(
          title: l10n.authLoginTitle,
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
                onPressed: isSocialLoading
                    ? null
                    : () => context.push(AppRoutes.emailLogin),
              ),
              Gap(spacing.sm),
              TextButton(
                onPressed: () => context.push(AppRoutes.signup),
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
