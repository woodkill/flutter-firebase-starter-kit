import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/crashlytics/crashlytics_service.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/error/result.dart';
import '../../../core/providers/firebase_providers.dart';
import '../domain/terms_acceptance.dart';

part 'terms_notifier.g.dart';

/// 약관 동의 상태를 관리하는 Notifier (Phase 10 D-15, D-16, D-17).
///
/// 이중 저장 전략 (D-16, Issue #6 — Plan 10-09 격상):
/// - **정식 사용자:** Firestore `users/{uid}/termsAccepted` 가 권위 있는
///   source. UID 변경 시 [reloadForUser] 호출로 자동 갱신 (D-15 1회 동의
///   invariant 가 사용자 단위로 평가되도록 보장).
/// - **익명 사용자:** SharedPreferences `terms.accepted_value` JSON 으로
///   device-local 동의 추적 (오프라인 + cold-start 대응).
/// - **로그아웃:** state=null 로 초기화하여 다음 평가 시 분기 (2)
///   /onboarding 발동.
/// - **Firestore read 실패:** SharedPreferences 로 graceful fallback
///   (오프라인 대응) + Crashlytics 기록.
///
/// ## D-33: Dev Tools production 표면 (Plan-checker WARNING #8)
///
/// [reset] 은 `@visibleForTesting` 없이 **public** 메서드이다. Plan 04
/// `_DevToolsSection` 이 프로덕션 코드에서 이 메서드를 호출하므로 제한을
/// 두지 않는다.
@Riverpod(keepAlive: true)
class TermsNotifier extends _$TermsNotifier {
  /// SharedPreferences 에 [TermsAcceptance] JSON 문자열 전체를 저장하는 키
  /// (WARNING #16 — cold-start 후 mirrorToFirestore 정확도 확보).
  static const String _key = 'terms.accepted_value';

  /// 구 int 기반 버전 키. Migration 감지용만. 신규 저장은 [_key] 사용.
  ///
  /// [reset] 호출 시 함께 제거한다.
  static const String _legacyVersionKey = 'terms.accepted_version';

  /// 현재 약관 버전. 약관 개정 후 bump 하면 기존 동의 데이터가 무효화된다.
  static const int currentVersion = 1;

  /// 내부 캐시. [mirrorToFirestore] 호출 시 [state] 대신 이 필드를 참조한다.
  TermsAcceptance? _acceptance;

  /// [_acceptance] 의 읽기 전용 접근자 (Phase 16 G-16-A9-1 — Custom Token
  /// callable payload 직렬화 source).
  ///
  /// 4 Custom Token endpoint (kakao/naver/line/yahoojp) 로 전송하는
  /// `termsAcceptanceSnapshot` payload 를 `AuthRepository` 가 콜백으로 읽는다.
  /// [state] 가 아니라 [_acceptance] 를 노출하는 이유는 [mirrorToFirestore]
  /// 가 참조하는 것과 동일한 내부 캐시여야 payload 값과 Firestore mirror 값이
  /// 항상 일치하기 때문이다.
  TermsAcceptance? get acceptanceSnapshot => _acceptance;

  /// Custom Token callable payload 로 전송할 `termsAcceptanceSnapshot` JSON
  /// (Phase 16 CR-01 — timezone 정합성 고정).
  ///
  /// [acceptanceSnapshot] 을 그대로 `toJson()` 하면 안 된다. [accept] 는
  /// `DateTime.now()` (**local**) 로 [TermsAcceptance.acceptedAt] 을 만들고,
  /// Dart 의 `toIso8601String()` 은 UTC 가 아닌 `DateTime` 에 타임존 지시자를
  /// 붙이지 않는다 (`2026-09-07T23:30:38.738305`). 서버(Cloud Functions, TZ=UTC)
  /// 는 `new Date(...)` 로 offset 없는 문자열을 **런타임 local = UTC** 로
  /// 해석하므로, KST 사용자의 동의 시각이 9시간 미래로 기록된다.
  ///
  /// 따라서 직렬화 시점에 [DateTime.toUtc] 로 정규화해 항상 `Z` 접미
  /// (절대 instant) 문자열을 전송한다. 이 정규화로 Custom Token 경로와
  /// [mirrorToFirestore] (`Timestamp.fromDate` — local `DateTime` 도 정확한
  /// instant 로 변환) 의 기준이 일치한다.
  ///
  /// 동의 기록이 없으면 `null` (payload 미부착).
  Map<String, dynamic>? get acceptanceSnapshotJson {
    // 정규화 책임은 TermsAcceptanceServerJson 확장 1곳에 모은다 (WR-05) —
    // 계약 sentinel 테스트가 같은 메서드를 통과해야 fixture drift 가 없다.
    return _acceptance?.toServerJson();
  }

  /// 가장 최근 [reloadForUser] 가 로드한 uid 를 보관한다 (Issue #7 C-1 —
  /// Plan 10-11 stale 가드).
  ///
  /// `resolveAuthRedirect` 분기 (5) 는 본 값이 `currentUser.uid` 와 일치하는 경우에만
  /// [state] 를 신뢰한다. UID 는 일치하지만 reload 가 아직 완료되지 않은
  /// 시점의 stale 평가를 차단하여 오진 리다이렉트(/onboarding flash) 를
  /// 방지한다. null 은 "한 번도 reload 된 적 없음" (cold-start) 또는
  /// "직전에 uid=null 로 reload 되어 logout 상태" 를 의미한다.
  String? _lastReloadedUid;

  /// [_lastReloadedUid] 의 읽기 전용 접근자 (Issue #7 C-1 — Plan 10-11
  /// resolveAuthRedirect stale 가드 용).
  String? get lastReloadedUid => _lastReloadedUid;

  @override
  TermsAcceptance? build() {
    // CR-01 (Plan 10-09 review fix): build() 에서 prefs 를 미리 로드하지 않는다.
    // authUserObserver 의 reloadForUser 가 모든 초기 로드를 책임지므로
    // _loadFromPrefs (fire-and-forget) 와 reloadForUser 의 비동기 race 로 인해
    // stale device-local JSON 이 Firestore 결과를 덮어쓰는 시나리오를 원천 차단.
    return null;
  }

  /// SharedPreferences 에서 전체 JSON 을 복원한다 (WARNING #16).
  ///
  /// **본 메서드는 익명 사용자 또는 Firestore 실패 시 fallback 으로만
  /// 사용된다 (Issue #6 — Plan 10-09).** 정식 사용자의 권위 source 는
  /// Firestore `users/{uid}/termsAccepted` 이다 ([_loadFromFirestore]).
  ///
  /// 우선순위:
  /// 1. [_key] JSON 문자열 → [TermsAcceptance.fromJson] 으로 정확 복원.
  /// 2. 구 [_legacyVersionKey] int 키 → 최소 정보만 복원 (marketing=false,
  ///    acceptedAt=epoch 보수 복원). 이 경로는 이전 릴리스 호환 목적.
  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedJson = prefs.getString(_key);
      if (savedJson != null && savedJson.isNotEmpty) {
        final map = jsonDecode(savedJson) as Map<String, dynamic>;
        final restored = TermsAcceptance.fromJson(map);
        if (!ref.mounted) return;
        if (restored.version >= currentVersion) {
          _acceptance = restored;
          state = restored;
        }
        return;
      }

      // Legacy migration: 구 int 버전 키만 있으면 최소 정보로 복원.
      final legacyVersion = prefs.getInt(_legacyVersionKey);
      if (legacyVersion != null && legacyVersion >= currentVersion) {
        final legacyRestored = TermsAcceptance(
          version: legacyVersion,
          service: true,
          privacy: true,
          marketing: false,
          acceptedAt: DateTime.fromMillisecondsSinceEpoch(0),
        );
        if (!ref.mounted) return;
        _acceptance = legacyRestored;
        state = legacyRestored;
      }
    } on Exception catch (e, st) {
      await ref
          .read(crashlyticsServiceProvider)
          .recordError(e, st, reason: 'terms_load');
    }
  }

  /// 약관 동의를 수락한다 (D-15, D-17).
  ///
  /// 필수 2개([service], [privacy]) 중 하나라도 false 이면
  /// [Result.failure]([ServiceUnavailable]) 반환 — state 변경 없음.
  /// 필수 2개가 true 이면 [TermsAcceptance] 를 생성해 state 갱신 +
  /// SharedPreferences 에 전체 JSON 을 저장한다.
  Future<Result<void>> accept({
    required bool service,
    required bool privacy,
    required bool marketing,
  }) async {
    if (!service || !privacy) {
      return const Result.failure(ServiceUnavailable());
    }
    final acceptance = TermsAcceptance(
      version: currentVersion,
      service: service,
      privacy: privacy,
      marketing: marketing,
      acceptedAt: DateTime.now(),
    );
    _acceptance = acceptance;
    state = acceptance;
    try {
      final prefs = await SharedPreferences.getInstance();
      // WARNING #16: 전체 JSON 문자열 저장.
      await prefs.setString(_key, jsonEncode(acceptance.toJson()));
      // 구 키는 호환성을 위해 유지 (legacy 코드가 있는 경우 대비).
      await prefs.setInt(_legacyVersionKey, currentVersion);
      return const Result.success(null);
    } on Exception catch (e, st) {
      await ref
          .read(crashlyticsServiceProvider)
          .recordError(e, st, reason: 'terms_save');
      return Result.failure(ServiceUnavailable(cause: e));
    }
  }

  /// Firestore `users/{uid}/termsAccepted` 를 읽어 state + [_acceptance] 를
  /// 갱신한다 (Issue #6 — D-15 1회 동의 invariant 를 사용자 단위로 평가).
  ///
  /// **호출자 책임:** [uid] 는 반드시 정식(비익명) 사용자 UID 여야 한다.
  /// 익명 사용자는 본 메서드 호출 대신 [_loadFromPrefs] 로 device-local
  /// 동의를 사용한다. 라우팅은 [reloadForUser] 가 담당한다.
  ///
  /// **에러 처리:**
  /// - Firestore 에서 문서/필드가 없거나 currentVersion 미달이면 state=null 로
  ///   초기화한다 (재동의 강제, resolveAuthRedirect 분기 (5) 발동).
  /// - [FirebaseException] (네트워크/권한) 발생 시 SharedPreferences 로
  ///   fallback 한 후 Crashlytics 에 reason='terms_load_firestore' 로
  ///   기록한다.
  Future<void> _loadFromFirestore({required String uid}) async {
    try {
      final firestore = ref.read(firebaseFirestoreProvider);
      final snapshot = await firestore.collection('users').doc(uid).get();
      if (!snapshot.exists) {
        if (!ref.mounted) return;
        _acceptance = null;
        state = null;
        return;
      }
      final data = snapshot.data();
      final terms = data?['termsAccepted'] as Map<String, dynamic>?;
      if (terms == null) {
        if (!ref.mounted) return;
        _acceptance = null;
        state = null;
        return;
      }
      final restored = TermsAcceptance(
        version: (terms['version'] as num?)?.toInt() ?? 0,
        service: terms['service'] as bool? ?? false,
        privacy: terms['privacy'] as bool? ?? false,
        marketing: terms['marketing'] as bool? ?? false,
        // Timestamp ↔ DateTime 역변환 ([mirrorToFirestore] 의 Timestamp.fromDate
        // 와 대칭). 누락 시 epoch 보수값.
        acceptedAt:
            (terms['acceptedAt'] as Timestamp?)?.toDate() ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
      if (!ref.mounted) return;
      if (restored.version >= currentVersion) {
        _acceptance = restored;
        state = restored;
      } else {
        // currentVersion 미달 — 재동의 강제 (분기 (5) 발동).
        _acceptance = null;
        state = null;
      }
    } on FirebaseException catch (e, st) {
      await ref
          .read(crashlyticsServiceProvider)
          .recordError(e, st, reason: 'terms_load_firestore');
      // 네트워크/권한 실패 시 SharedPreferences fallback (오프라인 대응).
      await _loadFromPrefs();
    } on Object catch (e, st) {
      await ref
          .read(crashlyticsServiceProvider)
          .recordError(e, st, reason: 'terms_load_firestore_other');
      await _loadFromPrefs();
    }
  }

  /// 정식 사용자 UID 변경 시 호출되는 public reload entry point
  /// (Issue #6 — Plan 10-09).
  ///
  /// [uid] 가 null 이면 state=null + SharedPreferences 동기 삭제 (CR-02
  /// review fix — 직전 사용자 데이터의 익명/차후 사용자 교차 누출 차단).
  /// [isAnonymous] true 면 SharedPreferences 우선 ([_loadFromPrefs]). 정식
  /// 사용자 UID 면 [_loadFromFirestore] 호출.
  ///
  /// authUserObserver (Plan 10-09 Task 3) 에서 UID 변경 감지 시 호출한다.
  Future<void> reloadForUser({String? uid, bool isAnonymous = false}) async {
    if (uid == null) {
      // 로그아웃 등 — state + device-local 모두 초기화하여 다음 익명/차후
      // 사용자 진입 시 직전 정식 사용자 동의가 승계되지 않도록 차단 (CR-02).
      if (!ref.mounted) return;
      _acceptance = null;
      state = null;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_key);
        await prefs.remove(_legacyVersionKey);
      } on Exception catch (e, st) {
        await ref
            .read(crashlyticsServiceProvider)
            .recordError(e, st, reason: 'terms_logout_prefs_clear');
      }
      if (!ref.mounted) return;
      // Issue #7 C-1 (Plan 10-11): uid=null 분기도 lastReloadedUid 를 명시
      // null 로 기록 — resolveAuthRedirect 는 분기 (5) 를 !isAnonymous 가드 하에
      // 실행하므로 본 분기 갱신은 향후 정식 사용자 전이의 stale 가드 기준선을
      // 제공한다.
      _lastReloadedUid = null;
      return;
    }
    if (isAnonymous) {
      // 익명 사용자 — device-local 우선 (기존 동작 유지).
      // null uid 경로에서 prefs 가 이미 clear 되었으므로 stale 데이터 위험 없음.
      await _loadFromPrefs();
      if (!ref.mounted) return;
      // Issue #7 C-1 (Plan 10-11): 익명 uid 도 lastReloadedUid 에 기록하여
      // resolveAuthRedirect 분기 (5) stale 가드가 정식 전이 시점에 올바른 비교를
      // 수행하도록 한다.
      _lastReloadedUid = uid;
      return;
    }
    await _loadFromFirestore(uid: uid);
    if (!ref.mounted) return;
    // Issue #7 C-1 (Plan 10-11): Firestore read 성공/실패 (fallback 포함)
    // 여부와 무관하게 uid 를 기록한다 — stale 가드의 기준은 "reload 가 이
    // uid 에 대해 완료되었는가" 이지 "state 가 정상 값인가" 가 아니다.
    _lastReloadedUid = uid;
  }

  /// 약관 동의 내역을 Firestore 에 미러링한다 (D-16).
  ///
  /// 호출자 책임: [uid] 는 반드시 **정식 (비익명) 사용자 UID** 여야 한다.
  /// 익명 UID 에 쓰기는 고아 문서를 생성하므로 금지 (Pitfall 2).
  /// Plan 05 `authUserObserver` 가 익명 → 정식 전이 감지 시점에 호출한다.
  ///
  /// state=null 은 `accept()` 미호출 또는 logout 직후 (CR-02 prefs clear) 를
  /// 의미하며 mirror 대상 부재 — Issue #7 D-1 (Plan 10-11) 에서 에러가 아닌
  /// no-op 성공으로 전환하여 mirror→reload 직렬화 체인 붕괴 및 로그 노이즈를
  /// 제거한다.
  ///
  /// **Issue #8 (Plan 10-12 — multi-user invariant):** `users/{uid}` 문서가
  /// 이미 Firestore 에 존재하는 경우 mirror 를 skip (no-op 성공 반환) 한다.
  /// device-local 익명 사용자의 동의값이 기존 정식 사용자 A 의 문서에 덮어
  /// 씌워지는 multi-user device invariant 위반을 차단한다. 문서 미존재
  /// (snapshot.exists=false) 인 경우에만 기존 set(merge: true) 로 write 하여
  /// BLOCKER #4 (익명 → 정식 승격 시 약관 동의 보존) 를 유지한다.
  /// skip 사유는 Crashlytics setCustomKey('mirror_skip_reason', ...) 로 추적.
  ///
  /// **revision W-1 scope note:** "문서 존재 + termsAccepted 필드 존재 +
  /// version < currentVersion" 케이스 (버전 bump 후 재동의 유도) 는 본 Plan
  /// 의 mirror 경로가 아닌 accept() flow 에서 처리한다. mirror 는 익명→정식
  /// 전이 시점에만 authUserObserver 가 호출하며, version bump 는 앱 업데이트
  /// 후 사용자가 명시적으로 재동의할 때 accept → mirror 경로로 새 Timestamp
  /// 가 기록된다. 이 경우 문서는 존재하지만 "기존 사용자" 의 Firestore 상태
  /// 자체를 보존하는 것이 multi-user invariant 의 의도이므로 skip 은 일관됨.
  /// 재동의 강제는 [_loadFromFirestore] 의 version 비교 로직이 담당한다.
  ///
  /// **G-16-A9-1 재검토 결론 (Phase 16 Plan 16-14 — 완화 반려):** gap 은 skip
  /// 조건을 `snapshot.exists` 대신
  /// `!snapshot.exists || snapshot.data()?['termsAccepted'] == null` 로
  /// 완화해 Cloud Function 이 방금 만든 문서를 "기존 사용자" 로 오인하는
  /// 경합을 해소할지 검토를 요구했다. 결론은 **완화하지 않음**이며 근거는
  /// 세 가지다:
  ///
  /// 1. `terms_notifier_firestore_test.dart` **Test 8** 이 "정식 사용자 A
  ///    문서 존재 + `termsAccepted` 필드 부재" 상태에서 익명 B 의
  ///    device-local 동의가 mirror 되지 **않아야** 한다고 단언한다 (Plan
  ///    10-12 Issue #8, UAT Test 21 재현). 제안된 완화 조건은 정확히 이
  ///    케이스를 write 로 바꾸므로 기존 multi-user invariant 를 되돌린다.
  /// 2. client 는 mirror 시점에 "이 문서가 Cloud Function 이 방금 만든
  ///    것인지" 와 "기존 사용자 A 의 문서인지" 를 구분할 정보가 없다. 두
  ///    경우 모두 익명→정식 전이이며 문서에 `termsAccepted` 가 없다.
  /// 3. 경합 자체는 상류에서 해소된다 —
  ///    `AuthRepository._buildCustomTokenPayload` 가 4 Custom Token callable
  ///    payload 에 `termsAcceptanceSnapshot` 을 동봉하고, 서버가 identity 를
  ///    만드는 같은 write 안에서 `termsAccepted` 를 기록한다. client mirror
  ///    가 skip 해도 서버 기록이 남는다. 그 write 의 주체는 유효한 IdP
  ///    토큰으로 identity 소유를 서버에 증명한 caller 이므로, Plan 10-12 가
  ///    막으려던 "인증하지 않은 제3자 문서에 device-local 값이 착지" 와는
  ///    위험 계열이 다르다.
  ///
  /// **잔여 위험:** 상류 경로를 잃으면 (예: Custom Token payload 전송 실패)
  /// 서버 동의 기록이 비게 된다 — client mirror 는 이 경우에도 skip 한다.
  ///
  /// **lock 표기:** 후속 phase 가 skip 조건을 바꾸려면 Test 8 (필드 부재)
  /// 과 Test 9 (필드 존재) 를 먼저 갱신해야 한다.
  ///
  /// **Issue #9 (Plan 10-13 — 재동의 경로):** [force] 가 true 이면 pre-read 를
  /// 건너뛰고 무조건 set(merge:true) 를 수행한다. `OnboardingScreen._handleCta`
  /// 의 재동의 경로(정식 사용자 A 로그인 상태에서 CTA 탭) 에서만 사용되며,
  /// 사용자가 **명시적으로 재동의** 한 의도를 Plan 10-12 skip 정책보다 우선시한다.
  /// authUserObserver 의 자동 mirror 호출은 [force] 기본값 false 를 유지하여
  /// multi-user invariant 방어를 보존한다.
  ///
  /// FirebaseException / 기타 예외는 Crashlytics 기록 후
  /// [ServiceUnavailable] 로 래핑한다.
  Future<Result<void>> mirrorToFirestore({
    required String uid,
    bool force = false,
  }) async {
    final acceptance = _acceptance;
    if (acceptance == null) {
      // Issue #7 D-1 (Plan 10-11): state=null 은 mirror 대상 부재 — no-op 성공.
      return const Result.success(null);
    }
    try {
      final firestore = ref.read(firebaseFirestoreProvider);
      final doc = firestore.collection('users').doc(uid);
      // Issue #9 (Plan 10-13): 사용자 명시적 재동의(onboarding CTA 재동의 경로)
      // 에서만 force=true 로 호출되어 Plan 10-12 pre-read+skip 정책을 우회한다.
      // 자동 경로(authUserObserver 익명→정식 전이) 는 force=false 기본값 유지.
      if (!force) {
        // Issue #8 (Plan 10-12): pre-read 로 기존 문서 여부 확인 — multi-user
        // invariant. 문서 존재 시 skip 하여 cross-user overwrite 차단.
        final snapshot = await doc.get();
        if (snapshot.exists) {
          await ref
              .read(crashlyticsServiceProvider)
              .setCustomKey('mirror_skip_reason', 'existing_user_doc');
          return const Result.success(null);
        }
      }
      await doc.set(<String, dynamic>{
        'termsAccepted': <String, dynamic>{
          'version': acceptance.version,
          'service': acceptance.service,
          'privacy': acceptance.privacy,
          'marketing': acceptance.marketing,
          'acceptedAt': Timestamp.fromDate(acceptance.acceptedAt),
        },
      }, SetOptions(merge: true));
      return const Result.success(null);
    } on FirebaseException catch (e, st) {
      await ref
          .read(crashlyticsServiceProvider)
          .recordError(e, st, reason: 'terms_mirror_firestore');
      return Result.failure(ServiceUnavailable(cause: e));
    } on Object catch (e, st) {
      await ref
          .read(crashlyticsServiceProvider)
          .recordError(e, st, reason: 'terms_mirror_other');
      return Result.failure(ServiceUnavailable(cause: e));
    }
  }

  /// 약관 상태를 초기화한다 (D-33 Dev Tools, WARNING #8: production 표면).
  ///
  /// Plan 04 `_DevToolsSection` 과 테스트 모두 본 메서드를 직접 호출한다.
  /// `@visibleForTesting` 어노테이션은 부여하지 않는다.
  Future<void> reset() async {
    _acceptance = null;
    state = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
      await prefs.remove(_legacyVersionKey);
    } on Exception catch (e, st) {
      await ref
          .read(crashlyticsServiceProvider)
          .recordError(e, st, reason: 'terms_reset');
    }
  }
}
