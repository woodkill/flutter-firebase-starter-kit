/// 인증 Provider 식별자 const String 상수 + 등록된 ID 리스트 (Phase 11 D-20).
///
/// **도메인 ProviderId 는 단순 슬러그**: `google` / `apple` / `facebook` /
/// `kakao` / `naver` / `line` / `yahoojp` / `wechat`. 모든 8 provider 가
/// 동일한 키 패턴을 공유하며, Strategy.providerId / config key / Remote Config
/// 키 prefix 모두 이 슬러그를 직접 사용한다 — `[rcKeyForProvider]` /
/// `[configKeyForProvider]` 는 단순 prefix 결합만 수행.
///
/// **Firebase Auth providerId (`'google.com'` 등) 와는 분리.** `User.providerData`
/// 가 노출하는 OAuth URI 형식은 우리 도메인 식별자가 아니라 Firebase 가
/// 자체적으로 반환하는 외부 형식이다. URI ↔ slug 간 매핑이 필요한 곳은
/// [provider_label_formatter] 등 boundary 에서만 처리한다.
///
/// **Phase 11-04 hotfix 결정:** 11-02 가 처음에는 OAuth URI 형식을 도메인
/// ProviderId 로 그대로 채택했으나, 점이 들어간 키가 dart-define / Firebase
/// Remote Config 매개변수 키 정책 (`[A-Za-z_][A-Za-z0-9_]*`) 을 위반해 정적
/// enabled / kill switch 가 동작 못 하는 회귀가 발생했다. 통일성과 키 정책
/// 적합성을 동시에 확보하기 위해 도메인 ProviderId 자체를 slug 로 정규화.
library;

/// Google 로그인 식별자 (도메인 slug — Firebase Auth providerId 는 'google.com').
const String kProviderIdGoogle = 'google';

/// Apple 로그인 식별자 (도메인 slug — Firebase Auth providerId 는 'apple.com').
const String kProviderIdApple = 'apple';

/// Facebook 로그인 식별자 (도메인 slug — Firebase Auth providerId 는 'facebook.com').
const String kProviderIdFacebook = 'facebook';

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
/// 도메인 ProviderId 가 slug 형태이므로 점 정규화 없이 단순 prefix 결합만
/// 수행한다. setDefaults (`bootstrap.dart`) 와 registry `_isEnabled` 가 동일한
/// 키를 사용해야 kill switch (D-28) 가 동작한다.
///
/// - `google`   → `auth_provider_google_enabled`
/// - `kakao`    → `auth_provider_kakao_enabled`
String rcKeyForProvider(String providerId) =>
    'auth_provider_${providerId}_enabled';

/// 주어진 providerId 의 dart-define 평탄 키 (config/{flavor}.json + AppConfig).
///
/// `--dart-define-from-file` 이 주입하는 컴파일 타임 환경 변수의 키 정책
/// `[A-Za-z_][A-Za-z0-9_]*` 과 정합. 도메인 ProviderId 가 slug 형태이므로
/// 점 정규화 불필요.
///
/// - `google`   → `authProvider_google_enabled`
/// - `kakao`    → `authProvider_kakao_enabled`
String configKeyForProvider(String providerId) =>
    'authProvider_${providerId}_enabled';
