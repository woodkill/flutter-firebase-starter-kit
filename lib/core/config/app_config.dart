import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../auth/provider_id.dart';

part 'app_config.g.dart';

/// 정적 인증 Provider 활성화 맵 (Phase 11 D-17, D-18, D-20).
///
/// `--dart-define-from-file=config/{flavor}.json` 의 단일 키
/// `enabledAuthProviders` (CSV — 활성화할 도메인 ProviderId 슬러그를 쉼표로
/// 나열) 를 컴파일 타임 상수로 읽어 [Map] 으로 노출한다.
///
/// **Phase 11-04 hotfix — 단일 CSV 결정:** 11-02 가 처음에는 8개 평탄 키
/// (`authProvider_{providerId}_enabled`) 를 dart-define 으로 직접 lookup 하는
/// 방식을 채택했으나, Dart 의 `bool.fromEnvironment` 는 첫 번째 인자가 컴파일
/// 타임 상수 String 일 때만 환경 변수 lookup 을 수행한다 (T-11-CONST-01).
/// for-comprehension 안의 함수 호출 결과 (`configKeyForProvider(id)`) 를
/// 인자로 넘기면 Dart 가 lookup 을 수행하지 못하고 `defaultValue: false` 로
/// 떨어진다.
///
/// 이를 회피하기 위해 8 entry 를 명시 const 리터럴로 풀었었지만 (회귀 commit
/// 287714e), starter kit 의 "새 provider 추가 시 보일러플레이트 최소" 가치와
/// 충돌해 단일 CSV 키 + 런타임 split 방식으로 정착한다. 단일 컴파일 타임
/// 상수 키 1개만 사용하므로 컴파일 타임 안전성을 유지하면서, AppConfig 코드는
/// provider 추가에 영향받지 않는다.
///
/// **새 provider 추가 절차 (Phase 12+ 5개 Custom Token 등):**
/// 1. [provider_id] 에 새 슬러그 상수 + [kAllProviderIds] 에 추가
/// 2. config JSON 의 `enabledAuthProviders` CSV 에 슬러그 추가 (활성화 시)
/// 3. AuthStrategy 구현체 등록 (별개 작업)
///
/// AppConfig 코드는 영구 불변.
abstract final class AppConfig {
  const AppConfig._();

  /// 빌드 flavor 식별자 (`dev` / `stg` / `prod`).
  ///
  /// `--dart-define-from-file=config/{flavor}.json` 의 `flavor` 키를 컴파일
  /// 타임 상수로 읽는다. 미주입 시 빈 문자열 — silent fallback 회피
  /// (WR-07 hotfix). prod 빌드에서 `--dart-define-from-file` 누락 시 RC fetch
  /// 주기가 dev (0초) 로 떨어지는 회귀를 막기 위해 [isDev] 헬퍼를 통해서만
  /// 분기한다.
  static const String flavor = String.fromEnvironment('flavor');

  /// 현재 빌드가 dev flavor 인지 여부.
  ///
  /// [flavor] 가 정확히 `'dev'` 일 때만 true. 미주입 / 다른 flavor 는 false.
  /// bootstrap 의 RC fetch 주기 (D-23: dev=0, 그 외=12h) 를 단일 진실원으로
  /// 결정한다.
  static bool get isDev => flavor == 'dev';

  /// Kakao 네이티브 앱 키 (Phase 12 D-20).
  ///
  /// `--dart-define-from-file=config/{flavor}.json` 의 `kakaoNativeAppKey`
  /// 키를 컴파일 타임 상수로 읽는다. 미주입 시 빈 문자열 — silent fallback
  /// 회피 (Phase 11-04 WR-07 hotfix 패턴). Kakao SDK 초기화는 빈 문자열
  /// 시 PlatformException 으로 즉시 발견 가능 (silent failure 아님).
  ///
  /// dev flavor 만 실 키 주입 (memory `project_firebase_dev_only`),
  /// stg/prod 는 사용자가 자체 등록 — manual.md 의 Kakao 단락 참조.
  static const String kakaoNativeAppKey = String.fromEnvironment(
    'kakaoNativeAppKey',
    defaultValue: '',
  );

  /// Naver 로그인 SDK 빌드타임 시크릿 3종 (Phase 13 — see ROADMAP.md).
  ///
  /// `--dart-define-from-file=config/{flavor}.json` 의 `naverClientId` /
  /// `naverClientSecret` / `naverUrlScheme` 키를 컴파일 타임 상수로 읽는다.
  /// Phase 12 의 [kakaoNativeAppKey] 패턴과 일관 — 미주입 시 빈 문자열,
  /// silent fallback 회피 (WR-07 hotfix). [NaverLoginSDK.initialize] 호출
  /// 시점에 빈 문자열이면 SDK assertion / 첫 API 호출에서 즉시 실패하므로
  /// silent failure 아님 (D-60).
  ///
  /// dev flavor 만 실 키 주입 (memory `project_firebase_dev_only`),
  /// stg/prod 는 사용자가 자체 등록 — manual.md 의 Naver 단락 참조 (Plan 13-07).
  static const String _naverClientId = String.fromEnvironment(
    'naverClientId',
    defaultValue: '',
  );
  static const String _naverClientSecret = String.fromEnvironment(
    'naverClientSecret',
    defaultValue: '',
  );
  static const String _naverUrlScheme = String.fromEnvironment(
    'naverUrlScheme',
    defaultValue: '',
  );

  /// Naver 로그인 클라이언트 ID. Naver Developers Console 의 Client ID 값.
  static String get naverClientId => _naverClientId;

  /// Naver 로그인 클라이언트 Secret. SDK init 의무 인자 (D-60 — 사용처 0건).
  static String get naverClientSecret => _naverClientSecret;

  /// Naver 로그인 URL Scheme. iOS only (Android 는 SDK 자동 머지).
  static String get naverUrlScheme => _naverUrlScheme;

  /// LINE Channel ID — public client identifier (Phase 14 D-LINE-16).
  ///
  /// `--dart-define-from-file=config/{flavor}.json` 의 `lineChannelId` 키를
  /// 컴파일 타임 상수로 읽는다. Phase 12 의 [kakaoNativeAppKey] / Phase 13 의
  /// [naverClientId] 패턴과 일관 — 미주입 시 빈 문자열, silent fallback 회피
  /// (WR-07 hotfix). [LineSDK.instance.setup] 호출 시점에 빈 문자열이면 SDK
  /// assertion / 첫 API 호출에서 즉시 실패하므로 silent failure 아님.
  ///
  /// dev flavor 만 실 키 주입 (memory `project_firebase_dev_only`),
  /// stg/prod 는 사용자가 자체 등록 — manual.md 의 LINE 단락 참조.
  ///
  /// LINE Channel Secret 은 client 측에 미저장 (D-LINE-18 — Cloud Function
  /// 의 Secret Manager 단독 보관). client 는 Channel ID 만 보유하면 OIDC
  /// 흐름 수행 가능.
  static const String lineChannelId = String.fromEnvironment(
    'lineChannelId',
    defaultValue: '',
  );

  /// Yahoo!JP OAuth/OIDC Client ID — public client identifier (Phase 15 D-YJP-03).
  ///
  /// `--dart-define-from-file=config/{flavor}.json` 의 `yahoojpClientId` 키를
  /// 컴파일 타임 상수로 읽는다. Phase 12 의 [kakaoNativeAppKey] / Phase 13 의
  /// [naverClientId] / Phase 14 의 [lineChannelId] 패턴과 일관 — 미주입 시
  /// 빈 문자열, silent fallback 회피 (WR-07 hotfix). [YahoojpSdkClient.signIn]
  /// 호출 시점에 빈 문자열이면 [ServiceUnavailable] throw — silent failure
  /// 회피 (T-15-15 mitigation, D-YJP-03 carry-forward).
  ///
  /// dev flavor 만 실 키 주입 (memory `project_firebase_dev_only`),
  /// stg/prod 는 사용자가 자체 등록 — manual.md 의 Yahoo!JP 단락 참조.
  ///
  /// Yahoo Developers Console "クライアントサイド・アプリケーション" 등록
  /// 시 client_secret 발급 X (D-YJP-03 — public client OIDC + PKCE 전제). client
  /// 는 Client ID 만 보유하면 OIDC 흐름 수행 가능.
  static const String yahoojpClientId = String.fromEnvironment(
    'yahoojpClientId',
    defaultValue: '',
  );

  /// Yahoo!JP OAuth redirect scheme — custom URL scheme (Phase 15 D-YJP-03).
  ///
  /// `--dart-define-from-file=config/{flavor}.json` 의 `yahoojpRedirectScheme`
  /// 키를 컴파일 타임 상수로 읽는다. Android 는 `manifestPlaceholders[
  /// "appAuthRedirectScheme"]` 가 자동 inject (Plan 15-01 build.gradle.kts),
  /// iOS 는 `Info.plist CFBundleURLTypes` 가 `$(YAHOOJP_REDIRECT_SCHEME)`
  /// xcconfig 변수로 주입 (Plan 15-01).
  ///
  /// [YahoojpSdkClient] 생성자는 본 값을 `${scheme}:/oauth2redirect` 패턴으로
  /// flutter_appauth 의 redirectUrl 인자에 주입한다.
  ///
  /// 미주입 시 빈 문자열 → flutter_appauth 첫 호출 시점에 즉시 실패 (silent
  /// failure 아님). Yahoo Developers Console Redirect URI 의 custom scheme 부분과
  /// 1:1 일치 의무 (T-15-02 mitigation).
  static const String yahoojpRedirectScheme = String.fromEnvironment(
    'yahoojpRedirectScheme',
    defaultValue: '',
  );

  /// 활성화된 ProviderId CSV — `--dart-define-from-file` 컴파일 타임 상수.
  ///
  /// 예: `'google,apple,facebook'`. 공백 / 빈 토큰은 무시한다. dart-define
  /// 미주입 시 빈 문자열 → 모두 disabled (D-21 안전 default).
  static const String _enabledRaw = String.fromEnvironment(
    'enabledAuthProviders',
    defaultValue: '',
  );

  /// 정적 활성화 맵을 반환한다.
  ///
  /// CSV 토큰을 set 으로 파싱한 뒤 [kAllProviderIds] 의 8 슬러그 모두에 대해
  /// membership 을 [bool] 로 노출한다. 미주입 / 미등록 슬러그는 [false]
  /// 안전 default (D-21).
  ///
  /// 반환 맵은 [Map.unmodifiable] 으로 감싸 정적 진실의 런타임 변조를
  /// 방어한다 (WR-02 hotfix) — D-26 의 "정적 false 절대 우위" invariant 가
  /// future contributor / 테스트 코드의 잘못된 변경에 무방비하지 않도록.
  static Map<String, bool> get authProviders {
    final enabled = _enabledRaw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    return Map<String, bool>.unmodifiable(<String, bool>{
      for (final id in kAllProviderIds) id: enabled.contains(id),
    });
  }

  /// 단일 슬러그의 정적 활성화 여부를 반환한다 (테스트/UI 가독성용 헬퍼).
  ///
  /// 의미상 [authProviders][providerId] 와 동일하지만 set membership 을
  /// 명시적으로 노출해 "CSV 가 정적 진실" 을 강조한다.
  static bool isEnabledStatically(String providerId) =>
      authProviders[providerId] ?? false;
}

/// 정적 활성화 맵 Provider — Registry ([activeStrategies]) 가 watch.
///
/// keepAlive: 빌드 타임 상수 — 앱 생명주기 동안 불변.
@Riverpod(keepAlive: true)
Map<String, bool> staticAuthProviders(Ref ref) => AppConfig.authProviders;
