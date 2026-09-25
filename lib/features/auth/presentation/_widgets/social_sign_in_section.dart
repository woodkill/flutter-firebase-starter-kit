import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../../../core/auth/auth_strategies_registry.dart';
import '../../../../core/auth/auth_strategy.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../_helpers/social_provider_resolver.dart';
import 'or_divider.dart';
import 'social_button.dart';

/// 활성화된 [AuthStrategy] 들을 [SocialButton] 으로 렌더링하는 공통 섹션
/// (Phase 11 D-11, Pattern H).
///
/// LoginScreen / LoginPromptSheet 2곳에서 동일하게 사용한다 (Phase 16.1 —
/// 소셜 섹션을 함께 담던 구 가입 화면 삭제로 3곳 → 2곳).
/// 활성 Strategy 목록은 [activeStrategiesProvider] (정적 config + Remote
/// Config kill switch overlay 합산, D-26) 가 제공한다. 인라인 Google/Apple/
/// Facebook 빌더는 [SocialButton] 으로 통합되어 본 섹션에서 제거되었다.
///
/// 진행 중 상태는 `build()` 안에서 [watchAnySocialSignInLoading] 이
/// **등록된 활성 Strategy 전체**를 watch 해 합산한다 — registry 등록만으로
/// 자동 반영되므로 provider 추가 시 본 위젯을 고칠 일이 없다.
///
/// IN-03 정정 (Phase 09 review): 이전 서술은 "`[isAnyLoading]` 은 Phase 11
/// 단계에서 3개 Provider (google/apple/facebook) 를 직접 watch" 였는데
/// (1) 구현은 이미 helper 로 대체됐고 (2) `isAnyLoading` 은 클래스 멤버가
/// 아니라 `build()` 의 지역 변수라 `[isAnyLoading]` 참조가 아무 것도 가리키지
/// 못했다.
class SocialSignInSection extends ConsumerWidget {
  /// [SocialSignInSection]을 생성한다.
  const SocialSignInSection({
    required this.isFormLoading,
    this.errorBanner,
    this.showOrDivider = true,
    this.strategies,
    this.onStrategyPressed,
    super.key,
  });

  /// 이메일 폼이 로딩 중인지 여부. true면 소셜 버튼도 비활성화한다.
  ///
  /// Phase 16.1 이후 이메일 form 은 별도 화면 (`/login/email`) 에 있고
  /// 그 화면은 chooser **위에** push 되므로, chooser 는 mount 상태를
  /// 유지한 채 `loginProvider` 의 로딩 상태를 이 파라미터로 전달한다
  /// (WR-01 — 교차 잠금 복원). 이메일 form 이 없는 [LoginPromptSheet] 는
  /// `false` 를 넘긴다.
  final bool isFormLoading;

  /// 소셜 버튼과 [OrDivider] 사이에 표시할 에러 배너.
  ///
  /// 소셜 로그인 에러는 소셜 버튼 바로 아래에 표시되어야 의미가 명확하다.
  /// null 또는 [SizedBox.shrink] 일 때는 공간을 차지하지 않는다.
  final Widget? errorBanner;

  /// 소셜 버튼 아래 [OrDivider] 노출 여부 (Phase 10 D-10).
  ///
  /// - `true` (기본값): `LoginScreen` chooser 처럼 소셜 → Divider →
  ///   이메일 진입 지점으로 이어지는 화면에서 사용. Phase 16.1 이후
  ///   divider 아래는 이메일 폼이 아니라 [EmailAuthCta] 다.
  /// - `false`: [LoginPromptSheet] 처럼 Divider 없이 소셜 버튼만 노출하는
  ///   Bottom Sheet에서 사용 (뒤에 "이메일로 계속" CTA 가 이어짐).
  final bool showOrDivider;

  /// 렌더할 Strategy 목록 대체. null 이면 [activeStrategiesProvider] 전체.
  ///
  /// 재인증 모드 로그인 화면이 현재 계정에 연결된 provider 만 넘긴다
  /// (debug reauth-login-auto-merge) — 연결 안 된 provider 버튼은 다른 계정
  /// 전환 · 무동의 연결의 입구가 된다.
  final List<AuthStrategy>? strategies;

  /// 버튼 탭 동작 대체 — [SocialButton.onPressed] 로 전달한다. null 이면 일반
  /// 로그인 ([AuthStrategy.signIn]).
  final ValueChanged<AuthStrategy>? onStrategyPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.appSpacing;

    // 이메일 또는 활성 소셜 provider 중 어느 하나라도 진행 중이면 이중 제출
    // 방지. WR-08 (Phase 7 review): 7 provider 하드코딩 합산 → registry 기반
    // helper. 이 합산 목록이 SocialLinkInProgress 의 bool 플래그를 지키는
    // 유일한 방어선인데 3곳에 복제되어 있어, 한 곳만 갱신되면 잠금이 silent
    // 로 무너졌다.
    //
    // 단락 평가 주의: helper 를 `||` 우변에 두면 isFormLoading=true 일 때
    // 소셜 provider 구독이 등록되지 않는다 — helper 를 먼저 평가한다.
    final isAnySocialLoading = watchAnySocialSignInLoading(ref);
    final isAnyLoading = isFormLoading || isAnySocialLoading;

    // 활성화된 Strategy 만 — 정적 config + RC overlay 합산 (D-26). 재인증
    // 모드는 호출부가 그 부분집합을 넘긴다.
    // 명시 타입 — `??` 우변 ref.watch 가 좌변 nullable 문맥으로 추론되지 않게.
    final List<AuthStrategy> visibleStrategies =
        strategies ?? ref.watch(activeStrategiesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var i = 0; i < visibleStrategies.length; i++) ...[
          if (i > 0) Gap(spacing.sm),
          // IN-05 (Phase 09 review): 동적 목록이므로 Key 필수.
          // [activeStrategiesProvider] 는 Remote Config kill switch 에 따라
          // **런타임에 원소가 빠질 수 있는** 목록이다. Key 가 없으면 Flutter
          // 가 타입+인덱스로 element 를 재사용하므로, 중간 원소가 제거되면
          // 이전 provider 버튼의 내부 상태(BrandFocusWrapper 의 focus 등)를
          // 다른 provider 버튼이 물려받는다.
          // `.claude/rules/flutter.md` 의 "동적 위젯 교체 시 Key 명시" 규약.
          //
          // **키에 인덱스를 함께 넣는 이유.** providerId 단독이 의미상 더
          // 정확하지만(각 버튼이 자기 상태를 유지), 레이아웃 회귀 가드
          // `login_prompt_sheet_overflow_test.dart` 가 "7 provider" 를
          // 시뮬레이션하려고 기존 strategy 를 **중복**시킨다 — 미등록
          // providerId 는 버튼 렌더 시점에 UnsupportedError 를 던져
          // 대체 구현을 만들 수 없기 때문이다(WR-01). production 의
          // `_allStrategies` 는 6개가 모두 distinct 라 중복이 불가능하지만,
          // 키가 중복되면 그 harness 가 "Duplicate keys" 로 깨진다.
          // 인덱스를 섞으면 목록이 바뀔 때 키도 바뀌어 **잘못된 상태 승계는
          // 그대로 차단**되며(원소 제거 시 뒤쪽 버튼은 재사용 대신 새로
          // 생성된다), 위치가 그대로인 버튼은 자기 상태를 유지한다.
          SocialButton(
            key: ValueKey<String>('${visibleStrategies[i].providerId}#$i'),
            strategy: visibleStrategies[i],
            isDisabled: isAnyLoading,
            onPressed: onStrategyPressed,
          ),
        ],
        if (errorBanner != null) ...[Gap(spacing.md), errorBanner!],
        if (showOrDivider) ...[
          Gap(spacing.lg),
          const OrDivider(),
          Gap(spacing.lg),
        ],
      ],
    );
  }
}
