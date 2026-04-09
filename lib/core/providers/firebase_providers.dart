import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'firebase_providers.g.dart';

/// FirebaseAuth 인스턴스를 제공한다.
///
/// 앱 생명주기 동안 유지되는 keepAlive Provider.
/// [FirebaseAuth.instance] 직접 접근 대신 이 Provider를 통해서만 접근한다.
///
/// ## Provider 생명주기 분류 기준 (D-06)
///
/// **keepAlive (`@Riverpod(keepAlive: true)`):**
/// - Firebase 인스턴스 (FirebaseAuth, FirebaseFirestore, FirebaseStorage 등)
/// - 인증 상태 스트림 (authStateChanges)
/// - 앱 설정 (locale, themeMode)
/// - Remote Config
/// - 앱 전역 상태 -- 앱 종료 전까지 유지되어야 하는 것
///
/// **autoDispose (`@riverpod` 소문자, 기본값):**
/// - 화면별 데이터 페치 (사용자 목록, 게시글 등)
/// - 폼 입력 상태
/// - 검색 결과
/// - UI 종속 상태 -- 화면 이탈 시 해제해도 되는 것
@Riverpod(keepAlive: true)
FirebaseAuth firebaseAuth(Ref ref) {
  return FirebaseAuth.instance;
}

/// Firebase 초기화 성공 여부를 제공한다.
///
/// [bootstrap]에서 [ProviderScope.overrides]로 초기값을 주입한다.
/// 기본값 `false`는 Firebase 미초기화 상태를 의미한다.
@Riverpod(keepAlive: true)
bool isFirebaseInitialized(Ref ref) {
  return false; // ProviderScope overrides로 실제 값 주입
}

/// Firebase Auth의 인증 상태 변경 스트림을 제공한다.
///
/// Firebase 미초기화 시 빈 스트림을 반환하여 에러를 방지한다.
/// 인증 가드([authRedirect])와 UI 모두에서 사용한다.
@Riverpod(keepAlive: true)
Stream<User?> authState(Ref ref) {
  final isInitialized = ref.watch(isFirebaseInitializedProvider);
  if (!isInitialized) return const Stream<User?>.empty();
  return ref.watch(firebaseAuthProvider).authStateChanges();
}

/// [GoogleSignIn] 인스턴스를 제공한다.
///
/// 싱글톤이지만 Provider로 감싸서 테스트 시 mock override를 가능하게 한다.
/// [initialize]는 [bootstrap]에서 1회 호출되어야 한다.
@Riverpod(keepAlive: true)
GoogleSignIn googleSignIn(Ref ref) {
  return GoogleSignIn.instance;
}
