/// 인증 Provider 식별자 const String 상수 + 등록된 ID 리스트 (Phase 11 D-20).
///
/// Strategy.providerId / config key / Remote Config 키 prefix 모두 동일 식별자
/// 공유. Firebase Auth providerId ('google.com' 등) 와 정합한다.
library;

/// Google 로그인 식별자 (Firebase providerId).
const String kProviderIdGoogle = 'google.com';

/// Apple 로그인 식별자 (Firebase providerId).
const String kProviderIdApple = 'apple.com';

/// Facebook 로그인 식별자 (Firebase providerId).
const String kProviderIdFacebook = 'facebook.com';

/// Kakao 로그인 식별자 (Custom Token, Firebase providerId 미사용).
const String kProviderIdKakao = 'kakao';

/// Naver 로그인 식별자 (Custom Token).
const String kProviderIdNaver = 'naver';

/// LINE 로그인 식별자 (Custom Token).
const String kProviderIdLine = 'line';

/// Yahoo! JAPAN 로그인 식별자 (Custom Token).
const String kProviderIdYahooJp = 'yahoojp';

/// WeChat 로그인 식별자 (Custom Token).
const String kProviderIdWeChat = 'wechat';

/// 등록된 모든 providerId 리스트.
///
/// 정적 config 평탄화 / Strategy ↔ config 일치 assert (Phase 11-03) 의 기준점.
/// 새 provider 추가 시 본 리스트 + [AppConfig.authProviders] / config JSON
/// 평탄 키를 동기화해야 한다.
const List<String> kAllProviderIds = <String>[
  kProviderIdGoogle,
  kProviderIdApple,
  kProviderIdFacebook,
  kProviderIdKakao,
  kProviderIdNaver,
  kProviderIdLine,
  kProviderIdYahooJp,
  kProviderIdWeChat,
];
