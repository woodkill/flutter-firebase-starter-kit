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
/// 이중 저장 전략 (D-16):
/// - SharedPreferences `terms.accepted_value` : 전체 [TermsAcceptance] JSON
///   문자열 (WARNING #16). 오프라인/cold-start 시에도 정확한 데이터 복원.
/// - Firestore `users/{uid}/termsAccepted` : 정식 로그인 후 호출자(Plan 05
///   `authUserObserver`)가 익명 → 정식 전이 시점에만 호출 (Pitfall 2,
///   BLOCKER #4). 본 Notifier 는 호출자 가드를 신뢰한다.
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
