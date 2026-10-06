/// 인증 Provider 식별자 const String 상수 + 등록된 ID 리스트 (Phase 11 D-20).
///
/// **도메인 ProviderId 는 단순 슬러그**: `google` / `apple` / `facebook` /
/// `kakao` / `naver` / `line`. [kAllProviderIds] 의 모든 provider 가
/// 동일한 키 패턴을 공유하며, Strategy.providerId / Remote Config 키 prefix
/// 모두 이 슬러그를 직접 사용한다 — [rcKeyForProvider] 가 단순 prefix 결합만
/// 수행.
///
/// **정적 활성화는 단일 CSV 진실:** `--dart-define-from-file` 의 단일 키
/// `enabledAuthProviders` (CSV) 가 정적 enabled 의 단일 진실이다 — 자세한
/// 내용은 [AppConfig.authProviders] 참조. 그 외 provider 별 평탄 키
/// `authProvider_*_enabled` 는 사용하지 않는다 (11-02 → 11-04 hotfix 결정).
/// IN-06 정정 (Phase 7 review): 개수를 문장에 박지 않는다 — 등록 목록의
/// 진실원은 [kAllProviderIds] 다.
///
/// **Firebase Auth providerId (`'google.com'` 등) 와는 분리.** `User.providerData`
/// 가 노출하는 OAuth URI 형식은 우리 도메인 식별자가 아니라 Firebase 가
/// 자체적으로 반환하는 외부 형식이다. URI → enum 변환은
/// [AccountProvider.tryParse] 한 곳이 맡고 (Phase 16.7), 표시 라벨 변환은
/// [provider_label_formatter] 등 boundary 에서만 처리한다.
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

/// 등록된 모든 providerId 리스트.
///
/// 정적 config 평탄화 / Strategy ↔ config 일치 assert (Phase 11-03) 의 기준점.
/// 새 provider 추가 시 본 리스트에 슬러그 추가 + config JSON 의
/// `enabledAuthProviders` CSV 에 토큰 추가 (활성화 시) 만 하면 된다 —
/// `AppConfig` 코드는 영구 불변 (Phase 11-04 단일 CSV 결정).
const List<String> kAllProviderIds = <String>[
  kProviderIdGoogle,
  kProviderIdApple,
  kProviderIdFacebook,
  kProviderIdKakao,
  kProviderIdNaver,
  kProviderIdLine,
];

/// 주어진 providerId 의 Remote Config 매개변수 키.
///
/// 도메인 ProviderId 가 slug 형태이므로 단순 prefix 결합만 수행한다.
/// setDefaults (`bootstrap.dart`) 와 registry `_isEnabled` 가 동일한 키를
/// 사용해야 kill switch (D-28) 가 동작한다.
///
/// - `google`   → `auth_provider_google_enabled`
/// - `kakao`    → `auth_provider_kakao_enabled`
String rcKeyForProvider(String providerId) =>
    'auth_provider_${providerId}_enabled';

/// 인증 식별자 + ARB key 매핑 enum — **소셜 ([kAllProviderIds]) + email**
/// (Phase 9.2 deferred R1 부활).
///
/// **IN-06 정정 (Phase 7 review):** 이전 문서는 (당시) "8 provider" 라고 적어
/// [kAllProviderIds] (당시 소셜 7) 와 어긋났고, 본 enum 만 email 을 포함해
/// (당시) 8값이라는 점이 혼동을 불렀다. 개수를 문장에 박는 대신 구성으로 표현하고
/// 목록 자체를 가리킨다 (`app_config.dart` 의 IN-04 정정 선례).
///
/// **Phase 16 Task 4.1** — Phase 9.2 P-A-narrow 시점 deferred 되었던 R1 의
/// client-side enum 인프라를 본 enum 으로 부활. `AccountLinkingSheet` (D-01/
/// D-02/D-03) + `_resolveAccountExists` provider-aware variant (D-12) +
/// `AccountExistsWithDifferentCredential.existingProvider` 필드 (D-12) 가
/// 모두 본 enum 을 single source of truth 로 사용한다.
///
/// **slug 와의 관계:** [tryParse] 로 [kProviderIdGoogle] 등 slug 또는 Cloud
/// Function `lookupSignInMethods` 응답 (`existingProvider: "kakao"`) 을
/// 받아 enum 으로 변환한다. unknown slug → null (R2 unknown fallback).
///
/// **email 매핑 (`authAccountProviderEmailPassword`):** Email/Password 는 정확히
/// 1 ARB key 만 보존 ("Email / Password"). slug `email` 은 `lookupSignInMethods`
/// callable 의 native path (`providerData: ["password"]`) 응답에 사용된다.
///
/// **exhaustive switch 의무:** Dart 3 enhanced enum + switch expression
/// exhaustive — 신규 provider 추가 시 analyze 가 unhandled case 발견 즉시
/// BLOCKER. T-16-NEW-XX-ENUM mitigation.
enum AccountProvider {
  /// Google 로그인 (native, providerData=`google.com`).
  google,

  /// Apple 로그인 (native, providerData=`apple.com`).
  apple,

  /// Facebook 로그인 (native, providerData=`facebook.com`).
  facebook,

  /// Email/Password 로그인 (native, providerData=`password`).
  email,

  /// Kakao 로그인 (Custom Token, identity_index 기반).
  kakao,

  /// Naver 로그인 (Custom Token).
  naver,

  /// LINE 로그인 (Custom Token).
  line;

  /// native provider (Firebase Auth 직접 연동) 여부 (Phase 16 16-08).
  ///
  /// `true` — google / apple / facebook / email (native:
  /// `linkWithCredential` 기반 reactive link arm 대상). `false` — Custom
  /// Token 3값 (kakao / naver / line: provider 전용 연결 callable
  /// `linkKakaoProvider` · `linkNaverProvider` · `linkLineProvider` 기반,
  /// 16-09 책임). LoginScreen 의 sheet 분기 + 16-09 의 Custom Token sheet
  /// 분기가 본 getter 를 공유한다.
  /// (Phase 16.1 — 소셜 섹션을 함께 담던 구 가입 화면이 삭제되어 sheet
  /// 호출처는 1곳이다.)
  bool get isNative => switch (this) {
    AccountProvider.google ||
    AccountProvider.apple ||
    AccountProvider.facebook ||
    AccountProvider.email => true,
    AccountProvider.kakao ||
    AccountProvider.naver ||
    AccountProvider.line => false,
  };

  /// 도메인 slug 문자열 (`google` / `kakao` / `line` 등).
  ///
  /// [tryParse] 의 역변환 — [kProviderIdGoogle] 등 const String 슬러그와 1:1
  /// 일치한다. 해제 callable payload · 로그 등 provider 식별에 쓴다 (연결
  /// callable 은 provider 별 이름이 provider 를 고정해 payload 에 싣지
  /// 않는다). [email] 은 Firebase Auth `password` providerData 도메인이지만
  /// 본 getter 는 slug 형태 `email` 을 반환한다 ([tryParse] 의
  /// `'email' || 'password'` 양방향과 대칭 — link callable 의 target 대상은
  /// 아님).
  String get slug => switch (this) {
    AccountProvider.google => kProviderIdGoogle,
    AccountProvider.apple => kProviderIdApple,
    AccountProvider.facebook => kProviderIdFacebook,
    AccountProvider.email => 'email',
    AccountProvider.kakao => kProviderIdKakao,
    AccountProvider.naver => kProviderIdNaver,
    AccountProvider.line => kProviderIdLine,
  };

  /// AppLocalizations getter 이름 — `authAccountProvider{X}` ARB key.
  ///
  /// 3 locale (ko/en/ja) 모두 `lib/l10n/app_*.arb` 에 정의 완료 (Phase 9.2
  /// P-A-narrow 시점 정착). 본 getter 가 반환하는 key 는 exception_l10n.dart
  /// 의 `_resolveProviderLabel` 와 AccountLinkingSheet 의 본문 라벨 변환에
  /// 사용된다.
  String get arbKey => switch (this) {
    AccountProvider.google => 'authAccountProviderGoogle',
    AccountProvider.apple => 'authAccountProviderApple',
    AccountProvider.facebook => 'authAccountProviderFacebook',
    AccountProvider.email => 'authAccountProviderEmailPassword',
    AccountProvider.kakao => 'authAccountProviderKakao',
    AccountProvider.naver => 'authAccountProviderNaver',
    AccountProvider.line => 'authAccountProviderLine',
  };

  /// slug 문자열을 [AccountProvider] 로 안전 변환한다.
  ///
  /// Cloud Function `lookupSignInMethods` 응답 (`{existingProvider: "kakao"}`
  /// 또는 `{existingProvider: null}`) 의 매핑에 사용된다. 알 수 없는 slug 또는
  /// `null` 입력은 `null` 반환 (R2 unknown fallback).
  ///
  /// **IN-03 정정 (Phase 7 review):** 정변환 [slug] 는 [kProviderIdGoogle]
  /// 등 const 를 쓰는데 역변환인 본 메서드만 문자열 리터럴을 써서, 상수 값이
  /// 바뀌면 정·역변환이 조용히 어긋났다. Dart 3 는 const 변수를 switch 패턴
  /// 으로 허용하므로 동일 상수를 공유한다. `'email'` / `'password'` 만
  /// 리터럴로 남긴다 — 전자는 [slug] 와 짝을 이루는 도메인 리터럴,
  /// 후자는 Firebase Auth `providerData` 의 외부 계약 문자열이다.
  ///
  /// **Phase 16.7 D-05:** native provider 의 URI(`'google.com'` 등)도 같은
  /// 지위의 리터럴로 함께 인식한다 — Firebase `providerData.providerId` 가
  /// 돌려주는 외부 계약 문자열이라 `'password'` 와 같다. `User.providerIds`
  /// 는 URI 와 slug 가 섞여 있으므로, 표시 정렬(`provider_label_formatter`)
  /// · 계정 연결 섹션 · 재인증 수단 계산이 URI ↔ slug 변환을 모두 본 메서드
  /// 하나로 처리한다.
  static AccountProvider? tryParse(String? slug) => switch (slug) {
    kProviderIdGoogle || 'google.com' => AccountProvider.google,
    kProviderIdApple || 'apple.com' => AccountProvider.apple,
    kProviderIdFacebook || 'facebook.com' => AccountProvider.facebook,
    'email' || 'password' => AccountProvider.email,
    kProviderIdKakao => AccountProvider.kakao,
    kProviderIdNaver => AccountProvider.naver,
    kProviderIdLine => AccountProvider.line,
    _ => null,
  };
}
