import 'package:flutter/material.dart';

import '../../core/error/app_exception.dart';
import '../../core/l10n/exception_l10n.dart';

/// [exception] 의 사용자 문구를 SnackBar 로 띄운다 (Phase 17 D-21).
///
/// 화면 내 고정 위치가 없는 일시 오류 전용이다 — 고정 위치가 있으면
/// `ErrorBanner` 를 쓴다. 다이얼로그는 파괴적 확인 전용으로 유지한다.
///
/// - 직전 SnackBar 를 먼저 닫아 연속 호출 시 마지막 1개만 남긴다.
/// - 문구는 [resolveExceptionMessage] 강제 경유 — 예외 내부 상세 · 서버
///   message 를 화면에 그리지 않는다.
/// - style · duration · 줄 수는 SDK 기본 (긴 문구는 잘리지 않고 높이가
///   늘어난다). 액션 버튼 없음.
/// - [behavior] 를 넘기면 그대로 전달한다 (예: Dev Tools 의 floating).
void showErrorSnackBar(
  BuildContext context,
  AppException exception, {
  SnackBarBehavior? behavior,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(resolveExceptionMessage(context, exception)),
        behavior: behavior,
      ),
    );
}
