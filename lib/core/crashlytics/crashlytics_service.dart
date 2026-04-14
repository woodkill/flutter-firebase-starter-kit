import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../providers/firebase_providers.dart';

part 'crashlytics_service.g.dart';

/// Firebase Crashlytics 를 감싸는 서비스 래퍼 (Phase 10 D-28).
///
/// Firebase 미초기화 환경([isEnabled]=false) 에서는 모든 메서드가 no-op 으로
/// 동작하여 Phase 1 D-13 철학 (Firebase 없이도 앱 정상 실행) 을 준수한다.
///
/// 사용 예:
/// ```dart
/// final crashlytics = ref.read(crashlyticsServiceProvider);
/// await crashlytics.setFlavor('dev');
/// await crashlytics.recordError(error, stack, reason: 'onboarding_load');
/// ```
class CrashlyticsService {
  /// [CrashlyticsService] 를 생성한다.
  const CrashlyticsService(this._crashlytics, {required this.isEnabled});

  final FirebaseCrashlytics? _crashlytics;

  /// Firebase 초기화 상태. false 이면 모든 메서드가 no-op 이다.
  final bool isEnabled;

  /// 에러를 Crashlytics 에 기록한다 (AUTH-11).
  ///
  /// [reason] 은 코드 경로 식별자만 사용한다 (예: 'onboarding_load').
  /// PII (이메일, 비밀번호 등) 를 [reason] 이나 [error] 에 포함하지 않는다.
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  }) async {
    final client = _crashlytics;
    if (!isEnabled || client == null) return;
    await client.recordError(
      error,
      stack,
      reason: reason,
      fatal: fatal,
    );
  }

  /// 사용자 ID 를 Crashlytics 리포트에 태깅한다.
  ///
  /// [uid] 가 null 이면 빈 문자열 ('') 로 clear 한다.
  /// Firebase UID 만 허용 — 이메일/이름 등 PII 금지.
  Future<void> setUserId(String? uid) async {
    final client = _crashlytics;
    if (!isEnabled || client == null) return;
    await client.setUserIdentifier(uid ?? '');
  }

  /// 커스텀 키/값을 태깅한다 (디버깅 맥락 정보).
  Future<void> setCustomKey(String key, Object value) async {
    final client = _crashlytics;
    if (!isEnabled || client == null) return;
    await client.setCustomKey(key, value);
  }

  /// Flavor (dev/stg/prod) 정보를 태깅한다 — AUTH-11 요구사항.
  Future<void> setFlavor(String flavor) => setCustomKey('flavor', flavor);
}

/// [CrashlyticsService] Provider (Phase 10 D-28).
///
/// Firebase 미초기화 시 `isEnabled=false` 로 생성되어 모든 메서드가 no-op 이다.
@Riverpod(keepAlive: true)
CrashlyticsService crashlyticsService(Ref ref) {
  final isInitialized = ref.watch(isFirebaseInitializedProvider);
  if (!isInitialized) {
    return const CrashlyticsService(null, isEnabled: false);
  }
  final crashlytics = ref.watch(firebaseCrashlyticsProvider);
  return CrashlyticsService(crashlytics, isEnabled: true);
}
