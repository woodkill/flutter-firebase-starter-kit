/// 인증 Provider 식별자 const String 상수 + 등록된 ID 리스트 (Phase 11 D-20).
///
/// Strategy.providerId / config key 는 Firebase Auth providerId ('google.com'
/// 등) 와 정합한다. Remote Config 매개변수 키만 RC 의 키 정책
/// (`[A-Za-z_][A-Za-z0-9_]*`) 에 맞춰 점을 언더스코어로 정규화 — [rcKeyForProvider]
/// 헬퍼를 단일 출처로 사용한다 (Phase 11-04 hotfix).
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

/// 주어진 providerId 의 Remote Config 매개변수 키.
///
/// Firebase Remote Config 의 매개변수 키 정책 `[A-Za-z_][A-Za-z0-9_]*` 은
/// 점(`.`) 을 거부하므로 OAuth URI 형식 (`google.com` 등) 의 점을 언더스코어로
/// 치환한다. setDefaults 와 registry `_isEnabled` 가 동일한 키를 사용해야
/// kill switch (D-28) 가 동작한다 (Phase 11-04 hotfix).
///
/// - `google.com`   → `auth_provider_google_com_enabled`
/// - `apple.com`    → `auth_provider_apple_com_enabled`
/// - `facebook.com` → `auth_provider_facebook_com_enabled`
/// - `kakao`        → `auth_provider_kakao_enabled`
String rcKeyForProvider(String providerId) =>
    'auth_provider_${providerId.replaceAll('.', '_')}_enabled';

/// 주어진 providerId 의 dart-define 평탄 키 (config/{flavor}.json + AppConfig).
///
/// `--dart-define-from-file` 이 주입하는 컴파일 타임 환경 변수의 키도 식별자
/// 정책 `[A-Za-z_][A-Za-z0-9_]*` 을 따르므로 OAuth URI 형식 ('google.com' 등)
/// 의 점을 그대로 키에 넣으면 `bool.fromEnvironment` lookup 이 실패해
/// `defaultValue: false` 로 떨어진다 (Phase 11-04 hotfix).
///
/// - `google.com`   → `authProvider_google_com_enabled`
/// - `apple.com`    → `authProvider_apple_com_enabled`
/// - `facebook.com` → `authProvider_facebook_com_enabled`
/// - `kakao`        → `authProvider_kakao_enabled`
String configKeyForProvider(String providerId) =>
    'authProvider_${providerId.replaceAll('.', '_')}_enabled';
