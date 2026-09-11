import 'dart:async';

import 'package:flutter_starter_kit/core/bootstrap.dart';

/// 앱 엔트리포인트.
///
/// 초기화 시퀀스는 [bootstrap] 을 참조한다. [bootstrap] 은 내부에서
/// `runZonedGuarded` 로 자체 에러 처리를 수행하고, 초기화가 실패해도
/// `runApp` 을 반드시 호출하므로 여기서는 의도적으로 fire-and-forget 한다.
void main() {
  unawaited(bootstrap());
}
