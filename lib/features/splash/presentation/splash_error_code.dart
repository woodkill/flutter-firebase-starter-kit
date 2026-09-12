import 'package:firebase_auth/firebase_auth.dart' as fb;

import '../../../core/error/app_exception.dart';

/// Splash 자동 익명 사인인 실패 시 Crashlytics custom-key 값 + 사용자 fingerprint
/// 양쪽에서 공통으로 사용하는 오류 코드 추출 함수 (Phase 10.1 D-10/D-11, WR-02/WR-03).
///
/// - `cause` 가 [fb.FirebaseAuthException] 이면 그 `code` 만 반환 — `message` 는
///   단말 주소/스택 토큰 포함 위험이 있어 절대 노출 금지 (D-10).
/// - 그 외에는 [AppException] 런타임 타입명 (예: `'NoInternetConnection'`,
///   `'UserDisabled'`) 을 반환. PII-safe 이면서 Crashlytics 대시보드에서
///   offline 윈도우 vs 진짜 unknown fallback 을 구분 가능 (WR-02).
///
/// **호출처:**
/// - `SplashInitializer._finalize` — Crashlytics setCustomKey value.
/// - `SplashScreen._showFailureDialog` — 사용자 fingerprint 표시 + 클립보드 복사.
///
/// 두 호출처가 동일 값을 공유하므로 retry 소진 시 사용자가 본 코드와 ops
/// dashboard 의 분류가 일치한다.
///
/// **IN-02 — `--obfuscate` 빌드 제약 (커스터마이징 포인트):** cause 가
/// [fb.FirebaseAuthException] 이 아닌 경로는 런타임 타입명을 반환하는데,
/// AOT obfuscation 을 켜면 타입명이 난독화되어 사용자 fingerprint 와
/// Crashlytics 분류가 **둘 다 의미를 잃는다**. obfuscation 을 켜는
/// 프로젝트는 [AppException] 에 난독화되지 않는 안정적인 `code` getter 를
/// 추가하고 본 함수의 fallback 을 그 값으로 교체할 것. 같은 제약이
/// `splash_screen._runInit` 의 `e.runtimeType.toString()` fallback 에도
/// 동일하게 적용된다.
String extractSplashErrorCode(AppException e) {
  final cause = e.cause;
  if (cause is fb.FirebaseAuthException) {
    return cause.code;
  }
  // WR-02: cause 가 FirebaseAuthException 이 아닌 경우 런타임 타입명을 fingerprint
  // 로 사용. NoInternetConnection / ServiceUnavailable / UserDisabled /
  // TooManyRequests 등 sealed AppException 분류가 그대로 노출되며, PII (이메일/
  // UID/메시지) 는 포함되지 않는다.
  return e.runtimeType.toString();
}
