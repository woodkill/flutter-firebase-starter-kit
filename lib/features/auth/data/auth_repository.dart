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

import '../../../core/auth/nonce.dart';
import '../../../core/auth/provider_id.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/error/result.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../onboarding/presentation/onboarding_notifier.dart';
import '../../settings/domain/unlink_provider_request.dart';
// Phase 16 G-16-A9-1: authRepository factory provider 의 콜백 주입 전용 import.
// AuthRepository 클래스 본체는 본 타입을 참조하지 않는다 (D-A2 관례).
import '../../terms/domain/terms_state.dart';
import '../../terms/presentation/terms_notifier.dart';
import '../application/social_link_in_progress.dart';
import '../domain/anonymous_sign_in.dart';
import '../domain/user.dart';
import 'kakao_sdk_client.dart';
import 'line_sdk_client.dart';
import 'naver_sdk_client.dart';
import 'naver_sign_in_result.dart';
import 'sign_up_method_recorder.dart';

part 'auth_repository.g.dart';

/// Firebase Auth를 감싸는 인증 Repository.
///
/// FirebaseAuth와 GoogleSignIn 의존성을 data 계층에 격리하고,
/// 상위 레이어(Notifier)에는 [Result] 타입으로만 노출한다.
/// FirebaseAuthException은 [AppException]으로 매핑되어 던져진다.
///
/// **PII 로깅 invariant (WR-05 — Phase 7 review, 클래스 전역 단일 정책):**
/// 본 클래스의 모든 [debugPrint] 는 예외 **본문을 출력하지 않는다**. 허용
/// 되는 식별 정보는 다음 3종뿐이다.
///
/// - `e.code` (FirebaseAuthException / FirebaseFunctionsException /
///   FirebaseException 등 열거형 코드)
/// - `e.runtimeType`
/// - [StackTrace] (file path + symbol + line 만 포함 — PII safe)
///
/// `$e` (= `toString()`) / `e.message` / `e.description` /
/// `LoginResult.message` / email / 토큰 값은 금지한다. SDK 예외 message 는
/// 사용자 이메일·프로필·CDN URL 등을 실을 수 있고, `kDebugMode` 한정이라도
/// 개발자 단말 logcat 에 남는다. 이전에는 4곳만 이 정책을 따르고 sign-in
/// 7 경로 등 나머지는 `$e` 를 그대로 찍어 정책이 두 갈래였다.
/// 같은 정책이 3 SDK wrapper (`kakao_sdk_client.dart` /
/// `naver_sdk_client.dart` / `line_sdk_client.dart`) 에도 동일 적용된다.
class AuthRepository implements AnonymousSignIn {
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
  /// 추가됐다 — naver_login_flutter 의 Future 반환 API wrapper (Phase 16.2
  /// D-16). Cloud Function 채널 (`naverCustomToken`) 은 [_functions] 를
  /// 재사용한다.
  ///
  /// [_lineSdkClient] 는 Phase 14 LINE 로그인 (Custom Token 방식) 을 위해
  /// 추가됐다 — flutter_line_sdk wrapper. Cloud Function 채널
  /// (`lineCustomToken`) 은 [_functions] 를 재사용한다.
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
  ///
  /// [recordSignUpMethod] 는 가입 수단을 `users/{uid}.signUpProviderId` 에
  /// 기록하는 콜백이다 (Phase 16.7 D-13 · D-15). 같은 D-A2 논리로
  /// `SignUpMethodRecorder` 타입은 [authRepository] factory provider 영역
  /// 한정이며, 본체는 [RecordSignUpMethod] signature 만 의존한다. 가입이
  /// 확정된 분기에서만 `unawaited(...)` 로 호출한다 — 서버 ack 를 기다리지
  /// 않고, 콜백은 어떤 예외도 던지지 않는다 (D-17). 미주입 시 기본값은
  /// no-op [_recordNoSignUpMethod] 라 기존 생성자 호출부는 변경 0 이다
  /// (positional 9 인자 불변 · D-27).
  AuthRepository(
    this._auth,
    this._googleSignIn,
    this._facebookAuth,
    this._socialLinkInProgress,
    this._kakaoSdkClient,
    this._functions,
    this._naverSdkClient,
    this._lineSdkClient,
    this._onResetOnboarding, {
    DateTime Function()? now,
    Map<String, dynamic>? Function()? readTermsAcceptanceSnapshot,
    RecordSignUpMethod? recordSignUpMethod,
  }) : _now = now ?? DateTime.now,
       _readTermsAcceptanceSnapshot =
           readTermsAcceptanceSnapshot ?? _readNoTermsAcceptanceSnapshot,
       _recordSignUpMethod = recordSignUpMethod ?? _recordNoSignUpMethod;

  final fb.FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;
  final FacebookAuth _facebookAuth;
  final SocialLinkInProgress _socialLinkInProgress;
  final KakaoSdkClient _kakaoSdkClient;
  final FirebaseFunctions _functions;
  final NaverSdkClient _naverSdkClient;
  final LineSdkClient _lineSdkClient;
  final Future<void> Function() _onResetOnboarding;

  /// device-local 약관 동의 snapshot 을 서버 계약 JSON 으로 읽는 콜백
  /// (Phase 16 G-16-A9-1). 동의 부재 시 null.
  final Map<String, dynamic>? Function() _readTermsAcceptanceSnapshot;

  /// 가입 수단 기록 콜백 (Phase 16.7 D-13 · D-17). 절대 throw 하지 않는다.
  final RecordSignUpMethod _recordSignUpMethod;

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
  ///
  /// **무효화 지점 3종 (WR-07 — Phase 7 review):**
  /// 1. read 시점 TTL 만료 evict ([_kAccountExistsCacheTtl])
  /// 2. 삽입 시점 size cap evict ([_kAccountExistsCacheMaxEntries])
  /// 3. **계정 경계 — [signOut] 의 `clear()`** (WR-07 에서 추가). 1·2 만으로는
  ///    로그아웃 후 다른 사용자 세션에 이전 사용자의 평문 이메일이 최대 TTL
  ///    동안 남고, 같은 window 안의 동일 이메일 충돌에서 이전 세션 응답이
  ///    재사용된다.
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

  /// Custom Token sign-in callable (kakao/naver/line) 타임아웃 — 10 초
  /// (WR-10). link arm(`linkCustomTokenProvider`) · 해제
  /// (`unlinkCustomTokenProvider`, Phase 16.8) callable 도 이 상수를 공유한다
  /// — 값을 바꿀 때 호출처가 조용히 어긋나지 않도록 리터럴을 두지 않는다
  /// (16.8 review IN-02 · iteration 2 IN-03).
  ///
  /// 로그인 · link arm callable 은 race-fix try-finally 블록 안에서 await
  /// 된다. hang 시 `_socialLinkInProgress.end()` 도 hang 하여 splash 의 자동
  /// 익명 sign-in 과 auth_guard GC-04 fail-safe redirect 가 무한 차단된다
  /// (Phase 9.1 D-03 race-fix 와 직접 충돌). 같은 논리로 별도 timeout 이
  /// 적용된 지점: `lookupSignInMethods` (5s) / `sendEmailVerification` (5s) /
  /// Facebook Graph + updatePhotoURL (각 5s).
  static const Duration _kCustomTokenTimeout = Duration(seconds: 10);

  /// Naver 킷 웹 경로 callable(`naverWebCustomToken`) 타임아웃 — 20 초
  /// (Phase 16.5 review WR-01).
  ///
  /// 웹 경로 서버는 NAVER 를 직렬로 2회 호출한다 (code 교환 5s · `/v1/nid/me`
  /// 5s — 둘 다 `AbortSignal.timeout` 이라 본문 읽기까지 포함한 상한,
  /// review 2회차 IN-04). 서버 토큰 폐기 호출은 quick 260924-lw2 에서
  /// 제거됐다(16.5 D-15 번복). 여기에 Firestore transaction ·
  /// `createCustomToken` · terms mirror · cold start 가 더해진다. 1-tap 과
  /// 같은 10s 를 쓰면 서버가 계정을 만든 뒤에도 클라이언트가
  /// `deadline-exceeded` → [NoInternetConnection] 을 내는 조용한 부분 성공이
  /// 생긴다. 로그인 · 재인증 두 호출처가 같은 값을 쓴다.
  static const Duration _kNaverWebCustomTokenTimeout = Duration(seconds: 20);

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
      return Result.failure(
        await _enrichAccountExistsAsync(_mapAuthException(e)),
      );
    } on Object catch (e, st) {
      // WR-06 (Phase 7 review): 비-Auth 예외 (PlatformException 등) 를 Result
      // 로 감싸 Notifier state 가 AsyncLoading 에 고정되는 것을 방지한다.
      // 소셜 6 경로 / [reloadUser] 가 이미 갖고 있는 방어의 email 계열 mirror
      // — 예외가 그대로 전파되면 LoginNotifier.submit 의
      // `state = switch (result)` 에 도달하지 못해 PrimaryCta 가 영구
      // 스피너/비활성으로 고정된다.
      if (kDebugMode) {
        debugPrint('signInWithEmail 비-Auth 예외: ${e.runtimeType}\n$st');
      }
      return Result.failure(ServiceUnavailable(cause: e));
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
      // Phase 16.7 D-14: 익명 link · createUser 둘 다 가입 확정이라 조건 없이
      // 기록한다 (email-already-in-use 는 throw 라 여기 도달하지 않는다).
      // D-17: 서버 ack 를 기다리지 않는다 — recorder 가 모든 예외를 흡수한다.
      unawaited(
        _recordSignUpMethod(fbUser.uid, fb.EmailAuthProvider.PROVIDER_ID),
      );
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
          debugPrint(
            'updateDisplayName/reload 비-Auth 예외: ${e.runtimeType}\n$st',
          );
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
          debugPrint('sendEmailVerification 비-Auth 예외: ${e.runtimeType}\n$st');
        }
      }

      return Result.success(_mapFirebaseUser(refreshed));
    } on fb.FirebaseAuthException catch (e) {
      // Phase 16 D-12 wiring — account-exists 시 provider enrichment.
      return Result.failure(
        await _enrichAccountExistsAsync(_mapAuthException(e)),
      );
    } on Object catch (e, st) {
      // WR-06 (Phase 7 review): 비-Auth 예외 (PlatformException 등) 를 Result
      // 로 감싸 Notifier state 가 AsyncLoading 에 고정되는 것을 방지한다.
      // 소셜 6 경로 / [reloadUser] 가 이미 갖고 있는 방어의 email 계열 mirror
      // — 예외가 그대로 전파되면 LoginNotifier.submit 의
      // `state = switch (result)` 에 도달하지 못해 PrimaryCta 가 영구
      // 스피너/비활성으로 고정된다.
      if (kDebugMode) {
        debugPrint('signUpWithEmail 비-Auth 예외: ${e.runtimeType}\n$st');
      }
      return Result.failure(ServiceUnavailable(cause: e));
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
  /// link 오류 code 2종은 반대로 처리한다.
  ///
  /// - `credential-already-in-use`: 익명 계정을 [_safeDelete] 로 폐기하고
  ///   기존 Google 계정으로 [fb.FirebaseAuth.signInWithCredential] fallback.
  ///   익명 UID 로 작성된 Firestore 데이터는 손실 (Starter Kit D-09 — 1회성
  ///   승격 패턴).
  /// - `email-already-in-use`: 새 로그인을 하지 않고 익명을 유지한 채
  ///   [AccountExistsWithDifferentCredential] 을 반환한다. Google 은 @gmail.com
  ///   주소에 한해 Firebase trusted provider 라 새 로그인이 같은 email 기존
  ///   계정으로의 자동 연결 + displayName · photoUrl 교체 + 세션 전환이 되기
  ///   때문이다 (debug google-gmail-email-arm-merge). 예외의 email 이 비어
  ///   있으면(iOS SDK 는 이 오류에 email 을 싣지 않음) 로컬
  ///   [GoogleSignInAccount.email] 로 채우고, pendingCredential 에는 로컬 Google
  ///   credential 을 넣어 기존 provider 조회 · 계정 연결 시트가 두 플랫폼에서
  ///   같게 동작한다.
  ///
  /// 다중 provider linking 은 Phase 17 (Account Linking) — see ROADMAP.md.
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
      // WR-01: idToken null/empty 가드 — Kakao/LINE Pitfall 1 mirror.
      final credential = _googleCredentialOf(account);

      final anonymous = _auth.currentUser;
      // Gap A close (HUMAN-UAT 2026-05-11): success path 합류 후 익명 분기 정보
      // 보존. helper 의 isLinkedFromAnonymous 명시 인자로 D-20 우회.
      // Phase 17 (Account Linking) — see ROADMAP.md.
      final isLinkedFromAnonymous = anonymous != null && anonymous.isAnonymous;
      // Phase 16.7 D-14: link 가 정상 반환한 분기에서만 true (fallback 은 false).
      var didLinkAnonymous = false;
      fb.UserCredential userCredential;
      if (anonymous != null && anonymous.isAnonymous) {
        // Phase 10 D-14 / BLOCKER #4: 익명 → 정식 승격.
        try {
          userCredential = await anonymous.linkWithCredential(credential);
          didLinkAnonymous = true;
        } on fb.FirebaseAuthException catch (e) {
          if (e.code == 'email-already-in-use') {
            // debug google-gmail-email-arm-merge — 새 로그인 금지.
            // @gmail.com Google 은 Firebase trusted provider 라 여기서 signIn
            // 하면 서버가 account-exists 로 거부하지 않고 같은 email 의 기존
            // 계정에 google.com 을 자동 연결하면서 displayName · photoUrl 을
            // Google 값으로 교체하고 세션을 그 계정으로 바꾼다 (iOS 실기기
            // 원장 실측). Phase 16 계정 연결 정책대로 account-exists 로 돌려
            // 사용자가 기존 방식으로 로그인한 뒤 연결하게 한다.
            // 익명은 유지한다 — lookupSignInMethods 가 request.auth 를 요구한다
            // (debug android-classic-anon-conflict).
            if (kDebugMode) {
              // PII invariant: code 와 bool 만 (e.email · credential 본문 비포함).
              debugPrint(
                'AuthRepository.signInWithGoogle: email-already-in-use — '
                '익명 유지 + 자동 합류 차단 '
                '(hasEmail: ${e.email?.isNotEmpty ?? false}, '
                'hasCredential: ${e.credential != null})',
              );
            }
            // email — 서버가 충돌 판정한 값을 우선하고, iOS 처럼 payload 에
            // 없으면 같은 Google 계정의 로컬 email 로 채운다.
            // pendingCredential — 방금 받은 로컬 credential 을 넘긴다. nonce 가
            // 없는 idToken credential 이라 link 실패 뒤에도 서버가 재사용을
            // 받는다 (실기기 실측). e.credential 은 iOS 에서 null 이다.
            final payloadEmail = e.email;
            return Result.failure(
              await _enrichAccountExistsAsync(
                AccountExistsWithDifferentCredential(
                  email: (payloadEmail != null && payloadEmail.isNotEmpty)
                      ? payloadEmail
                      : account.email,
                  pendingCredential: credential,
                  cause: e,
                ),
              ),
            );
          }
          if (e.code != 'credential-already-in-use') {
            rethrow;
          }
          // 이미 Google 로 가입된 계정이 있음 — google.com 사용자가 이미 있어
          // 같은 credential signIn 이 provider 일치 분기로 성공한다 (email
          // 합류 분기 아님). D-09 순서 유지 (SLP-7).
          if (kDebugMode) {
            debugPrint(
              'AuthRepository.signInWithGoogle: ${e.code} '
              '— 익명 계정 폐기 + 기존 Google 계정 로그인',
            );
          }
          await _safeDelete(anonymous);
          userCredential = await _auth.signInWithCredential(credential);
        }
      } else {
        userCredential = await _auth.signInWithCredential(credential);
      }
      final fbUser = userCredential.user;
      if (fbUser == null) {
        return const Result.failure(ServiceUnavailable());
      }
      // Phase 16.7 D-14: isLinkedFromAnonymous 는 fallback 뒤에도 true 라 쓰지
      // 않는다. link 분기는 isNewUser=false 라(Gap A) link 성공과 OR 한다.
      // D-17: 서버 ack 를 기다리지 않는다 — recorder 가 모든 예외를 흡수한다.
      final isSignUp =
          didLinkAnonymous ||
          (userCredential.additionalUserInfo?.isNewUser ?? false);
      if (isSignUp) {
        unawaited(
          _recordSignUpMethod(fbUser.uid, fb.GoogleAuthProvider.PROVIDER_ID),
        );
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
      // D2 B1: 소셜 invalid-credential 은 email 문구로 새지 않게 분리한다.
      return Result.failure(
        await _enrichAccountExistsAsync(_mapSocialAuthException(e)),
      );
    } on ServiceUnavailable catch (e) {
      // WR-01: [_googleCredentialOf] 의 idToken 가드 (serverClientId 미설정 등
      // 설정 오류) — signInWithKakao/Naver/Line 와 대칭으로 원본을
      // cause chain 으로 wrapping 하지 않고 그대로 보존.
      return Result.failure(e);
    } on Object catch (e, st) {
      // 비-Auth 예외 (PlatformException 등) 를 Result 로 감싸 Notifier state
      // 가 AsyncLoading 에 고정되는 것을 방지한다 (Apple/Facebook 패턴 미러링).
      // begin/end invariant 자체는 finally 블록이 보장하므로 race-fix 와 직교.
      if (kDebugMode) {
        debugPrint('signInWithGoogle 비-Auth 예외: ${e.runtimeType}\n$st');
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
  /// link 오류 code 2종은 반대로 처리한다.
  ///
  /// - `credential-already-in-use`: 익명 계정을 [_safeDelete] 로 폐기하고,
  ///   1차 [fb.User.linkWithProvider] 가 던진
  ///   [fb.FirebaseAuthException.credential] 을 우선 재사용하여
  ///   [fb.FirebaseAuth.signInWithCredential] 한 번으로 종결한다 — Apple OAuth
  ///   플로우(Android Custom Tab / iOS ASAuthorizationController 시트) 재진입을
  ///   회피한다 (260503-ang quick). `e.credential == null` 인 보조 경로에서만
  ///   [fb.FirebaseAuth.signInWithProvider] fallback 으로 회귀를 방지한다.
  /// - `email-already-in-use`: 새 로그인을 하지 않고 익명을 유지한 채
  ///   [AccountExistsWithDifferentCredential] 을 반환한다. Apple 은 Firebase
  ///   trusted provider 라 새 로그인이 같은 email 기존 계정으로의 자동 연결 +
  ///   displayName · photoUrl 덮어쓰기가 되기 때문이다 (debug
  ///   apple-email-merge-profile-loss). iOS 는 이 오류에 email 을 싣지 않아
  ///   기존 provider 를 알 수 없으므로 unknown-provider 안내로 끝난다.
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
      // Phase 16.7 D-14: link 가 정상 반환한 분기에서만 true (fallback 은 false).
      var didLinkAnonymous = false;
      fb.UserCredential userCredential;
      if (anonymous != null && anonymous.isAnonymous) {
        // Phase 10 D-14 / BLOCKER #4: 익명 → 정식 승격.
        try {
          userCredential = await anonymous.linkWithProvider(provider);
          didLinkAnonymous = true;
        } on fb.FirebaseAuthException catch (e) {
          if (e.code == 'email-already-in-use') {
            // debug apple-email-merge-profile-loss — 새 로그인 금지.
            // Apple 은 Firebase trusted provider 라 여기서 signIn 하면 서버가
            // 같은 email 의 기존 계정에 apple.com 을 자동 연결하면서
            // displayName · photoUrl 을 IdP 응답값으로 덮어쓴다 (두 번째 인가라
            // 이름 없음 · Apple 사진 없음 → 기존 프로필 소실). iOS SDK 는 이
            // 오류에 credential · email 을 싣지 않아 signIn 은 Apple 창 재표시
            // 까지 부른다. Phase 16 계정 연결 정책대로 account-exists 로 돌려
            // 사용자가 기존 방식으로 로그인한 뒤 설정에서 연결하게 한다.
            // 익명은 유지한다 — lookupSignInMethods 가 request.auth 를 요구한다.
            if (kDebugMode) {
              // PII invariant: code 와 bool 만 (e.email · credential 본문 비포함).
              debugPrint(
                'AuthRepository.signInWithApple: email-already-in-use — '
                '익명 유지 + 자동 합류 차단 '
                '(hasEmail: ${e.email?.isNotEmpty ?? false}, '
                'hasCredential: ${e.credential != null})',
              );
            }
            // pendingCredential 은 넘기지 않는다 — Apple credential 은 요청
            // 1회용 nonce 에 묶여 있어 나중에 재제출할 수 없다.
            return Result.failure(
              await _enrichAccountExistsAsync(
                AccountExistsWithDifferentCredential(email: e.email, cause: e),
              ),
            );
          }
          if (e.code != 'credential-already-in-use') {
            rethrow;
          }
          // Quick 260503-ang: 1차 linkWithProvider 의 credential 을 보존해
          // signInWithCredential 로 재사용한다. Apple OAuth Custom Tab(Android) /
          // ASAuthorizationController 시트(iOS) 가 두 번 열리는 UX 결함 차단.
          // e.credential 이 null 인 이론적 fallback 만 signInWithProvider 재호출.
          // credential-already-in-use 는 이 Apple 계정이 이미 연결된 사용자가
          // 있어 로그인이 provider 일치 분기로 끝난다 (email 합류 분기 아님).
          final pendingCredential = e.credential;
          if (kDebugMode) {
            debugPrint(
              'AuthRepository.signInWithApple: ${e.code} '
              '— 익명 계정 폐기 + 기존 Apple 계정 로그인 '
              '(credential reuse: ${pendingCredential != null})',
            );
          }
          // D-09 순서 유지 (SLP-8a).
          await _safeDelete(anonymous);
          if (pendingCredential != null) {
            userCredential = await _auth.signInWithCredential(
              pendingCredential,
            );
          } else {
            userCredential = await _auth.signInWithProvider(provider);
          }
        }
      } else {
        userCredential = await _auth.signInWithProvider(provider);
      }

      final fbUser = userCredential.user;
      if (fbUser == null) {
        return const Result.failure(ServiceUnavailable());
      }
      // Phase 16.7 D-14: isLinkedFromAnonymous 는 fallback 뒤에도 true 라 쓰지
      // 않는다. link 분기는 isNewUser=false 라(Gap A) link 성공과 OR 한다.
      // D-17: 서버 ack 를 기다리지 않는다 — recorder 가 모든 예외를 흡수한다.
      final isSignUp =
          didLinkAnonymous ||
          (userCredential.additionalUserInfo?.isNewUser ?? false);
      if (isSignUp) {
        unawaited(
          _recordSignUpMethod(fbUser.uid, fb.AppleAuthProvider.PROVIDER_ID),
        );
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
      // D2 B1: 소셜 invalid-credential 은 email 문구로 새지 않게 분리한다.
      return Result.failure(
        await _enrichAccountExistsAsync(_mapSocialAuthException(e)),
      );
    } on Object catch (e, st) {
      // 비-Auth 예외 (PlatformException 등)를 Result로 감싸
      // Notifier state가 AsyncLoading에 고정되는 것을 방지한다.
      if (kDebugMode) {
        debugPrint('signInWithApple 비-Auth 예외: ${e.runtimeType}\n$st');
      }
      return Result.failure(ServiceUnavailable(cause: e));
    } finally {
      _socialLinkInProgress.end();
    }
  }

  /// Facebook 계정으로 Firebase Auth에 로그인한다 (D-01).
  ///
  /// [FacebookAuth.login]으로 로그인하고 (D-03), [_facebookCredentialOf] 가
  /// 토큰 타입별로 만든 credential 을 [fb.FirebaseAuth.signInWithCredential]
  /// 에 전달한다. Android 는 [ClassicToken] →
  /// [fb.FacebookAuthProvider.credential] 이고, iOS 는 ATT 미허용 시 SDK 가
  /// Limited Login 으로 강제해 [LimitedToken] (OIDC JWT) →
  /// `OAuthProvider('facebook.com')` idToken + rawNonce credential 이다
  /// (debug ios-facebook-limited-login). Limited 에서는 Graph API 사진
  /// 갱신을 생략한다 (문서화된 한계).
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
  /// 위 순서는 [ClassicToken] credential 기준이다. iOS Limited Login
  /// credential 은 nonce 가 요청 1회용이라 [_signInAfterLimitedLinkConflict]
  /// 가 재시도 credential 을 새로 확보하고, `email-already-in-use` 는 익명을
  /// 유지한 채 signIn 한다 (debug ios-facebook-limited-login stage 2).
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
      // D1 A1: 로그인 + 토큰 타입별 credential 변환은 [_facebookCredentialOf]
      // 단일 진실원. WR-02: 취소만 silent null, 실패는 ServiceUnavailable 로
      // 승격한다 (아래 on ServiceUnavailable 이 흡수).
      final facebook = await _facebookCredentialOf();
      if (facebook == null) {
        return null; // D-09 silent cancel
      }
      final credential = facebook.credential;

      final anonymous = _auth.currentUser;
      // Gap A close (HUMAN-UAT 2026-05-11): success path 합류 후 익명 분기 정보
      // 보존. helper 의 isLinkedFromAnonymous 명시 인자로 D-20 우회.
      // Phase 17 (Account Linking) — see ROADMAP.md.
      final isLinkedFromAnonymous = anonymous != null && anonymous.isAnonymous;
      // Phase 16.7 D-14: link 가 정상 반환한 분기에서만 true (fallback 은 false).
      var didLinkAnonymous = false;
      fb.UserCredential userCredential;
      if (anonymous != null && anonymous.isAnonymous) {
        // Phase 10 D-14 / BLOCKER #4: 익명 → 정식 승격.
        try {
          userCredential = await anonymous.linkWithCredential(credential);
          didLinkAnonymous = true;
        } on fb.FirebaseAuthException catch (e) {
          if (kDebugMode) {
            // D9 (debug ios-facebook-limited-login stage 2): 실기기 재검증에서
            // 실제 link 실패 code 를 인용하는 영구 근거. PII invariant — code
            // 와 credential 유무 bool 만 (e.email · e.message · credential
            // 본문 비포함).
            debugPrint(
              'AuthRepository.signInWithFacebook: link 실패 '
              'code=${e.code}, hasCredential=${e.credential != null}',
            );
          }
          if (e.code != 'credential-already-in-use' &&
              e.code != 'email-already-in-use') {
            rethrow;
          }
          if (facebook.isLimited) {
            // D8 a: nonce 가 묶인 Limited credential 만 재시도 규칙이 다르다
            // (link 에 제출한 credential 재사용 금지).
            final retried = await _signInAfterLimitedLinkConflict(e, anonymous);
            if (retried == null) {
              return null; // D6: 두 번째 Facebook 창 취소 — 익명 보존
            }
            userCredential = retried;
          } else {
            // Classic (Android · iOS ATT 허용) — access token credential 에는
            // nonce 가 묶이지 않아 재제출이 허용되므로 같은 credential 을
            // 재사용한다 (로그인 *요청* 에는 Android 도 nonce 가 실린다 —
            // [_facebookCredentialOf] 「Android」 절).
            // 단 **삭제 시점**은 link 오류 code 로 갈린다: Limited arm 의
            // [_signInAfterLimitedLinkConflict] 가 이미 쓰는 구분을 이식했다
            // (debug android-classic-anon-conflict — 종전 D8 a 는 두 code 를
            // 뭉쳐 항상 삭제 선행이었다).
            final isEmailConflict = e.code == 'email-already-in-use';
            // 로그는 실제 code 를 출력한다 (이전엔 두 code 모두
            // credential-already-in-use 로 오표기).
            if (kDebugMode) {
              debugPrint(
                'AuthRepository.signInWithFacebook: ${e.code} '
                '${isEmailConflict ? '— 익명 유지 + 기존 계정 로그인' : '— 익명 계정 폐기 + 기존 Facebook 계정 로그인'}',
              );
            }
            if (!isEmailConflict) {
              // credential-already-in-use — facebook.com 사용자가 이미 있어
              // 같은 credential signIn 이 성공한다. D-09 순서 유지 (SLP-9).
              await _safeDelete(anonymous);
            }
            // email-already-in-use 는 익명을 유지한 채 signIn 한다. 서버가
            // account-exists 로 거부해도 currentUser 가 익명으로 남아 상위
            // catch 의 lookupSignInMethods(request.auth 필수) 가 인증을 통과해
            // AccountLinkingSheet 입력을 채운다. 삭제를 먼저 하면 callable 이
            // unauthenticated 로 실패해 시트 대신 unknown-provider 배너 +
            // 로그아웃 + 익명 손실로 끝난다.
            userCredential = await _auth.signInWithCredential(credential);
          }
        }
      } else {
        userCredential = await _auth.signInWithCredential(credential);
      }

      final fbUser = userCredential.user;
      if (fbUser == null) {
        return const Result.failure(ServiceUnavailable());
      }
      // Phase 16.7 D-14: isLinkedFromAnonymous 는 fallback 뒤에도 true 라 쓰지
      // 않는다. link 분기는 isNewUser=false 라(Gap A) link 성공과 OR 한다.
      // D-17: 서버 ack 를 기다리지 않는다 — recorder 가 모든 예외를 흡수한다.
      final isSignUp =
          didLinkAnonymous ||
          (userCredential.additionalUserInfo?.isNewUser ?? false);
      if (isSignUp) {
        unawaited(
          _recordSignUpMethod(fbUser.uid, fb.FacebookAuthProvider.PROVIDER_ID),
        );
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
      // D4 Da: Limited Login 토큰은 Graph API 를 쓸 수 없다 (Facebook 공식
      // "The ID token cannot be used to request additional data using the
      // Graph API"). 실패가 확정된 getUserData 왕복을 race-fix 창에서
      // 생략한다 — Limited 에서 photoURL 미갱신은 문서화된 한계.
      if (!facebook.isLimited) {
        await _setFacebookPhotoUrl(fbUser);
      }
      return Result.success(_mapFirebaseUser(fbUser));
    } on fb.FirebaseAuthException catch (e) {
      // Phase 16 D-12 wiring — account-exists 시 provider enrichment.
      // D2 B1: 소셜 invalid-credential 은 email 문구로 새지 않게 분리한다.
      return Result.failure(
        await _enrichAccountExistsAsync(_mapSocialAuthException(e)),
      );
    } on ServiceUnavailable catch (e) {
      // WR-02: [_facebookAccessTokenOf] 의 실패 승격 (status=failed /
      // operationInProgress / success 인데 accessToken 부재) — Custom Token
      // sign-in (kakao / naver / line) 과 동일하게 원본을 cause chain 없이
      // 그대로 보존.
      return Result.failure(e);
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('signInWithFacebook 비-Auth 예외: ${e.runtimeType}\n$st');
      }
      return Result.failure(ServiceUnavailable(cause: e));
    } finally {
      _socialLinkInProgress.end();
    }
  }

  /// iOS Limited Login 익명 승격 link 가 계정 충돌로 거부된 뒤 재시도
  /// sign-in 을 수행한다 (debug ios-facebook-limited-login stage 2 — D6 A+B ·
  /// D7 b).
  ///
  /// **왜 link 에 쓴 credential 을 다시 쓰지 않나:** Limited credential 은
  /// idToken + rawNonce 가 묶인 OIDC credential 이고, Firebase 서버는 link 와
  /// sign-in 을 별개 요청으로 보아 이미 쓴 nonce 를 거부한다
  /// (`missing-or-invalid-nonce` — iOS 실기기 run-02 관측, firebase-ios-sdk
  /// #4434 기여자 발언). 재시도 credential 은:
  /// 1. [fb.FirebaseAuthException.credential] — 서버가 충돌 응답에 실어 준
  ///    updatedCredential (pendingToken 기반, rawNonce 없음) 을 우선한다
  ///    (D6 B).
  /// 2. 없으면 [_facebookCredentialOf] 로 새 raw nonce 재로그인한다 (D6 A).
  ///    iOS `email-already-in-use` 는 SDK 가 credential 을 붙이지 않으므로
  ///    (`AuthBackend.swift:341-342`) 항상 이 경로라 Facebook 창이 한 번 더
  ///    열린다.
  ///
  /// 두 경우 모두 **익명 삭제보다 먼저** 확보해, 두 번째 창 취소 · 로그인
  /// 실패가 익명 계정을 지우지 않게 한다.
  ///
  /// **code 별 순서:**
  /// - `email-already-in-use` (D7 b) — 익명을 지우지 않은 채 signIn 한다.
  ///   Facebook 은 untrusted provider 라 같은 이메일 계정이 있으면 서버가
  ///   account-exists 로 거부하고, 이 throw 는 currentUser 전환 전이라 익명
  ///   caller 가 유지된다 → 상위 catch 의 `lookupSignInMethods` (request.auth
  ///   필수) 가 인증을 통과해 AccountLinkingSheet 입력을 채운다. 삭제를 먼저
  ///   하면 callable 이 unauthenticated 로 실패해 시트 대신 unknown-provider
  ///   배너 + 로그아웃 + 익명 손실로 끝난다.
  ///   **trade-off:** 재시도 signIn 이 성공하면 익명 계정을 삭제하지 않는다.
  ///   plugin 의 delete 는 `currentUser` (= 방금 로그인한 Facebook 계정) 를
  ///   지우므로 전환 뒤에는 익명 User 를 지울 수단이 없다 — 익명 사용자는
  ///   Auth 원장에 고아로 남는다 (앱 입장의 데이터 손실 범위는 D-09 와 같음).
  /// - `credential-already-in-use` — facebook.com 사용자가 이미 있어 그
  ///   credential 로 로그인이 성공하는 경로라 기존 D-09 순서 (익명 삭제 →
  ///   signIn) 를 유지한다 ([signInWithApple] updatedCredential 재사용 선례).
  ///
  /// 반환:
  /// - [fb.UserCredential] — 재시도 sign-in 성공.
  /// - `null` — 두 번째 Facebook 창에서 사용자 취소 (익명 보존, delete 0).
  ///
  /// Throws [fb.FirebaseAuthException] — 재시도 sign-in 거부 (상위 catch 가
  /// 매핑). Throws [ServiceUnavailable] — 재로그인 실패
  /// ([_facebookCredentialOf]).
  Future<fb.UserCredential?> _signInAfterLimitedLinkConflict(
    fb.FirebaseAuthException linkError,
    fb.User anonymous,
  ) async {
    final updatedCredential = linkError.credential;
    final isEmailConflict = linkError.code == 'email-already-in-use';
    if (kDebugMode) {
      // PII invariant: code 와 재사용 여부 bool 만 — email · credential 본문
      // 비포함.
      final action = isEmailConflict
          ? '익명 유지 + 재시도 credential 로 로그인'
          : '익명 계정 폐기 + 기존 Facebook 계정 로그인';
      debugPrint(
        'AuthRepository.signInWithFacebook: Limited ${linkError.code} '
        '— $action (credential reuse: ${updatedCredential != null})',
      );
    }

    // D6 A+B: 재시도 credential 을 삭제보다 먼저 확보한다.
    final fb.AuthCredential retryCredential;
    if (updatedCredential != null) {
      retryCredential = updatedCredential;
    } else {
      final fresh = await _facebookCredentialOf();
      if (fresh == null) return null; // 두 번째 창 취소 — 익명 보존
      retryCredential = fresh.credential;
    }

    if (!isEmailConflict) {
      // credential-already-in-use — D-09 순서 유지.
      await _safeDelete(anonymous);
    }
    // email-already-in-use (D7 b) 는 익명을 유지한 채 signIn 한다. 성공해도
    // 익명 삭제 금지 — 위 docstring trade-off 참조.
    return _auth.signInWithCredential(retryCredential);
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
  /// 실제 link 는 google/apple/facebook 3값 한정. Custom Token 3값
  /// (kakao/naver/line) 은 16-09 책임.
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

      // IN-04 (Phase 7 review): 무검사 `as` 캐스트 제거. 이전엔 null 검사만
      // 있고 타입 검사가 없어, 캐스트 실패 시 TypeError 가 `on Object` 로
      // 흡수돼 ServiceUnavailable ("잠시 후 다시 시도") 로 뭉개졌다 —
      // 재시도로 해소되지 않는 결정적 실패이므로 WR-06 선례대로
      // UnknownException 이다. 또한 캐스트 지점(Step 2)이 아니라 **재인증
      // 이전**에 판정해 무의미한 SDK OAuth 왕복을 회피한다. 프로젝트 규칙
      // (.claude/rules/flutter.md — `as` 캐스팅 최소화, pattern matching
      // 또는 `is` 체크) 정합.
      if (pendingCredential is! fb.AuthCredential) {
        return const Result.failure(UnknownException());
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
        linked = await currentUser.linkWithCredential(pendingCredential);
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
        debugPrint(
          'linkPendingNativeCredential 비-Auth 예외: ${e.runtimeType}\n$st',
        );
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
  /// 및 Custom Token 3값은 호출처에서 사전 분기되므로 본 helper 에 도달하지
  /// 않는다 — exhaustive switch 의 잔여 case 는 `null` 로 graceful fallback.
  Future<fb.AuthCredential?> _reauthNativeCredential(
    AccountProvider existingProvider,
  ) async {
    switch (existingProvider) {
      case AccountProvider.google:
        try {
          final account = await _googleSignIn.authenticate();
          // WR-01: idToken null/empty 가드 — 설정 오류를 빈 credential 대신
          // [ServiceUnavailable] 로 노출 (호출부 on Object 가 Failure 로 흡수).
          return _googleCredentialOf(account);
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
        // D1 A1: signIn · proactive link 와 같은 helper — iOS Limited Login
        // 토큰도 OIDC credential 로 변환된다. WR-02: 취소만 null (no-op),
        // 실패는 ServiceUnavailable throw (호출부 on Object 가 Failure 로
        // 흡수) — silent no-op 회피.
        final facebook = await _facebookCredentialOf();
        return facebook?.credential;
      case AccountProvider.email:
      case AccountProvider.kakao:
      case AccountProvider.naver:
      case AccountProvider.line:
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
        // WR-01: idToken null/empty 가드 — 설정 오류를 빈 credential 대신
        // [ServiceUnavailable] 로 노출 (래퍼 on Object 가 Failure 로 흡수).
        credential = _googleCredentialOf(account);
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
  /// [_facebookCredentialOf] (email + public_profile, 토큰 타입별 credential —
  /// iOS Limited Login 은 OIDC) 로 fresh credential 획득 후
  /// `_auth.currentUser.linkWithCredential(facebookCredential)`. 사용자 취소
  /// (status != success) 또는 accessToken null 시 `null` 반환 (no-op).
  ///
  /// 흐름 / 반환 시맨틱은 [linkGoogleCredential] 참조 (native — callable 미호출).
  Future<Result<User>?> linkFacebookCredential() {
    return _runProactiveNativeLink(() async {
      // D1 A1: 토큰 타입별 credential 변환 단일 진실원. WR-02: 취소만 null
      // (no-op), 실패는 ServiceUnavailable throw (래퍼 on Object 가 Failure
      // 로 흡수) — silent no-op 회피.
      final facebook = await _facebookCredentialOf();
      if (facebook == null) return null;
      final currentUser = _auth.currentUser;
      if (currentUser == null) return null;
      return currentUser.linkWithCredential(facebook.credential);
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
      // PII invariant (T-16-15-01): code 만 — email / e.credential / token 본문
      // 비포함. G-16-A6-2 (2026-09-07 A6) 에서 본 분기가 로그 0 이라 실 단말
      // logcat 만으로 원인 특정이 불가능했다. linkCustomTokenProviderArm(1004~)
      // 및 settings_repository(66~) 의 code-only 형식 mirror.
      if (kDebugMode) {
        debugPrint('proactive native link 실패: code=${e.code}');
      }
      return Result.failure(_mapProactiveLinkException(e));
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('proactive native link 비-Auth 예외: ${e.runtimeType}\n$st');
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
  /// - 그 외 → [_mapAuthException] (기존 표준 매핑 재사용). 위임 결과 중
  ///   하류가 실제로 구분하는 3 코드: `email-already-in-use` →
  ///   [EmailAlreadyInUse], `network-request-failed` → [NoInternetConnection],
  ///   `too-many-requests` → [TooManyRequests].
  ///
  /// **하류 계약 (G-16-A6-2):** `SettingsNotifier._dispatchLink` 가 본 메서드가
  /// 만든 [AppException] 서브타입을 원인별 `AccountLinkOutcome`
  /// (alreadyLinked / emailInUse / transientFailure / reauthRequired / failed)
  /// 으로 type-pattern 분기하고, Surface D 위젯이 outcome 별 전용 문구를
  /// 렌더한다. 따라서 본 매퍼의 서브타입 선택은 사용자 노출 문구를 직접
  /// 결정한다 — arm 을 넓히거나 좁힐 때 하류 매핑을 함께 확인할 것.
  AppException _mapProactiveLinkException(fb.FirebaseAuthException e) {
    return switch (e.code) {
      'requires-recent-login' => ReauthenticationRequiredException(cause: e),
      // WR-04: 의미가 정반대인 두 코드를 분리한다. 하나로 뭉개면 Surface D
      // 문구가 한쪽에는 사실과 반대 ("다른 계정에 연결됨"), 다른 쪽에는
      // 수행 불가능한 안내 ("먼저 해제하세요" — 다른 계정 소유주만 가능) 가
      // 된다.
      // - `provider-already-linked`: 해당 provider 가 **현재 계정에** 이미 연결.
      'provider-already-linked' => ProviderAlreadyLinkedToThisAccount(cause: e),
      // - `credential-already-in-use`: 해당 자격증명이 **다른 계정에** 연결.
      'credential-already-in-use' => AccountAlreadyLinked(cause: e),
      _ => _mapAuthException(e),
    };
  }

  /// Custom Token provider (Kakao/LINE) reactive link arm (Phase 16 16-09).
  ///
  /// Custom Token 계정 충돌 (account-exists) 직후 [AccountLinkingSheet] 에서
  /// 사용자가 기존-provider 버튼을 탭하면 본 메서드가 호출된다. 흐름
  /// (RESEARCH § reactive Custom Token data flow + Pattern 2):
  /// 1. [SocialLinkInProgress.begin] (Phase 9.1 D-22 race-fix invariant) —
  ///    try-finally 로 [SocialLinkInProgress.end] 1:1 보장.
  /// 2. caller 결정적 실패 검사 — `currentUser == null` · `isAnonymous` 면
  ///    SDK 왕복 전에 [UnknownException] (16.9 review IN-02 — 재시도로 해소
  ///    되지 않는 실패를 target 인증을 마친 뒤에 알리지 않는다).
  /// 3. [targetProvider] 별 SDK signIn 으로 **target OIDC 토큰 fresh 재획득**
  ///    (kakao→[KakaoSdkClient.signIn], line→[LineSdkClient.signIn]).
  ///    사용자 취소 (null) 시 `null` 반환
  ///    (silent — linkedProviders 변경 0).
  /// 4. SDK 왕복 뒤 caller 재확인 ([_readUnchangedCaller]) — current user 가
  ///    null · 익명 · 2 단계와 다른 uid 로 바뀌었으면 [UnknownException]
  ///    (16.9 review iteration 2 WR-01). 통과하면 `getIdToken(true /*
  ///    forceRefresh */)` 로 caller fresh ID Token 발급 — signIn **뒤** 에
  ///    둔다 (server-side auth_time 5분 boundary 는 SDK 왕복 시간을 뺀 뒤에
  ///    재야 한다).
  /// 5. `_functions.httpsCallable('linkCustomTokenProvider')` 호출 —
  ///    deployed contract `{idToken, targetProvider, targetProviderToken,
  ///    nonce} → {ok:true}` (link_custom_token_provider.ts line 67~80 verbatim).
  /// 6. `{ok:true}` 검증 후 `_auth.currentUser` reload → [_mapFirebaseUser].
  /// 7. finally 에서 target SDK logout (1회성 토큰 정책 —
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
  /// **targetProvider 제약:** kakao/line(OIDC ID token) 전용 — naver 는
  /// [linkNaverProviderArm] 이 access token/code 로 맡는다(16.9 D-01).
  /// native 는 `link*Credential` 이 맡는다. 그 외 입력은 [ArgumentError] throw.
  ///
  /// 에러 매핑 ([_mapLinkCallableException] — [linkNaverProviderArm] 과 공용 ·
  /// 16.9 review WR-01):
  /// - `unauthenticated` + `details.reason == 'reauthentication_required'`
  ///   (auth_time 초과 / verifyIdToken 실패) · `permission-denied` (idToken
  ///   uid 불일치) →
  ///   [ReauthenticationRequiredException] (재로그인 유도).
  /// - reason 없는 `unauthenticated` (Kakao/LINE ID token 거부 · App Check
  ///   차단) → [_mapFunctionsException] 의 [ServiceUnavailable] (일시 오류).
  /// - `already-exists` + reason `provider_already_linked` →
  ///   [ProviderAlreadyLinkedToThisAccount] (같은 provider 의 다른 신원이 이미
  ///   이 계정에 연결 — 16.9 review IN-03).
  /// - `already-exists` → [AccountAlreadyLinked] (identity_index 이미 존재).
  /// - 그 외 (`failed-precondition` 익명 caller / `invalid-argument` 등) →
  ///   [_mapFunctionsException] (적절 [AppException]).
  ///
  /// **구조적(결정적) 실패는 [UnknownException] 이다 (WR-06).** caller 부재 /
  /// 익명 caller / SDK 왕복 중 caller 교체 / `getIdToken` null / 응답
  /// `ok != true` 는 재시도로 해소되지 않는다. [ServiceUnavailable] 로 두면 하류 `SettingsNotifier._mapLinkFailure`
  /// 가 [AccountLinkOutcome.transientFailure] ("잠시 후 다시 시도해 주세요") 로
  /// 안내해 사용자가 매 시도마다 SDK OAuth 왕복을 반복하는 무한 루프에 든다.
  /// [ServiceUnavailable] 은 실제 서비스 **도달** 실패에만 남긴다.
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
    // deployed callable 미지원 target 사전 차단 (kakao/line 만 허용).
    if (targetProvider != AccountProvider.kakao &&
        targetProvider != AccountProvider.line) {
      throw ArgumentError.value(
        targetProvider,
        'targetProvider',
        'linkCustomTokenProvider 는 kakao/line 만 지원 '
            '(naver 는 linkNaverProviderArm, native 는 link*Credential).',
      );
    }
    try {
      _socialLinkInProgress.begin(); // race-fix Pitfall 8 단일 진실원

      // Step 2 — caller 결정적 실패 검사. SDK 호출과 의존 관계가 없으므로
      // target OAuth 왕복 **앞** 에 둔다 (16.9 review IN-02 — 이전에는
      // 인증을 마친 뒤에야 「연결 실패」 를 보였다).
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        // WR-06: 재시도로 해소되지 않는 **결정적** 실패다. ServiceUnavailable
        // 로 두면 하류 _mapLinkFailure 가 transientFailure ("잠시 후 다시
        // 시도해 주세요") 로 안내해 사용자를 무한 재시도 루프 (매 시도마다
        // SDK OAuth 왕복) 에 몰아넣는다. UnknownException → failed.
        return const Result.failure(UnknownException());
      }
      // WR-06: client-side 익명 caller 가드 (defense-in-depth). reactive
      // collision arm 의 caller 는 구조상 fresh collided sign-in 이므로
      // 익명일 수 없다 — 익명 도달은 upstream 로직 오류 신호다. 서버
      // `failed-precondition` 거부에만 의존하지 않고 client 에서 loud
      // fail 하여 불필요한 SDK · callable round-trip 을 회피한다 (proactive
      // arm / deployed callable 익명 차단 mirror).
      if (currentUser.isAnonymous) {
        // WR-06: 결정적 실패 — 재시도 유도 금지 (currentUser==null 동일).
        return const Result.failure(UnknownException());
      }

      // Step 3 — target OIDC 토큰 fresh 재획득 (1회성 정책). 사용자 취소 시
      // null silent return.
      final targetToken = await _acquireTargetProviderToken(targetProvider);
      if (targetToken == null) return null; // 사용자 취소 — no-op.

      // Step 3-1 — WR-06 재확인 (16.9 review iteration 2 WR-01). SDK 왕복
      // 동안 세션이 바뀌었으면 (sign-out · 익명 재진입 · 다른 계정) 결정적
      // 실패다. `User.getIdToken` 은 캡처한 객체가 아니라 호출 시점의
      // native current user 토큰을 만들므로, 캡처 객체만 믿으면 이 실패가
      // 서버 왕복 + transientFailure 로 흘러간다.
      final caller = _readUnchangedCaller(currentUser.uid);
      if (caller == null) {
        // WR-06: 결정적 실패 — 재시도 유도 금지 (왕복 전 검사와 같은 판정).
        return const Result.failure(UnknownException());
      }

      // Step 3-2 — caller fresh ID Token (forceRefresh=true). signIn 뒤에
      // 발급해야 server-side auth_time 5분 boundary 가 SDK 왕복 시간을
      // 잡아먹지 않는다.
      final callerIdToken = await caller.getIdToken(true);
      if (callerIdToken == null) {
        // WR-06: 결정적 실패 — 재시도 유도 금지.
        return const Result.failure(UnknownException());
      }

      // Step 4 — deployed linkCustomTokenProvider callable 호출.
      final callable = _functions.httpsCallable(
        'linkCustomTokenProvider',
        options: HttpsCallableOptions(timeout: _kCustomTokenTimeout),
      );
      final response = await callable
          .call<Map<String, dynamic>>(<String, dynamic>{
            'idToken': callerIdToken,
            'targetProvider': targetProvider.slug,
            'targetProviderToken': targetToken.idToken,
            'nonce': targetToken.nonce,
          });

      // Step 5 — {ok:true} 검증 후 reload → 도메인 User.
      final ok = response.data['ok'] == true;
      if (!ok) {
        // WR-06: 서버 계약 위반 (도달은 성공했으나 ok != true) — 재시도로
        // 해소되지 않는다. ServiceUnavailable 은 실제 서비스 **도달** 실패
        // (unavailable / deadline-exceeded) 에만 남긴다.
        return const Result.failure(UnknownException());
      }
      await caller.reload();
      final refreshed = _auth.currentUser ?? caller;
      return Result.success(_mapFirebaseUser(refreshed));
    } on FirebaseFunctionsException catch (e) {
      // 16.9 review WR-01: 연결 callable 공용 판정 — 재로그인은 서버가
      // details.reason 으로 표시한 거부에만 (IdP 거부 · App Check 차단 제외).
      return Result.failure(_mapLinkCallableException(e));
    } on fb.FirebaseAuthException catch (e) {
      return Result.failure(_mapAuthException(e));
    } on ServiceUnavailable catch (e) {
      // target SDK 가 OIDC scope 누락 등으로 ServiceUnavailable throw — Kakao/
      // LINE signIn 과 동일 시맨틱 (Pitfall 1).
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
      // 1회성 토큰 정책 (signInWithKakao/Line finally logout mirror) —
      // Pitfall 2 race-fix end 직전 위치.
      await _logoutTargetProvider(targetProvider);
      _socialLinkInProgress.end();
    }
  }

  /// Naver 계정을 로그인된 현재 계정에 연결한다 — Surface D proactive link arm
  /// (Phase 16.9 D-01 · SOCL-12).
  ///
  /// 흐름 ([linkCustomTokenProviderArm] 골격 mirror):
  /// 1. [SocialLinkInProgress.begin] (race-fix Pitfall 8 단일 진실원) —
  ///    try-finally 로 [SocialLinkInProgress.end] 1:1 보장.
  /// 2. caller 결정적 실패 검사 — `currentUser == null` · `isAnonymous` 면
  ///    NAVER 앱 · 브라우저 왕복 전에 [UnknownException] (16.9 review IN-02).
  /// 3. [NaverSdkClient.signIn] — 경로 선택(설치 판정 · 1-tap/웹) · `state`
  ///    생성/대조 · 취소 처리는 전부 이 호출에서 상속한다(C-02 · 16.5 D-04).
  ///    `null`(사용자 취소 · 재진입) → `null` 반환(no-op).
  /// 4. NAVER 왕복 뒤 caller 재확인 ([_readUnchangedCaller] — null · 익명 ·
  ///    다른 uid 면 [UnknownException], 16.9 review iteration 2 WR-01) →
  ///    caller fresh ID Token (`getIdToken(true)`) — signIn **뒤** 에 발급
  ///    한다(서버 auth_time 5분 boundary 통과 의무).
  /// 5. 결과 variant 로 payload · timeout 을 고른다([_naverLinkPayload]) →
  ///    callable `linkNaverProvider` 호출 → `{ok:true}` 검증 → reload.
  /// 6. finally: [NaverSdkClient.logout] (로컬 SDK 토큰만 — C-05 1회성 토큰
  ///    정책, [signInWithNaver] mirror) + [SocialLinkInProgress.end].
  ///
  /// 가입 수단(`signUpProviderId`) · 프로필 필드는 쓰지 않는다(C-06) — 연결
  /// 원장 기록은 서버 transaction 이 맡는다.
  ///
  /// 에러 매핑 ([_mapLinkCallableException] — [linkCustomTokenProviderArm] 과
  /// 공용 · C-04 · 16.9 review WR-01):
  /// - `unauthenticated` + `details.reason == 'reauthentication_required'` ·
  ///   `permission-denied` → [ReauthenticationRequiredException] (재로그인
  ///   유도).
  /// - reason 없는 `unauthenticated` (Naver `/v1/nid/me` 거부 · code 교환
  ///   `invalid_grant` · App Check 차단) → [ServiceUnavailable] (일시 오류 —
  ///   로그인 경로 [_mapFunctionsException] 과 같은 안내).
  /// - `already-exists` + reason `provider_already_linked` →
  ///   [ProviderAlreadyLinkedToThisAccount] (다른 Naver 신원이 이미 이 계정에
  ///   연결 — 16.9 review IN-03).
  /// - `already-exists` → [AccountAlreadyLinked] (Naver 신원이 다른 계정 소유).
  /// - 그 외 [FirebaseFunctionsException] → [_mapFunctionsException].
  /// - [NaverSdkClient.signIn] 의 [ServiceUnavailable] (SDK/웹 세션 오류) 은
  ///   그대로 전달, 기타 [Object] → [ServiceUnavailable] 단일 매핑.
  ///
  /// **구조적(결정적) 실패는 [UnknownException] 이다 (WR-06).** caller 부재 /
  /// 익명 caller / NAVER 왕복 중 caller 교체 / `getIdToken` null / 응답
  /// `ok != true` 는 재시도로 해소되지 않는다.
  ///
  /// **PII invariant (T-16-09-02 관례):** catch path 의 [debugPrint] 는
  /// runtimeType 만 출력한다 — access token · code · state · idToken · 이메일
  /// 본문은 싣지 않는다.
  ///
  /// 반환:
  /// - `Result.success(User)` — 연결 성공.
  /// - `Result.failure(...)` — callable 거부 / reauth 초과 / 다른 계정 소유.
  /// - `null` — Naver SDK 단계 사용자 취소 (no-op).
  Future<Result<User>?> linkNaverProviderArm() async {
    try {
      _socialLinkInProgress.begin(); // race-fix Pitfall 8 단일 진실원

      // 16.9 review IN-02: 결정적 caller 실패는 NAVER 왕복 **앞** 에서 검사
      // 한다 — SDK 호출과 의존 관계가 없고, 익명 사용자가 브라우저 인증을
      // 마친 뒤에야 「연결 실패」 를 보는 일을 막는다.
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        // WR-06: 결정적 실패 — 재시도 유도 금지.
        return const Result.failure(UnknownException());
      }
      if (currentUser.isAnonymous) {
        // WR-06: 익명 caller 는 연결 불가 — SDK · 서버 왕복 전에 loud fail.
        return const Result.failure(UnknownException());
      }

      // C-02 — 1-tap/웹 라우팅 · state · 취소는 signIn() 계약을 상속한다.
      final result = await _naverSdkClient.signIn();
      if (result == null) return null; // 사용자 취소 — no-op.

      // WR-06 재확인 (16.9 review iteration 2 WR-01) — NAVER 왕복 동안 세션이
      // 바뀌었으면 결정적 실패다. `User.getIdToken` 은 호출 시점의 native
      // current user 토큰을 만들므로 캡처 객체만 믿지 않는다
      // ([linkCustomTokenProviderArm] mirror).
      final caller = _readUnchangedCaller(currentUser.uid);
      if (caller == null) {
        // WR-06: 결정적 실패 — 재시도 유도 금지.
        return const Result.failure(UnknownException());
      }

      // signIn 뒤에 발급 — 서버 auth_time 5분 boundary 가 NAVER 왕복 시간을
      // 잡아먹지 않는다.
      final callerIdToken = await caller.getIdToken(true);
      if (callerIdToken == null) {
        // WR-06: 결정적 실패 — 재시도 유도 금지.
        return const Result.failure(UnknownException());
      }

      final request = _naverLinkPayload(result, callerIdToken);
      final callable = _functions.httpsCallable(
        'linkNaverProvider',
        options: HttpsCallableOptions(timeout: request.timeout),
      );
      final response = await callable.call<Map<String, dynamic>>(
        request.payload,
      );

      if (response.data['ok'] != true) {
        // WR-06: 서버 계약 위반 (도달은 성공했으나 ok != true).
        return const Result.failure(UnknownException());
      }
      await caller.reload();
      return Result.success(_mapFirebaseUser(_auth.currentUser ?? caller));
    } on FirebaseFunctionsException catch (e) {
      // 16.9 review WR-01: [linkCustomTokenProviderArm] 과 같은 공용 판정 —
      // Naver 거부(`/v1/nid/me` 401 · code 교환 invalid_grant) · App Check
      // 차단은 재로그인이 아니라 일시 오류다.
      return Result.failure(_mapLinkCallableException(e));
    } on fb.FirebaseAuthException catch (e) {
      return Result.failure(_mapAuthException(e));
    } on ServiceUnavailable catch (e) {
      // NaverSdkClient.signIn 의 SDK/웹 세션 오류 — 원본 보존.
      return Result.failure(e);
    } on Object catch (e) {
      // PII invariant: runtimeType 만 — 토큰 · code · state · 이메일 비포함.
      if (kDebugMode) {
        debugPrint(
          'linkNaverProviderArm 비-Functions 예외: '
          'runtimeType=${e.runtimeType}',
        );
      }
      return Result.failure(ServiceUnavailable(cause: e));
    } finally {
      // C-05 — 모든 경로에서 로컬 SDK 토큰 정리 (signInWithNaver mirror).
      await _naverSdkClient.logout();
      _socialLinkInProgress.end();
    }
  }

  /// SDK 왕복 뒤 current user 가 왕복 전 [expectedUid] 의 정식 계정 그대로면
  /// 그 [fb.User] 를, 아니면 `null` 을 돌려준다 — 두 연결 arm 공용
  /// (16.9 review iteration 2 WR-01).
  ///
  /// NAVER · Kakao · LINE 왕복(수십 초~분) 동안 SDK 가 세션을 끊고 Splash 가
  /// 익명으로 재진입하거나 다른 계정으로 바뀔 수 있다. `User.getIdToken` 은
  /// 캡처한 객체가 아니라 호출 시점의 native current user 토큰을 만들므로
  /// (firebase_auth 6.7.0 — Android `getCurrentUserFromPigeon` · iOS
  /// `getFIRAuthFromPigeon(app).currentUser`), 왕복 전에 캡처한 객체로 토큰을 받으면 익명 caller 는
  /// 서버 `failed-precondition` → transientFailure(WR-06 위반), 다른 계정은
  /// 사전 검사하지 않은 계정에 연결된다. network 비용 없는 동기 읽기다.
  fb.User? _readUnchangedCaller(String expectedUid) {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous || user.uid != expectedUid) {
      return null;
    }
    return user;
  }

  /// 연결 callable(`linkCustomTokenProvider` · `linkNaverProvider`) 거부를
  /// [AppException] 으로 매핑한다 — 두 link arm 의 단일 진실원
  /// (Phase 16.9 review WR-01).
  ///
  /// 서버 `unauthenticated` 는 재인증 필요 외에도 IdP 자격증명 거부
  /// (`idpCredentialRejected` — Naver `/v1/nid/me` 401 · `resultcode != 00` ·
  /// code 교환 `invalid_grant` · Kakao/LINE ID token 검증 실패) · App Check
  /// 차단 · auth token 무효(firebase-functions 7.2.5 — details 없음)가 함께
  /// 쓴다. code 만 보고 재로그인으로 보내면 Firebase 세션이 정상인데도
  /// 「보안을 위해 다시 로그인」 안내 + 로그인 화면 이동이 되고, 재로그인
  /// 뒤에도 같은 원인이면 같은 결과가 반복된다. 그래서:
  ///
  /// 1. `unauthenticated` + `details.reason == 'reauthentication_required'` →
  ///    [ReauthenticationRequiredException] (서버 `reauthenticationRequired()`
  ///    — `verifyIdToken(checkRevoked)` 실패 · `assertFreshAuth`). 다른 code
  ///    에 같은 reason 이 실려도 재로그인으로 보내지 않는다(code anchor —
  ///    16.9 review iteration 2 IN-01).
  /// 2. `permission-denied` (`caller_identity_mismatch` 아님) →
  ///    [ReauthenticationRequiredException]. 두 연결 callable 의
  ///    `permission-denied` 출처는 idToken uid ≠ `request.auth.uid` 하나뿐이다
  ///    (App Check 차단 · auth 무효는 `unauthenticated`, firebase-functions 의
  ///    `permission-denied` 는 킷 미사용 `authPolicy` 전용). 같은 기기의 같은
  ///    `currentUser` 에서 두 값을 만들므로 불일치는 세션이 흔들린 상태이고,
  ///    재로그인이 세션을 다시 맞추는 해소책이다.
  /// 3. `already-exists` + `details.reason == 'provider_already_linked'` →
  ///    [ProviderAlreadyLinkedToThisAccount] (같은 provider 의 다른 신원이
  ///    **이 계정에** 이미 연결 — 16.9 review IN-03 · Firebase
  ///    `provider-already-linked` mirror). 아래 4 와 code 를 공유하지만 의미가
  ///    정반대이므로 반드시 먼저 판정한다.
  /// 4. `already-exists` (reason 없음) → [AccountAlreadyLinked] (신원이 다른
  ///    계정 소유).
  /// 5. 나머지 → [_mapFunctionsException] — reason 없는 `unauthenticated` 는
  ///    로그인 경로와 같은 [ServiceUnavailable] (하류
  ///    `SettingsNotifier._mapLinkFailure` → transientFailure 「잠시 후 다시
  ///    시도」), `unavailable` → [NoInternetConnection], `failed-precondition`
  ///    (익명 caller) · `invalid-argument` → [ServiceUnavailable].
  ///
  /// 서버 message 는 읽지 않는다 — `code` + `details.reason` 만 분기한다.
  AppException _mapLinkCallableException(FirebaseFunctionsException e) {
    // 16.9 review iteration 2 IN-01: code 가 1차 축 · reason 은 그 안의 2차
    // 축이다 (아래 provider_already_linked 판정과 같은 규칙) — reauth reason
    // 은 서버 `reauthenticationRequired()` 가 만드는 `unauthenticated` 에서만
    // 읽는다.
    if ((e.code == 'unauthenticated' &&
            _isReauthRequiredRejection(e.details)) ||
        (e.code == 'permission-denied' &&
            !_isCallerIdentityMismatch(e.details))) {
      return ReauthenticationRequiredException(cause: e);
    }
    if (e.code == 'already-exists') {
      // IN-03: 「이 계정에 이미 연결」 (reason) 을 「다른 계정 소유」 보다 먼저.
      return _isProviderAlreadyLinkedRejection(e.details)
          ? ProviderAlreadyLinkedToThisAccount(cause: e)
          : AccountAlreadyLinked(cause: e);
    }
    return _mapFunctionsException(e);
  }

  /// [targetProvider] 별 SDK signIn 으로 target OIDC 토큰을 fresh 재획득한다
  /// (Phase 16 16-09). 사용자 취소 시 `null` 반환.
  ///
  /// 반환 [_TargetProviderToken] 은 `{idToken, nonce}` 묶음 — target Custom
  /// Token SDK 별 result 타입을 단일 인터페이스로 normalize 한다.
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

      final callable = _functions.httpsCallable(
        'kakaoCustomToken',
        options: HttpsCallableOptions(timeout: _kCustomTokenTimeout),
      );
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
        debugPrint('signInWithKakao 비-Auth 예외: ${e.runtimeType}\n$st');
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
  /// (1) SDK = naver_login_flutter (Future 직결 — [NaverSdkClient] wrapper)
  /// (2) Cloud Function 페이로드 = 1-tap `accessToken` 단일 (nonce 부재 —
  ///     D-46) · 킷 웹 `code` + `state` (Phase 16.5 D-13)
  /// (3) Naver 검증 = REST `/v1/nid/me` Bearer (CF 측 — Plan 13-02)
  /// (4) finally 에서 SDK logout (D-57 — 1회성 access_token)
  ///
  /// 흐름:
  /// 1. [SocialLinkInProgress.begin] (race-fix Pitfall 8 — 단일 진실원)
  /// 2. [_naverSdkClient.signIn] — null 반환 (사용자 취소) → null silent (D-45)
  /// 3. 결과 variant 로 callable 을 고른다 (Phase 16.5 D-13 — 재인증과 공유하는
  ///    [_naverCallableRequest] 의 exhaustive switch):
  ///    [NaverAppSignIn] → `naverCustomToken({accessToken})`,
  ///    [NaverWebSignIn] → `naverWebCustomToken({code, state})` (서버가 code 를
  ///    token 으로 교환). 두 callable 모두 REST 검증 + Identity Index
  ///    lookup-first + `createCustomToken` 을 공용 helper 로 수행한다
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
    // — 모든 path 에서 finally logout (D-57). Phase 16.2 D-16 으로 앱 쪽
    // 타이머가 사라져 finally 는 항상 로그인 Future 완료 **뒤에** 실행된다 —
    // 늦은 성공이 logout 이후에 토큰을 저장하는 경로가 구조적으로 없다.
    // NaverSdkClient.logout 은 내부 try/catch graceful — SDK "no session"
    // 상태에서도 silent no-op. Kakao path 와 대칭 (D-57 일관) + 보안 우선 정책.
    try {
      _socialLinkInProgress.begin(); // race-fix Pitfall 8 단일 진실원

      final result = await _naverSdkClient.signIn();
      if (result == null) {
        return null; // D-45 silent
      }

      // Phase 16.5 D-13: 경로별 자격증명 → callable · payload · timeout 은
      // 재인증과 공유하는 단일 진실원 [_naverCallableRequest] 가 고른다.
      final request = _naverCallableRequest(result);
      final callable = _functions.httpsCallable(
        request.callableName,
        options: HttpsCallableOptions(timeout: request.timeout),
      );
      // G-16-A9-1 / D-13: device-local 약관 동의를 add-only 로 동봉한다.
      // base 키(1-tap `accessToken` · 웹 `code`+`state`) 가 다른 것은 provider
      // 계약 차이이며 snapshot 부착 방식은 3 provider 동일하다.
      final response = await callable.call<Map<String, dynamic>>(
        _buildCustomTokenPayload(request.payload),
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
        debugPrint('signInWithNaver 비-Auth 예외: ${e.runtimeType}\n$st');
      }
      return Result.failure(ServiceUnavailable(cause: e));
    } finally {
      // D-57 (Phase 13 — see ROADMAP.md): SDK access_token 1회성 정책.
      // Pitfall 2 — race-fix end 직전 위치. 실패 graceful (NaverSdkClient.logout
      // 내부 try/catch) — outer 흐름 차단 안 함.
      // WR-01-iter2: 취소 · 오류 path 에서도 SDK 측 디바이스 토큰이 잔존할
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

      final callable = _functions.httpsCallable(
        'lineCustomToken',
        options: HttpsCallableOptions(timeout: _kCustomTokenTimeout),
      );
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
      // record 의 email 필드가 비어 있어 [_autoSendEmailVerification] 내부의
      // `email.isEmpty` 가드가 자연 no-op 처리 (IN-02 — 라인 번호 인용
      // 폐기, 심볼 참조로 대체). Kakao/Naver 의
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
        debugPrint('signInWithLine 비-Auth 예외: ${e.runtimeType}\n$st');
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

  /// 기존 provider 로 로그인한다 — reactive 시트 step 1 디스패처
  /// (Phase 16 Plan 16-19).
  ///
  /// **용도 (2단계 플로우 step 1):** 서버 `already-exists` 로 열린
  /// `AccountLinkingSheet` 의 CTA 는 link 가 아니라 **기존 provider 로의
  /// 로그인** 을 수행한다. 충돌 시점의 caller 는 정의상 미로그인이거나 익명
  /// 이므로 link arm (`linkPendingNativeCredential` /
  /// [linkCustomTokenProviderArm]) 은 구조적으로 성공할 수 없다 — 본 메서드가
  /// 그 자리를 대신한다 (mockup `surface-a-two-step-reactive.md` 경로 B).
  ///
  /// **step 2 계약:** 나머지 로그인 수단 추가는 Settings "계정 연결"
  /// (proactive arm — `SettingsNotifier.linkProvider`) 가 담당한다. 본
  /// 메서드는 link 를 수행하지 않으며 자동 연속 link 도 하지 않는다.
  ///
  /// **[AccountProvider.email] 제외 이유:** 이메일 로그인은 비밀번호 입력
  /// 화면이 필요해 bottom sheet 안에서 완결될 수 없다. 호출처가 이미
  /// `/login` 으로 분기하므로 본 메서드 도달은 로직 오류 신호이며
  /// [ArgumentError] 로 loud fail 한다 ([linkCustomTokenProviderArm] 의
  /// `ArgumentError.value` 선례 mirror).
  ///
  /// **[SocialLinkInProgress] 단일 진실원 (Pitfall 8):** 본 메서드는 자체
  /// begin/end 를 추가하지 않는다 — 위임 대상 7 메서드가 이미 진입/`finally`
  /// 에서 1:1 로 관리한다. 여기서 한 겹 더 감싸면 중첩 카운트가 되어 race-fix
  /// invariant 가 깨진다.
  ///
  /// **PII invariant (T-16-19-02):** 본 메서드는 자체 로그를 추가하지 않는다
  /// (위임 대상이 이미 code/runtimeType only 로그 정책을 따른다).
  ///
  /// 반환 3값 (위임 대상의 계약을 그대로 보존):
  /// - `Result.success(User)` — 로그인 성공.
  /// - `Result.failure(...)` — 로그인 실패. 예외 타입도 그대로 전파된다
  ///   (익명 caller 재충돌의 [AccountExistsWithDifferentCredential] 포함).
  /// - `null` — 사용자가 IdP SDK 단계에서 취소 (no-op).
  ///
  /// **`async` 선언 이유 (IN-02, 4차 리뷰):** [AccountProvider.email] arm 의
  /// [ArgumentError] 는 `Future` 반환 API 의 계약대로 **Future 에러**로 전파
  /// 되어야 한다. `async` 가 없으면 동기 throw 가 되어 `.catchError(...)` /
  /// `unawaited(...)` 스타일 호출처에서 잡히지 않는다 (현재 유일 호출처인
  /// 시트는 `await` 이라 무해하지만 계약이 어긋난 상태였다).
  Future<Result<User>?> signInWithExistingProvider({
    required AccountProvider provider,
  }) async {
    return switch (provider) {
      AccountProvider.google => signInWithGoogle(),
      AccountProvider.apple => signInWithApple(),
      AccountProvider.facebook => signInWithFacebook(),
      AccountProvider.kakao => signInWithKakao(),
      // naver 는 로그인 · 연결 모두 지원(연결은 linkNaverProviderArm · 16.9).
      // 이 메서드는 step 1 로그인만 맡는다.
      AccountProvider.naver => signInWithNaver(),
      AccountProvider.line => signInWithLine(),
      AccountProvider.email => throw ArgumentError.value(
        provider,
        'provider',
        'signInWithExistingProvider 는 소셜 6 provider 만 지원 '
            '(email 은 비밀번호 입력 화면이 필요해 sheet 에서 처리 불가 — '
            '호출처가 /login 으로 분기).',
      ),
    };
  }

  /// 현재 로그인한 계정을 [provider] 로 재인증한다 — auth_time 만 갱신하고
  /// 계정은 바꾸지 않는다 (debug reauth-login-auto-merge).
  ///
  /// 재인증 로그인 화면(`/login?reauth=1`)의 소셜 버튼 전용이다. 일반 로그인
  /// ([signInWithApple] 등) 은 비익명 사용자에게 새 로그인이라, 다른 계정으로
  /// 세션이 바뀌거나 같은 email 계정에 trusted provider 가 자동 연결되며
  /// 프로필이 덮어써질 수 있다. 본 메서드는 provider 별로 다음 경로만 쓴다.
  ///
  /// - Google: 계정 선택기가 돌려준 계정 ID 를 현재 계정의 `google.com`
  ///   연결 uid 와 **Firebase 호출 전** 대조한 뒤
  ///   [fb.User.reauthenticateWithCredential]. ID 는 둘 다 Google user ID(sub)
  ///   다 — google_sign_in_android 는 idToken `sub`, iOS 는
  ///   `GIDGoogleUser.userID`, Firebase `UserInfo.getUid()` 는 "Google user ID".
  ///   연결 안 된 계정을 서버에 보내지 않으므로 trusted email 합류 경로가 없다.
  /// - Apple: [fb.User.reauthenticateWithProvider] (호출마다 새 nonce — 실패한
  ///   credential 을 재제출하지 않는다).
  /// - Facebook: 새로 받은 credential 로 [fb.User.reauthenticateWithCredential].
  /// - Custom Token (kakao / naver / line): SDK 토큰 → callable → 응답 uid 가
  ///   현재 uid 와 같을 때만 [fb.FirebaseAuth.signInWithCustomToken]. 서버는
  ///   정식 로그인 caller 의 미매핑 identity 를 `permission-denied` +
  ///   `caller_identity_mismatch` 로 거부한다 (functions `resolveIdentity` 가드).
  ///
  /// native 3종(Google · Apple · Facebook)은 IdP 를 부르기 **전에** 서버 기준으로
  /// 연결을 재확인한다 ([_reloadLinkedNativeUser]) — SDK 캐시 `providerData` 는
  /// 앱 밖에서 해제된 provider 를 계속 담을 수 있다 (실기기 D1).
  ///
  /// 반환:
  /// - `Result.success(User)` — 같은 계정으로 재인증 완료.
  /// - `Result.failure(ReauthUserMismatch)` — 다른 계정 · 연결 안 된 identity.
  /// - `Result.failure(ReauthMethodUnavailable)` — native 재확인 실패 (reload
  ///   실패 · 서버 기준 미연결). IdP 호출 0.
  /// - `Result.failure(...)` — 그 밖의 실패 (네트워크 등).
  /// - `null` — 사용자가 IdP 단계에서 취소 (no-op).
  ///
  /// Throws [ArgumentError] — [AccountProvider.email] (비밀번호 입력이 필요해
  /// [reauthenticateWithPassword] 를 쓴다). `async` 라 Future 에러로 전파된다.
  Future<Result<User>?> reauthenticate(AccountProvider provider) async {
    if (provider == AccountProvider.email) {
      throw ArgumentError.value(
        provider,
        'provider',
        'email 재인증은 reauthenticateWithPassword 를 쓴다.',
      );
    }
    try {
      _socialLinkInProgress.begin(); // race-fix Pitfall 8 단일 진실원
      final current = _auth.currentUser;
      if (current == null || current.isAnonymous) {
        // 재인증 화면은 정식 사용자 전용이다 — 도달은 상위 로직 오류이며
        // 재시도로 풀리지 않는다 (WR-06 원칙).
        return const Result.failure(UnknownException());
      }
      final fb.UserCredential? reauthed = switch (provider) {
        AccountProvider.google => await _reauthWithGoogle(
          await _reloadLinkedNativeUser(current, 'google.com'),
        ),
        AccountProvider.apple => await _reauthWithApple(
          await _reloadLinkedNativeUser(current, 'apple.com'),
        ),
        AccountProvider.facebook => await _reauthWithFacebook(
          await _reloadLinkedNativeUser(current, 'facebook.com'),
        ),
        AccountProvider.kakao ||
        AccountProvider.naver ||
        AccountProvider.line => await _reauthWithCustomToken(provider, current),
        // 위에서 ArgumentError 로 차단 — 도달하지 않는다.
        AccountProvider.email => null,
      };
      if (reauthed == null) return null; // 사용자 취소 — no-op.
      final reauthedUser = reauthed.user;
      if (reauthedUser == null) {
        return const Result.failure(ServiceUnavailable());
      }
      if (reauthedUser.uid != current.uid) {
        // 방어 계층 — SDK user-mismatch · 서버 가드 · 응답 uid 대조가 모두
        // 앞에서 막으므로 정상 경로에서는 도달하지 않는다.
        _logReauthMismatch(provider, 'post-reauth uid');
        return const Result.failure(ReauthUserMismatch());
      }
      return Result.success(_mapFirebaseUser(reauthedUser));
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      return Result.failure(_mapGoogleException(e));
    } on fb.FirebaseAuthException catch (e) {
      if (_isOAuthCancelCode(e.code)) return null;
      return Result.failure(_mapReauthAuthException(provider, e));
    } on FirebaseFunctionsException catch (e) {
      return Result.failure(_mapFunctionsException(e));
    } on AppException catch (e) {
      // ReauthUserMismatch (사전 대조) · ServiceUnavailable (토큰 부재) 등
      // helper 가 던진 도메인 예외를 그대로 보존한다.
      return Result.failure(e);
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('reauthenticate 비-Auth 예외: ${e.runtimeType}\n$st');
      }
      return Result.failure(ServiceUnavailable(cause: e));
    } finally {
      // 1회성 토큰 정책 (signInWith{Kakao,Naver,Line} finally mirror).
      await _logoutCustomTokenSdk(provider);
      _socialLinkInProgress.end();
    }
  }

  /// 현재 로그인한 계정을 비밀번호로 재인증한다
  /// (debug reauth-login-auto-merge).
  ///
  /// email 은 입력받지 않고 현재 계정의 email 을 쓴다 — 재인증 화면의 이메일
  /// 칸은 읽기 전용이며, 다른 계정 자격증명으로의 로그인을 원천 차단한다.
  /// [fb.FirebaseAuth.signInWithEmailAndPassword] 를 호출하지 않는다.
  ///
  /// 에러 매핑: `user-mismatch` → [ReauthUserMismatch], 그 밖은 이메일 로그인과
  /// 같은 [_mapAuthException] (틀린 비밀번호 → [InvalidCredentials]).
  Future<Result<User>> reauthenticateWithPassword({
    required String password,
  }) async {
    try {
      final current = _auth.currentUser;
      final email = current?.email;
      if (current == null ||
          current.isAnonymous ||
          email == null ||
          email.isEmpty) {
        // 비밀번호 재인증 대상이 아닌 세션 — 재시도로 풀리지 않는다.
        return const Result.failure(UnknownException());
      }
      final reauthed = await current.reauthenticateWithCredential(
        fb.EmailAuthProvider.credential(email: email, password: password),
      );
      final reauthedUser = reauthed.user;
      if (reauthedUser == null) {
        return const Result.failure(ServiceUnavailable());
      }
      if (reauthedUser.uid != current.uid) {
        _logReauthMismatch(AccountProvider.email, 'post-reauth uid');
        return const Result.failure(ReauthUserMismatch());
      }
      return Result.success(_mapFirebaseUser(reauthedUser));
    } on fb.FirebaseAuthException catch (e) {
      if (e.code == 'user-mismatch') {
        _logReauthMismatch(AccountProvider.email, e.code);
        return Result.failure(ReauthUserMismatch(cause: e));
      }
      return Result.failure(_mapAuthException(e));
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint(
          'reauthenticateWithPassword 비-Auth 예외: ${e.runtimeType}\n$st',
        );
      }
      return Result.failure(ServiceUnavailable(cause: e));
    }
  }

  /// native 재인증 직전에 서버 기준으로 [providerId] 연결을 재확인하고, reload
  /// 된 같은 계정 사용자를 돌려준다 (debug reauth-login-auto-merge — 실기기 D1
  /// stale providerData).
  ///
  /// SDK 캐시 `providerData` 는 기동 시 keychain 복원 · 토큰 갱신으로는 바뀌지
  /// 않아 앱 밖(Admin SDK · 다른 기기)에서 해제된 provider 가 남을 수 있다.
  /// [fb.User.reload] 는 기존 객체를 고치지 않고 [fb.FirebaseAuth.currentUser]
  /// 를 새 객체로 교체하므로 (firebase_auth_platform_interface 9.1.0
  /// `MethodChannelUser.reload`), 판정은 reload 뒤 다시 읽은 사용자로 한다.
  /// Firestore `linkedProviders` 와 합치지 않는다 — native 연결의 진실원은
  /// Firebase Auth 다.
  ///
  /// Throws [ReauthMethodUnavailable] — reload 실패 · reload 뒤 같은 uid 세션
  /// 없음 · [providerId] 미연결. 모두 IdP 호출 전이다 (fail-closed).
  Future<fb.User> _reloadLinkedNativeUser(
    fb.User cached,
    String providerId,
  ) async {
    try {
      await cached.reload();
    } on Object catch (e) {
      final reason = e is fb.FirebaseAuthException ? e.code : e.runtimeType;
      _logReauthMethodUnavailable(providerId, 'reload failed: $reason');
      throw ReauthMethodUnavailable(cause: e);
    }
    final reloaded = _auth.currentUser;
    if (reloaded == null || reloaded.uid != cached.uid) {
      _logReauthMethodUnavailable(providerId, 'no same-uid session');
      throw const ReauthMethodUnavailable();
    }
    final isLinked = reloaded.providerData.any(
      (info) => info.providerId == providerId,
    );
    if (!isLinked) {
      _logReauthMethodUnavailable(providerId, 'not linked on server');
      throw const ReauthMethodUnavailable();
    }
    return reloaded;
  }

  /// Apple 로 재인증한다 ([reauthenticate] Apple arm).
  ///
  /// [fb.User.reauthenticateWithProvider] 는 호출마다 새 nonce 를 만든다 —
  /// 실패한 credential 을 재제출하지 않는다.
  Future<fb.UserCredential> _reauthWithApple(fb.User current) {
    return current.reauthenticateWithProvider(
      fb.AppleAuthProvider()
        ..addScope('email')
        ..addScope('name'),
    );
  }

  /// Google 계정 선택 → 현재 계정 연결 대조 → 재인증한다
  /// ([reauthenticate] Google arm).
  ///
  /// [current] 는 [_reloadLinkedNativeUser] 가 돌려준 서버 기준 사용자다 —
  /// 연결 uid 대조가 stale 캐시가 아니라 reload 된 `providerData` 를 본다.
  ///
  /// Throws [ReauthUserMismatch] — 선택한 계정이 현재 계정의 `google.com`
  /// 연결이 아니다 (Firebase 호출 0). Throws [GoogleSignInException] — 취소 ·
  /// SDK 실패 (호출부가 매핑).
  Future<fb.UserCredential> _reauthWithGoogle(fb.User current) async {
    final account = await _googleSignIn.authenticate();
    final isLinkedAccount = current.providerData.any(
      (info) => info.providerId == 'google.com' && info.uid == account.id,
    );
    if (!isLinkedAccount) {
      _logReauthMismatch(AccountProvider.google, 'account not linked');
      throw const ReauthUserMismatch();
    }
    return current.reauthenticateWithCredential(_googleCredentialOf(account));
  }

  /// Facebook 로그인으로 새 credential 을 받아 재인증한다
  /// ([reauthenticate] Facebook arm). 취소 시 `null`.
  ///
  /// iOS Limited Login credential 도 호출마다 새 nonce 로 만들어진다
  /// ([_facebookCredentialOf]) — 실패한 credential 을 재제출하지 않는다.
  Future<fb.UserCredential?> _reauthWithFacebook(fb.User current) async {
    final facebook = await _facebookCredentialOf();
    if (facebook == null) return null;
    return current.reauthenticateWithCredential(facebook.credential);
  }

  /// Custom Token provider 로 같은 계정의 새 세션을 받는다
  /// ([reauthenticate] Custom Token arm). SDK 취소 시 `null`.
  ///
  /// Firebase 에 Custom Token 재인증 API 가 없으므로 로그인 callable 을
  /// 부르되, 응답 uid 가 현재 uid 와 같을 때만 [fb.FirebaseAuth.signInWithCustomToken]
  /// 을 호출한다 — 다른 계정 토큰으로 세션이 바뀌지 않는다. 신규 identity
  /// 등록 · 프로필 덮어쓰기 차단은 서버 가드 책임이다 (응답 전에 일어나므로
  /// client 대조만으로는 막을 수 없다).
  ///
  /// Throws [ReauthUserMismatch] — 응답 uid 불일치. Throws [UnknownException] —
  /// 응답 계약 위반 (customToken · uid 부재). Throws
  /// [FirebaseFunctionsException] — callable 거부 (호출부가 매핑).
  Future<fb.UserCredential?> _reauthWithCustomToken(
    AccountProvider provider,
    fb.User current,
  ) async {
    final request = await _customTokenReauthRequest(provider);
    if (request == null) return null;
    final callable = _functions.httpsCallable(
      request.callableName,
      options: HttpsCallableOptions(timeout: request.timeout),
    );
    final response = await callable.call<Map<String, dynamic>>(request.payload);
    final customToken = response.data['customToken'];
    final uid = response.data['uid'];
    if (customToken is! String || customToken.isEmpty || uid is! String) {
      throw const UnknownException();
    }
    if (uid != current.uid) {
      _logReauthMismatch(provider, 'callable uid');
      throw const ReauthUserMismatch();
    }
    return _auth.signInWithCustomToken(customToken);
  }

  /// Custom Token provider 별 SDK 로그인 → callable 이름 · payload · timeout 을
  /// 만든다. SDK 취소 시 `null`.
  ///
  /// payload 키는 각 로그인 메서드와 같다 (Naver 1-tap = `accessToken` · Naver
  /// 웹 = `code` + `state`, 나머지 = `idToken` + `nonce`). 재인증은 기존 identity 재로그인이라 약관 snapshot
  /// (신규 계정 생성 시에만 서버가 mirror) 은 싣지 않는다. timeout 도 로그인
  /// 메서드와 같다 (Naver 웹 = [_kNaverWebCustomTokenTimeout], 나머지 =
  /// [_kCustomTokenTimeout] — Phase 16.5 review WR-01).
  Future<_CustomTokenCallableRequest?> _customTokenReauthRequest(
    AccountProvider provider,
  ) async {
    switch (provider) {
      case AccountProvider.kakao:
        final result = await _kakaoSdkClient.signIn();
        if (result == null) return null;
        return (
          callableName: 'kakaoCustomToken',
          payload: <String, dynamic>{
            'idToken': result.idToken,
            'nonce': result.nonce,
          },
          timeout: _kCustomTokenTimeout,
        );
      case AccountProvider.naver:
        final result = await _naverSdkClient.signIn();
        if (result == null) return null;
        // Phase 16.5 D-13 — 경로에 따라 1-tap 또는 웹 callable (로그인과 공유).
        return _naverCallableRequest(result);
      case AccountProvider.line:
        final result = await _lineSdkClient.signIn();
        if (result == null) return null;
        return (
          callableName: 'lineCustomToken',
          payload: <String, dynamic>{
            'idToken': result.idToken,
            'nonce': result.nonce,
          },
          timeout: _kCustomTokenTimeout,
        );
      case AccountProvider.google:
      case AccountProvider.apple:
      case AccountProvider.facebook:
      case AccountProvider.email:
        // 호출부가 Custom Token provider (kakao / naver / line) 만 넘긴다 —
        // 도달하지 않는다.
        return null;
    }
  }

  /// Naver SDK 결과 variant → callable 이름 · base payload · timeout
  /// (Phase 16.5 D-13 · review IN-01).
  ///
  /// [signInWithNaver] 와 [_customTokenReauthRequest] 가 공유하는 단일
  /// 진실원이다 — callable 이름 · payload 키 · 경로별 timeout 을 바꿀 때 한
  /// 곳만 고치면 된다. exhaustive switch 라 새 variant 는 컴파일 에러로 잡힌다.
  /// - [NaverAppSignIn] → `naverCustomToken({accessToken})` · 10s
  /// - [NaverWebSignIn] → `naverWebCustomToken({code, state})` · 20s
  ///   (NAVER 직렬 2회 — WR-01)
  ///
  /// 약관 snapshot 은 싣지 않는다 — 로그인 경로만 호출부가
  /// [_buildCustomTokenPayload] 로 덧붙인다.
  _CustomTokenCallableRequest _naverCallableRequest(NaverSignInResult result) {
    return switch (result) {
      NaverAppSignIn(:final accessToken) => (
        callableName: 'naverCustomToken',
        payload: <String, dynamic>{'accessToken': accessToken},
        timeout: _kCustomTokenTimeout,
      ),
      NaverWebSignIn(:final code, :final state) => (
        callableName: 'naverWebCustomToken',
        payload: <String, dynamic>{'code': code, 'state': state},
        timeout: _kNaverWebCustomTokenTimeout,
      ),
    };
  }

  /// Naver SDK 결과 variant → 연결 callable payload · timeout (Phase 16.9).
  ///
  /// callable 은 하나(`linkNaverProvider`) — 모양은 서버가 필드 존재로
  /// 판별한다(1-tap `accessToken` / 웹 `code`+`state` 배타). 결과 variant
  /// switch 라 새 variant 는 컴파일 에러로 잡힌다. timeout 은 로그인과 같은
  /// 경로별 상수를 쓴다.
  /// - [NaverAppSignIn] → `{idToken, accessToken}` · [_kCustomTokenTimeout]
  /// - [NaverWebSignIn] → `{idToken, code, state}` ·
  ///   [_kNaverWebCustomTokenTimeout] (NAVER 직렬 호출 — WR-01)
  ({Map<String, dynamic> payload, Duration timeout}) _naverLinkPayload(
    NaverSignInResult result,
    String callerIdToken,
  ) {
    return switch (result) {
      NaverAppSignIn(:final accessToken) => (
        payload: <String, dynamic>{
          'idToken': callerIdToken,
          'accessToken': accessToken,
        },
        timeout: _kCustomTokenTimeout,
      ),
      NaverWebSignIn(:final code, :final state) => (
        payload: <String, dynamic>{
          'idToken': callerIdToken,
          'code': code,
          'state': state,
        },
        timeout: _kNaverWebCustomTokenTimeout,
      ),
    };
  }

  /// Custom Token provider SDK 를 logout 한다 (재인증 finally — 1회성 토큰).
  /// native provider 는 no-op.
  Future<void> _logoutCustomTokenSdk(AccountProvider provider) async {
    switch (provider) {
      case AccountProvider.kakao:
        await _kakaoSdkClient.logout();
      case AccountProvider.naver:
        await _naverSdkClient.logout();
      case AccountProvider.line:
        await _lineSdkClient.logout();
      case AccountProvider.google:
      case AccountProvider.apple:
      case AccountProvider.facebook:
      case AccountProvider.email:
        break;
    }
  }

  /// native 재인증의 [fb.FirebaseAuthException] 을 [AppException] 으로
  /// 매핑한다 (debug reauth-login-auto-merge).
  ///
  /// - `user-mismatch` — 자격증명이 현재 계정 것이 아니다.
  /// - `user-not-found` — 어느 계정에도 연결 안 된 identity (재인증은 신규
  ///   계정을 만들지 않는다 — iOS SDK 는 이를 userMismatch 로 바꾼다).
  /// - `account-exists-with-different-credential` — 다른 계정 email 과 충돌.
  ///
  /// 세 코드 모두 [ReauthUserMismatch] 이고, 나머지는 소셜 로그인과 같은
  /// [_mapSocialAuthException] 이다.
  AppException _mapReauthAuthException(
    AccountProvider provider,
    fb.FirebaseAuthException e,
  ) {
    switch (e.code) {
      case 'user-mismatch':
      case 'user-not-found':
      case 'account-exists-with-different-credential':
        _logReauthMismatch(provider, e.code);
        return ReauthUserMismatch(cause: e);
    }
    return _mapSocialAuthException(e);
  }

  /// OAuth 창 사용자 취소 code 인지 판정한다 (Apple · 웹 인증 공통).
  static bool _isOAuthCancelCode(String code) =>
      code == 'canceled' ||
      code == 'web-context-canceled' ||
      code == 'web-context-cancelled' ||
      code == 'popup-closed-by-user';

  /// native 재인증 재확인 실패를 기록한다 — providerId URI 와 판정 근거(오류
  /// code 또는 타입)만 (PII 0 — uid · email · 오류 message 미기록).
  void _logReauthMethodUnavailable(String providerId, String reason) {
    if (kDebugMode) {
      debugPrint(
        'AuthRepository.reauthenticate: 서버 기준 재확인 실패 → '
        'ReauthMethodUnavailable (providerId=$providerId, reason=$reason)',
      );
    }
  }

  /// 재인증 계정 불일치를 기록한다 — provider slug 와 판정 근거만 (PII 0).
  void _logReauthMismatch(AccountProvider provider, String reason) {
    if (kDebugMode) {
      debugPrint(
        'AuthRepository.reauthenticate: 계정 불일치 → ReauthUserMismatch '
        '(provider=${provider.slug}, reason=$reason)',
      );
    }
  }

  /// 현재 계정에서 native provider([providerId] — `google.com` · `apple.com` ·
  /// `facebook.com` · `password`) 연결을 해제한다 (Phase 16.8 D-01 · D-02 ·
  /// D-06 · D-08).
  ///
  /// 흐름: Firebase [fb.User.unlink] → `reload()` → `_auth.currentUser` 를
  /// 도메인 [User] 로 매핑한다. `reload()` 로 서버 기준 `providerData` 를 다시
  /// 읽어 stale 캐시로 「해제됨」 을 표시하는 일을 막고(T-16.8-04), 그 결과
  /// `userChanges()` 가 재방출되어 설정 목록이 갱신된다.
  ///
  /// - 재인증을 요구하지 않는다 (D-06) — 확인 다이얼로그가 유일한 진입이다.
  /// - 가입 수단 기록(`signUpProviderId`)은 읽지도 쓰지도 않는다 (D-01 ·
  ///   D-08) — 해제 대상 판정은 UI 의 `canUnlinkProvider` 가 끝냈다.
  /// - [SocialLinkInProgress] 를 감싸지 않는다: 해제는 `currentUser == null`
  ///   창이 없어 익명 자동 로그인 race 가 생기지 않는다 (RESEARCH OQ2).
  ///
  /// 반환:
  /// - `Result.success(User)` — 해제 성공 · reload 된 사용자 (reload 실패는
  ///   흡수하고 성공 유지 — [_reloadAfterUnlink]).
  /// - `Result.failure(ProviderNotLinked)` — `no-such-provider` (이미 해제됨).
  /// - `Result.failure(ReauthenticationRequiredException)` —
  ///   `requires-recent-login` (D-06 으로 기대하지 않는 방어 매핑).
  /// - `Result.failure(UnknownException)` — caller 부재 · 익명 caller
  ///   (WR-06 결정적 실패 — 재시도 유도 금지).
  /// - 그 외 Auth 코드 → [_mapAuthException] · 비-Auth 예외 →
  ///   [ServiceUnavailable].
  Future<Result<User>> unlinkNativeProvider(String providerId) async {
    final current = _auth.currentUser;
    if (current == null || current.isAnonymous) {
      // WR-06: 결정적 실패 — 재시도 유도 금지.
      return const Result.failure(UnknownException());
    }
    try {
      final updated = await current.unlink(providerId);
      // 해제는 Firebase 에서 이미 확정됐다 — 후속 reload 실패가 성공 판정을
      // 뒤집지 않는다 (16.8 review WR-01 · signUpWithEmail 선례).
      await _reloadAfterUnlink(updated, 'unlinkNativeProvider');
      return Result.success(_mapFirebaseUser(_auth.currentUser ?? updated));
    } on fb.FirebaseAuthException catch (e) {
      return Result.failure(_mapUnlinkAuthException(e));
    } on Object catch (e) {
      // PII 0 — runtimeType 만.
      if (kDebugMode) {
        debugPrint(
          'unlinkNativeProvider 비-Auth 예외: runtimeType=${e.runtimeType}',
        );
      }
      return Result.failure(ServiceUnavailable(cause: e));
    }
  }

  /// 현재 계정에서 Custom Token provider([providerSlug] — `kakao` · `line`)
  /// 연결을 해제한다 (Phase 16.8 D-01 · D-02 · D-03 · D-04 · D-06).
  ///
  /// callable `unlinkCustomTokenProvider` 에 [UnlinkProviderRequest] 를 보내고
  /// (`{provider: slug}` — uid 는 서버가 `request.auth` 에서 읽는다) `{ok: true}`
  /// 를 받으면 `reload()` 뒤 도메인 [User] 로 매핑한다. 서버가
  /// `identity_index` · `users/{uid}.linkedProviders` 를 정리하므로
  /// `linkedProvidersStreamProvider` 가 재방출되어 설정 목록이 갱신된다.
  ///
  /// - 재인증을 요구하지 않는다 (D-06) · `signUpProviderId` 를 쓰지 않는다
  ///   (D-01) · [SocialLinkInProgress] 를 감싸지 않는다 (RESEARCH OQ2).
  /// - 서버 `message` 는 렌더하지 않는다 — `code` + `details.reason` 만 분기.
  ///
  /// 에러 매핑 (분기 순서가 계약 — RESEARCH Pitfall 4):
  /// 1. `failed-precondition` + `details.reason == 'last_credential'` →
  ///    [UnlinkLastCredentialRejected] (서버 D-03 가드). [_mapFunctionsException]
  ///    은 `failed-precondition` 을 [ServiceUnavailable] 로 뭉개므로 반드시 앞에서.
  /// 2. `not-found` → [ProviderNotLinked] (대상 CT 신원 없음).
  /// 3. `resource-exhausted` → [TooManyRequests].
  /// 4. 나머지 → [_mapFunctionsException] (`unavailable` · `deadline-exceeded`
  ///    는 거기서 [NoInternetConnection], `unauthenticated` ·
  ///    `permission-denied` 는 [ServiceUnavailable] → 「잠시 후 다시 시도」).
  ///
  /// `unauthenticated` · `permission-denied` 를 [ReauthenticationRequiredException]
  /// 으로 바꾸지 않는 이유 (16.8 review IN-06): App Check 차단(INVALID ·
  /// MISSING)은 SDK 가 `unauthenticated` 로 던지고 재로그인으로 해소되지 않는다.
  /// 이 callable 은 `permission-denied` 를 던지지 않으며(idToken uid 불일치 ·
  /// `caller_identity_mismatch` 경로 없음), 해제는 재인증이 없어(D-06)
  /// 재로그인 안내는 native `requires-recent-login` 방어에만 쓴다.
  ///
  /// 반환:
  /// - `Result.success(User)` — 해제 성공 · reload 된 사용자 (reload 실패는
  ///   흡수하고 성공 유지 — [_reloadAfterUnlink]).
  /// - `Result.failure(...)` — 위 매핑 · caller 부재/익명/`ok != true` 는
  ///   [UnknownException] (WR-06 결정적 실패).
  Future<Result<User>> unlinkCustomTokenProvider(String providerSlug) async {
    final current = _auth.currentUser;
    if (current == null || current.isAnonymous) {
      // WR-06: 결정적 실패 — 재시도 유도 금지.
      return const Result.failure(UnknownException());
    }
    try {
      final callable = _functions.httpsCallable(
        'unlinkCustomTokenProvider',
        options: HttpsCallableOptions(timeout: _kCustomTokenTimeout),
      );
      final response = await callable.call<Map<String, dynamic>>(
        UnlinkProviderRequest(provider: providerSlug).toJson(),
      );
      if (response.data['ok'] != true) {
        // WR-06: 서버 계약 위반 — 재시도로 해소되지 않는다.
        return const Result.failure(UnknownException());
      }
      // 서버 원장에서 해제가 확정됐다 — reload 는 providerData 갱신용일 뿐이고
      // CT 목록은 Firestore stream 이 갱신하므로 실패를 성공에 반영하지 않는다
      // (16.8 review WR-01).
      await _reloadAfterUnlink(current, 'unlinkCustomTokenProvider');
      return Result.success(_mapFirebaseUser(_auth.currentUser ?? current));
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'failed-precondition' &&
          _isLastCredentialRejection(e.details)) {
        return Result.failure(UnlinkLastCredentialRejected(cause: e));
      }
      if (e.code == 'not-found') {
        return Result.failure(ProviderNotLinked(cause: e));
      }
      if (e.code == 'resource-exhausted') {
        return Result.failure(TooManyRequests(cause: e));
      }
      return Result.failure(_mapFunctionsException(e));
    } on fb.FirebaseAuthException catch (e) {
      return Result.failure(_mapAuthException(e));
    } on Object catch (e) {
      // PII 0 — runtimeType 만.
      if (kDebugMode) {
        debugPrint(
          'unlinkCustomTokenProvider 비-Functions 예외: '
          'runtimeType=${e.runtimeType}',
        );
      }
      return Result.failure(ServiceUnavailable(cause: e));
    }
  }

  /// native 해제의 [fb.FirebaseAuthException] 을 [AppException] 으로 매핑한다
  /// (Phase 16.8).
  ///
  /// - `no-such-provider` → [ProviderNotLinked] (이미 해제됨 — 결정적).
  /// - `requires-recent-login` → [ReauthenticationRequiredException].
  /// - 나머지 → [_mapAuthException] (`network-request-failed` ·
  ///   `too-many-requests` 등 공통 매핑).
  AppException _mapUnlinkAuthException(fb.FirebaseAuthException e) =>
      switch (e.code) {
        'no-such-provider' => ProviderNotLinked(cause: e),
        'requires-recent-login' => ReauthenticationRequiredException(cause: e),
        _ => _mapAuthException(e),
      };

  /// 해제가 확정된 뒤 [user] 를 `reload()` 하고 실패는 흡수한다 (Phase 16.8
  /// review WR-01).
  ///
  /// 해제는 Firebase Auth(native) · 서버 원장(CT)에서 이미 확정됐으므로 여기서
  /// 실패를 전파하면 성공이 「잠시 후 다시 시도」 로 뒤집히고, 재시도는
  /// 「이미 해제됨」 이 되어 안내가 모순된다. `signUpWithEmail` 의 reload 흡수와
  /// 같은 원칙이다. 로그는 [fb.FirebaseAuthException.code] 또는 runtimeType 만
  /// 남긴다 (PII 0). [caller] 는 로그에 붙일 호출 메서드 이름이다.
  Future<void> _reloadAfterUnlink(fb.User user, String caller) async {
    try {
      await user.reload();
    } on Object catch (e) {
      if (kDebugMode) {
        final reason = e is fb.FirebaseAuthException ? e.code : e.runtimeType;
        debugPrint('$caller reload 실패(해제 성공 유지): $reason');
      }
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
  @override
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
        debugPrint('signInAnonymously 비-Auth 예외: ${e.runtimeType}\n$st');
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
  /// 2. [signOut] — Firebase Auth + 등록된 소셜 SDK 순차 logout (Phase 9.2
  ///    R6 invariant). IN-02 정정 (Phase 7 review): 이전 문서는 "5 SDK
  ///    (Google/Facebook/Kakao/Naver/LINE)" 로 적어 이후 provider 증분 추가를
  ///    반영하지 못했다. 개수를 문장에 박지 말고 [signOut] 구현을 진실원
  ///    으로 본다.
  ///
  /// 호출 후 navigation 명시 호출은 불필요하다. authStateChanges →
  /// AuthRefresh → resolveAuthRedirect 분기 (2) 가 `!isAuthenticated &&
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
  /// **회원탈퇴 경로에서의 사용 (10-REVIEW CR-01 정정):** Phase 16 구현
  /// `SettingsNotifier.requestAccountDeletion` 이 실제로 본 메서드를 사용한다
  /// (이전 doc 은 사용하지 않는다고 적혀 있었으나 사실과 달랐다). 단,
  /// 서버측 hard delete (`deleteUserAccount` callable) 가 확정된 **이후의
  /// best-effort 로컬 정리**로만 호출되며, 본 메서드의 실패는 탈퇴 성공/실패
  /// 판정에 영향을 주지 않고 Crashlytics `withdrawal_post_signout` telemetry
  /// 로만 기록된다. deleteUser 후의 onboardingSeen 정책은 본 메서드가 수행하는
  /// reset (onboardingSeen=false) 을 그대로 따른다.
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
        debugPrint('AuthRepository._safeDelete 실패 (무시): ${e.runtimeType}\n$st');
      }
    }
  }

  /// (Phase 9.2 D-18 — R4) Firebase Auth 의 [fb.User.sendEmailVerification] 을
  /// 소셜 sign-in success path 에서 자동 호출하는 단일 진실원.
  ///
  /// **IN-02 정정 (Phase 7 review):** 이전 문서는 "5 social sign-in 메서드"
  /// / "5 call site" 로 적었으나 provider 증분 추가로 현재 호출자는 소셜
  /// 7 sign-in 메서드 전부다. 개수를 문장에 박지 않고 호출 관계로 서술한다.
  ///
  /// **WR-01 (Phase 9.2 review fix):** 시그니처를 [fb.UserCredential] 채택으로
  /// 변경 — `isNewUser` 추출을 helper 안으로 흡수하여 각 call site 의 verbatim
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
  /// 자연 no-op 이 되는 경로 (IN-02 정정 — Facebook 을 제외한 소셜 전부):
  /// - Apple / Google — idToken 의 `email_verified=true` claim
  /// - Kakao / Naver — Cloud Function `identity_index.ts` 가
  ///   `emailVerified: true` 자동 set
  /// - LINE — email scope 미채택 (D-LINE-21) 으로
  ///   user record 의 email 이 비어 있어 아래 `email.isEmpty` 가드가 차단
  ///
  /// 따라서 **실효적 발송은 Facebook 경로 하나**다.
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
        debugPrint(
          '_autoSendEmailVerification 비-Auth 예외: ${e.runtimeType}\n$st',
        );
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
  /// 호출하면 `onboardingSeen=true` snapshot 이 유지된 채 resolveAuthRedirect
  /// 가 재평가되어 익명홈 통과 race 가 가능하다 (I2 위배 — D-20 cycle 회귀
  /// vector). Phase 17 (회원탈퇴 reauthentication + deleteUser) 는 별도
  /// 논의 — see ROADMAP Phase 17.
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('GoogleSignIn.signOut() 실패 (무시): ${e.runtimeType}\n$st');
      }
    }
    // Facebook 세션 해제 (D-08).
    try {
      await _facebookAuth.logOut();
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('FacebookAuth.logOut() 실패 (무시): ${e.runtimeType}\n$st');
      }
    }
    // Kakao SDK 세션 해제 (Phase 9.2 D-26 — Phase 12 D-57 정합).
    try {
      await _kakaoSdkClient.logout();
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('KakaoSdkClient.logout() 실패 (무시): ${e.runtimeType}\n$st');
      }
    }
    // Naver SDK 세션 해제 (Phase 9.2 D-26 — Phase 13 D-57 정합).
    try {
      await _naverSdkClient.logout();
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('NaverSdkClient.logout() 실패 (무시): ${e.runtimeType}\n$st');
      }
    }
    // LINE SDK 세션 해제 (Phase 14 D-LINE-57 — Kakao/Naver 패턴 일관).
    try {
      await _lineSdkClient.logout();
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('LineSdkClient.logout() 실패 (무시): ${e.runtimeType}\n$st');
      }
    }
    // WR-07 (Phase 7 review): 계정 경계에서 PII (평문 email key) 잔류 차단 +
    // stale existingProvider 응답 차단. [_accountExistsCache] 는 평문 이메일을
    // key 로 보유하는 in-memory map 이고 [AuthRepository] 는
    // `@Riverpod(keepAlive: true)` 라 앱 생명주기 내내 동일 인스턴스다. TTL
    // 5분 / 64 entry cap 만으로는 로그아웃·계정 전환 시 (1) 사용자 A 의
    // 이메일이 B 세션에 최대 5분 남고 (2) 같은 5분 안에 B 가 동일 이메일
    // 충돌을 겪으면 A 세션의 캐시 응답이 재사용된다.
    _accountExistsCache.clear();
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
    } on Object catch (e, st) {
      // WR-06 (Phase 7 review): 비-Auth 예외 (PlatformException 등) 를 Result
      // 로 감싸 Notifier state 가 AsyncLoading 에 고정되는 것을 방지한다.
      // 소셜 6 경로 / [reloadUser] 가 이미 갖고 있는 방어의 email 계열 mirror
      // — 예외가 그대로 전파되면 LoginNotifier.submit 의
      // `state = switch (result)` 에 도달하지 못해 PrimaryCta 가 영구
      // 스피너/비활성으로 고정된다.
      if (kDebugMode) {
        debugPrint('sendPasswordReset 비-Auth 예외: ${e.runtimeType}\n$st');
      }
      return Result.failure(ServiceUnavailable(cause: e));
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
    } on Object catch (e, st) {
      // WR-06 (Phase 7 review): 비-Auth 예외 (PlatformException 등) 를 Result
      // 로 감싸 Notifier state 가 AsyncLoading 에 고정되는 것을 방지한다.
      // 소셜 6 경로 / [reloadUser] 가 이미 갖고 있는 방어의 email 계열 mirror
      // — 예외가 그대로 전파되면 LoginNotifier.submit 의
      // `state = switch (result)` 에 도달하지 못해 PrimaryCta 가 영구
      // 스피너/비활성으로 고정된다.
      if (kDebugMode) {
        debugPrint('sendEmailVerification 비-Auth 예외: ${e.runtimeType}\n$st');
      }
      return Result.failure(ServiceUnavailable(cause: e));
    }
  }

  /// 현재 사용자 정보를 Firebase에서 리로드한다.
  ///
  /// [fb.User.reload]를 호출하여 서버에서 최신 사용자 정보를
  /// 가져온다. 이메일 인증 완료 여부 확인 시 사용한다. 재인증 선택 화면도
  /// 열릴 때 1회 호출해 연결 provider 목록을 서버 기준으로 새로고침한다
  /// (reload 가 `userChanges` 를 재방출 → `currentUserProvider` 재계산).
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
        debugPrint('reloadUser 비-Auth 예외: ${e.runtimeType}\n$st');
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
  ///
  /// native 소셜 3 경로 (Google · Apple · Facebook sign-in) 는
  /// [_mapSocialAuthException] 을 거쳐 `invalid-credential` 만 분리한다.
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

  /// native 소셜 로그인 (Google · Apple · Facebook) 의
  /// [fb.FirebaseAuthException] 을 [AppException] 으로 매핑한다
  /// (debug ios-facebook-limited-login — D2 B1).
  ///
  /// `invalid-credential` · `missing-or-invalid-nonce` 만 [UnknownException]
  /// 으로 분리하고, 나머지 code 는 [_mapAuthException] 에 그대로 위임한다
  /// (account-exists pendingCredential 보존 · network · too-many-requests 등
  /// 동일).
  ///
  /// **왜 분리하나:** [_mapAuthException] 의 `invalid-credential` →
  /// [InvalidCredentials] 는 email/password 경로의 Email Enumeration 방지
  /// 통합 매핑 (D-18) 이다. 소셜 경로가 같은 arm 을 타면 사용자가 입력한 적
  /// 없는 「이메일 또는 비밀번호가 올바르지 않습니다.」 가 표시된다 (iOS
  /// Facebook Limited Login 실측). 소셜 `invalid-credential` 은 SDK 토큰을
  /// Firebase 가 거부한 결정적 실패라 재입력 · 재시도로 풀리지 않으므로
  /// IN-04 / WR-06 선례대로 [UnknownException] 이다.
  ///
  /// **`missing-or-invalid-nonce` 도 같은 arm (D10 a):** 서버가 요청의
  /// nonce 를 거부한 것이다 (firebase-js-sdk errors.ts "The request does not
  /// contain a valid nonce"). 앱이 요청마다 새 nonce 를 만들고 이미 제출한
  /// credential 을 재사용하지 않는 한 도달하지 않으므로, 남는 원인은 해시 짝
  /// 불일치 · credential 재사용 회귀 같은 결정적 클라이언트 결함이다.
  /// 기본 폴백 [ServiceUnavailable] 의 「일시적」 문구는 매번 같은 실패로
  /// 끝나는 재시도를 유도하므로 쓰지 않는다 (iOS 실기기 run-02 관측).
  ///
  /// 적용 범위는 signInWithGoogle · signInWithApple · signInWithFacebook 의
  /// catch 3곳뿐이다. email 계열 · 익명 · Custom Token (kakao / naver / line) ·
  /// reactive / proactive link 매핑은 바꾸지 않는다.
  AppException _mapSocialAuthException(fb.FirebaseAuthException e) {
    if (e.code != 'invalid-credential' &&
        e.code != 'missing-or-invalid-nonce') {
      return _mapAuthException(e);
    }
    if (kDebugMode) {
      // PII invariant: code 만 — e.message · e.email · e.credential 비포함.
      // UnknownException 이 code 를 감추므로 판정 근거 1줄을 남긴다
      // (_logAndFallback 의 code-only 형식 mirror).
      debugPrint(
        'AuthRepository: 소셜 로그인 거부 → UnknownException: code=${e.code}',
      );
    }
    return UnknownException(cause: e);
  }

  /// Custom Token callable payload 에 `termsAcceptanceSnapshot` 을 add-only 로
  /// 부착한다 (Phase 16 G-16-A9-1 / D-13).
  ///
  /// **회귀 invariant (add-only):** device-local 동의가 없어 reader 가 null 을
  /// 반환하면 [base] 를 그대로 반환한다 — 3 provider 의 기존 payload 키 집합이
  /// 한 글자도 바뀌지 않는다. 서버 arg 도 optional 이므로 본 helper 호출만
  /// 되돌리면 완전 복귀한다.
  ///
  /// **서버 계약:** 부착 값의 키 집합은
  /// `functions/src/shared/terms_acceptance_json.ts` 의 `TermsAcceptanceJson`
  /// 5 키 (version / service / privacy / marketing / acceptedAt) 와 정확히
  /// 일치해야 한다. 3 provider endpoint (kakao/naver/line) 가 이를 optional 로
  /// 수신해 `users/{uid}` 문서 생성과 같은 write 안에서 mirror 한다.
  ///
  /// **`acceptedAt` 은 UTC ISO 8601 String (`Z` 접미) 이어야 한다.** 서버가
  /// `Timestamp.fromDate(new Date(...))` 로 파싱하므로 `DateTime` 객체나 epoch
  /// int 를 보내면 파싱이 깨진다.
  ///
  /// **CR-01:** `TermsAcceptance.toJson()` 출력만으로는 계약을 만족하지
  /// **않는다** — `toIso8601String()` 은 UTC 가 아닌 `DateTime` 에 타임존
  /// 지시자를 붙이지 않고, 서버(TZ=UTC) 는 offset 없는 문자열을 UTC 로 해석해
  /// local offset 만큼 어긋난 시각을 기록한다. 정규화 책임은 producer 인
  /// `TermsNotifier.acceptanceSnapshotJson` 에 있으며 본 메서드는 주입된
  /// snapshot 을 그대로 부착한다.
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
  ///   → [ServiceUnavailable] (`unauthenticated` = App Check 차단 · auth
  ///    무효 · idToken 검증 실패 · token age 위반 · IdP 자격증명 거부 /
  ///    `invalid-argument` = 입력 계약 위반 / `failed-precondition` = 사전
  ///    조건 위배(익명 caller 등) / `permission-denied` = 미분류 방어 분기 —
  ///    연결 callable 의 idToken uid 불일치는 [_mapLinkCallableException] 이
  ///    선분기한다 · 16.8 review IN-06 · iteration 2 IN-02 · 16.9 review
  ///    iteration 2 IN-03 정정)
  /// - `unavailable` / `deadline-exceeded` → [NoInternetConnection]
  ///   (Cloud Function 일시 장애 / 네트워크 지연)
  /// - `already-exists` → [AccountExistsWithDifferentCredential]
  ///   (R3 — Phase 12.1 BL-04 hotfix. Cloud Function 의 already-exists 응답을
  ///    사용자 recovery 가능한 도메인 예외로 매핑. email field 는 Cloud Function
  ///    이 PII 이유로 응답에 미포함 → null 유지. LoginScreen 의 자동 채움은
  ///    `email != null` 분기에서만 트리거)
  /// - 그 외 → [ServiceUnavailable(cause: e)]
  AppException _mapFunctionsException(FirebaseFunctionsException e) {
    // debug reauth-login-auto-merge — 서버 비익명 caller 가드 거부. idToken
    // uid 불일치 거부와 같은 `permission-denied` 라 details.reason 으로만
    // 구분한다 (App Check 차단은 `unauthenticated` — 아래 주석).
    if (e.code == 'permission-denied' && _isCallerIdentityMismatch(e.details)) {
      return ReauthUserMismatch(cause: e);
    }
    return switch (e.code) {
      // IN-02: permission-denied 명시 분기 — `caller_identity_mismatch`(위
      // 선분기) 외 미분류 permission-denied 의 방어 분기다. 서버의 다른
      // 출처는 idToken uid 불일치 셋뿐이고 여기 도달하지 않는다
      // (16.9 review iteration 2 IN-03): 연결 callable
      // (`link_custom_token_provider` · `link_naver_provider`)의 불일치는
      // `_mapLinkCallableException` 이 선분기(재로그인)하고,
      // `delete_user_account` 는 `SettingsRepository._mapDeleteError` 경로다.
      // App Check 차단 (enforceAppCheck:true — INVALID · MISSING) · auth
      // 무효 · token age 위반은 `unauthenticated` 로 온다 (firebase-functions 7.2.5
      // `common/providers/https.js` · `shared/reauth.ts`). SDK 자체의
      // permission-denied 는 authPolicy(킷 미사용) 전용 (16.8 review IN-06).
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

  /// callable 거부 [details] 가 서버 비익명 caller 가드의 `caller_identity_mismatch`
  /// 인지 판정한다 (debug reauth-login-auto-merge).
  ///
  /// functions `callerIdentityMismatch()` 가 `{reason: 'caller_identity_mismatch'}`
  /// 를 싣는다. [details] 가 [Map] 이 아니거나 reason 이 다르면 `false`.
  bool _isCallerIdentityMismatch(Object? details) =>
      details is Map && details['reason'] == 'caller_identity_mismatch';

  /// callable 거부 [details] 가 서버 재인증 필요 표시
  /// (`{reason: 'reauthentication_required'}`)인지 판정한다
  /// (Phase 16.9 review WR-01).
  ///
  /// functions `reauthenticationRequired()` 가 싣는다. [details] 가 [Map] 이
  /// 아니거나 reason 이 다르면 `false` — fail-closed 로 재로그인 분기를 막는다.
  bool _isReauthRequiredRejection(Object? details) =>
      details is Map && details['reason'] == 'reauthentication_required';

  /// 연결 callable 거부 [details] 가 서버 provider 당 신원 1개 가드
  /// (`{reason: 'provider_already_linked'}`)인지 판정한다
  /// (Phase 16.9 review IN-03).
  ///
  /// functions `providerAlreadyLinked()` 가 싣는다. [details] 가 [Map] 이
  /// 아니거나 reason 이 다르면 `false` ([AccountAlreadyLinked] 로 남는다).
  bool _isProviderAlreadyLinkedRejection(Object? details) =>
      details is Map && details['reason'] == 'provider_already_linked';

  /// callable `unlinkCustomTokenProvider` 거부 [details] 가 서버 D-03 가드의
  /// `last_credential` 인지 판정한다 (Phase 16.8 · RESEARCH Pitfall 4).
  ///
  /// [details] 가 [Map] 이 아니거나 reason 이 다르면 `false`.
  bool _isLastCredentialRejection(Object? details) =>
      details is Map && details['reason'] == 'last_credential';

  /// [FirebaseFunctionsException.details] 에서 `existingProvider` slug 를 안전
  /// 추출해 [AccountProvider] 로 변환한다 (16-13 A4 gap closure).
  ///
  /// 서버 collision throw 의 `details` 는 `{existingProvider: 'kakao'}` 형태의
  /// Map 이다. [details] 가 [Map] 이 아니거나 `existingProvider` 키가 없거나
  /// 값이 [String] 이 아니거나 unknown slug 면 `null` 을 반환한다 (R2 일반
  /// 배너 fallback 보존). [AccountProvider.tryParse] 가 등록 slug
  /// ([AccountProvider.values] — 소셜 [kAllProviderIds] + email/password)
  /// 만 enum 변환하고 그 외 (`null` / unknown) 는 `null` 로 흡수한다
  /// (IN-06 — 숫자 대신 목록 참조).
  ///
  /// [details] 는 `dynamic` 이므로 [Object?] 로 받아 `is` 가드로 좁힌다
  /// (flutter.md `dynamic` 금지 + `as` 최소화).
  AccountProvider? _existingProviderFromDetails(Object? details) {
    if (details is! Map) return null;
    final raw = details['existingProvider'];
    return raw is String ? AccountProvider.tryParse(raw) : null;
  }

  /// Facebook [LoginResult] → [AccessToken] 정규화 단일 진실원
  /// (WR-02 — Phase 7 review).
  ///
  /// [LoginStatus] 는 4값 (`success` / `cancelled` / `failed` /
  /// `operationInProgress`) 이다. 이전 구현은 `status != success` 를 전부
  /// "사용자 취소" 로 흡수해 `failed` (토큰 오류 / 네트워크 / 앱 설정 오류)
  /// 와 `operationInProgress` 에서도 **화면에 아무 일도 일어나지 않았다**.
  /// Kakao / LINE 이 비-취소 오류를 [ServiceUnavailable] 로
  /// 승격하는 규칙과 대칭을 맞춘다.
  ///
  /// `status == success` 인데 [LoginResult.accessToken] 이 null 인 경우도
  /// 취소가 아니므로 동일하게 실패로 승격한다.
  ///
  /// 반환:
  /// - [AccessToken] — 로그인 성공.
  /// - `null` — 사용자 취소 (D-09 silent no-op).
  ///
  /// Throws [ServiceUnavailable] — 취소가 아닌 실패.
  AccessToken? _facebookAccessTokenOf(LoginResult loginResult) {
    if (loginResult.status == LoginStatus.cancelled) {
      return null; // D-09 silent cancel
    }
    if (loginResult.status != LoginStatus.success) {
      if (kDebugMode) {
        // PII invariant (T-16-09-02 mirror): status 만 — loginResult.message
        // 본문은 사용자 식별 정보를 실을 수 있으므로 비포함.
        debugPrint('facebook login 실패: status=${loginResult.status}');
      }
      throw const ServiceUnavailable();
    }
    final accessToken = loginResult.accessToken;
    if (accessToken == null) {
      if (kDebugMode) {
        debugPrint('facebook login: status=success 인데 accessToken 부재');
      }
      throw const ServiceUnavailable();
    }
    return accessToken;
  }

  /// Facebook 로그인 → Firebase [fb.AuthCredential] 변환 단일 진실원
  /// (debug ios-facebook-limited-login — D1 A1).
  ///
  /// [signInWithFacebook] / [_reauthNativeCredential] / [linkFacebookCredential]
  /// 3 호출 지점이 공유한다 (Google [_googleCredentialOf] WR-01 선례 — 곳마다
  /// 복제하면 한 곳만 고쳐지는 구조가 된다, IN-05).
  ///
  /// **iOS Limited Login:** 앱이 [LoginTracking.enabled] 를 요청해도
  /// flutter_facebook_auth 7.2.0 iOS 는 ATT 미허용이면 Limited Login 으로
  /// 강제하고 (`FacebookAuth.swift:106-110`) [LimitedToken] (OIDC JWT) 을
  /// 돌려준다. 이 JWT 를 access token 으로 넘기면 Firebase 가
  /// `invalid-credential` 로 거부하므로 토큰 런타임 타입으로 분기한다:
  /// - [LimitedToken] → `OAuthProvider('facebook.com').credential(idToken:
  ///   JWT, rawNonce: 원문)` — Firebase iOS 문서 "use the ID token from
  ///   Facebook's response with the unhashed nonce".
  /// - [ClassicToken] → [fb.FacebookAuthProvider.credential] (Android 는 항상
  ///   이 경로 — 플러그인 Android 소스에 Limited 분기 없음).
  ///
  /// **Android (flutter_facebook_auth 7.2.0~):** 7.1.6 까지 Android 는 앱이
  /// 넘긴 nonce 를 버렸지만, 7.2.0 부터 nonce 가 있으면
  /// `LoginConfiguration(permissions, nonce)` 로 로그인한다
  /// (`FacebookAuth.java` login). Facebook Android SDK 18.1.3 의
  /// `LoginConfiguration` 은 요청 권한에 `openid` 를 더하고 PKCE code
  /// verifier 를 만들며, 결과 [ClassicToken.authenticationToken] 에 OIDC JWT 가
  /// 실린다. 그래도 Android 는 access token credential 을 유지한다 —
  /// access token 이 있어 Graph API (프로필 사진 · email) 를 쓸 수 있고
  /// (`isLimited: false`), OIDC credential 은 access token 이 없는 Limited
  /// Login 용 대안이기 때문이다. `authenticationToken` 은 JWT 이므로
  /// tokenString 과 같이 로그 경로에 싣지 않는다.
  ///
  /// **nonce:** 요청마다 [generateNonce] 로 raw nonce 를 새로 만들고, 로그인
  /// 요청에는 [hashNonceSha256Hex] 값을 넘긴다 (문서 "send the SHA-256 hash
  /// of the nonce with your sign-in request"). 플러그인은 nonce 를 해시하지
  /// 않고 그대로 SDK 에 넘기며, 생략하면 해시가 아닌 UUID 를 자동 생성하므로
  /// (`FacebookAuth.swift:111`) 반드시 앱이 넘긴다.
  ///
  /// 반환:
  /// - `(credential, isLimited)` — 로그인 성공. `isLimited` 는 Graph API
  ///   사용 가능 여부 판단 ([_setFacebookPhotoUrl] 생략, D4 Da) 에 쓴다.
  /// - `null` — 사용자 취소 (D-09 silent no-op).
  ///
  /// Throws [ServiceUnavailable] — 취소가 아닌 로그인 실패
  /// ([_facebookAccessTokenOf]) 또는 Classic / Limited 어느 쪽도 아닌 토큰
  /// 타입 ([AccessToken] 은 sealed 가 아니다).
  Future<({fb.AuthCredential credential, bool isLimited})?>
  _facebookCredentialOf() async {
    final rawNonce = generateNonce(byteLength: 32);
    final loginResult = await _facebookAuth.login(
      permissions: ['email', 'public_profile'],
      loginTracking: LoginTracking.enabled,
      nonce: hashNonceSha256Hex(rawNonce),
    );
    // WR-02: 취소만 null, 실패는 ServiceUnavailable throw.
    final accessToken = _facebookAccessTokenOf(loginResult);
    if (accessToken == null) return null;
    if (kDebugMode) {
      // D5 E1 — 실기기 재검증에서 수정 경로 (limited → oauth) 를 탔다는 인용
      // 근거. 토큰 종류만 출력한다. tokenString · userId · email · nonce 는
      // 보간 인자로도 넘기지 않는다 (PII invariant — 민감값을 애초에 로그
      // 경로에 싣지 않음).
      debugPrint('facebook login 토큰 진단: type=${accessToken.type.name}');
    }
    return switch (accessToken) {
      LimitedToken(:final tokenString) => (
        credential: fb.OAuthProvider(
          fb.FacebookAuthProvider.PROVIDER_ID,
        ).credential(idToken: tokenString, rawNonce: rawNonce),
        isLimited: true,
      ),
      ClassicToken(:final tokenString) => (
        credential: fb.FacebookAuthProvider.credential(tokenString),
        isLimited: false,
      ),
      // 형태를 모르는 토큰으로 Firebase 를 호출하지 않고 실패로 승격한다.
      _ => throw const ServiceUnavailable(),
    };
  }

  /// Google [GoogleSignInAccount] → Firebase [fb.AuthCredential] 변환 단일
  /// 진실원 (WR-01 — Phase 7 review).
  ///
  /// `google_sign_in` 7.x 의 `GoogleSignInAuthentication.idToken` 은 nullable
  /// 이다. Android `serverClientId` 미설정 같은 **설정 오류** 시 null 로
  /// 도착하는데, [fb.GoogleAuthProvider.credential] 은
  /// `assert(accessToken != null || idToken != null)` 만 두고 있어 release
  /// 빌드에서는 assert 가 제거되고 빈 credential 로 Firebase 를 호출한다.
  /// 그 결과 상위 `on Object catch` 가 설정 오류를 "일시적 서비스 불가" 로
  /// 오안내한다.
  ///
  /// Kakao (`kakao_sdk_client.dart` Pitfall 1) / LINE 이 이미
  /// 갖고 있는 `idToken == null || isEmpty` → [ServiceUnavailable] 가드를
  /// mirror 하여 OIDC 3 provider 의 규칙을 통일한다. Google 3 호출 지점
  /// ([signInWithGoogle] / [_reauthNativeCredential] / [linkGoogleCredential])
  /// 이 본 helper 를 공유한다.
  ///
  /// Throws [ServiceUnavailable] — idToken 이 null 또는 빈 문자열인 경우.
  fb.AuthCredential _googleCredentialOf(GoogleSignInAccount account) {
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw const ServiceUnavailable();
    }
    return fb.GoogleAuthProvider.credential(idToken: idToken);
  }

  /// [GoogleSignInException]을 [AppException]으로 매핑한다.
  ///
  /// 취소([GoogleSignInExceptionCode.canceled])는 호출부에서 별도 처리하므로
  /// 여기에 도달하지 않는다. 기타 에러는 [ServiceUnavailable]로 매핑한다.
  AppException _mapGoogleException(GoogleSignInException e) {
    if (kDebugMode) {
      // WR-05 PII invariant: code 만 — `description` 은 SDK 원문 message
      // 로 사용자 식별 정보를 실을 수 있어 비포함 (_runProactiveNativeLink /
      // linkCustomTokenProviderArm 의 code-only 형식 mirror).
      debugPrint('AuthRepository: GoogleSignIn 에러 -- code=${e.code}');
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
      // WR-05 PII invariant: code 만 — `e.message` 는 Firebase 원문으로
      // email 등 식별 정보를 실을 수 있어 비포함.
      debugPrint(
        'AuthRepository: ServiceUnavailable 폴백 — $reason: code=${e.code}',
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

/// Custom Token 로그인 · 재인증 callable 호출 명세 — 이름 · base payload ·
/// timeout (Phase 16.5 review WR-01 · IN-01).
typedef _CustomTokenCallableRequest = ({
  String callableName,
  Map<String, dynamic> payload,
  Duration timeout,
});

/// Custom Token target provider 의 OIDC 토큰 + nonce 묶음 (Phase 16 16-09).
///
/// [KakaoSignInResult] / [LineSignInResult] 의 `idToken`
/// + `nonce` 를 단일 인터페이스로 normalize 하여
/// [AuthRepository.linkCustomTokenProviderArm] 가 provider-agnostic 하게
/// callable payload 를 구성하도록 한다.
class _TargetProviderToken {
  const _TargetProviderToken(this.idToken, this.nonce);

  /// target provider OIDC ID Token — deployed callable `targetProviderToken`.
  final String idToken;

  /// 단일 사용 raw nonce — deployed callable `nonce` (2 provider 모두 의무).
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

/// 가입 수단 기록 콜백 signature (Phase 16.7 D-13 · D-15).
///
/// [uid] 문서에 [providerId] (`User.providerIds` 와 같은 형식) 를 기록한다.
/// 구현은 어떤 예외도 던지지 않아야 한다 — 호출처가 `unawaited` 로 부른다
/// (D-17).
typedef RecordSignUpMethod =
    Future<void> Function(String uid, String providerId);

/// [AuthRepository.new] 의 `recordSignUpMethod` 미주입 시 기본 구현
/// (Phase 16.7).
///
/// 아무것도 기록하지 않는다 — 기존 테스트의 생성자 호출부 회귀 0.
Future<void> _recordNoSignUpMethod(String uid, String providerId) async {}

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
    // Phase 10.2 D-A2: cross-feature 결합도 최소화를 위한 callback 주입.
    // OnboardingNotifier 타입은 본 factory 영역에서만 알며,
    // AuthRepository 클래스 본체는 콜백 signature 만 의존한다.
    () => ref.read(onboardingProvider.notifier).reset(),
    // Phase 16 G-16-A9-1: 동일한 D-A2 콜백 주입 관례. TermsState 타입은
    // 본 factory 영역에서만 알며, AuthRepository 클래스 본체는
    // `Map<String, dynamic>? Function()` signature 만 의존한다.
    // buildAcceptanceSnapshotJson() 이 서버 TermsAcceptanceJson 5 키를 산출한다
    // (acceptedAt = UTC 정규화된 ISO 8601 — CR-01).
    readTermsAcceptanceSnapshot: () =>
        ref.read(termsProvider).buildAcceptanceSnapshotJson(),
    // Phase 16.7 D-13 · D-15: 동일한 D-A2 콜백 주입 관례.
    // SignUpMethodRecorder 타입은 본 factory 영역에서만 알며, AuthRepository
    // 클래스 본체는 RecordSignUpMethod signature 만 의존한다.
    // 콜백을 async 로 둬 recorder provider 생성 중 동기 예외
    // (_assertFirebaseReady 등) 도 Future 안으로 흘린다 — 가입 흐름의 catch 에
    // 닿아 가입을 실패로 바꾸지 않는다 (D-17).
    recordSignUpMethod: (uid, providerId) async => ref
        .read(signUpMethodRecorderProvider)
        .record(uid: uid, providerId: providerId),
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
/// **Phase 16.7 (D-11 데이터 계층):** 같은 snapshot 의 `signUpProviderId` 를
/// [User.signUpProviderId] 에 싣는다. stream 은 [UserProviderRecord] 로
/// 두 필드를 함께 emit 하며, 위 3 분기 규칙(AsyncLoading = 직전 cached
/// record · AsyncError = 빈 record)이 두 필드에 똑같이 적용된다. 첫 emit
/// 전(cached 없음) · 읽기 실패 · 필드 부재는 모두 null — 추론 0.
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
  // - AsyncData(rec)   → record 그대로 사용
  // - AsyncLoading     → recAsync.value (직전 cached record)
  //                      ?? _emptyUserProviderRecord
  //                      sign-in 직후 첫 emit 도착 전 시점에 base.providerIds
  //                      만으로 fallback 하지 않음 — Custom Token user (Naver/
  //                      Kakao) 의 ephemeral '-' UX (R13) 차단. Phase 16.7:
  //                      signUpProviderId 도 같은 cached record 에서 보존.
  // - AsyncError       → _emptyUserProviderRecord (영구 spinner 회피,
  //                      handleError 가 이미 빈 record 로 정착하므로 실질 도달
  //                      거의 없음)
  final recAsync = ref.watch(linkedProvidersStreamProvider(fbUser.uid));
  final rec = recAsync.when(
    data: (r) => r,
    loading: () => recAsync.value ?? _emptyUserProviderRecord,
    error: (_, _) => _emptyUserProviderRecord,
  );

  // Set 기반 중복 제거 (Native URI + Custom Token slug 양쪽 보존).
  // Phase 16.7: 연결 목록이 비어도 signUpProviderId 를 실어야 하므로 early
  // return 없이 항상 합성한다 (D-11 — 값이 없으면 null 그대로).
  final merged = <String>{
    ...base.providerIds,
    ...rec.linkedProviderIds,
  }.toList();
  return base.copyWith(
    providerIds: merged,
    signUpProviderId: rec.signUpProviderId,
  );
}

/// [linkedProvidersStream] 이 emit 하는 `users/{uid}` provider 상태 record
/// (Phase 16.7 D-11).
///
/// - `linkedProviderIds`: `linkedProviders[].providerId` (Custom Token slug 등).
/// - `signUpProviderId`: 가입 수단 providerId — 필드 부재 · String 아닌
///   타입 · 문서 부재 · 읽기 실패는 null (추론 0).
typedef UserProviderRecord = ({
  List<String> linkedProviderIds,
  String? signUpProviderId,
});

/// 빈 [UserProviderRecord] — 문서 부재 · 읽기 실패 · 첫 emit 전 fallback.
const UserProviderRecord _emptyUserProviderRecord = (
  linkedProviderIds: <String>[],
  signUpProviderId: null,
);

/// Firestore `users/{uid}.linkedProviders[].providerId` + `signUpProviderId`
/// 를 [UserProviderRecord] stream 으로 노출한다 (Phase 12 D-16 · Phase 16.7
/// D-11, family by uid).
///
/// `users/{uid}` 문서가 미존재 (mirrorToFirestore 가 작성 전) 이면 빈
/// record 를, `linkedProviders` 필드가 없으면 빈 연결 목록을 emit 한다.
/// `signUpProviderId` 는 String 일 때만 싣고 그 외(부재 · 타입 불일치)는
/// null 이다. 같은 문서에 두 번째 listener 를 두지 않도록 두 필드를 한 번에
/// 파싱한다 (Phase 16.7).
///
/// 아래 설명의 「빈 배열」 은 Phase 16.7 부터 빈 record
/// (`_emptyUserProviderRecord`) 를 뜻한다.
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
/// - I5 (WR-04 — generator 비종료): 빈 배열 fallback 을 emit 한 뒤에도
///   generator 를 종료하지 않고 backoff (5s→60s 상한) 후 재구독한다. 본
///   provider 는 `keepAlive` 라 종료 시 앱 재시작 전까지 재구독이 없어,
///   일시적 `unavailable` 한 번으로 세션 내내 linkedProviders 가 빈 배열에
///   고정되고 [currentUser] 합집합이 Custom Token provider 전부를 영구
///   누락했다.
/// - I4 (Type-safe parsing): 기존 [Iterable.whereType] 필터로 invalid entry
///   를 자동 제거 (T-12-06-05).
///
/// `kDebugMode` 에서는 retry / 에러 로그를 출력한다 — release 빌드는 silent.
///
/// **참고:** Firestore SDK 자체의 token cache 자동 재구독 미동작은 known bug
/// (firebase-android-sdk #5101, flutterfire #11146). 본 fix 는 client-side
/// workaround. spec: `docs/superpowers/specs/2026-05-08-r10-followup-2-design.md`.
@Riverpod(keepAlive: true)
Stream<UserProviderRecord> linkedProvidersStream(Ref ref, String uid) async* {
  final firestore = ref.watch(firebaseFirestoreProvider);
  var permissionDeniedRetries = 0;
  const maxRetries = 5;
  const retryDelay = Duration(seconds: 1);
  // WR-04 (Phase 7 review): fallback emit 후 재구독 backoff. 5s 에서 시작해
  // 2배씩 증가하고 60s 를 상한으로 한다 — 영구 장애에서 hot loop 을 만들지
  // 않으면서도 일시 장애에서는 세션 내 자력 복구가 가능하다.
  const initialErrorBackoff = Duration(seconds: 5);
  const maxErrorBackoff = Duration(seconds: 60);
  var errorBackoff = initialErrorBackoff;

  while (true) {
    try {
      await for (final snap
          in firestore.collection('users').doc(uid).snapshots()) {
        // I3: 정상 emit 도달 시 카운터 리셋 — 장기 세션 token 재만료 시
        // 다시 retry 가능. WR-04: 에러 backoff 도 함께 리셋한다.
        permissionDeniedRetries = 0;
        errorBackoff = initialErrorBackoff;
        if (!snap.exists) {
          yield _emptyUserProviderRecord;
          continue;
        }
        final data = snap.data();
        // Phase 16.7 D-11: 가입 수단 — String 이 아니면 null (I4 관례).
        final signUpRaw = data?['signUpProviderId'];
        final signUpProviderId = signUpRaw is String ? signUpRaw : null;
        final raw = data?['linkedProviders'] as List<dynamic>?;
        if (raw == null) {
          // linkedProviders 부재여도 signUpProviderId 는 버리지 않는다.
          yield (
            linkedProviderIds: const <String>[],
            signUpProviderId: signUpProviderId,
          );
          continue;
        }
        // I4: Type-safe parsing — invalid entry 자동 제거.
        yield (
          linkedProviderIds: raw
              .whereType<Map<String, dynamic>>()
              .map((m) => m['providerId'] as String?)
              .whereType<String>()
              .toList(growable: false),
          signUpProviderId: signUpProviderId,
        );
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
            '(after ${retryDelay.inMilliseconds}ms delay): ${e.code}',
          );
        }
        await Future<void>.delayed(retryDelay);
        continue;
      }
      // I1 (D-41 보존):
      // (1) 다른 FirebaseException (network / unavailable 등) — 즉시 빈 배열.
      // (2) permission-denied — maxRetries 회 재구독 후에도 거부 → 영구
      //     spinner 회피 escape hatch (총 maxRetries+1 회 거부 후 escape).
      // I5 (WR-04): 두 경우 모두 emit 후 generator 를 닫지 않고 backoff
      // 재구독으로 이어진다.
      if (kDebugMode) {
        debugPrint(
          'linkedProvidersStream 에러 (fallback empty, '
          '${errorBackoff.inSeconds}s 후 재구독): ${e.code}\n$st',
        );
      }
      yield _emptyUserProviderRecord;
      // WR-04: 이전 구현은 여기서 `break` 로 generator 를 종료시켰다. 본
      // provider 는 `@Riverpod(keepAlive: true)` 라 재구독이 일어나지 않아
      // 일시적 `unavailable` 한 번이면 세션 내내 linkedProviders 가 빈
      // 배열로 고정되고, currentUser 의 합집합이 Custom Token provider 들을
      // 영구 누락했다 (Settings "계정 연결" 섹션 / provider 라벨 오표시).
      // permission-denied 에 이미 존재하는 "일시 장애에서 복구한다" 의도를
      // 나머지 에러에도 대칭 적용한다.
      await Future<void>.delayed(errorBackoff);
      // 재구독 라운드에서는 permission-denied 예산도 새로 부여한다.
      permissionDeniedRetries = 0;
      final doubled = errorBackoff * 2;
      errorBackoff = doubled > maxErrorBackoff ? maxErrorBackoff : doubled;
      continue;
    }
  }
}
