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
///
/// **Lazy-initialized (WR-03):** `@Riverpod(keepAlive: true)` 는 declaration
/// 시점이 아닌 첫 read 시점에 `build()` 가 1회 호출되어 false 로 시작하며,
/// 이후 [begin] / [end] 가 state 를 토글한다. 일반적인 cold-start 흐름에서는
/// `AuthRepository` 생성자가 `socialLinkInProgressProvider.notifier` 를
/// watch 하므로 (auth_repository.dart line 643-651), AuthRepository 가
/// 처음 build 되는 시점에 본 Notifier 도 함께 초기화된다. SplashInitializer
/// → authRepositoryProvider read 경로가 일반 진입점이다.
///
/// **소유권 invariant:** 본 Notifier 는 `AuthRepository` 단독 소유다.
/// [begin] / [end] 는 오직 `signInWith{Google,Apple,Facebook}` 의 try /
/// finally 블록에서만 호출되어야 하며, 외부 모듈이 직접 호출하면 race-fix
/// invariant 가 깨진다. consumer (SplashInitializer / auth_guard.authRedirect)
/// 는 read/watch 만 수행하고 mutate 하지 않는다 (defense-in-depth, D-02).
@Riverpod(keepAlive: true)
class SocialLinkInProgress extends _$SocialLinkInProgress {
  /// 초기 상태는 `false` — 진행 중인 social linking 이 없는 상태.
  ///
  /// Lazy-initialized: 첫 read 시점에 1회 호출된다. [begin] 호출 *전* 의
  /// 평가는 항상 false 로 정확하며, 호출 *후* 의 평가는 이미 state=true 가
  /// 적용된 상태이므로 race-window 진입 여부 판단이 일관된다.
  @override
  bool build() => false;

  /// 소셜 IdP linking 시퀀스 진입을 표시한다.
  ///
  /// AuthRepository.signInWith{Google,Apple,Facebook} 의 `try` 블록
  /// 첫 줄에서 호출한다 (D-03). 외부 모듈에서 호출 금지.
  void begin() => state = true;

  /// 소셜 IdP linking 시퀀스 종료를 표시한다.
  ///
  /// AuthRepository.signInWith{Google,Apple,Facebook} 의 `finally` 블록
  /// 에서 호출한다 — success/failure/cancel 어떤 경로로 반환하든 호출되어
  /// 야 한다 (D-03). 외부 모듈에서 호출 금지.
  void end() => state = false;
}
