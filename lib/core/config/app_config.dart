import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../auth/provider_id.dart';

part 'app_config.g.dart';

/// 정적 인증 Provider 활성화 맵 (Phase 11 D-17, D-18, D-20).
///
/// `--dart-define-from-file=config/{flavor}.json` 의 단일 키
/// `enabledAuthProviders` (CSV — 활성화할 도메인 ProviderId 슬러그를 쉼표로
/// 나열) 를 컴파일 타임 상수로 읽어 [Map] 으로 노출한다.
///
/// **Phase 11-04 hotfix — 단일 CSV 결정:** 11-02 가 처음에는 provider 별 평탄 키
/// (`authProvider_{providerId}_enabled`) 를 dart-define 으로 직접 lookup 하는
/// 방식을 채택했으나, Dart 의 `bool.fromEnvironment` 는 첫 번째 인자가 컴파일
/// 타임 상수 String 일 때만 환경 변수 lookup 을 수행한다 (T-11-CONST-01).
/// for-comprehension 안의 함수 호출 결과 (`configKeyForProvider(id)`) 를
/// 인자로 넘기면 Dart 가 lookup 을 수행하지 못하고 `defaultValue: false` 로
/// 떨어진다.
///
/// 이를 회피하기 위해 전 entry 를 명시 const 리터럴로 풀었었지만 (회귀 commit
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

  /// 앱 표시 이름 — `--dart-define-from-file` 의 `appName` 키.
  ///
  /// 미주입 시 빈 문자열 — silent fallback 회피 (WR-07 hotfix 패턴). 키 이름을
  /// 오타 내도 defaultValue 로 그럴듯한 값이 나오지 않아 즉시 검출된다.
  ///
  /// **표기 규칙 (IN-02 리뷰 — 파일 전체 공통):** 본 클래스의 모든
  /// `String.fromEnvironment` 는 `defaultValue` 인자를 **생략**한다.
  /// `String.fromEnvironment` 의 기본 defaultValue 가 이미 `''` 이므로
  /// `defaultValue: ''` 는 동작상 무의미한데, 일부만 명시하면 독자가 두 표기의
  /// 의미 차이를 찾느라 시간을 쓴다. 빈 문자열 자체가 "미주입" sentinel 이며,
  /// 그 값을 무엇으로 대체할지는 소비처가 결정한다 (`App` 은 l10n 의
  /// `appTitle`, 환경 정보 화면은 경고 chip).
  /// 빈 문자열일 때 표시 문자열을 무엇으로 대체할지는 소비처가 결정한다
  /// (`App` 은 l10n 의 `appTitle`, 환경 정보 화면은 경고 chip).
  static const String appName = String.fromEnvironment('appName');

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
  ///
  /// **IN-03:** 과거 Naver 3종만 `private const` + `public getter` 2단 구조라
  /// 다른 키들(전부 public `static const`)과 일관성이 깨졌고, getter 는 const
  /// 문맥에서 쓸 수 없어 소비처의 선택지도 좁았다. 지금은 평탄화되어 다른
  /// 키와 동일한 방식으로 쓸 수 있다.

  /// Naver 로그인 클라이언트 ID. Naver Developers Console 의 Client ID 값.
  static const String naverClientId = String.fromEnvironment('naverClientId');

  /// Naver 로그인 클라이언트 Secret.
  ///
  /// `NaverLoginSDK.initialize` 의 의무 인자로 `bootstrap.dart` 에서 1회
  /// 사용한다. 그 외 참조는 없다 (IN-03 — 과거 doc 의 "사용처 0건" 은 실제와
  /// 어긋났다).
  ///
  /// **fork 사용자 주의:** 클라이언트 시크릿은 앱 바이너리에서 추출 가능하다
  /// (Naver SDK 가 client 측 초기화 인자로 요구하는 설계상 불가피하다).
  /// 이 값은 서버 시크릿이 아니며, 반드시 **자신의 키를 발급받아** 사용할 것 —
  /// 스타터킷의 dev 키를 그대로 배포하지 말 것.
  static const String naverClientSecret = String.fromEnvironment(
    'naverClientSecret',
  );

  /// Naver 로그인 URL Scheme. iOS only (Android 는 SDK 자동 머지).
  static const String naverUrlScheme = String.fromEnvironment('naverUrlScheme');

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
  static const String lineChannelId = String.fromEnvironment('lineChannelId');

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
  );

  /// 활성화된 ProviderId CSV — `--dart-define-from-file` 컴파일 타임 상수.
  ///
  /// 예: `'google,apple,facebook'`. 공백 / 빈 토큰은 무시한다. dart-define
  /// 미주입 시 빈 문자열 → 모두 disabled (D-21 안전 default).
  static const String _enabledRaw = String.fromEnvironment(
    'enabledAuthProviders',
  );

  /// 정적 활성화 맵을 반환한다.
  ///
  /// CSV 토큰을 set 으로 파싱한 뒤 [kAllProviderIds] 의 **모든 슬러그**에 대해
  /// membership 을 [bool] 로 노출한다. 미주입 / 미등록 슬러그는 [false]
  /// 안전 default (D-21).
  ///
  /// IN-04: 과거 doc 은 슬러그 개수를 숫자로 못박았는데 그 숫자가 실제
  /// [kAllProviderIds] 길이와 달랐다 (`email` 은 목록에 없다 —
  /// `exception_l10n.dart` 의 provider 개수 서술과 혼동된 값이다). 개수는
  /// provider 추가/폐기마다 바뀌므로 (Phase 16 WeChat 폐기 등) doc 에서
  /// 숫자를 제거하고 목록 자체를 가리킨다.
  ///
  /// 반환 맵은 [Map.unmodifiable] 으로 감싸 정적 진실의 런타임 변조를
  /// 방어한다 (WR-02 hotfix) — D-26 의 "정적 false 절대 우위" invariant 가
  /// future contributor / 테스트 코드의 잘못된 변경에 무방비하지 않도록.
  static Map<String, bool> get authProviders =>
      parseEnabledProviders(_enabledRaw);

  /// [raw] CSV 를 정적 활성화 맵으로 파싱한다 (WR-09).
  ///
  /// [authProviders] 의 본체이며, `_enabledRaw` 가 컴파일 타임 상수라 테스트가
  /// 다른 CSV 를 주입할 수 없으므로 순수 함수로 분리해 [visibleForTesting]
  /// 으로 노출한다.
  ///
  /// **미지 슬러그는 debug 에서 즉시 실패시킨다.** 결과 맵은
  /// [kAllProviderIds] 로만 구성되므로 CSV 에 들어 있지만 알려진 슬러그가
  /// 아닌 토큰은 아무 흔적 없이 버려졌다. `"gogle,apple"` (오타),
  /// `"Google,apple"` (대소문자), `"google;apple"` (구분자 오타) 는 모두
  /// analyze 통과 · 런타임 무증상이며, 증상은 "로그인 화면에 Google 버튼이
  /// 없다" 로만 나타난다. config JSON 은 IDE 자동완성도 스키마 검증도 없는
  /// 평문이라 오타 확률이 낮지 않다.
  ///
  /// 안전 default 자체(D-21 — 모르는 것은 false)는 유지한다. 이 검사는
  /// **"의도적으로 끈 것" 과 "오타로 꺼진 것" 을 구분할 수단**을 더하는 것이며,
  /// 같은 파일이 5곳에서 반복 선언한 "silent fallback 회피" 원칙과 정합한다.
  /// release 빌드에서는 평가되지 않으므로 프로덕션 동작은 그대로다.
  @visibleForTesting
  static Map<String, bool> parseEnabledProviders(String raw) {
    final enabled = raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    assert(() {
      final unknown = enabled.difference(kAllProviderIds.toSet());
      if (unknown.isNotEmpty) {
        throw StateError(
          'enabledAuthProviders 에 미지의 슬러그: ${unknown.join(", ")}. '
          'config/{flavor}.json 오타이거나 kAllProviderIds 등록 누락이다 '
          '(알려진 슬러그: ${kAllProviderIds.join(", ")}).',
        );
      }
      return true;
    }());
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
