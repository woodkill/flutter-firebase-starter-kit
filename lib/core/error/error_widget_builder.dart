import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../shared/widgets/error_fallback.dart';

/// release 깨진 화면 대체가 그려질 때 Crashlytics non-fatal 기록에 쓰는 reason.
///
/// Phase 17 — see ROADMAP.md (D-22). 고정 상수 1개만 쓴다 — 사용자 값이 reason
/// 에 섞이지 않는다 (T-17-26). framework 의 `FlutterError.reportError`(fatal
/// 경로)와 구분되는 「대체 화면이 사용자에게 보였다」 신호다.
const String kErrorWidgetBuildReason = 'error_widget_build';

/// release 빌드의 `ErrorWidget.builder` 본문 — [onBuildError] 로 [details] 를
/// 1회 넘긴 뒤 [ErrorFallback] 을 돌려준다.
///
/// Phase 17 — see ROADMAP.md (D-22). release 전용이다(debug 는 SDK 기본 빨간
/// 화면 유지 — 설치 분기는 bootstrap). 재시도 버튼은 없다 — 위젯 트리를
/// 안전하게 다시 세울 수 없다.
///
/// [onBuildError] 가 throw 해도 대체 화면은 그려진다 — builder 안의 예외는
/// 다시 `ErrorWidget` 을 부르는 연쇄 오류가 되기 때문이다 (T-17-25).
Widget buildReleaseErrorWidget(
  FlutterErrorDetails details, {
  required void Function(FlutterErrorDetails details) onBuildError,
}) {
  try {
    onBuildError(details);
  } on Object catch (e, st) {
    // 기록 실패는 화면에 영향을 주지 않는다. release 에서는 출력하지 않는다.
    if (kDebugMode) {
      debugPrint('ErrorWidget 기록 실패 (무시): $e\n$st');
    }
  }
  return const ErrorFallback();
}
