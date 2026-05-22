// Phase 15 — see ROADMAP.md
import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/error/result.dart';
import '../data/auth_repository.dart';

part 'yahoojp_sign_in_notifier.g.dart';

/// Yahoo!JP 로그인 상태를 관리하는 [AsyncNotifier] (Phase 15, SOCL-04).
///
/// Phase 7 [GoogleSignInNotifier] / Phase 8 [AppleSignInNotifier] / Phase 9
/// [FacebookSignInNotifier] / Phase 12 [KakaoSignInNotifier] / Phase 13
/// [NaverSignInNotifier] / Phase 14 [LineSignInNotifier] 구조를 그대로
/// 미러링한다. autoDispose 이므로 화면 이탈 시 상태가 초기화된다. 성공 후
/// 화면 이동은 authRedirect 가 담당한다.
///
/// **race-fix invariant (Pitfall 8):** 본 Notifier 는 race-guard begin/end 를
/// 직접 호출하지 않는다. 단일 진실원은 [AuthRepository.signInWithYahoojp] 의
/// try-finally (Plan 15-03 Task 2).
///
/// **build() 시그니처 (R7 / Phase 13 D-42 carry-forward — Phase 14 D-LINE
/// 동일 invariant):** `FutureOr<void> build()` 유지 — Riverpod 3.x build
/// inference 규칙상 `void build()` 로 변경 시 generator 가 sync
/// `$Notifier<void>` 가족으로 강등되며 AsyncNotifier API 자체가 깨진다
/// (Phase 13 Plan 13-04 T-13-NAVER-NOTIFIER-R7-01 lesson). 회귀 가드
/// 테스트 + docstring 으로 invariant enforce
/// (sentinel: `T-15-YJP-NOTIFIER-R7-01`).
///
/// **Custom Token 이므로 emailVerified=true 가 자동 부여**: Apple / Kakao /
/// Naver / LINE 동일 경로. authRedirect 는 home 으로 자동 이동하며
/// `/verify-email` 우회. **Yahoo!JP D-YJP-09 차이점:** scope openid+profile
/// 만 → Firebase Auth user record 의 email 필드가 비어 있으므로
/// `_autoSendEmailVerification` 내부 email.isEmpty 가드 (line 918) 가 자연
/// no-op (LINE D-LINE-21 동일 mechanism).
@riverpod
class YahoojpSignInNotifier extends _$YahoojpSignInNotifier {
  @override
  FutureOr<void> build() {
    // 초기 상태: AsyncData(null) — 회귀 가드 테스트가 verify
    // (T-15-YJP-NOTIFIER-R7-01).
  }

  /// Yahoo!JP 로그인을 수행한다.
  ///
  /// 취소(null) 시 state 를 [AsyncData] 로 유지하여 조용히 무시 (D-YJP-09).
  /// 성공 시 [AsyncData]. 실패 시 [AsyncError] 로 전환되어 LoginScreen /
  /// SignupScreen / LoginPromptSheet 의 ref.listen 에서 FormErrorBanner 로
  /// 렌더링된다.
  Future<void> signInWithYahoojp() async {
    state = const AsyncLoading<void>();
    final result = await ref.read(authRepositoryProvider).signInWithYahoojp();
    if (!ref.mounted) return;

    if (result == null) {
      state = const AsyncData<void>(null); // D-YJP-09 silent cancel
      return;
    }

    state = switch (result) {
      Success<dynamic>() => const AsyncData<void>(null),
      Failure<dynamic>(exception: final ex) => AsyncError<void>(
        ex,
        StackTrace.current,
      ),
    };
  }
}
