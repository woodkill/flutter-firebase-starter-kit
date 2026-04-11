import 'package:flutter_test/flutter_test.dart';

/// SocialSignInSection 플랫폼 분기 위젯 테스트 스텁 (Phase 8 Wave 0).
///
/// Plan 05에서 `debugDefaultTargetPlatformOverride`를 활용하여 채운다.
/// 커버리지 목표: AUTH-03-11 ~ AUTH-03-14
/// (`.planning/phases/08-apple-login/08-RESEARCH.md` §Validation Architecture).
void main() {
  group('SocialSignInSection platform branching (Wave 0 stub)', () {
    test(
      'Plan 05에서 구현 예정 — Wave 0 스텁',
      () {
        // Plan 05에서 작성할 시나리오:
        //   1. iOS에서 Apple → Google 순서 렌더링
        //   2. Android에서 Google → Apple 순서 렌더링
        //   3. 라이트 모드: Buttons.apple 렌더링
        //   4. 다크 모드: Buttons.appleDark 렌더링
        //   5. 모든 버튼 isAnyLoading=true일 때 disabled 동작
        expect(true, isTrue);
      },
      skip: 'Plan 05에서 구현',
    );
  });
}
