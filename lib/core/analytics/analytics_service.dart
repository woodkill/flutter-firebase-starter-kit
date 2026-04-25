import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../providers/firebase_providers.dart';

part 'analytics_service.g.dart';

/// Firebase Analytics 를 감싸는 서비스 래퍼 (Phase 10 D-29, D-30).
///
/// Firebase 미초기화 환경([isEnabled]=false) 에서는 모든 메서드가 no-op 으로
/// 동작하여 Phase 1 D-13 철학을 준수한다.
///
/// PII 보호 (T-10-02): [setUserId] 는 Firebase UID 만 허용하고,
/// [logEvent] 파라미터에도 이메일/이름 등 개인 식별 정보를 전달하지 않는다.
class AnalyticsService {
  /// [AnalyticsService] 를 생성한다.
  const AnalyticsService(this._analytics, {required this.isEnabled});

  final FirebaseAnalytics? _analytics;

  /// Firebase 초기화 상태. false 이면 모든 메서드가 no-op 이다.
  final bool isEnabled;

  /// 게스트 모드 사용자 속성 태깅 (Phase 10 D-30).
  ///
  /// 이름은 snake_case `'guest_mode'` 고정 (GA4 규칙).
  /// Firebase Console 의 custom definitions 에 사전 등록 권장.
  Future<void> setGuestMode(bool isAnonymous) async {
    final client = _analytics;
    if (!isEnabled || client == null) return;
    await client.setUserProperty(
      name: 'guest_mode',
      value: isAnonymous ? 'true' : 'false',
    );
  }

  /// 사용자 ID 를 Analytics 에 태깅한다.
  ///
  /// [uid] 는 Firebase UID (익명 또는 정식) 만 허용한다.
  Future<void> setUserId(String? uid) async {
    final client = _analytics;
    if (!isEnabled || client == null) return;
    await client.setUserId(id: uid);
  }

  /// 커스텀 이벤트를 기록한다.
  ///
  /// [parameters] 에 PII 를 포함하지 않도록 호출부에서 주의한다.
  Future<void> logEvent(String name, {Map<String, Object>? parameters}) async {
    final client = _analytics;
    if (!isEnabled || client == null) return;
    await client.logEvent(name: name, parameters: parameters);
  }

  /// 화면 전환 이벤트를 기록한다 (D-29 Pitfall 1 대응 보조).
  ///
  /// `FirebaseAnalyticsObserver` 가 누락하는 go_router same-level 전환을
  /// 수동 보완하기 위해 presentation 계층에서 직접 호출한다.
  Future<void> logScreenView({
    required String screenName,
    String? screenClass,
  }) async {
    final client = _analytics;
    if (!isEnabled || client == null) return;
    await client.logScreenView(
      screenName: screenName,
      screenClass: screenClass,
    );
  }
}

/// [AnalyticsService] Provider (Phase 10 D-29).
///
/// Firebase 미초기화 시 `isEnabled=false` 로 생성되어 모든 메서드가 no-op 이다.
@Riverpod(keepAlive: true)
AnalyticsService analyticsService(Ref ref) {
  final isInitialized = ref.watch(isFirebaseInitializedProvider);
  if (!isInitialized) {
    return const AnalyticsService(null, isEnabled: false);
  }
  final analytics = ref.watch(firebaseAnalyticsProvider);
  return AnalyticsService(analytics, isEnabled: true);
}
