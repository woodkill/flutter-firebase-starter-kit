import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_starter_kit/core/firebase/firebase_options_dev.dart'
    as dev;
import 'package:flutter_starter_kit/core/firebase/firebase_options_stg.dart'
    as stg;
import 'package:flutter_starter_kit/core/firebase/firebase_options_prod.dart'
    as prod;

/// 현재 flavor에 맞는 Firebase 프로젝트를 초기화한다.
///
/// [flavor] 값에 따라 dev/stg/prod Firebase 옵션을 선택하고,
/// [Firebase.initializeApp]을 호출한다.
/// Firebase 프로젝트가 아직 연결되지 않은 경우(placeholder 상태)
/// `false`를 반환한다.
Future<bool> initializeFirebase() async {
  const flavor = String.fromEnvironment('flavor', defaultValue: 'dev');

  try {
    final options = switch (flavor) {
      'prod' => prod.DefaultFirebaseOptions.currentPlatform,
      'stg' => stg.DefaultFirebaseOptions.currentPlatform,
      _ => dev.DefaultFirebaseOptions.currentPlatform,
    };

    await Firebase.initializeApp(options: options);
    return true;
  } on Exception catch (e) {
    // Firebase 프로젝트 미연결 시(placeholder) 앱은 정상 실행
    debugPrint('Firebase 초기화 실패 (placeholder 상태일 수 있음): $e');
    return false;
  }
}
