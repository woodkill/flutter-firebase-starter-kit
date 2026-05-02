import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../auth/provider_id.dart';

part 'app_config.g.dart';

/// 정적 인증 Provider 활성화 맵 (Phase 11 D-17, D-18, D-20).
///
/// `--dart-define-from-file=config/{flavor}.json` 의 평탄 키
/// `authProvider_{providerId}_enabled` (boolean) 을 모아 [Map] 으로 노출한다.
///
/// **Pitfall 2 결정 (Phase 11):** `--dart-define-from-file` 은 nested 객체를
/// dart 환경에 직접 노출하지 않으므로, 가독성 `authProviders: {...}` 객체와
/// dart 읽기용 평탄 키 `authProvider_{id}_enabled` 를 config JSON 에 동시에
/// 보관한다. 두 형태의 동기화는 [app_config_test] 가 검증한다.
abstract final class AppConfig {
  const AppConfig._();

  /// 정적 활성화 맵을 반환한다.
  ///
  /// 미주입 키는 [false] 안전 default (D-21).
  /// 모든 8 providerId ([kAllProviderIds]) 를 키로 보유한다.
  static Map<String, bool> get authProviders => <String, bool>{
    for (final id in kAllProviderIds)
      id: bool.fromEnvironment(
        'authProvider_${id}_enabled',
        defaultValue: false,
      ),
  };
}

/// 정적 활성화 맵 Provider — Registry ([activeStrategies]) 가 watch.
///
/// keepAlive: 빌드 타임 상수 — 앱 생명주기 동안 불변.
@Riverpod(keepAlive: true)
Map<String, bool> staticAuthProviders(Ref ref) => AppConfig.authProviders;
