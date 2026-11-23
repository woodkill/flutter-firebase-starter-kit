// 약관 동의 묶음에 더하는 필수 확인 행 목록 — 내 앱의 파일이다(킷 판은 빈 목록).
import 'app_terms_confirmation_slot.dart';

/// 온보딩 마지막 슬라이드의 약관 동의 묶음에 더할 필수 확인 행을 만든다.
///
/// - 행 하나는 `AppTermsConfirmation(label: …, missingHint: …)` 이다. 문구는 내
///   ARB 키(`input.context.l10n.<키>`)로 만든다. `missingHint` 는 빼도 된다.
/// - 목록 순서가 화면 순서다. 빈 목록이면 확인 행이 없다(킷 판).
/// - 킷은 이 파일을 고치지 않는다. 온보딩 화면을 직접 그리는 킷 시험은 이 함수
///   대신 빈 목록을 돌려주는 함수를 넘겨 그린다
///   (`OnboardingScreen.termsConfirmationsBuilder`).
/// - 안내: `docs/guide.md` 「약관 동의에 필수 확인 행 더하기」.
List<AppTermsConfirmation> buildAppTermsConfirmations(
  AppTermsConfirmationsInput input,
) => <AppTermsConfirmation>[
  // 예: AppTermsConfirmation(label: …, missingHint: …),
];
