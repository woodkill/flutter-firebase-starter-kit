// 10-REVIEW WR-12 — Splash 가 사용하는 AuthRepository 표면의 최소 계약.
//
// `SplashInitializer` 는 `AuthRepository` 전체가 아니라 익명 사인인 1개
// 메서드만 사용한다. 그 사실을 타입으로 표현해 Firebase 미초기화 경로의
// no-op 구현이 `noSuchMethod` 없이 성립하게 한다.
import '../../../core/error/result.dart';
import 'user.dart';

/// 익명 사인인 능력만 노출하는 최소 인터페이스 (10-REVIEW WR-12).
///
/// `AuthRepository` 가 구현하며, `SplashInitializer.authRepository` 필드
/// 타입이 본 인터페이스로 좁혀진다.
///
/// **도입 이유:** 이전에는 Firebase 미초기화 경로의 주입 대상이
/// `implements AuthRepository` + `dynamic noSuchMethod` 조합이었다. 그 조합은
/// (a) `.claude/rules/flutter.md` 의 "`dynamic` 사용 금지" 위반이고,
/// (b) 컴파일러가 인터페이스 누락을 검출하지 못하게 만들어 후속 phase 가
/// 미초기화 경로에서 새 메서드를 호출해도 **런타임까지 발견 불가**였으며,
/// (c) `AuthRepository` 가 concrete class 라 계약이 암묵적이었다.
///
/// **배치 위치 (deviation 근거):** 10-REVIEW 는 본 선언을
/// `splash_initializer.dart` 에 두라고 제안했으나, 그러면 `features/auth/data`
/// 가 `features/splash/presentation` 을 import 해야 해 feature-first 계층이
/// 역전된다. auth 도메인에 두면 splash 가 domain 을 참조하는 정상 방향이 된다.
abstract interface class AnonymousSignIn {
  /// 익명 사용자로 로그인한다.
  Future<Result<User>> signInAnonymously();
}
