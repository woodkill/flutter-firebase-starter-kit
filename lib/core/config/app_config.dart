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
  static Map<String, bool> get authProviders {
    final enabled = _enabledRaw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    return <String, bool>{
      for (final id in kAllProviderIds) id: enabled.contains(id),
    };
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
