import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../auth/provider_id.dart';

part 'app_config.g.dart';

/// 정적 인증 Provider 활성화 맵 (Phase 11 D-17, D-18, D-20).
///
/// `--dart-define-from-file=config/{flavor}.json` 의 평탄 키
/// `authProvider_{providerId}_enabled` (boolean) 을 컴파일 타임 상수로 읽어
/// [Map] 으로 노출한다.
///
/// **Pitfall 2 결정 (Phase 11):** `--dart-define-from-file` 은 nested 객체를
/// dart 환경에 직접 노출하지 않으므로, 가독성 `authProviders: {...}` 객체와
/// dart 읽기용 평탄 키를 config JSON 에 동시에 보관한다. 두 형태의 동기화는
/// [app_config_test] 가 검증한다.
///
/// **Phase 11-04 hotfix — 컴파일 타임 상수 제약 (Pitfall 2 보강):**
/// `bool.fromEnvironment` 는 **첫 번째 인자가 컴파일 타임 상수 String** 일 때만
/// `--dart-define` lookup 이 동작한다. for-comprehension 이나 함수 호출 결과
/// (예: `configKeyForProvider(id)`) 를 인자로 넘기면 Dart 가 환경 변수
/// lookup 을 수행하지 못하고 `defaultValue: false` 로 떨어진다 (T-11-CONST-01).
///
/// 따라서 8개 entry 를 모두 const 리터럴 키로 명시한다. [configKeyForProvider]
/// 헬퍼는 setDefaults 와 registry 의 런타임 lookup (RC `getAll/getBool`) 에서만
/// 사용 — 그쪽은 컴파일 타임 상수 제약이 없다.
abstract final class AppConfig {
  const AppConfig._();

  /// 정적 활성화 맵을 반환한다.
  ///
  /// 미주입 키는 [false] 안전 default (D-21).
  /// 모든 8 providerId ([kAllProviderIds]) 를 키로 보유한다.
  ///
  /// 8 entry 모두 const 리터럴 키 — Dart 컴파일 타임 상수 제약 (T-11-CONST-01).
  /// 새 provider 추가 시 본 맵 + [kAllProviderIds] + config JSON 평탄 키를
  /// 함께 갱신해야 한다.
  static const Map<String, bool> authProviders = <String, bool>{
    kProviderIdGoogle: bool.fromEnvironment(
      'authProvider_google_enabled',
      defaultValue: false,
    ),
    kProviderIdApple: bool.fromEnvironment(
      'authProvider_apple_enabled',
      defaultValue: false,
    ),
    kProviderIdFacebook: bool.fromEnvironment(
      'authProvider_facebook_enabled',
      defaultValue: false,
    ),
    kProviderIdKakao: bool.fromEnvironment(
      'authProvider_kakao_enabled',
      defaultValue: false,
    ),
    kProviderIdNaver: bool.fromEnvironment(
      'authProvider_naver_enabled',
      defaultValue: false,
    ),
    kProviderIdLine: bool.fromEnvironment(
      'authProvider_line_enabled',
      defaultValue: false,
    ),
    kProviderIdYahooJp: bool.fromEnvironment(
      'authProvider_yahoojp_enabled',
      defaultValue: false,
    ),
    kProviderIdWeChat: bool.fromEnvironment(
      'authProvider_wechat_enabled',
      defaultValue: false,
    ),
  };
}

/// 정적 활성화 맵 Provider — Registry ([activeStrategies]) 가 watch.
///
/// keepAlive: 빌드 타임 상수 — 앱 생명주기 동안 불변.
@Riverpod(keepAlive: true)
Map<String, bool> staticAuthProviders(Ref ref) => AppConfig.authProviders;
