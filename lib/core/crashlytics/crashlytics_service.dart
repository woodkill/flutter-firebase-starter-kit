import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../providers/firebase_providers.dart';

part 'crashlytics_service.g.dart';

/// Firebase Crashlytics 를 감싸는 서비스 래퍼 (Phase 10 D-28).
///
/// **실패 격리 계약 (코드 리뷰 WR-01).** 본 래퍼의 모든 메서드는 **호출자에게
/// 예외를 던지지 않는다.** 두 층으로 보장한다.
/// 1. Firebase 미초기화 환경([isEnabled]=false) 에서는 네이티브 호출 자체를
///    하지 않고 즉시 반환한다 (Phase 1 D-13 — Firebase 없이도 앱 정상 실행).
/// 2. 초기화 이후의 호출 실패 (네이티브 채널 [PlatformException] 등) 도 래퍼
///    내부에서 흡수하고 debug 로그만 남긴다.
///
/// 수정 전에는 (2) 가 없어 에러 리포팅 실패가 원래 진단하려던 예외를 대체하고
/// (`locale_provider` / `theme_provider` 의 catch 블록), `auth_guard` 의
/// `await for` 스트림을 영구 종료시켰다. Crashlytics 실패를 Crashlytics 로
/// 보고할 수는 없으므로 `kDebugMode` 로그가 유일한 관측 채널이다.
///
/// **타입 계약 (코드 리뷰 WR-02).** [setCustomKey] 의 값은 네이티브 계약상
/// [String] / [num] / [bool] 만 허용된다 — [_assertSupportedCustomKeyValue]
/// 참조.
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
  }) {
    final client = _crashlytics;
    if (!isEnabled || client == null) return Future<void>.value();
    return _runBestEffort(
      'recordError(${reason ?? '-'})',
      () => client.recordError(error, stack, reason: reason, fatal: fatal),
    );
  }

  /// 사용자 ID 를 Crashlytics 리포트에 태깅한다.
  ///
  /// [uid] 가 null 이면 빈 문자열 ('') 로 clear 한다.
  /// Firebase UID 만 허용 — 이메일/이름 등 PII 금지.
  Future<void> setUserId(String? uid) {
    final client = _crashlytics;
    if (!isEnabled || client == null) return Future<void>.value();
    return _runBestEffort(
      'setUserIdentifier',
      () => client.setUserIdentifier(uid ?? ''),
    );
  }

  /// 커스텀 키/값을 태깅한다 (디버깅 맥락 정보).
  ///
  /// **[value] 허용 타입 (WR-02):** [String] / [num] / [bool] 만 네이티브
  /// Crashlytics 가 받는다. 그 외 타입은 debug 에서 assert 로 드러내고,
  /// release 에서는 네이티브가 조용히 무시하거나 `toString()` 으로 강등한다.
  /// 임의 객체를 넘기면 [Object.toString] 이 호출되어 **PII 가 리포트로 새어
  /// 나갈 수 있으므로** 호출부에서 필요한 필드만 골라 넘긴다.
  Future<void> setCustomKey(String key, Object value) {
    _assertSupportedCustomKeyValue(key, value);
    final client = _crashlytics;
    if (!isEnabled || client == null) return Future<void>.value();
    return _runBestEffort(
      'setCustomKey($key)',
      () => client.setCustomKey(key, value),
    );
  }

  /// Flavor (dev/stg/prod) 정보를 태깅한다 — AUTH-11 요구사항.
  Future<void> setFlavor(String flavor) => setCustomKey('flavor', flavor);

  /// [setCustomKey] 의 값 타입이 네이티브 계약에 맞는지 debug 에서 검사한다.
  void _assertSupportedCustomKeyValue(String key, Object value) {
    assert(
      value is String || value is num || value is bool,
      'Crashlytics setCustomKey("$key") 값은 String / num / bool 만 허용된다 '
      '(주입 타입: ${value.runtimeType}). 임의 객체는 toString() 으로 강등되어 '
      'PII 유출 경로가 된다.',
    );
  }

  /// best-effort 텔레메트리 호출을 실행하고 모든 실패를 흡수한다 (WR-01).
  ///
  /// [label] 은 debug 로그에 남길 호출 식별자다. Crashlytics 실패를
  /// Crashlytics 로 보고할 수는 없으므로 `kDebugMode` 로그가 유일한 채널이다.
  Future<void> _runBestEffort(
    String label,
    Future<void> Function() call,
  ) async {
    try {
      await call();
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('crashlytics $label failed: $e\n$st');
      }
    }
  }
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
