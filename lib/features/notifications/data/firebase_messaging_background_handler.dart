// FCM 백그라운드 · 종료 상태 메시지 핸들러 (Phase 17 D-01).
//
// 공식 규칙(firebase.google.com/docs/cloud-messaging/flutter/receive ·
// RESEARCH R-12):
// - top-level 함수여야 한다 — 익명 함수 · 초기화가 필요한 클래스 메서드 금지.
// - Flutter 3.3+ release 빌드에서 tree shaking 으로 지워지지 않도록
//   `@pragma('vm:entry-point')` 를 붙인다.
// - 앱과 다른 별도 isolate 에서 돈다 — UI · Riverpod 상태에 접근할 수 없다.
// - 30초 안에 끝나야 한다.
//
// notification 메시지(제목 · 본문이 있는 알림)는 백그라운드 · 종료 상태에서
// OS 가 manifest 기본 채널(`general`)로 이미 표시한다. 그래서 이 핸들러는 할
// 일이 없다 — 탭 이동은 앱이 다시 열릴 때 `onMessageOpenedApp` ·
// `getInitialMessage` 가 맡는다(NotificationTapHandler).
//
// **커스터마이징 포인트:** data-only 메시지로 백그라운드 작업(예: 캐시 갱신)을
// 하려면 이 함수 안에서 처리한다. 다른 Firebase 서비스를 쓰려면 먼저
// `Firebase.initializeApp()` 을 불러야 한다. 토큰 · 메시지 본문은 로그에 싣지
// 않는다.

import 'package:firebase_messaging/firebase_messaging.dart';

/// FCM 백그라운드 · 종료 상태 메시지 핸들러 — 현재 no-op (Phase 17 D-01).
///
/// `bootstrap()` 이 Firebase 초기화 분기 안 · `runApp` 앞에서
/// `FirebaseMessaging.onBackgroundMessage` 로 등록한다.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // notification 메시지는 OS 가 표시했으므로 처리할 것이 없다(위 파일 머리
  // 주석). 별도 isolate 라 앱 상태 · 화면을 건드리지 않는다.
}
