import '../../../l10n/generated/app_localizations.dart';

/// [formatProviderIds] 가 라벨로 변환하는 매핑 키 set.
///
/// Phase 7~9 에서 확립된 4개 매핑을 컨트랙트로 노출한다.
/// Phase 12~16 (LINE/Yahoo/카카오/네이버/WeChat 등) 신규 provider 매핑이 추가될 때
/// 본 set 과 [formatProviderIds] switch 분기, 그리고 단위 테스트의 컨트랙트
/// 검증을 함께 갱신해야 한다. 컨트랙트 테스트가 우선 실패하여 동시 갱신 의무를
/// 강제한다.
///
/// **Firebase Auth providerId 형식 그대로 사용**: 본 매핑의 키들은 도메인
/// ProviderId (slug — `'google'` 등, [kProviderIdGoogle]) 가 아니라 Firebase
/// Auth 가 `User.providerData[i].providerId` 로 자체 반환하는 OAuth URI 형식
/// (`'google.com'` 등) 이다. 도메인 식별자와 분리되며 Firebase 측 형식을 그대로
/// 받아 매핑한다 (Phase 11-04 hotfix 의 ProviderId slug 통일과 무관).
const Set<String> kSupportedAuthProviderIds = <String>{
  'password',
  'google.com',
  'apple.com',
  'facebook.com',
};

/// `User.providerIds` 를 사용자 가독형 라벨 문자열로 변환한다 (D-11).
///
/// - `'password'` -> [AppLocalizations.authAccountProviderEmailPassword]
/// - `'google.com'` -> [AppLocalizations.authAccountProviderGoogle]
/// - `'apple.com'` -> [AppLocalizations.authAccountProviderApple] (Phase 8)
/// - `'facebook.com'` -> [AppLocalizations.authAccountProviderFacebook] (Phase 9)
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
          _ => id,
        },
      )
      .join(', ');
}
