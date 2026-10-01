import '../../../core/router/app_routes.dart';

/// 알림 채널 id (Phase 17 D-01 · UI-SPEC §(O)).
///
/// Android manifest 의 `default_notification_channel_id` 와 같은 값이다 —
/// 백그라운드 · 종료 상태 FCM 알림과 포그라운드 로컬 알림이 한 채널로 모여
/// 같은 모양으로 보인다. 바꾸면 manifest meta-data 도 함께 바꿔야 한다.
const String kNotificationChannelId = 'general';

/// 알림 탭으로 열 수 있는 화면 경로 허용 목록 (Phase 17 D-04).
///
/// **근거:** CONTEXT D-04 「2026-10-01 정정 (허용 목록 축소)」 사용자 결정 —
/// 원문 「AppRoutes 에 없으면 홈」 을 대체한다. 경로 상수가 있더라도 흐름
/// 진입 전용 화면(스플래시 · 온보딩 · 로그인 · 가입 · 이메일 로그인 ·
/// 비밀번호 찾기 · 이메일 인증 · 탈퇴 진행)은 앞 단계 상태 없이 열면 안 되므로
/// 목록에 넣지 않는다 — 알림 payload 는 서버(콘솔 운영자)가 보낸 값이라
/// 앱 탐색을 결정하는 신뢰 경계다(open redirect 방어).
///
/// **커스터마이징 포인트:** 알림으로 열 새 화면은 이 목록에 경로 상수 1줄을
/// 더한다. 문자열 정확 일치로만 비교한다 — query · 경로 변수는 허용하지 않는다.
const Set<String> kNotificationRoutableRoutes = {
  AppRoutes.home,
  AppRoutes.settings,
  AppRoutes.termsService,
  AppRoutes.termsPrivacy,
};

/// 알림 payload 의 route 값을 이동할 경로로 판정한다 (Phase 17 D-04).
///
/// [raw] 가 [kNotificationRoutableRoutes] 에 정확히 있는 문자열이면 그대로,
/// 그 밖(없음 · 문자열 아님 · 목록 밖 · 외부 URL)이면 홈([AppRoutes.home])을
/// 돌려준다.
String resolveNotificationRoute(Object? raw) => switch (raw) {
  final String route when kNotificationRoutableRoutes.contains(route) => route,
  _ => AppRoutes.home,
};
