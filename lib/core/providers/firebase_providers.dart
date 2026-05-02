import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
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

/// Firebase Auth의 사용자 변경 스트림을 제공한다.
///
/// [FirebaseAuth.userChanges]를 사용한다. `authStateChanges()`의 상위
/// 집합으로, credential linking/unlinking(익명→정식 승격 포함)에도
/// emit하여 `linkWithCredential` 후 UI가 즉시 갱신된다.
/// Firebase 미초기화 시 빈 스트림을 반환하여 에러를 방지한다.
/// 인증 가드([authRedirect])와 UI 모두에서 사용한다.
@Riverpod(keepAlive: true)
Stream<User?> authState(Ref ref) {
  final isInitialized = ref.watch(isFirebaseInitializedProvider);
  if (!isInitialized) return const Stream<User?>.empty();
  return ref.watch(firebaseAuthProvider).userChanges();
}

/// [GoogleSignIn] 인스턴스를 제공한다.
///
/// 싱글톤이지만 Provider로 감싸서 테스트 시 mock override를 가능하게 한다.
/// [initialize]는 [bootstrap]에서 1회 호출되어야 한다.
@Riverpod(keepAlive: true)
GoogleSignIn googleSignIn(Ref ref) {
  return GoogleSignIn.instance;
}

/// [FacebookAuth] 인스턴스를 제공한다.
///
/// 싱글톤이지만 Provider로 감싸서 테스트 시 mock override를 가능하게 한다.
/// 네이티브 SDK가 앱 시작 시 자동 초기화하므로 별도 초기화 불필요.
@Riverpod(keepAlive: true)
FacebookAuth facebookAuth(Ref ref) {
  return FacebookAuth.instance;
}

/// [FirebaseCrashlytics] 인스턴스를 제공한다 (Phase 10 D-28).
///
/// 앱 생명주기 동안 유지되는 keepAlive Provider.
/// [FirebaseCrashlytics.instance] 직접 접근 대신 이 Provider를 통해서만 접근한다.
///
/// **주의:** Firebase 미초기화 시 [FirebaseCrashlytics.instance] 접근은
/// throw 할 수 있다 (Phase 1 D-13). 소비자는 반드시
/// [isFirebaseInitializedProvider] 가드 후 접근하거나,
/// `CrashlyticsService` 래퍼를 사용하여 미초기화 시 no-op 으로 처리한다.
@Riverpod(keepAlive: true)
FirebaseCrashlytics firebaseCrashlytics(Ref ref) {
  return FirebaseCrashlytics.instance;
}

/// [FirebaseAnalytics] 인스턴스를 제공한다 (Phase 10 D-29).
///
/// 앱 생명주기 동안 유지되는 keepAlive Provider.
/// [FirebaseAnalytics.instance] 직접 접근 대신 이 Provider를 통해서만 접근한다.
///
/// **주의:** Firebase 미초기화 시 접근은 throw 할 수 있다.
/// 소비자는 `AnalyticsService` 래퍼로 가드된 접근을 해야 한다.
@Riverpod(keepAlive: true)
FirebaseAnalytics firebaseAnalytics(Ref ref) {
  return FirebaseAnalytics.instance;
}

/// [FirebaseFirestore] 인스턴스를 제공한다 (Phase 10 D-16 약관 미러 대비).
///
/// 앱 생명주기 동안 유지되는 keepAlive Provider.
/// 약관 동의 상태 미러링, 사용자 프로필 Firestore 저장 등에 사용한다.
@Riverpod(keepAlive: true)
FirebaseFirestore firebaseFirestore(Ref ref) {
  return FirebaseFirestore.instance;
}

/// [FirebaseRemoteConfig] 인스턴스를 제공한다 (Phase 11 D-22~D-27).
///
/// 앱 생명주기 동안 유지되는 keepAlive Provider.
/// `auth_provider_{id}_enabled` kill switch 키를 [activeStrategies] 가 read.
///
/// **주의:** Firebase 미초기화 시 [FirebaseRemoteConfig.instance] 접근은
/// throw 할 수 있다 (Phase 1 D-13). [bootstrap] 의
/// `if (isFirebaseInitialized)` 블록 안에서만 초기화/접근하도록 한다.
@Riverpod(keepAlive: true)
FirebaseRemoteConfig firebaseRemoteConfig(Ref ref) {
  return FirebaseRemoteConfig.instance;
}

/// [FirebaseFunctions] 인스턴스를 제공한다 (Phase 11 D-04 region scoped).
///
/// `asia-northeast3` (서울) region 으로 고정 — `functions/src/shared/region.ts`
/// 와 정합. Phase 12+ Custom Token 함수 호출 시 사용한다.
@Riverpod(keepAlive: true)
FirebaseFunctions firebaseFunctions(Ref ref) {
  return FirebaseFunctions.instanceFor(region: 'asia-northeast3');
}
