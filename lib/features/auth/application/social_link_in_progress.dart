import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'social_link_in_progress.g.dart';

/// 소셜 IdP(Google/Apple/Facebook) 재로그인 시 race condition 보호용 플래그
/// (Phase 9.1 D-01).
///
/// `signInWithGoogle` / `signInWithApple` / `signInWithFacebook` 의
/// `_safeDelete(anonymous) → signInWithCredential/Provider` 시퀀스 사이에
/// `currentUser=null` 윈도우가 발생하면, splash 의 자동 익명 sign-in 또는
/// auth_guard 의 GC-04 fail-safe redirect 가 끼어들어 정식 사용자 상태가
/// 새 익명 UID 로 덮어써지는 race 가 발생한다 (`09-UAT.md` Gap test 6).
///
/// 본 Notifier 는 AuthRepository 의 social sign-in 메서드 진입 직후
/// [begin] 으로 `true` 전환되고, finally 블록에서 [end] 로 `false` 복귀한다.
/// SplashInitializer 와 auth_guard.authRedirect 는 본 state 를 read/watch 하여
/// 진행 중이면 자동 익명 sign-in / fail-safe redirect 를 보류한다
/// (defense-in-depth, D-02).
///
/// `@Riverpod(keepAlive: true)` 로 선언하여 hot reload / Provider rebuild 시
/// state 가 churn 되지 않도록 한다. consumer 는 모두 동일 컨테이너 안에서
/// 단일 인스턴스를 공유한다.
@Riverpod(keepAlive: true)
class SocialLinkInProgress extends _$SocialLinkInProgress {
  /// 초기 상태는 `false` — 진행 중인 social linking 이 없는 상태.
  @override
  bool build() => false;

  /// 소셜 IdP linking 시퀀스 진입을 표시한다.
  ///
  /// AuthRepository.signInWith{Google,Apple,Facebook} 의 `try` 블록
  /// 첫 줄에서 호출한다 (D-03).
  void begin() => state = true;

  /// 소셜 IdP linking 시퀀스 종료를 표시한다.
  ///
  /// AuthRepository.signInWith{Google,Apple,Facebook} 의 `finally` 블록
  /// 에서 호출한다 — success/failure/cancel 어떤 경로로 반환하든 호출되어
  /// 야 한다 (D-03).
  void end() => state = false;
}
