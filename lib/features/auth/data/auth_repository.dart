import 'package:firebase_auth/firebase_auth.dart' as fb;

import '../domain/user.dart';

// part 'auth_repository.g.dart'; // Task 2에서 build_runner 실행과 함께 활성화.

/// Firebase Auth를 감싸는 인증 Repository.
///
/// FirebaseAuth 의존성을 data 계층에 격리하고,
/// 상위 레이어(Notifier)에는 [Result] 타입으로만 노출한다.
/// FirebaseAuthException은 [AppException]으로 매핑되어 던져진다.
///
/// 본 Task 1에서는 스켈레톤만 작성되며, 메서드 본체와
/// `@Riverpod` Provider 선언은 Task 2에서 추가된다.
class AuthRepository {
  /// [AuthRepository]를 생성한다.
  const AuthRepository(this._auth);

  // ignore: unused_field, prefer_final_fields
  final fb.FirebaseAuth _auth;

  // 메서드 본체는 Task 2에서 작성된다.
}

/// firebase_auth [fb.User]를 도메인 [User]로 변환한다 (D-12).
///
/// firebase_auth import는 features/auth/data 경계 안에만 존재해야 하며,
/// 본 함수가 그 경계 변환점이다. `lib/features/auth/domain/user.dart`는
/// 본 함수에 의존하지 않으며, 순수 Freezed 모델로 유지된다.
///
/// - [fbUser.email]이 null이면 빈 문자열로 fallback.
/// - [fbUser.metadata.creationTime]이 null이면 [DateTime.now]로 fallback.
User _mapFirebaseUser(fb.User fbUser) {
  return User(
    uid: fbUser.uid,
    email: fbUser.email ?? '',
    displayName: fbUser.displayName,
    photoUrl: fbUser.photoURL,
    createdAt: fbUser.metadata.creationTime ?? DateTime.now(),
  );
}
