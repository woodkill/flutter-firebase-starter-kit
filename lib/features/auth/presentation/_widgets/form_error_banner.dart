// 폼 상단 오류 배너 — 기존 import 호환용 shim.
// 본문은 lib/shared/widgets/error_banner.dart 의 공용 ErrorBanner 로 이동했다.
import '../../../../shared/widgets/error_banner.dart';

export '../../../../shared/widgets/error_banner.dart';

/// Phase 17 D-21 — 공용 [ErrorBanner] 로 승격. 기존 import 호환용 별칭.
typedef FormErrorBanner = ErrorBanner;
