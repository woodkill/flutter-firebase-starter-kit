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

  @override
  TermsAcceptance? build() {
    _loadFromPrefs();
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
  ///   초기화한다 (재동의 강제, authRedirect 분기 (5) 발동).
  /// - [FirebaseException] (네트워크/권한) 발생 시 SharedPreferences 로
  ///   fallback 한 후 Crashlytics 에 reason='terms_load_firestore' 로
  ///   기록한다.
  Future<void> _loadFromFirestore({required String uid}) async {
    try {
      final firestore = ref.read(firebaseFirestoreProvider);
      final snapshot =
          await firestore.collection('users').doc(uid).get();
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
        acceptedAt: (terms['acceptedAt'] as Timestamp?)?.toDate() ??
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
  /// [uid] 가 null 이면 [reset] 동등 동작 (state=null + SharedPreferences 유지
  /// — 다음 익명 진입 시 device-local fallback 가능). [isAnonymous] true 면
  /// SharedPreferences 우선 ([_loadFromPrefs]). 정식 사용자 UID 면
  /// [_loadFromFirestore] 호출.
  ///
  /// authUserObserver (Plan 10-09 Task 3) 에서 UID 변경 감지 시 호출한다.
  Future<void> reloadForUser({
    String? uid,
    bool isAnonymous = false,
  }) async {
    if (uid == null) {
      // 로그아웃 등 — state 만 비워 다음 평가 시 분기 (2) /onboarding 으로 보냄.
      // SharedPreferences 키는 유지하여 익명 재진입 시 fallback 가능.
      if (!ref.mounted) return;
      _acceptance = null;
      state = null;
      return;
    }
    if (isAnonymous) {
      // 익명 사용자 — device-local 우선 (기존 동작 유지).
      await _loadFromPrefs();
      return;
    }
    await _loadFromFirestore(uid: uid);
  }

  /// 약관 동의 내역을 Firestore 에 미러링한다 (D-16).
  ///
  /// 호출자 책임: [uid] 는 반드시 **정식 (비익명) 사용자 UID** 여야 한다.
  /// 익명 UID 에 쓰기는 고아 문서를 생성하므로 금지 (Pitfall 2).
  /// Plan 05 `authUserObserver` 가 익명 → 정식 전이 감지 시점에 호출한다.
  ///
  /// state 가 null 이면 [ServiceUnavailable] 을 반환한다 (accept 미호출).
  /// FirebaseException / 기타 예외는 Crashlytics 기록 후
  /// [ServiceUnavailable] 로 래핑한다.
  Future<Result<void>> mirrorToFirestore({required String uid}) async {
    final acceptance = _acceptance;
    if (acceptance == null) {
      return const Result.failure(ServiceUnavailable());
    }
    try {
      final firestore = ref.read(firebaseFirestoreProvider);
      await firestore.collection('users').doc(uid).set(
        <String, dynamic>{
          'termsAccepted': <String, dynamic>{
            'version': acceptance.version,
            'service': acceptance.service,
            'privacy': acceptance.privacy,
            'marketing': acceptance.marketing,
            'acceptedAt': Timestamp.fromDate(acceptance.acceptedAt),
          },
        },
        SetOptions(merge: true),
      );
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
