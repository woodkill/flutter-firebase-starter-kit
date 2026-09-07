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

import '../../../core/auth/provider_id.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/error/result.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../onboarding/presentation/onboarding_notifier.dart';
// Phase 16 G-16-A9-1: authRepository factory provider 의 콜백 주입 전용 import.
// AuthRepository 클래스 본체는 본 타입을 참조하지 않는다 (D-A2 관례).
import '../../terms/presentation/terms_notifier.dart';
import '../application/social_link_in_progress.dart';
import '../domain/user.dart';
import 'kakao_sdk_client.dart';
import 'line_sdk_client.dart';
import 'naver_sdk_client.dart';
import 'yahoojp_sdk_client.dart';

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
  ///
  /// [_lineSdkClient] 는 Phase 14 LINE 로그인 (Custom Token 방식) 을 위해
  /// 추가됐다 — flutter_line_sdk wrapper. Cloud Function 채널
  /// (`lineCustomToken`) 은 [_functions] 를 재사용한다.
  ///
  /// [_yahoojpSdkClient] 는 Phase 15 Yahoo!JP 로그인 (Custom Token 방식) 을
  /// 위해 추가됐다 — flutter_appauth wrapper. Cloud Function 채널
  /// (`yahoojpCustomToken`) 은 [_functions] 를 재사용한다.
  ///
  /// [_onResetOnboarding] 은 로그아웃 시 onboarding 완료 플래그를 false 로
  /// 되돌리는 콜백이다 (Phase 10.2 D-A2). OnboardingNotifier 타입을 직접
  /// 참조하지 않아 Feature-First 결합도를 최소화한다 — `OnboardingNotifier`
  /// import 는 본 클래스 본체가 아닌 [authRepository] factory provider 영역
  /// 한정. 콜백 signature `Future<void> Function()` 만 의존하므로
  /// `Notifier` 구현 교체에도 본 클래스 변경 0건.
  ///
  /// [readTermsAcceptanceSnapshot] 은 device-local 약관 동의를 Custom Token
  /// callable payload 용 JSON 으로 읽는 콜백이다 (Phase 16 G-16-A9-1).
  /// `_onResetOnboarding` 과 동일한 D-A2 논리로 `TermsNotifier` 타입은 본
  /// 클래스 본체가 아닌 [authRepository] factory provider 영역 한정이며,
  /// 본체는 `Map<String, dynamic>? Function()` signature 만 의존한다.
  /// 반환 map 의 키 집합은 서버 계약
  /// `functions/src/shared/terms_acceptance_json.ts` 의
  /// `TermsAcceptanceJson` 5 키 (version / service / privacy / marketing /
  /// acceptedAt) 와 정확히 일치해야 한다 (D-13 / D-14 anchor). 미주입 시
  /// 기본값은 항상 null 을 반환하는 [_readNoTermsAcceptanceSnapshot] 이며,
  /// 이때 payload 는 기존과 100% 동일하다 (add-only, 회귀 0).
  AuthRepository(
    this._auth,
    this._googleSignIn,
    this._facebookAuth,
    this._socialLinkInProgress,
    this._kakaoSdkClient,
    this._functions,
    this._naverSdkClient,
    this._lineSdkClient,
    this._yahoojpSdkClient,
    this._onResetOnboarding, {
    DateTime Function()? now,
    Map<String, dynamic>? Function()? readTermsAcceptanceSnapshot,
  }) : _now = now ?? DateTime.now,
       _readTermsAcceptanceSnapshot =
           readTermsAcceptanceSnapshot ?? _readNoTermsAcceptanceSnapshot;

  final fb.FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;
  final FacebookAuth _facebookAuth;
  final SocialLinkInProgress _socialLinkInProgress;
  final KakaoSdkClient _kakaoSdkClient;
  final FirebaseFunctions _functions;
  final NaverSdkClient _naverSdkClient;
  final LineSdkClient _lineSdkClient;
  final YahoojpSdkClient _yahoojpSdkClient;
  final Future<void> Function() _onResetOnboarding;

  /// device-local 약관 동의 snapshot 을 서버 계약 JSON 으로 읽는 콜백
  /// (Phase 16 G-16-A9-1). 동의 부재 시 null.
  final Map<String, dynamic>? Function() _readTermsAcceptanceSnapshot;

  /// Phase 16 D-12 / Pitfall 5 — client-side cache for `lookupSignInMethods`
  /// callable responses. 동일 collisionEmail 의 rate limit 누적 회피
  /// (Cloud Function 10/min/UID 한도 보호) 및 사용자 retry path 의
  /// 응답 latency 최소화.
  ///
  /// **TTL 5 분:** D-10 의 enumeration alarm threshold (UID 별 5 회/min) 와
  /// 일관 — 동일 캐시 entry 가 5 분 후 invalidate 되면 server 측 행동
  /// 분석은 짧은 window 만 본다.
  ///
  /// Map value 는 `AccountProvider?` (null 허용) — callable 가 unknown 응답
  /// (또는 fail) 시 unknown fallback 도 cache 하여 같은 이메일 재시도 시
  /// 다시 호출되는 비용 회피.
  final Map<String, _CachedProvider> _accountExistsCache = {};

  /// TTL 5 분 — D-10 enumeration alarm window 와 일관.
  static const Duration _kAccountExistsCacheTtl = Duration(minutes: 5);

  /// WR-05 — `_accountExistsCache` 최대 entry 수 (unbounded Map 성장 차단).
  ///
  /// keepAlive [AuthRepository] 에서 서로 다른 collisionEmail 충돌이 반복되면
  /// plaintext email key 가 무한 누적되어 PII 가 TTL 보다 오래 메모리에
  /// 잔류한다. 새 entry 삽입 시 본 한도를 초과하면 가장 오래된(삽입 순서)
  /// entry 를 evict 하여 메모리·잔류 시간을 bound 한다.
  static const int _kAccountExistsCacheMaxEntries = 64;

  /// `lookupSignInMethods` callable 호출 타임아웃 — 5 초.
  static const Duration _kLookupTimeout = Duration(seconds: 5);

  /// 단위 테스트 결정성 보장을 위한 시간 주입 hook.
  final DateTime Function() _now;

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
      // Phase 16 D-12 wiring — account-exists 시 provider enrichment.
      return Result.failure(await _enrichAccountExistsAsync(_mapAuthException(e)));
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
      // Phase 16 D-12 wiring — account-exists 시 provider enrichment.
      return Result.failure(await _enrichAccountExistsAsync(_mapAuthException(e)));
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
      // Gap A close (HUMAN-UAT 2026-05-11): success path 합류 후 익명 분기 정보
      // 보존. helper 의 isLinkedFromAnonymous 명시 인자로 D-20 우회.
      // Phase 17 (Account Linking) — see ROADMAP.md.
      final isLinkedFromAnonymous = anonymous != null && anonymous.isAnonymous;
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
      // Gap A close (HUMAN-UAT 2026-05-11): linkWithCredential 분기의
      // isNewUser=false 사양 보강.
      await _autoSendEmailVerification(
        userCredential,
        isLinkedFromAnonymous: isLinkedFromAnonymous,
      );
      return Result.success(_mapFirebaseUser(fbUser));
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return null;
      }
      return Result.failure(_mapGoogleException(e));
    } on fb.FirebaseAuthException catch (e) {
      // Phase 16 D-12 wiring — account-exists 시 provider enrichment.
      return Result.failure(await _enrichAccountExistsAsync(_mapAuthException(e)));
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
      // Gap A close (HUMAN-UAT 2026-05-11): success path 합류 후 익명 분기 정보
      // 보존. helper 의 isLinkedFromAnonymous 명시 인자로 D-20 우회.
      // Phase 17 (Account Linking) — see ROADMAP.md.
      final isLinkedFromAnonymous = anonymous != null && anonymous.isAnonymous;
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
      // Gap A close (HUMAN-UAT 2026-05-11): linkWithProvider 분기의
      // isNewUser=false 사양 보강.
      await _autoSendEmailVerification(
        userCredential,
        isLinkedFromAnonymous: isLinkedFromAnonymous,
      );
      return Result.success(_mapFirebaseUser(fbUser));
    } on fb.FirebaseAuthException catch (e) {
      // D-09: 사용자 취소 시 null 반환.
      if (e.code == 'canceled' ||
          e.code == 'web-context-canceled' ||
          e.code == 'web-context-cancelled' ||
          e.code == 'popup-closed-by-user') {
        return null;
      }
      // Phase 16 D-12 wiring — account-exists 시 provider enrichment.
      return Result.failure(await _enrichAccountExistsAsync(_mapAuthException(e)));
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
      // Gap A close (HUMAN-UAT 2026-05-11): success path 합류 후 익명 분기 정보
      // 보존. helper 의 isLinkedFromAnonymous 명시 인자로 D-20 우회.
      // Phase 17 (Account Linking) — see ROADMAP.md.
      final isLinkedFromAnonymous = anonymous != null && anonymous.isAnonymous;
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
      // Gap A close (HUMAN-UAT 2026-05-11): linkWithCredential 분기의
      // isNewUser=false 사양 보강.
      await _autoSendEmailVerification(
        userCredential,
        isLinkedFromAnonymous: isLinkedFromAnonymous,
      );
      await _setFacebookPhotoUrl(fbUser);
      return Result.success(_mapFirebaseUser(fbUser));
    } on fb.FirebaseAuthException catch (e) {
      // Phase 16 D-12 wiring — account-exists 시 provider enrichment.
      return Result.failure(await _enrichAccountExistsAsync(_mapAuthException(e)));
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('signInWithFacebook 비-Auth 예외: $e\n$st');
      }
      return Result.failure(ServiceUnavailable(cause: e));
    } finally {
      _socialLinkInProgress.end();
    }
  }

  /// 충돌 시점에 보존된 native pending credential 을 실제 계정에 연결한다
  /// (Phase 16 16-08 — native reactive link arm / SOCL-12).
  ///
  /// account-exists 충돌 (`AccountExistsWithDifferentCredential`) 직후
  /// [AccountLinkingSheet] 에서 사용자가 기존-provider 버튼을 탭하면 본
  /// 메서드가 호출된다. 흐름:
  /// 1. [SocialLinkInProgress.begin] (Phase 9.1 D-22 race-fix invariant) —
  ///    try-finally 로 [SocialLinkInProgress.end] 1:1 보장.
  /// 2. [existingProvider] 로 재인증 (native 3값 google/apple/facebook 의
  ///    SDK 호출부 재사용). 사용자 취소 시 `null` 반환 (no-op — linkedProviders
  ///    변경 0, D-03 dismiss 와 동일 시맨틱).
  /// 3. 재인증 성공 후 `_auth.currentUser.linkWithCredential(pendingCredential)`
  ///    으로 두 자격증명을 한 계정에 연결.
  /// 4. `provider-already-linked` / `credential-already-in-use` →
  ///    [AccountAlreadyLinked] 매핑 (회귀 안전). 그 외 FirebaseAuthException
  ///    → [_mapAuthException].
  ///
  /// **email-existing 정책 (scope 명시):** [AccountProvider.email] 은
  /// pendingCredential link 대상이 아니라 "이미 존재하는 비밀번호 계정으로
  /// 로그인" 이므로 reactive link arm 을 적용하지 않는다 — sheet 에서
  /// /login redirect (D-03 cancel 과 동일 복귀) 가 담당하고, 본 메서드는
  /// [ServiceUnavailable] Failure 로 재로그인 유도 신호를 반환한다. native
  /// 실제 link 는 google/apple/facebook 3값 한정. Custom Token 4값
  /// (kakao/naver/line/yahoojp) 은 16-09 책임.
  ///
  /// 반환:
  /// - `Result.success(User)` — link 성공.
  /// - `Result.failure(...)` — link 충돌 / credential 부재 / 재인증 실패.
  /// - `null` — 사용자가 재인증을 취소 (no-op).
  Future<Result<User>?> linkPendingNativeCredential({
    required AccountProvider existingProvider,
    required Object? pendingCredential,
  }) async {
    try {
      _socialLinkInProgress.begin(); // race-fix Pitfall 8 단일 진실원
      // email-existing 은 reactive link arm 미적용 — sheet 가 /login redirect.
      // pendingCredential 부재 (Cloud Function already-exists path 등) 도
      // 재로그인 유도.
      if (existingProvider == AccountProvider.email ||
          pendingCredential == null) {
        return const Result.failure(ServiceUnavailable());
      }

      // Step 1 — 기존 provider 로 재인증해 credential 을 획득한다. 사용자
      // 취소 시 null 신호 그대로 전파 (no-op).
      final reauthCredential = await _reauthNativeCredential(existingProvider);
      if (reauthCredential == null) return null; // 사용자 취소 — no-op.

      // Step 2 — 재인증 성공으로 currentUser 가 존재한다고 가정. pending
      // credential 을 현재 계정에 연결한다.
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        return const Result.failure(ServiceUnavailable());
      }

      final fb.UserCredential linked;
      try {
        linked = await currentUser.linkWithCredential(
          pendingCredential as fb.AuthCredential,
        );
      } on fb.FirebaseAuthException catch (e) {
        // WR-01: proactive arm 과 동일 매핑으로 통일 —
        // `requires-recent-login` → [ReauthenticationRequiredException]
        // (sheet 가 /login 라우팅), `provider-already-linked` /
        // `credential-already-in-use` → [AccountAlreadyLinked], 그 외 →
        // [_mapAuthException]. 기존엔 reauth-expired 가 default fallback
        // (ServiceUnavailable) 으로 흡수되어 sheet 가 mute pop(false) 했다.
        return Result.failure(_mapProactiveLinkException(e));
      }

      final fbUser = linked.user;
      if (fbUser == null) {
        return const Result.failure(ServiceUnavailable());
      }
      return Result.success(_mapFirebaseUser(fbUser));
    } on fb.FirebaseAuthException catch (e) {
      return Result.failure(_mapAuthException(e));
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('linkPendingNativeCredential 비-Auth 예외: $e\n$st');
      }
      return Result.failure(ServiceUnavailable(cause: e));
    } finally {
      _socialLinkInProgress.end();
    }
  }

  /// native [existingProvider] 로 재인증해 [fb.AuthCredential] 을 획득한다
  /// (Phase 16 16-08). 사용자 취소 시 `null` 반환.
  ///
  /// 기존 [signInWithGoogle] / [signInWithApple] / [signInWithFacebook] 의
  /// SDK 호출부를 재사용하되 익명 승격 분기는 타지 않는다 (재인증 컨텍스트는
  /// 정식 사용자 currentUser 가 이미 존재함을 전제). [AccountProvider.email]
  /// 및 Custom Token 4값은 호출처에서 사전 분기되므로 본 helper 에 도달하지
  /// 않는다 — exhaustive switch 의 잔여 case 는 `null` 로 graceful fallback.
  Future<fb.AuthCredential?> _reauthNativeCredential(
    AccountProvider existingProvider,
  ) async {
    switch (existingProvider) {
      case AccountProvider.google:
        try {
          final account = await _googleSignIn.authenticate();
          final authentication = account.authentication;
          return fb.GoogleAuthProvider.credential(
            idToken: authentication.idToken,
          );
        } on GoogleSignInException catch (e) {
          if (e.code == GoogleSignInExceptionCode.canceled) return null;
          rethrow;
        }
      case AccountProvider.apple:
        // Apple 은 provider 기반 재인증 — reauthenticateWithProvider 가
        // UserCredential.credential 을 반환한다.
        final provider = fb.AppleAuthProvider()
          ..addScope('email')
          ..addScope('name');
        final currentUser = _auth.currentUser;
        if (currentUser == null) return null;
        final reauthResult = await currentUser.reauthenticateWithProvider(
          provider,
        );
        return reauthResult.credential;
      case AccountProvider.facebook:
        final loginResult = await _facebookAuth.login(
          permissions: ['email', 'public_profile'],
          loginTracking: LoginTracking.enabled,
        );
        if (loginResult.status != LoginStatus.success) return null;
        final accessToken = loginResult.accessToken;
        if (accessToken == null) return null;
        return fb.FacebookAuthProvider.credential(accessToken.tokenString);
      case AccountProvider.email:
      case AccountProvider.kakao:
      case AccountProvider.naver:
      case AccountProvider.line:
      case AccountProvider.yahoojp:
        // 호출처에서 사전 분기 — 도달하지 않음 (graceful null).
        return null;
    }
  }

  /// 로그인된 사용자에게 Google 계정을 proactive 하게 연결한다
  /// (Phase 16 16-10 — proactive native link arm / SOCL-12 / UAT A6).
  ///
  /// Settings "계정 연결" 섹션 (Surface D) 에서 사용자가 Google 버튼을 탭하면
  /// 호출된다 — account-exists 충돌 없이 logged-in user 가 직접 provider 를
  /// 추가하는 흐름. 익명 승격 분기는 타지 않으며 (currentUser 가 이미 정식
  /// user 전제), Cloud Functions callable 을 호출하지 않는다 (native — UAT A6
  /// invariant).
  ///
  /// 흐름:
  /// 1. [SocialLinkInProgress.begin] (Phase 9.1 D-22 race-fix invariant) —
  ///    try-finally 로 [SocialLinkInProgress.end] 1:1 보장.
  /// 2. [GoogleSignIn.authenticate] 로 fresh Google credential 획득. 사용자
  ///    취소 ([GoogleSignInExceptionCode.canceled]) 시 `null` 반환 (no-op —
  ///    linkedProviders 변경 0).
  /// 3. `_auth.currentUser.linkWithCredential(googleCredential)`.
  /// 4. 에러 매핑 ([_mapProactiveLinkException]): `requires-recent-login` →
  ///    [ReauthenticationRequiredException] (5분 auth_time boundary — withdrawal
  ///    D-06 reauth gate mirror), `provider-already-linked` /
  ///    `credential-already-in-use` → [AccountAlreadyLinked], 그 외 →
  ///    [_mapAuthException].
  ///
  /// 반환: `Result.success(User)` — link 성공 / `Result.failure(...)` — 충돌·
  /// 재인증 필요 / `null` — 사용자 취소 (no-op).
  Future<Result<User>?> linkGoogleCredential() {
    return _runProactiveNativeLink(() async {
      final fb.AuthCredential credential;
      try {
        final account = await _googleSignIn.authenticate();
        final authentication = account.authentication;
        credential = fb.GoogleAuthProvider.credential(
          idToken: authentication.idToken,
        );
      } on GoogleSignInException catch (e) {
        if (e.code == GoogleSignInExceptionCode.canceled) return null;
        rethrow;
      }
      final currentUser = _auth.currentUser;
      if (currentUser == null) return null;
      return currentUser.linkWithCredential(credential);
    });
  }

  /// 로그인된 사용자에게 Apple 계정을 proactive 하게 연결한다
  /// (Phase 16 16-10 — proactive native link arm / SOCL-12 / UAT A6).
  ///
  /// Apple 은 provider 기반 — `_auth.currentUser.linkWithProvider(AppleAuthProvider)`
  /// 로 OAuth 플로우(iOS ASAuthorizationController / Android Custom Tab) 를
  /// Firebase 가 내부 처리한다. 사용자 취소 (`canceled` 등) 시 `null` 반환.
  /// 에러 매핑은 [linkGoogleCredential] 과 동일 ([_mapProactiveLinkException]).
  ///
  /// 흐름 / 반환 시맨틱은 [linkGoogleCredential] 참조 (native — callable 미호출).
  Future<Result<User>?> linkAppleCredential() {
    return _runProactiveNativeLink(() async {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return null;
      final provider = fb.AppleAuthProvider()
        ..addScope('email')
        ..addScope('name');
      return currentUser.linkWithProvider(provider);
    });
  }

  /// 로그인된 사용자에게 Facebook 계정을 proactive 하게 연결한다
  /// (Phase 16 16-10 — proactive native link arm / SOCL-12 / UAT A6).
  ///
  /// [FacebookAuth.login] (email + public_profile) 로 fresh credential 획득 후
  /// `_auth.currentUser.linkWithCredential(facebookCredential)`. 사용자 취소
  /// (status != success) 또는 accessToken null 시 `null` 반환 (no-op).
  ///
  /// 흐름 / 반환 시맨틱은 [linkGoogleCredential] 참조 (native — callable 미호출).
  Future<Result<User>?> linkFacebookCredential() {
    return _runProactiveNativeLink(() async {
      final loginResult = await _facebookAuth.login(
        permissions: ['email', 'public_profile'],
        loginTracking: LoginTracking.enabled,
      );
      if (loginResult.status != LoginStatus.success) return null;
      final accessToken = loginResult.accessToken;
      if (accessToken == null) return null;
      final credential = fb.FacebookAuthProvider.credential(
        accessToken.tokenString,
      );
      final currentUser = _auth.currentUser;
      if (currentUser == null) return null;
      return currentUser.linkWithCredential(credential);
    });
  }

  /// 로그인된 사용자에게 이메일/비밀번호 자격증명을 연결한다
  /// (Phase 16 16-10 — native link 메서드 / SOCL-12).
  ///
  /// **의도적 latent / extensibility API — Surface D 기본 UI 에 미연결
  /// (16-11 결정, 2026-06-02 — keep-as-documented).** email(이메일/비밀번호) 은
  /// Surface D proactive "계정 연결" 목록에서 **제외**된다 (mockup §0 사용자
  /// 시각 sign-off — email EXCLUDE). 본 메서드는 starter-kit 의 email-credential
  /// linking **확장점** 으로 제공되며, 기본 동작에서는 의도적으로 어떤 UI 에도
  /// wire 되지 않는다:
  /// - **proactive (Settings Surface D):** call site 0 — email 후보 미포함.
  /// - **reactive (16-08 충돌 arm):** generic `linkPendingNativeCredential`
  ///   (pendingCredential 직접 link) 를 사용하므로 본 메서드 미경유.
  ///
  /// email/password proactive 연결이 필요한 프로젝트는 (1) 16-11
  /// `_kProactiveLinkCandidates` 에 [AccountProvider.email] 을 추가하고,
  /// (2) 별도 password 입력 다이얼로그를 신설한 뒤, (3) 본 메서드를 그
  /// affordance 에 wire 하면 된다 (mockup §0 EXCLUDE 결정 역전 — starter-kit
  /// 기본은 소셜만). 본 메서드를 dead code 로 제거하지 않는 이유는 위
  /// 확장 경로의 진입 비용을 낮추기 위함이다 (16-11 deferred-items RESOLVED).
  ///
  /// [fb.EmailAuthProvider.credential] 생성 후
  /// `_auth.currentUser.linkWithCredential(emailCredential)`. 에러 매핑은
  /// [linkGoogleCredential] 과 동일 ([_mapProactiveLinkException]).
  Future<Result<User>?> linkEmailCredential({
    required String email,
    required String password,
  }) {
    return _runProactiveNativeLink(() async {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return null;
      final credential = fb.EmailAuthProvider.credential(
        email: email,
        password: password,
      );
      return currentUser.linkWithCredential(credential);
    });
  }

  /// proactive native link 4 메서드의 공통 실행 래퍼 (Phase 16 16-10).
  ///
  /// [linkAction] 은 provider 별 fresh credential 획득 + link 호출을 수행하고
  /// [fb.UserCredential] 을 반환한다. 사용자 취소 시 `null` 을 반환하면 본
  /// 래퍼가 `null` (no-op) 로 전파한다. 공통 책임:
  /// 1. [SocialLinkInProgress.begin] + try-finally [SocialLinkInProgress.end]
  ///    1:1 (Phase 9.1 D-22 race-fix invariant).
  /// 2. [linkAction] 이 던지는 [fb.FirebaseAuthException] →
  ///    [_mapProactiveLinkException] (reauth gate / already-linked / 표준 매핑).
  /// 3. Apple OAuth 사용자 취소 코드 (`canceled` 등) → `null` (no-op).
  /// 4. 비-Auth 예외 → [ServiceUnavailable] (Notifier AsyncLoading 고정 방지).
  Future<Result<User>?> _runProactiveNativeLink(
    Future<fb.UserCredential?> Function() linkAction,
  ) async {
    try {
      _socialLinkInProgress.begin(); // race-fix Pitfall 8 단일 진실원
      final linked = await linkAction();
      if (linked == null) return null; // 사용자 취소 — no-op.
      final fbUser = linked.user;
      if (fbUser == null) {
        return const Result.failure(ServiceUnavailable());
      }
      return Result.success(_mapFirebaseUser(fbUser));
    } on fb.FirebaseAuthException catch (e) {
      // Apple/OAuth 사용자 취소 → null (no-op, signInWithApple cancel 코드 mirror).
      if (e.code == 'canceled' ||
          e.code == 'web-context-canceled' ||
          e.code == 'web-context-cancelled' ||
          e.code == 'popup-closed-by-user') {
        return null;
      }
      return Result.failure(_mapProactiveLinkException(e));
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('proactive native link 비-Auth 예외: $e\n$st');
      }
      return Result.failure(ServiceUnavailable(cause: e));
    } finally {
      _socialLinkInProgress.end();
    }
  }

  /// proactive native link 의 [fb.FirebaseAuthException] → [AppException] 매핑
  /// (Phase 16 16-10).
  ///
  /// - `requires-recent-login` → [ReauthenticationRequiredException] (5분
  ///   auth_time boundary 초과 — withdrawal D-06 reauth gate mirror. 16-11 UI
  ///   가 재로그인 라우팅. threat T-16-10-01 mitigate).
  /// - `provider-already-linked` / `credential-already-in-use` →
  ///   [AccountAlreadyLinked] (회귀 안전 ARB 재사용. threat T-16-10-02 mitigate).
  /// - 그 외 → [_mapAuthException] (기존 표준 매핑 재사용).
  AppException _mapProactiveLinkException(fb.FirebaseAuthException e) {
    return switch (e.code) {
      'requires-recent-login' => ReauthenticationRequiredException(cause: e),
      'provider-already-linked' ||
      'credential-already-in-use' => AccountAlreadyLinked(cause: e),
      _ => _mapAuthException(e),
    };
  }

  /// Custom Token provider (Kakao/LINE/YJP) reactive link arm (Phase 16 16-09).
  ///
  /// Custom Token 계정 충돌 (account-exists) 직후 [AccountLinkingSheet] 에서
  /// 사용자가 기존-provider 버튼을 탭하면 본 메서드가 호출된다. 흐름
  /// (RESEARCH § reactive Custom Token data flow + Pattern 2):
  /// 1. [SocialLinkInProgress.begin] (Phase 9.1 D-22 race-fix invariant) —
  ///    try-finally 로 [SocialLinkInProgress.end] 1:1 보장.
  /// 2. [targetProvider] 별 SDK signIn 으로 **target OIDC 토큰 fresh 재획득**
  ///    (kakao→[KakaoSdkClient.signIn], line→[LineSdkClient.signIn],
  ///    yahoojp→[YahoojpSdkClient.signIn]). 사용자 취소 (null) 시 `null` 반환
  ///    (silent — linkedProviders 변경 0).
  /// 3. `_auth.currentUser.getIdToken(true /* forceRefresh */)` 로 caller
  ///    fresh ID Token 발급 (server-side auth_time 5분 boundary 통과 의무).
  /// 4. `_functions.httpsCallable('linkCustomTokenProvider')` 호출 —
  ///    deployed contract `{idToken, targetProvider, targetProviderToken,
  ///    nonce} → {ok:true}` (link_custom_token_provider.ts line 67~80 verbatim).
  /// 5. `{ok:true}` 검증 후 `_auth.currentUser` reload → [_mapFirebaseUser].
  /// 6. finally 에서 target SDK logout (1회성 토큰 정책 —
  ///    [signInWithKakao]/[signInWithLine] 의 finally logout mirror) +
  ///    [SocialLinkInProgress.end].
  ///
  /// **토큰 재획득 결정 (RESEARCH 검증, data flow step 6 인용):** 원본 collided
  /// 로그인 시도의 target 토큰은 SDK 1회성 정책 (finally logout) 으로 이미
  /// 소비/만료되었고 nonce 도 단일 사용이므로 안전 재사용 불가다. 따라서 sheet
  /// 버튼 탭 시점에 fresh 재획득한다 (RESEARCH line 333~341 의 "user taps Kakao
  /// button → Kakao SDK" 가 fresh 재획득을 전제). proactive arm 과 동일
  /// mechanism.
  ///
  /// **targetProvider 제약:** kakao/line/yahoojp 만 허용한다 (naver/native 는
  /// deployed callable OIDC 미지원 — link_custom_token_provider.ts line 27~33
  /// verbatim, Naver-as-target reactive link 는 Phase 17+ carry-forward).
  /// 그 외 입력은 [ArgumentError] throw.
  ///
  /// 에러 매핑 (deployed callable HttpsError code):
  /// - `unauthenticated` / `permission-denied` →
  ///   [ReauthenticationRequiredException] (auth_time 초과 / verifyIdToken 실패
  ///   → 재로그인 유도).
  /// - `already-exists` → [AccountAlreadyLinked] (identity_index 이미 존재).
  /// - 그 외 (`failed-precondition` 익명 caller / `invalid-argument` 등) →
  ///   [_mapFunctionsException] (적절 [AppException]).
  ///
  /// **PII invariant (T-16-09-02 / T-16-NEW-07):** catch path 의 [debugPrint]
  /// 는 code/runtimeType 만 출력하고 idToken / targetProviderToken /
  /// collisionEmail 본문은 절대 포함하지 않는다.
  ///
  /// 반환:
  /// - `Result.success(User)` — link 성공.
  /// - `Result.failure(...)` — callable 거부 / reauth 초과 / 이미 link 됨.
  /// - `null` — target SDK signIn 사용자 취소 (no-op).
  Future<Result<User>?> linkCustomTokenProviderArm({
    required AccountProvider targetProvider,
  }) async {
    // deployed callable 미지원 target 사전 차단 (kakao/line/yahoojp 만 허용).
    if (targetProvider != AccountProvider.kakao &&
        targetProvider != AccountProvider.line &&
        targetProvider != AccountProvider.yahoojp) {
      throw ArgumentError.value(
        targetProvider,
        'targetProvider',
        'linkCustomTokenProvider 는 kakao/line/yahoojp 만 지원 '
            '(naver/native deployed callable OIDC 미지원 — Phase 17+).',
      );
    }
    try {
      _socialLinkInProgress.begin(); // race-fix Pitfall 8 단일 진실원

      // Step 2 — target OIDC 토큰 fresh 재획득 (1회성 정책). 사용자 취소 시
      // null silent return.
      final targetToken = await _acquireTargetProviderToken(targetProvider);
      if (targetToken == null) return null; // 사용자 취소 — no-op.

      // Step 3 — caller fresh ID Token (forceRefresh=true) — server-side
      // auth_time 5분 boundary 통과 의무.
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        return const Result.failure(ServiceUnavailable());
      }
      // WR-06: client-side 익명 caller 가드 (defense-in-depth). reactive
      // collision arm 의 caller 는 구조상 fresh collided sign-in 이므로
      // 익명일 수 없다 — 익명 도달은 upstream 로직 오류 신호다. 서버
      // `failed-precondition` 거부에만 의존하지 않고 client 에서 loud
      // fail 하여 불필요한 callable round-trip 을 회피한다 (proactive arm /
      // deployed callable 익명 차단 mirror).
      if (currentUser.isAnonymous) {
        return const Result.failure(ServiceUnavailable());
      }
      final callerIdToken = await currentUser.getIdToken(true);
      if (callerIdToken == null) {
        return const Result.failure(ServiceUnavailable());
      }

      // Step 4 — deployed linkCustomTokenProvider callable 호출.
      final callable = _functions.httpsCallable(
        'linkCustomTokenProvider',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 10)),
      );
      final response = await callable.call<Map<String, dynamic>>(
        <String, dynamic>{
          'idToken': callerIdToken,
          'targetProvider': targetProvider.slug,
          'targetProviderToken': targetToken.idToken,
          'nonce': targetToken.nonce,
        },
      );

      // Step 5 — {ok:true} 검증 후 reload → 도메인 User.
      final ok = response.data['ok'] == true;
      if (!ok) {
        return const Result.failure(ServiceUnavailable());
      }
      await currentUser.reload();
      final refreshed = _auth.currentUser ?? currentUser;
      return Result.success(_mapFirebaseUser(refreshed));
    } on FirebaseFunctionsException catch (e) {
      // deployed contract — unauthenticated/permission-denied → 재로그인 유도.
      if (e.code == 'unauthenticated' || e.code == 'permission-denied') {
        return Result.failure(ReauthenticationRequiredException(cause: e));
      }
      // already-exists → 이미 link 된 identity (회귀 안전 ARB 재사용).
      if (e.code == 'already-exists') {
        return Result.failure(AccountAlreadyLinked(cause: e));
      }
      // failed-precondition (익명 caller) / invalid-argument 등 → 표준 매핑.
      return Result.failure(_mapFunctionsException(e));
    } on fb.FirebaseAuthException catch (e) {
      return Result.failure(_mapAuthException(e));
    } on ServiceUnavailable catch (e) {
      // target SDK 가 OIDC scope 누락 등으로 ServiceUnavailable throw — Kakao/
      // LINE/YJP signIn 과 동일 시맨틱 (Pitfall 1).
      return Result.failure(e);
    } on Object catch (e) {
      // PII invariant (T-16-09-02): code/runtimeType 만 — 토큰/email 본문 비포함.
      if (kDebugMode) {
        debugPrint(
          'linkCustomTokenProviderArm 비-Functions 예외: '
          'runtimeType=${e.runtimeType}',
        );
      }
      return Result.failure(ServiceUnavailable(cause: e));
    } finally {
      // 1회성 토큰 정책 (signInWithKakao/Line/Yahoojp finally logout mirror) —
      // Pitfall 2 race-fix end 직전 위치.
      await _logoutTargetProvider(targetProvider);
      _socialLinkInProgress.end();
    }
  }

  /// [targetProvider] 별 SDK signIn 으로 target OIDC 토큰을 fresh 재획득한다
  /// (Phase 16 16-09). 사용자 취소 시 `null` 반환.
  ///
  /// 반환 [_TargetProviderToken] 은 `{idToken, nonce}` 묶음 — 4 Custom Token
  /// SDK 의 result 타입을 단일 인터페이스로 normalize 한다.
  Future<_TargetProviderToken?> _acquireTargetProviderToken(
    AccountProvider targetProvider,
  ) async {
    switch (targetProvider) {
      case AccountProvider.kakao:
        final result = await _kakaoSdkClient.signIn();
        if (result == null) return null;
        return _TargetProviderToken(result.idToken, result.nonce);
      case AccountProvider.line:
        final result = await _lineSdkClient.signIn();
        if (result == null) return null;
        return _TargetProviderToken(result.idToken, result.nonce);
      case AccountProvider.yahoojp:
        final result = await _yahoojpSdkClient.signIn();
        if (result == null) return null;
        return _TargetProviderToken(result.idToken, result.nonce);
      case AccountProvider.google:
      case AccountProvider.apple:
      case AccountProvider.facebook:
      case AccountProvider.email:
      case AccountProvider.naver:
        // 호출처에서 사전 차단 (ArgumentError) — 도달하지 않음 (graceful null).
        return null;
    }
  }

  /// [targetProvider] SDK logout — 1회성 토큰 정책 (Phase 16 16-09).
  ///
  /// [linkCustomTokenProviderArm] 의 finally 블록에서 호출한다. 각 SDK 의
  /// logout 은 내부 try/catch graceful 이므로 "no session" 상태에서도 silent.
  Future<void> _logoutTargetProvider(AccountProvider targetProvider) async {
    switch (targetProvider) {
      case AccountProvider.kakao:
        await _kakaoSdkClient.logout();
      case AccountProvider.line:
        await _lineSdkClient.logout();
      case AccountProvider.yahoojp:
        await _yahoojpSdkClient.logout();
      case AccountProvider.google:
      case AccountProvider.apple:
      case AccountProvider.facebook:
      case AccountProvider.email:
      case AccountProvider.naver:
        // 호출처에서 사전 차단 — 도달하지 않음.
        break;
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
      // G-16-A9-1 / D-13: device-local 약관 동의를 add-only 로 동봉해 서버가
      // identity 생성과 같은 write 안에서 termsAccepted 를 mirror 하게 한다.
      final response = await callable.call<Map<String, dynamic>>(
        _buildCustomTokenPayload(<String, dynamic>{
          'idToken': result.idToken,
          'nonce': result.nonce,
        }),
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
      // G-16-A9-1 / D-13: device-local 약관 동의를 add-only 로 동봉한다.
      // base 키가 accessToken 단일인 것은 provider 계약 차이이며 snapshot
      // 부착 방식은 4 provider 동일하다.
      final response = await callable.call<Map<String, dynamic>>(
        _buildCustomTokenPayload(<String, dynamic>{
          'accessToken': result.accessToken,
        }),
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
    } on ServiceUnavailable catch (e) {
      // IN-01: signInWithKakao 와 대칭 — NaverSdkClient 가 OAuth misconfig /
      // SDK 내부 ServiceUnavailable throw 시 원본 ServiceUnavailable 을
      // cause chain 으로 wrapping 하지 않고 그대로 보존. 현재 NaverSdkClient
      // 는 null 반환 + Object catch 경로 위주이지만 미래 wrapper 변경 시
      // 대비 + provider 간 audit 일관성.
      return Result.failure(e);
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

  /// LINE 계정으로 Firebase Auth 에 로그인한다 (Phase 14, SOCL-03).
  ///
  /// **Custom Token 방식** — Phase 12 Kakao 와 동일 흐름. 차이:
  /// (1) SDK = flutter_line_sdk ([LineSdkClient] wrapper)
  /// (2) Cloud Function 페이로드 = `{idToken, nonce}` (LINE OIDC — Kakao 와 동일)
  /// (3) LINE 검증 = Cloud Function 측 jose verification + nonce SHA256 비교
  ///     (Plan 14-04 helper nonceHashing — A1 emulator 검증 의무)
  /// (4) finally 에서 SDK logout (D-LINE-57 — 1회성 access_token)
  ///
  /// 흐름:
  /// 1. [SocialLinkInProgress.begin] (race-fix Pitfall 8 — 단일 진실원)
  /// 2. [_lineSdkClient.signIn] — null 반환 (사용자 취소) → null silent
  /// 3. `_functions.httpsCallable('lineCustomToken')({idToken, nonce})` →
  ///    Cloud Function 이 jose 검증 + nonce hash 비교 + Identity Index lookup +
  ///    `createCustomToken` (Plan 14-04)
  /// 4. [fb.FirebaseAuth.signInWithCustomToken] → Firebase Auth 세션 시작
  /// 5. [_mapFirebaseUser] → 도메인 [User]
  /// 6. finally: [_lineSdkClient.logout] (D-LINE-57 — Pitfall 2 race-fix end
  ///    직전 위치) + [SocialLinkInProgress.end]
  ///
  /// 에러 매핑 (Phase 12 D-30 / D-34 helper 재사용 — Kakao path 와 100% 대칭):
  /// - [LineSdkClient.signIn] 가 null 반환 (사용자 취소 silent — D-LINE-21) → null.
  /// - [FirebaseFunctionsException] → [_mapFunctionsException]
  ///   (`already-exists` 분기는 Phase 12.1 D-34 에서
  ///   [AccountExistsWithDifferentCredential] 자동 흡수)
  /// - [fb.FirebaseAuthException] → [_mapAuthException]
  /// - [ServiceUnavailable] (LineSdkClient 가 OIDC scope 누락 — Pitfall 1) →
  ///   그대로 Failure 재패키징
  /// - 그 외 → [ServiceUnavailable(cause: e)] + [kDebugMode] [debugPrint]
  ///
  /// **race-fix invariant (Phase 9.1 D-03 / Pitfall 8):** body 전체 try-finally
  /// 로 감싸 진입 직후 [SocialLinkInProgress.begin] / 종료 시
  /// [SocialLinkInProgress.end] 호출. Strategy 단계 추가 호출 절대 금지.
  ///
  /// **D-LINE-57 1회성 토큰 정책 (Phase 13 WR-01-iter2 일관):** 모든 path 에서
  /// finally logout — 성공 / cancel / error / timeout 모두 일관. SDK
  /// "no session" 상태는 [LineSdkClient.logout] 내부 try/catch 가 silent 흡수.
  ///
  /// Returns null = 사용자 취소 silent.
  Future<Result<User>?> signInWithLine() async {
    try {
      _socialLinkInProgress.begin(); // race-fix Pitfall 8 단일 진실원

      final result = await _lineSdkClient.signIn();
      if (result == null) {
        return null; // D-LINE-21 silent cancel
      }

      final callable = _functions.httpsCallable('lineCustomToken');
      // G-16-A9-1 / D-13: device-local 약관 동의를 add-only 로 동봉해 서버가
      // identity 생성과 같은 write 안에서 termsAccepted 를 mirror 하게 한다.
      final response = await callable.call<Map<String, dynamic>>(
        _buildCustomTokenPayload(<String, dynamic>{
          'idToken': result.idToken,
          'nonce': result.nonce,
        }),
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
      // (Phase 9.2 R4) 자동 sendEmailVerification — IN-01 (Phase 14 review)
      // 정정: LINE 은 D-LINE-21 (email scope 미채택) 으로 Firebase Auth user
      // record 의 email 필드가 비어 있어 `_autoSendEmailVerification` 내부
      // `email.isEmpty` 가드 (line 914) 가 자연 no-op 처리. Kakao/Naver 의
      // `emailVerified=true 자동 set` no-op 와는 다른 mechanism — LINE 전용
      // path 명시.
      await _autoSendEmailVerification(userCredential);
      return Result.success(_mapFirebaseUser(fbUser));
    } on FirebaseFunctionsException catch (e) {
      // already-exists 분기는 Phase 12.1 D-34 에서 _mapFunctionsException 자동 흡수.
      return Result.failure(_mapFunctionsException(e));
    } on fb.FirebaseAuthException catch (e) {
      return Result.failure(_mapAuthException(e));
    } on ServiceUnavailable catch (e) {
      // IN-01: signInWithKakao/Naver 와 대칭 — LineSdkClient 가 OIDC scope
      // 누락 / SDK 내부 ServiceUnavailable throw 시 원본을 cause chain 으로
      // wrapping 하지 않고 그대로 보존.
      return Result.failure(e);
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('signInWithLine 비-Auth 예외: $e\n$st');
      }
      return Result.failure(ServiceUnavailable(cause: e));
    } finally {
      // D-LINE-57: SDK access_token 1회성 정책 (Phase 13 D-57 retroactive 일관).
      // Pitfall 2 — race-fix end 직전 위치. 실패 graceful (LineSdkClient.logout
      // 내부 try/catch) — outer 흐름 차단 안 함.
      await _lineSdkClient.logout();
      _socialLinkInProgress.end();
    }
  }

  /// Yahoo!JP OIDC + Firebase Custom Token 로그인 흐름 (Phase 15 D-YJP-01~22).
  ///
  /// Phase 14 [signInWithLine] 직접 mirror + 6 deviation (D-YJP-04/09 + race-fix +
  /// endSession 1회성 + clientId ctor 주입 + scope openid+profile + Cloud
  /// Function name `yahoojpCustomToken`).
  ///
  /// 흐름:
  /// 1. race-fix begin (Pitfall 8 — try-finally 단일 진실원)
  /// 2. [YahoojpSdkClient.signIn] (flutter_appauth
  ///    `authorizeAndExchangeCode` — ASWebAuthenticationSession iOS / Custom
  ///    Tabs Android, OIDC PKCE 자동, idToken + raw nonce 반환)
  /// 3. [FirebaseFunctions.httpsCallable] `yahoojpCustomToken` 호출 — 본 plan
  ///    의 Cloud Function 이 jose 검증 + nonce raw 비교 (nonceHashing=none) +
  ///    Identity Index lookup + `createCustomToken` (Plan 15-02)
  /// 4. [fb.FirebaseAuth.signInWithCustomToken] → Firebase Auth 세션 시작
  /// 5. [_mapFirebaseUser] → 도메인 [User]
  /// 6. finally: [_yahoojpSdkClient.logout] (D-YJP-08 — Pitfall 2 race-fix end
  ///    직전 위치, endSession endpoint 미명시 시 graceful no-op) +
  ///    [SocialLinkInProgress.end]
  ///
  /// 에러 매핑 (Phase 14 LINE path 와 100% 대칭):
  /// - [YahoojpSdkClient.signIn] 가 null 반환 (사용자 취소 silent —
  ///   FlutterAppAuthUserCancelledException → null, D-YJP-09) → null.
  /// - [FirebaseFunctionsException] → [_mapFunctionsException]
  ///   (`already-exists` 분기는 Phase 12.1 D-34 에서
  ///   [AccountExistsWithDifferentCredential] 자동 흡수)
  /// - [fb.FirebaseAuthException] → [_mapAuthException]
  /// - [ServiceUnavailable] (YahoojpSdkClient 가 OIDC scope 누락 — Pitfall 1 /
  ///   clientId 빈 문자열 — T-15-15) → 그대로 Failure 재패키징
  /// - 그 외 → [ServiceUnavailable(cause: e)] + [kDebugMode] [debugPrint]
  ///
  /// **race-fix invariant (Phase 9.1 D-03 / Pitfall 8):** body 전체 try-finally
  /// 로 감싸 진입 직후 [SocialLinkInProgress.begin] / 종료 시
  /// [SocialLinkInProgress.end] 호출. Strategy 단계 추가 호출 절대 금지.
  ///
  /// **D-YJP-08 1회성 토큰 정책 (Phase 14 D-LINE-57 mirror):** 모든 path 에서
  /// finally logout — 성공 / cancel / error / timeout 모두 일관. SDK 가
  /// endSession endpoint 미명시이므로 [YahoojpSdkClient.logout] 내부
  /// try/catch 가 PlatformException 을 silent 흡수 (T-15-14 mitigation).
  ///
  /// **D-YJP-09 정정 lock — email scope 미채택:** Yahoo!JP UserInfo API 審査
  /// 절차 회피를 위해 scope openid+profile 만 채택. Firebase Auth user record
  /// 의 email 필드가 비어 있어 `_autoSendEmailVerification` 내부
  /// email.isEmpty 가드 (line 918) 가 자연 no-op 처리 (LINE D-LINE-21 동일
  /// mechanism).
  ///
  /// Returns null = 사용자 취소 silent.
  Future<Result<User>?> signInWithYahoojp() async {
    try {
      _socialLinkInProgress.begin(); // race-fix Pitfall 8 단일 진실원

      final result = await _yahoojpSdkClient.signIn();
      if (result == null) {
        return null; // D-YJP-09 silent cancel
      }

      final callable = _functions.httpsCallable('yahoojpCustomToken');
      // G-16-A9-1 / D-13: device-local 약관 동의를 add-only 로 동봉해 서버가
      // identity 생성과 같은 write 안에서 termsAccepted 를 mirror 하게 한다.
      final response = await callable.call<Map<String, dynamic>>(
        _buildCustomTokenPayload(<String, dynamic>{
          'idToken': result.idToken,
          'nonce': result.nonce,
        }),
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
      // (Phase 9.2 R4) 자동 sendEmailVerification — Yahoo!JP 는 D-YJP-09 정정
      // lock (scope openid+profile 만) 으로 Firebase Auth user record 의
      // email 필드가 비어 있어 `_autoSendEmailVerification` 내부
      // `email.isEmpty` 가드 (line 918) 가 자연 no-op 처리 (Phase 14 LINE
      // 와 동일 mechanism — D-LINE-21 직접 mirror).
      await _autoSendEmailVerification(userCredential);
      return Result.success(_mapFirebaseUser(fbUser));
    } on FirebaseFunctionsException catch (e) {
      // already-exists 분기는 Phase 12.1 D-34 에서 _mapFunctionsException 자동 흡수.
      return Result.failure(_mapFunctionsException(e));
    } on fb.FirebaseAuthException catch (e) {
      return Result.failure(_mapAuthException(e));
    } on ServiceUnavailable catch (e) {
      // signInWithKakao/Naver/Line 와 대칭 — YahoojpSdkClient 가 OIDC scope
      // 누락 (Pitfall 1) / clientId 빈 문자열 (T-15-15) / SDK 내부
      // ServiceUnavailable throw 시 원본을 cause chain 으로 wrapping 하지
      // 않고 그대로 보존.
      return Result.failure(e);
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('signInWithYahoojp 비-Auth 예외: $e\n$st');
      }
      return Result.failure(ServiceUnavailable(cause: e));
    } finally {
      // D-YJP-08: SDK endSession 1회성 정책 (Phase 14 D-LINE-57 mirror).
      // Pitfall 2 — race-fix end 직전 위치. 실패 graceful (YahoojpSdkClient.
      // logout 내부 try/catch) — outer 흐름 차단 안 함 (T-15-14 mitigation).
      await _yahoojpSdkClient.logout();
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

  /// 로그아웃 + onboarding 완료 플래그 reset
  /// (Phase 10.2 D-A1/A3, I2 invariant 단일 진리원).
  ///
  /// 흐름 (D-A3 — 순서 절대 뒤집기 금지):
  /// 1. [_onResetOnboarding] — `OnboardingNotifier.reset` 콜백.
  ///    state 동기 false set + SharedPreferences 키 제거. lossy persistence
  ///    정책 (disk 실패 시 Crashlytics 기록 후 graceful 진행).
  /// 2. [signOut] — Firebase Auth + Google + Facebook + Kakao + Naver + LINE
  ///    5 SDK 순차 logout (Phase 9.2 R6 invariant).
  ///
  /// 호출 후 navigation 명시 호출은 불필요하다. authStateChanges →
  /// AuthChangeNotifier → authRedirect 분기 (2) 가 `!isAuthenticated &&
  /// !onboardingSeen` 조합을 감지하여 `/onboarding` 으로 자연 redirect 한다
  /// (Phase 10.2 D-B1). reset 이 signOut 보다 먼저 수행되어야 재평가 시점에
  /// `onboardingSeen=false` 가 확정되어 분기 (2) 가 trip 한다 — 순서 뒤집기
  /// 시 stale `onboardingSeen=true` snapshot 으로 GC-04 fail-safe /splash
  /// churn 위험 (Pitfall 3 회귀).
  ///
  /// **D-20 폐기 history (Phase 10):** Phase 10 D-20 의 자동 익명 재진입 API
  /// 는 로그아웃 직후 즉시 익명 세션으로 자동 재진입하여 Home 화면을 유지하는
  /// 정책이었다. 그러나 새 익명 UID 마다 Firestore `users/{uid}/termsAccepted`
  /// 가 null 로 reset 되어 I1 invariant (익명홈 = `onboardingSeen=true AND
  /// termsAccepted=true`) 를 위배했고, 9.2 HUMAN-UAT cycle 1+2 OOS-01 driver
  /// log 3건 (Facebook 이메일 인증 / Kakao 신규 / Naver 신규 — 2026-05-11)
  /// 으로 재현되었다. Phase 10.2 (2026-05-12) 에서 메서드 자체를 완전 폐기
  /// (D-A5) 하고 본 [signOutAndResetOnboarding] 으로 교체했다.
  ///
  /// **Phase 17 (Account Linking & Withdrawal) note:** 회원탈퇴 (reauthentication
  /// + `fb.User.delete`) 경로는 본 메서드를 사용하지 **않는다**. deleteUser
  /// 후의 onboardingSeen 정책은 Phase 17 에서 별도 결정한다
  /// (see ROADMAP Phase 17).
  Future<void> signOutAndResetOnboarding() async {
    await _onResetOnboarding();
    await signOut();
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
  /// **Gap A close (HUMAN-UAT 2026-05-11):** named 인자
  /// [isLinkedFromAnonymous] 도입. Firebase Auth 가
  /// `linkWithCredential` / `linkWithProvider` 분기에서 새 UID 를 발급함에도
  /// `additionalUserInfo.isNewUser=false` 를 반환하는 사양 (Firebase spec) 을
  /// 호출 측 명시 인자로 보강한다. true 일 경우 `additionalIsNewUser ||
  /// isLinkedFromAnonymous` OR 결합으로 D-20 spam 가드를 우회 — 다른 4
  /// 가드 (user==null / isAnonymous / email empty / emailVerified=true) 는
  /// unchanged 동작 (short-circuit 우회 권한 없음). Phase 17 (Account Linking)
  /// — see ROADMAP.md.
  ///
  /// 가드 (D-19 / D-20) — 다음 5 조건 중 하나라도 true 면 no-op:
  /// - [fb.UserCredential.user] == null
  /// - [fb.User.isAnonymous] == true
  /// - [fb.User.email] 이 null 또는 빈 문자열 (WR-04 fix — 이전 `== null`
  ///   가드는 빈 문자열을 통과시켜 Firebase Auth 가 `auth/missing-email`
  ///   throw 시 graceful catch 가 흡수하나 메일 미발송)
  /// - [fb.User.emailVerified] == true
  /// - `additionalUserInfo.isNewUser == false` **AND** [isLinkedFromAnonymous]
  ///   == false (D-20 — 재로그인 spam 방지 + Gap A close 보강)
  ///
  /// Apple/Google 의 idToken `email_verified=true` claim + Kakao/Naver 의
  /// Cloud Function `identity_index.ts:225` `emailVerified: true` 자동 set
  /// 으로 인해 4 provider 는 자연 no-op 이며, Facebook 만 실효적 호출 한다.
  ///
  /// 발송 실패는 graceful (D-21 — Phase 6.1 D-10/D-11 패턴 계승). 로그인
  /// 자체는 성공 유지. [fb.FirebaseAuthException] + [Object] 양쪽 catch +
  /// [kDebugMode] [debugPrint] only.
  ///
  /// [isLinkedFromAnonymous] Google/Apple/Facebook 의 익명 →
  /// `linkWithCredential` / `linkWithProvider` 분기에서만 `true` 명시 전달.
  /// 비-익명 `signInWithCredential` + Kakao/Naver `signInWithCustomToken`
  /// 분기는 default `false` 자연 유지.
  Future<void> _autoSendEmailVerification(
    fb.UserCredential userCredential, {
    bool isLinkedFromAnonymous = false,
  }) async {
    final user = userCredential.user;
    if (user == null) return;
    if (user.isAnonymous) return;
    // WR-04: `email == null` 가드는 빈 문자열을 통과 → Firebase Auth 가
    // `auth/missing-email` throw 시 graceful catch 흡수하나 메일 미발송.
    // null + empty 양쪽을 단일 가드로 차단.
    if ((user.email ?? '').isEmpty) return;
    if (user.emailVerified) return;
    // Gap A close (HUMAN-UAT 2026-05-11): Firebase 가 linkWithCredential
    // 분기에서 isNewUser=false 를 반환하는 사양 보강. 호출 측이
    // isLinkedFromAnonymous=true 명시 전달 시 OR 결합으로 D-20 우회.
    // Phase 17 (Account Linking) — see ROADMAP.md.
    final additionalIsNewUser =
        userCredential.additionalUserInfo?.isNewUser ?? false;
    final isNewUser = additionalIsNewUser || isLinkedFromAnonymous;
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
  ///
  /// **I2 invariant 호출자 책임 (Phase 10.2 D-A7):** 재진입 path (logout UI)
  /// 의도시 [signOutAndResetOnboarding] 사용. [signOut] 단독 호출은
  /// [signOutAndResetOnboarding] 내부 단계 전용 (현재 production 의 유일한
  /// 직접 호출자 — Phase 10.2 review iter3 IN-01 정정. 이전 doc 은
  /// [_safeDelete] 를 internal caller 예시로 인용했으나 [_safeDelete] 는
  /// `user.delete()` 만 호출하고 [signOut] 은 호출하지 않으므로 self-
  /// inconsistent 했음). UI 호출자 (로그아웃 버튼) 가 본 메서드를 직접
  /// 호출하면 `onboardingSeen=true` snapshot 이 유지된 채 authRedirect
  /// 가 재평가되어 익명홈 통과 race 가 가능하다 (I2 위배 — D-20 cycle 회귀
  /// vector). Phase 17 (회원탈퇴 reauthentication + deleteUser) 는 별도
  /// 논의 — see ROADMAP Phase 17.
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
    // LINE SDK 세션 해제 (Phase 14 D-LINE-57 — Kakao/Naver 패턴 일관).
    try {
      await _lineSdkClient.logout();
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('LineSdkClient.logout() 실패 (무시): $e\n$st');
      }
    }
    // Yahoo!JP SDK 세션 해제 (Phase 15 D-YJP-08 — Kakao/Naver/LINE 패턴 일관).
    try {
      await _yahoojpSdkClient.logout();
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('YahoojpSdkClient.logout() 실패 (무시): $e\n$st');
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
      // (Phase 9.2 R2) Path A-narrow — email 필드 보존: server-side provider
      // 매핑 input. (Phase 16 16-08) pendingCredential: e.credential 보존 —
      // native reactive link arm (linkPendingNativeCredential) 의 입력.
      'account-exists-with-different-credential' =>
        AccountExistsWithDifferentCredential(
          email: e.email,
          pendingCredential: e.credential,
          cause: e,
        ),
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

  /// Custom Token callable payload 에 `termsAcceptanceSnapshot` 을 add-only 로
  /// 부착한다 (Phase 16 G-16-A9-1 / D-13).
  ///
  /// **회귀 invariant (add-only):** device-local 동의가 없어 reader 가 null 을
  /// 반환하면 [base] 를 그대로 반환한다 — 4 provider 의 기존 payload 키 집합이
  /// 한 글자도 바뀌지 않는다. 서버 arg 도 optional 이므로 본 helper 호출만
  /// 되돌리면 완전 복귀한다.
  ///
  /// **서버 계약:** 부착 값의 키 집합은
  /// `functions/src/shared/terms_acceptance_json.ts` 의 `TermsAcceptanceJson`
  /// 5 키 (version / service / privacy / marketing / acceptedAt) 와 정확히
  /// 일치해야 한다. 4 endpoint (kakao/naver/line/yahoojp) 가 이를 optional 로
  /// 수신해 `users/{uid}` 문서 생성과 같은 write 안에서 mirror 한다.
  ///
  /// **`acceptedAt` 은 ISO 8601 String 이어야 한다.** 서버가
  /// `Timestamp.fromDate(new Date(...))` 로 파싱하므로 `DateTime` 객체나 epoch
  /// int 를 보내면 파싱이 깨진다. `TermsAcceptance.toJson()` 의
  /// `toIso8601String()` 출력이 그대로 계약을 만족한다.
  Map<String, dynamic> _buildCustomTokenPayload(Map<String, dynamic> base) {
    final snapshot = _readTermsAcceptanceSnapshot();
    if (snapshot == null) {
      return base;
    }
    // spread 로 base 를 불변 유지한 채 새 map 을 만든다.
    return <String, dynamic>{...base, 'termsAcceptanceSnapshot': snapshot};
  }

  /// [FirebaseFunctionsException] 을 [AppException] 으로 매핑한다
  /// (Phase 12 D-30 / RESEARCH Pattern 4 / Phase 12.1 R3 — D-34).
  ///
  /// Cloud Function 의 [HttpsError] 표준 코드 → [AppException] 분류:
  /// - `unauthenticated` / `invalid-argument` / `failed-precondition` /
  ///   `permission-denied`
  ///   → [ServiceUnavailable] (App Check 차단 / JWT 검증 실패 / 사전 조건
  ///    위배 / App Check enforcement 실패 / token age 위반)
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
      // IN-02: permission-denied 명시 분기 — App Check enforcement 차단
      // (enforceAppCheck:true onCall) 또는 Firebase Auth token age 위반.
      // 기존 default 분기 (ServiceUnavailable(cause: e)) 와 동일 시맨틱이나
      // ops triage 시 unclassified default 와 분리되어 fingerprint 가능.
      'unauthenticated' ||
      'invalid-argument' ||
      'failed-precondition' ||
      'permission-denied' => const ServiceUnavailable(),
      'unavailable' || 'deadline-exceeded' => const NoInternetConnection(),
      // R3 (D-34) — Cloud Function 의 already-exists → 사용자 recovery 가능한
      // AccountExistsWithDifferentCredential 매핑. 신규 클래스/ARB 0건
      // (Phase 8/9 패턴 재사용 — errorAccountExistsWithDifferentCredential).
      //
      // (16-13 A4 gap closure) Custom Token side existingProvider wiring:
      // 서버(16-13 Task 1)가 collision throw 의 HttpsError details 에
      // existingProvider slug 를 전달하므로 client 가 직독해
      // existingProvider 에 매핑한다 (16-09 의 sheet 분기 도달 가능 = dead
      // branch 해소). native side (_enrichAccountExistsAsync via
      // lookupSignInMethods) 와 달리 Custom Token side 는 server details
      // 직독 — 추가 callable round-trip 0. email==null 은 그대로 유지 (서버
      // PII 정책 — server 가 email 본문 미전달). unknown/누락/non-Map details
      // 는 _existingProviderFromDetails 가 null 반환 → R2 일반 배너 fallback.
      'already-exists' => AccountExistsWithDifferentCredential(
        existingProvider: _existingProviderFromDetails(e.details),
        cause: e,
      ),
      _ => ServiceUnavailable(cause: e),
    };
  }

  /// [FirebaseFunctionsException.details] 에서 `existingProvider` slug 를 안전
  /// 추출해 [AccountProvider] 로 변환한다 (16-13 A4 gap closure).
  ///
  /// 서버 collision throw 의 `details` 는 `{existingProvider: 'kakao'}` 형태의
  /// Map 이다. [details] 가 [Map] 이 아니거나 `existingProvider` 키가 없거나
  /// 값이 [String] 이 아니거나 unknown slug 면 `null` 을 반환한다 (R2 일반
  /// 배너 fallback 보존). [AccountProvider.tryParse] 가 등록 8 slug 만 enum
  /// 변환하고 그 외 (`null` / unknown) 는 `null` 로 흡수한다.
  ///
  /// [details] 는 `dynamic` 이므로 [Object?] 로 받아 `is` 가드로 좁힌다
  /// (flutter.md `dynamic` 금지 + `as` 최소화).
  AccountProvider? _existingProviderFromDetails(Object? details) {
    if (details is! Map) return null;
    final raw = details['existingProvider'];
    return raw is String ? AccountProvider.tryParse(raw) : null;
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

  /// Phase 16 D-12 wiring — [AccountExistsWithDifferentCredential] 의 base
  /// instance 가 입력으로 들어오면 (1) cache 확인, (2) miss 시
  /// `lookupSignInMethods` callable 호출, (3) `existingProvider` 가 채워진
  /// 새 instance 를 반환한다.
  ///
  /// 입력이 [AccountExistsWithDifferentCredential] 가 아니거나 email 이
  /// null 인 경우 입력 그대로 반환 (회귀 0).
  ///
  /// **PII invariant (R7 / T-16-NEW-07):** 본 메서드 가 catch 시점에서
  /// `collisionEmail` 본문을 logger / Crashlytics 페이로드에 절대 포함시키지
  /// 않는다. cache key 는 메모리 내부에만 유지되며 외부 sink 비전파.
  ///
  /// **Pitfall 5 회피:** [_accountExistsCache] TTL 5 분 — 동일 이메일 두
  /// 번째 호출 시 callable 미호출.
  Future<AppException> _enrichAccountExistsAsync(AppException base) async {
    if (base is! AccountExistsWithDifferentCredential) return base;
    final email = base.email;
    if (email == null || email.isEmpty) return base; // unknown fallback path
    if (base.existingProvider != null) return base; // 이미 식별됨 (no-op)

    final provider = await _lookupExistingProvider(email);
    return AccountExistsWithDifferentCredential(
      email: email,
      existingProvider: provider,
      // (Phase 16 16-08) enrichment 이 pendingCredential 을 떨어뜨리지 않도록
      // carry-forward — native reactive link arm 의 입력 보존.
      pendingCredential: base.pendingCredential,
      cause: base.cause,
    );
  }

  /// Phase 16 D-12 — `lookupSignInMethods` Cloud Function callable 호출
  /// (RESEARCH § Pitfall 5 의 client cache 패턴 mirror).
  ///
  /// 응답 schema: `{existingProvider: "kakao" | "google" | ... | null}`.
  /// callable 가 throw (network/App Check/rate-limit) 하거나 응답이
  /// unknown slug 인 경우 graceful `null` 반환 — R2 unknown fallback
  /// baseline 보존.
  Future<AccountProvider?> _lookupExistingProvider(String email) async {
    // Step 1 — cache 확인 (Pitfall 5: TTL 5 분 invariant).
    // WR-05: 만료 entry 는 read 시점에 즉시 evict 하여 plaintext email 의
    // 메모리 잔류 시간을 TTL 로 제한한다 (기존엔 만료 후에도 덮어쓰기 전까지
    // 무기한 잔류).
    final cached = _accountExistsCache[email];
    if (cached != null) {
      if (cached.isExpired(_now())) {
        _accountExistsCache.remove(email);
      } else {
        return cached.provider;
      }
    }

    // Step 2 — cache miss → callable 호출.
    AccountProvider? provider;
    try {
      final callable = _functions.httpsCallable(
        'lookupSignInMethods',
        options: HttpsCallableOptions(timeout: _kLookupTimeout),
      );
      final response = await callable.call<Map<String, dynamic>>(
        <String, dynamic>{'email': email},
      );
      final slug = response.data['existingProvider'] as String?;
      provider = AccountProvider.tryParse(slug);
    } on Object catch (e) {
      // PII invariant — error 페이로드에 collisionEmail 미포함.
      // debugPrint 본문 도 email 비포함 (T-16-NEW-07 sentinel).
      if (kDebugMode) {
        debugPrint(
          'AuthRepository._lookupExistingProvider: lookup fail — '
          'silent fallback (existingProvider=null). cause runtimeType='
          '${e.runtimeType}',
        );
      }
      provider = null;
    }

    // Step 3 — cache (success / fallback 모두 cache 하여 retry 비용 절감).
    // WR-05: 새 key 삽입 전 size cap 적용 — 한도 초과 시 가장 오래된(삽입
    // 순서) entry 를 evict (Dart Map 은 insertion-order 보존). 동일 key
    // 갱신은 size 증가가 아니므로 evict 불요.
    if (!_accountExistsCache.containsKey(email) &&
        _accountExistsCache.length >= _kAccountExistsCacheMaxEntries) {
      _accountExistsCache.remove(_accountExistsCache.keys.first);
    }
    _accountExistsCache[email] = _CachedProvider(provider, _now());
    return provider;
  }
}

/// Custom Token target provider 의 OIDC 토큰 + nonce 묶음 (Phase 16 16-09).
///
/// [KakaoSignInResult] / [LineSignInResult] / [YahoojpSignInResult] 의 `idToken`
/// + `nonce` 를 단일 인터페이스로 normalize 하여
/// [AuthRepository.linkCustomTokenProviderArm] 가 provider-agnostic 하게
/// callable payload 를 구성하도록 한다.
class _TargetProviderToken {
  const _TargetProviderToken(this.idToken, this.nonce);

  /// target provider OIDC ID Token — deployed callable `targetProviderToken`.
  final String idToken;

  /// 단일 사용 raw nonce — deployed callable `nonce` (3 provider 모두 의무).
  final String nonce;
}

/// [AuthRepository._accountExistsCache] 의 entry — TTL 검증을 위한 발효
/// 시각 보유.
class _CachedProvider {
  _CachedProvider(this.provider, this.cachedAt);
  final AccountProvider? provider;
  final DateTime cachedAt;

  bool isExpired(DateTime now) =>
      now.difference(cachedAt) >= AuthRepository._kAccountExistsCacheTtl;
}

/// [AuthRepository.new] 의 `readTermsAcceptanceSnapshot` 미주입 시 기본 구현
/// (Phase 16 G-16-A9-1).
///
/// 항상 null 을 반환하여 Custom Token payload 를 기존 키 집합 그대로 유지한다
/// (add-only invariant — 기존 테스트 12곳의 생성자 호출부 회귀 0).
Map<String, dynamic>? _readNoTermsAcceptanceSnapshot() => null;

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
    // Phase 14 — see ROADMAP.md (LINE Custom Token wrapper).
    ref.watch(lineSdkClientProvider),
    // Phase 15 — see ROADMAP.md (Yahoo!JP Custom Token wrapper).
    ref.watch(yahoojpSdkClientProvider),
    // Phase 10.2 D-A2: cross-feature 결합도 최소화를 위한 callback 주입.
    // OnboardingNotifier 타입은 본 factory 영역에서만 알며,
    // AuthRepository 클래스 본체는 콜백 signature 만 의존한다.
    () => ref.read(onboardingProvider.notifier).reset(),
    // Phase 16 G-16-A9-1: 동일한 D-A2 콜백 주입 관례. TermsNotifier 타입은
    // 본 factory 영역에서만 알며, AuthRepository 클래스 본체는
    // `Map<String, dynamic>? Function()` signature 만 의존한다. toJson() 이
    // 서버 TermsAcceptanceJson 5 키를 그대로 산출한다 (acceptedAt = ISO 8601).
    readTermsAcceptanceSnapshot: () =>
        ref.read(termsProvider.notifier).acceptanceSnapshot?.toJson(),
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
          // attempt N/M = 본 거부를 받고 즉시 시도하는 N 번째 재구독
          // (총 M 회 = maxRetries). 다음 거부가 발생하면 N+1, 마지막 N=M
          // 의 재구독 까지 모두 permission-denied 면 다음 거부가 escape
          // 분기로 빠진다 (WR-03 — log 가 "retry 5/5 후 즉시 escape" 로
          // 잘못 읽히지 않게 명시).
          debugPrint(
            'linkedProvidersStream permission-denied: '
            'retrying attempt $permissionDeniedRetries of $maxRetries '
            '(after ${retryDelay.inMilliseconds}ms delay): $e',
          );
        }
        await Future<void>.delayed(retryDelay);
        continue;
      }
      // I1 (D-41 보존):
      // (1) 다른 FirebaseException (network / unavailable 등) — 즉시 빈 배열.
      // (2) permission-denied — maxRetries 회 재구독 후에도 거부 → 영구
      //     spinner 회피 escape hatch (총 maxRetries+1 회 거부 후 escape).
      if (kDebugMode) {
        debugPrint('linkedProvidersStream 에러 (fallback empty): $e\n$st');
      }
      yield const <String>[];
      break;
    }
  }
}
