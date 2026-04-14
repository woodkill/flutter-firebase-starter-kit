import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics_service.dart';
import '../../../core/error/result.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../auth/data/auth_repository.dart';
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

  static const int _lastPage = 2;

  bool get _isLastPage => _currentPage == _lastPage;
  bool get _requiredChecked => _service && _privacy;

  /// CTA 활성화 여부.
  ///
  /// 마지막 슬라이드에서는 [_isSubmitting] 만 false 면 enabled — 필수 동의
  /// 미충족 시에도 탭 가능하게 두어 [_handleCta] 의 `_showRequiredError`
  /// 분기가 사용자에게 헬퍼 텍스트로 안내된다 (Plan 10-03 Test 5 의도).
  /// 1~2번 슬라이드는 항상 enabled (다음 페이지로 이동).
  bool get _isCtaEnabled => !_isSubmitting;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _handleCta() async {
    if (!_isLastPage) {
      await _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
      return;
    }
    if (!_requiredChecked) {
      setState(() => _showRequiredError = true);
      return;
    }
    setState(() => _isSubmitting = true);

    final termsResult = await ref.read(termsProvider.notifier).accept(
          service: _service,
          privacy: _privacy,
          marketing: _marketing,
        );
    if (!mounted) return;
    if (termsResult is Failure<void>) {
      setState(() => _isSubmitting = false);
      return;
    }

    final anonResult =
        await ref.read(authRepositoryProvider).signInAnonymously();
    if (!mounted) return;
    if (anonResult is Failure) {
      // D-27 오프라인 처리는 Splash 단계에서 수행. 여기서는 단순 fallback.
      setState(() => _isSubmitting = false);
      return;
    }

    await ref.read(onboardingProvider.notifier).markSeen();
    await ref
        .read(analyticsServiceProvider)
        .logEvent('onboarding_completed');

    if (!mounted) return;
    setState(() => _isSubmitting = false);
    context.go(AppRoutes.home);
  }

  void _handleSkip() {
    _pageController.animateToPage(
      _lastPage,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _handleTermsChanged(bool service, bool privacy, bool marketing) {
    setState(() {
      _service = service;
      _privacy = privacy;
      _marketing = marketing;
      if (_requiredChecked) {
        _showRequiredError = false;
      }
    });
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
                style: typography.labelLarge
                    .copyWith(color: colorScheme.onSurfaceVariant),
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
                          onStateChanged: _handleTermsChanged,
                        ),
                        if (_showRequiredError) ...[
                          Gap(spacing.sm),
                          Text(
                            l10n.termsRequiredError,
                            style: typography.bodyMedium
                                .copyWith(color: colorScheme.error),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Gap(spacing.xl),
            OnboardingIndicator(
              count: 3,
              activeIndex: _currentPage,
            ),
            Gap(spacing.xl),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: spacing.lg,
                vertical: spacing.lg,
              ),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _isCtaEnabled ? _handleCta : null,
                  child: _isSubmitting
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.onPrimary,
                          ),
                        )
                      : Text(
                          _isLastPage
                              ? l10n.onboardingGetStarted
                              : l10n.onboardingNext,
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
