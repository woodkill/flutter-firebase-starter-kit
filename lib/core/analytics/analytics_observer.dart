import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_analytics/observer.dart';
import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../providers/firebase_providers.dart';

part 'analytics_observer.g.dart';

/// Firebase 미초기화 시 Observer 등록을 스킵하기 위한 NoOp 구현.
///
/// [NavigatorObserver] 기본 구현은 모든 라이프사이클 콜백이 비어 있으므로
/// 추가 동작 없이 그대로 사용해도 부작용이 없다.
///
/// 주의: [NavigatorObserver] 의 기본 생성자가 non-const 이므로 본 클래스도
/// const 생성자를 가질 수 없다 (`const_constructor_with_non_const_super`).
class _NoOpNavigatorObserver extends NavigatorObserver {
  _NoOpNavigatorObserver();
}

/// `GoRouter.observers` 에 주입하기 위한 [NavigatorObserver] Provider (D-29).
///
/// Firebase 미초기화 시 [_NoOpNavigatorObserver] 를 반환하여
/// Phase 1 D-13 철학 (Firebase 없이도 앱 정상 실행) 을 준수한다.
///
/// [FirebaseAnalyticsObserver] 의 `nameExtractor` 는 `settings.name` 을
/// 사용하며, 이는 [GoRoute.name] 에 매핑된다. 모든 `GoRoute` 에 `name`
/// 설정 필수 (Pitfall 1).
///
/// **screen_view 단일 발신 계약 (코드 리뷰 CR-01).**
/// [FirebaseAnalyticsObserver] 는 `didPush` 시점에만 동작하지 않는다 —
/// 패키지 소스 (`firebase_analytics/lib/observer.dart`) 기준
/// `didPush` / `didReplace` / `didPop` **3콜백 모두**가 `_sendScreenView`
/// 를 호출하므로 `go_router` 의 push / `context.go()` same-level replace /
/// pop 이 전부 커버된다.
///
/// 과거 WARNING #14 (Pitfall 1) 는 그 반대를 전제로 `appRouter` 에
/// `routerDelegate.addListener` 수동 `logScreenView` 를 덧붙였는데, 두 경로
/// 사이에 교차 dedup 이 없어 **모든 전환이 GA4 에 2회 적재**됐다. 수동
/// 경로는 제거했다 — 본 Provider 가 공급하는 observer 가 유일한 발신
/// 주체다. 소비처 화면에서 `didChangeDependencies` 등으로 추가 발신을
/// 넣으면 같은 이중 계측이 재발하므로 금지한다.
@Riverpod(keepAlive: true)
NavigatorObserver analyticsObserver(Ref ref) {
  final isInitialized = ref.watch(isFirebaseInitializedProvider);
  if (!isInitialized) {
    return _NoOpNavigatorObserver();
  }
  final analytics = ref.watch(firebaseAnalyticsProvider);
  return FirebaseAnalyticsObserver(
    analytics: analytics,
    nameExtractor: (settings) => settings.name,
  );
}
