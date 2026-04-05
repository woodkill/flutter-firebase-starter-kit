import 'package:firebase_auth/firebase_auth.dart';
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
