/// 계정 대표 이름 · 사진의 표시 값을 고르는 규칙 (Phase 17 D-27).
///
/// Firebase Auth 에 의존하지 않는 순수 함수다 — `currentUserProvider`
/// (auth_repository.dart) 가 Auth top-level 값과 `providerData` 를 넘겨 쓴다.
/// Apple 가입 이름 복사(`AuthRepository.signInWithApple`)도 [hasProfileValue]
/// 를 쓴다.
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
/// 예외: Apple 가입은 `AuthRepository.signInWithApple` 이 Apple 이름을 top-level
/// `displayName` 에 1회 복사한다(quick 261003-kgc) — Apple 은 두 번째 인가부터
/// 이름을 주지 않고 서버가 `providerData`(apple.com) 이름을 빈 값으로 갱신해,
/// 이 함수의 fallback 도 비기 때문이다(2026-10-03 iOS 실측).
String? resolveProfileValue({
  required String? topLevel,
  required List<(String providerId, String? value)> providerValues,
  required String? signUpProviderId,
}) {
  if (hasProfileValue(topLevel)) return topLevel;
  if (signUpProviderId != null) {
    for (final (providerId, value) in providerValues) {
      if (providerId == signUpProviderId && hasProfileValue(value)) {
        return value;
      }
    }
  }
  for (final (_, value) in providerValues) {
    if (hasProfileValue(value)) return value;
  }
  return null;
}

/// 프로필 표시 값(이름 · 사진 URL)이 있는지 판정한다.
///
/// null · 빈 문자열 · 공백만 있는 문자열은 값이 없다. [resolveProfileValue] 의
/// fallback 판정과 `AuthRepository` 의 Apple 가입 이름 복사(quick 261003-kgc)가
/// 같은 기준을 쓴다 — 복사 조건(top-level 비었음)과 표시 fallback 조건이
/// 어긋나지 않게 한 곳에 둔다.
bool hasProfileValue(String? value) => value != null && value.trim().isNotEmpty;
