import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../providers/firebase_providers.dart';

part 'analytics_service.g.dart';

/// GA4 이벤트명 / 사용자 속성명 규칙 (알파벳 시작, 영숫자·언더스코어, 40자
/// 이내). debug assert 전용이므로 release 빌드에서는 초기화조차 되지 않는다.
final RegExp _kGa4NamePattern = RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{0,39}$');

/// Firebase Analytics 를 감싸는 서비스 래퍼 (Phase 10 D-29, D-30).
///
/// **실패 격리 계약 (코드 리뷰 WR-01).** 본 래퍼의 모든 메서드는
/// **호출자에게 예외를 던지지 않는다.** 두 층으로 보장한다.
/// 1. Firebase 미초기화 환경([isEnabled]=false) 에서는 네이티브 호출 자체를
///    하지 않고 즉시 반환한다 (Phase 1 D-13).
/// 2. 초기화 이후의 호출 실패 — 예약 이벤트명 / `firebase_` prefix /
///    사용자 속성 이름 규칙 위반 시 `firebase_analytics` 가 실제로 던지는
///    [ArgumentError], 네이티브 채널 [PlatformException] 등 — 도 래퍼
///    내부에서 흡수하고 debug 로그만 남긴다.
///
/// 수정 전에는 (2) 가 없어 텔레메트리 한 번의 실패가 사용자 플로우를 끊었다
/// (온보딩 완료 경로의 영구 정지, `auth_guard` 의 `await for` 스트림 영구
/// 종료). telemetry 는 실패해도 앱이 계속 돌아야 하는 best-effort 계층이므로
/// 격리 책임을 호출자 N곳이 아니라 래퍼 1곳에 둔다.
///
/// **타입 계약 (코드 리뷰 WR-02).** GA4 파라미터 값은 [String] 또는 [num] 만
/// 허용된다. `firebase_analytics` 의 검사는 `assert` 뿐이라 release 에서는
/// 네이티브로 그대로 내려가 **조용히 누락**되므로, 본 래퍼가 같은 규칙을
/// 진입점에서 다시 assert 하여 debug 에서 원인이 드러나게 한다.
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
  Future<void> setGuestMode(bool isAnonymous) {
    final client = _analytics;
    if (!isEnabled || client == null) return Future<void>.value();
    return _runBestEffort(
      'setUserProperty(guest_mode)',
      () => client.setUserProperty(
        name: 'guest_mode',
        value: isAnonymous ? 'true' : 'false',
      ),
    );
  }

  /// 사용자 ID 를 Analytics 에 태깅한다.
  ///
  /// [uid] 는 Firebase UID (익명 또는 정식) 만 허용한다.
  Future<void> setUserId(String? uid) {
    final client = _analytics;
    if (!isEnabled || client == null) return Future<void>.value();
    return _runBestEffort('setUserId', () => client.setUserId(id: uid));
  }

  /// 커스텀 이벤트를 기록한다.
  ///
  /// [parameters] 에 PII 를 포함하지 않도록 호출부에서 주의한다.
  ///
  /// **[name] (WR-02):** GA4 규칙상 알파벳으로 시작하고 영숫자·언더스코어만
  /// 40자 이내여야 한다. 규칙 위반 이름은 GA4 가 조용히 버리므로 debug
  /// assert 로 드러낸다. 예약 이벤트명 (`app_open`, `session_start` 등) 과
  /// `firebase_` prefix 는 `firebase_analytics` 가 [ArgumentError] 를 던지며,
  /// 그 예외는 WR-01 격리로 흡수되고 debug 로그에만 남는다.
  ///
  /// **[parameters] 값 (WR-02):** [String] 또는 [num] 만 허용한다. `bool` 은
  /// `'true'` / `'false'` 문자열로 변환해 전달할 것 — 그대로 넘기면 debug
  /// 에서는 플랫폼 assert 로 죽고 release 에서는 조용히 누락된다.
  Future<void> logEvent(String name, {Map<String, Object>? parameters}) {
    assert(
      _kGa4NamePattern.hasMatch(name),
      'GA4 이벤트명 규칙 위반: "$name" (알파벳 시작, 영숫자/_ 40자 이내).',
    );
    assert(
      parameters?.values.every((v) => v is String || v is num) ?? true,
      'GA4 파라미터 값은 String 또는 num 만 허용된다 (bool 은 문자열로 변환할 것): '
      '$parameters',
    );
    final client = _analytics;
    if (!isEnabled || client == null) return Future<void>.value();
    return _runBestEffort(
      'logEvent($name)',
      () => client.logEvent(name: name, parameters: parameters),
    );
  }

  /// 화면 전환 이벤트를 기록한다.
  ///
  /// **라우팅 전환에는 호출하지 않는다 (코드 리뷰 CR-01).** `GoRouter` 의
  /// 화면 전환 계측은 `analyticsObserverProvider` 의
  /// `FirebaseAnalyticsObserver` 가 단독으로 담당한다 (push/replace/pop
  /// 3콜백 모두 커버). 여기에 수동 호출을 겹치면 같은 전환이 GA4 에 2회
  /// 적재된다.
  ///
  /// 본 메서드는 `GoRouter` 바깥의 화면 표면 — 예컨대 라우트를 만들지 않는
  /// 전체화면 모달 / `PageView` 탭 / 커스텀 오버레이 — 을 하나의 "화면"
  /// 으로 계측하고 싶은 fork 사용자를 위한 진입점으로 남겨 둔다.
  Future<void> logScreenView({
    required String screenName,
    String? screenClass,
  }) {
    final client = _analytics;
    if (!isEnabled || client == null) return Future<void>.value();
    return _runBestEffort(
      'logScreenView($screenName)',
      () => client.logScreenView(
        screenName: screenName,
        screenClass: screenClass,
      ),
    );
  }

  /// best-effort 텔레메트리 호출을 실행하고 모든 실패를 흡수한다 (WR-01).
  ///
  /// [label] 은 debug 로그에 남길 호출 식별자다. 실패를 Analytics 로 보고할
  /// 수는 없으므로 (같은 채널이 이미 실패한 상태) `kDebugMode` 로그가 유일한
  /// 관측 채널이다.
  Future<void> _runBestEffort(
    String label,
    Future<void> Function() call,
  ) async {
    try {
      await call();
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('analytics $label failed: $e\n$st');
      }
    }
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
