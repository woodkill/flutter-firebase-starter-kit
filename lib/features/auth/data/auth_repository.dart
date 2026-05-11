// `cloud_functions` 의 `Result` 와 [Result] (core/error/result.dart) 가 충돌하므로
// 본 파일은 cloud_functions 의 Result 를 hide 한다 (본 모듈은 [Result] 만 사용).
import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/foundation.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/error/app_exception.dart';
import '../../../core/error/result.dart';
import '../../../core/providers/firebase_providers.dart';
import '../application/social_link_in_progress.dart';
import '../domain/user.dart';
import 'kakao_sdk_client.dart';
import 'naver_sdk_client.dart';

part 'auth_repository.g.dart';

/// Firebase Auth를 감싸는 인증 Repository.
///
/// FirebaseAuth와 GoogleSignIn 의존성을 data 계층에 격리하고,
/// 상위 레이어(Notifier)에는 [Result] 타입으로만 노출한다.
/// FirebaseAuthException은 [AppException]으로 매핑되어 던져진다.
class AuthRepository {
  /// [AuthRepository]를 생성한다.
  ///
  /// [_socialLinkInProgress] 는 social IdP linking 진행 중을 표시하는 race
  /// 보호 신호 (Phase 9.1 D-01). signInWithGoogle/Apple/Facebook/Kakao 의
  /// try-finally 블록에서 begin()/end() 가 호출된다 (D-03 / Phase 12 D-15).
  ///
  /// [_kakaoSdkClient] 와 [_functions] 는 Phase 12 Kakao 로그인 (Custom Token
  /// 방식) 을 위해 추가됐다 — kakao_flutter_sdk_user 호출 wrapper +
  /// `kakaoCustomToken` Cloud Function 호출 채널.
  ///
  /// [_naverSdkClient] 는 Phase 13 Naver 로그인 (Custom Token 방식) 을 위해
  /// 추가됐다 — naver_login_sdk callback → Future wrapper. Cloud Function
  /// 채널 (`naverCustomToken`) 은 [_functions] 를 재사용한다.
  const AuthRepository(
    this._auth,
    this._googleSignIn,
    this._facebookAuth,
    this._socialLinkInProgress,
    this._kakaoSdkClient,
    this._functions,
    this._naverSdkClient,
  );

  final fb.FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;
  final FacebookAuth _facebookAuth;
  final SocialLinkInProgress _socialLinkInProgress;
  final KakaoSdkClient _kakaoSdkClient;
  final FirebaseFunctions _functions;
  final NaverSdkClient _naverSdkClient;

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
  /// 흐름: (익명 분기) `EmailAuthProvider.credential` + `linkWithCredential` /
  /// (비익명) `createUserWithEmailAndPassword` → `updateDisplayName` → `reload` →
  /// 도메인 User 변환.
  ///
  /// **Phase 10 D-14 / BLOCKER #4:** `_auth.currentUser` 가 익명 사용자라면
  /// `linkWithCredential` 로 익명 UID 를 정식 이메일/비밀번호 자격증명에 연결하여
  /// 단일 clean `authStateChanges` emit 을 유도한다. `email-already-in-use`
  /// 시에는 익명 계정을 유지한 채 [EmailAlreadyInUse] Failure 를 반환한다
  /// (delete 하지 않음 — 사용자가 기존 이메일로 로그인하면 다시 정식 세션으로
  /// 전환됨). 다중 provider linking / 재승격 / 익명 데이터 마이그레이션은
  /// Phase 17 (Account Linking) — see ROADMAP.md.
  Future<Result<User>> signUpWithEmail({
    required String email,
    required String password,
    required String displayName,
  }) async {
    // D-10 흐름:
    // 1. (익명) linkWithCredential / (비익명) createUserWithEmailAndPassword
    // 2. updateDisplayName (실패 시 graceful: 계정은 생성됨, displayName 미설정)
    // 3. reload (실패 시 _auth.currentUser 재획득으로 fallback)
    // 4. _mapFirebaseUser 로 도메인 모델 변환
    try {
      final anonymous = _auth.currentUser;
      final fb.UserCredential credential;
      if (anonymous != null && anonymous.isAnonymous) {
        // Phase 10 D-14 / BLOCKER #4: 익명 → 정식 승격.
        final emailCredential = fb.EmailAuthProvider.credential(
          email: email,
          password: password,
        );
        credential = await anonymous.linkWithCredential(emailCredential);
      } else {
        credential = await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      }
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
  ///
  /// **Phase 10 D-14 / BLOCKER #4:** `_auth.currentUser` 가 익명 사용자라면
  /// [fb.User.linkWithCredential] 로 익명 UID 를 Google 자격증명에 연결한다.
  /// `credential-already-in-use` / `email-already-in-use` 예외 시 익명 계정을
  /// [_safeDelete] 로 폐기하고 기존 Google 계정으로 [fb.FirebaseAuth.signInWithCredential]
  /// fallback. 익명 UID 로 작성된 Firestore 데이터는 손실 (Starter Kit D-09 —
  /// 1회성 승격 패턴). 다중 provider linking 은 Phase 17 (Account Linking) —
  /// see ROADMAP.md.
  ///
  /// **Phase 9.1 D-03 / D-04:** 메서드 body 전체를 try-finally 로 감싸
  /// 진입 직후 [SocialLinkInProgress.begin] / 종료 시 [SocialLinkInProgress.end]
  /// 를 호출한다. 이로써 `_safeDelete` +
  /// `signInWithCredential` 사이의 `currentUser=null` 윈도우 동안 splash 의 자동
  /// 익명 sign-in 과 auth_guard 의 GC-04 fail-safe redirect 를 보류시킨다.
  /// race condition 상세: `09-UAT.md` Gap test 6.
  Future<Result<User>?> signInWithGoogle() async {
    try {
      _socialLinkInProgress.begin();
      final account = await _googleSignIn.authenticate();
      final authentication = account.authentication;
      final credential = fb.GoogleAuthProvider.credential(
        idToken: authentication.idToken,
      );

      final anonymous = _auth.currentUser;
      fb.UserCredential userCredential;
      if (anonymous != null && anonymous.isAnonymous) {
        // Phase 10 D-14 / BLOCKER #4: 익명 → 정식 승격.
        try {
          userCredential = await anonymous.linkWithCredential(credential);
        } on fb.FirebaseAuthException catch (e) {
          if (e.code == 'credential-already-in-use' ||
              e.code == 'email-already-in-use') {
            // 이미 Google 로 가입된 계정이 있음 — 익명 데이터 폐기 + 기존 계정 로그인.
            if (kDebugMode) {
              debugPrint(
                'AuthRepository.signInWithGoogle: credential-already-in-use '
                '— 익명 계정 폐기 + 기존 Google 계정 로그인',
              );
            }
            await _safeDelete(anonymous);
            userCredential = await _auth.signInWithCredential(credential);
          } else {
            rethrow;
          }
        }
      } else {
        userCredential = await _auth.signInWithCredential(credential);
      }
      final fbUser = userCredential.user;
      if (fbUser == null) {
        return const Result.failure(ServiceUnavailable());
      }
      // (Phase 9.2 R4) 자동 sendEmailVerification — Google idToken
      // email_verified=true claim 자연 no-op (D-19).
      // WR-01: helper 가 isNewUser 추출을 흡수 → call site 1줄 압축.
      await _autoSendEmailVerification(userCredential);
      return Result.success(_mapFirebaseUser(fbUser));
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return null;
      }
      return Result.failure(_mapGoogleException(e));
    } on fb.FirebaseAuthException catch (e) {
      return Result.failure(_mapAuthException(e));
    } on Object catch (e, st) {
      // 비-Auth 예외 (PlatformException 등) 를 Result 로 감싸 Notifier state
      // 가 AsyncLoading 에 고정되는 것을 방지한다 (Apple/Facebook 패턴 미러링).
      // begin/end invariant 자체는 finally 블록이 보장하므로 race-fix 와 직교.
      if (kDebugMode) {
        debugPrint('signInWithGoogle 비-Auth 예외: $e\n$st');
      }
      return Result.failure(ServiceUnavailable(cause: e));
    } finally {
      _socialLinkInProgress.end();
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
  ///
  /// **Phase 10 D-14 / BLOCKER #4:** `_auth.currentUser` 가 익명 사용자라면
  /// [fb.User.linkWithProvider] 로 익명 UID 를 Apple 자격증명에 연결한다.
  /// `credential-already-in-use` / `email-already-in-use` 예외 시 익명 계정을
  /// [_safeDelete] 로 폐기하고, 1차 [fb.User.linkWithProvider] 가 던진
  /// [fb.FirebaseAuthException.credential] 을 우선 재사용하여
  /// [fb.FirebaseAuth.signInWithCredential] 한 번으로 종결한다 — Apple OAuth
  /// 플로우(Android Custom Tab / iOS ASAuthorizationController 시트) 재진입을
  /// 회피한다 (260503-ang quick). `e.credential == null` 인 보조 경로에서만
  /// [fb.FirebaseAuth.signInWithProvider] fallback 으로 회귀를 방지한다.
  ///
  /// **Blocker #2 — `_auth.currentUser` 재조회 제거:** linking / signIn 결과
  /// [fb.UserCredential.user] 를 직접 [_mapFirebaseUser] 에 전달하며,
  /// `_auth.currentUser` 재조회는 수행하지 않는다. 구현 단순화 + 테스트 stub
  /// 복잡도 제거 이중 효과.
  ///
  /// **Phase 9.1 D-03 / D-04:** 메서드 body 전체를 try-finally 로 감싸
  /// 진입 직후 [SocialLinkInProgress.begin] / 종료 시 [SocialLinkInProgress.end]
  /// 를 호출한다. 이로써 `_safeDelete` +
  /// `signInWithProvider` 사이의 `currentUser=null` 윈도우 동안 splash 의 자동
  /// 익명 sign-in 과 auth_guard 의 GC-04 fail-safe redirect 를 보류시킨다.
  /// race condition 상세: `09-UAT.md` Gap test 6.
  Future<Result<User>?> signInWithApple() async {
    try {
      _socialLinkInProgress.begin();
      final provider = fb.AppleAuthProvider()
        ..addScope('email')
        ..addScope('name');

      final anonymous = _auth.currentUser;
      fb.UserCredential userCredential;
      if (anonymous != null && anonymous.isAnonymous) {
        // Phase 10 D-14 / BLOCKER #4: 익명 → 정식 승격.
        try {
          userCredential = await anonymous.linkWithProvider(provider);
        } on fb.FirebaseAuthException catch (e) {
          if (e.code == 'credential-already-in-use' ||
              e.code == 'email-already-in-use') {
            // Quick 260503-ang: 1차 linkWithProvider 의 credential 을 보존해
            // signInWithCredential 로 재사용한다. Apple OAuth Custom Tab(Android) /
            // ASAuthorizationController 시트(iOS) 가 두 번 열리는 UX 결함 차단.
            // e.credential 이 null 인 이론적 fallback 만 signInWithProvider 재호출.
            final pendingCredential = e.credential;
            if (kDebugMode) {
              debugPrint(
                'AuthRepository.signInWithApple: credential-already-in-use '
                '— 익명 계정 폐기 + 기존 Apple 계정 로그인 '
                '(credential reuse: ${pendingCredential != null})',
              );
            }
            await _safeDelete(anonymous);
            if (pendingCredential != null) {
              userCredential = await _auth.signInWithCredential(
                pendingCredential,
              );
            } else {
              userCredential = await _auth.signInWithProvider(provider);
            }
          } else {
            rethrow;
          }
        }
      } else {
        userCredential = await _auth.signInWithProvider(provider);
      }

      final fbUser = userCredential.user;
      if (fbUser == null) {
        return const Result.failure(ServiceUnavailable());
      }
      // Blocker #2: `_auth.currentUser` 재조회 금지. linkWithProvider /
      // signInWithProvider 결과의 UserCredential.user 를 직접 사용한다.
      // (Phase 9.2 R4) 자동 sendEmailVerification — Apple idToken
      // email_verified=true claim 자연 no-op (D-19).
      // WR-01: helper 가 isNewUser 추출을 흡수 → call site 1줄 압축.
      await _autoSendEmailVerification(userCredential);
      return Result.success(_mapFirebaseUser(fbUser));
    } on fb.FirebaseAuthException catch (e) {
      // D-09: 사용자 취소 시 null 반환.
      if (e.code == 'canceled' ||
          e.code == 'web-context-canceled' ||
          e.code == 'web-context-cancelled' ||
          e.code == 'popup-closed-by-user') {
        return null;
      }
      return Result.failure(_mapAuthException(e));
    } on Object catch (e, st) {
      // 비-Auth 예외 (PlatformException 등)를 Result로 감싸
      // Notifier state가 AsyncLoading에 고정되는 것을 방지한다.
      if (kDebugMode) {
        debugPrint('signInWithApple 비-Auth 예외: $e\n$st');
      }
      return Result.failure(ServiceUnavailable(cause: e));
    } finally {
      _socialLinkInProgress.end();
    }
  }

  /// Facebook 계정으로 Firebase Auth에 로그인한다 (D-01).
  ///
  /// [FacebookAuth.login]으로 Classic Login을 수행하고 (D-03),
  /// 획득한 [AccessToken]의 tokenString으로
  /// [fb.FacebookAuthProvider.credential]을 생성하여
  /// [fb.FirebaseAuth.signInWithCredential]에 전달한다.
  ///
  /// 요청 권한은 email + public_profile만 사용한다 (D-02).
  /// 사용자 취소 시 null을 반환하여 Notifier에서 no-op 처리한다 (D-09).
  /// 동일 이메일 충돌 시 [AccountExistsWithDifferentCredential]을 반환한다.
  ///
  /// **Phase 10 D-14 / BLOCKER #4:** `_auth.currentUser` 가 익명 사용자라면
  /// [fb.User.linkWithCredential] 로 익명 UID 를 Facebook 자격증명에 연결한다.
  /// `credential-already-in-use` / `email-already-in-use` 예외 시 익명 계정을
  /// [_safeDelete] 로 폐기하고 기존 Facebook 계정으로 [fb.FirebaseAuth.signInWithCredential]
  /// fallback. 익명 UID 로 작성된 Firestore 데이터는 손실 (D-09 — 1회성 승격).
  ///
  /// **Phase 9.1 D-03 / D-04:** 메서드 body 전체를 try-finally 로 감싸
  /// 진입 직후 [SocialLinkInProgress.begin] / 종료 시 [SocialLinkInProgress.end]
  /// 를 호출한다. 이로써 `_safeDelete` +
  /// `signInWithCredential` 사이의 `currentUser=null` 윈도우 동안 splash 의 자동
  /// 익명 sign-in 과 auth_guard 의 GC-04 fail-safe redirect 를 보류시킨다.
  /// race condition 상세: `09-UAT.md` Gap test 6.
  Future<Result<User>?> signInWithFacebook() async {
    try {
      _socialLinkInProgress.begin();
      final loginResult = await _facebookAuth.login(
        permissions: ['email', 'public_profile'],
        loginTracking: LoginTracking.enabled,
      );

      if (loginResult.status != LoginStatus.success) {
        return null;
      }

      final accessToken = loginResult.accessToken;
      if (accessToken == null) {
        return null;
      }

      final credential = fb.FacebookAuthProvider.credential(
        accessToken.tokenString,
      );

      final anonymous = _auth.currentUser;
      fb.UserCredential userCredential;
      if (anonymous != null && anonymous.isAnonymous) {
        // Phase 10 D-14 / BLOCKER #4: 익명 → 정식 승격.
        try {
          userCredential = await anonymous.linkWithCredential(credential);
        } on fb.FirebaseAuthException catch (e) {
          if (e.code == 'credential-already-in-use' ||
              e.code == 'email-already-in-use') {
            if (kDebugMode) {
              debugPrint(
                'AuthRepository.signInWithFacebook: credential-already-in-use '
                '— 익명 계정 폐기 + 기존 Facebook 계정 로그인',
              );
            }
            await _safeDelete(anonymous);
            userCredential = await _auth.signInWithCredential(credential);
          } else {
            rethrow;
          }
        }
      } else {
        userCredential = await _auth.signInWithCredential(credential);
      }

      final fbUser = userCredential.user;
      if (fbUser == null) {
        return const Result.failure(ServiceUnavailable());
      }
      // (Phase 9.2 R4 + R5 — D-25 verify → photoURL 순차)
      // Facebook 만 emailVerified=false 기본 → 실효적 sendEmailVerification.
      // photoURL 은 Graph API picture.type(large) 응답 기반 갱신.
      // 두 호출 모두 race-fix try-finally 블록 안 (D-22, Phase 9.1 D-03).
      // WR-01: helper 가 isNewUser 추출을 흡수 → call site 1줄 압축.
      await _autoSendEmailVerification(userCredential);
      await _setFacebookPhotoUrl(fbUser);
      return Result.success(_mapFirebaseUser(fbUser));
    } on fb.FirebaseAuthException catch (e) {
      return Result.failure(_mapAuthException(e));
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('signInWithFacebook 비-Auth 예외: $e\n$st');
      }
      return Result.failure(ServiceUnavailable(cause: e));
    } finally {
      _socialLinkInProgress.end();
    }
  }

  /// Kakao 계정으로 Firebase Auth 에 로그인한다 (Phase 12 D-28 / SOCL-01).
  ///
  /// **Custom Token 방식** — Native provider (Google/Apple/Facebook) 와 달리
  /// Firebase 가 직접 IdP 와 통신하지 않고, Cloud Function `kakaoCustomToken`
  /// 이 Kakao OIDC ID Token 을 jose 로 자체 검증한 뒤 Custom Token 을 발급한다.
  /// 익명 → Kakao 승격은 Cloud Function 의 `request.auth.uid` seed 로직
  /// (12-02 Pattern 3) 이 처리하므로, 본 메서드는 `linkWithCredential` 분기를
  /// 사용하지 않는다 (D-28 — Native provider 와의 차이).
  ///
  /// 흐름 (RESEARCH Pattern 4):
  /// 1. [SocialLinkInProgress.begin] (race-fix Pitfall 8 — 단일 진실원)
  /// 2. [_kakaoSdkClient.signIn] (D-01 KakaoTalk 우선 + fallback, D-04 nonce)
  ///    - null 반환 (사용자 취소) → null 반환 (D-05 silent)
  /// 3. `_functions.httpsCallable('kakaoCustomToken')(idToken, nonce)` →
  ///    Cloud Function 이 OIDC 검증 + Identity Index lookup-first +
  ///    `createCustomToken` (12-02)
  /// 4. [fb.FirebaseAuth.signInWithCustomToken] → Firebase Auth 세션 시작
  /// 5. [_mapFirebaseUser] → 도메인 [User]
  /// 6. finally: [SocialLinkInProgress.end]
  ///
  /// 에러 매핑 (D-30 — 기존 [AppException] 계층 재사용):
  /// - [PlatformException 'CANCELED'] / [KakaoClientException
  ///   ClientErrorCause.cancelled] — wrapper 가 null 로 흡수.
  /// - [FirebaseFunctionsException] → [_mapFunctionsException] (12-02 표준
  ///   코드 매핑 — invalid-argument/unauthenticated → ServiceUnavailable,
  ///   unavailable/deadline-exceeded → NoInternetConnection)
  /// - [fb.FirebaseAuthException] → [_mapAuthException] (기존 helper 재사용)
  /// - [ServiceUnavailable] (idToken null — Pitfall 1 OIDC 미활성화) → 그대로
  ///   Failure 재패키징
  /// - 그 외 → [ServiceUnavailable(cause: e)] + kDebugMode debugPrint
  ///
  /// **Phase 9.1 D-03 / D-04 race-fix:** body 전체 try-finally 로 감싸
  /// 진입 직후 [SocialLinkInProgress.begin] / 종료 시 [SocialLinkInProgress.end]
  /// 호출. Strategy 단계 추가 호출 절대 금지 (Pitfall 8).
  Future<Result<User>?> signInWithKakao() async {
    // WR-01-iter2 (Phase 13 review iter2): D-57 1회성 토큰 정책의 invariant 강화
    // — 모든 path 에서 finally logout. 이전 iter1 의 `issuedToken` 가드는 timeout
    // path 에서 SDK 측 디바이스 토큰이 잔존할 가능성 (24h TTL) 을 남겼다.
    // KakaoSdkClient.logout 은 내부 try/catch graceful — SDK "no session" 상태에서도
    // silent no-op (D-57 retroactive 일관). 사용자 취소 / signIn 단계 throw path
    // 의 spurious platform-channel round-trip 비용은 운영상 무시 가능 수준이고,
    // D-57 의 invariant ("finally 에서 즉시 logout") 가 timeout / 취소 path 에서도
    // 일관되게 적용되는 보안 우선 정책 채택.
    try {
      _socialLinkInProgress.begin();

      final result = await _kakaoSdkClient.signIn();
      if (result == null) {
        // 사용자 취소 silent (D-05 — wrapper 가 null 로 흡수).
        return null;
      }

      final callable = _functions.httpsCallable('kakaoCustomToken');
      final response = await callable.call<Map<String, dynamic>>(
        <String, dynamic>{'idToken': result.idToken, 'nonce': result.nonce},
      );
      final customToken = response.data['customToken'] as String?;
      if (customToken == null) {
        return const Result.failure(ServiceUnavailable());
      }

      final userCredential = await _auth.signInWithCustomToken(customToken);
      final fbUser = userCredential.user;
      if (fbUser == null) {
        return const Result.failure(ServiceUnavailable());
      }
      // (Phase 9.2 R4) 자동 sendEmailVerification — Kakao Cloud Function
      // identity_index.ts:225 emailVerified=true 자연 no-op (D-19).
      // WR-01: helper 가 isNewUser 추출을 흡수 → call site 1줄 압축.
      await _autoSendEmailVerification(userCredential);
      return Result.success(_mapFirebaseUser(fbUser));
    } on FirebaseFunctionsException catch (e) {
      return Result.failure(_mapFunctionsException(e));
    } on fb.FirebaseAuthException catch (e) {
      return Result.failure(_mapAuthException(e));
    } on ServiceUnavailable catch (e) {
      // KakaoSdkClient 가 idToken null 시 throw — Pitfall 1 (OIDC 미활성화).
      return Result.failure(e);
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('signInWithKakao 비-Auth 예외: $e\n$st');
      }
      return Result.failure(ServiceUnavailable(cause: e));
    } finally {
      // D-57 retroactive (Phase 13 — see ROADMAP.md): SDK 1회성 토큰 정책 일관.
      // Pitfall 2 — race-fix end 직전 위치. 실패 graceful (kDebugMode debugPrint) —
      // outer 흐름 차단 안 함 (KakaoSdkClient.logout 내부 try/catch).
      // WR-01-iter2: timeout / 취소 path 에서도 SDK 측 디바이스 토큰이 잔존할
      // 가능성이 있어 모든 path 에서 logout. SDK "no session" 상태는 logout 내부
      // try/catch 가 silent 흡수.
      await _kakaoSdkClient.logout();
      _socialLinkInProgress.end();
    }
  }

  /// Naver 계정으로 Firebase Auth 에 로그인한다 (Phase 13 — see ROADMAP.md,
  /// SOCL-02).
  ///
  /// **Custom Token 방식** — Phase 12 Kakao 와 동일 흐름. 차이:
  /// (1) SDK = naver_login_sdk (callback-based — [NaverSdkClient] wrapper)
  /// (2) Cloud Function 페이로드 = `accessToken` 단일 (nonce 부재 — D-46)
  /// (3) Naver 검증 = REST `/v1/nid/me` Bearer (CF 측 — Plan 13-02)
  /// (4) finally 에서 SDK logout (D-57 — 1회성 access_token)
  ///
  /// 흐름:
  /// 1. [SocialLinkInProgress.begin] (race-fix Pitfall 8 — 단일 진실원)
  /// 2. [_naverSdkClient.signIn] — null 반환 (사용자 취소) → null silent (D-45)
  /// 3. `_functions.httpsCallable('naverCustomToken')(accessToken)` →
  ///    Cloud Function 이 REST 검증 + Identity Index lookup-first +
  ///    `createCustomToken` (Plan 13-02)
  /// 4. [fb.FirebaseAuth.signInWithCustomToken] → Firebase Auth 세션 시작
  /// 5. [_mapFirebaseUser] → 도메인 [User]
  /// 6. finally: [_naverSdkClient.logout] (D-57 — Pitfall 2 race-fix end 직전) +
  ///    [SocialLinkInProgress.end]
  ///
  /// 에러 매핑 (Phase 12 D-30 / D-34 helper 재사용):
  /// - [NaverSdkClient.signIn] 가 null 반환 (사용자 취소 silent — D-45) → null.
  /// - [FirebaseFunctionsException] → [_mapFunctionsException]
  ///   (`already-exists` 분기는 Phase 12.1 D-34 에서
  ///   [AccountExistsWithDifferentCredential] 자동 흡수)
  /// - [fb.FirebaseAuthException] → [_mapAuthException]
  /// - 그 외 → [ServiceUnavailable(cause: e)] + [kDebugMode] [debugPrint]
  ///
  /// Returns null = 사용자 취소 silent (D-45).
  Future<Result<User>?> signInWithNaver() async {
    // WR-01-iter2 (Phase 13 review iter2): D-57 1회성 토큰 정책의 invariant 강화
    // — 모든 path 에서 finally logout. iter1 의 `issuedToken` 가드는 timeout path
    // (60s onTimeout 직전 SDK 가 onSuccess fire 직전 디바이스 토큰 발급) 에서 SDK
    // 측 access_token 이 24h TTL 까지 잔존할 가능성을 남겼다. NaverSdkClient.logout
    // 은 내부 try/catch graceful — SDK "no session" 상태에서도 silent no-op.
    // Kakao path 와 대칭 (D-57 일관) + 보안 우선 정책 채택.
    try {
      _socialLinkInProgress.begin(); // race-fix Pitfall 8 단일 진실원

      final result = await _naverSdkClient.signIn();
      if (result == null) {
        return null; // D-45 silent
      }

      final callable = _functions.httpsCallable('naverCustomToken');
      final response = await callable.call<Map<String, dynamic>>(
        <String, dynamic>{'accessToken': result.accessToken},
      );
      final customToken = response.data['customToken'] as String?;
      if (customToken == null) {
        return const Result.failure(ServiceUnavailable());
      }

      final userCredential = await _auth.signInWithCustomToken(customToken);
      final fbUser = userCredential.user;
      if (fbUser == null) {
        return const Result.failure(ServiceUnavailable());
      }
      // (Phase 9.2 R4) 자동 sendEmailVerification — Naver Cloud Function
      // identity_index.ts:225 emailVerified=true 자연 no-op (D-19).
      // WR-01: helper 가 isNewUser 추출을 흡수 → call site 1줄 압축.
      await _autoSendEmailVerification(userCredential);
      return Result.success(_mapFirebaseUser(fbUser));
    } on FirebaseFunctionsException catch (e) {
      // already-exists 분기는 Phase 12.1 D-34 에서 _mapFunctionsException 자동 흡수.
      return Result.failure(_mapFunctionsException(e));
    } on fb.FirebaseAuthException catch (e) {
      return Result.failure(_mapAuthException(e));
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('signInWithNaver 비-Auth 예외: $e\n$st');
      }
      return Result.failure(ServiceUnavailable(cause: e));
    } finally {
      // D-57 (Phase 13 — see ROADMAP.md): SDK access_token 1회성 정책.
      // Pitfall 2 — race-fix end 직전 위치. 실패 graceful (NaverSdkClient.logout
      // 내부 try/catch) — outer 흐름 차단 안 함.
      // WR-01-iter2: timeout / 취소 path 에서도 SDK 측 디바이스 토큰이 잔존할
      // 가능성이 있어 모든 path 에서 logout (24h TTL 잔존 회피). SDK "no session"
      // 상태는 logout 내부 try/catch 가 silent 흡수.
      await _naverSdkClient.logout();
      _socialLinkInProgress.end();
    }
  }

  /// 익명 로그인으로 게스트 사용자 세션을 시작한다 (Phase 10 D-09).
  ///
  /// [fb.FirebaseAuth.signInAnonymously] 를 호출하여 임시 UID 를 발급받는다.
  /// 이 UID 는 [fb.User.linkWithCredential] 로 정식 계정에 연결하면 승격된다
  /// (Phase 17 (Account Linking) — see ROADMAP.md).
  ///
  /// 에러 매핑:
  /// - `operation-not-allowed` → [ServiceUnavailable]
  ///   (Firebase Console 에서 Anonymous provider 가 비활성 상태 — A4 위험).
  ///   `_logAndFallback` 이 `kDebugMode` 로그를 출력한다.
  /// - `network-request-failed` → [NoInternetConnection] (Pitfall 3)
  /// - 그 외 FirebaseAuthException → [ServiceUnavailable]
  /// - 비-Auth 예외 → [ServiceUnavailable]
  Future<Result<User>> signInAnonymously() async {
    try {
      final userCredential = await _auth.signInAnonymously();
      final fbUser = userCredential.user;
      if (fbUser == null) {
        return const Result.failure(ServiceUnavailable());
      }
      return Result.success(_mapFirebaseUser(fbUser));
    } on fb.FirebaseAuthException catch (e) {
      return Result.failure(_mapAuthException(e));
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('signInAnonymously 비-Auth 예외: $e\n$st');
      }
      return Result.failure(ServiceUnavailable(cause: e));
    }
  }

  /// 로그아웃 후 즉시 익명 세션으로 재진입한다 (Phase 10 D-20).
  ///
  /// 흐름: [signOut] → [signInAnonymously].
  /// 로그아웃으로 Home 에서 Login 화면으로 튕기는 UX 단절을 방지하고,
  /// 사용자가 즉시 게스트 상태로 앱을 계속 사용할 수 있도록 한다.
  ///
  /// 실패 처리:
  /// - [signOut] 은 기존 정책대로 내부 GoogleSignIn/FacebookAuth 실패를 무시하고
  ///   [fb.FirebaseAuth.signOut] 을 보장한다.
  /// - [signOut] 이 성공한 상태에서 [signInAnonymously] 가 네트워크 오류로
  ///   실패하면 [Result.failure] 를 반환하며, 호출자(Notifier) 가 적절한
  ///   fallback (다이얼로그 또는 /login 이동) 을 결정한다.
  Future<Result<User>> signOutAndContinueAsGuest() async {
    await signOut();
    return signInAnonymously();
  }

  /// 익명 계정을 안전하게 폐기한다 (credential-already-in-use fallback 용).
  ///
  /// [fb.User.delete] 가 `requires-recent-login` 등 예외를 던질 수 있으나,
  /// 익명 계정은 세션 직후에만 생성되어 있으므로 실패 가능성은 낮다.
  /// 실패 시에도 진행하여 상위 fallback [fb.FirebaseAuth.signInWithCredential] /
  /// [fb.FirebaseAuth.signInWithProvider] 가 로그인 UX 를 완결한다.
  /// 실패는 [kDebugMode] 에서만 로깅한다.
  ///
  /// Phase 10 D-14 / BLOCKER #4 `credential-already-in-use` fallback 경로
  /// 전용 헬퍼. public API 표면에는 노출하지 않는다.
  Future<void> _safeDelete(fb.User user) async {
    try {
      await user.delete();
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('AuthRepository._safeDelete 실패 (무시): $e\n$st');
      }
    }
  }

  /// (Phase 9.2 D-18 — R4) Firebase Auth 의 [fb.User.sendEmailVerification] 을
  /// 5 social sign-in 메서드 success path 에서 자동 호출하는 단일 진실원.
  ///
  /// **WR-01 (Phase 9.2 review fix):** 시그니처를 [fb.UserCredential] 채택으로
  /// 변경 — `isNewUser` 추출을 helper 안으로 흡수하여 5 call site 의 verbatim
  /// 복제 (`final isNewUser = userCredential.additionalUserInfo?.isNewUser
  /// ?? false;`) 를 제거. SRP/DRY 강화.
  ///
  /// 가드 (D-19) — 다음 5 조건 중 하나라도 true 면 no-op:
  /// - [fb.UserCredential.user] == null
  /// - [fb.User.isAnonymous] == true
  /// - [fb.User.email] 이 null 또는 빈 문자열 (WR-04 fix — 이전 `== null`
  ///   가드는 빈 문자열을 통과시켜 Firebase Auth 가 `auth/missing-email`
  ///   throw 시 graceful catch 가 흡수하나 메일 미발송)
  /// - [fb.User.emailVerified] == true
  /// - [fb.AdditionalUserInfo.isNewUser] == false (D-20 — 재로그인 spam 방지)
  ///
  /// Apple/Google 의 idToken `email_verified=true` claim + Kakao/Naver 의
  /// Cloud Function `identity_index.ts:225` `emailVerified: true` 자동 set
  /// 으로 인해 4 provider 는 자연 no-op 이며, Facebook 만 실효적 호출 한다.
  ///
  /// 발송 실패는 graceful (D-21 — Phase 6.1 D-10/D-11 패턴 계승). 로그인
  /// 자체는 성공 유지. [fb.FirebaseAuthException] + [Object] 양쪽 catch +
  /// [kDebugMode] [debugPrint] only.
  Future<void> _autoSendEmailVerification(
    fb.UserCredential userCredential,
  ) async {
    final user = userCredential.user;
    if (user == null) return;
    if (user.isAnonymous) return;
    // WR-04: `email == null` 가드는 빈 문자열을 통과 → Firebase Auth 가
    // `auth/missing-email` throw 시 graceful catch 흡수하나 메일 미발송.
    // null + empty 양쪽을 단일 가드로 차단.
    if ((user.email ?? '').isEmpty) return;
    if (user.emailVerified) return;
    final isNewUser = userCredential.additionalUserInfo?.isNewUser ?? false;
    if (!isNewUser) return; // D-20 재로그인 spam 방지
    try {
      // WR-03 (Phase 9.2 review fix): timeout 보호. helper 가 race-fix
      // try-finally 블록 안에서 await 되므로 hang 시 `_socialLinkInProgress.end()`
      // 도 hang → splash 자동 익명 sign-in / auth_guard GC-04 fail-safe redirect
      // 무한 차단 (Phase 9.1 D-03 race-fix 와 직접 충돌). [TimeoutException] 은
      // 아래 `on Object catch` 가 graceful 흡수.
      await user.sendEmailVerification().timeout(const Duration(seconds: 5));
    } on fb.FirebaseAuthException catch (e) {
      if (kDebugMode) {
        debugPrint('_autoSendEmailVerification FirebaseAuth 실패: ${e.code}');
      }
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('_autoSendEmailVerification 비-Auth 예외: $e\n$st');
      }
    }
  }

  /// (Phase 9.2 D-23 — R5) Facebook Graph API picture.type(large) →
  /// [fb.User.updatePhotoURL] 갱신 단일 진실원.
  ///
  /// 응답 path 추출 = safe navigation + type guard + graceful skip (D-24).
  /// [FacebookAuth.getUserData] default fields 는
  /// `'name,email,picture.width(200)'` 이지만 SPEC R5 가 `picture.type(large)`
  /// 채택 — 명시 fields 인자 의무.
  ///
  /// graceful skip 발동 조건:
  /// - `result['picture']` 가 [Map] 이 아님
  /// - `result['picture']['data']` 가 [Map] 이 아님
  /// - `result['picture']['data']['url']` 이 [String] 이 아님 또는 빈 string
  /// - [FacebookAuth.getUserData] / [fb.User.updatePhotoURL] 가 throw
  ///
  /// **D-27 PII regression invariant:** catch 블록의 [debugPrint] 가
  /// `e.runtimeType` + [StackTrace] 만 출력한다 (`e.toString()` / `result`
  /// Map / `url` 값 직접 출력 금지). Dart [StackTrace] 는 file path + function
  /// symbol + line number 만 포함하므로 exception message body 의 PII
  /// (sentinel facebook id `'999888777'` / sentinel CDN URL / sentinel email)
  /// 가 logger 에 노출되지 않는다. graceful skip 디버깅 가치를 위해 stack
  /// trace 보존을 의도된 design 으로 채택. Phase 12.1 D-40 catch-block
  /// sentinel 패턴 계승.
  Future<void> _setFacebookPhotoUrl(fb.User user) async {
    try {
      // (D-24) SPEC R5 의 'picture.type(large)' 명시 fields verbatim.
      // WR-03 (Phase 9.2 review fix): Graph API (외부 서버) hang 보호 — 5s
      // timeout. race-fix try-finally 블록 안에서 await 되므로 hang 시
      // `_socialLinkInProgress.end()` 도 hang → splash 자동 익명 sign-in /
      // auth_guard GC-04 fail-safe redirect 무한 차단 (Phase 9.1 D-03 race-fix
      // 와 직접 충돌). [TimeoutException] 은 아래 `on Object catch` 가 graceful
      // 흡수.
      final result = await _facebookAuth
          .getUserData(fields: 'picture.type(large)')
          .timeout(const Duration(seconds: 5));
      // BL-01 (Phase 9.2 review fix): iOS 의 Facebook getUserData 응답은
      // `Map<String, dynamic>.from(result)` shallow 변환 — `result['picture']`
      // 가 native bridge 시 `Map<dynamic, dynamic>` (또는
      // `_InternalLinkedHashMap<Object?, Object?>`) 로 들어옴. Dart generic
      // invariance 로 인해 `is Map<String, dynamic>` 검사가 항상 false 가 되어
      // R5 silent skip 회귀를 일으킨다. generic 인자 없이 `is Map` 으로 완화하여
      // Android (typed) / iOS (untyped) 양쪽 응답 형태를 모두 흡수한다.
      final pictureData = result['picture'];
      if (pictureData is Map) {
        final data = pictureData['data'];
        if (data is Map) {
          final url = data['url'];
          if (url is String && url.isNotEmpty) {
            // WR-03: updatePhotoURL 도 동일하게 5s timeout 보호. Firebase Auth
            // native HTTP 호출이라 platform-side timeout 가능성 있으나 보수적
            // 로 적용.
            await user.updatePhotoURL(url).timeout(const Duration(seconds: 5));
          }
        }
      }
    } on Object catch (e, st) {
      // (D-27 PII invariant) e.runtimeType + StackTrace 만 출력 — exception
      // message body (Graph API 응답 PII: facebook id, CDN URL, email) 의
      // logger 노출 vector 차단. StackTrace 는 file/symbol/line 만 포함하므로
      // PII safe.
      if (kDebugMode) {
        debugPrint(
          '_setFacebookPhotoUrl 실패 (graceful skip): ${e.runtimeType}\n$st',
        );
      }
    }
  }

  /// 로그아웃한다.
  ///
  /// [GoogleSignIn.signOut]을 병행 호출하여 Google 세션도 해제한다 (D-07).
  /// [FacebookAuth.logOut]을 병행 호출하여 Facebook 세션도 해제한다 (D-08).
  /// 각 소셜 로그인 SDK의 signOut/logOut 실패 시에도
  /// [fb.FirebaseAuth.signOut]은 반드시 호출한다.
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('GoogleSignIn.signOut() 실패 (무시): $e\n$st');
      }
    }
    // Facebook 세션 해제 (D-08).
    try {
      await _facebookAuth.logOut();
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('FacebookAuth.logOut() 실패 (무시): $e\n$st');
      }
    }
    // Kakao SDK 세션 해제 (Phase 9.2 D-26 — Phase 12 D-57 정합).
    try {
      await _kakaoSdkClient.logout();
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('KakaoSdkClient.logout() 실패 (무시): $e\n$st');
      }
    }
    // Naver SDK 세션 해제 (Phase 9.2 D-26 — Phase 13 D-57 정합).
    try {
      await _naverSdkClient.logout();
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('NaverSdkClient.logout() 실패 (무시): $e\n$st');
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
      'user-not-found' => InvalidCredentials(cause: e),
      // (Phase 9.2 R2) Path A-narrow — email 필드 보존: Phase 17 (Account
      // Linking) — see ROADMAP.md 부활 시 server-side provider 매핑 input.
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

  /// [FirebaseFunctionsException] 을 [AppException] 으로 매핑한다
  /// (Phase 12 D-30 / RESEARCH Pattern 4 / Phase 12.1 R3 — D-34).
  ///
  /// Cloud Function 의 [HttpsError] 표준 코드 → [AppException] 분류:
  /// - `unauthenticated` / `invalid-argument` / `failed-precondition`
  ///   → [ServiceUnavailable] (App Check 차단 / JWT 검증 실패 / 사전 조건 위배)
  /// - `unavailable` / `deadline-exceeded` → [NoInternetConnection]
  ///   (Cloud Function 일시 장애 / 네트워크 지연)
  /// - `already-exists` → [AccountExistsWithDifferentCredential]
  ///   (R3 — Phase 12.1 BL-04 hotfix. Cloud Function 의 already-exists 응답을
  ///    사용자 recovery 가능한 도메인 예외로 매핑. email field 는 Cloud Function
  ///    이 PII 이유로 응답에 미포함 → null 유지. LoginScreen 의 자동 채움은
  ///    `email != null` 분기에서만 트리거)
  /// - 그 외 → [ServiceUnavailable(cause: e)]
  AppException _mapFunctionsException(FirebaseFunctionsException e) {
    return switch (e.code) {
      'unauthenticated' ||
      'invalid-argument' ||
      'failed-precondition' => const ServiceUnavailable(),
      'unavailable' || 'deadline-exceeded' => const NoInternetConnection(),
      // R3 (D-34) — Cloud Function 의 already-exists → 사용자 recovery 가능한
      // AccountExistsWithDifferentCredential 매핑. 신규 클래스/ARB 0건
      // (Phase 8/9 패턴 재사용 — errorAccountExistsWithDifferentCredential).
      // (Phase 9.2 R2) Path A-narrow — email==null 유지: Phase 17 (Account
      // Linking) — see ROADMAP.md 부활 시 unknown fallback 동일 path 통합.
      'already-exists' => AccountExistsWithDifferentCredential(cause: e),
      _ => ServiceUnavailable(cause: e),
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
    providerIds: fbUser.providerData.map((info) => info.providerId).toList(),
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
    ref.watch(facebookAuthProvider),
    ref.watch(socialLinkInProgressProvider.notifier),
    ref.watch(kakaoSdkClientProvider),
    ref.watch(firebaseFunctionsProvider),
    ref.watch(naverSdkClientProvider),
  );
}

/// 현재 인증된 사용자를 도메인 [User]로 노출한다 (D-12, Phase 12 D-16 확장).
///
/// [authStateProvider]를 watch하여 firebase User → 도메인 User로 변환한다.
/// 비인증 상태 또는 AsyncLoading/AsyncError 시에는 null을 반환한다.
/// firebase_auth import는 features/auth/data 경계 안에 격리되며,
/// presentation 계층은 본 Provider만 사용해야 한다.
///
/// **Phase 12 변경 (D-16):** Firebase `providerData[].providerId`
/// (Native 4 — `'google.com'` 등 OAuth URI) 와 Firestore
/// `users/{uid}.linkedProviders[].providerId` (Custom Token slug — `'kakao'`
/// 등) 를 합집합 (Set 기반 중복 제거) 으로 [User.providerIds] 에 채운다.
/// Firebase Auth `providerData` 는 Custom Token 흐름 (Kakao 등) 을 표시하지
/// 않으므로, Custom Token provider 의 진실원은 Firestore `linkedProviders[]`
/// 다 (D-15).
///
/// **Fallback (Phase 13 R13 fix — 옵션 A, explicit pattern matching):**
/// `linkedProvidersStreamProvider` 의 AsyncValue 3 분기를 명시적으로 처리한다.
///
/// - **AsyncData(list)**: list 그대로 합산 (기존 동일).
/// - **AsyncLoading**: `linkedAsync.value` (직전 cached emit) 우선 활용,
///   null (첫 진입) 이면 빈 배열 fallback. sign-in 직후 첫 emit 도착 전
///   시점에도 cached list 가 보존되어 Custom Token user (Naver/Kakao) 의
///   ephemeral "-" UX (R13 race) 가 차단된다.
/// - **AsyncError**: 빈 배열 fallback (영구 spinner 회피, 옵션 A 단점 대응).
///   실 production path 는 `linkedProvidersStream` 의 `handleError` 가
///   `AsyncData(<String>[])` 로 정착시키므로 본 분기 도달은 거의 없으나
///   안전망으로 유지.
///
/// 폐기된 contract (Phase 12 ~ Phase 13 R13 발현 전):
/// `maybeWhen(data:..., orElse: const <String>[])` — AsyncLoading + AsyncError
/// 모두 빈 배열 fallback 으로 fall-through → ephemeral "-" UX 회귀.
///
/// **Race 안전성 (Pitfall 12):** 12-02 Cloud Function 이 `users/{uid}` 를
/// `set({...}, {merge: true})` 로 작성하므로 Plan 10-12 mirrorToFirestore 와
/// 공존한다. linkedProviders 가 사라지지 않는다.
@Riverpod(keepAlive: true)
User? currentUser(Ref ref) {
  final asyncState = ref.watch(authStateProvider);
  final fbUser = asyncState.whenOrNull(data: (u) => u);
  if (fbUser == null) return null;

  final base = _mapFirebaseUser(fbUser);

  // Phase 12 D-16 + Phase 13 R13 fix (옵션 A): 합집합 — explicit AsyncValue
  // pattern matching 으로 AsyncLoading 직전 cached emit 보존.
  //
  // - AsyncData(list)  → list 그대로 사용
  // - AsyncLoading     → linkedAsync.value (직전 cached emit) ?? const <String>[]
  //                      sign-in 직후 첫 emit 도착 전 시점에 base.providerIds
  //                      만으로 fallback 하지 않음 — Custom Token user (Naver/
  //                      Kakao) 의 ephemeral '-' UX (R13) 차단.
  // - AsyncError       → const <String>[] (영구 spinner 회피, handleError 가
  //                      이미 AsyncData([]) 정착하므로 실질 도달 거의 없음)
  final linkedAsync = ref.watch(linkedProvidersStreamProvider(fbUser.uid));
  final linked = linkedAsync.when(
    data: (list) => list,
    loading: () => linkedAsync.value ?? const <String>[],
    error: (_, _) => const <String>[],
  );

  if (linked.isEmpty) return base;
  // Set 기반 중복 제거 (Native URI + Custom Token slug 양쪽 보존).
  final merged = <String>{...base.providerIds, ...linked}.toList();
  return base.copyWith(providerIds: merged);
}

/// Firestore `users/{uid}.linkedProviders[].providerId` 를 stream 으로 노출한다
/// (Phase 12 D-16, family by uid).
///
/// `users/{uid}` 문서가 미존재 (mirrorToFirestore 가 작성 전) 이거나
/// `linkedProviders` 필드가 없으면 빈 배열을 emit 한다.
///
/// **에러 흡수 (Phase 12.1 R6 / D-41 보존):** 네트워크 / 다른 FirebaseException
/// 발생 시 빈 배열을 명시적으로 emit 한다 — `AsyncData(<String>[])` 정착으로
/// `AsyncLoading` 영구 잔류를 회피한다. 직접 stream 소비 consumer (Account
/// 섹션, debug widget) 의 spinner 무한 회피가 본 정책의 핵심.
///
/// **Phase 13 R10-FOLLOWUP-2 race fix (본 함수 재작성, async\* generator):**
/// sign-in 직후 Firebase Auth ID Token 갱신과 Firestore SDK 의 token cache
/// propagate 사이의 짧은 timing window 에서 첫 snapshots subscription 이
/// `[cloud_firestore/permission-denied]` 를 받는 race 를 stream 자체에서
/// 흡수한다. `permission-denied` 만 선택적으로 1s × 5회 retry (총 5s envelope),
/// 다른 FirebaseException 은 기존 D-41 정책대로 즉시 빈 배열 fallback.
/// retry 중에는 yield 안 함 → consumer ([currentUserProvider]) 의 R13 fix
/// (linkedAsync.when AsyncLoading 분기 cached value 보존) 가 직전 emit 을
/// UI 에 유지. 5회 escape 시에도 빈 배열 emit (영구 spinner 회피, escape hatch).
///
/// **Invariants (spec §4.6):**
/// - I1 (D-41 보존): 다른 FirebaseException 즉시 빈 배열 + 5회 escape 도 빈
///   배열. 영구 spinner / 영구 "-" 회피.
/// - I2 (R13 호환): permission-denied retry 중 yield 안 함 → consumer 의
///   AsyncLoading 분기 유지 → cached value 노출.
/// - I3 (카운터 리셋): 정상 emit 도달 시 retry 카운터 0 — 장기 세션에서
///   token 재만료 시 다시 retry 가능.
/// - I4 (Type-safe parsing): 기존 [Iterable.whereType] 필터로 invalid entry
///   를 자동 제거 (T-12-06-05).
///
/// `kDebugMode` 에서는 retry / 에러 로그를 출력한다 — release 빌드는 silent.
///
/// **참고:** Firestore SDK 자체의 token cache 자동 재구독 미동작은 known bug
/// (firebase-android-sdk #5101, flutterfire #11146). 본 fix 는 client-side
/// workaround. spec: `docs/superpowers/specs/2026-05-08-r10-followup-2-design.md`.
@Riverpod(keepAlive: true)
Stream<List<String>> linkedProvidersStream(Ref ref, String uid) async* {
  final firestore = ref.watch(firebaseFirestoreProvider);
  var permissionDeniedRetries = 0;
  const maxRetries = 5;
  const retryDelay = Duration(seconds: 1);

  while (true) {
    try {
      await for (final snap
          in firestore.collection('users').doc(uid).snapshots()) {
        // I3: 정상 emit 도달 시 카운터 리셋 — 장기 세션 token 재만료 시
        // 다시 retry 가능.
        permissionDeniedRetries = 0;
        if (!snap.exists) {
          yield const <String>[];
          continue;
        }
        final raw = snap.data()?['linkedProviders'] as List<dynamic>?;
        if (raw == null) {
          yield const <String>[];
          continue;
        }
        // I4: Type-safe parsing — invalid entry 자동 제거.
        yield raw
            .whereType<Map<String, dynamic>>()
            .map((m) => m['providerId'] as String?)
            .whereType<String>()
            .toList(growable: false);
      }
      // source stream 정상 종료 (provider dispose 등) — loop 탈출.
      break;
    } on FirebaseException catch (e, st) {
      if (e.code == 'permission-denied' &&
          permissionDeniedRetries < maxRetries) {
        // R10-FOLLOWUP-2: sign-in 직후 SDK token cache propagate race.
        // I2 — yield 안 함 → consumer 의 AsyncLoading 분기 유지 → cached
        // value 보존. 1s 후 source stream 재구독.
        permissionDeniedRetries += 1;
        if (kDebugMode) {
          debugPrint(
            'linkedProvidersStream permission-denied retry '
            '$permissionDeniedRetries/$maxRetries: $e',
          );
        }
        await Future<void>.delayed(retryDelay);
        continue;
      }
      // I1 (D-41 보존):
      // (1) 다른 FirebaseException (network / unavailable 등) — 즉시 빈 배열.
      // (2) permission-denied 5회 escape — 영구 spinner 회피 escape hatch.
      if (kDebugMode) {
        debugPrint('linkedProvidersStream 에러 (fallback empty): $e\n$st');
      }
      yield const <String>[];
      break;
    }
  }
}
