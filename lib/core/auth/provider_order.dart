// Phase 16.10 — see ROADMAP.md (C-08 · UI-SPEC §행 순서)
//
// 소셜 provider 의 킷 표준 표시 순서 — 목록 1곳 (C-08).
import 'provider_id.dart';

/// 킷 표준 소셜 provider 표시 순서 (Phase 16.10 C-08 · UI-SPEC §행 순서).
///
/// 계정 정보 화면 「계정 연결」 후보 목록과 탈퇴 진행 화면의 행 정렬이 이
/// 목록 하나를 참조한다 — 화면마다 순서를 따로 두지 않는다. 이메일/비밀번호는 소셜이
/// 아니므로 넣지 않는다. 이메일/비밀번호 연결 후보가 필요하면 이 목록이 아니라
/// 「계정 연결」 후보 필터(`account_linking_section.dart`)에 따로 더한다
/// (`AuthRepository.linkEmailCredential` 문서 · 16.10 review IN-07).
///
/// 새 provider 추가 시 본 리스트에 표시하고 싶은 자리에 1줄만 넣으면 된다 —
/// 두 화면의 정렬 코드는 바뀌지 않는다. 개수를 문장에 박지 않는다(진실원은
/// 목록 자체다).
const List<AccountProvider> kSocialProviderOrder = <AccountProvider>[
  AccountProvider.google,
  AccountProvider.apple,
  AccountProvider.facebook,
  AccountProvider.kakao,
  AccountProvider.naver,
  AccountProvider.line,
];
