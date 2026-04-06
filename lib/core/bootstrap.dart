import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/app.dart';
import 'package:flutter_starter_kit/core/firebase/firebase_initializer.dart';
import 'package:flutter_starter_kit/core/providers/firebase_providers.dart';
import 'package:intl/date_symbol_data_local.dart';

/// 앱 초기화 시퀀스를 실행한다.
///
/// 실행 순서:
/// 1. [WidgetsFlutterBinding.ensureInitialized] -- Flutter 엔진 바인딩
/// 2. [initializeDateFormatting] -- intl 날짜 포맷 데이터 초기화
/// 3. [initializeFirebase] -- Firebase 초기화 (실패 허용)
/// 4. [runApp] -- [ProviderScope]로 감싼 [App] 위젯 실행
///
/// [isFirebaseInitializedProvider]에 Firebase 초기화 결과를 override로 주입하여
/// Router와 화면 모두에서 Provider를 통해 접근할 수 있도록 한다.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();

  final isFirebaseInitialized = await initializeFirebase();

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
