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
/// **주의 (Pitfall 1, WARNING #14):** [FirebaseAnalyticsObserver] 는
/// `didPush` 시점에 동작하지만, `go_router` 의 `context.go()` same-level
/// 전환은 push 대신 replace 동작을 일으켜 observer 가 이벤트를 놓칠 수
/// 있다. 이를 보완하기 위해 Plan 05 `appRouter` 는
/// `GoRouter.routerDelegate.addListener` 로 matchedLocation 변경을 감지하여
/// `AnalyticsService.logScreenView` 를 수동 호출한다 (또는 주요 화면의
/// `didChangeDependencies` 에서 수동 호출).
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
