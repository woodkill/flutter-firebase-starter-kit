/**
 * deleteUserAccount onCall 회귀 테스트 placeholder
 * (Phase 16 Plan 16-01 Task 1.2 Wave 0 sentinel).
 *
 * **Mock 한계 명시:** 본 file 은 Wave 0 sentinel placeholder 로 본체 test
 * case 는 Plan 16-02 가 작성한다. 본체 test 는 functions/test/auth/
 * line_custom_token.test.ts (Phase 14 Plan 14-04 Task 1) 의 mock 패턴을
 * mirror — admin.auth().deleteUser mock + Firestore batch delete mock +
 * request.auth uid 분기 fixture.
 *
 * 본체 test 시나리오 (Plan 16-02 가 작성 예정):
 *  - Test 1: 정상 탈퇴 — admin.auth().deleteUser + Firestore doc 삭제
 *  - Test 2: request.auth=null → unauthenticated HttpsError
 *  - Test 3: idToken mismatch (D-07 재인증 의무) → invalid-argument
 *  - Test 4: Firestore batch delete 실패 → internal HttpsError (D-08)
 */
describe("[Wave 0 sentinel] deleteUserAccount — Plan 16-02 placeholder", () => {
  it.todo("Plan 16-02 implementation");
});
