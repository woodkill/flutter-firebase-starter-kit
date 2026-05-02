import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 소셜 로그인 Strategy — Provider 식별 + signIn delegation 책임만 보유
/// (Phase 11 D-10).
///
/// 버튼 렌더링은 [SocialButton] 책임 (Phase 11-04). `lib/core/auth` (도메인)
/// ↔ `lib/features/auth/presentation` (UI) 경계 명확.
///
/// **Phase 9.1 race-fix 의무 (D-15, Pitfall 8):** 기존 `*SignInNotifier` 위임
/// 구현체 ([GoogleAuthStrategy] / [AppleAuthStrategy] / [FacebookAuthStrategy])
/// 는 `AuthRepository` 가 이미 `socialLinkInProgress.begin/end` 를 try-finally
/// 로 호출한다. Strategy 단계에서 **추가 begin/end 호출 절대 금지** — 이중
/// begin race 회귀 (T-11-RACE-01) 가 발생한다.
///
/// Phase 12+ Custom Token Strategy 가 `AuthRepository` 외부에서 Custom Token
/// 호출을 직접 수행하는 경우에는 Strategy 의 `signIn` 안에서 try-finally 로
/// `socialLinkInProgress.begin/end` 호출 의무.
///
/// **반환 타입 결정 (Q&A):** `Future<void>` — `*SignInNotifier` 가
/// `AsyncValue<void>` 만 노출하므로 Result 이중 진실을 회피한다. UI 는
/// `ref.listen(googleSignInProvider, ...)` 등 Notifier 의 [AsyncValue] 로
/// success/error 분기 (Phase 11-04 마이그레이션).
abstract class AuthStrategy {
  /// `const` 생성자 — 구현체는 모두 stateless / immutable.
  const AuthStrategy();

  /// Firebase providerId 와 정합한 식별자 (D-20).
  ///
  /// 정적 config key (`authProvider_{providerId}_enabled`) 와 Remote Config
  /// 키 (`auth_provider_{providerId}_enabled`) prefix 모두 동일 식별자
  /// 공유.
  String get providerId;

  /// ARB 키 (예: `'authGoogleSignIn'`).
  String get labelKey;

  /// 버튼 렌더링 식별자 — `sign_in_button` 패키지의 `Buttons` enum 매핑
  /// (Phase 11-04).
  String get iconAsset;

  /// 로그인 실행 진입점.
  ///
  /// 위임 대상 Notifier 가 `AsyncValue<void>` 로 상태를 노출한다. UI 는
  /// `ref.listen(*SignInProvider, ...)` 으로 success/error 를 구독한다.
  Future<void> signIn(Ref ref);

  /// 로케일별 기본 우선순위 — Phase 11 placeholder (D-13).
  ///
  /// Phase 16.1 (SOCL-10) 에서 본문을 채운다.
  int defaultPriorityFor(Locale locale) => 0;
}
