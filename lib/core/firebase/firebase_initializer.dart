import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import 'firebase_options_dev.dart' as dev;
import 'firebase_options_prod.dart' as prod;
import 'firebase_options_stg.dart' as stg;

/// 현재 flavor에 맞는 Firebase 프로젝트를 초기화한다.
///
/// [AppConfig.flavor] 값에 따라 dev/stg/prod Firebase 옵션을 선택하고,
/// [Firebase.initializeApp]을 호출한다.
///
/// **반환 계약:** 초기화에 성공하면 `true`. 초기화에 실패하면 **원인과
/// 무관하게** `false` 를 반환하며, 호출자는 Firebase 의존 기능을 모두
/// 비활성화해야 한다. `false` 는 두 가지를 함께 의미한다.
///
/// - 설계된 경로 — Firebase 프로젝트 미연결(placeholder 의 [UnsupportedError]).
/// - 장애 경로 — 설정 불일치([FirebaseException], 예: `duplicate-app`) 나
///   플러그인 등록 실패 등. 디버그 빌드에서는 [FirebaseException] 을 assert
///   로 즉시 터뜨려 placeholder 와 육안 구분이 가능하게 한다.
///
/// 두 경로를 호출자가 코드로 구분해야 한다면 반환 타입을 결과 객체로
/// 승격해야 한다 (현재 [bool] 소비처가 6곳 이상이라 미적용 — REVIEW 의
/// IN-03 참조).
///
/// flavor 가 미주입(빈 문자열)이거나 3 값 도메인(`dev`/`stg`/`prod`) 밖이면
/// [StateError] 를 던진다 — `false` 로 흡수하지 않는다. 잘못된 flavor 를
/// 조용히 dev 로 흡수하면 prod 사용자 데이터가 dev Firebase 프로젝트에
/// 기록되므로, 부팅 시점에 즉시 터뜨리는 편이 안전하다.
Future<bool> initializeFirebase() async {
  try {
    // 단일 진실원: [AppConfig.flavor] (미주입 시 빈 문자열 — silent fallback
    // 회피). 3 값 도메인을 모두 명시하고, 나머지는 기본 분기로 흡수하지 않는다.
    final options = switch (AppConfig.flavor) {
      'dev' => dev.DefaultFirebaseOptions.currentPlatform,
      'stg' => stg.DefaultFirebaseOptions.currentPlatform,
      'prod' => prod.DefaultFirebaseOptions.currentPlatform,
      final unknown => throw StateError(
        'flavor dart-define 누락 또는 미지원 값: "$unknown". '
        '--dart-define-from-file=config/{dev|stg|prod}.json 을 지정할 것.',
      ),
    };

    await Firebase.initializeApp(options: options);
    return true;
  } on StateError {
    // flavor 설정 오류는 placeholder 미연결과 구분해 전파한다.
    rethrow;
  } on UnsupportedError catch (e) {
    // 설계된 경로: placeholder — 앱은 Firebase 없이 정상 실행한다.
    if (kDebugMode) {
      debugPrint('Firebase 미연결 (placeholder): $e');
    }
    return false;
  } on FirebaseException catch (e, st) {
    // 설정 불일치. 대표 사례는 `duplicate-app` — Gradle 의
    // `com.google.gms.google-services` 플러그인이 만든 네이티브 default app 의
    // apiKey / databaseURL / storageBucket 이 dart `options` 와 다르면
    // firebase_core 가 던진다. placeholder 와 같은 `false` 로 뭉개면
    // "dart 는 dev, 네이티브는 prod" 같은 오연결이 조용히 넘어가므로,
    // 디버그 빌드에서는 assert 로 즉시 터뜨려 개발자에게 알린다.
    assert(() {
      throw StateError('Firebase 초기화 실패 [${e.code}]: ${e.message}\n$st');
    }());
    return false;
  } on Object catch (e, st) {
    // 그 외 장애 (플러그인 등록 실패, 손상된 options 등). stack trace 보존.
    if (kDebugMode) {
      debugPrint('Firebase 초기화 실패: $e\n$st');
    }
    return false;
  }
}
