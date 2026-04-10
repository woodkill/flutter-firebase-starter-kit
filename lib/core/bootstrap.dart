import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/app.dart';
import 'package:flutter_starter_kit/core/firebase/firebase_initializer.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/date_symbol_data_local.dart';

/// 앱 초기화 시퀀스를 실행한다.
///
/// 실행 순서:
/// 1. [WidgetsFlutterBinding.ensureInitialized] -- Flutter 엔진 바인딩
/// 2. [initializeDateFormatting] -- intl 날짜 포맷 데이터 초기화
/// 3. [initializeFirebase] -- Firebase 초기화 (실패 허용)
/// 4. [GoogleSignIn.instance.initialize] -- Google Sign-In 초기화
/// 5. [runApp] -- [ProviderScope]로 감싼 [App] 위젯 실행
///
/// [isFirebaseInitializedProvider]에 Firebase 초기화 결과를 override로 주입하여
/// Router와 화면 모두에서 Provider를 통해 접근할 수 있도록 한다.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();

  final isFirebaseInitialized = await initializeFirebase();

  // Firebase 초기화 성공 시 GoogleSignIn 초기화.
  // Dart-only Firebase 방식이므로 google-services.json Gradle 플러그인을
  // 사용하지 않아 serverClientId를 --dart-define-from-file에서 명시적으로 전달.
  if (isFirebaseInitialized) {
    const serverClientId =
        String.fromEnvironment('googleServerClientId');
    try {
      await GoogleSignIn.instance.initialize(
        serverClientId: serverClientId.isEmpty ? null : serverClientId,
      );
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('GoogleSignIn.initialize() 실패 (무시): $e\n$st');
      }
    }
  }

  runApp(
    ProviderScope(
      overrides: [
        isFirebaseInitializedProvider
            .overrideWithValue(isFirebaseInitialized),
      ],
      child: const App(),
    ),
  );
}
