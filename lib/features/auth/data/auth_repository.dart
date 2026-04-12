import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/error/app_exception.dart';
import '../../../core/error/result.dart';
import '../../../core/providers/firebase_providers.dart';
import '../domain/user.dart';

part 'auth_repository.g.dart';

/// Firebase Auth를 감싸는 인증 Repository.
///
/// FirebaseAuth와 GoogleSignIn 의존성을 data 계층에 격리하고,
/// 상위 레이어(Notifier)에는 [Result] 타입으로만 노출한다.
/// FirebaseAuthException은 [AppException]으로 매핑되어 던져진다.
class AuthRepository {
  /// [AuthRepository]를 생성한다.
  const AuthRepository(
    this._auth,
    this._googleSignIn,
  );

  final fb.FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;

  /// 이메일/비밀번호로 로그인한다.
  ///
  /// 성공 시 [Success]에 도메인 [User]를 담아 반환한다.
  /// 실패 시 [_mapAuthException]으로 변환된 [AppException]을
  /// [Failure]에 담는다.
  Future<Result<User>> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final fbUser = credential.user;
      if (fbUser == null) {
        return const Result.failure(InvalidCredentials());
      }
      return Result.success(_mapFirebaseUser(fbUser));
    } on fb.FirebaseAuthException catch (e) {
      return Result.failure(_mapAuthException(e));
    }
  }

  /// 이메일/비밀번호로 가입한다.
  ///
  /// [displayName] 업데이트 실패 시에도 가입 자체는 성공 처리한다 (D-10).
  /// 흐름: createUserWithEmailAndPassword → updateDisplayName → reload →
  /// 도메인 User 변환.
  Future<Result<User>> signUpWithEmail({
    required String email,
    required String password,
    required String displayName,
  }) async {
    // D-10 흐름:
    // 1. createUserWithEmailAndPassword
    // 2. updateDisplayName (실패 시 graceful: 계정은 생성됨, displayName 미설정)
    // 3. reload (실패 시 _auth.currentUser 재획득으로 fallback)
    // 4. _mapFirebaseUser 로 도메인 모델 변환
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final fbUser = credential.user;
      if (fbUser == null) {
        return const Result.failure(InvalidCredentials());
      }
      // displayName 업데이트는 실패해도 가입은 성공 처리한다 (D-10).
      //
      // reload() 는 토큰 만료 / 네트워크 오류 시 FirebaseAuthException 외에도
      // 비-Auth FirebaseException 또는 PlatformException 을 던질 수 있으므로,
      // Object catch 로 우회 전파를 막아 D-10 의도(가입 성공 유지)를 보존한다.
      try {
        await fbUser.updateDisplayName(displayName);
        await fbUser.reload();
      } on fb.FirebaseAuthException catch (e) {
        if (kDebugMode) {
          debugPrint('updateDisplayName/reload 실패: ${e.code}');
        }
      } on Object catch (e, st) {
        // 비-Auth Firebase/Platform 예외도 graceful 처리 (D-10 의도 보존).
        if (kDebugMode) {
          debugPrint('updateDisplayName/reload 비-Auth 예외: $e\n$st');
        }
      }
      final refreshed = _auth.currentUser ?? fbUser;

      // 이메일 인증 메일 자동 발송 (D-01).
      // 발송 실패 시 가입은 성공 유지한다 (D-11, Phase 6 D-10 패턴).
      try {
        await refreshed.sendEmailVerification();
      } on fb.FirebaseAuthException catch (e) {
        if (kDebugMode) {
          debugPrint('sendEmailVerification 실패: ${e.code}');
        }
      } on Object catch (e, st) {
        if (kDebugMode) {
          debugPrint('sendEmailVerification 비-Auth 예외: $e\n$st');
        }
      }

      return Result.success(_mapFirebaseUser(refreshed));
    } on fb.FirebaseAuthException catch (e) {
      return Result.failure(_mapAuthException(e));
    }
  }

  /// Google 계정으로 Firebase Auth에 로그인한다.
  ///
  /// Google Sign-In v7 [GoogleSignIn.authenticate] API를 사용한다.
  /// 사용자 취소([GoogleSignInExceptionCode.canceled]) 시 null을 반환하여
  /// Notifier에서 no-op 처리한다 (D-06).
  /// 동일 이메일 충돌 시 [AccountExistsWithDifferentCredential]을 반환한다 (D-10).
  Future<Result<User>?> signInWithGoogle() async {
    try {
      final account = await _googleSignIn.authenticate();
      final authentication = account.authentication;
      final credential = fb.GoogleAuthProvider.credential(
        idToken: authentication.idToken,
      );
      final userCredential = await _auth.signInWithCredential(credential);
      final fbUser = userCredential.user;
      if (fbUser == null) {
        return const Result.failure(ServiceUnavailable());
      }
      return Result.success(_mapFirebaseUser(fbUser));
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return null;
      }
      return Result.failure(_mapGoogleException(e));
    } on fb.FirebaseAuthException catch (e) {
      return Result.failure(_mapAuthException(e));
    }
  }

  /// Apple 계정으로 Firebase Auth에 로그인한다 (D-01).
  ///
  /// [fb.FirebaseAuth.signInWithProvider]를 사용하여 양 플랫폼 모두
  /// Firebase가 OAuth 플로우를 내부 처리한다:
  /// - **iOS:** 네이티브 ASAuthorizationController 시트를 띄우고
  ///   displayName 자동 저장 (최초 로그인 시).
  /// - **Android:** Chrome Custom Tab으로 Apple 웹 OAuth를 처리하고
  ///   인증 완료 후 Custom Tab 자동 닫힘.
  ///
  /// 사용자 취소 시 null을 반환하여 Notifier에서 no-op 처리한다
  /// (D-09, Phase 7 D-06 미러링).
  /// 동일 이메일 충돌 시 [AccountExistsWithDifferentCredential]을
  /// 반환한다 (Phase 7 D-10 재사용).
  Future<Result<User>?> signInWithApple() async {
    try {
      final provider = fb.AppleAuthProvider()
        ..addScope('email')
        ..addScope('name');
      final userCredential = await _auth.signInWithProvider(provider);
      final fbUser = userCredential.user;
      if (fbUser == null) {
        return const Result.failure(ServiceUnavailable());
      }
      final refreshed = _auth.currentUser ?? fbUser;
      return Result.success(_mapFirebaseUser(refreshed));
    } on fb.FirebaseAuthException catch (e) {
      // D-09: 사용자 취소 시 null 반환.
      if (e.code == 'web-context-canceled' ||
          e.code == 'web-context-cancelled' ||
          e.code == 'popup-closed-by-user') {
        return null;
      }
      return Result.failure(_mapAuthException(e));
    }
  }

  /// 로그아웃한다.
  ///
  /// [GoogleSignIn.signOut]을 병행 호출하여 Google 세션도 해제한다 (D-07).
  /// [GoogleSignIn.signOut] 실패 시에도 [fb.FirebaseAuth.signOut]은 반드시 호출한다.
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('GoogleSignIn.signOut() 실패 (무시): $e\n$st');
      }
    }
    await _auth.signOut();
  }

  /// 비밀번호 재설정 메일을 발송한다.
  ///
  /// EEP(Email Enumeration Protection) 활성화 환경에서는 존재하지 않는
  /// 이메일에 대해서도 에러를 던지지 않으므로, 성공 응답은 "메일이
  /// 발송됐다"가 아니라 "요청이 처리됐다"를 의미한다.
  Future<Result<void>> sendPasswordReset({required String email}) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return const Result.success(null);
    } on fb.FirebaseAuthException catch (e) {
      return Result.failure(_mapAuthException(e));
    }
  }

  /// 현재 사용자에게 이메일 인증 메일을 발송한다.
  ///
  /// Firebase Auth의 [fb.User.sendEmailVerification]에 위임한다.
  /// 실패 시 [_mapAuthException]으로 변환된 [AppException]을
  /// [Failure]에 담는다.
  Future<Result<void>> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null) {
      return const Result.failure(ServiceUnavailable());
    }
    try {
      await user.sendEmailVerification();
      return const Result.success(null);
    } on fb.FirebaseAuthException catch (e) {
      return Result.failure(_mapAuthException(e));
    }
  }

  /// 현재 사용자 정보를 Firebase에서 리로드한다.
  ///
  /// [fb.User.reload]를 호출하여 서버에서 최신 사용자 정보를
  /// 가져온다. 이메일 인증 완료 여부 확인 시 사용한다.
  Future<Result<void>> reloadUser() async {
    final user = _auth.currentUser;
    if (user == null) {
      return const Result.failure(ServiceUnavailable());
    }
    try {
      await user.reload();
      return const Result.success(null);
    } on fb.FirebaseAuthException catch (e) {
      return Result.failure(_mapAuthException(e));
    } on Object catch (e, st) {
      // 비-Auth Firebase/Platform 예외도 Result로 감싸 전파를 막는다.
      // Timer.periodic 콜백(pollOnce)에서 미처리 예외는 isolate 크래시를,
      // checkManually에서는 isChecking 플래그 영구 고정을 유발할 수 있다.
      if (kDebugMode) {
        debugPrint('reloadUser 비-Auth 예외: $e\n$st');
      }
      return Result.failure(ServiceUnavailable(cause: e));
    }
  }

  /// FirebaseAuthException을 [AppException]으로 매핑한다 (D-18).
  ///
  /// EEP 활성 환경에서는 `wrong-password`/`user-not-found`가 emit되지 않고
  /// `invalid-credential`로 통합되지만, EEP 비활성 프로젝트 호환을 위해
  /// 모든 코드를 매핑한다.
  ///
  /// 매핑 규칙:
  /// - `invalid-credential` / `wrong-password` / `user-not-found`
  ///   → [InvalidCredentials] (Email Enumeration 방지를 위한 통합 매핑)
  /// - `email-already-in-use` → [EmailAlreadyInUse]
  /// - `weak-password` → [WeakPassword]
  /// - `invalid-email` → [InvalidEmail]
  /// - `user-disabled` → [UserDisabled]
  /// - `network-request-failed` → [NoInternetConnection]
  /// - `too-many-requests` → [TooManyRequests]
  /// - `operation-not-allowed` → [ServiceUnavailable]
  ///   (Firebase Console에서 해당 인증 방식이 비활성화된 설정 오류.
  ///    사용자에게는 일시적 서비스 불가로 표시하되, 디버그 모드에서는
  ///    debugPrint로 코드를 출력하여 개발자가 즉시 인지하도록 한다.)
  /// - 그 외 → [ServiceUnavailable] (debugPrint로 코드 노출)
  AppException _mapAuthException(fb.FirebaseAuthException e) {
    return switch (e.code) {
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' =>
        InvalidCredentials(cause: e),
      'account-exists-with-different-credential' =>
        AccountExistsWithDifferentCredential(email: e.email, cause: e),
      'email-already-in-use' => EmailAlreadyInUse(cause: e),
      'weak-password' => WeakPassword(cause: e),
      'invalid-email' => InvalidEmail(cause: e),
      'user-disabled' => UserDisabled(cause: e),
      'network-request-failed' => NoInternetConnection(cause: e),
      'too-many-requests' => TooManyRequests(cause: e),
      'operation-not-allowed' => _logAndFallback(e),
      _ => _logAndFallback(e),
    };
  }

  /// [GoogleSignInException]을 [AppException]으로 매핑한다.
  ///
  /// 취소([GoogleSignInExceptionCode.canceled])는 호출부에서 별도 처리하므로
  /// 여기에 도달하지 않는다. 기타 에러는 [ServiceUnavailable]로 매핑한다.
  AppException _mapGoogleException(GoogleSignInException e) {
    if (kDebugMode) {
      debugPrint(
        'AuthRepository: GoogleSignIn 에러 -- '
        'code=${e.code}, description=${e.description}',
      );
    }
    return ServiceUnavailable(cause: e);
  }

  /// 매핑되지 않았거나 설정성 오류로 분류된 FirebaseAuthException을
  /// [ServiceUnavailable]로 변환하면서, 디버그 모드에서는 원본 코드와
  /// 메시지를 출력해 개발자가 즉시 인지할 수 있도록 한다.
  ///
  /// 예: Firebase Console에서 Email/Password 인증 방식이 꺼져 있어
  /// `operation-not-allowed`가 던져지면 사용자에게는 동일한 안전 메시지
  /// (`errorServiceUnavailable`)가 노출되지만, 콘솔에는 정확한 코드가
  /// 찍혀 설정 누락임을 즉시 알 수 있다.
  ///
  /// 디버그 메시지는 명시적으로 매핑된 케이스(`operation-not-allowed`)와
  /// fallback 케이스를 구분하여 grep 추적 시 혼선을 방지한다.
  ServiceUnavailable _logAndFallback(fb.FirebaseAuthException e) {
    if (kDebugMode) {
      final reason = e.code == 'operation-not-allowed'
          ? 'Firebase Console 인증 방식 비활성 (설정 오류)'
          : '매핑되지 않은 코드 (default fallback)';
      debugPrint(
        'AuthRepository: ServiceUnavailable 폴백 — $reason: '
        'code=${e.code}, message=${e.message}',
      );
    }
    return ServiceUnavailable(cause: e);
  }
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
    emailVerified: fbUser.emailVerified,
    displayName: fbUser.displayName,
    photoUrl: fbUser.photoURL,
    createdAt: fbUser.metadata.creationTime ?? DateTime.now(),
    providerIds: fbUser.providerData
        .map((info) => info.providerId)
        .toList(),
  );
}

/// [AuthRepository] 인스턴스 Provider (D-08: keepAlive).
///
/// FirebaseAuth / GoogleSignIn Provider를 의존하여 단일 인스턴스를 제공한다.
@Riverpod(keepAlive: true)
AuthRepository authRepository(Ref ref) {
  return AuthRepository(
    ref.watch(firebaseAuthProvider),
    ref.watch(googleSignInProvider),
  );
}

/// 현재 인증된 사용자를 도메인 [User]로 노출한다 (D-12).
///
/// [authStateProvider]를 watch하여 firebase User → 도메인 User로 변환한다.
/// 비인증 상태 또는 AsyncLoading/AsyncError 시에는 null을 반환한다.
/// firebase_auth import는 features/auth/data 경계 안에 격리되며,
/// presentation 계층은 본 Provider만 사용해야 한다.
@Riverpod(keepAlive: true)
User? currentUser(Ref ref) {
  final asyncState = ref.watch(authStateProvider);
  return asyncState.whenOrNull(
    data: (fbUser) => fbUser == null ? null : _mapFirebaseUser(fbUser),
  );
}
