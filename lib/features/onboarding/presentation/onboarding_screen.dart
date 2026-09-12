import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics_service.dart';
import '../../../core/error/result.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/_widgets/primary_cta.dart';
import '../../terms/presentation/terms_notifier.dart';
import '_widgets/onboarding_indicator.dart';
import '_widgets/onboarding_slide.dart';
import '_widgets/terms_checkbox_group.dart';
import 'onboarding_notifier.dart';

/// 3-slide onboarding 캐러셀 + 마지막 슬라이드 약관 동의 (Phase 10
/// D-01~D-08, D-15).
///
/// 흐름:
/// 1. 1~2번 슬라이드: AppBar "건너뛰기" 노출, FilledButton "다음" 으로 이동.
/// 2. 3번 슬라이드(마지막): "건너뛰기" 숨김, [TermsCheckboxGroup] 표시,
///    FilledButton "시작하기". 필수 2개 미동의 시 disabled.
/// 3. "시작하기" 탭 → [TermsNotifier.accept] → [AuthRepository.signInAnonymously]
///    → [OnboardingNotifier.markSeen] → Analytics 이벤트 → [AppRoutes.home].
/// 4. **Issue #9 (Plan 10-13):** 이미 정식(비익명) 사용자로 로그인된 상태에서
///    `/onboarding` 에 도달한 경우(재동의), `signInAnonymously` 를 skip 하고
///    [TermsNotifier.mirrorToFirestore] 를 `force: true` 로 호출하여 A 의
///    Firestore 에 재동의를 기록한다.
class OnboardingScreen extends ConsumerStatefulWidget {
  /// [OnboardingScreen] 을 생성한다.
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;
  bool _service = false;
  bool _privacy = false;
  bool _marketing = false;
  bool _showRequiredError = false;
  bool _isSubmitting = false;

  /// 온보딩 슬라이드 개수 (IN-07 — 단일 진실원).
  ///
  /// PageView children 개수 · [_lastPage] · [OnboardingIndicator.count] 세 곳이
  /// 각각 하드코딩되어 있었다. 누락 시 (a) 인디케이터 도트 수가 실제 페이지와
  /// 어긋나거나 (b) [_isLastPage] 가 마지막이 아닌 페이지에서 true 가 되어
  /// 약관 체크박스가 없는 페이지에 "시작하기" 가 노출되며, 어느 쪽도 정적
  /// 분석에 걸리지 않는다. 슬라이드를 추가/삭제하면 본 상수와 PageView
  /// children 만 함께 고치면 된다.
  static const int _slideCount = 3;

  static const int _lastPage = _slideCount - 1;

  /// 슬라이드 전환 지속시간 (IN-06 — `_handleCta` / `_handleSkip` 공유).
  ///
  /// 두 곳에 리터럴로 중복되어 있어 한쪽만 바꾸면 전환 체감이 어긋났다.
  static const Duration _kPageTransition = Duration(milliseconds: 300);

  bool get _isLastPage => _currentPage == _lastPage;
  bool get _requiredChecked => _service && _privacy;

  /// "전체 동의" 체크박스 표시 값 (WR-16 — 부모가 단일 진실원).
  bool get _allTermsChecked => _service && _privacy && _marketing;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _handleCta() async {
    if (!_isLastPage) {
      await _pageController.nextPage(
        duration: _kPageTransition,
        curve: Curves.easeOut,
      );
      return;
    }
    if (!_requiredChecked) {
      setState(() => _showRequiredError = true);
      return;
    }
    setState(() => _isSubmitting = true);
    // 제출 구간의 SnackBar 안내에 쓸 l10n 핸들을 await 이전에 캡처한다.
    final l10n = context.l10n;

    // CR-02: 제출 구간 전체를 try/finally 로 감싼다. 과거에는 성공 경로와
    // 알려진 실패 경로에서만 `_isSubmitting = false` 를 되돌렸기 때문에,
    // 중간에서 예외가 던져지면 (대표적으로 Firebase 미초기화 빌드의
    // `[core/no-app]`) 플래그가 true 로 고정되어 `_isCtaEnabled` 가 영구
    // false 가 됐다 — 사용자에게는 에러 메시지도 복구 수단도 없는 정지
    // 상태였다. finally 는 어떤 경로로 빠져나가든 CTA 를 되살린다.
    var isCompleted = false;
    try {
      final termsResult = await ref
          .read(termsProvider.notifier)
          .accept(service: _service, privacy: _privacy, marketing: _marketing);
      if (!mounted) return;
      if (termsResult is Failure<void>) {
        // WR-10: 종전에는 CTA 만 원상 복귀하고 안내가 없어 "시작하기를
        // 눌렀는데 아무 일도 일어나지 않는" dead-end 였다. 실제 실패 원인은
        // SharedPreferences 쓰기 실패이므로 재시도 여지를 알려야 한다.
        // 기존 키를 재사용한다 (신규 ARB 키 0).
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.errorUnknown)));
        return;
      }

      // CR-02 / Phase 1 D-13 가드: Firebase 미초기화 빌드 (stg/prod
      // placeholder 기본 상태, `firebase-configure.sh` 실행 전 dev) 에서
      // `firebaseAuthProvider` 를 읽으면 `[core/no-app]` 이 던져진다.
      // 미초기화 상태에서는 "정식 로그인 사용자" 자체가 성립할 수 없으므로
      // currentUser 를 null 로 간주하고 재동의 분기를 건너뛴다.
      final isFirebaseReady = ref.read(isFirebaseInitializedProvider);

      // Issue #9 (Plan 10-13) — 재동의 경로: 이미 정식 사용자로 로그인된
      // 상태에서 `/onboarding` 으로 리다이렉트된 경우(Plan 10-11 stale 가드 +
      // Plan 10-12 mirror skip 로 발동된 분기 (5) /onboarding),
      // signInAnonymously 호출은 A 세션을 새 익명 세션으로 덮어쓰므로 skip
      // 한다. 대신 A 의 Firestore 에 재동의 내용을 force write 하여
      // analytics + markSeen 경로로 마무리한다.
      //
      // Starter-kit 관점: "재동의 UX" 를 프로젝트에서 불필요하다고 판단하면
      // 이 분기 조건 (`!currentFbUser.isAnonymous`) 을 주석 처리하거나, 상위
      // `auth_guard.dart` 분기 (5) 를 비활성화하여 전체 기능을 끌 수 있다.
      final currentFbUser = isFirebaseReady
          ? ref.read(firebaseAuthProvider).currentUser
          : null;
      final isReConsent = currentFbUser != null && !currentFbUser.isAnonymous;

      if (isReConsent) {
        final mirrorResult = await ref
            .read(termsProvider.notifier)
            .mirrorToFirestore(uid: currentFbUser.uid, force: true);
        if (!mounted) return;
        if (mirrorResult is Failure) {
          // WR-11: 빈 조건문(주석만 있는 블록) 을 없애고 사용자에게 transient
          // 안내를 노출한다. 법적 동의 기록이 조용히 유실되는 비용이 SnackBar
          // 1회보다 크다. 홈 진행은 그대로 유지한다 — termsNotifier 가
          // Crashlytics 에 이미 기록했고 재동의 자체는 로컬에 반영됐다.
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.settingsLinkFailedTransient)),
          );
        }
      } else if (isFirebaseReady) {
        // 기본 경로 (최초 사용자 / 익명 사용자) — 기존 signInAnonymously 호출.
        final anonResult = await ref
            .read(authRepositoryProvider)
            .signInAnonymously();
        if (!mounted) return;
        if (anonResult is Failure) {
          // D-27 오프라인 처리는 Splash 단계에서 수행. 여기서는 단순 fallback.
          return;
        }
      }
      // Firebase 미초기화 (isFirebaseReady=false) 는 위 두 분기 모두 건너뛴다.
      // 익명 사인인 자체가 불가능한 환경이므로 약관 동의 + markSeen (둘 다
      // SharedPreferences 전용) 만 로컬에 기록하고 홈으로 진행한다 — D-13
      // ("Firebase 없이도 앱 정상 실행") 을 온보딩 경로에서도 성립시킨다.

      await ref.read(onboardingProvider.notifier).markSeen();
      await ref.read(analyticsServiceProvider).logEvent('onboarding_completed');

      if (!mounted) return;
      isCompleted = true;
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }

    if (isCompleted && mounted) {
      context.go(AppRoutes.home);
    }
  }

  void _handleSkip() {
    _pageController.animateToPage(
      _lastPage,
      duration: _kPageTransition,
      curve: Curves.easeOut,
    );
  }

  /// 약관 3 플래그를 갱신한다 (WR-16 — 부모가 단일 진실원).
  ///
  /// 지정하지 않은 인자는 현재 값을 유지한다. 필수 2개가 충족되면
  /// `_showRequiredError` 헬퍼 텍스트를 내린다.
  void _setTerms({bool? service, bool? privacy, bool? marketing}) {
    setState(() {
      _service = service ?? _service;
      _privacy = privacy ?? _privacy;
      _marketing = marketing ?? _marketing;
      if (_requiredChecked) {
        _showRequiredError = false;
      }
    });
  }

  /// "전체 동의" 토글 — 3 플래그를 한 번에 설정한다 (WR-16).
  void _handleAllTermsChanged(bool? value) {
    final next = value ?? false;
    _setTerms(service: next, privacy: next, marketing: next);
  }

  void _handlePageChanged(int index) {
    setState(() {
      _currentPage = index;
      if (index != _lastPage) {
        _showRequiredError = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    final typography = context.appTypography;
    final colorScheme = context.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (!_isLastPage)
            TextButton(
              onPressed: _handleSkip,
              child: Text(
                l10n.onboardingSkip,
                style: typography.labelLarge.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          Gap(spacing.sm),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: _handlePageChanged,
                children: [
                  OnboardingSlide(
                    icon: Icons.rocket_launch,
                    title: l10n.onboardingSlide1Title,
                    body: l10n.onboardingSlide1Body,
                  ),
                  OnboardingSlide(
                    icon: Icons.security,
                    title: l10n.onboardingSlide2Title,
                    body: l10n.onboardingSlide2Body,
                  ),
                  SingleChildScrollView(
                    padding: EdgeInsets.symmetric(horizontal: spacing.lg),
                    child: Column(
                      children: [
                        OnboardingSlide(
                          icon: Icons.public,
                          title: l10n.onboardingSlide3Title,
                          body: l10n.onboardingSlide3Body,
                        ),
                        Gap(spacing.xl),
                        TermsCheckboxGroup(
                          service: _service,
                          privacy: _privacy,
                          marketing: _marketing,
                          allChecked: _allTermsChecked,
                          onServiceChanged: (v) =>
                              _setTerms(service: v ?? false),
                          onPrivacyChanged: (v) =>
                              _setTerms(privacy: v ?? false),
                          onMarketingChanged: (v) =>
                              _setTerms(marketing: v ?? false),
                          onAllChanged: _handleAllTermsChanged,
                        ),
                        if (_showRequiredError) ...[
                          Gap(spacing.sm),
                          Text(
                            l10n.termsRequiredError,
                            style: typography.bodyMedium.copyWith(
                              color: colorScheme.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Gap(spacing.xl),
            OnboardingIndicator(count: _slideCount, activeIndex: _currentPage),
            Gap(spacing.xl),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: spacing.lg,
                vertical: spacing.lg,
              ),
              // WR-08: 공용 PrimaryCta 를 재사용한다. 직접 만든 복제본에는
              // PrimaryCta 가 가진 Semantics(label: commonLoading) 래퍼가 없어
              // 제출 중 스크린 리더가 상태를 읽지 못했고, 48/24/2 하드코딩으로
              // 매직 넘버도 재도입됐다. PrimaryCta 는 isLoading 일 때 버튼을
              // disabled 로 만들므로 기존 `_isCtaEnabled = !_isSubmitting`
              // 의미가 그대로 보존된다 — 필수 미동의 시에도 탭 가능해
              // `_showRequiredError` 분기가 유지된다 (Plan 10-03 Test 5 의도).
              child: PrimaryCta(
                label: _isLastPage
                    ? l10n.onboardingGetStarted
                    : l10n.onboardingNext,
                onPressed: _handleCta,
                isLoading: _isSubmitting,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
