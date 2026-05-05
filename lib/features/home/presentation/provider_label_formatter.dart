// Phase 13 — see ROADMAP.md (D-53 5 provider 일반화 + assert + Localizable Unknown)

import '../../../core/auth/provider_id.dart';
import '../../../l10n/generated/app_localizations.dart';

/// [formatProviderIds] 가 라벨로 변환하는 매핑 키 set.
///
/// Phase 7~9 의 4개 native URI + Phase 12 `kakao` slug + Phase 13 `naver` slug +
/// Phase 14~16 미리 등재 (`line` / `yahoojp` / `wechat`) 까지 모두 컨트랙트로
/// 노출한다. 컨트랙트 테스트가 우선 실패하여 동시 갱신 의무를 강제한다.
///
/// **두 형식이 공존한다 (Phase 12 D-16 / D-17, Phase 13 D-53):**
///
/// - **Native 4 provider** (Email/Google/Apple/Facebook): Firebase Auth 가
///   `User.providerData[i].providerId` 로 자체 반환하는 OAuth URI 형식
///   (`'password'` / `'google.com'` / `'apple.com'` / `'facebook.com'`).
/// - **Custom Token provider** (Kakao/Naver/LINE/Yahoo!JP/WeChat): Firebase 가
///   URI 를 반환하지 않으므로 Firestore `users/{uid}.linkedProviders[].providerId`
///   의 도메인 slug ([kProviderIdKakao] 등) 를 직접 사용한다.
///
/// `currentUserProvider` 가 양쪽을 합산해 `User.providerIds` 에 채우므로
/// (Phase 12 D-16 합집합 정책) 본 매핑 set 과 switch 는 두 형식을 모두
/// 인식해야 한다 (slug vs URI 매핑 책임은 본 모듈 단일 진실원).
const Set<String> kSupportedAuthProviderIds = <String>{
  // Native (URI 형식)
  'password',
  'google.com',
  'apple.com',
  'facebook.com',
  // Custom Token slug — Native URI 형식 미존재 (Phase 12 D-17 / Phase 13 D-53).
  kProviderIdKakao,
  kProviderIdNaver,
  kProviderIdLine,
  kProviderIdYahooJp,
  kProviderIdWeChat,
};

/// `User.providerIds` 를 사용자 가독형 라벨 문자열로 변환한다 (D-11, D-17, D-53).
///
/// - `'password'` -> [AppLocalizations.authAccountProviderEmailPassword]
/// - `'google.com'` -> [AppLocalizations.authAccountProviderGoogle]
/// - `'apple.com'` -> [AppLocalizations.authAccountProviderApple] (Phase 8)
/// - `'facebook.com'` -> [AppLocalizations.authAccountProviderFacebook] (Phase 9)
/// - [kProviderIdKakao] -> [AppLocalizations.authAccountProviderKakao] (Phase 12 D-17)
/// - [kProviderIdNaver] -> [AppLocalizations.authAccountProviderNaver] (Phase 13)
/// - [kProviderIdLine] -> [AppLocalizations.authAccountProviderLine] (Phase 14 pre-registered)
/// - [kProviderIdYahooJp] -> [AppLocalizations.authAccountProviderYahooJp] (Phase 15 pre-registered)
/// - [kProviderIdWeChat] -> [AppLocalizations.authAccountProviderWechat] (Phase 16 pre-registered)
/// - 미지원 slug -> [AppLocalizations.errorUnknownProvider] (D-53 Localizable Unknown,
///   raw slug 노출 차단)
///
/// 빈 리스트이면 `'-'`. 다중 provider 는 `, ` 로 결합한다.
///
/// **D-53 contract drift 가드 (kDebugMode assert):** [kAllProviderIds] 의 모든
/// slug 가 본 switch 에 매핑되는지 검증. Phase 14~16 진입 시 신규 slug 가
/// kAllProviderIds 에 추가되지만 본 switch 갱신을 누락하면 dev 빌드 fail.
String formatProviderIds(List<String> providerIds, AppLocalizations l10n) {
  // D-53 contract drift 방지 assert (kDebugMode 만).
  // kAllProviderIds 의 모든 slug 가 아래 switch 에 매핑되는지 검증한다.
  // Phase 14~16 진입 시 신규 slug 가 kAllProviderIds 에 추가되면 본 함수
  // 갱신 의무를 강제 (dev 빌드 fail).
  assert(() {
    const knownIds = <String>{
      kProviderIdGoogle,
      kProviderIdApple,
      kProviderIdFacebook,
      kProviderIdKakao,
      kProviderIdNaver,
      kProviderIdLine,
      kProviderIdYahooJp,
      kProviderIdWeChat,
    };
    final missing = kAllProviderIds
        .where((id) => !knownIds.contains(id))
        .toList();
    if (missing.isNotEmpty) {
      throw StateError(
        'kAllProviderIds 중 매핑되지 않은 provider: $missing — '
        'provider_label_formatter switch 확장 필요 (D-53).',
      );
    }
    return true;
  }());

  if (providerIds.isEmpty) return '-';
  return providerIds
      .map(
        (id) => switch (id) {
          // Native URI 형식
          'password' => l10n.authAccountProviderEmailPassword,
          'google.com' => l10n.authAccountProviderGoogle,
          'apple.com' => l10n.authAccountProviderApple,
          'facebook.com' => l10n.authAccountProviderFacebook,
          // Custom Token slug 형식 (D-17 / D-53)
          kProviderIdKakao => l10n.authAccountProviderKakao,
          kProviderIdNaver => l10n.authAccountProviderNaver,
          kProviderIdLine => l10n.authAccountProviderLine,
          kProviderIdYahooJp => l10n.authAccountProviderYahooJp,
          kProviderIdWeChat => l10n.authAccountProviderWechat,
          // D-53 release fallback — Localizable Unknown (raw slug 노출 절대 금지).
          _ => l10n.errorUnknownProvider,
        },
      )
      .join(', ');
}
