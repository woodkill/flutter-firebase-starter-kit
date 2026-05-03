import '../../../l10n/generated/app_localizations.dart';

/// [formatProviderIds] 가 라벨로 변환하는 매핑 키 set.
///
/// Phase 7~9 에서 확립된 4개 매핑 + Phase 12 `kakao` slug 까지 컨트랙트로
/// 노출한다. Phase 13~16 (Naver/LINE/Yahoo!JP/WeChat) 신규 provider 매핑이
/// 추가될 때 본 set 과 [formatProviderIds] switch 분기, 그리고 단위 테스트의
/// 컨트랙트 검증을 함께 갱신해야 한다. 컨트랙트 테스트가 우선 실패하여 동시
/// 갱신 의무를 강제한다.
///
/// **두 형식이 공존한다 (Phase 12 D-16, D-17 / 12-UI-SPEC line 372-378):**
///
/// - **Native 4 provider** (Email/Google/Apple/Facebook): Firebase Auth 가
///   `User.providerData[i].providerId` 로 자체 반환하는 OAuth URI 형식
///   (`'password'` / `'google.com'` / `'apple.com'` / `'facebook.com'`).
/// - **Custom Token provider** (Kakao 외 Phase 13~16): Firebase 가 URI 를
///   반환하지 않으므로 Firestore `users/{uid}.linkedProviders[].providerId`
///   의 도메인 slug (`'kakao'` 등 — [kProviderIdKakao]) 를 직접 사용한다.
///
/// `currentUserProvider` 가 양쪽을 합산해 `User.providerIds` 에 채우므로
/// (Phase 12 D-16 합집합 정책) 본 매핑 set 과 switch 는 두 형식을 모두
/// 인식해야 한다 (slug vs URI 매핑 책임은 본 모듈 단일 진실원).
const Set<String> kSupportedAuthProviderIds = <String>{
  'password',
  'google.com',
  'apple.com',
  'facebook.com',
  // Custom Token slug — Native URI 형식 미존재 (Phase 12 D-17).
  'kakao',
};

/// `User.providerIds` 를 사용자 가독형 라벨 문자열로 변환한다 (D-11, Phase 12 D-17).
///
/// - `'password'` -> [AppLocalizations.authAccountProviderEmailPassword]
/// - `'google.com'` -> [AppLocalizations.authAccountProviderGoogle]
/// - `'apple.com'` -> [AppLocalizations.authAccountProviderApple] (Phase 8)
/// - `'facebook.com'` -> [AppLocalizations.authAccountProviderFacebook] (Phase 9)
/// - `'kakao'` -> [AppLocalizations.authAccountProviderKakao] (Phase 12 D-17 — slug 직접)
/// - 미지원 프로바이더는 raw ID 그대로 표시 (`_ => id` fallback).
///
/// 빈 리스트이면 `'-'`. 다중 provider 는 `, ` 로 결합한다.
String formatProviderIds(List<String> providerIds, AppLocalizations l10n) {
  if (providerIds.isEmpty) return '-';
  return providerIds
      .map(
        (id) => switch (id) {
          'password' => l10n.authAccountProviderEmailPassword,
          'google.com' => l10n.authAccountProviderGoogle,
          'apple.com' => l10n.authAccountProviderApple,
          'facebook.com' => l10n.authAccountProviderFacebook,
          // Phase 12 (D-17 — Custom Token slug, OAuth URI 형식 미존재).
          'kakao' => l10n.authAccountProviderKakao,
          _ => id,
        },
      )
      .join(', ');
}
