import 'package:firebase_auth/firebase_auth.dart' as fb;

import '../../../core/error/app_exception.dart';

/// Splash 자동 익명 사인인 실패 시 Crashlytics custom-key 값 + 사용자 fingerprint
/// 양쪽에서 공통으로 사용하는 오류 코드 추출 함수 (Phase 10.1 D-10/D-11, WR-03).
///
/// `cause` 가 [fb.FirebaseAuthException] 이면 그 `code` 만 반환 — `message` 는
/// 단말 주소/스택 토큰 포함 위험이 있어 절대 노출 금지 (D-10). cause 가 없거나
/// 다른 타입이면 `'unknown'` 폴백.
///
/// **호출처:**
/// - `SplashInitializer._finalize` — Crashlytics setCustomKey value.
/// - `SplashScreen._showFailureDialog` — 사용자 fingerprint 표시 + 클립보드 복사.
///
/// 두 호출처가 동일 값을 공유하므로 retry 소진 시 사용자가 본 코드와 ops
/// dashboard 의 분류가 일치한다.
String extractSplashErrorCode(AppException e) {
  final cause = e.cause;
  if (cause is fb.FirebaseAuthException) {
    return cause.code;
  }
  return 'unknown';
}
