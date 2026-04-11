import 'package:flutter_test/flutter_test.dart';

/// AppleSignInNotifier 단위 테스트 스텁 (Phase 8 Wave 0).
///
/// Plan 03에서 GoogleSignInNotifier 테스트를 미러링하여 채운다.
/// 커버리지 목표: AUTH-03-08 / AUTH-03-09 / AUTH-03-10
/// (`.planning/phases/08-apple-login/08-RESEARCH.md` §Validation Architecture).
void main() {
  group('AppleSignInNotifier (Wave 0 stub)', () {
    test(
      'Plan 03에서 구현 예정 — Wave 0 스텁',
      () {
        // Plan 03에서 GoogleSignInNotifier 테스트를 복사 후
        // 'google' → 'apple' 치환하여 4개 시나리오 작성:
        //   1. 성공 시 AsyncData(null)
        //   2. 취소(null 반환) 시 AsyncData (D-09)
        //   3. Failure 반환 시 AsyncError
        //   4. AccountExistsWithDifferentCredential 시 email 보존
        expect(true, isTrue);
      },
      skip: 'Plan 03에서 구현',
    );
  });
}
