import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/app.dart';
import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/config/app_config.dart';
import 'package:flutter_starter_kit/core/error/error_widget_builder.dart';
import 'package:flutter_starter_kit/core/firebase/firebase_initializer.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:flutter_starter_kit/core/remote_config/feature_flag.dart';
import 'package:flutter_starter_kit/features/notifications/data/firebase_messaging_background_handler.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/date_symbol_data_local.dart';
// Phase 14 — see ROADMAP.md (LINE Login SDK init).
import 'package:flutter_line_sdk/flutter_line_sdk.dart';
// kakao_flutter_sdk_user 가 kakao_flutter_sdk_auth 를 통해 transitive 로
// kakao_flutter_sdk_common 을 re-export 하므로 직접 의존성 import 1개로 충분.
// pubspec.yaml 의 직접 의존성 (`kakao_flutter_sdk_user`)과 일관 — depend_on_referenced_packages 통과.
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

/// FCM 백그라운드 · 종료 상태 메시지 핸들러를 등록한다 (Phase 17 D-01).
///
/// [bootstrap] 이 Firebase 초기화 분기 안 · `runApp` 앞에서 1회 부른다.
/// 알림 권한을 요청하지 않는다 — 권한은 설정 「알림 받기」 스위치를 켤 때만
/// 요청한다(D-03). 등록 실패는 앱 실행을 막지 않는다(Phase 1 D-13 철학).
void _registerBackgroundMessageHandler() {
  try {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } on Object catch (e, st) {
    if (kDebugMode) {
      debugPrint('FCM 백그라운드 핸들러 등록 실패 (무시): $e\n$st');
    }
  }
}

/// 앱 초기화 시퀀스를 실행한다 (Phase 10 D-28).
///
/// 실행 순서:
/// 1. [runZonedGuarded] 로 전체 시퀀스를 감싸 Zone 미처리 에러 수집 (경로 1)
/// 2. [WidgetsFlutterBinding.ensureInitialized] -- Flutter 엔진 바인딩
/// 3. [initializeDateFormatting] -- intl 날짜 포맷 데이터 초기화
/// 4. [initializeFirebase] -- Firebase 초기화 (실패 허용)
/// 5. Firebase 초기화 성공 시 Crashlytics 3경로 등록 + flavor custom key
///    - 경로 1: [runZonedGuarded] 의 onError -> recordError(fatal: true)
///    - 경로 2: [FlutterError.onError] -> recordFlutterFatalError
///    - 경로 3: [PlatformDispatcher.onError] -> recordError(fatal: true)
/// 6. [GoogleSignIn.instance.initialize] -- Google Sign-In 초기화
///    (이후 Kakao · LINE · Remote Config 초기화, 그리고 FCM 백그라운드
///    핸들러 등록 -- Phase 17 D-01, [_registerBackgroundMessageHandler])
/// 7. release 빌드만 [ErrorWidget.builder] 를 [buildReleaseErrorWidget] 으로
///    교체 (Phase 17 D-22 -- 깨진 화면 대체 + non-fatal 기록, Firebase 초기화
///    결과와 무관하게 설치)
/// 8. [runApp] -- [ProviderScope] 로 감싼 [App] 위젯 실행
///
/// [isFirebaseInitializedProvider] 에 Firebase 초기화 결과를 override 로
/// 주입하여 Router 와 화면 모두에서 Provider 를 통해 접근할 수 있도록 한다.
///
/// **Phase 1 D-13 철학:** Firebase 초기화 실패 시에도 앱은 정상 실행되어야
/// 한다. Crashlytics 등록은 `isFirebaseInitialized=true` 분기 안에서만
/// 수행하여 미초기화 상태에서 [FirebaseCrashlytics.instance] 접근으로 throw
/// 하지 않도록 한다. 또한 Zone onError 콜백 자체가 try/catch 로 감싸져
/// recordError 실패 시 debugPrint 로 fallback 한다 (Pitfall 4).
Future<void> bootstrap() async {
  // runZonedGuarded 는 fire-and-forget 형태로 내부 Future 를 Zone 가드 안에서
  // 처리하므로 외부에서 별도 await 가 불필요 (의도적 fire-and-forget).
  unawaited(
    runZonedGuarded<Future<void>>(
      () async {
        WidgetsFlutterBinding.ensureInitialized();

        // 초기화 전 구간을 try 로 감싸 어떤 실패에도 [runApp] 이 반드시
        // 호출되도록 보장한다. 이전에는 [initializeDateFormatting] 이나
        // [initializeFirebase] 가 throw 하면 zone onError 로 빠져 runApp 이
        // 끝내 호출되지 않았고, flutter_native_splash 의 네이티브 스플래시가
        // 영구히 남아 사용자에게는 "앱이 멈춤" 으로 보였다 (release 빌드에서는
        // 로그조차 남지 않는다).
        //
        // Firebase 초기화 실패 시에도 앱은 정상 실행되어야 한다는 D-13 철학의
        // 연장선이다. flavor 미주입으로 [initializeFirebase] 가 StateError 를
        // 던지는 경우에도 (잘못된 프로젝트에 연결하는 대신) Firebase 의존
        // 기능 전체가 비활성화된 채로 화면은 뜬다.
        var isFirebaseInitialized = false;
        try {
          await initializeDateFormatting();

          isFirebaseInitialized = await initializeFirebase();

          if (isFirebaseInitialized) {
            // App Check 활성화 (Phase 12 D-11, Pitfall 6 — Cloud Function abuse
            // 방어). dev/debug 빌드는 debug provider, release 빌드는 Play
            // Integrity (Android) / DeviceCheck (iOS). 활성화 실패는 무시 +
            // debugPrint fallback (GoogleSignIn / KakaoSdk 패턴 일관).
            //
            // dev flavor 의 debug provider 첫 실행 시 logcat / Xcode console 에
            // debug 토큰 출력 -- Firebase Console > App Check > 디버그 토큰 관리
            // 에 등록 의무 (manual.md 5단계).
            try {
              await FirebaseAppCheck.instance.activate(
                providerAndroid: kDebugMode
                    ? const AndroidDebugProvider()
                    : const AndroidPlayIntegrityProvider(),
                providerApple: kDebugMode
                    ? const AppleDebugProvider()
                    : const AppleDeviceCheckProvider(),
              );
            } on Object catch (e, st) {
              if (kDebugMode) {
                debugPrint('FirebaseAppCheck.activate() 실패 (무시): $e\n$st');
              }
            }

            // 경로 2: Flutter framework 에러 -> Crashlytics
            FlutterError.onError =
                FirebaseCrashlytics.instance.recordFlutterFatalError;

            // 경로 3: Platform/async 에러 -> Crashlytics. fire-and-forget.
            PlatformDispatcher.instance.onError = (error, stack) {
              unawaited(
                FirebaseCrashlytics.instance.recordError(
                  error,
                  stack,
                  fatal: true,
                ),
              );
              return true;
            };

            // Flavor custom key 태깅 (AUTH-11). [AppConfig.flavor] 가 단일
            // 진실원 — silent fallback 회피 (WR-07 hotfix). 미주입 시 빈 문자열.
            await FirebaseCrashlytics.instance.setCustomKey(
              'flavor',
              AppConfig.flavor,
            );

            // GoogleSignIn 초기화 (기존 로직 유지).
            //
            // serverClientId 는 `--dart-define-from-file` 에서 명시적으로
            // 전달한다. Android 는 `android/app/build.gradle.kts` 가
            // `com.google.gms.google-services` 플러그인을 적용하지만, 그
            // 플러그인이 노출하는 값에 의존하지 않고 flavor config 를 단일
            // 진실원으로 쓰기 위함이다 (iOS 와 동일 경로 유지).
            const serverClientId = String.fromEnvironment(
              'googleServerClientId',
            );
            try {
              await GoogleSignIn.instance.initialize(
                serverClientId: serverClientId.isEmpty ? null : serverClientId,
              );
            } on Object catch (e, st) {
              if (kDebugMode) {
                debugPrint('GoogleSignIn.initialize() 실패 (무시): $e\n$st');
              }
            }

            // Kakao SDK 초기화 (Phase 12 D-04 / Pattern A).
            //
            // Firebase 초기화 직후 + RC fetch 전 위치 — 첫 SDK API 호출
            // (loginWithKakaoTalk 등) 시점에 실제 PlatformChannel가 초기화된다.
            // [KakaoSdk.init]은 [Future<void>] 반환 (kakao_flutter_sdk_common
            // 2.0.0+1) — `await` 필수.
            //
            // dev flavor만 실 키 주입 (D-22), stg/prod는 placeholder —
            // manual.md 안내. 빈 문자열 시 throw하지 않으나 (`_nativeKey = '' OK`),
            // 첫 SDK API 호출에서 실패하므로 silent failure 회피 (D-20 의도).
            //
            // KakaoSdk.init이 throw할 가능성(`null` 인자 시 KakaoClientException)에
            // 대비해 try/catch + debugPrint fallback (GoogleSignIn 패턴 일관).
            try {
              await KakaoSdk.init(nativeAppKey: AppConfig.kakaoNativeAppKey);
            } on Object catch (e, st) {
              if (kDebugMode) {
                debugPrint('KakaoSdk.init() 실패 (무시): $e\n$st');
              }
            }

            // Naver 는 runtime 초기화 블록이 없다 (Phase 16.2 D-04).
            //
            // 교체된 플러그인은 client ID · secret · 앱 이름을 plugin
            // registration 시점에 네이티브 설정에서 읽는다 — Android 는
            // AndroidManifest meta-data, iOS 는 Info.plist 키다. 따라서
            // bootstrap 이 호출할 초기화 API 자체가 존재하지 않는다.

            // LINE SDK 초기화 (Phase 14 D-LINE-17).
            //
            // flutter_line_sdk 의 [LineSDK.instance.setup] 호출 의무. KakaoSdk
            // init 직후 + RC fetch 전 위치 — LoginScreen 진입 직전 사용 가능 +
            // cold start 의 첫 클릭 지연 회피. SDK 자체 멱등성 보장 (LineSDK
            // _channel 의 'setup' invokeMethod 가 native side 에서 idempotent
            // 처리).
            //
            // [LineSDK.instance.setup] 는 [Future<void>] 반환 — `await` 의무.
            // dev flavor 만 실 키 주입 (D-LINE-19 / memory `project_firebase_dev_only`),
            // stg/prod 는 placeholder — manual.md D-LINE-22a (1) 절차 따름.
            // 빈 문자열 시 SDK 첫 login() 호출에서 실패하므로 silent failure 회피
            // (KakaoSdk 패턴 일관).
            //
            // 호출 자체가 throw 할 가능성 (assertion 등) 에 대비해 try/catch +
            // debugPrint fallback (GoogleSignIn / KakaoSdk 패턴 일관).
            try {
              await LineSDK.instance.setup(AppConfig.lineChannelId);
            } on Object catch (e, st) {
              if (kDebugMode) {
                debugPrint('LineSDK.setup() 실패 (무시): $e\n$st');
              }
            }

            // Remote Config 초기화 (Phase 11 D-24, D-25 폴백, Pitfall 4 silent
            // stale 가드). fetch 실패는 무시 + 정적 config 로 진행.
            try {
              final rc = FirebaseRemoteConfig.instance;
              await rc.setConfigSettings(
                RemoteConfigSettings(
                  fetchTimeout: const Duration(minutes: 1),
                  // D-23: dev=0, 그 외=12h. [AppConfig.isDev] 단일 진실원으로
                  // prod 빌드의 flavor dart-define 누락 silent fallback 차단
                  // (WR-07 hotfix).
                  minimumFetchInterval: AppConfig.isDev
                      ? Duration.zero
                      : const Duration(hours: 12),
                ),
              );
              // 정적 config 의 enabled 값을 RC default 로 동시 로드 — RC
              // 미초기화/오프라인 상태에서도 정적 enabled provider 가 그대로
              // 보이도록 보장 (D-25, T-11-RC-03).
              //
              // setDefaults 는 [AppConfig.authProviders] 의 모든 슬러그
              // ([kAllProviderIds]) 에 대해
              // `auth_provider_{providerId}_enabled: <CSV 포함 여부>` 를 자동
              // 생성한다. enabledAuthProviders CSV 토큰 기준:
              // - 'auth_provider_google_enabled': true (Phase 6+)
              // - 'auth_provider_apple_enabled': true (Phase 7+)
              // - 'auth_provider_facebook_enabled': true (Phase 9+)
              // - 'auth_provider_kakao_enabled': true (Phase 12+)
              // - 'auth_provider_naver_enabled': true (Phase 13 — see ROADMAP.md)
              // - 'auth_provider_line_enabled': true (Phase 14 — see ROADMAP.md)
              //
              // Phase 17 — see ROADMAP.md (D-11): FeatureFlag 기본값(공지 배너
              // 스위치 · 언어별 문구)을 같은 맵에 합산한다
              // ([buildRemoteConfigDefaults]).
              await rc.setDefaults(buildRemoteConfigDefaults());
              await rc.fetchAndActivate();
            } on Object catch (e, st) {
              // D-25: fetch 실패는 무시. Crashlytics 로그만 + 정적 config 로 진행.
              if (kDebugMode) {
                debugPrint('RemoteConfig 초기화 실패 (무시): $e\n$st');
              }
              unawaited(
                FirebaseCrashlytics.instance.recordError(e, st, fatal: false),
              );
            }

            // Phase 17 — see ROADMAP.md (D-01) — 권한 요청 없이 핸들러 등록만.
            // 백그라운드 · 종료 상태 메시지 핸들러는 runApp 앞에서 등록한다.
            _registerBackgroundMessageHandler();
          }
        } on Object catch (e, st) {
          if (kDebugMode) {
            debugPrint('bootstrap 초기화 실패 (Firebase 비활성): $e\n$st');
          }
        }

        // release 깨진 화면 대체 (Phase 17 — see ROADMAP.md (D-22)) — debug 는
        // SDK 기본 빨간 화면 유지. Firebase 초기화 결과와 무관하게 설치하고,
        // Crashlytics 미초기화면 기록만 생략한다. 위 3경로 fatal 은 그대로다 —
        // 이 기록은 「대체 화면이 사용자에게 보였다」 는 별도 non-fatal 신호다.
        if (!kDebugMode) {
          ErrorWidget.builder = (details) => buildReleaseErrorWidget(
            details,
            onBuildError: (d) {
              if (isFirebaseInitialized) {
                unawaited(
                  FirebaseCrashlytics.instance.recordError(
                    d.exception,
                    d.stack,
                    reason: kErrorWidgetBuildReason,
                    fatal: false,
                  ),
                );
              }
            },
          );
        }

        runApp(
          ProviderScope(
            overrides: [
              isFirebaseInitializedProvider.overrideWithValue(
                isFirebaseInitialized,
              ),
            ],
            child: const App(),
          ),
        );
      },
      (error, stack) {
        // 경로 1: Zone 미처리 에러 -> Crashlytics
        //
        // Pitfall 4: Crashlytics 미초기화 상태에서도 onError 콜백이 호출될 수
        // 있으므로 try/catch 로 recordError 호출 자체를 방어한다.
        try {
          unawaited(
            FirebaseCrashlytics.instance.recordError(error, stack, fatal: true),
          );
        } on Object catch (e, st) {
          if (kDebugMode) {
            debugPrint(
              'Crashlytics 미초기화 상태 Zone 에러: $error\n$stack\n'
              'recordError 실패: $e\n$st',
            );
          }
        }
      },
    ),
  );
}

/// Remote Config 기본값 맵을 만든다 — `setDefaults` 입력 (Phase 11 D-25 ·
/// Phase 17 D-11).
///
/// 1. 인증 provider kill switch — [AppConfig.authProviders] 의 모든 슬러그에
///    대해 `auth_provider_{providerId}_enabled: <정적 enabled>` (D-25).
/// 2. [FeatureFlag] 기본값 — 공지 배너 스위치 · 언어별 문구 (D-11). 스위치를
///    추가하면 enum 1줄로 여기에 자동 합산된다.
///
/// `remoteconfig.template.json` 은 만들지 않는다 — 기본값의 진실원은 이 맵이다.
@visibleForTesting
Map<String, Object> buildRemoteConfigDefaults() => <String, Object>{
  for (final entry in AppConfig.authProviders.entries)
    rcKeyForProvider(entry.key): entry.value,
  // Phase 17 — see ROADMAP.md (D-11) — FeatureFlag 기본값 합산.
  for (final flag in FeatureFlag.values) flag.key: flag.defaultValue,
};
