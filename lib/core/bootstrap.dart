import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/app.dart';
import 'package:flutter_starter_kit/core/auth/provider_id.dart';
import 'package:flutter_starter_kit/core/config/app_config.dart';
import 'package:flutter_starter_kit/core/firebase/firebase_initializer.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/date_symbol_data_local.dart';
// kakao_flutter_sdk_user 가 kakao_flutter_sdk_auth 를 통해 transitive 로
// kakao_flutter_sdk_common 을 re-export 하므로 직접 의존성 import 1개로 충분.
// pubspec.yaml 의 직접 의존성 (`kakao_flutter_sdk_user`)과 일관 — depend_on_referenced_packages 통과.
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

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
/// 7. [runApp] -- [ProviderScope] 로 감싼 [App] 위젯 실행
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
        await initializeDateFormatting();

        final isFirebaseInitialized = await initializeFirebase();

        if (isFirebaseInitialized) {
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
          // Dart-only Firebase 방식이므로 google-services.json Gradle 플러그인을
          // 사용하지 않아 serverClientId 를 --dart-define-from-file 에서 명시적
          // 으로 전달.
          const serverClientId = String.fromEnvironment('googleServerClientId');
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
            await KakaoSdk.init(
              nativeAppKey: AppConfig.kakaoNativeAppKey,
            );
          } on Object catch (e, st) {
            if (kDebugMode) {
              debugPrint('KakaoSdk.init() 실패 (무시): $e\n$st');
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
            await rc.setDefaults(<String, Object>{
              for (final entry in AppConfig.authProviders.entries)
                rcKeyForProvider(entry.key): entry.value,
            });
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
