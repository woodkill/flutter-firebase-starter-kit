/**
 * mirrorTermsAcceptanceSnapshot onCall 회귀 테스트 placeholder
 * (Phase 16 Plan 16-01 Task 1.2 Wave 0 sentinel).
 *
 * **Mock 한계 명시:** 본 file 은 Wave 0 sentinel placeholder 로 본체 test
 * case 는 Plan 16-02 가 작성한다. 본체 test 는 Firestore users/{uid} doc
 * set merge mock + server timestamp mock + request.auth uid 분기 fixture
 * 를 mirror.
 *
 * 본체 test 시나리오 (Plan 16-02 가 작성 예정):
 *  - Test 1: 정상 mirror — Firestore users/{uid}.termsAcceptedAt set
 *  - Test 2: request.auth=null → unauthenticated HttpsError
 *  - Test 3: termsVersion 누락 → invalid-argument HttpsError
 *  - Test 4: Firestore set 실패 → internal HttpsError
 */
describe(
  "[Wave 0 sentinel] mirrorTermsAcceptanceSnapshot — Plan 16-02 placeholder",
  () => {
    it.todo("Plan 16-02 implementation");
  },
);
