import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_starter_kit/core/config/app_config.dart';
import 'package:flutter_starter_kit/core/firebase/firebase_options_dev.dart'
    as dev;
import 'package:flutter_starter_kit/core/firebase/firebase_options_stg.dart'
    as stg;
import 'package:flutter_starter_kit/core/firebase/firebase_options_prod.dart'
    as prod;

/// 현재 flavor에 맞는 Firebase 프로젝트를 초기화한다.
///
/// [AppConfig.flavor] 값에 따라 dev/stg/prod Firebase 옵션을 선택하고,
/// [Firebase.initializeApp]을 호출한다.
/// Firebase 프로젝트가 아직 연결되지 않은 경우(placeholder 상태)
/// `false`를 반환한다.
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
    // 설정 오류는 placeholder 미연결과 구분해 전파한다 (아래 catch 로 흡수 금지).
    rethrow;
  } catch (e) {
    // Firebase 프로젝트 미연결 시(placeholder) 앱은 정상 실행
    debugPrint('Firebase 초기화 실패 (placeholder 상태일 수 있음): $e');
    return false;
  }
}
