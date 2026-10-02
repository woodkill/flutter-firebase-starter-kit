import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/auth_strategies_registry.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/providers/firebase_providers.dart'
    hide googleSignInProvider;
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../_helpers/social_provider_resolver.dart';
import 'account_linking_sheet.dart';
import 'auth_in_progress_overlay.dart';
import 'email_auth_cta.dart';
import 'form_error_banner.dart';
import 'social_sign_in_section.dart';

/// 로그인 유도 Bottom Sheet 을 표시한다 (Phase 10 D-10).
///
/// 익명 또는 미인증 사용자가 보호 기능을 탭할 때 [AuthRequired] 가 호출한다.
/// Material 3 기본 drag handle + top rounded corner (28dp) 적용.
/// 최대 높이는 화면의 90% (quick 260911-0t3 — 0.75 에서 상향). 이는 상한일
/// 뿐이며, 콘텐츠가 작으면 sheet 는 그보다 낮은 콘텐츠 높이로 줄어든다.
Future<void> showLoginPromptSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.9,
    ),
    builder: (_) => const LoginPromptSheet(),
  );
}

/// 고정 배치에서 목록 창이 가져야 하는 최소 높이 — provider 버튼 1개 피치
/// (56dp · quick 261003-0fp 실측 버튼 높이). 이보다 낮으면 전체 스크롤로
/// 바꾼다 (Phase 3 D-09 · 사용자 sign-off 2026-10-03 선택지 1).
const double _minPinnedListHeight = 56;

/// 로그인 유도 Bottom Sheet 본체 (Phase 10 D-10).
///
/// 소셜 로그인 **성공** 시 sheet 를 닫고 [context.go] 로 Home 이동을
/// 명시적으로 호출한다 (Issue #3 safety net). resolveAuthRedirect 가 정상
/// 동작하면 중복 호출이며, GoRouter redirect 타이밍 경합 시 fallback
/// 으로 동작한다.
///
/// 소셜 로그인 **실패** 시에는 sheet 를 닫지 않고 소셜 버튼 바로 아래
/// [FormErrorBanner] 로 inline 표시한다. 이메일 충돌
/// ([AccountExistsWithDifferentCredential]) 이 기존 provider 를 식별한
/// 경우에는 [AccountLinkingSheet] 를 본 sheet **위에** 쌓아 안내하고,
/// 식별하지 못한 경우 (unknown) 는 배너 inline fallback 으로 남는다 --
/// Surface A (`login_screen.dart`) 와 동일한 정책이다
/// (quick 260910-uff -- AR-16.1-01 회수).
///
/// 레이아웃 (top -> bottom) -- 3블록 (quick 260911-0t3):
/// 1. Drag handle (Material 3 기본, `showDragHandle: true`)
/// 2. **고정 헤더** -- [Gap] lg=16 / 헤더 텍스트 (`authPromptSheetTitle` --
///    headlineMedium, onSurface) / [Gap] sm=8 / 본문 텍스트
///    (`authPromptSheetBody` -- bodyMedium, onSurfaceVariant) / [Gap] xl=24
/// 3. **스크롤 영역** -- [Flexible] (기본 `FlexFit.loose`) 안의 스크롤 뷰
///    1겹에 [SocialSignInSection] -- 활성 provider (기본 6개), "또는"
///    구분선 없음. 소셜 로그인 실패 시 provider 버튼 바로 아래에 에러
///    배너가 함께 렌더된다 (quick 260910-uff).
/// 4. **고정 footer** -- [Gap] md=12 / [EmailAuthCta]
///    (`authContinueWithEmail`) -- 탭 시 Bottom Sheet 를 닫고
///    `/login/email` (이메일 로그인 전용 화면) 로 push 한다 (Phase 16.1) /
///    [Gap] lg=16 (safe-area 하단)
///
/// provider 수가 늘어도 스크롤 영역(3)이 최대 높이 90% 안에서 흡수하므로
/// RenderFlex overflow 가 발생하지 않으며, [EmailAuthCta] 는 스크롤 영역
/// **밖** 고정 footer 라 폰 높이·provider 수와 무관하게 항상 첫 화면에
/// 보인다 (quick 260911-0t3 -- Sketch 004 winner B 「전체 스크롤」 supersede).
/// Drag handle 은 Bottom Sheet 이 builder 밖에 렌더하므로 스크롤과 무관하게
/// 고정된다.
///
/// **저높이 전체 스크롤 (Phase 3 D-09 · quick 261003-0fp · 사용자 sign-off
/// 2026-10-03 선택지 1):** 가로 모드처럼 시트가 낮아 고정 헤더(2)와 고정
/// footer(4) 사이 목록 창이 provider 버튼 1개(56dp)보다 낮아지면, 헤더 ·
/// 목록 · footer 를 스크롤 뷰 1겹에 함께 넣는다. 판정은 그려진 헤더 ·
/// footer 의 실측 높이로 하므로 언어 · 폭 · 글꼴 크기가 바뀌어도 맞는다.
/// 세로 폰과 780x360 처럼 창이 충분하면 지금의 고정 배치 그대로다.
class LoginPromptSheet extends ConsumerStatefulWidget {
  /// [LoginPromptSheet] 를 생성한다.
  const LoginPromptSheet({super.key});

  @override
  ConsumerState<LoginPromptSheet> createState() => _LoginPromptSheetState();
}

class _LoginPromptSheetState extends ConsumerState<LoginPromptSheet> {
  /// 소셜 로그인 에러를 소셜 버튼 영역에 표시하기 위한 상태.
  AppException? _socialError;

  /// 고정 헤더 실측용 key (저높이 전체 스크롤 판정 · quick 261003-0fp).
  final GlobalKey _headerKey = GlobalKey();

  /// 고정 footer 실측용 key (저높이 전체 스크롤 판정 · quick 261003-0fp).
  final GlobalKey _footerKey = GlobalKey();

  /// 저높이 전체 스크롤 모드 여부 — 기본은 고정 헤더 · footer 배치.
  bool _isAllScroll = false;

  /// account-exists 충돌 시 계정 연결 시트를 본 sheet **위에** 노출한다
  /// (quick 260910-uff -- Surface A 의 동명 메서드 1:1 mirror).
  ///
  /// `ref.listen` 콜백 (build 동안) 안에서 직접 `showModalBottomSheet` 를
  /// 호출하면 build 중 navigator 변경 위반이 되므로 post-frame callback
  /// 으로 1 frame 미룬다. 본 sheet 의 `context` 를 넘기므로 연결 시트는
  /// 위에 쌓이고, 사용자가 취소하면 본 sheet 로 되돌아온다.
  ///
  /// 연결 시트가 link / 기존 provider 로그인 성공(`true`) 으로 스스로
  /// 닫히면 본 sheet 도 함께 닫는다 -- 시트가 `/home` 으로 이동한 뒤에도
  /// modal 이 홈 위에 떠 있는 상태를 남기지 않기 위함이다. 취소·실패
  /// (`false` / `null`) 에는 아무 동작도 하지 않아 사용자가 본 sheet 에서
  /// 다른 수단을 재시도할 수 있다.
  void _showAccountLinkingSheet(AccountExistsWithDifferentCredential err) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final navigator = Navigator.of(context);
      final linkResult = AccountLinkingSheet.show(
        context,
        existingProvider: err.existingProvider!,
        pendingCredential: err.pendingCredential,
      );
      // ignore: discarded_futures
      linkResult.then((linked) {
        if (linked != true) return;
        if (!mounted) return;
        if (navigator.canPop()) navigator.pop();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    final typography = context.appTypography;
    final colorScheme = context.colorScheme;

    // Issue #3 safety net: 소셜 로그인 성공 시 Sheet pop + Home 이동.
    // activeStrategiesProvider 결과를 순회하여 단일 ref.listen 패턴으로 통합
    // (Phase 11-04 Pattern I, corrections 3번 / Pitfall 6 — 4곳 중 1곳).
    final strategies = ref.watch(activeStrategiesProvider);
    for (final strategy in strategies) {
      ref.listen<AsyncValue<void>>(resolveSocialProvider(strategy.providerId), (
        previous,
        next,
      ) {
        // IN-04 (Phase 09 review): 새 시도가 시작되면 직전 provider 의 실패
        // 배너를 비운다 (Surface A `login_screen` 과 동일 규약 — 두 surface
        // 의 소셜 에러 표시 계약은 대칭을 유지해야 한다).
        if (next is AsyncLoading) {
          if (mounted && _socialError != null) {
            setState(() => _socialError = null);
          }
          return;
        }
        if (previous is AsyncLoading && next is AsyncData) {
          if (!mounted) return;
          final user = ref.read(firebaseAuthProvider).currentUser;
          if (user != null && !user.isAnonymous) {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
            context.go(AppRoutes.home);
          }
          return;
        }
        if (next is AsyncError) {
          // dispose 후 ref.listen 콜백 race 방어 (Surface A WR-04 계승).
          if (!mounted) return;
          final err = next.error;
          // 기존 provider 를 식별한 충돌만 계정 연결 시트로 안내하고,
          // 식별 실패 (unknown) 는 배너 inline fallback 으로 남긴다
          // (Surface A 의 R2 회귀 0 계약 동형). 실패 경로는 본 sheet 를
          // pop 하지 않는다 -- 사용자는 현재 화면을 잃지 않는다.
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

    // 소셜 OAuth 진행 (Phase 11-04 hotfix UX gap): sheet 안에서만 overlay
    // 표시 — sheet 가 OAuth 성공 직후 pop 되므로 표시 시간은 짧지만
    // signInWithCredential / Firestore mirror 구간을 시각적으로 메운다.
    // WR-08 (Phase 7 review): 7 provider 하드코딩 합산 → registry 기반
    // helper (복제 3곳 제거 — 단일 진실원).
    final isSocialLoading = watchAnySocialSignInLoading(ref);

    // 고정 헤더 — 스크롤해도 "왜 로그인이 필요한가" 맥락이 남는다.
    // 전체 스크롤 모드에서도 같은 위젯이라 높이가 같다 (모드 판정 안정).
    final header = Padding(
      key: _headerKey,
      padding: EdgeInsets.symmetric(horizontal: spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Gap(spacing.lg),
          Text(
            l10n.authPromptSheetTitle,
            style: typography.headlineMedium.copyWith(
              color: colorScheme.onSurface,
            ),
          ),
          Gap(spacing.sm),
          Text(
            l10n.authPromptSheetBody,
            style: typography.bodyMedium.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          Gap(spacing.xl),
        ],
      ),
    );
    final socialSection = SocialSignInSection(
      isFormLoading: false,
      showOrDivider: false,
      errorBanner: FormErrorBanner(exception: _socialError),
    );
    // 고정 footer — CTA 가 스크롤 영역 밖이라 폰 높이·provider 수와
    // 무관하게 첫 화면에 보인다 (quick 260911-0t3).
    final footer = Padding(
      key: _footerKey,
      padding: EdgeInsets.symmetric(horizontal: spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Gap(spacing.md),
          // WR-08 — 소셜 OAuth 진행 중에는 null 을 넘겨 disabled 시각·
          // 시맨틱을 AuthInProgressOverlay 의 탭 차단과 일치시킨다.
          EmailAuthCta(
            onPressed: isSocialLoading
                ? null
                : () => _handleContinueWithEmail(context),
          ),
          Gap(spacing.lg),
        ],
      ),
    );

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 그려진 헤더 · footer 실측 높이로 모드를 다시 판정한다 — 회전 ·
          // 언어 · 글꼴 크기가 바뀌면 다시 layout 되어 이 경로를 다시 탄다.
          _scheduleLayoutModeCheck(constraints.maxHeight);
          return Stack(
            children: <Widget>[
              if (_isAllScroll)
                // 저높이(가로) 전체 스크롤 — 헤더 · 목록 · footer 를 스크롤
                // 1겹에 넣는다 (Phase 3 D-09 · quick 261003-0fp · 사용자
                // sign-off 2026-10-03 선택지 1).
                SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      header,
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: spacing.lg),
                        child: socialSection,
                      ),
                      footer,
                    ],
                  ),
                )
              else
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    // provider 목록만 스크롤 — Flexible 은 기본 FlexFit.loose
                    // 라 콘텐츠가 작으면 sheet 가 cap 아래로 줄어든다
                    // (Expanded 금지).
                    Flexible(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.symmetric(horizontal: spacing.lg),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [socialSection],
                        ),
                      ),
                    ),
                    footer,
                  ],
                ),
              if (isSocialLoading) const AuthInProgressOverlay(),
            ],
          );
        },
      ),
    );
  }

  /// 다음 프레임에 헤더 · footer 실측 높이로 배치 모드를 판정한다.
  ///
  /// 고정 헤더와 고정 footer 사이에 남는 목록 창(`maxHeight − 헤더 − footer`)
  /// 이 [_minPinnedListHeight] 보다 낮으면 전체 스크롤, 아니면 고정 배치다.
  /// 헤더 · footer 는 두 모드에서 같은 위젯 · 같은 폭이라 높이가 같으므로
  /// 판정이 모드 전환으로 뒤집히지 않는다(진동 없음). 판정이 바뀔 때만
  /// `setState` 한다.
  void _scheduleLayoutModeCheck(double maxHeight) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !maxHeight.isFinite) return;
      final headerBox = _headerKey.currentContext?.findRenderObject();
      final footerBox = _footerKey.currentContext?.findRenderObject();
      if (headerBox is! RenderBox || !headerBox.hasSize) return;
      if (footerBox is! RenderBox || !footerBox.hasSize) return;
      final pinnedListWindow =
          maxHeight - headerBox.size.height - footerBox.size.height;
      final shouldScrollAll = pinnedListWindow < _minPinnedListHeight;
      if (shouldScrollAll != _isAllScroll) {
        setState(() => _isAllScroll = shouldScrollAll);
      }
    });
  }

  /// "이메일로 계속" 탭 핸들러.
  ///
  /// Bottom Sheet 를 닫고 `/login/email` (이메일 로그인 전용 화면) 로
  /// push 한다. Phase 16.1 — 쿼리 파라미터 기반 포커스 진입 계약은 전용
  /// route 로 대체됐다. 앱이 쿼리 문자열을 생성하는 지점이 사라지므로
  /// 임의 쿼리 주입으로 UI 동작을 바꿀 표면 자체가 없다 (T-16.1-02).
  void _handleContinueWithEmail(BuildContext context) {
    Navigator.of(context).pop();
    context.push(AppRoutes.emailLogin);
  }
}
