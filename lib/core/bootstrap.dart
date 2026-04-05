import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_starter_kit/app.dart';
import 'package:flutter_starter_kit/core/firebase/firebase_initializer.dart';

/// 앱 초기화 시퀀스를 실행한다.
///
/// 실행 순서:
/// 1. [WidgetsFlutterBinding.ensureInitialized] -- Flutter 엔진 바인딩
/// 2. [initializeFirebase] -- Firebase 초기화 (실패 허용)
/// 3. [runApp] -- [ProviderScope]로 감싼 [App] 위젯 실행
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  final isFirebaseInitialized = await initializeFirebase();

  runApp(
    ProviderScope(
      child: App(isFirebaseInitialized: isFirebaseInitialized),
    ),
  );
}
