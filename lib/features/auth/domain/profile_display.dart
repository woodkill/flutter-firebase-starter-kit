/// 계정 대표 이름 · 사진의 표시 값을 고르는 규칙 (Phase 17 D-27).
///
/// Firebase Auth 에 의존하지 않는 순수 함수다 — `currentUserProvider`
/// (auth_repository.dart) 가 Auth top-level 값과 `providerData` 를 넘겨 쓴다.
library;

/// 표시할 이름 또는 사진 값을 고른다 (Phase 17 D-27 — provider 공통 표시 규칙).
///
/// 순서:
/// 1. [topLevel] (Auth top-level `displayName` · `photoURL`)
/// 2. [providerValues] 중 [signUpProviderId] 와 같은 providerId 항목의 값
/// 3. [providerValues] 의 첫 비어 있지 않은 값 (목록 순서)
/// 4. null — 표시 층은 기존 fallback(홈 이름 `-` · 기본 아바타)을 쓴다.
///
/// null · 빈 문자열 · 공백만 있는 문자열은 값이 없는 것으로 본다. 고른 값은
/// 원문 그대로 돌려준다.
///
/// Auth 에 쓰지 않는다(RESEARCH R-04 (a)) — 익명 link 뒤 비어 있는
/// top-level 을 메모리 합성으로만 채운다. 연결 provider 값은 표시 fallback 으로만
/// 쓰고 저장하지 않는다(2026-09-28 원칙 「계정 대표값 = 가입 수단 값」).
String? resolveProfileValue({
  required String? topLevel,
  required List<(String providerId, String? value)> providerValues,
  required String? signUpProviderId,
}) {
  if (_hasValue(topLevel)) return topLevel;
  if (signUpProviderId != null) {
    for (final (providerId, value) in providerValues) {
      if (providerId == signUpProviderId && _hasValue(value)) return value;
    }
  }
  for (final (_, value) in providerValues) {
    if (_hasValue(value)) return value;
  }
  return null;
}

/// [value] 가 표시할 수 있는 값이면 true.
bool _hasValue(String? value) => value != null && value.trim().isNotEmpty;
