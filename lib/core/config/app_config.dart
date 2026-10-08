import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../auth/provider_id.dart';

part 'app_config.g.dart';

/// 인증 · 재설정 메일을 누가 보내는지 고르는 발송 모드 (Phase 17.5 D-09).
///
/// config 키 `emailDelivery` 의 값과 1:1 이다 — [AppConfig.emailDeliveryMode]
/// 가 파싱 결과를 주고, 배포 스크립트도 같은 키를 같은 규칙으로 읽는다.
enum EmailDeliveryMode {
  /// Firebase Auth 가 기본 템플릿으로 보낸다 (기본값 · 추가 설정 0).
  firebase,

  /// 킷 callable 이 메일을 렌더해 `mail` 컬렉션에 쓰고, Trigger Email 확장이
  /// 사용자가 설정한 SMTP 발송 서비스로 보낸다.
  kit,
}

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
  /// **표기 규칙 (IN-02 리뷰 — 파일 전체 공통):** 시크릿·식별자 키는
  /// `defaultValue` 인자를 **생략**한다. `String.fromEnvironment` 의 기본
  /// defaultValue 가 이미 `''` 이므로 `defaultValue: ''` 는 동작상 무의미한데,
  /// 일부만 명시하면 독자가 두 표기의 의미 차이를 찾느라 시간을 쓴다. 빈
  /// 문자열 자체가 "미주입" sentinel 이며, 그 값을 무엇으로 대체할지는
  /// 소비처가 결정한다 (`App` 은 l10n 의 `appTitle`, 환경 정보 화면은 경고
  /// chip).
  ///
  /// **예외 — 유의미한 non-empty default.** 빈 값이 애초에 유효하지 않고
  /// 기본값이 곧 프로젝트 표준인 운영 상수는 default 를 명시한다
  /// ([functionsRegion] 이 유일한 사례다). 금지되는 것은 `defaultValue: ''`
  /// 라는 **no-op 표기**이지 default 개념 자체가 아니다.
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

  // Naver SDK(1-tap) 설정은 여전히 빌드 타임 native 로만 주입된다 (Phase 16.2
  // D-04 — see ROADMAP.md). Android: config/{flavor}.json → gradle resValue →
  // manifest @string meta-data / iOS: ios/Flutter/{flavor}.xcconfig → Info.plist
  // 의 Nid* 키. Phase 16.5 가 킷 웹 경로용으로 아래 3상수를 추가했다 — D-04 의
  // 본질은 **secret** 을 Dart 번들에 올리지 않는 것이다. client_id 는 RFC 6749
  // §2.2 의 공개 식별자이고 authorize URL · native meta-data 에 이미 평문으로
  // 있다. naverClientSecret 은 Dart 에 절대 두지 않는다(서버 Secret Manager 단독).

  /// Naver Client ID — public client identifier (Phase 16.5 D-04 정합).
  ///
  /// `--dart-define-from-file=config/{flavor}.json` 의 `naverClientId` 키를
  /// 컴파일 타임 상수로 읽는다(Android gradle `resValue` 와 같은 키 재사용).
  /// [kakaoNativeAppKey] · [lineChannelId] 패턴과 일관 —
  /// 미주입 시 빈 문자열, silent fallback 회피 (WR-07 hotfix). 빈 문자열이면
  /// `NaverWebAuthClient.signIn()` 이 세션을 열기 전에 [ServiceUnavailable] 로
  /// 시끄럽게 실패한다 (`Naver web 도착: outcome=error ... code=config`).
  ///
  /// iOS 는 `ios/Flutter/{flavor}.xcconfig` 의 `NAVER_CLIENT_ID` 와 **같은 값**
  /// 이어야 한다 — 갈리면 1-tap(SDK) 과 웹이 다른 앱으로 로그인하는 조용한
  /// 실패가 된다 (계약 테스트 `T-16.5-NATIVE-01` 이 dev 값을 잠근다).
  ///
  /// dev flavor 만 실 키 주입 (memory `project_firebase_dev_only`),
  /// stg/prod 는 사용자가 자체 등록 — manual.md 의 Naver 단락 참조.
  static const String naverClientId = String.fromEnvironment('naverClientId');

  /// 킷 웹 경로 콜백 scheme — 기존 iOS URL Scheme 재사용 (Phase 16.5 D-09).
  ///
  /// `--dart-define-from-file=config/{flavor}.json` 의 `naverUrlScheme` 키
  /// (이미 NAVER 콘솔 「iOS URL Scheme」 에 등록된 값) 를 읽는다. probe ② 결과가
  /// A(콘솔 작업 0 으로 authorize 통과) 라 이 식을 채택했다 — 역도메인 파생
  /// 문자열(probe B)이나 Hosting bounce(probe C) 는 쓰지 않는다.
  ///
  /// Android 는 gradle `manifestPlaceholders["naverWebCallbackScheme"]` 가 같은
  /// config 키로 `CallbackActivity` intent-filter scheme 을 채운다. 값은 RFC
  /// 3986 소문자 scheme 이어야 한다 (`flutter_web_auth_2` 가 Dart 단에서 강제).
  /// 미주입 시 빈 문자열 → [naverClientId] 와 같은 지점에서 `code=config`.
  static const String naverWebCallbackScheme = String.fromEnvironment(
    'naverUrlScheme',
  );

  /// 킷 웹 경로 authorize `redirect_uri` — `<scheme>://authorize` (D-09).
  ///
  /// iOS SDK 가 쓰는 `urlScheme + "://authorize"` 와 같은 형태다 (probe ② A 가
  /// 콘솔 Callback URL 등록 없이 통과를 실측). 서버 token 교환에는 싣지 않는다.
  static const String naverWebRedirectUri =
      '$naverWebCallbackScheme://authorize';

  /// LINE Channel ID — public client identifier (Phase 14 D-LINE-16).
  ///
  /// `--dart-define-from-file=config/{flavor}.json` 의 `lineChannelId` 키를
  /// 컴파일 타임 상수로 읽는다. Phase 12 의 [kakaoNativeAppKey] 패턴과 일관 —
  /// 미주입 시 빈 문자열, silent fallback 회피 (WR-07 hotfix).
  /// [LineSDK.instance.setup] 호출 시점에 빈 문자열이면 SDK assertion /
  /// 첫 API 호출에서 즉시 실패하므로 silent failure 아님.
  ///
  /// dev flavor 만 실 키 주입 (memory `project_firebase_dev_only`),
  /// stg/prod 는 사용자가 자체 등록 — manual.md 의 LINE 단락 참조.
  ///
  /// LINE Channel Secret 은 client 측에 미저장 (D-LINE-18 — Cloud Function
  /// 의 Secret Manager 단독 보관). client 는 Channel ID 만 보유하면 OIDC
  /// 흐름 수행 가능.
  static const String lineChannelId = String.fromEnvironment('lineChannelId');

  /// Cloud Functions region — `--dart-define-from-file` 의 `functionsRegion` 키.
  ///
  /// **IN-03/IN-06 리뷰:** 과거 이 값은 `firebase_providers.dart` 의
  /// `FirebaseFunctions.instanceFor(region: 'asia-northeast3')` 에 코드
  /// 리터럴로 박혀 있었다. 서울 외 region 을 쓰는 fork 사용자는 dart 소스를
  /// 직접 고쳐야 했고, 이는 "config 로 환경을 바꾼다" 는 이 프로젝트의 다른
  /// 모든 설정 패턴과 어긋났다.
  ///
  /// **TS 와 1:1 일치 의무.** 서버 측 진실원은
  /// `functions/src/shared/region.ts` 의 `REGION` 상수다. 두 값이 어긋나면
  /// 런타임에 callable `not-found` 로만 드러난다 — 배포 전에 반드시 함께
  /// 바꿀 것. `app_config_test.dart` 가 두 파일의 값 일치를 테스트로 잠근다.
  ///
  /// 다른 키들과 달리 `defaultValue` 를 명시한다 — region 은 시크릿이 아니고
  /// 빈 문자열이 유효한 값이 아니며, 기본값이 곧 프로젝트 표준이기 때문이다
  /// (IN-02 표기 규칙의 명시된 예외).
  static const String functionsRegion = String.fromEnvironment(
    'functionsRegion',
    defaultValue: defaultFunctionsRegion,
  );

  /// [functionsRegion] 의 기본값 — `functions/src/shared/region.ts` 의
  /// `REGION` 과 동일해야 한다 (Phase 11 D-04).
  static const String defaultFunctionsRegion = 'asia-northeast3';

  /// 브랜드 색 — `--dart-define-from-file` 의 `brandColor` 키 (Phase 17.5 D-06).
  ///
  /// 형식은 `#RRGGBB`(대소문자 무관 16진수 6자리). 앱 테마 seed · 인증 결과
  /// 페이지 · 킷 발송 메일이 같은 값을 쓴다 — 세 소비처의 판정은
  /// `hosting/test/shared_rules.json` 표가 함께 고정한다.
  ///
  /// 표기 규칙(IN-02)에 따라 `defaultValue` 를 생략한다. 빈 문자열 =
  /// 미주입 sentinel 이고, 비었거나 형식이 틀린 값을 무엇으로 대체할지는
  /// 소비처가 정한다 (앱은 [parseBrandColor] 가 null 이면 기존 테마 seed).
  static const String brandColor = String.fromEnvironment('brandColor');

  /// `#RRGGBB` 형식만 허용하는 [brandColor] 판정 정규식.
  ///
  /// 앞뒤 공백을 trim 하지 않는다 — 메일 · 페이지 구현과 같은 정확 일치다.
  static final RegExp _brandColorPattern = RegExp(r'^#([0-9A-Fa-f]{6})$');

  /// [raw] 를 불투명 [Color] 로 파싱한다. 형식이 틀리면 null 을 반환한다.
  ///
  /// [brandColor] 가 컴파일 타임 상수라 테스트가 다른 값을 주입할 수 없으므로
  /// 순수 함수로 분리했다. 앱(`App`)이 `?? AppTheme.seedColor` 로 대체 색을
  /// 직접 고르는 소비처라 [parseEnabledProviders] 와 달리 `@visibleForTesting`
  /// 을 붙이지 않는다 (붙이면 lib 호출이 analyze 경고가 된다).
  ///
  /// 형식 오류 값은 앱 시작을 막지 않는다 — null 을 받은 소비처가 기본 색을
  /// 쓴다 (`#673AB7` · `Colors.deepPurple` 과 같은 ARGB). `int.parse` 는
  /// 정규식을 통과한 16진수 6자리에만 적용되므로 throw 하지 않는다.
  static Color? parseBrandColor(String raw) {
    final match = _brandColorPattern.firstMatch(raw);
    if (match == null) {
      return null;
    }
    return Color(0xFF000000 | int.parse(match.group(1)!, radix: 16));
  }

  /// 인증 메일 발송 모드 원문 — `--dart-define-from-file` 의 `emailDelivery`
  /// 키 (Phase 17.5 D-09).
  ///
  /// 값은 `firebase` · `kit` · 빈 문자열. 표기 규칙(IN-02)에 따라
  /// `defaultValue` 를 생략한다 — 빈 문자열 = 미주입 sentinel 이며 키가 없는
  /// 기존 config 도 [EmailDeliveryMode.firebase] 로 동작한다. 판정은
  /// [emailDeliveryMode] 로 읽는다.
  static const String emailDelivery = String.fromEnvironment('emailDelivery');

  /// [raw] 를 [EmailDeliveryMode] 로 파싱한다.
  ///
  /// `''` · `'firebase'` → [EmailDeliveryMode.firebase], `'kit'` →
  /// [EmailDeliveryMode.kit]. trim · 대소문자 변환 없이 정확 일치로만 읽는다 —
  /// 배포 스크립트와 같은 규칙이라 두 쪽 판정이 갈리지 않는다.
  ///
  /// **그 밖의 값은 debug 에서 즉시 실패시킨다** ([parseEnabledProviders] 와
  /// 같은 구조). `"Kit"` · `"smtp"` 같은 설정 오타가 조용히 firebase 로
  /// 동작하면 「kit 메일이 안 온다」 로만 드러난다. 배포 스크립트는 같은 값을
  /// 거부(FAIL)하므로, release 빌드(`assert` 미평가)의 firebase 대체는 배포
  /// 단계를 거치지 않은 빌드에서만 생긴다.
  ///
  /// [emailDelivery] 가 컴파일 타임 상수라 테스트가 다른 값을 주입할 수
  /// 없으므로 순수 함수로 분리해 [visibleForTesting] 으로 노출한다.
  @visibleForTesting
  static EmailDeliveryMode parseEmailDeliveryMode(String raw) {
    switch (raw) {
      case '':
      case 'firebase':
        return EmailDeliveryMode.firebase;
      case 'kit':
        return EmailDeliveryMode.kit;
    }
    assert(() {
      throw StateError(
        'emailDelivery 값이 잘못됐다: "$raw" — config/{flavor}.json 에서 '
        'firebase · kit · 빈 값 중 하나로 고친다',
      );
    }());
    return EmailDeliveryMode.firebase;
  }

  /// 현재 빌드의 인증 메일 발송 모드 — [emailDelivery] 의 파싱 결과.
  static EmailDeliveryMode get emailDeliveryMode =>
      parseEmailDeliveryMode(emailDelivery);

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
  /// provider 추가/폐기마다 바뀌므로 doc 에서
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
      isProviderStaticallyEnabled(authProviders, providerId);
}

/// 정적 활성화 맵 [staticEnabled] 에서 [providerId] 가 켜져 있는지 판정한다.
///
/// 맵에 없는 id 는 false 다 (D-21 안전 default). Remote Config 는 보지 않는다.
/// 이 판정을 provider SDK 를 부르는 두 곳이 공유한다 (Phase 17.3 — see
/// ROADMAP.md) — bootstrap 의 SDK 초기화 선택(`selectEnabledSdkInits`)과
/// 로그아웃의 SDK 로그아웃 fan-out(`AuthRepository.signOut`). 초기화하지 않은
/// SDK 를 부르면 LINE 은 네이티브가 프로세스를 끝내므로(Dart `try/catch` 로
/// 막을 수 없다) 두 곳의 판정이 어긋나면 안 된다.
bool isProviderStaticallyEnabled(
  Map<String, bool> staticEnabled,
  String providerId,
) => staticEnabled[providerId] ?? false;

/// 정적 활성화 맵 Provider — Registry ([activeStrategies]) 가 watch.
///
/// keepAlive: 빌드 타임 상수 — 앱 생명주기 동안 불변.
@Riverpod(keepAlive: true)
Map<String, bool> staticAuthProviders(Ref ref) => AppConfig.authProviders;
