/**
 * lookupSignInMethods onCall 회귀 테스트 placeholder
 * (Phase 16 Plan 16-01 Task 1.2 Wave 0 sentinel).
 *
 * **Mock 한계 명시:** 본 file 은 Wave 0 sentinel placeholder 로 본체 test
 * case 는 Plan 16-02 가 작성한다. 본체 test 는 admin.auth().getUserByEmail
 * mock + provider list 추출 + Identity Index lookup mock fixture 를 mirror.
 *
 * 본체 test 시나리오 (Plan 16-02 가 작성 예정):
 *  - Test 1: email 존재 → provider list 반환
 *  - Test 2: request.auth=null → unauthenticated HttpsError
 *  - Test 3: email 미존재 → empty provider list (not-found 아님 — D-10 3층)
 *  - Test 4: invalid email format → invalid-argument HttpsError
 */
describe(
  "[Wave 0 sentinel] lookupSignInMethods — Plan 16-02 placeholder",
  () => {
    it.todo("Plan 16-02 implementation");
  },
);
